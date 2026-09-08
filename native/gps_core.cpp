#include "gps_core.h"
#include "gps_route_plan.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <queue>
#include <stdexcept>
#include <utility>

// Implements the portable BRG1/BRS2 snap and A* routing core.
//
// Dependencies:
// - Standard C++20 and gps_core.h/gps_route_plan.h only.
// - No filesystem, mmap, sockets, JSON, Godot or process APIs.

namespace brur::gps {
namespace {
constexpr std::size_t BRG_HEADER = 12;
constexpr std::size_t NODE_SIZE = 40;
constexpr std::size_t EDGE_SIZE = 34;
constexpr std::size_t BRS_HEADER = 20;
constexpr std::size_t CELL_SIZE = 16;
constexpr double PI = 3.14159265358979323846;
constexpr double AVOID_PENALTY = 4.0;

template <class T>
T read_value(const std::uint8_t *pointer) {
    T value;
    std::memcpy(&value, pointer, sizeof(T));
    return value;
}

struct Node {
    double lat;
    float x;
    float y;
    std::uint32_t adjacency_offset;
    std::uint32_t adjacency_count;
};

struct Edge {
    std::int64_t way_id;
    std::uint32_t segment_index;
    std::uint32_t source;
    std::uint32_t target;
    float length_m;
    float speed_kmh;
    std::uint8_t road_class;
    std::uint8_t access_class;
    std::uint8_t flags;
};

struct GraphView {
    ByteView bytes;
    std::uint32_t node_count = 0;
    std::uint32_t edge_count = 0;
    std::size_t edge_table_offset = 0;

    explicit GraphView(ByteView input) : bytes(input) {
        if (!bytes.data || bytes.size < BRG_HEADER || std::memcmp(bytes.data, "BRG1", 4) != 0)
            throw std::runtime_error("bad BRG1 data");
        node_count = read_value<std::uint32_t>(bytes.data + 4);
        edge_count = read_value<std::uint32_t>(bytes.data + 8);
        edge_table_offset = BRG_HEADER + static_cast<std::size_t>(node_count) * NODE_SIZE;
        if (edge_table_offset + static_cast<std::size_t>(edge_count) * EDGE_SIZE != bytes.size)
            throw std::runtime_error("BRG1 size mismatch");
    }

    Node node(std::uint32_t index) const {
        if (index >= node_count) throw std::runtime_error("BRG1 node index out of range");
        const auto *p = bytes.data + BRG_HEADER + static_cast<std::size_t>(index) * NODE_SIZE;
        return {
            read_value<double>(p + 16),
            read_value<float>(p + 24),
            read_value<float>(p + 28),
            read_value<std::uint32_t>(p + 32),
            read_value<std::uint32_t>(p + 36),
        };
    }

    Edge edge(std::uint32_t index) const {
        if (index >= edge_count) throw std::runtime_error("BRG1 edge index out of range");
        const auto *p = bytes.data + edge_table_offset + static_cast<std::size_t>(index) * EDGE_SIZE;
        return {
            read_value<std::int64_t>(p),
            read_value<std::uint32_t>(p + 8),
            read_value<std::uint32_t>(p + 12),
            read_value<std::uint32_t>(p + 16),
            read_value<float>(p + 20),
            read_value<float>(p + 24),
            p[28], p[29], p[30],
        };
    }
};

bool edge_allowed(const Edge &edge) {
    return (edge.flags & 1u) == 0 && (edge.access_class == 0 || edge.access_class == 1);
}

double travel_time_s(const Edge &edge) {
    return edge.length_m / (edge.speed_kmh / 3.6);
}

bool is_small_road(std::uint8_t road_class) { return road_class >= 10 && road_class <= 15; }
bool is_major_road(std::uint8_t road_class) { return road_class <= 5; }

double edge_cost(const Edge &edge, RoutingPreference preference) {
    if (preference == RoutingPreference::Shortest) return edge.length_m;
    double cost = travel_time_s(edge);
    if (preference == RoutingPreference::AvoidSmallRoads && is_small_road(edge.road_class)) cost *= AVOID_PENALTY;
    if (preference == RoutingPreference::AvoidMajorRoads && is_major_road(edge.road_class)) cost *= AVOID_PENALTY;
    return cost;
}

struct SnapIndexView {
    const GraphView &graph;
    ByteView bytes;
    float cell_size_m = 0.0f;
    float max_legal_speed_kmh = 0.0f;
    std::uint32_t cell_count = 0;
    std::uint32_t ref_count = 0;
    std::size_t ref_table_offset = 0;

