#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>

// Portable zero-allocation CH query core over immutable BCH1 bytes.
//
// Dependencies:
// - Standard C++20 only.
// - Caller owns immutable BCH1 bytes and output buffers.
// - Construction may allocate fixed workspace once; route queries do not allocate.

namespace brur::gps::ch {

struct ByteView {
    const std::uint8_t *data = nullptr;
    std::size_t size = 0;
};

enum class QueryFailure : std::uint8_t {
    None,
    InvalidData,
    InvalidNode,
    PolicyMismatch,
    Unreachable,
    StateOverflow,
    QueueOverflow,
    OutputOverflow,
    ShortcutStackOverflow,
};

struct QueryStats {
    std::uint64_t settled = 0;
    std::uint64_t relaxed = 0;
    std::uint32_t queue_peak = 0;
    std::uint32_t state_peak = 0;
    std::uint32_t shortcut_unpacked = 0;
};

struct QueryResult {
    bool success = false;
    QueryFailure failure = QueryFailure::InvalidData;
    double cost = 0.0;
    std::size_t edge_count = 0;
    QueryStats stats;
};

struct ContextConfig {
    std::uint32_t state_capacity_per_direction = 16384;
    std::uint32_t queue_capacity_per_direction = 16384;
    std::uint32_t shortcut_stack_capacity = 8192;
    std::uint32_t ch_path_capacity = 8192;
};

class RoutingContext {
public:
    RoutingContext(ByteView bch1, ContextConfig config = {});
    ~RoutingContext();
    RoutingContext(RoutingContext &&) noexcept;
    RoutingContext &operator=(RoutingContext &&) noexcept;
    RoutingContext(const RoutingContext &) = delete;
    RoutingContext &operator=(const RoutingContext &) = delete;

    bool valid() const noexcept;
    std::uint32_t node_count() const noexcept;
    std::uint32_t edge_count() const noexcept;
    std::uint32_t preference_code() const noexcept;
    float avoid_penalty() const noexcept;

    QueryResult route_nodes(
        std::uint32_t start_node,
        std::uint32_t target_node,
        std::uint32_t requested_preference_code,
        float requested_avoid_penalty,
        std::uint32_t *output_edges,
        std::size_t output_capacity) noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

const char *query_failure_name(QueryFailure failure) noexcept;

} // namespace brur::gps::ch
