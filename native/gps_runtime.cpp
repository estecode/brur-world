#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <limits>
#include <queue>
#include <stdexcept>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

// Native gameplay routing proof over the existing BRG1 + BRS2 files.
//
// Dependencies:
// - BRG1 owns the immutable road graph and edge facts.
// - BRS2 owns the persistent road-snap spatial index.
// - No third-party runtime libraries are used.
//
// This deliberately keeps the same exact fastest-route semantics as the Python
// reference while moving the hot search loop into C++20. BCH/CH can replace the
// search topology later without changing the file ownership or Godot-facing API.

namespace {
constexpr size_t BRG_HEADER = 12;
constexpr size_t NODE_SIZE = 40;
constexpr size_t EDGE_SIZE = 34;
constexpr size_t BRS_HEADER = 20;
constexpr size_t CELL_SIZE = 16;
constexpr double EARTH_RADIUS = 6378137.0;
constexpr double PI = 3.14159265358979323846;

struct MappedFile {
    int fd = -1;
    size_t size = 0;
    const uint8_t *data = nullptr;

    explicit MappedFile(const std::string &path) {
        fd = open(path.c_str(), O_RDONLY);
        if (fd < 0) throw std::runtime_error("open failed: " + path);
        struct stat st {};
        if (fstat(fd, &st) != 0) {
            close(fd);
            throw std::runtime_error("stat failed: " + path);
        }
        size = static_cast<size_t>(st.st_size);
        data = static_cast<const uint8_t *>(mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0));
        if (data == MAP_FAILED) {
            data = nullptr;
            close(fd);
            fd = -1;
            throw std::runtime_error("mmap failed: " + path);
        }
    }

    ~MappedFile() {
        if (data) munmap(const_cast<uint8_t *>(data), size);
        if (fd >= 0) close(fd);
    }
};

template <class T>
T read_value(const uint8_t *pointer) {
    T value;
    std::memcpy(&value, pointer, sizeof(T));
    return value;
}

struct Node {
    double lon;
    double lat;
    float x;
    float y;
    uint32_t adjacency_offset;
    uint32_t adjacency_count;
};

struct Edge {
    int64_t way_id;
    uint32_t segment_index;
    uint32_t source;
    uint32_t target;
    float length_m;
    float speed_kmh;
    uint8_t road_class;
    uint8_t access_class;
    uint8_t flags;
};

struct Graph {
    MappedFile file;
    uint32_t node_count = 0;
    uint32_t edge_count = 0;
    size_t edge_table_offset = 0;

    explicit Graph(const std::string &path) : file(path) {
        if (file.size < BRG_HEADER || std::memcmp(file.data, "BRG1", 4) != 0)
            throw std::runtime_error("bad BRG1 file");
        node_count = read_value<uint32_t>(file.data + 4);
        edge_count = read_value<uint32_t>(file.data + 8);
        edge_table_offset = BRG_HEADER + static_cast<size_t>(node_count) * NODE_SIZE;
        if (edge_table_offset + static_cast<size_t>(edge_count) * EDGE_SIZE != file.size)
            throw std::runtime_error("BRG1 size mismatch");
    }

    Node node(uint32_t index) const {
        const uint8_t *p = file.data + BRG_HEADER + static_cast<size_t>(index) * NODE_SIZE;
        return {
            read_value<double>(p + 8), read_value<double>(p + 16),
            read_value<float>(p + 24), read_value<float>(p + 28),
            read_value<uint32_t>(p + 32), read_value<uint32_t>(p + 36),
        };
    }

    Edge edge(uint32_t index) const {
        const uint8_t *p = file.data + edge_table_offset + static_cast<size_t>(index) * EDGE_SIZE;
        return {
            read_value<int64_t>(p), read_value<uint32_t>(p + 8),
            read_value<uint32_t>(p + 12), read_value<uint32_t>(p + 16),
            read_value<float>(p + 20), read_value<float>(p + 24),
            p[28], p[29], p[30],
        };
    }
};

