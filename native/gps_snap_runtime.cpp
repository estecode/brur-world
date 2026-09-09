#include "gps_snap_runtime.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>

namespace brur::gps::snap {
namespace {
constexpr std::size_t HEADER_SIZE = 48;
constexpr std::size_t CELL_SIZE = 16;
constexpr std::size_t SEGMENT_SIZE = 24;
constexpr std::uint32_t VERSION = 1;
constexpr std::uint32_t NO_EDGE = 0xffffffffu;
constexpr std::uint32_t EMPTY_SEGMENT = 0xffffffffu;
constexpr double CM_PER_METER = 100.0;

template <class T>
bool read_scalar(ByteView bytes, std::size_t offset, T &value) noexcept {
    if (!bytes.data || offset > bytes.size || sizeof(T) > bytes.size - offset) return false;
    std::memcpy(&value, bytes.data + offset, sizeof(T));
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    auto *raw = reinterpret_cast<std::uint8_t *>(&value);
    std::reverse(raw, raw + sizeof(T));
#endif
    return true;
}

struct Header {
    std::uint32_t version = 0;
    std::uint32_t cell_size_cm = 0;
    std::uint32_t cell_count = 0;
    std::uint32_t segment_count = 0;
    std::uint32_t ref_count = 0;
    double origin_x = 0.0;
    double origin_y = 0.0;
    float max_legal_speed_kmh = 0.0f;
};

struct Segment {
    std::uint32_t forward_edge = NO_EDGE;
    std::uint32_t reverse_edge = NO_EDGE;
    std::int32_t ax = 0;
    std::int32_t ay = 0;
    std::int32_t bx = 0;
    std::int32_t by = 0;
};

struct SeenSlot {
    std::uint32_t segment = EMPTY_SEGMENT;
    std::uint32_t epoch = 0;
};

bool parse_header(ByteView bytes, Header &header) noexcept {
    if (!bytes.data || bytes.size < HEADER_SIZE || std::memcmp(bytes.data, "BRS3", 4) != 0) return false;
    std::uint32_t reserved = 0;
    if (!read_scalar(bytes, 4, header.version) || header.version != VERSION ||
        !read_scalar(bytes, 8, header.cell_size_cm) || !read_scalar(bytes, 12, header.cell_count) ||
        !read_scalar(bytes, 16, header.segment_count) || !read_scalar(bytes, 20, header.ref_count) ||
        !read_scalar(bytes, 24, header.origin_x) || !read_scalar(bytes, 32, header.origin_y) ||
        !read_scalar(bytes, 40, header.max_legal_speed_kmh) || !read_scalar(bytes, 44, reserved)) {
        return false;
    }
    if (header.cell_size_cm == 0 || header.segment_count == 0 || header.max_legal_speed_kmh <= 0.0f) return false;
    const std::uint64_t cell_end = HEADER_SIZE + static_cast<std::uint64_t>(header.cell_count) * CELL_SIZE;
    const std::uint64_t segment_end = cell_end + static_cast<std::uint64_t>(header.segment_count) * SEGMENT_SIZE;
    const std::uint64_t expected = segment_end + static_cast<std::uint64_t>(header.ref_count) * 4;
    return expected == bytes.size;
}

std::uint32_t hash_segment(std::uint32_t value) noexcept {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

} // namespace

struct RoutingSnapContext::Impl {
    ByteView bytes;
    Header header;
    std::size_t segment_offset = 0;
    std::size_t ref_offset = 0;
    std::unique_ptr<SeenSlot[]> seen;
    std::uint32_t seen_capacity = 0;
    std::uint32_t epoch = 1;
    bool is_valid = false;

    Impl(ByteView input, std::uint32_t candidate_capacity)
        : bytes(input),
          seen(candidate_capacity ? new (std::nothrow) SeenSlot[candidate_capacity] : nullptr),
          seen_capacity(candidate_capacity) {
        if (!parse_header(bytes, header) || !seen || seen_capacity == 0) return;
        segment_offset = HEADER_SIZE + static_cast<std::size_t>(header.cell_count) * CELL_SIZE;
        ref_offset = segment_offset + static_cast<std::size_t>(header.segment_count) * SEGMENT_SIZE;
        is_valid = true;
    }

    void begin_query() noexcept {
        if (++epoch == 0) {
            for (std::uint32_t i = 0; i < seen_capacity; ++i) seen[i].epoch = 0;
            epoch = 1;
        }
    }

