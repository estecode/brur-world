#include "gps_ch_runtime.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>
#include <utility>

namespace brur::gps::ch {
namespace {
constexpr std::size_t HEADER_SIZE = 84;
constexpr std::size_t EDGE_SIZE = 28;
constexpr std::uint32_t VERSION = 1;
constexpr std::uint32_t EMPTY_NODE = 0xffffffffu;
constexpr std::uint32_t NO_INDEX = 0xffffffffu;

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

struct EdgeRecord {
    std::uint32_t source = 0;
    std::uint32_t target = 0;
    double cost = 0.0;
    std::int32_t original = -1;
    std::int32_t left = -1;
    std::int32_t right = -1;
};

struct StateSlot {
    std::uint32_t node = EMPTY_NODE;
    std::uint32_t epoch = 0;
    double distance = std::numeric_limits<double>::infinity();
    std::uint32_t parent_node = NO_INDEX;
    std::uint32_t parent_edge = NO_INDEX;
};

struct HeapItem {
    double distance = 0.0;
    std::uint32_t node = 0;
};

class FixedHeap {
public:
    explicit FixedHeap(std::uint32_t capacity)
        : items_(capacity ? new (std::nothrow) HeapItem[capacity] : nullptr), capacity_(capacity) {}

    bool valid() const noexcept { return capacity_ > 0 && items_ != nullptr; }
    void clear() noexcept { size_ = 0; peak_ = 0; }
    bool empty() const noexcept { return size_ == 0; }
    std::uint32_t peak() const noexcept { return peak_; }
    const HeapItem &top() const noexcept { return items_[0]; }

    bool push(HeapItem item) noexcept {
        if (size_ >= capacity_) return false;
        std::uint32_t index = size_++;
        if (size_ > peak_) peak_ = size_;
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
                slot.distance = std::numeric_limits<double>::infinity();
                slot.parent_node = NO_INDEX;
                slot.parent_edge = NO_INDEX;
                if (++used_ > peak_) peak_ = used_;
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
    float avoid_penalty = 0.0f;
    std::uint64_t rank_offset = 0;
    std::uint64_t edge_offset = 0;
    std::uint64_t up_offsets_offset = 0;
    std::uint64_t up_refs_offset = 0;
    std::uint64_t down_offsets_offset = 0;
    std::uint64_t down_refs_offset = 0;
};

bool parse_header(ByteView bytes, Header &out) noexcept {
    if (!bytes.data || bytes.size < HEADER_SIZE || std::memcmp(bytes.data, "BCH1", 4) != 0) return false;
    std::uint32_t reserved = 0;
    if (!read_scalar(bytes, 4, out.version) || out.version != VERSION ||
        !read_scalar(bytes, 8, out.node_count) || !read_scalar(bytes, 12, out.edge_count) ||
        !read_scalar(bytes, 16, out.up_ref_count) || !read_scalar(bytes, 20, out.down_ref_count) ||
        !read_scalar(bytes, 24, out.preference_code) || !read_scalar(bytes, 28, reserved) ||
        !read_scalar(bytes, 32, out.avoid_penalty) || !read_scalar(bytes, 36, out.rank_offset) ||
        !read_scalar(bytes, 44, out.edge_offset) || !read_scalar(bytes, 52, out.up_offsets_offset) ||
        !read_scalar(bytes, 60, out.up_refs_offset) || !read_scalar(bytes, 68, out.down_offsets_offset) ||
        !read_scalar(bytes, 76, out.down_refs_offset)) return false;
    if (out.node_count == 0) return false;

    const std::uint64_t expected_rank = HEADER_SIZE;
    const std::uint64_t expected_edge = expected_rank + static_cast<std::uint64_t>(out.node_count) * 4;
    const std::uint64_t expected_up_offsets = expected_edge + static_cast<std::uint64_t>(out.edge_count) * EDGE_SIZE;
    const std::uint64_t expected_up_refs = expected_up_offsets + static_cast<std::uint64_t>(out.node_count + 1) * 4;
    const std::uint64_t expected_down_offsets = expected_up_refs + static_cast<std::uint64_t>(out.up_ref_count) * 4;
    const std::uint64_t expected_down_refs = expected_down_offsets + static_cast<std::uint64_t>(out.node_count + 1) * 4;
    const std::uint64_t expected_size = expected_down_refs + static_cast<std::uint64_t>(out.down_ref_count) * 4;

    return out.rank_offset == expected_rank && out.edge_offset == expected_edge &&
           out.up_offsets_offset == expected_up_offsets && out.up_refs_offset == expected_up_refs &&
           out.down_offsets_offset == expected_down_offsets && out.down_refs_offset == expected_down_refs &&
           expected_size == bytes.size;
}

} // namespace

struct RoutingContext::Impl {
    ByteView bytes;
    Header header;
    SparseState forward_state;
    SparseState backward_state;
    FixedHeap forward_heap;
    FixedHeap backward_heap;
    std::unique_ptr<std::uint32_t[]> shortcut_stack;
    std::uint32_t shortcut_stack_capacity = 0;
    std::unique_ptr<std::uint32_t[]> ch_path;
    std::uint32_t ch_path_capacity = 0;
    bool is_valid = false;

