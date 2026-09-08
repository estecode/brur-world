#include "../../native/gps_core.h"

#include <cassert>
#include <cmath>
#include <cstring>
#include <iostream>
#include <vector>

// Deterministic contracts for the portable native GPS core using in-memory BRG1/BRS2 bytes.
//
// Dependencies:
// - gps_core only; no files, mmap, sockets, JSON, Godot or Sweden data.

namespace {
using namespace brur::gps;

template <class T>
void put(std::vector<std::uint8_t> &bytes, std::size_t offset, T value) {
    std::memcpy(bytes.data() + offset, &value, sizeof(T));
}

struct Fixture {
    std::vector<std::uint8_t> graph;
    std::vector<std::uint8_t> snap;
};

Fixture fixture() {
    constexpr std::uint32_t node_count = 6;
    constexpr std::uint32_t edge_count = 7;
    constexpr std::size_t header = 12;
    constexpr std::size_t node_size = 40;
    constexpr std::size_t edge_size = 34;

    Fixture result;
    result.graph.assign(header + node_count * node_size + edge_count * edge_size, 0);
    std::memcpy(result.graph.data(), "BRG1", 4);
    put(result.graph, 4, node_count);
    put(result.graph, 8, edge_count);

    struct N { float x; float y; std::uint32_t offset; std::uint32_t count; };
    const N nodes[] = {
        {0, 0, 0, 1}, {10, 0, 1, 2}, {110, 100, 3, 1}, {500, 500, 4, 0},
        {210, 0, 4, 3}, {220, 0, 7, 0},
    };
    for (std::uint32_t i = 0; i < node_count; ++i) {
        const auto o = header + i * node_size;
        put<std::int64_t>(result.graph, o, 100 + i);
        put<double>(result.graph, o + 8, 13.0 + i * 0.001);
        put<double>(result.graph, o + 16, 55.0);
        put<float>(result.graph, o + 24, nodes[i].x);
        put<float>(result.graph, o + 28, nodes[i].y);
        put(result.graph, o + 32, nodes[i].offset);
        put(result.graph, o + 36, nodes[i].count);
    }

    struct E {
        std::uint32_t source;
        std::uint32_t target;
        float length;
        float speed;
        std::uint8_t road_class;
        std::uint8_t access;
        std::uint8_t flags;
        std::int64_t way;
    };
    const E edges[] = {
        {0, 1, 10, 50, 2, 0, 0, 1},
        {1, 2, 120, 120, 2, 0, 0, 10},
        {1, 4, 100, 20, 11, 0, 0, 20},
        {2, 4, 120, 120, 2, 0, 0, 10},
        {4, 5, 10, 50, 2, 0, 0, 30},
        {4, 1, 100, 50, 2, 0, 1, 40},
        {4, 1, 100, 50, 2, 2, 0, 41},
    };
    const auto edge_table = header + node_count * node_size;
    for (std::uint32_t i = 0; i < edge_count; ++i) {
        const auto o = edge_table + i * edge_size;
        put(result.graph, o, edges[i].way);
        put<std::uint32_t>(result.graph, o + 8, i);
        put(result.graph, o + 12, edges[i].source);
        put(result.graph, o + 16, edges[i].target);
        put(result.graph, o + 20, edges[i].length);
        put(result.graph, o + 24, edges[i].speed);
        result.graph[o + 28] = edges[i].road_class;
        result.graph[o + 29] = edges[i].access;
        result.graph[o + 30] = edges[i].flags;
    }

    constexpr std::size_t brs_header = 20;
    constexpr std::size_t cell_size = 16;
    result.snap.assign(brs_header + cell_size + edge_count * 4, 0);
    std::memcpy(result.snap.data(), "BRS2", 4);
    put<float>(result.snap, 4, 1000.0f);
    put<std::uint32_t>(result.snap, 8, 1);
    put<std::uint32_t>(result.snap, 12, edge_count);
    put<float>(result.snap, 16, 120.0f);
    put<std::int32_t>(result.snap, 20, 0);
    put<std::int32_t>(result.snap, 24, 0);
    put<std::uint32_t>(result.snap, 28, 0);
    put<std::uint32_t>(result.snap, 32, edge_count);
    for (std::uint32_t i = 0; i < edge_count; ++i)
        put<std::uint32_t>(result.snap, brs_header + cell_size + i * 4, i);
    return result;
}

SnappedPosition position(double x, double y, std::uint32_t edge, double fraction) {
    SnappedPosition result;
    result.success = true;
    result.failure = RouteFailure::None;
    result.point = {x, y};
    result.directions = {{edge, fraction}};
    return result;
}

std::vector<std::uint32_t> edge_indices(const RouteResult &route) {
    std::vector<std::uint32_t> result;
    for (const auto &leg : route.legs)
        result.insert(result.end(), leg.edge_indices.begin(), leg.edge_indices.end());
    return result;
}

void test_preferences_and_determinism() {
    auto data = fixture();
    RoutingContext core({{data.graph.data(), data.graph.size()}, {data.snap.data(), data.snap.size()}});
    const auto start = position(10, 0, 0, 1.0);
    const auto target = position(210, 0, 4, 0.0);

    auto fastest = core.route({start, target, RoutingPreference::Fastest});
    auto shortest = core.route({start, target, RoutingPreference::Shortest});
    auto avoid_small = core.route({start, target, RoutingPreference::AvoidSmallRoads});
    auto avoid_major = core.route({start, target, RoutingPreference::AvoidMajorRoads});

    assert(fastest.success && shortest.success && avoid_small.success && avoid_major.success);
    assert((edge_indices(fastest) == std::vector<std::uint32_t>{1, 3}));
    assert((edge_indices(shortest) == std::vector<std::uint32_t>{2}));
    assert((edge_indices(avoid_small) == std::vector<std::uint32_t>{1, 3}));
    assert((edge_indices(avoid_major) == std::vector<std::uint32_t>{2}));
    assert(shortest.metrics.distance_m < fastest.metrics.distance_m);
    assert(fastest.metrics.travel_time_s < shortest.metrics.travel_time_s);

    auto repeated = core.route({start, target, RoutingPreference::Fastest});
    assert(edge_indices(repeated) == edge_indices(fastest));
    assert(repeated.metrics.distance_m == fastest.metrics.distance_m);
    assert(repeated.metrics.travel_time_s == fastest.metrics.travel_time_s);
}

void test_same_edge_route() {
    auto data = fixture();
    RoutingContext core({{data.graph.data(), data.graph.size()}, {data.snap.data(), data.snap.size()}});
    const auto route = core.route({position(30, 0, 2, 0.2), position(90, 0, 2, 0.8), RoutingPreference::Fastest});
    assert(route.success);
    assert(route.metrics.steps == 1);
    assert((edge_indices(route) == std::vector<std::uint32_t>{2}));
    assert(std::abs(route.metrics.distance_m - 60.0) < 1e-6);
}

void test_oneway_and_access_edges_are_not_traversed() {
    auto data = fixture();
    RoutingContext core({{data.graph.data(), data.graph.size()}, {data.snap.data(), data.snap.size()}});
    const auto route = core.route({position(210, 0, 3, 1.0), position(10, 0, 1, 0.0), RoutingPreference::Fastest});
    assert(!route.success);
    assert(route.failure == RouteFailure::Unreachable);
}

void test_ordered_plan_and_failed_leg() {
    auto data = fixture();
    RoutingContext core({{data.graph.data(), data.graph.size()}, {data.snap.data(), data.snap.size()}});

    RoutePlanRequest ok;
    ok.stops = {position(10, 0, 0, 1.0), position(210, 0, 4, 0.0), position(215, 0, 4, 0.5)};
    const auto result = core.route_plan(ok);
    assert(result.success);
    assert(result.legs.size() == 2);
    assert(result.legs[0].from_stop_index == 0 && result.legs[0].to_stop_index == 1);
    assert(result.legs[1].from_stop_index == 1 && result.legs[1].to_stop_index == 2);

    RoutePlanRequest bad;
    bad.stops = {position(10, 0, 0, 1.0), position(210, 0, 4, 0.0), position(10, 0, 1, 0.0)};
    const auto failed = core.route_plan(bad);
    assert(!failed.success);
    assert(failed.failed_leg_index == 1);
    assert(failed.failure == RouteFailure::Unreachable);
}

void test_snap_contract() {
    auto data = fixture();
    RoutingContext core({{data.graph.data(), data.graph.size()}, {data.snap.data(), data.snap.size()}});
    const auto near = core.snap({5, 1}, 10);
    assert(near.success);
    assert(near.candidates == 7);
    assert(std::abs(near.point.y) < 1e-6);
    const auto far = core.snap({900, 900}, 5);
    assert(!far.success);
    assert(far.failure == RouteFailure::SnapFailed);
}
} // namespace

int main() {
    test_preferences_and_determinism();
    test_same_edge_route();
    test_oneway_and_access_edges_are_not_traversed();
    test_ordered_plan_and_failed_leg();
    test_snap_contract();
    std::cout << "native gps core tests: OK\n";
    return 0;
}
