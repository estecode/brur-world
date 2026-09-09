#include "gps_ch_runtime.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>
#include <utility>

// Implements the portable fixed-capacity BCH2 query core.
//
// Dependencies:
// - Standard C++20 and gps_ch_runtime.h only.
// - No filesystem, mmap, sockets, JSON, Godot or process APIs.

namespace brur::gps::ch {
namespace {
constexpr std::size_t HEADER_SIZE = 128;
constexpr std::uint32_t VERSION = 1;
constexpr std::uint32_t EMPTY_NODE = 0xffffffffu;
constexpr std::uint32_t NO_INDEX = 0xffffffffu;
constexpr std::uint64_t INF = std::numeric_limits<std::uint64_t>::max();

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

struct StateSlot {
    std::uint32_t node = EMPTY_NODE;
    std::uint32_t epoch = 0;
    std::uint64_t distance = INF;
    std::uint32_t parent_node = NO_INDEX;
    std::uint32_t parent_edge = NO_INDEX;
};

struct HeapItem {
    std::uint64_t distance = 0;
    std::uint32_t node = 0;
};

class FixedBinaryHeap {
public:
    explicit FixedBinaryHeap(std::uint32_t capacity)
        : items_(capacity ? new (std::nothrow) HeapItem[capacity] : nullptr), capacity_(capacity) {}

    bool valid() const noexcept { return capacity_ > 0 && items_ != nullptr; }
    void clear() noexcept { size_ = 0; peak_ = 0; }
    bool empty() const noexcept { return size_ == 0; }
    std::uint32_t peak() const noexcept { return peak_; }
    const HeapItem &top() const noexcept { return items_[0]; }

    bool push(HeapItem item) noexcept {
        if (size_ >= capacity_) return false;
        std::uint32_t index = size_++;
        peak_ = std::max(peak_, size_);
        while (index > 0) {
            const std::uint32_t parent = (index - 1) / 2;
            if (!less(item, items_[parent])) break;
            items_[index] = items_[parent];
            index = parent;
        }
        items_[index] = item;
        return true;
    }

    HeapItem pop() noexcept {
        const HeapItem root = items_[0];
        const HeapItem tail = items_[--size_];
        if (size_ == 0) return root;
        std::uint32_t index = 0;
        while (true) {
            const std::uint32_t left = index * 2 + 1;
            if (left >= size_) break;
            const std::uint32_t right = left + 1;
            std::uint32_t child = left;
            if (right < size_ && less(items_[right], items_[left])) child = right;
            if (!less(items_[child], tail)) break;
            items_[index] = items_[child];
            index = child;
        }
        items_[index] = tail;
        return root;
    }

private:
    static bool less(const HeapItem &a, const HeapItem &b) noexcept {
        return a.distance < b.distance || (a.distance == b.distance && a.node < b.node);
    }

    std::unique_ptr<HeapItem[]> items_;
    std::uint32_t capacity_ = 0;
    std::uint32_t size_ = 0;
    std::uint32_t peak_ = 0;
};

class SparseState {
public:
    explicit SparseState(std::uint32_t capacity)
        : slots_(capacity ? new (std::nothrow) StateSlot[capacity] : nullptr), capacity_(capacity) {}

    bool valid() const noexcept { return capacity_ > 0 && slots_ != nullptr; }

    void begin_query() noexcept {
        used_ = 0;
        peak_ = 0;
        if (++epoch_ == 0) {
            for (std::uint32_t i = 0; i < capacity_; ++i) slots_[i].epoch = 0;
            epoch_ = 1;
        }
    }

    std::uint32_t peak() const noexcept { return peak_; }

    StateSlot *find(std::uint32_t node) noexcept {
        if (!valid()) return nullptr;
        std::uint32_t index = hash(node) % capacity_;
        for (std::uint32_t probe = 0; probe < capacity_; ++probe) {
            StateSlot &slot = slots_[index];
            if (slot.epoch != epoch_) return nullptr;
            if (slot.node == node) return &slot;
            if (++index == capacity_) index = 0;
        }
        return nullptr;
    }