    Impl(ByteView input, ContextConfig config)
        : bytes(input),
          forward_state(config.state_capacity_per_direction),
          backward_state(config.state_capacity_per_direction),
          forward_heap(config.queue_capacity_per_direction),
          backward_heap(config.queue_capacity_per_direction),
          shortcut_stack(config.shortcut_stack_capacity
                             ? new (std::nothrow) std::uint32_t[config.shortcut_stack_capacity]
                             : nullptr),
          shortcut_stack_capacity(config.shortcut_stack_capacity),
          ch_path(config.ch_path_capacity ? new (std::nothrow) std::uint32_t[config.ch_path_capacity] : nullptr),
          ch_path_capacity(config.ch_path_capacity) {
        is_valid = parse_header(bytes, header) && forward_state.valid() && backward_state.valid() &&
                   forward_heap.valid() && backward_heap.valid() && shortcut_stack_capacity > 0 &&
                   shortcut_stack != nullptr && ch_path_capacity > 0 && ch_path != nullptr;
    }

    bool edge(std::uint32_t edge_index, EdgeRecord &out) const noexcept {
        if (edge_index >= header.edge_count) return false;
        const std::size_t base = static_cast<std::size_t>(header.edge_offset) +
                                 static_cast<std::size_t>(edge_index) * EDGE_SIZE;
        return read_scalar(bytes, base, out.source) && read_scalar(bytes, base + 4, out.target) &&
               read_scalar(bytes, base + 8, out.cost) && read_scalar(bytes, base + 16, out.original) &&
               read_scalar(bytes, base + 20, out.left) && read_scalar(bytes, base + 24, out.right);
    }