    SnapIndexView(const GraphView &graph_, ByteView input) : graph(graph_), bytes(input) {
        if (!bytes.data || bytes.size < BRS_HEADER || std::memcmp(bytes.data, "BRS2", 4) != 0)
            throw std::runtime_error("bad BRS2 data");
        cell_size_m = read_value<float>(bytes.data + 4);
        cell_count = read_value<std::uint32_t>(bytes.data + 8);
        ref_count = read_value<std::uint32_t>(bytes.data + 12);
        max_legal_speed_kmh = read_value<float>(bytes.data + 16);
        if (!(cell_size_m > 0.0f) || !(max_legal_speed_kmh > 0.0f))
            throw std::runtime_error("bad BRS2 metadata");
        ref_table_offset = BRS_HEADER + static_cast<std::size_t>(cell_count) * CELL_SIZE;
        if (ref_table_offset + static_cast<std::size_t>(ref_count) * 4 != bytes.size)
            throw std::runtime_error("BRS2 size mismatch");
    }

    bool find_cell(std::int32_t wanted_x, std::int32_t wanted_y,
                   std::uint32_t &offset, std::uint32_t &count) const {
        std::uint32_t low = 0;
        std::uint32_t high = cell_count;
        while (low < high) {
            const auto middle = low + (high - low) / 2;
            const auto *p = bytes.data + BRS_HEADER + static_cast<std::size_t>(middle) * CELL_SIZE;
            const auto x = read_value<std::int32_t>(p);
            const auto y = read_value<std::int32_t>(p + 4);
            if (x < wanted_x || (x == wanted_x && y < wanted_y)) low = middle + 1;
            else high = middle;
        }
        if (low >= cell_count) return false;
        const auto *p = bytes.data + BRS_HEADER + static_cast<std::size_t>(low) * CELL_SIZE;
        if (read_value<std::int32_t>(p) != wanted_x || read_value<std::int32_t>(p + 4) != wanted_y)
            return false;
        offset = read_value<std::uint32_t>(p + 8);
        count = read_value<std::uint32_t>(p + 12);
        if (static_cast<std::uint64_t>(offset) + count > ref_count)
            throw std::runtime_error("BRS2 cell refs out of range");
        return true;
    }

