#pragma once

#include "gps_route_plan.h"

#include <cstddef>
#include <sstream>
#include <string>
#include <vector>

// Portable parser for the one-line native GPS waypoint request contract.
//
// Dependencies:
// - Standard C++20 plus gps_route_plan.h data types.
// - No sockets, filesystem, Godot or routing graph dependency.

namespace brur::gps {

constexpr std::size_t MAX_ROUTE_PLAN_STOPS = 32;

struct RoutePlanCommand {
    std::string preference;
    std::vector<RoutePlanPoint> stops;
};

struct RoutePlanParseResult {
    bool success = false;
    std::string error;
    RoutePlanCommand request;
};

inline RoutePlanParseResult parse_route_plan_request(const std::string &line) {
    RoutePlanParseResult result;
    std::istringstream input(line);
    std::string command;
    std::size_t stop_count = 0;
    if (!(input >> command >> result.request.preference >> stop_count) || command != "plan") {
        result.error = "bad_plan";
        return result;
    }
    if (result.request.preference.empty() || stop_count < 2 || stop_count > MAX_ROUTE_PLAN_STOPS) {
        result.error = "bad_plan";
        return result;
    }

    result.request.stops.reserve(stop_count);
    for (std::size_t i = 0; i < stop_count; ++i) {
        RoutePlanPoint point;
        if (!(input >> point.x >> point.y)) {
            result.error = "bad_plan";
            result.request.stops.clear();
            return result;
        }
        result.request.stops.push_back(point);
    }

    std::string trailing;
    if (input >> trailing) {
        result.error = "bad_plan";
        result.request.stops.clear();
        return result;
    }

    result.success = true;
    return result;
}

} // namespace brur::gps
