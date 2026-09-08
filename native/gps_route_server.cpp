#define main brur_native_benchmark_main
#include "gps_runtime.cpp"
#undef main

#include "gps_route_plan.h"

#include <arpa/inet.h>
#include <cerrno>
#include <iomanip>
#include <netinet/in.h>
#include <sstream>
#include <sys/resource.h>
#include <sys/socket.h>

// Resident localhost adapter for Godot GPS queries.
//
// Dependencies:
// - gps_runtime.cpp owns BRG1/BRS2 loading, snapping, legality and A* primitives.
// - gps_route_plan.h owns ordered multi-leg route-plan aggregation and is platform-neutral.
// - This file owns only the localhost transport, request parsing and JSON serialization.
//
// The graph, snap index and routing context are created once and stay resident.
// File-backed routing pages are also touched before the server announces ready,
// so the first gameplay route does not pay Sweden-scale mmap page faults.

namespace {
enum class RoutingPreference : uint8_t {
    Fastest,
    Shortest,
    AvoidSmallRoads,
    AvoidMajorRoads,
};

constexpr double AVOID_PENALTY = 4.0;
constexpr std::size_t MAX_PLAN_STOPS = 32;

struct RoutePolylineResult {
    RouteResult metrics;
    std::vector<std::pair<double, double>> points;
};

struct SnappedPlanStop {
    Snap snap;
    double snap_ms = 0.0;
};

RoutingPreference parse_preference(const std::string &value) {
    if (value.empty() || value == "fastest") return RoutingPreference::Fastest;
    if (value == "shortest") return RoutingPreference::Shortest;
    if (value == "avoid_small_roads") return RoutingPreference::AvoidSmallRoads;
    if (value == "avoid_major_roads") return RoutingPreference::AvoidMajorRoads;
    throw std::runtime_error("unknown routing preference: " + value);
}

const char *preference_name(RoutingPreference preference) {
    switch (preference) {
        case RoutingPreference::Fastest: return "fastest";
        case RoutingPreference::Shortest: return "shortest";
        case RoutingPreference::AvoidSmallRoads: return "avoid_small_roads";
        case RoutingPreference::AvoidMajorRoads: return "avoid_major_roads";
    }
    return "fastest";
}

double travel_time_s(const Edge &edge) {
    return edge.length_m / (edge.speed_kmh / 3.6);
}

bool is_small_road(uint8_t road_class) {
    return road_class >= 10 && road_class <= 15;
}

bool is_major_road(uint8_t road_class) {
    return road_class <= 5;
}

double route_edge_cost(const Edge &edge, RoutingPreference preference) {
    if (preference == RoutingPreference::Shortest) return edge.length_m;
    double cost = travel_time_s(edge);
    if (preference == RoutingPreference::AvoidSmallRoads && is_small_road(edge.road_class))
        cost *= AVOID_PENALTY;
    else if (preference == RoutingPreference::AvoidMajorRoads && is_major_road(edge.road_class))
        cost *= AVOID_PENALTY;
    return cost;
}

double route_heuristic(const Router &router, uint32_t node_index,
                       const std::vector<uint32_t> &targets, RoutingPreference preference) {
    const Node node = router.graph.node(node_index);
    double best = std::numeric_limits<double>::infinity();
    for (uint32_t target_index : targets) {
        const Node target = router.graph.node(target_index);
        const double projected = std::hypot(static_cast<double>(node.x) - target.x,
                                            static_cast<double>(node.y) - target.y);
        best = std::min(best, projected * router.mercator_lower_bound_scale);
    }
    if (preference == RoutingPreference::Shortest) return best;
    return best / router.max_speed_mps;
}

void append_point(std::vector<std::pair<double, double>> &points, double x, double y) {
    if (!points.empty()) {
        const auto &last = points.back();
        if (std::abs(last.first - x) < 1e-6 && std::abs(last.second - y) < 1e-6) return;
    }
    points.emplace_back(x, y);
}

RoutePolylineResult route_with_polyline(Router &router, const Snap &start, const Snap &target,
                                        RoutingPreference preference) {
    RoutePolylineResult output;
    RouteResult &result = output.metrics;
    if (!start.ok || !target.ok) return output;

    if (++router.current_epoch == 0) {
        std::fill(router.epoch.begin(), router.epoch.end(), 0);
        router.current_epoch = 1;
    }

    bool have_direct = false;
    double direct_cost = std::numeric_limits<double>::infinity();
    double direct_distance = 0.0;
    double direct_time = 0.0;
    for (const DirectedSnap &from : start.directions) {
        for (const DirectedSnap &to : target.directions) {
            if (from.edge_index != to.edge_index || to.fraction + 1e-12 < from.fraction) continue;
            const Edge edge = router.graph.edge(from.edge_index);
            const double fraction = std::max(0.0, to.fraction - from.fraction);
            const double cost = route_edge_cost(edge, preference) * fraction;
            if (!have_direct || cost < direct_cost) {
                have_direct = true;
                direct_cost = cost;
                direct_distance = edge.length_m * fraction;
                direct_time = travel_time_s(edge) * fraction;
            }
        }
    }

    struct Terminal {
        uint32_t node;
        uint32_t edge;
        double cost;
        double fraction;
    };
    std::vector<Terminal> terminals;
    std::vector<uint32_t> target_nodes;
    for (const DirectedSnap &snap : target.directions) {
        const Edge edge = router.graph.edge(snap.edge_index);
        terminals.push_back({edge.source, snap.edge_index,
                             route_edge_cost(edge, preference) * snap.fraction, snap.fraction});
        target_nodes.push_back(edge.source);
    }
    std::sort(target_nodes.begin(), target_nodes.end());
    target_nodes.erase(std::unique(target_nodes.begin(), target_nodes.end()), target_nodes.end());

    std::priority_queue<QueueItem, std::vector<QueueItem>, QueueCompare> queue;
    for (const DirectedSnap &snap : start.directions) {
        const Edge edge = router.graph.edge(snap.edge_index);
        const double cost = route_edge_cost(edge, preference) * (1.0 - snap.fraction);
        const uint32_t node = edge.target;
        if (router.epoch[node] != router.current_epoch || cost < router.distance[node]) {
            router.epoch[node] = router.current_epoch;
            router.distance[node] = cost;
            router.parent_node[node] = UINT32_MAX;
            router.parent_edge[node] = UINT32_MAX;
            router.seed_edge[node] = snap.edge_index;
            queue.push({cost + route_heuristic(router, node, target_nodes, preference), cost, node});
        }
    }
    result.queue_peak = queue.size();

    double best_total = have_direct ? direct_cost : std::numeric_limits<double>::infinity();
    uint32_t best_node = UINT32_MAX;
    uint32_t best_target_edge = UINT32_MAX;
    while (!queue.empty()) {
        const QueueItem item = queue.top();
        queue.pop();
        if (router.epoch[item.node] != router.current_epoch || item.cost != router.distance[item.node]) continue;
        if (item.estimate >= best_total - 1e-12) break;
        ++result.settled;

        for (const Terminal &terminal : terminals) {
            if (terminal.node != item.node) continue;
            const double total = item.cost + terminal.cost;
            if (total < best_total - 1e-12) {
                best_total = total;
                best_node = item.node;
                best_target_edge = terminal.edge;
            }
        }

        const Node node = router.graph.node(item.node);
        for (uint32_t i = 0; i < node.adjacency_count; ++i) {
            const uint32_t edge_index = node.adjacency_offset + i;
            const Edge edge = router.graph.edge(edge_index);
            if (!edge_allowed(edge)) continue;
            ++result.relaxed;
            const double candidate = item.cost + route_edge_cost(edge, preference);
            if (router.epoch[edge.target] != router.current_epoch || candidate < router.distance[edge.target] - 1e-12) {
                router.epoch[edge.target] = router.current_epoch;
                router.distance[edge.target] = candidate;
                router.parent_node[edge.target] = item.node;
                router.parent_edge[edge.target] = edge_index;
                router.seed_edge[edge.target] = router.seed_edge[item.node];
                const double estimate = candidate + route_heuristic(router, edge.target, target_nodes, preference);
                if (estimate < best_total - 1e-12) {
                    queue.push({estimate, candidate, edge.target});
                    result.queue_peak = std::max(result.queue_peak, queue.size());
                }
            }
        }
    }

    if (best_node == UINT32_MAX) {
        if (!have_direct) return output;
        result.ok = true;
        result.cost = direct_cost;
        result.distance_m = direct_distance;
        result.travel_time_s = direct_time;
        result.steps = direct_distance > 1e-9 ? 1 : 0;
        append_point(output.points, start.x, start.y);
        append_point(output.points, target.x, target.y);
        return output;
    }

    result.ok = true;
    result.cost = best_total;
    std::vector<uint32_t> middle_edges;
    uint32_t current = best_node;
    while (router.parent_node[current] != UINT32_MAX) {
        middle_edges.push_back(router.parent_edge[current]);
        current = router.parent_node[current];
    }
    std::reverse(middle_edges.begin(), middle_edges.end());

    const uint32_t start_edge_index = router.seed_edge[current];
    double start_fraction = 0.0;
    for (const DirectedSnap &snap : start.directions)
        if (snap.edge_index == start_edge_index) start_fraction = snap.fraction;
    const Edge start_edge = router.graph.edge(start_edge_index);
    const double start_part = 1.0 - start_fraction;
    result.distance_m += start_edge.length_m * start_part;
    result.travel_time_s += travel_time_s(start_edge) * start_part;
    if (start_part > 1e-12) ++result.steps;

    append_point(output.points, start.x, start.y);
    if (start_part > 1e-12) {
        const Node node = router.graph.node(start_edge.target);
        append_point(output.points, node.x, node.y);
    }

    for (uint32_t edge_index : middle_edges) {
        const Edge edge = router.graph.edge(edge_index);
        result.distance_m += edge.length_m;
        result.travel_time_s += travel_time_s(edge);
        ++result.steps;
        const Node node = router.graph.node(edge.target);
        append_point(output.points, node.x, node.y);
    }

    double target_fraction = 0.0;
    for (const DirectedSnap &snap : target.directions)
        if (snap.edge_index == best_target_edge) target_fraction = snap.fraction;
    const Edge target_edge = router.graph.edge(best_target_edge);
    result.distance_m += target_edge.length_m * target_fraction;
    result.travel_time_s += travel_time_s(target_edge) * target_fraction;
    if (target_fraction > 1e-12) ++result.steps;
    append_point(output.points, target.x, target.y);
    return output;
}

brur::gps::RoutePlanLegOutput to_plan_leg(const RoutePolylineResult &route) {
    brur::gps::RoutePlanLegOutput output;
    output.success = route.metrics.ok;
    if (!output.success) output.failure_reason = "unreachable";
    output.cost = route.metrics.cost;
    output.distance_m = route.metrics.distance_m;
    output.travel_time_s = route.metrics.travel_time_s;
    output.settled = route.metrics.settled;
    output.relaxed = route.metrics.relaxed;
    output.queue_peak = route.metrics.queue_peak;
    output.steps = route.metrics.steps;
    output.points.reserve(route.points.size());
    for (const auto &point : route.points) output.points.push_back({point.first, point.second});
    return output;
}

std::string route_json(const Snap &start, const Snap &target, const RoutePolylineResult &route,
                       RoutingPreference preference, double start_snap_ms,
                       double target_snap_ms, double route_ms) {
    std::ostringstream out;
    out << std::setprecision(12);
    out << "{\"success\":" << (route.metrics.ok ? "true" : "false")
        << ",\"preference\":\"" << preference_name(preference) << "\""
        << ",\"start_snap_ms\":" << start_snap_ms
        << ",\"target_snap_ms\":" << target_snap_ms
        << ",\"snap_ms\":" << (start_snap_ms + target_snap_ms)
        << ",\"route_ms\":" << route_ms
        << ",\"start_candidates\":" << start.candidates
        << ",\"target_candidates\":" << target.candidates
        << ",\"settled\":" << route.metrics.settled
        << ",\"relaxed\":" << route.metrics.relaxed
        << ",\"queue_peak\":" << route.metrics.queue_peak
        << ",\"distance_m\":" << route.metrics.distance_m
        << ",\"travel_time_s\":" << route.metrics.travel_time_s
        << ",\"steps\":" << route.metrics.steps
        << ",\"failed_leg_index\":null"
        << ",\"start_snap\":[" << start.x << ',' << start.y << ']'
        << ",\"target_snap\":[" << target.x << ',' << target.y << ']'
        << ",\"snaps\":[[" << start.x << ',' << start.y << "],[" << target.x << ',' << target.y << "]]"
        << ",\"legs\":[{\"index\":0,\"from_stop_index\":0,\"to_stop_index\":1"
        << ",\"success\":" << (route.metrics.ok ? "true" : "false")
        << ",\"distance_m\":" << route.metrics.distance_m
        << ",\"travel_time_s\":" << route.metrics.travel_time_s
        << ",\"settled\":" << route.metrics.settled
        << ",\"relaxed\":" << route.metrics.relaxed
        << ",\"queue_peak\":" << route.metrics.queue_peak
        << ",\"steps\":" << route.metrics.steps << "}]"
        << ",\"points\":[";
    for (size_t i = 0; i < route.points.size(); ++i) {
        if (i) out << ',';
        out << '[' << route.points[i].first << ',' << route.points[i].second << ']';
    }
    out << "]}\n";
    return out.str();
}

std::string plan_json(const std::vector<SnappedPlanStop> &stops,
                      const brur::gps::RoutePlanResult &plan,
                      RoutingPreference preference, double snap_ms, double route_ms) {
    std::ostringstream out;
    out << std::setprecision(12);
    out << "{\"success\":" << (plan.success ? "true" : "false")
        << ",\"preference\":\"" << preference_name(preference) << "\""
        << ",\"snap_ms\":" << snap_ms
        << ",\"route_ms\":" << route_ms
        << ",\"settled\":" << plan.settled
        << ",\"relaxed\":" << plan.relaxed
        << ",\"queue_peak\":" << plan.queue_peak
        << ",\"distance_m\":" << plan.distance_m
        << ",\"travel_time_s\":" << plan.travel_time_s
        << ",\"steps\":" << plan.steps;
    if (plan.success) out << ",\"failed_leg_index\":null";
    else out << ",\"failed_leg_index\":" << plan.failed_leg_index;
    if (!plan.failure_reason.empty()) out << ",\"failure_reason\":\"" << plan.failure_reason << "\"";

    if (!stops.empty()) {
        out << ",\"start_snap\":[" << stops.front().snap.x << ',' << stops.front().snap.y << ']'
            << ",\"target_snap\":[" << stops.back().snap.x << ',' << stops.back().snap.y << ']';
    }

    out << ",\"snaps\":[";
    for (std::size_t i = 0; i < stops.size(); ++i) {
        if (i) out << ',';
        out << '[' << stops[i].snap.x << ',' << stops[i].snap.y << ']';
    }
    out << "]";

    out << ",\"legs\":[";
    for (std::size_t i = 0; i < plan.legs.size(); ++i) {
        if (i) out << ',';
        const auto &leg = plan.legs[i];
        out << "{\"index\":" << leg.leg_index
            << ",\"from_stop_index\":" << leg.from_stop_index
            << ",\"to_stop_index\":" << leg.to_stop_index
            << ",\"success\":" << (leg.route.success ? "true" : "false")
            << ",\"distance_m\":" << leg.route.distance_m
            << ",\"travel_time_s\":" << leg.route.travel_time_s
            << ",\"settled\":" << leg.route.settled
            << ",\"relaxed\":" << leg.route.relaxed
            << ",\"queue_peak\":" << leg.route.queue_peak
            << ",\"steps\":" << leg.route.steps
            << ",\"point_start_index\":" << leg.point_start_index
            << ",\"point_end_index\":" << leg.point_end_index;
        if (!leg.route.failure_reason.empty())
            out << ",\"failure_reason\":\"" << leg.route.failure_reason << "\"";
        out << '}';
    }
    out << "]";

    out << ",\"points\":[";
    for (std::size_t i = 0; i < plan.points.size(); ++i) {
        if (i) out << ',';
        out << '[' << plan.points[i].x << ',' << plan.points[i].y << ']';
    }
    out << "]}\n";
    return out.str();
}

std::string plan_snap_failure_json(std::size_t failed_stop_index, RoutingPreference preference,
                                   double snap_ms) {
    const std::size_t failed_leg = failed_stop_index == 0 ? 0 : failed_stop_index - 1;
    std::ostringstream out;
    out << std::setprecision(12)
        << "{\"success\":false"
        << ",\"preference\":\"" << preference_name(preference) << "\""
        << ",\"adapter_error\":\"snap_failed\""
        << ",\"failure_reason\":\"snap_failed\""
        << ",\"failed_stop_index\":" << failed_stop_index
        << ",\"failed_leg_index\":" << failed_leg
        << ",\"snap_ms\":" << snap_ms
        << ",\"route_ms\":0"
        << ",\"points\":[],\"legs\":[]}\n";
    return out.str();
}

bool send_all(int fd, const std::string &payload) {
    size_t sent = 0;
    while (sent < payload.size()) {
        const ssize_t count = send(fd, payload.data() + sent, payload.size() - sent, 0);
        if (count <= 0) return false;
        sent += static_cast<size_t>(count);
    }
    return true;
}

std::string handle_plan_query(std::istringstream &input, SnapIndex &snap_index, Router &router) {
    std::string preference_text;
    std::size_t stop_count = 0;
    if (!(input >> preference_text >> stop_count) || stop_count < 2 || stop_count > MAX_PLAN_STOPS)
        return "{\"success\":false,\"adapter_error\":\"bad_plan\"}\n";
    const RoutingPreference preference = parse_preference(preference_text);

    std::vector<std::pair<double, double>> coordinates;
    coordinates.reserve(stop_count);
    for (std::size_t i = 0; i < stop_count; ++i) {
        double x = 0.0;
        double y = 0.0;
        if (!(input >> x >> y))
            return "{\"success\":false,\"adapter_error\":\"bad_plan\"}\n";
        coordinates.emplace_back(x, y);
    }

    std::vector<SnappedPlanStop> stops;
    stops.reserve(stop_count);
    double total_snap_ms = 0.0;
    for (std::size_t i = 0; i < coordinates.size(); ++i) {
        const auto started = std::chrono::steady_clock::now();
        const Snap snap = snap_index.snap(coordinates[i].first, coordinates[i].second);
        const auto finished = std::chrono::steady_clock::now();
        const double snap_ms = elapsed_ms(started, finished);
        total_snap_ms += snap_ms;
        if (!snap.ok) return plan_snap_failure_json(i, preference, total_snap_ms);
        stops.push_back({snap, snap_ms});
    }

    const auto route_started = std::chrono::steady_clock::now();
    const auto plan = brur::gps::execute_route_plan(
        stops,
        [&router, preference](const SnappedPlanStop &from, const SnappedPlanStop &to, std::size_t) {
            return to_plan_leg(route_with_polyline(router, from.snap, to.snap, preference));
        });
    const auto route_finished = std::chrono::steady_clock::now();
    return plan_json(stops, plan, preference, total_snap_ms,
                     elapsed_ms(route_started, route_finished));
}

std::string handle_query(const std::string &line, SnapIndex &snap_index, Router &router) {
    std::istringstream input(line);
    std::string first;
    if (!(input >> first)) return "{\"success\":false,\"adapter_error\":\"bad_request\"}\n";
    if (first == "plan") return handle_plan_query(input, snap_index, router);

    double start_x = 0.0;
    try {
        start_x = std::stod(first);
    } catch (...) {
        return "{\"success\":false,\"adapter_error\":\"bad_request\"}\n";
    }
    double start_y = 0.0;
    double target_x = 0.0;
    double target_y = 0.0;
    std::string preference_text = "fastest";
    if (!(input >> start_y >> target_x >> target_y))
        return "{\"success\":false,\"adapter_error\":\"bad_request\"}\n";
    input >> preference_text;
    const RoutingPreference preference = parse_preference(preference_text);

    const auto a = std::chrono::steady_clock::now();
    const Snap start = snap_index.snap(start_x, start_y);
    const auto b = std::chrono::steady_clock::now();
    const Snap target = snap_index.snap(target_x, target_y);
    const auto c = std::chrono::steady_clock::now();
    const RoutePolylineResult route = route_with_polyline(router, start, target, preference);
    const auto d = std::chrono::steady_clock::now();
    return route_json(start, target, route, preference,
                      elapsed_ms(a, b), elapsed_ms(b, c), elapsed_ms(c, d));
}

uint64_t warm_mapped_file(const MappedFile &file) {
    if (file.data == nullptr || file.size == 0) return 0;
    (void)madvise(const_cast<uint8_t *>(file.data), file.size, MADV_WILLNEED);
    const long configured_page_size = sysconf(_SC_PAGESIZE);
    const size_t page_size = configured_page_size > 0 ? static_cast<size_t>(configured_page_size) : 4096u;
    uint64_t checksum = 0;
    for (size_t offset = 0; offset < file.size; offset += page_size) checksum += file.data[offset];
    checksum += file.data[file.size - 1];
    return checksum;
}

void lower_background_priority() {
    if (setpriority(PRIO_PROCESS, 0, 8) != 0)
        std::cerr << "[native-gps-server] warning: could not lower process priority\n";
}
} // namespace

