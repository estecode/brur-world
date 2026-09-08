#include "gps_core.h"
#include "gps_mapped_data.h"

#include <chrono>
#include <iomanip>
#include <iostream>
#include <string>

// Machine-readable one-route CLI adapter over the portable GPS core.
//
// Dependencies:
// - gps_core owns snapping, legality, preferences and routing.
// - gps_mapped_data owns POSIX file mapping.
// - This file owns argv parsing and stdout JSON only.

namespace {
template <class A, class B>
double elapsed_ms(A a, B b) {
    return std::chrono::duration<double, std::milli>(b - a).count();
}
} // namespace

int main(int argc, char **argv) {
    using namespace brur::gps;
    try {
        if (argc < 5) {
            std::cerr << "usage: brur-gps-route START_X START_Y TARGET_X TARGET_Y "
                         "[routing.brg] [routing_snap.brs] [preference]\n";
            return 2;
        }
        const double start_x = std::stod(argv[1]);
        const double start_y = std::stod(argv[2]);
        const double target_x = std::stod(argv[3]);
        const double target_y = std::stod(argv[4]);
        const std::string graph_path = argc > 5 ? argv[5] : "world_data/routing.brg";
        const std::string snap_path = argc > 6 ? argv[6] : "world_data/routing_snap.brs";
        RoutingPreference preference = RoutingPreference::Fastest;
        if (argc > 7 && !parse_routing_preference(argv[7], preference)) {
            std::cerr << "unknown routing preference\n";
            return 2;
        }

        adapter::MappedRoutingData mapped(graph_path, snap_path);
        RoutingContext core(mapped.view());

        const auto a = std::chrono::steady_clock::now();
        const auto start = core.snap({start_x, start_y});
        const auto b = std::chrono::steady_clock::now();
        const auto target = core.snap({target_x, target_y});
        const auto c = std::chrono::steady_clock::now();
        const auto route = core.route({start, target, preference});
        const auto d = std::chrono::steady_clock::now();

        std::cout << std::setprecision(12)
                  << "{\"success\":" << (route.success ? "true" : "false")
                  << ",\"preference\":\"" << routing_preference_name(preference) << "\""
                  << ",\"start_snap_ms\":" << elapsed_ms(a, b)
                  << ",\"target_snap_ms\":" << elapsed_ms(b, c)
                  << ",\"route_ms\":" << elapsed_ms(c, d)
                  << ",\"start_candidates\":" << start.candidates
                  << ",\"target_candidates\":" << target.candidates
                  << ",\"settled\":" << route.metrics.settled
                  << ",\"relaxed\":" << route.metrics.relaxed
                  << ",\"queue_peak\":" << route.metrics.queue_peak
                  << ",\"distance_m\":" << route.metrics.distance_m
                  << ",\"travel_time_s\":" << route.metrics.travel_time_s
                  << ",\"steps\":" << route.metrics.steps;
        if (route.failure != RouteFailure::None)
            std::cout << ",\"failure_reason\":\"" << route_failure_name(route.failure) << "\"";
        std::cout << ",\"start_snap\":[" << start.point.x << ',' << start.point.y << ']'
                  << ",\"target_snap\":[" << target.point.x << ',' << target.point.y << ']'
                  << ",\"points\":[";
        for (std::size_t i = 0; i < route.points.size(); ++i) {
            if (i) std::cout << ',';
            std::cout << '[' << route.points[i].x << ',' << route.points[i].y << ']';
        }
        std::cout << "],\"edge_indices\":[";
        bool first_edge = true;
        for (const auto &leg : route.legs) {
            for (auto edge_index : leg.edge_indices) {
                if (!first_edge) std::cout << ',';
                first_edge = false;
                std::cout << edge_index;
            }
        }
        std::cout << "]}\n";
        return route.success ? 0 : 3;
    } catch (const std::exception &error) {
        std::cerr << "native gps route error: " << error.what() << "\n";
        return 1;
    }
}
