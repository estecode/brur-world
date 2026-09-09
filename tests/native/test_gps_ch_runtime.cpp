#include "../../native/gps_ch_runtime.h"

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <vector>

// Deterministic zero-allocation contracts for the portable CH query runtime.
//
// Dependencies:
// - gps_ch_runtime only; no files, mmap, sockets, Godot or Sweden data.
// - Builds a tiny BCH1 fixture directly in memory.

namespace {
using namespace brur::gps::ch;

std::size_t allocation_count = 0;

void *tracked_allocate(std::size_t size) {
    ++allocation_count;
    if (void *pointer = std::malloc(size)) return pointer;
    throw std::bad_alloc();
}

template <class T>
void put(std::vector<std::uint8_t> &bytes, std::size_t offset, T value) {
    std::memcpy(bytes.data() + offset, &value, sizeof(T));
}

std::vector<std::uint8_t> fixture() {
    constexpr std::uint32_t node_count = 4;
    constexpr std::uint32_t edge_count = 5;
    constexpr std::uint32_t upward_ref_count = 4;
    constexpr std::uint32_t downward_ref_count = 0;
    constexpr std::size_t header_size = 84;
    constexpr std::size_t edge_size = 28;

    const std::size_t rank_offset = header_size;
    const std::size_t edge_offset = rank_offset + node_count * 4;
    const std::size_t upward_offsets_offset = edge_offset + edge_count * edge_size;
    const std::size_t upward_refs_offset = upward_offsets_offset + (node_count + 1) * 4;
    const std::size_t downward_offsets_offset = upward_refs_offset + upward_ref_count * 4;
    const std::size_t downward_refs_offset = downward_offsets_offset + (node_count + 1) * 4;

    std::vector<std::uint8_t> bytes(downward_refs_offset + downward_ref_count * 4, 0);
    std::memcpy(bytes.data(), "BCH1", 4);
    put(bytes, 4, std::uint32_t{1});
    put(bytes, 8, node_count);
    put(bytes, 12, edge_count);
    put(bytes, 16, upward_ref_count);
    put(bytes, 20, downward_ref_count);
    put(bytes, 24, std::uint32_t{0});
    put(bytes, 28, std::uint32_t{0});
    put(bytes, 32, 4.0f);
    put(bytes, 36, static_cast<std::uint64_t>(rank_offset));
    put(bytes, 44, static_cast<std::uint64_t>(edge_offset));
    put(bytes, 52, static_cast<std::uint64_t>(upward_offsets_offset));
    put(bytes, 60, static_cast<std::uint64_t>(upward_refs_offset));
    put(bytes, 68, static_cast<std::uint64_t>(downward_offsets_offset));
    put(bytes, 76, static_cast<std::uint64_t>(downward_refs_offset));

    for (std::uint32_t i = 0; i < node_count; ++i) put(bytes, rank_offset + i * 4, i);

    struct Edge {
        std::uint32_t source;
        std::uint32_t target;
        double cost;
        std::int32_t original;
        std::int32_t left;
        std::int32_t right;
    };
    const Edge edges[] = {
        {0, 1, 1.0, 0, -1, -1},
        {1, 2, 1.0, 1, -1, -1},
        {2, 3, 1.0, 2, -1, -1},
        {0, 3, 10.0, 3, -1, -1},
        {0, 2, 2.0, -1, 0, 1},
    };
    for (std::uint32_t i = 0; i < edge_count; ++i) {
        const std::size_t offset = edge_offset + i * edge_size;
        put(bytes, offset, edges[i].source);
        put(bytes, offset + 4, edges[i].target);
        put(bytes, offset + 8, edges[i].cost);
        put(bytes, offset + 16, edges[i].original);
        put(bytes, offset + 20, edges[i].left);
        put(bytes, offset + 24, edges[i].right);
    }

    const std::uint32_t upward_offsets[] = {0, 2, 3, 4, 4};
    for (std::uint32_t i = 0; i <= node_count; ++i) {
        put(bytes, upward_offsets_offset + i * 4, upward_offsets[i]);
        put(bytes, downward_offsets_offset + i * 4, std::uint32_t{0});
    }
    const std::uint32_t upward_refs[] = {4, 3, 1, 2};
    for (std::uint32_t i = 0; i < upward_ref_count; ++i) {
        put(bytes, upward_refs_offset + i * 4, upward_refs[i]);
    }
    return bytes;
}

void test_exact_route_and_no_query_allocations() {
    auto bytes = fixture();
    RoutingContext context({bytes.data(), bytes.size()}, {32, 32, 32, 32});
    assert(context.valid());
    assert(context.node_count() == 4);
    assert(context.edge_count() == 5);

    std::uint32_t edges[16]{};
    allocation_count = 0;
    const QueryResult result = context.route_nodes(0, 3, 0, 4.0f, edges, 16);
    assert(result.success);
    assert(result.failure == QueryFailure::None);
    assert(result.cost == 3.0);
    assert(result.edge_count == 3);
    assert(edges[0] == 0 && edges[1] == 1 && edges[2] == 2);
    assert(result.stats.settled > 0);
    assert(result.stats.relaxed > 0);
    assert(result.stats.queue_peak > 0);
    assert(result.stats.state_peak > 0);
    assert(result.stats.shortcut_unpacked == 1);
    assert(allocation_count == 0);
}

void test_policy_and_capacity_failures_are_explicit() {
    auto bytes = fixture();
    RoutingContext context({bytes.data(), bytes.size()}, {2, 2, 8, 8});
    assert(context.valid());
    std::uint32_t edges[1]{};

    const QueryResult mismatch = context.route_nodes(0, 3, 1, 4.0f, edges, 1);
    assert(!mismatch.success);
    assert(mismatch.failure == QueryFailure::PolicyMismatch);

    const QueryResult overflow = context.route_nodes(0, 3, 0, 4.0f, edges, 1);
    assert(!overflow.success);
    assert(overflow.failure == QueryFailure::StateOverflow ||
           overflow.failure == QueryFailure::QueueOverflow ||
           overflow.failure == QueryFailure::OutputOverflow);
}

} // namespace

void *operator new(std::size_t size) { return tracked_allocate(size); }
void operator delete(void *pointer) noexcept { std::free(pointer); }
void operator delete(void *pointer, std::size_t) noexcept { std::free(pointer); }
void *operator new[](std::size_t size) { return tracked_allocate(size); }
void operator delete[](void *pointer) noexcept { std::free(pointer); }
void operator delete[](void *pointer, std::size_t) noexcept { std::free(pointer); }

int main() {
    test_exact_route_and_no_query_allocations();
    test_policy_and_capacity_failures_are_explicit();
    std::cout << "native gps CH runtime tests: OK\n";
    return 0;
}