int main(int argc, char **argv) {
    try {
        const std::string graph_path = argc > 1 ? argv[1] : "world_data/routing.brg";
        const std::string snap_path = argc > 2 ? argv[2] : "world_data/routing_snap.brs";
        const int port = argc > 3 ? std::stoi(argv[3]) : 47741;

        lower_background_priority();
        const auto started = std::chrono::steady_clock::now();
        Graph graph(graph_path);
        SnapIndex snap_index(graph, snap_path);
        Router router(graph, snap_index.max_legal_speed_kmh);

        const auto warm_started = std::chrono::steady_clock::now();
        const uint64_t warm_checksum = warm_mapped_file(graph.file) ^ warm_mapped_file(snap_index.file);
        const auto warm_finished = std::chrono::steady_clock::now();

        const int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) throw std::runtime_error("socket failed");
        int reuse = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        sockaddr_in address {};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = htons(static_cast<uint16_t>(port));
        if (bind(server_fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
            close(server_fd);
            throw std::runtime_error("bind failed on localhost:" + std::to_string(port));
        }
        if (listen(server_fd, 1) != 0) {
            close(server_fd);
            throw std::runtime_error("listen failed");
        }

        std::cerr << "[native-gps-server] ready on 127.0.0.1:" << port
                  << " | startup " << elapsed_ms(started, std::chrono::steady_clock::now()) << " ms"
                  << " | page warm " << elapsed_ms(warm_started, warm_finished) << " ms"
                  << " | checksum " << warm_checksum << "\n";

        while (true) {
            const int client_fd = accept(server_fd, nullptr, nullptr);
            if (client_fd < 0) {
                if (errno == EINTR) continue;
                break;
            }
            std::string pending;
            char buffer[4096];
            bool connected = true;
            while (connected) {
                const ssize_t count = recv(client_fd, buffer, sizeof(buffer), 0);
                if (count <= 0) break;
                pending.append(buffer, static_cast<size_t>(count));
                while (true) {
                    const size_t newline = pending.find('\n');
                    if (newline == std::string::npos) break;
                    const std::string line = pending.substr(0, newline);
                    pending.erase(0, newline + 1);
                    if (line.empty()) continue;
                    try {
                        if (!send_all(client_fd, handle_query(line, snap_index, router))) {
                            connected = false;
                            break;
                        }
                    } catch (const std::exception &error) {
                        std::ostringstream response;
                        response << "{\"success\":false,\"adapter_error\":\"" << error.what() << "\"}\n";
                        if (!send_all(client_fd, response.str())) {
                            connected = false;
                            break;
                        }
                    }
                }
            }
            close(client_fd);
        }
        close(server_fd);
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "native gps server error: " << error.what() << "\n";
        return 1;
    }
}