    StateSlot *get_or_insert(std::uint32_t node) noexcept {
        if (!valid()) return nullptr;
        std::uint32_t index = hash(node) % capacity_;
        for (std::uint32_t probe = 0; probe < capacity_; ++probe) {
            StateSlot &slot = slots_[index];
            if (slot.epoch != epoch_) {
                slot.epoch = epoch_;
                slot.node = node;
                slot.distance = INF;
                slot.parent_node = NO_INDEX;
                slot.parent_edge = NO_INDEX;
                ++used_;
                peak_ = std::max(peak_, used_);
                return &slot;
            }
            if (slot.node == node) return &slot;
            if (++index == capacity_) index = 0;
        }
        return nullptr;
    }

private:
    static std::uint32_t hash(std::uint32_t value) noexcept {
        value ^= value >> 16;
        value *= 0x7feb352du;
        value ^= value >> 15;
        value *= 0x846ca68bu;
        value ^= value >> 16;
        return value;
    }

    std::unique_ptr<StateSlot[]> slots_;
    std::uint32_t capacity_ = 0;
    std::uint32_t epoch_ = 1;
    std::uint32_t used_ = 0;
    std::uint32_t peak_ = 0;
};

struct Header {
    std::uint32_t version = 0;
    std::uint32_t node_count = 0;
    std::uint32_t edge_count = 0;
    std::uint32_t up_ref_count = 0;
    std::uint32_t down_ref_count = 0;
    std::uint32_t preference_code = 0;
    std::uint32_t weight_scale = 0;
    float avoid_penalty = 0.0f;
    std::uint64_t source_offset = 0;
    std::uint64_t target_offset = 0;
    std::uint64_t weight_offset = 0;
    std::uint64_t original_offset = 0;
    std::uint64_t left_offset = 0;
    std::uint64_t right_offset = 0;
    std::uint64_t up_offsets_offset = 0;
    std::uint64_t up_refs_offset = 0;
    std::uint64_t down_offsets_offset = 0;
    std::uint64_t down_refs_offset = 0;
    std::uint64_t end_offset = 0;
};

bool parse_header(ByteView bytes, Header &out) noexcept {
    if (!bytes.data || bytes.size < HEADER_SIZE || std::memcmp(bytes.data, "BCH2", 4) != 0) return false;
    std::uint32_t reserved = 0;
    if (!read_scalar(bytes, 4, out.version) || out.version != VERSION ||
        !read_scalar(bytes, 8, out.node_count) || !read_scalar(bytes, 12, out.edge_count) ||
        !read_scalar(bytes, 16, out.up_ref_count) || !read_scalar(bytes, 20, out.down_ref_count) ||
        !read_scalar(bytes, 24, out.preference_code) || !read_scalar(bytes, 28, out.weight_scale) ||
        !read_scalar(bytes, 32, out.avoid_penalty) || !read_scalar(bytes, 36, reserved) ||
        !read_scalar(bytes, 40, out.source_offset) || !read_scalar(bytes, 48, out.target_offset) ||
        !read_scalar(bytes, 56, out.weight_offset) || !read_scalar(bytes, 64, out.original_offset) ||
        !read_scalar(bytes, 72, out.left_offset) || !read_scalar(bytes, 80, out.right_offset) ||
        !read_scalar(bytes, 88, out.up_offsets_offset) || !read_scalar(bytes, 96, out.up_refs_offset) ||
        !read_scalar(bytes, 104, out.down_offsets_offset) || !read_scalar(bytes, 112, out.down_refs_offset) ||
        !read_scalar(bytes, 120, out.end_offset)) return false;
    if (out.node_count == 0 || out.weight_scale == 0) return false;

    const std::uint64_t edge_bytes = static_cast<std::uint64_t>(out.edge_count) * 4;
    const std::uint64_t expected_source = HEADER_SIZE;
    const std::uint64_t expected_target = expected_source + edge_bytes;
    const std::uint64_t expected_weight = expected_target + edge_bytes;
    const std::uint64_t expected_original = expected_weight + edge_bytes;
    const std::uint64_t expected_left = expected_original + edge_bytes;
    const std::uint64_t expected_right = expected_left + edge_bytes;
    const std::uint64_t expected_up_offsets = expected_right + edge_bytes;
    const std::uint64_t expected_up_refs = expected_up_offsets + static_cast<std::uint64_t>(out.node_count + 1) * 4;
    const std::uint64_t expected_down_offsets = expected_up_refs + static_cast<std::uint64_t>(out.up_ref_count) * 4;
    const std::uint64_t expected_down_refs = expected_down_offsets + static_cast<std::uint64_t>(out.node_count + 1) * 4;
    const std::uint64_t expected_end = expected_down_refs + static_cast<std::uint64_t>(out.down_ref_count) * 4;
    return out.source_offset == expected_source && out.target_offset == expected_target &&
           out.weight_offset == expected_weight && out.original_offset == expected_original &&
           out.left_offset == expected_left && out.right_offset == expected_right &&
           out.up_offsets_offset == expected_up_offsets && out.up_refs_offset == expected_up_refs &&
           out.down_offsets_offset == expected_down_offsets && out.down_refs_offset == expected_down_refs &&
           out.end_offset == expected_end && expected_end == bytes.size;
}

} // namespace

struct RoutingContext::Impl {
    ByteView bytes;
    Header header;
    SparseState forward_state;
    SparseState backward_state;
    FixedBinaryHeap forward_heap;
    FixedBinaryHeap backward_heap;
    std::unique_ptr<std::uint32_t[]> shortcut_stack;
    std::uint32_t shortcut_stack_capacity = 0;
    std::unique_ptr<std::uint32_t[]> ch_path;
    std::uint32_t ch_path_capacity = 0;
    bool is_valid = false;