bool edge_allowed(const Edge &edge) {
    const bool against_oneway = (edge.flags & 1u) != 0;
    return !against_oneway && (edge.access_class == 0 || edge.access_class == 1);
}

struct DirectedSnap {
    uint32_t edge_index;
    double fraction;
};

struct Snap {
    double x = 0.0;
    double y = 0.0;
    double distance_m = 0.0;
    std::vector<DirectedSnap> directions;
    size_t candidates = 0;
    bool ok = false;
};

struct SnapIndex {
    const Graph &graph;
    MappedFile file;
    float cell_size_m = 0.0f;
    float max_legal_speed_kmh = 0.0f;
    uint32_t cell_count = 0;
    uint32_t ref_count = 0;
    size_t ref_table_offset = 0;

    SnapIndex(const Graph &graph_, const std::string &path) : graph(graph_), file(path) {
        if (file.size < BRS_HEADER || std::memcmp(file.data, "BRS2", 4) != 0)
            throw std::runtime_error("bad BRS2 file");
        cell_size_m = read_value<float>(file.data + 4);
        cell_count = read_value<uint32_t>(file.data + 8);
        ref_count = read_value<uint32_t>(file.data + 12);
        max_legal_speed_kmh = read_value<float>(file.data + 16);
        ref_table_offset = BRS_HEADER + static_cast<size_t>(cell_count) * CELL_SIZE;
        if (ref_table_offset + static_cast<size_t>(ref_count) * 4 != file.size)
            throw std::runtime_error("BRS2 size mismatch");
    }

    bool find_cell(int32_t wanted_x, int32_t wanted_y, uint32_t &offset, uint32_t &count) const {
        uint32_t low = 0;
        uint32_t high = cell_count;
        while (low < high) {
            const uint32_t middle = low + (high - low) / 2;
            const uint8_t *p = file.data + BRS_HEADER + static_cast<size_t>(middle) * CELL_SIZE;
            const int32_t x = read_value<int32_t>(p);
            const int32_t y = read_value<int32_t>(p + 4);
            if (x < wanted_x || (x == wanted_x && y < wanted_y)) low = middle + 1;
            else high = middle;
        }
        if (low >= cell_count) return false;
        const uint8_t *p = file.data + BRS_HEADER + static_cast<size_t>(low) * CELL_SIZE;
        if (read_value<int32_t>(p) != wanted_x || read_value<int32_t>(p + 4) != wanted_y) return false;
        offset = read_value<uint32_t>(p + 8);
        count = read_value<uint32_t>(p + 12);
        return true;
    }

    std::vector<DirectedSnap> directions(uint32_t representative_index, double fraction) const {
        std::vector<DirectedSnap> result;
        const Edge representative = graph.edge(representative_index);
        if (edge_allowed(representative)) result.push_back({representative_index, fraction});
        const Node target = graph.node(representative.target);
        for (uint32_t i = 0; i < target.adjacency_count; ++i) {
            const uint32_t edge_index = target.adjacency_offset + i;
            const Edge edge = graph.edge(edge_index);
            if (edge.target == representative.source && edge.way_id == representative.way_id &&
                edge.segment_index == representative.segment_index) {
                if (edge_allowed(edge)) result.push_back({edge_index, 1.0 - fraction});
                break;
            }
        }
        std::sort(result.begin(), result.end(), [](const auto &a, const auto &b) {
            return a.edge_index < b.edge_index;
        });
        return result;
    }

    Snap snap(double x, double y, double max_distance_m = 250.0) const {
        const int32_t cx = static_cast<int32_t>(std::floor(x / cell_size_m));
        const int32_t cy = static_cast<int32_t>(std::floor(y / cell_size_m));
        const int radius = static_cast<int>(std::ceil(max_distance_m / cell_size_m)) + 1;
        std::vector<uint32_t> candidates;
        for (int ix = cx - radius; ix <= cx + radius; ++ix) {
            for (int iy = cy - radius; iy <= cy + radius; ++iy) {
                uint32_t offset = 0;
                uint32_t count = 0;
                if (!find_cell(ix, iy, offset, count)) continue;
                for (uint32_t j = 0; j < count; ++j) {
                    candidates.push_back(read_value<uint32_t>(file.data + ref_table_offset +
                                                               static_cast<size_t>(offset + j) * 4));
                }
            }
        }
        std::sort(candidates.begin(), candidates.end());
        candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());