    std::vector<DirectedSnap> directions(std::uint32_t representative_index, double fraction) const {
        std::vector<DirectedSnap> result;
        const Edge representative = graph.edge(representative_index);
        if (edge_allowed(representative)) result.push_back({representative_index, fraction});
        const Node target = graph.node(representative.target);
        if (static_cast<std::uint64_t>(target.adjacency_offset) + target.adjacency_count > graph.edge_count)
            throw std::runtime_error("BRG1 adjacency out of range");
        for (std::uint32_t i = 0; i < target.adjacency_count; ++i) {
            const auto edge_index = target.adjacency_offset + i;
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

    SnappedPosition snap(RoutePoint point, double max_distance_m) const {
        SnappedPosition result;
        if (!(max_distance_m >= 0.0) || !std::isfinite(point.x) || !std::isfinite(point.y)) {
            result.failure = RouteFailure::InvalidData;
            return result;
        }
        const auto cx = static_cast<std::int32_t>(std::floor(point.x / cell_size_m));
        const auto cy = static_cast<std::int32_t>(std::floor(point.y / cell_size_m));
        const int radius = static_cast<int>(std::ceil(max_distance_m / cell_size_m)) + 1;
        std::vector<std::uint32_t> candidates;
        for (int ix = cx - radius; ix <= cx + radius; ++ix) {
            for (int iy = cy - radius; iy <= cy + radius; ++iy) {
                std::uint32_t offset = 0;
                std::uint32_t count = 0;
                if (!find_cell(ix, iy, offset, count)) continue;
                for (std::uint32_t j = 0; j < count; ++j) {
                    candidates.push_back(read_value<std::uint32_t>(
                        bytes.data + ref_table_offset + static_cast<std::size_t>(offset + j) * 4));
                }
            }
        }
        std::sort(candidates.begin(), candidates.end());
        candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());
        result.candidates = candidates.size();

        double best_distance = std::numeric_limits<double>::infinity();
        std::uint32_t best_edge = 0;
        double best_fraction = 0.0;
        double best_x = 0.0;
        double best_y = 0.0;
        for (auto edge_index : candidates) {
            if (edge_index >= graph.edge_count) throw std::runtime_error("BRS2 edge ref out of range");
            const Edge edge = graph.edge(edge_index);
            const Node a = graph.node(edge.source);
            const Node b = graph.node(edge.target);
            const double dx = static_cast<double>(b.x) - a.x;
            const double dy = static_cast<double>(b.y) - a.y;
            const double length_sq = dx * dx + dy * dy;
            double fraction = length_sq > 0.0
                ? ((point.x - a.x) * dx + (point.y - a.y) * dy) / length_sq
                : 0.0;
            fraction = std::clamp(fraction, 0.0, 1.0);
            const double px = a.x + dx * fraction;
            const double py = a.y + dy * fraction;
            const double distance = std::hypot(point.x - px, point.y - py);
            if (distance < best_distance || (distance == best_distance && edge_index < best_edge)) {
                best_distance = distance;
                best_edge = edge_index;
                best_fraction = fraction;
                best_x = px;
                best_y = py;
            }
        }
        if (!std::isfinite(best_distance) || best_distance > max_distance_m) return result;
        result.point = {best_x, best_y};
        result.distance_m = best_distance;
        result.directions = directions(best_edge, best_fraction);
        result.success = !result.directions.empty();
        result.failure = result.success ? RouteFailure::None : RouteFailure::SnapFailed;
        return result;
    }
};

struct QueueItem {
    double estimate;
    double cost;
    std::uint32_t node;
};
struct QueueCompare {
    bool operator()(const QueueItem &a, const QueueItem &b) const {
        return a.estimate > b.estimate || (a.estimate == b.estimate && a.node > b.node);
    }
};

void append_point(std::vector<RoutePoint> &points, RoutePoint point) {
    if (!points.empty() && std::abs(points.back().x - point.x) < 1e-6 &&
        std::abs(points.back().y - point.y) < 1e-6) return;
    points.push_back(point);
}
} // namespace

struct RoutingContext::Impl {
    GraphView graph;
    SnapIndexView snap_index;
    double max_speed_mps;
    double mercator_lower_bound_scale = 1.0;
    std::vector<double> distance;
    std::vector<std::uint32_t> epoch;
    std::vector<std::uint32_t> parent_node;
    std::vector<std::uint32_t> parent_edge;
    std::vector<std::uint32_t> seed_edge;
    std::uint32_t current_epoch = 1;

    explicit Impl(const RoutingDataView &data)
        : graph(data.graph), snap_index(graph, data.snap),
          max_speed_mps(snap_index.max_legal_speed_kmh / 3.6),
          distance(graph.node_count), epoch(graph.node_count), parent_node(graph.node_count),
          parent_edge(graph.node_count), seed_edge(graph.node_count) {
        double max_abs_lat = 0.0;
        for (std::uint32_t i = 0; i < graph.node_count; ++i)
            max_abs_lat = std::max(max_abs_lat, std::abs(graph.node(i).lat));
        mercator_lower_bound_scale = std::cos(max_abs_lat * PI / 180.0) * 0.999999;
    }

    double heuristic(std::uint32_t node_index, const std::vector<std::uint32_t> &targets,
                     RoutingPreference preference) const {
        const Node node = graph.node(node_index);
        double best = std::numeric_limits<double>::infinity();
        for (auto target_index : targets) {
            const Node target = graph.node(target_index);
            best = std::min(best,
                std::hypot(static_cast<double>(node.x) - target.x,
                           static_cast<double>(node.y) - target.y) * mercator_lower_bound_scale);
        }
        return preference == RoutingPreference::Shortest ? best : best / max_speed_mps;
    }

