#include "gps_core.h"
#include "gps_mapped_data.h"

#include <chrono>
#include <cmath>
#include <iostream>
#include <string>

// Native GPS benchmark adapter over the same portable core used by CLI/TCP.
//
// Dependencies:
// - gps_core owns all routing semantics.
// - gps_mapped_data owns POSIX file mapping.
// - This file owns benchmark scenarios and console output only.

namespace {
constexpr double EARTH_RADIUS = 6378137.0;
constexpr double PI = 3.14159265358979323846;

double project_x(double lon) { return EARTH_RADIUS * lon * PI / 180.0; }
double project_y(double lat) {
    const double radians = lat * PI / 180.0;
    return EARTH_RADIUS * std::log(std::tan(PI / 4.0 + radians / 2.0));
}

template <class A, class B>
double elapsed_ms(A a, B b) {
    return std::chrono::duration<double, std::milli>(b - a).count();
}

void benchmark_case(brur::gps::RoutingContext &core, const char *name,
                    double start_lon, double start_lat, double target_lon, double target_lat) {
    using namespace brur::gps;
    const auto a = std::chrono::steady_clock::now();
    const auto start = core.snap({project_x(start_lon), project_y(start_lat)});
    const auto b = std::chrono::steady_clock::now();
    const auto target = core.snap({project_x(target_lon), project_y(target_lat)});
    const auto c = std::chrono::steady_clock::now();
    const auto route = core.route({start, target, RoutingPreference::Fastest});
    const auto d = std::chrono::steady_clock::now();

    std::cout << "[native-gps] " << name << " start snap: " << elapsed_ms(a, b)
              << " ms | candidates " << start.candidates << "\n";
    std::cout << "[native-gps] " << name << " target snap: " << elapsed_ms(b, c)
              << " ms | candidates " << target.candidates << "\n";
    std::cout << "[native-gps] " << name << " fastest: " << elapsed_ms(c, d)
              << " ms | settled " << route.metrics.settled
              << " | relaxed " << route.metrics.relaxed
              << " | queue peak " << route.metrics.queue_peak << "\n";
    if (route.success) {
        std::cout << "[native-gps]   " << route.metrics.distance_m / 1000.0 << " km | "
                  << route.metrics.travel_time_s / 60.0 << " min | "
                  << route.metrics.steps << " steps\n";
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
        brur::gps::adapter::MappedRoutingData mapped(graph_path, snap_path);
        brur::gps::RoutingContext core(mapped.view());
        std::cout << "[native-gps] graph: " << core.node_count() << " nodes, "
                  << core.edge_count() << " directed edges | startup "
                  << elapsed_ms(started, std::chrono::steady_clock::now()) << " ms\n";
        benchmark_case(core, "city", 18.0686, 59.3293, 18.0009, 59.3600);
        benchmark_case(core, "regional", 18.0686, 59.3293, 17.6389, 59.8586);
        benchmark_case(core, "long", 18.0686, 59.3293, 11.9746, 57.7089);
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "native gps error: " << error.what() << "\n";
        return 1;
    }
}