    Impl(ByteView input, ContextConfig config)
        : bytes(input), forward_state(config.state_capacity_per_direction),
          backward_state(config.state_capacity_per_direction), forward_heap(config.queue_capacity_per_direction),
          backward_heap(config.queue_capacity_per_direction),
          shortcut_stack(config.shortcut_stack_capacity ? new (std::nothrow) std::uint32_t[config.shortcut_stack_capacity] : nullptr),
          shortcut_stack_capacity(config.shortcut_stack_capacity),
          ch_path(config.ch_path_capacity ? new (std::nothrow) std::uint32_t[config.ch_path_capacity] : nullptr),
          ch_path_capacity(config.ch_path_capacity) {
        is_valid = parse_header(bytes, header) && forward_state.valid() && backward_state.valid() &&
                   forward_heap.valid() && backward_heap.valid() && shortcut_stack && shortcut_stack_capacity > 0 &&
                   ch_path && ch_path_capacity > 0;
    }

    bool edge_target_weight(std::uint32_t edge_index, std::uint32_t &target, std::uint32_t &weight) const noexcept {
        if (edge_index >= header.edge_count) return false;
        const std::size_t i = static_cast<std::size_t>(edge_index) * 4;
        return read_scalar(bytes, static_cast<std::size_t>(header.target_offset) + i, target) &&
               read_scalar(bytes, static_cast<std::size_t>(header.weight_offset) + i, weight);
    }

    bool edge_source_weight(std::uint32_t edge_index, std::uint32_t &source, std::uint32_t &weight) const noexcept {
        if (edge_index >= header.edge_count) return false;
        const std::size_t i = static_cast<std::size_t>(edge_index) * 4;
        return read_scalar(bytes, static_cast<std::size_t>(header.source_offset) + i, source) &&
               read_scalar(bytes, static_cast<std::size_t>(header.weight_offset) + i, weight);
    }

    bool cold_edge(std::uint32_t edge_index, std::int32_t &original, std::int32_t &left, std::int32_t &right) const noexcept {
        if (edge_index >= header.edge_count) return false;
        const std::size_t i = static_cast<std::size_t>(edge_index) * 4;
        return read_scalar(bytes, static_cast<std::size_t>(header.original_offset) + i, original) &&
               read_scalar(bytes, static_cast<std::size_t>(header.left_offset) + i, left) &&
               read_scalar(bytes, static_cast<std::size_t>(header.right_offset) + i, right);
    }

    bool refs(std::uint32_t node, bool forward, std::uint32_t &start, std::uint32_t &end) const noexcept {
        if (node >= header.node_count) return false;
        const std::uint64_t offsets = forward ? header.up_offsets_offset : header.down_offsets_offset;
        const std::uint32_t count = forward ? header.up_ref_count : header.down_ref_count;
        if (!read_scalar(bytes, static_cast<std::size_t>(offsets) + static_cast<std::size_t>(node) * 4, start) ||
            !read_scalar(bytes, static_cast<std::size_t>(offsets) + static_cast<std::size_t>(node + 1) * 4, end)) return false;
        return start <= end && end <= count;
    }

    bool ref_at(std::uint32_t position, bool forward, std::uint32_t &edge_index) const noexcept {
        const std::uint32_t count = forward ? header.up_ref_count : header.down_ref_count;
        if (position >= count) return false;
        const std::uint64_t base = forward ? header.up_refs_offset : header.down_refs_offset;
        return read_scalar(bytes, static_cast<std::size_t>(base) + static_cast<std::size_t>(position) * 4, edge_index);
    }