    RouteLegResult route_leg(const SnappedPosition &start, const SnappedPosition &target,
                             RoutingPreference preference, std::size_t leg_index) {
        RouteLegResult out;
        out.leg_index = leg_index;
        out.from_stop_index = leg_index;
        out.to_stop_index = leg_index + 1;
        if (!start.success || !target.success) {
            out.failure = RouteFailure::SnapFailed;
            return out;
        }
        if (++current_epoch == 0) {
            std::fill(epoch.begin(), epoch.end(), 0);
            current_epoch = 1;
        }

        bool have_direct = false;
        double direct_cost = std::numeric_limits<double>::infinity();
        double direct_distance = 0.0;
        double direct_time = 0.0;
        std::uint32_t direct_edge = 0;
        for (const auto &from : start.directions) {
            for (const auto &to : target.directions) {
                if (from.edge_index != to.edge_index || to.fraction + 1e-12 < from.fraction) continue;
                const Edge edge = graph.edge(from.edge_index);
                const double fraction = std::max(0.0, to.fraction - from.fraction);
                const double cost = edge_cost(edge, preference) * fraction;
                if (!have_direct || cost < direct_cost) {
                    have_direct = true;
                    direct_cost = cost;
                    direct_distance = edge.length_m * fraction;
                    direct_time = travel_time_s(edge) * fraction;
                    direct_edge = from.edge_index;
                }
            }
        }

        struct Terminal {
            std::uint32_t node;
            std::uint32_t edge;
            double cost;
        };
        std::vector<Terminal> terminals;
        std::vector<std::uint32_t> target_nodes;
        for (const auto &snap : target.directions) {
            const Edge edge = graph.edge(snap.edge_index);
            terminals.push_back({edge.source, snap.edge_index, edge_cost(edge, preference) * snap.fraction});
            target_nodes.push_back(edge.source);
        }
        std::sort(target_nodes.begin(), target_nodes.end());
        target_nodes.erase(std::unique(target_nodes.begin(), target_nodes.end()), target_nodes.end());

        std::priority_queue<QueueItem, std::vector<QueueItem>, QueueCompare> queue;
        for (const auto &snap : start.directions) {
            const Edge edge = graph.edge(snap.edge_index);
            const double cost = edge_cost(edge, preference) * (1.0 - snap.fraction);
            const auto node = edge.target;
            if (epoch[node] != current_epoch || cost < distance[node]) {
                epoch[node] = current_epoch;
                distance[node] = cost;
                parent_node[node] = UINT32_MAX;
                parent_edge[node] = UINT32_MAX;
                seed_edge[node] = snap.edge_index;
                queue.push({cost + heuristic(node, target_nodes, preference), cost, node});
            }
        }
        out.metrics.queue_peak = queue.size();

        double best_total = have_direct ? direct_cost : std::numeric_limits<double>::infinity();
        std::uint32_t best_node = UINT32_MAX;
        std::uint32_t best_target_edge = UINT32_MAX;
        while (!queue.empty()) {
            const auto item = queue.top();
            queue.pop();
            if (epoch[item.node] != current_epoch || item.cost != distance[item.node]) continue;
            if (item.estimate >= best_total - 1e-12) break;
            ++out.metrics.settled;

            for (const auto &terminal : terminals) {
                if (terminal.node != item.node) continue;
                const double total = item.cost + terminal.cost;
                if (total < best_total - 1e-12) {
                    best_total = total;
                    best_node = item.node;
                    best_target_edge = terminal.edge;
                }
            }

            const Node node = graph.node(item.node);
            if (static_cast<std::uint64_t>(node.adjacency_offset) + node.adjacency_count > graph.edge_count)
                throw std::runtime_error("BRG1 adjacency out of range");
            for (std::uint32_t i = 0; i < node.adjacency_count; ++i) {
                const auto edge_index = node.adjacency_offset + i;
                const Edge edge = graph.edge(edge_index);
                if (!edge_allowed(edge)) continue;
                ++out.metrics.relaxed;
                const double candidate = item.cost + edge_cost(edge, preference);
                if (epoch[edge.target] != current_epoch || candidate < distance[edge.target] - 1e-12) {
                    epoch[edge.target] = current_epoch;
                    distance[edge.target] = candidate;
                    parent_node[edge.target] = item.node;
                    parent_edge[edge.target] = edge_index;
                    seed_edge[edge.target] = seed_edge[item.node];
                    const double estimate = candidate + heuristic(edge.target, target_nodes, preference);
                    if (estimate < best_total - 1e-12) {
                        queue.push({estimate, candidate, edge.target});
                        out.metrics.queue_peak = std::max(out.metrics.queue_peak, queue.size());
                    }
                }
            }
        }

        if (best_node == UINT32_MAX) {
            if (!have_direct) return out;
            out.success = true;
            out.failure = RouteFailure::None;
            out.metrics.cost = direct_cost;
            out.metrics.distance_m = direct_distance;
            out.metrics.travel_time_s = direct_time;
            out.metrics.steps = direct_distance > 1e-9 ? 1 : 0;
            append_point(out.points, start.point);
            append_point(out.points, target.point);
            if (out.metrics.steps) out.edge_indices.push_back(direct_edge);
            return out;
        }

        out.success = true;
        out.failure = RouteFailure::None;
        out.metrics.cost = best_total;
        std::vector<std::uint32_t> middle_edges;
        std::uint32_t current = best_node;
        while (parent_node[current] != UINT32_MAX) {
            middle_edges.push_back(parent_edge[current]);
            current = parent_node[current];
        }
        std::reverse(middle_edges.begin(), middle_edges.end());

        const auto start_edge_index = seed_edge[current];
        double start_fraction = 0.0;
        for (const auto &snap : start.directions)
            if (snap.edge_index == start_edge_index) start_fraction = snap.fraction;
        const Edge start_edge = graph.edge(start_edge_index);
        const double start_part = 1.0 - start_fraction;
        out.metrics.distance_m += start_edge.length_m * start_part;
        out.metrics.travel_time_s += travel_time_s(start_edge) * start_part;
        if (start_part > 1e-12) {
            ++out.metrics.steps;
            out.edge_indices.push_back(start_edge_index);
        }
        append_point(out.points, start.point);
        if (start_part > 1e-12) {
            const Node node = graph.node(start_edge.target);
            append_point(out.points, {node.x, node.y});
        }

        for (auto edge_index : middle_edges) {
            const Edge edge = graph.edge(edge_index);
            out.metrics.distance_m += edge.length_m;
            out.metrics.travel_time_s += travel_time_s(edge);
            ++out.metrics.steps;
            out.edge_indices.push_back(edge_index);
            const Node node = graph.node(edge.target);
            append_point(out.points, {node.x, node.y});
        }

        double target_fraction = 0.0;
        for (const auto &snap : target.directions)
            if (snap.edge_index == best_target_edge) target_fraction = snap.fraction;
        const Edge target_edge = graph.edge(best_target_edge);
        out.metrics.distance_m += target_edge.length_m * target_fraction;
        out.metrics.travel_time_s += travel_time_s(target_edge) * target_fraction;
        if (target_fraction > 1e-12) {
            ++out.metrics.steps;
            out.edge_indices.push_back(best_target_edge);
        }
        append_point(out.points, target.point);
        return out;
    }
};

const char *routing_preference_name(RoutingPreference preference) {
    switch (preference) {
        case RoutingPreference::Fastest: return "fastest";
        case RoutingPreference::Shortest: return "shortest";
        case RoutingPreference::AvoidSmallRoads: return "avoid_small_roads";
        case RoutingPreference::AvoidMajorRoads: return "avoid_major_roads";
    }
    return "fastest";
}

bool parse_routing_preference(std::string_view text, RoutingPreference &out) {
    if (text.empty() || text == "fastest") out = RoutingPreference::Fastest;
    else if (text == "shortest") out = RoutingPreference::Shortest;
    else if (text == "avoid_small_roads") out = RoutingPreference::AvoidSmallRoads;
    else if (text == "avoid_major_roads") out = RoutingPreference::AvoidMajorRoads;
    else return false;
    return true;
}

const char *route_failure_name(RouteFailure failure) {
    switch (failure) {
        case RouteFailure::None: return "";
        case RouteFailure::InvalidData: return "invalid_data";
        case RouteFailure::SnapFailed: return "snap_failed";
        case RouteFailure::Unreachable: return "unreachable";
    }
    return "unreachable";
}

RoutingContext::RoutingContext(const RoutingDataView &data) : impl_(std::make_unique<Impl>(data)) {}
RoutingContext::~RoutingContext() = default;
RoutingContext::RoutingContext(RoutingContext &&) noexcept = default;
RoutingContext &RoutingContext::operator=(RoutingContext &&) noexcept = default;
std::uint32_t RoutingContext::node_count() const { return impl_->graph.node_count; }
std::uint32_t RoutingContext::edge_count() const { return impl_->graph.edge_count; }
double RoutingContext::max_legal_speed_kmh() const { return impl_->snap_index.max_legal_speed_kmh; }
SnappedPosition RoutingContext::snap(RoutePoint point, double max_distance_m) const {
    return impl_->snap_index.snap(point, max_distance_m);
}

RouteResult RoutingContext::route(const RouteRequest &request) {
    RouteResult result;
    result.preference = request.preference;
    result.snaps = {request.start.point, request.target.point};
    result.snap_candidates = {request.start.candidates, request.target.candidates};
    if (!request.start.success || !request.target.success) {
        result.failure = RouteFailure::SnapFailed;
        result.failed_leg_index = 0;
        return result;
    }
    auto leg = impl_->route_leg(request.start, request.target, request.preference, 0);
    leg.point_start_index = 0;
    leg.point_end_index = leg.points.empty() ? 0 : leg.points.size() - 1;
    result.legs.push_back(leg);
    if (!leg.success) {
        result.failure = leg.failure;
        result.failed_leg_index = 0;
        return result;
    }
    result.success = true;
    result.failure = RouteFailure::None;
    result.metrics = leg.metrics;
    result.points = std::move(leg.points);
    return result;
}

RouteResult RoutingContext::route_plan(const RoutePlanRequest &request) {
    RouteResult result;
    result.preference = request.preference;
    if (request.stops.size() < 2) {
        result.failure = RouteFailure::InvalidData;
        result.failed_leg_index = 0;
        return result;
    }
    result.snaps.reserve(request.stops.size());
    result.snap_candidates.reserve(request.stops.size());
    for (std::size_t i = 0; i < request.stops.size(); ++i) {
        result.snaps.push_back(request.stops[i].point);
        result.snap_candidates.push_back(request.stops[i].candidates);
        if (!request.stops[i].success) {
            result.failure = RouteFailure::SnapFailed;
            result.failed_leg_index = i == 0 ? 0 : i - 1;
            return result;
        }
    }

    std::vector<RouteLegResult> raw_legs(request.stops.size() - 1);
    const auto plan = execute_route_plan(
        request.stops,
        [this, &request, &raw_legs](const SnappedPosition &from, const SnappedPosition &to,
                                    std::size_t i) {
            raw_legs[i] = impl_->route_leg(from, to, request.preference, i);
            RoutePlanLegOutput output;
            output.success = raw_legs[i].success;
            output.failure_reason = route_failure_name(raw_legs[i].failure);
            output.cost = raw_legs[i].metrics.cost;
            output.distance_m = raw_legs[i].metrics.distance_m;
            output.travel_time_s = raw_legs[i].metrics.travel_time_s;
            output.settled = raw_legs[i].metrics.settled;
            output.relaxed = raw_legs[i].metrics.relaxed;
            output.queue_peak = raw_legs[i].metrics.queue_peak;
            output.steps = raw_legs[i].metrics.steps;
            for (const auto &point : raw_legs[i].points) output.points.push_back({point.x, point.y});
            return output;
        });

    result.success = plan.success;
    result.failure = plan.success ? RouteFailure::None : RouteFailure::Unreachable;
    result.failed_leg_index = plan.failed_leg_index;
    result.metrics = {
        plan.cost, plan.distance_m, plan.travel_time_s, plan.settled, plan.relaxed,
        plan.queue_peak, plan.steps,
    };
    for (const auto &point : plan.points) result.points.push_back({point.x, point.y});
    result.legs.reserve(plan.legs.size());
    for (const auto &plan_leg : plan.legs) {
        auto leg = raw_legs[plan_leg.leg_index];
        leg.point_start_index = plan_leg.point_start_index;
        leg.point_end_index = plan_leg.point_end_index;
        result.legs.push_back(std::move(leg));
    }
    return result;
}

} // namespace brur::gps