    bool mark_seen(std::uint32_t segment_index) noexcept {
        std::uint32_t slot_index = hash_segment(segment_index) % seen_capacity;
        for (std::uint32_t probe = 0; probe < seen_capacity; ++probe) {
            SeenSlot &slot = seen[slot_index];
            if (slot.epoch != epoch) {
                slot.epoch = epoch;
                slot.segment = segment_index;
                return true;
            }
            if (slot.segment == segment_index) return false;
            if (++slot_index == seen_capacity) slot_index = 0;
        }
        return false;
    }

    bool seen_full_for(std::uint32_t segment_index) const noexcept {
        std::uint32_t slot_index = hash_segment(segment_index) % seen_capacity;
        for (std::uint32_t probe = 0; probe < seen_capacity; ++probe) {
            const SeenSlot &slot = seen[slot_index];
            if (slot.epoch != epoch || slot.segment == segment_index) return false;
            if (++slot_index == seen_capacity) slot_index = 0;
        }
        return true;
    }

    bool find_cell(std::int32_t wanted_x, std::int32_t wanted_y, std::uint32_t &offset, std::uint32_t &count) const noexcept {
        std::uint32_t low = 0;
        std::uint32_t high = header.cell_count;
        while (low < high) {
            const std::uint32_t middle = low + (high - low) / 2;
            const std::size_t base = HEADER_SIZE + static_cast<std::size_t>(middle) * CELL_SIZE;
            std::int32_t x = 0;
            std::int32_t y = 0;
            if (!read_scalar(bytes, base, x) || !read_scalar(bytes, base + 4, y)) return false;
            if (x < wanted_x || (x == wanted_x && y < wanted_y)) low = middle + 1;
            else high = middle;
        }
        if (low >= header.cell_count) return false;
        const std::size_t base = HEADER_SIZE + static_cast<std::size_t>(low) * CELL_SIZE;
        std::int32_t x = 0;
        std::int32_t y = 0;
        if (!read_scalar(bytes, base, x) || !read_scalar(bytes, base + 4, y) || x != wanted_x || y != wanted_y) return false;
        if (!read_scalar(bytes, base + 8, offset) || !read_scalar(bytes, base + 12, count)) return false;
        return static_cast<std::uint64_t>(offset) + count <= header.ref_count;
    }

    bool read_segment(std::uint32_t index, Segment &segment) const noexcept {
        if (index >= header.segment_count) return false;
        const std::size_t base = segment_offset + static_cast<std::size_t>(index) * SEGMENT_SIZE;
        return read_scalar(bytes, base, segment.forward_edge) && read_scalar(bytes, base + 4, segment.reverse_edge) &&
               read_scalar(bytes, base + 8, segment.ax) && read_scalar(bytes, base + 12, segment.ay) &&
               read_scalar(bytes, base + 16, segment.bx) && read_scalar(bytes, base + 20, segment.by);
    }

    bool read_ref(std::uint32_t position, std::uint32_t &segment_index) const noexcept {
        if (position >= header.ref_count) return false;
        return read_scalar(bytes, ref_offset + static_cast<std::size_t>(position) * 4, segment_index);
    }

