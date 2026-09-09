#include "../../native/gps_ch_runtime.h"

#include <cassert>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <vector>

// Deterministic zero-allocation contracts for the portable BCH2 query runtime.
//
// Dependencies:
// - gps_ch_runtime only; no files, mmap, sockets, Godot or Sweden data.
// - Builds a tiny BCH2 fixture directly in memory.

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
    constexpr std::uint32_t weight_scale = 1'000'000;
    constexpr std::size_t header_size = 128;

    const std::size_t source_offset = header_size;
    const std::size_t target_offset = source_offset + edge_count * 4;
    const std::size_t weight_offset = target_offset + edge_count * 4;
    const std::size_t original_offset = weight_offset + edge_count * 4;
    const std::size_t left_offset = original_offset + edge_count * 4;
    const std::size_t right_offset = left_offset + edge_count * 4;
    const std::size_t upward_offsets_offset = right_offset + edge_count * 4;
    const std::size_t upward_refs_offset = upward_offsets_offset + (node_count + 1) * 4;
    const std::size_t downward_offsets_offset = upward_refs_offset + upward_ref_count * 4;
    const std::size_t downward_refs_offset = downward_offsets_offset + (node_count + 1) * 4;
    const std::size_t end_offset = downward_refs_offset + downward_ref_count * 4;

    std::vector<std::uint8_t> bytes(end_offset, 0);
    std::memcpy(bytes.data(), "BCH2", 4);
    put(bytes, 4, std::uint32_t{1});
    put(bytes, 8, node_count);
    put(bytes, 12, edge_count);
    put(bytes, 16, upward_ref_count);
    put(bytes, 20, downward_ref_count);
    put(bytes, 24, std::uint32_t{0});
    put(bytes, 28, weight_scale);
    put(bytes, 32, 4.0f);
    put(bytes, 36, std::uint32_t{0});
    put(bytes, 40, static_cast<std::uint64_t>(source_offset));
    put(bytes, 48, static_cast<std::uint64_t>(target_offset));
    put(bytes, 56, static_cast<std::uint64_t>(weight_offset));
    put(bytes, 64, static_cast<std::uint64_t>(original_offset));
    put(bytes, 72, static_cast<std::uint64_t>(left_offset));
    put(bytes, 80, static_cast<std::uint64_t>(right_offset));
    put(bytes, 88, static_cast<std::uint64_t>(upward_offsets_offset));
    put(bytes, 96, static_cast<std::uint64_t>(upward_refs_offset));
    put(bytes, 104, static_cast<std::uint64_t>(downward_offsets_offset));
    put(bytes, 112, static_cast<std::uint64_t>(downward_refs_offset));
    put(bytes, 120, static_cast<std::uint64_t>(end_offset));

    const std::uint32_t sources[] = {0, 1, 2, 0, 0};
    const std::uint32_t targets[] = {1, 2, 3, 3, 2};
    const std::uint32_t weights[] = {
        1'000'000, 1'000'000, 1'000'000, 10'000'000, 2'000'000,
    };
    const std::int32_t originals[] = {0, 1, 2, 3, -1};
    const std::int32_t lefts[] = {-1, -1, -1, -1, 0};
    const std::int32_t rights[] = {-1, -1, -1, -1, 1};
    for (std::uint32_t i = 0; i < edge_count; ++i) {
        put(bytes, source_offset + i * 4, sources[i]);
        put(bytes, target_offset + i * 4, targets[i]);
        put(bytes, weight_offset + i * 4, weights[i]);
        put(bytes, original_offset + i * 4, originals[i]);
        put(bytes, left_offset + i * 4, lefts[i]);
        put(bytes, right_offset + i * 4, rights[i]);
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
    assert(context.weight_scale() == 1'000'000);

    std::uint32_t edges[16]{};
    allocation_count = 0;
    const QueryResult result = context.route_nodes(0, 3, 0, 4.0f, edges, 16);
    assert(result.success);
    assert(result.failure == QueryFailure::None);
    assert(std::abs(result.cost - 3.0) < 1e-12);
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
