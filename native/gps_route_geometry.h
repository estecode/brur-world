#pragma once

#include "gps_core.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <vector>

// Expands routed BRG1 edge indices into detailed BRH1 road-shape geometry.
//
// Dependencies:
// - Standard C++20 and gps_core.h route result types only.
// - Consumes caller-owned immutable BRH1 bytes; no files, sockets, JSON or Godot.
// - Does not change routing cost, snapping, legality, preferences or chosen edges.

namespace brur::gps {

class RouteGeometryView {
public:
    explicit RouteGeometryView(ByteView bytes) : bytes_(bytes) {
        constexpr std::size_t header_size = 12;
        constexpr std::size_t edge_record_size = 12;
        constexpr std::size_t point_size = 8;
        if (!bytes_.data || bytes_.size < header_size || std::memcmp(bytes_.data, "BRH1", 4) != 0)
            throw std::runtime_error("bad BRH1 data");
        edge_count_ = read<std::uint32_t>(bytes_.data + 4);
        point_count_ = read<std::uint32_t>(bytes_.data + 8);
        point_table_offset_ = header_size + static_cast<std::size_t>(edge_count_) * edge_record_size;
        const auto expected = point_table_offset_ + static_cast<std::size_t>(point_count_) * point_size;
        if (expected != bytes_.size) throw std::runtime_error("BRH1 size mismatch");
    }

    std::uint32_t edge_count() const { return edge_count_; }
    std::uint32_t point_count() const { return point_count_; }

    std::vector<RoutePoint> edge_points(std::uint32_t edge_index) const {
        const Entry entry = edge_entry(edge_index);
        std::vector<RoutePoint> result;
        result.reserve(entry.count);
        for (std::uint32_t i = 0; i < entry.count; ++i) {
            const std::uint32_t source_index = entry.reversed ? entry.count - 1u - i : i;
            const auto *p = bytes_.data + point_table_offset_ +
                static_cast<std::size_t>(entry.offset + source_index) * 8u;
            result.push_back({read<float>(p), read<float>(p + 4)});
        }
        return result;
    }

    void densify(RouteResult &result) const {
        if (!result.success) return;
        std::vector<RoutePoint> merged;
        for (auto &leg : result.legs) {
            if (!leg.success || leg.points.empty()) continue;
            const RoutePoint start = leg.points.front();
            const RoutePoint target = leg.points.back();
            leg.points = densify_leg(leg.edge_indices, start, target);
            leg.point_start_index = merged.empty() ? 0 : merged.size() - 1;
            for (const auto &point : leg.points) append_unique(merged, point);
            leg.point_end_index = merged.empty() ? 0 : merged.size() - 1;
        }
        if (!result.legs.empty()) result.points = std::move(merged);
    }

private:
    struct Entry {
        std::uint32_t offset = 0;
        std::uint32_t count = 0;
        bool reversed = false;
    };

    struct Projection {
        std::size_t segment = 0;
        double fraction = 0.0;
        RoutePoint point;
        double distance_sq = 0.0;
    };

    ByteView bytes_;
    std::uint32_t edge_count_ = 0;
    std::uint32_t point_count_ = 0;
    std::size_t point_table_offset_ = 0;

    template <class T>
    static T read(const std::uint8_t *pointer) {
        T value;
        std::memcpy(&value, pointer, sizeof(T));
        return value;
    }

    Entry edge_entry(std::uint32_t edge_index) const {
        if (edge_index >= edge_count_) throw std::runtime_error("BRH1 edge index out of range");
        const auto *p = bytes_.data + 12u + static_cast<std::size_t>(edge_index) * 12u;
        Entry result;
        result.offset = read<std::uint32_t>(p);
        result.count = read<std::uint32_t>(p + 4);
        result.reversed = p[8] != 0;
        if (static_cast<std::uint64_t>(result.offset) + result.count > point_count_)
            throw std::runtime_error("BRH1 point range out of bounds");
        if (result.count < 2) throw std::runtime_error("BRH1 edge geometry needs at least two points");
        return result;
    }

    static void append_unique(std::vector<RoutePoint> &points, RoutePoint point) {
        if (!points.empty() && std::abs(points.back().x - point.x) < 1e-5 &&
            std::abs(points.back().y - point.y) < 1e-5) return;
        points.push_back(point);
    }

    static bool projection_tie_break(const RoutePoint &candidate, const RoutePoint &best) {
        if (candidate.x != best.x) return candidate.x < best.x;
        return candidate.y < best.y;
    }

    static Projection closest_on_polyline(const std::vector<RoutePoint> &shape, RoutePoint wanted) {
        Projection best;
        best.distance_sq = std::numeric_limits<double>::infinity();
        for (std::size_t i = 0; i + 1 < shape.size(); ++i) {
            const auto &a = shape[i];
            const auto &b = shape[i + 1];
            const double dx = b.x - a.x;
            const double dy = b.y - a.y;
            const double length_sq = dx * dx + dy * dy;
            double fraction = length_sq > 0.0
                ? ((wanted.x - a.x) * dx + (wanted.y - a.y) * dy) / length_sq
                : 0.0;
            fraction = std::clamp(fraction, 0.0, 1.0);
            const RoutePoint projected{a.x + dx * fraction, a.y + dy * fraction};
            const double ex = wanted.x - projected.x;
            const double ey = wanted.y - projected.y;
            const double distance_sq = ex * ex + ey * ey;
            if (!std::isfinite(best.distance_sq)) {
                best = {i, fraction, projected, distance_sq};
                continue;
            }
            const double tie_tolerance = 1e-10 * std::max({1.0, std::abs(best.distance_sq), std::abs(distance_sq)});
            if (distance_sq + tie_tolerance < best.distance_sq ||
                (std::abs(distance_sq - best.distance_sq) <= tie_tolerance &&
                 projection_tie_break(projected, best.point))) {
                best = {i, fraction, projected, distance_sq};
            }
        }
        return best;
    }

    static double ordered_position(const Projection &projection) {
        return static_cast<double>(projection.segment) + projection.fraction;
    }

    std::vector<RoutePoint> densify_leg(const std::vector<std::uint32_t> &edges,
                                        RoutePoint start, RoutePoint target) const {
        if (edges.empty()) return {start, target};
        std::vector<RoutePoint> points;

        for (std::size_t edge_position = 0; edge_position < edges.size(); ++edge_position) {
            const auto shape = edge_points(edges[edge_position]);
            Projection from{0, 0.0, shape.front(), 0.0};
            Projection to{shape.size() - 2, 1.0, shape.back(), 0.0};
            if (edge_position == 0) from = closest_on_polyline(shape, start);
            if (edge_position + 1 == edges.size()) to = closest_on_polyline(shape, target);

            if (ordered_position(to) + 1e-9 < ordered_position(from)) {
                // Snaps are still owned by BRG1. If an old chord-based partial snap is
                // ambiguous on a looping shape, keep the edge's directed full geometry.
                from = {0, 0.0, shape.front(), 0.0};
                to = {shape.size() - 2, 1.0, shape.back(), 0.0};
            }

            // Projection is deterministic by coordinate rather than traversal order so a
            // shared waypoint resolves to one visible point on both directed copies of the
            // same physical shape. Otherwise adjacent legs can be joined by a false chord.
            append_unique(points, from.point);
            for (std::size_t i = from.segment + 1; i <= to.segment && i < shape.size(); ++i)
                append_unique(points, shape[i]);
            append_unique(points, to.point);
        }

        return points;
    }
};

} // namespace brur::gps