    SnapResult query(double x, double y, double max_distance_m) noexcept {
        SnapResult result;
        result.failure = SnapFailure::NotFound;
        if (!is_valid || !std::isfinite(x) || !std::isfinite(y) || !std::isfinite(max_distance_m) || max_distance_m < 0.0) {
            result.failure = SnapFailure::InvalidData;
            return result;
        }
        begin_query();

        const std::int64_t qx = std::llround((x - header.origin_x) * CM_PER_METER);
        const std::int64_t qy = std::llround((y - header.origin_y) * CM_PER_METER);
        const double cell_size = static_cast<double>(header.cell_size_cm);
        const auto center_x = static_cast<std::int32_t>(std::floor(static_cast<double>(qx) / cell_size));
        const auto center_y = static_cast<std::int32_t>(std::floor(static_cast<double>(qy) / cell_size));
        const int radius = static_cast<int>(std::ceil(max_distance_m * CM_PER_METER / cell_size)) + 1;

        double best_distance_sq = std::numeric_limits<double>::infinity();
        std::uint32_t best_segment_index = NO_EDGE;
        double best_fraction = 0.0;
        double best_x_cm = 0.0;
        double best_y_cm = 0.0;

        for (int dx_cell = -radius; dx_cell <= radius; ++dx_cell) {
            for (int dy_cell = -radius; dy_cell <= radius; ++dy_cell) {
                std::uint32_t offset = 0;
                std::uint32_t count = 0;
                if (!find_cell(center_x + dx_cell, center_y + dy_cell, offset, count)) continue;
                for (std::uint32_t i = 0; i < count; ++i) {
                    std::uint32_t segment_index = 0;
                    if (!read_ref(offset + i, segment_index) || segment_index >= header.segment_count) {
                        result.failure = SnapFailure::InvalidData;
                        return result;
                    }
                    if (seen_full_for(segment_index)) {
                        result.failure = SnapFailure::CandidateOverflow;
                        return result;
                    }
                    if (!mark_seen(segment_index)) continue;
                    ++result.candidates;

                    Segment segment;
                    if (!read_segment(segment_index, segment)) {
                        result.failure = SnapFailure::InvalidData;
                        return result;
                    }
                    const double ax = segment.ax;
                    const double ay = segment.ay;
                    const double sx = static_cast<double>(segment.bx) - ax;
                    const double sy = static_cast<double>(segment.by) - ay;
                    const double length_sq = sx * sx + sy * sy;
                    double fraction = 0.0;
                    if (length_sq > 0.0) {
                        fraction = ((static_cast<double>(qx) - ax) * sx + (static_cast<double>(qy) - ay) * sy) / length_sq;
                        fraction = std::clamp(fraction, 0.0, 1.0);
                    }
                    const double px = ax + sx * fraction;
                    const double py = ay + sy * fraction;
                    const double ddx = static_cast<double>(qx) - px;
                    const double ddy = static_cast<double>(qy) - py;
                    const double distance_sq = ddx * ddx + ddy * ddy;
                    if (distance_sq < best_distance_sq ||
                        (distance_sq == best_distance_sq && segment_index < best_segment_index)) {
                        best_distance_sq = distance_sq;
                        best_segment_index = segment_index;
                        best_fraction = fraction;
                        best_x_cm = px;
                        best_y_cm = py;
                    }
                }
            }
        }

        if (best_segment_index == NO_EDGE) return result;
        result.distance_m = std::sqrt(best_distance_sq) / CM_PER_METER;
        if (result.distance_m > max_distance_m) return result;

        Segment best_segment;
        if (!read_segment(best_segment_index, best_segment)) {
            result.failure = SnapFailure::InvalidData;
            return result;
        }
        if (best_segment.forward_edge != NO_EDGE) {
            result.directions[result.direction_count++] = {best_segment.forward_edge, best_fraction};
        }
        if (best_segment.reverse_edge != NO_EDGE) {
            result.directions[result.direction_count++] = {best_segment.reverse_edge, 1.0 - best_fraction};
        }
        if (result.direction_count == 2 && result.directions[1].edge_index < result.directions[0].edge_index) {
            std::swap(result.directions[0], result.directions[1]);
        }
        if (result.direction_count == 0) {
            result.failure = SnapFailure::InvalidData;
            return result;
        }

        result.x = header.origin_x + best_x_cm / CM_PER_METER;
        result.y = header.origin_y + best_y_cm / CM_PER_METER;
        result.success = true;
        result.failure = SnapFailure::None;
        return result;
    }
};

RoutingSnapContext::RoutingSnapContext(ByteView brs3, std::uint32_t candidate_capacity)
    : impl_(new Impl(brs3, candidate_capacity)) {}
RoutingSnapContext::~RoutingSnapContext() = default;
RoutingSnapContext::RoutingSnapContext(RoutingSnapContext &&) noexcept = default;
RoutingSnapContext &RoutingSnapContext::operator=(RoutingSnapContext &&) noexcept = default;

bool RoutingSnapContext::valid() const noexcept { return impl_ && impl_->is_valid; }
std::uint32_t RoutingSnapContext::segment_count() const noexcept { return valid() ? impl_->header.segment_count : 0; }
std::uint32_t RoutingSnapContext::cell_count() const noexcept { return valid() ? impl_->header.cell_count : 0; }
double RoutingSnapContext::cell_size_m() const noexcept {
    return valid() ? static_cast<double>(impl_->header.cell_size_cm) / CM_PER_METER : 0.0;
}
float RoutingSnapContext::max_legal_speed_kmh() const noexcept {
    return valid() ? impl_->header.max_legal_speed_kmh : 0.0f;
}
SnapResult RoutingSnapContext::snap(double x, double y, double max_distance_m) noexcept {
    if (!impl_) return {};
    return impl_->query(x, y, max_distance_m);
}

const char *snap_failure_name(SnapFailure failure) noexcept {
    switch (failure) {
        case SnapFailure::None: return "";
        case SnapFailure::InvalidData: return "invalid_data";
        case SnapFailure::NotFound: return "not_found";
        case SnapFailure::CandidateOverflow: return "candidate_overflow";
    }
    return "invalid_data";
}

} // namespace brur::gps::snap