    bool refs(std::uint32_t node, bool forward, std::uint32_t &start, std::uint32_t &end) const noexcept {
        if (node >= header.node_count) return false;
        const std::uint64_t offsets = forward ? header.up_offsets_offset : header.down_offsets_offset;
        const std::uint32_t count = forward ? header.up_ref_count : header.down_ref_count;
        if (!read_scalar(bytes, static_cast<std::size_t>(offsets) + static_cast<std::size_t>(node) * 4, start) ||
            !read_scalar(bytes, static_cast<std::size_t>(offsets) + static_cast<std::size_t>(node + 1) * 4, end)) {
            return false;
        }
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

    QueryFailure unpack(
        std::uint32_t edge_index,
        std::uint32_t *output,
        std::size_t capacity,
        std::size_t &count,
        QueryStats &stats) noexcept {
        std::uint32_t stack_size = 0;
        shortcut_stack[stack_size++] = edge_index;
        while (stack_size > 0) {
            const std::uint32_t current = shortcut_stack[--stack_size];
            EdgeRecord record;
            if (!edge(current, record)) return QueryFailure::InvalidData;
            if (record.original >= 0) {
                if (count >= capacity) return QueryFailure::OutputOverflow;
                output[count++] = static_cast<std::uint32_t>(record.original);
                continue;
            }
            ++stats.shortcut_unpacked;
            if (record.left < 0 || record.right < 0) return QueryFailure::InvalidData;
            if (stack_size + 2 > shortcut_stack_capacity) return QueryFailure::ShortcutStackOverflow;
            shortcut_stack[stack_size++] = static_cast<std::uint32_t>(record.right);
            shortcut_stack[stack_size++] = static_cast<std::uint32_t>(record.left);
        }
        return QueryFailure::None;
    }

    QueryResult route(
        std::uint32_t start,
        std::uint32_t target,
        std::uint32_t requested_preference,
        float requested_penalty,
        std::uint32_t *output,
        std::size_t capacity) noexcept {
        if (!is_valid || !output || capacity == 0) return fail(QueryFailure::InvalidData);
        if (start >= header.node_count || target >= header.node_count) return fail(QueryFailure::InvalidNode);
        if (requested_preference != header.preference_code ||
            std::abs(requested_penalty - header.avoid_penalty) > 1e-5f) {
            return fail(QueryFailure::PolicyMismatch);
        }

        QueryResult result;
        result.failure = QueryFailure::Unreachable;
        if (start == target) {
            result.success = true;
            result.failure = QueryFailure::None;
            return result;
        }

        forward_state.begin_query();
        backward_state.begin_query();
        forward_heap.clear();
        backward_heap.clear();

        StateSlot *forward_start = forward_state.get_or_insert(start);
        StateSlot *backward_start = backward_state.get_or_insert(target);
        if (!forward_start || !backward_start) return fail(QueryFailure::StateOverflow);
        forward_start->distance = 0.0;
        backward_start->distance = 0.0;
        if (!forward_heap.push({0.0, start}) || !backward_heap.push({0.0, target})) {
            return fail(QueryFailure::QueueOverflow);
        }

        double best_path = std::numeric_limits<double>::infinity();
        std::uint32_t meeting = NO_INDEX;
        QueryStats stats;

        while (!forward_heap.empty() || !backward_heap.empty()) {
            const double forward_key = forward_heap.empty()
                ? std::numeric_limits<double>::infinity()
                : forward_heap.top().distance;
            const double backward_key = backward_heap.empty()
                ? std::numeric_limits<double>::infinity()
                : backward_heap.top().distance;
            if (std::isfinite(best_path) && std::isfinite(forward_key) && std::isfinite(backward_key) &&
                forward_key + backward_key >= best_path - 1e-12) {
                break;
            }

            const bool expand_forward = forward_key <= backward_key;
            FixedHeap &heap = expand_forward ? forward_heap : backward_heap;
            SparseState &state = expand_forward ? forward_state : backward_state;
            SparseState &other_state = expand_forward ? backward_state : forward_state;
            const HeapItem item = heap.pop();
            StateSlot *current = state.find(item.node);
            if (!current || item.distance != current->distance) continue;
            ++stats.settled;

            if (StateSlot *other = other_state.find(item.node)) {
                const double total = item.distance + other->distance;
                if (total < best_path - 1e-12 ||
                    (std::abs(total - best_path) <= 1e-12 && item.node < meeting)) {
                    best_path = total;
                    meeting = item.node;
                }
            }

            std::uint32_t begin = 0;
            std::uint32_t end = 0;
            if (!refs(item.node, expand_forward, begin, end)) return fail(QueryFailure::InvalidData, stats);
            for (std::uint32_t position = begin; position < end; ++position) {
                std::uint32_t edge_index = 0;
                EdgeRecord record;
                if (!ref_at(position, expand_forward, edge_index) || !edge(edge_index, record)) {
                    return fail(QueryFailure::InvalidData, stats);
                }
                ++stats.relaxed;
                const std::uint32_t next = expand_forward ? record.target : record.source;
                const double candidate = item.distance + record.cost;
                StateSlot *next_slot = state.get_or_insert(next);
                if (!next_slot) return fail(QueryFailure::StateOverflow, stats);
                if (candidate < next_slot->distance - 1e-12) {
                    next_slot->distance = candidate;
                    next_slot->parent_node = item.node;
                    next_slot->parent_edge = edge_index;
                    if (!heap.push({candidate, next})) return fail(QueryFailure::QueueOverflow, stats);
                }

                if (StateSlot *other = other_state.find(next)) {
                    const double total = candidate + other->distance;
                    if (total < best_path - 1e-12 ||
                        (std::abs(total - best_path) <= 1e-12 && next < meeting)) {
                        best_path = total;
                        meeting = next;
                    }
                }
            }

            stats.queue_peak = std::max({stats.queue_peak, forward_heap.peak(), backward_heap.peak()});
            stats.state_peak = std::max({stats.state_peak, forward_state.peak(), backward_state.peak()});
        }

        if (meeting == NO_INDEX || !std::isfinite(best_path)) return fail(QueryFailure::Unreachable, stats);

        std::uint32_t before_count = 0;
        std::uint32_t current_node = meeting;
        while (current_node != start) {
            StateSlot *slot = forward_state.find(current_node);
            if (!slot || slot->parent_edge == NO_INDEX || slot->parent_node == NO_INDEX) {
                return fail(QueryFailure::InvalidData, stats);
            }
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
            if (!slot || slot->parent_edge == NO_INDEX || slot->parent_node == NO_INDEX) {
                return fail(QueryFailure::InvalidData, stats);
            }
            const QueryFailure failure = unpack(slot->parent_edge, output, capacity, output_count, stats);
            if (failure != QueryFailure::None) return fail(failure, stats);
            current_node = slot->parent_node;
        }

        result.success = true;
        result.failure = QueryFailure::None;
        result.cost = best_path;
        result.edge_count = output_count;
        result.stats = stats;
        return result;
    }
};

RoutingContext::RoutingContext(ByteView bch1, ContextConfig config)
    : impl_(new Impl(bch1, config)) {}
RoutingContext::~RoutingContext() = default;
RoutingContext::RoutingContext(RoutingContext &&) noexcept = default;
RoutingContext &RoutingContext::operator=(RoutingContext &&) noexcept = default;

bool RoutingContext::valid() const noexcept { return impl_ && impl_->is_valid; }
std::uint32_t RoutingContext::node_count() const noexcept { return valid() ? impl_->header.node_count : 0; }
std::uint32_t RoutingContext::edge_count() const noexcept { return valid() ? impl_->header.edge_count : 0; }
std::uint32_t RoutingContext::preference_code() const noexcept { return valid() ? impl_->header.preference_code : 0; }
float RoutingContext::avoid_penalty() const noexcept { return valid() ? impl_->header.avoid_penalty : 0.0f; }

QueryResult RoutingContext::route_nodes(
    std::uint32_t start,
    std::uint32_t target,
    std::uint32_t preference,
    float penalty,
    std::uint32_t *output,
    std::size_t capacity) noexcept {
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
