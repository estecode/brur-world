#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>

// Portable zero-allocation road snapping over immutable BRS3 bytes.
//
// Dependencies:
// - Standard C++20 only.
// - BRS3 is generated offline from the authoritative BRG1 graph.
// - Construction allocates fixed dedup state once; snap queries do not allocate.

namespace brur::gps::snap {

struct ByteView {
    const std::uint8_t *data = nullptr;
    std::size_t size = 0;
};

enum class SnapFailure : std::uint8_t {
    None,
    InvalidData,
    NotFound,
    CandidateOverflow,
};

struct Direction {
    std::uint32_t edge_index = 0;
    double fraction = 0.0;
};

struct SnapResult {
    bool success = false;
    SnapFailure failure = SnapFailure::InvalidData;
    double x = 0.0;
    double y = 0.0;
    double distance_m = 0.0;
    std::uint32_t candidates = 0;
    std::uint8_t direction_count = 0;
    Direction directions[2]{};
};

class RoutingSnapContext {
public:
    explicit RoutingSnapContext(ByteView brs3, std::uint32_t candidate_capacity = 4096);
    ~RoutingSnapContext();
    RoutingSnapContext(RoutingSnapContext &&) noexcept;
    RoutingSnapContext &operator=(RoutingSnapContext &&) noexcept;
    RoutingSnapContext(const RoutingSnapContext &) = delete;
    RoutingSnapContext &operator=(const RoutingSnapContext &) = delete;

    bool valid() const noexcept;
    std::uint32_t segment_count() const noexcept;
    std::uint32_t cell_count() const noexcept;
    double cell_size_m() const noexcept;
    float max_legal_speed_kmh() const noexcept;

    SnapResult snap(double x, double y, double max_distance_m = 250.0) noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

const char *snap_failure_name(SnapFailure failure) noexcept;

} // namespace brur::gps::snap
