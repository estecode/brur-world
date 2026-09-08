#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string_view>
#include <vector>

// Portable native GPS routing core over immutable BRG1/BRS2 byte views.
//
// Dependencies:
// - Standard C++20 only.
// - Consumes caller-owned read-only bytes; adapters own files/mmap/sockets/CLI.
// - Uses gps_route_plan.h only for portable ordered-leg aggregation.

namespace brur::gps {

struct ByteView {
    const std::uint8_t *data = nullptr;
    std::size_t size = 0;
};

struct RoutingDataView {
    ByteView graph;
    ByteView snap;
};

enum class RoutingPreference : std::uint8_t {
    Fastest,
    Shortest,
    AvoidSmallRoads,
    AvoidMajorRoads,
};

enum class RouteFailure : std::uint8_t {
    None,
    InvalidData,
    SnapFailed,
    Unreachable,
};

const char *routing_preference_name(RoutingPreference preference);
bool parse_routing_preference(std::string_view text, RoutingPreference &out);
const char *route_failure_name(RouteFailure failure);

struct RoutePoint {
    double x = 0.0;
    double y = 0.0;
};

struct DirectedSnap {
    std::uint32_t edge_index = 0;
    double fraction = 0.0;
};

struct SnappedPosition {
    bool success = false;
    RouteFailure failure = RouteFailure::SnapFailed;
    RoutePoint point;
    double distance_m = 0.0;
    std::size_t candidates = 0;
    std::vector<DirectedSnap> directions;
};

struct RouteMetrics {
    double cost = 0.0;
    double distance_m = 0.0;
    double travel_time_s = 0.0;
    std::uint64_t settled = 0;
    std::uint64_t relaxed = 0;
    std::size_t queue_peak = 0;
    std::size_t steps = 0;
};

struct RouteLegResult {
    bool success = false;
    RouteFailure failure = RouteFailure::Unreachable;
    std::size_t leg_index = 0;
    std::size_t from_stop_index = 0;
    std::size_t to_stop_index = 0;
    std::size_t point_start_index = 0;
    std::size_t point_end_index = 0;
    RouteMetrics metrics;
    std::vector<RoutePoint> points;
    std::vector<std::uint32_t> edge_indices;
};

struct RouteResult {
    bool success = false;
    RouteFailure failure = RouteFailure::Unreachable;
    std::size_t failed_leg_index = static_cast<std::size_t>(-1);
    RoutingPreference preference = RoutingPreference::Fastest;
    RouteMetrics metrics;
    std::vector<RoutePoint> snaps;
    std::vector<std::size_t> snap_candidates;
    std::vector<RoutePoint> points;
    std::vector<RouteLegResult> legs;
};

struct RouteRequest {
    SnappedPosition start;
    SnappedPosition target;
    RoutingPreference preference = RoutingPreference::Fastest;
};

struct RoutePlanRequest {
    std::vector<SnappedPosition> stops;
    RoutingPreference preference = RoutingPreference::Fastest;
};

class RoutingContext {
public:
    explicit RoutingContext(const RoutingDataView &data);
    ~RoutingContext();
    RoutingContext(RoutingContext &&) noexcept;
    RoutingContext &operator=(RoutingContext &&) noexcept;
    RoutingContext(const RoutingContext &) = delete;
    RoutingContext &operator=(const RoutingContext &) = delete;

    std::uint32_t node_count() const;
    std::uint32_t edge_count() const;
    double max_legal_speed_kmh() const;

    SnappedPosition snap(RoutePoint point, double max_distance_m = 250.0) const;
    RouteResult route(const RouteRequest &request);
    RouteResult route_plan(const RoutePlanRequest &request);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace brur::gps
