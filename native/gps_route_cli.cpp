#define main brur_native_benchmark_main
#include "gps_runtime.cpp"
#undef main

#include <iomanip>
#include <sstream>

// Thin machine-readable adapter used by Godot for the issue #4 gameplay POC.
//
// Dependencies:
// - gps_runtime.cpp owns BRG1/BRS2 loading, snapping, legality and A* primitives.
// - This file only exposes one world-coordinate route request as JSON.
// - No routing data or graph preprocessing is duplicated in Godot/GDScript.

namespace {
struct RoutePolylineResult {
    RouteResult metrics;
    std::vector<std::pair<double, double>> points;
};

void append_point(std::vector<std::pair<double, double>> &points, double x, double y) {
    if (!points.empty()) {
        const auto &last = points.back();
        if (std::abs(last.first - x) < 1e-6 && std::abs(last.second - y) < 1e-6) return;
    }
    points.emplace_back(x, y);
}

RoutePolylineResult route_with_polyline(Router &router, const Snap &start, const Snap &target) {
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
            const double cost = router.edge_cost(edge) * fraction;
            if (!have_direct || cost < direct_cost) {
                have_direct = true;
                direct_cost = cost;
                direct_distance = edge.length_m * fraction;
                direct_time = router.edge_cost(edge) * fraction;
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
        terminals.push_back({edge.source, snap.edge_index, router.edge_cost(edge) * snap.fraction, snap.fraction});
        target_nodes.push_back(edge.source);
    }
    std::sort(target_nodes.begin(), target_nodes.end());
    target_nodes.erase(std::unique(target_nodes.begin(), target_nodes.end()), target_nodes.end());

    std::priority_queue<QueueItem, std::vector<QueueItem>, QueueCompare> queue;
    for (const DirectedSnap &snap : start.directions) {
        const Edge edge = router.graph.edge(snap.edge_index);
        const double cost = router.edge_cost(edge) * (1.0 - snap.fraction);
        const uint32_t node = edge.target;
        if (router.epoch[node] != router.current_epoch || cost < router.distance[node]) {
            router.epoch[node] = router.current_epoch;
            router.distance[node] = cost;
            router.parent_node[node] = UINT32_MAX;
            router.parent_edge[node] = UINT32_MAX;
            router.seed_edge[node] = snap.edge_index;
            queue.push({cost + router.heuristic(node, target_nodes), cost, node});
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
            const double candidate = item.cost + router.edge_cost(edge);
            if (router.epoch[edge.target] != router.current_epoch || candidate < router.distance[edge.target] - 1e-12) {
                router.epoch[edge.target] = router.current_epoch;
                router.distance[edge.target] = candidate;
                router.parent_node[edge.target] = item.node;
                router.parent_edge[edge.target] = edge_index;
                router.seed_edge[edge.target] = router.seed_edge[item.node];
                const double estimate = candidate + router.heuristic(edge.target, target_nodes);
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
    result.travel_time_s += router.edge_cost(start_edge) * start_part;
    if (start_part > 1e-12) ++result.steps;

    append_point(output.points, start.x, start.y);
    if (start_part > 1e-12) {
        const Node node = router.graph.node(start_edge.target);
        append_point(output.points, node.x, node.y);
    }

    for (uint32_t edge_index : middle_edges) {
        const Edge edge = router.graph.edge(edge_index);
        result.distance_m += edge.length_m;
        result.travel_time_s += router.edge_cost(edge);
        ++result.steps;
        const Node node = router.graph.node(edge.target);
        append_point(output.points, node.x, node.y);
    }

    double target_fraction = 0.0;
    for (const DirectedSnap &snap : target.directions)
        if (snap.edge_index == best_target_edge) target_fraction = snap.fraction;
    const Edge target_edge = router.graph.edge(best_target_edge);
    result.distance_m += target_edge.length_m * target_fraction;
    result.travel_time_s += router.edge_cost(target_edge) * target_fraction;
    if (target_fraction > 1e-12) ++result.steps;
    append_point(output.points, target.x, target.y);
    return output;
}

void print_json(const Snap &start, const Snap &target, const RoutePolylineResult &route,
                double start_snap_ms, double target_snap_ms, double route_ms) {
    std::cout << std::setprecision(12);
    std::cout << "{\"success\":" << (route.metrics.ok ? "true" : "false")
              << ",\"start_snap_ms\":" << start_snap_ms
              << ",\"target_snap_ms\":" << target_snap_ms
              << ",\"route_ms\":" << route_ms
              << ",\"start_candidates\":" << start.candidates
              << ",\"target_candidates\":" << target.candidates
              << ",\"settled\":" << route.metrics.settled
              << ",\"relaxed\":" << route.metrics.relaxed
              << ",\"queue_peak\":" << route.metrics.queue_peak
              << ",\"distance_m\":" << route.metrics.distance_m
              << ",\"travel_time_s\":" << route.metrics.travel_time_s
              << ",\"steps\":" << route.metrics.steps
              << ",\"start_snap\":[" << start.x << ',' << start.y << ']'
              << ",\"target_snap\":[" << target.x << ',' << target.y << ']'
              << ",\"points\":[";
    for (size_t i = 0; i < route.points.size(); ++i) {
        if (i) std::cout << ',';
        std::cout << '[' << route.points[i].first << ',' << route.points[i].second << ']';
    }
    std::cout << "]}\n";
}
} // namespace

int main(int argc, char **argv) {
    try {
        if (argc < 5) {
            std::cerr << "usage: brur-gps-route START_X START_Y TARGET_X TARGET_Y [routing.brg] [routing_snap.brs]\n";
            return 2;
        }
        const double start_x = std::stod(argv[1]);
        const double start_y = std::stod(argv[2]);
        const double target_x = std::stod(argv[3]);
        const double target_y = std::stod(argv[4]);
        const std::string graph_path = argc > 5 ? argv[5] : "world_data/routing.brg";
        const std::string snap_path = argc > 6 ? argv[6] : "world_data/routing_snap.brs";

        Graph graph(graph_path);
        SnapIndex snap_index(graph, snap_path);
        Router router(graph, snap_index.max_legal_speed_kmh);

        const auto a = std::chrono::steady_clock::now();
        const Snap start = snap_index.snap(start_x, start_y);
        const auto b = std::chrono::steady_clock::now();
        const Snap target = snap_index.snap(target_x, target_y);
        const auto c = std::chrono::steady_clock::now();
        const RoutePolylineResult route = route_with_polyline(router, start, target);
        const auto d = std::chrono::steady_clock::now();
        print_json(start, target, route, elapsed_ms(a, b), elapsed_ms(b, c), elapsed_ms(c, d));
        return route.metrics.ok ? 0 : 3;
    } catch (const std::exception &error) {
        std::cerr << "native gps route error: " << error.what() << "\n";
        return 1;
    }
}
