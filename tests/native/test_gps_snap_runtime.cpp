#include "../../native/gps_snap_runtime.h"

#include <cassert>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <vector>

// Deterministic zero-allocation contracts for BRS3 fixed-point road snapping.
//
// Dependencies:
// - gps_snap_runtime only; no BRG objects, files, mmap, Godot or Sweden data.

namespace {
using namespace brur::gps::snap;

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
    constexpr std::size_t header_size = 48;
    constexpr std::size_t cell_size = 16;
    constexpr std::size_t segment_size = 24;
    constexpr std::uint32_t cell_count = 1;
    constexpr std::uint32_t segment_count = 2;
    constexpr std::uint32_t ref_count = 2;
    const std::size_t segment_offset = header_size + cell_count * cell_size;
    const std::size_t ref_offset = segment_offset + segment_count * segment_size;

    std::vector<std::uint8_t> bytes(ref_offset + ref_count * 4, 0);
    std::memcpy(bytes.data(), "BRS3", 4);
    put(bytes, 4, std::uint32_t{1});
    put(bytes, 8, std::uint32_t{10000});
    put(bytes, 12, cell_count);
    put(bytes, 16, segment_count);
    put(bytes, 20, ref_count);
    put(bytes, 24, 1000.0);
    put(bytes, 32, 2000.0);
    put(bytes, 40, 120.0f);
    put(bytes, 44, std::uint32_t{0});

    put(bytes, 48, std::int32_t{0});
    put(bytes, 52, std::int32_t{0});
    put(bytes, 56, std::uint32_t{0});
    put(bytes, 60, ref_count);

    put(bytes, segment_offset, std::uint32_t{7});
    put(bytes, segment_offset + 4, std::uint32_t{8});
    put(bytes, segment_offset + 8, std::int32_t{0});
    put(bytes, segment_offset + 12, std::int32_t{0});
    put(bytes, segment_offset + 16, std::int32_t{1000});
    put(bytes, segment_offset + 20, std::int32_t{0});

    const std::size_t second = segment_offset + segment_size;
    put(bytes, second, std::uint32_t{9});
    put(bytes, second + 4, std::uint32_t{0xffffffffu});
    put(bytes, second + 8, std::int32_t{5000});
    put(bytes, second + 12, std::int32_t{5000});
    put(bytes, second + 16, std::int32_t{6000});
    put(bytes, second + 20, std::int32_t{5000});

    put(bytes, ref_offset, std::uint32_t{0});
    put(bytes, ref_offset + 4, std::uint32_t{1});
    return bytes;
}

void test_fixed_point_snap_and_no_allocations() {
    auto bytes = fixture();
    RoutingSnapContext context({bytes.data(), bytes.size()}, 16);
    assert(context.valid());
    assert(context.segment_count() == 2);
    assert(std::abs(context.cell_size_m() - 100.0) < 1e-12);

    allocation_count = 0;
    const SnapResult result = context.snap(1005.0, 2001.0, 20.0);
    assert(result.success);
    assert(result.failure == SnapFailure::None);
    assert(result.candidates == 2);
    assert(std::abs(result.x - 1005.0) < 1e-9);
    assert(std::abs(result.y - 2000.0) < 1e-9);
    assert(std::abs(result.distance_m - 1.0) < 1e-9);
    assert(result.direction_count == 2);
    assert(result.directions[0].edge_index == 7);
    assert(result.directions[1].edge_index == 8);
    assert(std::abs(result.directions[0].fraction - 0.5) < 1e-9);
    assert(std::abs(result.directions[1].fraction - 0.5) < 1e-9);
    assert(allocation_count == 0);
}

void test_candidate_overflow_is_explicit() {
    auto bytes = fixture();
    RoutingSnapContext context({bytes.data(), bytes.size()}, 1);
    assert(context.valid());
    const SnapResult result = context.snap(1005.0, 2001.0, 20.0);
    assert(!result.success);
    assert(result.failure == SnapFailure::CandidateOverflow);
}

} // namespace

void *operator new(std::size_t size) { return tracked_allocate(size); }
void operator delete(void *pointer) noexcept { std::free(pointer); }
void operator delete(void *pointer, std::size_t) noexcept { std::free(pointer); }
void *operator new[](std::size_t size) { return tracked_allocate(size); }
void operator delete[](void *pointer) noexcept { std::free(pointer); }
void operator delete[](void *pointer, std::size_t) noexcept { std::free(pointer); }

int main() {
    test_fixed_point_snap_and_no_allocations();
    test_candidate_overflow_is_explicit();
    std::cout << "native gps snap runtime tests: OK\n";
    return 0;
}