    QueryResult fail(QueryFailure failure, const QueryStats &stats = {}) const noexcept {
        QueryResult result;
        result.failure = failure;
        result.stats = stats;
        return result;
    }

    QueryFailure unpack(std::uint32_t edge_index, std::uint32_t *output, std::size_t capacity,
                        std::size_t &count, QueryStats &stats) noexcept {
        std::uint32_t stack_size = 0;
        shortcut_stack[stack_size++] = edge_index;
        while (stack_size > 0) {
            const std::uint32_t current = shortcut_stack[--stack_size];
            std::int32_t original = -1, left = -1, right = -1;
            if (!cold_edge(current, original, left, right)) return QueryFailure::InvalidData;
            if (original >= 0) {
                if (count >= capacity) return QueryFailure::OutputOverflow;
                output[count++] = static_cast<std::uint32_t>(original);
                continue;
            }
            ++stats.shortcut_unpacked;
            if (left < 0 || right < 0) return QueryFailure::InvalidData;
            if (stack_size + 2 > shortcut_stack_capacity) return QueryFailure::ShortcutStackOverflow;
            shortcut_stack[stack_size++] = static_cast<std::uint32_t>(right);
            shortcut_stack[stack_size++] = static_cast<std::uint32_t>(left);
        }
        return QueryFailure::None;
    }