        Snap result;
        result.candidates = candidates.size();
        double best_distance = std::numeric_limits<double>::infinity();
        uint32_t best_edge = 0;
        double best_fraction = 0.0;
        double best_x = 0.0;
        double best_y = 0.0;
        for (uint32_t edge_index : candidates) {
            const Edge edge = graph.edge(edge_index);
            const Node a = graph.node(edge.source);
            const Node b = graph.node(edge.target);
            const double dx = static_cast<double>(b.x) - a.x;
            const double dy = static_cast<double>(b.y) - a.y;
            const double length_sq = dx * dx + dy * dy;
            double fraction = length_sq > 0.0 ? ((x - a.x) * dx + (y - a.y) * dy) / length_sq : 0.0;
            fraction = std::max(0.0, std::min(1.0, fraction));
            const double px = a.x + dx * fraction;
            const double py = a.y + dy * fraction;
            const double distance = std::hypot(x - px, y - py);
            if (distance < best_distance || (distance == best_distance && edge_index < best_edge)) {
                best_distance = distance;
                best_edge = edge_index;
                best_fraction = fraction;
                best_x = px;
                best_y = py;
            }
        }
        if (!std::isfinite(best_distance) || best_distance > max_distance_m) return result;
        result.x = best_x;
        result.y = best_y;
        result.distance_m = best_distance;
        result.directions = directions(best_edge, best_fraction);
        result.ok = !result.directions.empty();
        return result;
    }
};

double project_x(double lon) { return EARTH_RADIUS * lon * PI / 180.0; }
double project_y(double lat) {
    const double radians = lat * PI / 180.0;
    return EARTH_RADIUS * std::log(std::tan(PI / 4.0 + radians / 2.0));
}

struct QueueItem {
    double estimate;
    double cost;
    uint32_t node;
};
struct QueueCompare {
    bool operator()(const QueueItem &a, const QueueItem &b) const {
        return a.estimate > b.estimate || (a.estimate == b.estimate && a.node > b.node);
    }
};

struct RouteResult {
    bool ok = false;
    double cost = 0.0;
    double distance_m = 0.0;
    double travel_time_s = 0.0;
    uint64_t settled = 0;
    uint64_t relaxed = 0;
    size_t queue_peak = 0;
    size_t steps = 0;
};

struct Router {
    const Graph &graph;
    double max_speed_mps;
    double mercator_lower_bound_scale = 1.0;
    std::vector<double> distance;
    std::vector<uint32_t> epoch;
    std::vector<uint32_t> parent_node;
    std::vector<uint32_t> parent_edge;
    std::vector<uint32_t> seed_edge;
    uint32_t current_epoch = 1;

    Router(const Graph &graph_, double max_speed_kmh)
        : graph(graph_), max_speed_mps(max_speed_kmh / 3.6), distance(graph_.node_count),
          epoch(graph_.node_count), parent_node(graph_.node_count), parent_edge(graph_.node_count),
          seed_edge(graph_.node_count) {
        double max_abs_lat = 0.0;
        for (uint32_t i = 0; i < graph.node_count; ++i)
            max_abs_lat = std::max(max_abs_lat, std::abs(graph.node(i).lat));
        // Web Mercator stretches ground distance by sec(latitude). Multiplying a
        // projected straight-line distance by cos(max |latitude|) is therefore
        // a conservative lower bound for this graph and keeps A* exact.
        mercator_lower_bound_scale = std::cos(max_abs_lat * PI / 180.0) * 0.999999;
    }

    double edge_cost(const Edge &edge) const { return edge.length_m / (edge.speed_kmh / 3.6); }

