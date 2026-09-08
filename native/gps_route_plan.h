#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

// Portable ordered route-plan core for GPS waypoints.
//
// Dependencies:
// - Standard C++20 only; no Godot, sockets, filesystem or routing-file dependency.
// - A caller supplies stops of any type plus a callback that routes one adjacent leg.
// - The callback returns RoutePlanLegOutput; this module only preserves leg order,
//   aggregates metrics and merges geometry without duplicate boundary points.

namespace brur::gps {

struct RoutePlanPoint {
    double x = 0.0;
    double y = 0.0;
};

struct RoutePlanLegOutput {
    bool success = false;
    std::string failure_reason;
    double cost = 0.0;
    double distance_m = 0.0;
    double travel_time_s = 0.0;
    uint64_t settled = 0;
    uint64_t relaxed = 0;
    std::size_t queue_peak = 0;
    std::size_t steps = 0;
    std::vector<RoutePlanPoint> points;
};

struct RoutePlanLeg {
    std::size_t leg_index = 0;
    std::size_t from_stop_index = 0;
    std::size_t to_stop_index = 0;
    std::size_t point_start_index = 0;
    std::size_t point_end_index = 0;
    RoutePlanLegOutput route;
};

struct RoutePlanResult {
    bool success = false;
    std::string failure_reason;
    std::size_t failed_leg_index = static_cast<std::size_t>(-1);
    double cost = 0.0;
    double distance_m = 0.0;
    double travel_time_s = 0.0;
    uint64_t settled = 0;
    uint64_t relaxed = 0;
    std::size_t queue_peak = 0;
    std::size_t steps = 0;
    std::vector<RoutePlanPoint> points;
    std::vector<RoutePlanLeg> legs;
};

inline bool same_point(const RoutePlanPoint &a, const RoutePlanPoint &b) {
    return a.x == b.x && a.y == b.y;
}

inline void append_leg_points(std::vector<RoutePlanPoint> &target,
                              const std::vector<RoutePlanPoint> &source) {
    for (const RoutePlanPoint &point : source) {
        if (!target.empty() && same_point(target.back(), point)) continue;
        target.push_back(point);
    }
}

template <class Stop, class RouteLegFn>
RoutePlanResult execute_route_plan(const std::vector<Stop> &stops, RouteLegFn route_leg) {
    RoutePlanResult result;
    if (stops.size() < 2) {
        result.failure_reason = "no_destination";
        result.failed_leg_index = 0;
        return result;
    }

    result.legs.reserve(stops.size() - 1);
    for (std::size_t leg_index = 0; leg_index + 1 < stops.size(); ++leg_index) {
        RoutePlanLeg leg;
        leg.leg_index = leg_index;
        leg.from_stop_index = leg_index;
        leg.to_stop_index = leg_index + 1;
        leg.point_start_index = result.points.empty() ? 0 : result.points.size() - 1;
        leg.route = route_leg(stops[leg_index], stops[leg_index + 1], leg_index);

        if (!leg.route.success) {
            leg.point_end_index = leg.point_start_index;
            result.legs.push_back(std::move(leg));
            result.failure_reason = result.legs.back().route.failure_reason.empty()
                ? "unreachable"
                : result.legs.back().route.failure_reason;
            result.failed_leg_index = leg_index;
            return result;
        }

        append_leg_points(result.points, leg.route.points);
        leg.point_end_index = result.points.empty() ? 0 : result.points.size() - 1;
        result.cost += leg.route.cost;
        result.distance_m += leg.route.distance_m;
        result.travel_time_s += leg.route.travel_time_s;
        result.settled += leg.route.settled;
        result.relaxed += leg.route.relaxed;
        result.queue_peak = std::max(result.queue_peak, leg.route.queue_peak);
        result.steps += leg.route.steps;
        result.legs.push_back(std::move(leg));
    }

    result.success = true;
    return result;
}

} // namespace brur::gps