    QueryResult route(std::uint32_t start, std::uint32_t target, std::uint32_t requested_preference,
                      float requested_penalty, std::uint32_t *output, std::size_t capacity) noexcept {
        if (!is_valid || !output || capacity == 0) return fail(QueryFailure::InvalidData);
        if (start >= header.node_count || target >= header.node_count) return fail(QueryFailure::InvalidNode);
        if (requested_preference != header.preference_code || std::abs(requested_penalty - header.avoid_penalty) > 1e-5f)
            return fail(QueryFailure::PolicyMismatch);
        if (start == target) {
            QueryResult result;
            result.success = true;
            result.failure = QueryFailure::None;
            return result;
        }

        forward_state.begin_query();
        backward_state.begin_query();
        forward_heap.clear();
        backward_heap.clear();
        StateSlot *fs = forward_state.get_or_insert(start);
        StateSlot *bs = backward_state.get_or_insert(target);
        if (!fs || !bs) return fail(QueryFailure::StateOverflow);
        fs->distance = 0;
        bs->distance = 0;
        if (!forward_heap.push({0, start}) || !backward_heap.push({0, target})) return fail(QueryFailure::QueueOverflow);

        std::uint64_t best_path = INF;
        std::uint32_t meeting = NO_INDEX;
        QueryStats stats;
        while (!forward_heap.empty() || !backward_heap.empty()) {
            const std::uint64_t fk = forward_heap.empty() ? INF : forward_heap.top().distance;
            const std::uint64_t bk = backward_heap.empty() ? INF : backward_heap.top().distance;
            if (best_path != INF && fk != INF && bk != INF && fk <= INF - bk && fk + bk >= best_path) break;

            const bool forward = fk <= bk;
            FixedBinaryHeap &heap = forward ? forward_heap : backward_heap;
            SparseState &state = forward ? forward_state : backward_state;
            SparseState &other_state = forward ? backward_state : forward_state;
            if (heap.empty()) break;
            const HeapItem item = heap.pop();
            StateSlot *current = state.find(item.node);
            if (!current || current->distance != item.distance) continue;
            ++stats.settled;

            if (StateSlot *other = other_state.find(item.node); other && item.distance <= INF - other->distance) {
                const std::uint64_t total = item.distance + other->distance;
                if (total < best_path || (total == best_path && item.node < meeting)) { best_path = total; meeting = item.node; }
            }

            std::uint32_t begin = 0, end = 0;
            if (!refs(item.node, forward, begin, end)) return fail(QueryFailure::InvalidData, stats);
            for (std::uint32_t position = begin; position < end; ++position) {
                std::uint32_t edge_index = 0, next = 0, weight = 0;
                if (!ref_at(position, forward, edge_index)) return fail(QueryFailure::InvalidData, stats);
                const bool ok = forward ? edge_target_weight(edge_index, next, weight) : edge_source_weight(edge_index, next, weight);
                if (!ok) return fail(QueryFailure::InvalidData, stats);
                ++stats.relaxed;
                if (item.distance > INF - weight) continue;
                const std::uint64_t candidate = item.distance + weight;
                StateSlot *next_slot = state.get_or_insert(next);
                if (!next_slot) return fail(QueryFailure::StateOverflow, stats);
                if (candidate < next_slot->distance) {
                    next_slot->distance = candidate;
                    next_slot->parent_node = item.node;
                    next_slot->parent_edge = edge_index;
                    if (!heap.push({candidate, next})) return fail(QueryFailure::QueueOverflow, stats);
                }
                if (StateSlot *other = other_state.find(next); other && candidate <= INF - other->distance) {
                    const std::uint64_t total = candidate + other->distance;
                    if (total < best_path || (total == best_path && next < meeting)) { best_path = total; meeting = next; }
                }
            }
            stats.queue_peak = std::max({stats.queue_peak, forward_heap.peak(), backward_heap.peak()});
            stats.state_peak = std::max({stats.state_peak, forward_state.peak(), backward_state.peak()});
        }
        if (meeting == NO_INDEX || best_path == INF) return fail(QueryFailure::Unreachable, stats);

        std::uint32_t before_count = 0;
        std::uint32_t current_node = meeting;
        while (current_node != start) {
            StateSlot *slot = forward_state.find(current_node);
            if (!slot || slot->parent_edge == NO_INDEX || slot->parent_node == NO_INDEX) return fail(QueryFailure::InvalidData, stats);
            if (before_count >= ch_path_capacity) return fail(QueryFailure::OutputOverflow, stats);
            ch_path[before_count++] = slot->parent_edge;
            current_node = slot->parent_node;
        }
        std::size_t output_count = 0;
        for (std::uint32_t i = before_count; i > 0; --i) {
            const QueryFailure failure = unpack(ch_path[i - 1], output, capacity, output_count, stats);
            if (failure != QueryFailure::None) return fail(failure, stats);
        }
        current_node = meeting;
        while (current_node != target) {
            StateSlot *slot = backward_state.find(current_node);
            if (!slot || slot->parent_edge == NO_INDEX || slot->parent_node == NO_INDEX) return fail(QueryFailure::InvalidData, stats);
            const QueryFailure failure = unpack(slot->parent_edge, output, capacity, output_count, stats);
            if (failure != QueryFailure::None) return fail(failure, stats);
            current_node = slot->parent_node;
        }

        QueryResult result;
        result.success = true;
        result.failure = QueryFailure::None;
        result.cost = static_cast<double>(best_path) / static_cast<double>(header.weight_scale);
        result.edge_count = output_count;
        result.stats = stats;
        return result;
    }
};

RoutingContext::RoutingContext(ByteView bch2, ContextConfig config) : impl_(new Impl(bch2, config)) {}
RoutingContext::~RoutingContext() = default;
RoutingContext::RoutingContext(RoutingContext &&) noexcept = default;
RoutingContext &RoutingContext::operator=(RoutingContext &&) noexcept = default;
bool RoutingContext::valid() const noexcept { return impl_ && impl_->is_valid; }
std::uint32_t RoutingContext::node_count() const noexcept { return valid() ? impl_->header.node_count : 0; }
std::uint32_t RoutingContext::edge_count() const noexcept { return valid() ? impl_->header.edge_count : 0; }
std::uint32_t RoutingContext::preference_code() const noexcept { return valid() ? impl_->header.preference_code : 0; }
std::uint32_t RoutingContext::weight_scale() const noexcept { return valid() ? impl_->header.weight_scale : 0; }
float RoutingContext::avoid_penalty() const noexcept { return valid() ? impl_->header.avoid_penalty : 0.0f; }
QueryResult RoutingContext::route_nodes(std::uint32_t start, std::uint32_t target, std::uint32_t preference,
                                       float penalty, std::uint32_t *output, std::size_t capacity) noexcept {
    if (!impl_) return {};
    return impl_->route(start, target, preference, penalty, output, capacity);
}
const char *query_failure_name(QueryFailure failure) noexcept {
    switch (failure) {
        case QueryFailure::None: return "";
        case QueryFailure::InvalidData: return "invalid_data";
        case QueryFailure::InvalidNode: return "invalid_node";
        case QueryFailure::PolicyMismatch: return "policy_mismatch";
        case QueryFailure::Unreachable: return "unreachable";
        case QueryFailure::StateOverflow: return "state_overflow";
        case QueryFailure::QueueOverflow: return "queue_overflow";
        case QueryFailure::OutputOverflow: return "output_overflow";
        case QueryFailure::ShortcutStackOverflow: return "shortcut_stack_overflow";
    }
    return "invalid_data";
}

} // namespace brur::gps::ch