    double heuristic(uint32_t node_index, const std::vector<uint32_t> &targets) const {
        const Node node = graph.node(node_index);
        double best = std::numeric_limits<double>::infinity();
        for (uint32_t target_index : targets) {
            const Node target = graph.node(target_index);
            const double projected = std::hypot(static_cast<double>(node.x) - target.x,
                                                static_cast<double>(node.y) - target.y);
            best = std::min(best, projected * mercator_lower_bound_scale);
        }
        return best / max_speed_mps;
    }

    RouteResult route(const Snap &start, const Snap &target) {
        RouteResult result;
        if (!start.ok || !target.ok) return result;
        if (++current_epoch == 0) {
            std::fill(epoch.begin(), epoch.end(), 0);
            current_epoch = 1;
        }

        struct Terminal { uint32_t node; uint32_t edge; double cost; double fraction; };
        std::vector<Terminal> terminals;
        std::vector<uint32_t> target_nodes;
        for (const DirectedSnap &snap : target.directions) {
            const Edge edge = graph.edge(snap.edge_index);
            terminals.push_back({edge.source, snap.edge_index, edge_cost(edge) * snap.fraction, snap.fraction});
            target_nodes.push_back(edge.source);
        }
        std::sort(target_nodes.begin(), target_nodes.end());
        target_nodes.erase(std::unique(target_nodes.begin(), target_nodes.end()), target_nodes.end());

        std::priority_queue<QueueItem, std::vector<QueueItem>, QueueCompare> queue;
        for (const DirectedSnap &snap : start.directions) {
            const Edge edge = graph.edge(snap.edge_index);
            const double cost = edge_cost(edge) * (1.0 - snap.fraction);
            const uint32_t node = edge.target;
            if (epoch[node] != current_epoch || cost < distance[node]) {
                epoch[node] = current_epoch;
                distance[node] = cost;
                parent_node[node] = UINT32_MAX;
                parent_edge[node] = UINT32_MAX;
                seed_edge[node] = snap.edge_index;
                queue.push({cost + heuristic(node, target_nodes), cost, node});
            }
        }
        result.queue_peak = queue.size();

        double best_total = std::numeric_limits<double>::infinity();
        uint32_t best_node = UINT32_MAX;
        uint32_t best_target_edge = UINT32_MAX;
        while (!queue.empty()) {
            const QueueItem item = queue.top();
            queue.pop();
            if (epoch[item.node] != current_epoch || item.cost != distance[item.node]) continue;
            if (item.estimate >= best_total) break;
            ++result.settled;

            for (const Terminal &terminal : terminals) {
                if (terminal.node != item.node) continue;
                const double total = item.cost + terminal.cost;
                if (total < best_total) {
                    best_total = total;
                    best_node = item.node;
                    best_target_edge = terminal.edge;
                }
            }

            const Node node = graph.node(item.node);
            for (uint32_t i = 0; i < node.adjacency_count; ++i) {
                const uint32_t edge_index = node.adjacency_offset + i;
                const Edge edge = graph.edge(edge_index);
                if (!edge_allowed(edge)) continue;
                ++result.relaxed;
                const double candidate = item.cost + edge_cost(edge);
                if (epoch[edge.target] != current_epoch || candidate < distance[edge.target]) {
                    epoch[edge.target] = current_epoch;
                    distance[edge.target] = candidate;
                    parent_node[edge.target] = item.node;
                    parent_edge[edge.target] = edge_index;
                    seed_edge[edge.target] = seed_edge[item.node];
                    const double estimate = candidate + heuristic(edge.target, target_nodes);
                    if (estimate < best_total) {
                        queue.push({estimate, candidate, edge.target});
                        result.queue_peak = std::max(result.queue_peak, queue.size());
                    }
                }
            }
        }
        if (best_node == UINT32_MAX) return result;

        result.ok = true;
        result.cost = best_total;
        std::vector<uint32_t> middle_edges;
        uint32_t current = best_node;
        while (parent_node[current] != UINT32_MAX) {
            middle_edges.push_back(parent_edge[current]);
            current = parent_node[current];
        }
        std::reverse(middle_edges.begin(), middle_edges.end());

        const uint32_t start_edge_index = seed_edge[current];
        double start_fraction = 0.0;
        for (const DirectedSnap &snap : start.directions)
            if (snap.edge_index == start_edge_index) start_fraction = snap.fraction;
        const Edge start_edge = graph.edge(start_edge_index);
        const double start_part = 1.0 - start_fraction;
        result.distance_m += start_edge.length_m * start_part;
        result.travel_time_s += edge_cost(start_edge) * start_part;
        if (start_part > 1e-12) ++result.steps;

        for (uint32_t edge_index : middle_edges) {
            const Edge edge = graph.edge(edge_index);
            result.distance_m += edge.length_m;
            result.travel_time_s += edge_cost(edge);
            ++result.steps;
        }

        double target_fraction = 0.0;
        for (const DirectedSnap &snap : target.directions)
            if (snap.edge_index == best_target_edge) target_fraction = snap.fraction;
        const Edge target_edge = graph.edge(best_target_edge);
        result.distance_m += target_edge.length_m * target_fraction;
        result.travel_time_s += edge_cost(target_edge) * target_fraction;
        if (target_fraction > 1e-12) ++result.steps;
        return result;
    }
};

