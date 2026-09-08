#include "../../native/gps_route_plan.h"

#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>

// Deterministic input -> expected-output contract tests for the portable waypoint core.
// Dependencies: native/gps_route_plan.h only; no Sweden data, sockets, Godot or filesystem.

namespace {
using brur::gps::RoutePlanLegOutput;
using brur::gps::RoutePlanPoint;
using brur::gps::execute_route_plan;

RoutePlanLegOutput successful_leg(int from, int to, std::size_t) {
    RoutePlanLegOutput result;
    result.success = true;
    result.cost = static_cast<double>(to - from) * 10.0;
    result.distance_m = static_cast<double>(to - from) * 100.0;
    result.travel_time_s = static_cast<double>(to - from) * 5.0;
    result.settled = static_cast<uint64_t>(from + to);
    result.relaxed = static_cast<uint64_t>((from + to) * 2);
    result.queue_peak = static_cast<std::size_t>(to);
    result.steps = static_cast<std::size_t>(to - from);
    result.points = {
        {static_cast<double>(from), 0.0},
        {static_cast<double>(to), 0.0},
    };
    return result;
}

void test_requires_destination() {
    const std::vector<int> stops = {1};
    const auto result = execute_route_plan(stops, successful_leg);
    assert(!result.success);
    assert(result.failure_reason == "no_destination");
    assert(result.failed_leg_index == 0);
    assert(result.legs.empty());
}

void test_direct_route_has_one_leg() {
    const std::vector<int> stops = {1, 4};
    const auto result = execute_route_plan(stops, successful_leg);
    assert(result.success);
    assert(result.legs.size() == 1);
    assert(result.legs[0].from_stop_index == 0);
    assert(result.legs[0].to_stop_index == 1);
    assert(result.distance_m == 300.0);
    assert(result.travel_time_s == 15.0);
    assert(result.points.size() == 2);
    assert(result.points.front().x == 1.0);
    assert(result.points.back().x == 4.0);
}

void test_multiple_waypoints_preserve_order_and_merge_boundaries() {
    const std::vector<int> stops = {1, 2, 3, 5};
    const auto result = execute_route_plan(stops, successful_leg);
    assert(result.success);
    assert(result.legs.size() == 3);
    assert(result.legs[0].from_stop_index == 0 && result.legs[0].to_stop_index == 1);
    assert(result.legs[1].from_stop_index == 1 && result.legs[1].to_stop_index == 2);
    assert(result.legs[2].from_stop_index == 2 && result.legs[2].to_stop_index == 3);
    assert(result.points.size() == 4);
    assert(result.points[0].x == 1.0);
    assert(result.points[1].x == 2.0);
    assert(result.points[2].x == 3.0);
    assert(result.points[3].x == 5.0);
    assert(result.distance_m == 400.0);
    assert(result.travel_time_s == 20.0);
    assert(result.cost == 40.0);
    assert(result.steps == 4);
    assert(result.queue_peak == 5);
}

void test_failed_middle_leg_is_reported_exactly() {
    const std::vector<int> stops = {1, 2, 3, 4};
    const auto result = execute_route_plan(
        stops,
        [](int from, int to, std::size_t leg_index) {
            if (leg_index == 1) {
                RoutePlanLegOutput failed;
                failed.success = false;
                failed.failure_reason = "unreachable";
                return failed;
            }
            return successful_leg(from, to, leg_index);
        });
    assert(!result.success);
    assert(result.failed_leg_index == 1);
    assert(result.failure_reason == "unreachable");
    assert(result.legs.size() == 2);
    assert(result.legs[0].route.success);
    assert(!result.legs[1].route.success);
    assert(result.distance_m == 100.0);
    assert(result.points.size() == 2);
}

void test_same_input_is_deterministic() {
    const std::vector<int> stops = {1, 2, 4};
    const auto first = execute_route_plan(stops, successful_leg);
    const auto second = execute_route_plan(stops, successful_leg);
    assert(first.success == second.success);
    assert(first.distance_m == second.distance_m);
    assert(first.travel_time_s == second.travel_time_s);
    assert(first.points.size() == second.points.size());
    for (std::size_t i = 0; i < first.points.size(); ++i) {
        assert(first.points[i].x == second.points[i].x);
        assert(first.points[i].y == second.points[i].y);
    }
}
} // namespace

int main() {
    test_requires_destination();
    test_direct_route_has_one_leg();
    test_multiple_waypoints_preserve_order_and_merge_boundaries();
    test_failed_middle_leg_is_reported_exactly();
    test_same_input_is_deterministic();
    std::cout << "native gps route-plan tests: OK\n";
    return 0;
}
