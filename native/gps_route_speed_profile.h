#pragma once

#include "gps_core.h"
#include "gps_route_geometry.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <vector>

// Builds a per-route-point speed profile from the authoritative BRG1 edge metadata.
//
// Dependencies:
// - Consumes immutable BRG1 bytes, chosen route edge indices and BRH1 route geometry.
// - Does not choose routes, alter geometry, perform I/O or know about JSON/Godot.

namespace brur::gps {

class RoutingSpeedView {
public:
    explicit RoutingSpeedView(ByteView bytes) : bytes_(bytes) {
        constexpr std::size_t header_size = 12;
        constexpr std::size_t node_record_size = 40;
        constexpr std::size_t edge_record_size = 34;
        if (!bytes_.data || bytes_.size < header_size || std::memcmp(bytes_.data, "BRG1", 4) != 0)
            throw std::runtime_error("bad BRG1 speed data");
        node_count_ = read<std::uint32_t>(bytes_.data + 4);
        edge_count_ = read<std::uint32_t>(bytes_.data + 8);
        edge_table_offset_ = header_size + static_cast<std::size_t>(node_count_) * node_record_size;
        if (edge_table_offset_ + static_cast<std::size_t>(edge_count_) * edge_record_size != bytes_.size)
            throw std::runtime_error("BRG1 speed size mismatch");
    }

    std::uint32_t edge_count() const { return edge_count_; }

    float speed_mps(std::uint32_t edge_index) const {
        constexpr std::size_t edge_record_size = 34;
        constexpr std::size_t speed_offset = 24;
        if (edge_index >= edge_count_) throw std::runtime_error("BRG1 speed edge index out of range");
        const auto *p = bytes_.data + edge_table_offset_ + static_cast<std::size_t>(edge_index) * edge_record_size;
        const float speed_kmh = read<float>(p + speed_offset);
        if (!(speed_kmh > 0.0f) || !std::isfinite(speed_kmh))
            throw std::runtime_error("bad BRG1 routed speed");
        return speed_kmh / 3.6f;
    }

private:
    ByteView bytes_;
    std::uint32_t node_count_ = 0;
    std::uint32_t edge_count_ = 0;
    std::size_t edge_table_offset_ = 0;

    template <class T>
    static T read(const std::uint8_t *pointer) {
        T value;
        std::memcpy(&value, pointer, sizeof(T));
        return value;
    }
};

inline bool same_route_point(const RoutePoint &a, const RoutePoint &b) {
    return std::abs(a.x - b.x) < 1e-4 && std::abs(a.y - b.y) < 1e-4;
}

inline std::vector<float> build_route_speed_profile(const RouteResult &result,
                                                     const RouteGeometryView &geometry,
                                                     const RoutingSpeedView &speeds) {
    std::vector<float> profile(result.points.size(), 13.9f);
    if (!result.success || result.points.empty()) return profile;

    for (const auto &leg : result.legs) {
        if (!leg.success || leg.edge_indices.empty() || leg.point_start_index >= result.points.size()) continue;
        const std::size_t end = std::min(leg.point_end_index, result.points.size() - 1);
        std::size_t edge_position = 0;
        auto shape = geometry.edge_points(leg.edge_indices[edge_position]);
        RoutePoint edge_end = shape.back();

        for (std::size_t point_index = leg.point_start_index; point_index <= end; ++point_index) {
            while (edge_position + 1 < leg.edge_indices.size() &&
                   same_route_point(result.points[point_index], edge_end)) {
                ++edge_position;
                shape = geometry.edge_points(leg.edge_indices[edge_position]);
                edge_end = shape.back();
            }
            profile[point_index] = speeds.speed_mps(leg.edge_indices[edge_position]);
        }
    }
    return profile;
}

} // namespace brur::gps