template <class ClockPoint>
double elapsed_ms(ClockPoint start, ClockPoint end) {
    return std::chrono::duration<double, std::milli>(end - start).count();
}

void benchmark_case(const SnapIndex &snap_index, Router &router, const char *name,
                    double start_lon, double start_lat, double target_lon, double target_lat) {
    const auto a = std::chrono::steady_clock::now();
    const Snap start = snap_index.snap(project_x(start_lon), project_y(start_lat));
    const auto b = std::chrono::steady_clock::now();
    const Snap target = snap_index.snap(project_x(target_lon), project_y(target_lat));
    const auto c = std::chrono::steady_clock::now();
    const RouteResult route = router.route(start, target);
    const auto d = std::chrono::steady_clock::now();

    std::cout << "[native-gps] " << name << " start snap: " << elapsed_ms(a, b)
              << " ms | candidates " << start.candidates << "\n";
    std::cout << "[native-gps] " << name << " target snap: " << elapsed_ms(b, c)
              << " ms | candidates " << target.candidates << "\n";
    std::cout << "[native-gps] " << name << " fastest: " << elapsed_ms(c, d)
              << " ms | settled " << route.settled << " | relaxed " << route.relaxed
              << " | queue peak " << route.queue_peak << "\n";
    if (route.ok) {
        std::cout << "[native-gps]   " << route.distance_m / 1000.0 << " km | "
                  << route.travel_time_s / 60.0 << " min | " << route.steps << " steps\n";
    } else {
        std::cout << "[native-gps]   failed\n";
    }
}
} // namespace

int main(int argc, char **argv) {
    try {
        const std::string graph_path = argc > 1 ? argv[1] : "world_data/routing.brg";
        const std::string snap_path = argc > 2 ? argv[2] : "world_data/routing_snap.brs";
        const auto started = std::chrono::steady_clock::now();
        Graph graph(graph_path);
        SnapIndex snap_index(graph, snap_path);
        Router router(graph, snap_index.max_legal_speed_kmh);
        const auto ready = std::chrono::steady_clock::now();
        std::cout << "[native-gps] graph: " << graph.node_count << " nodes, " << graph.edge_count
                  << " directed edges | startup " << elapsed_ms(started, ready) << " ms\n";
        benchmark_case(snap_index, router, "city", 18.0686, 59.3293, 18.0009, 59.3600);
        benchmark_case(snap_index, router, "regional", 18.0686, 59.3293, 17.6389, 59.8586);
        benchmark_case(snap_index, router, "long", 18.0686, 59.3293, 11.9746, 57.7089);
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "native gps error: " << error.what() << "\n";
        return 1;
    }
}
