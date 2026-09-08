#pragma once

// Portable BSI2 search core for offline GPS address/POI lookup.
//
// Dependencies:
// - Standard C++20 only.
// - Consumes an immutable byte span; file mapping/loading belongs to adapters.
// - Query text must already be normalized to lowercase ASCII words using the
//   same normalization contract as tools/gps_search.py.

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace brur::gps::search {

constexpr std::size_t BSI2_HEADER_SIZE = 32;
constexpr std::size_t BSI2_RECORD_SIZE = 72;

inline uint32_t read_u32_le(const uint8_t *p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}

inline uint64_t read_u64_le(const uint8_t *p) {
    uint64_t value = 0;
    for (unsigned i = 0; i < 8; ++i) value |= static_cast<uint64_t>(p[i]) << (8u * i);
    return value;
}

inline double read_f64_le(const uint8_t *p) {
    const uint64_t bits = read_u64_le(p);
    double value = 0.0;
    static_assert(sizeof(value) == sizeof(bits));
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

struct RecordView {
    std::string_view id;
    std::string_view kind;
    std::string_view display;
    std::string_view subtitle;
    std::string_view display_normalized;
    std::string_view search_text;
    uint32_t display_char_length = 0;
    double x = 0.0;
    double y = 0.0;
};

struct Score {
    uint32_t tier = 0;
    uint32_t normalized_length_delta = 0;
    uint32_t display_char_length = 0;
    std::string_view id;
};

struct Result {
    RecordView record;
    Score score;
};

inline bool score_less(const Score &a, const Score &b) {
    if (a.tier != b.tier) return a.tier < b.tier;
    if (a.normalized_length_delta != b.normalized_length_delta)
        return a.normalized_length_delta < b.normalized_length_delta;
    if (a.display_char_length != b.display_char_length)
        return a.display_char_length < b.display_char_length;
    return a.id < b.id;
}

inline bool result_less(const Result &a, const Result &b) {
    return score_less(a.score, b.score);
}

inline std::vector<std::string_view> split_words(std::string_view text) {
    std::vector<std::string_view> words;
    std::size_t start = 0;
    while (start < text.size()) {
        while (start < text.size() && text[start] == ' ') ++start;
        if (start >= text.size()) break;
        const std::size_t end = text.find(' ', start);
        if (end == std::string_view::npos) {
            words.emplace_back(text.substr(start));
            break;
        }
        words.emplace_back(text.substr(start, end - start));
        start = end + 1;
    }
    return words;
}

inline bool all_tokens_prefix(const std::vector<std::string_view> &tokens, std::string_view words_text) {
    if (tokens.empty()) return false;
    for (const std::string_view token : tokens) {
        bool found = false;
        std::size_t start = 0;
        while (start < words_text.size()) {
            while (start < words_text.size() && words_text[start] == ' ') ++start;
            if (start >= words_text.size()) break;
            const std::size_t end = words_text.find(' ', start);
            const std::size_t length = (end == std::string_view::npos ? words_text.size() : end) - start;
            const std::string_view word = words_text.substr(start, length);
            if (word.size() >= token.size() && word.substr(0, token.size()) == token) {
                found = true;
                break;
            }
            if (end == std::string_view::npos) break;
            start = end + 1;
        }
        if (!found) return false;
    }
    return true;
}

inline bool match_score(std::string_view query,
                        const std::vector<std::string_view> &tokens,
                        const RecordView &record,
                        Score &score) {
    const auto display = record.display_normalized;
    const auto haystack = record.search_text;
    uint32_t tier = std::numeric_limits<uint32_t>::max();
    if (query == display) {
        tier = 0;
    } else if (display.size() >= query.size() && display.substr(0, query.size()) == query) {
        tier = 1;
    } else if (all_tokens_prefix(tokens, display)) {
        tier = 2;
    } else if (display.find(query) != std::string_view::npos) {
        tier = 3;
    } else if (all_tokens_prefix(tokens, haystack)) {
        tier = 4;
    } else if (haystack.find(query) != std::string_view::npos) {
        tier = 5;
    } else {
        return false;
    }
    score.tier = tier;
    score.normalized_length_delta = display.size() > query.size()
        ? static_cast<uint32_t>(display.size() - query.size()) : 0u;
    score.display_char_length = record.display_char_length;
    score.id = record.id;
    return true;
}

class IndexView {
public:
    IndexView() = default;
    IndexView(const uint8_t *data, std::size_t size) { reset(data, size); }

    void reset(const uint8_t *data, std::size_t size) {
        data_ = data;
        size_ = size;
        if (data_ == nullptr || size_ < BSI2_HEADER_SIZE)
            throw std::runtime_error("BSI2 file too small");
        if (std::string_view(reinterpret_cast<const char *>(data_), 4) != "BSI2")
            throw std::runtime_error("unsupported search index format");
        const uint32_t record_size = read_u32_le(data_ + 4);
        count_ = read_u32_le(data_ + 8);
        records_offset_ = read_u64_le(data_ + 16);
        strings_offset_ = read_u64_le(data_ + 24);
        if (record_size != BSI2_RECORD_SIZE)
            throw std::runtime_error("unsupported BSI2 record size");
        if (records_offset_ < BSI2_HEADER_SIZE || strings_offset_ < records_offset_ || strings_offset_ > size_)
            throw std::runtime_error("invalid BSI2 offsets");
        const uint64_t records_end = records_offset_ + static_cast<uint64_t>(count_) * BSI2_RECORD_SIZE;
        if (records_end != strings_offset_ || records_end > size_)
            throw std::runtime_error("invalid BSI2 record table");
    }

    uint32_t count() const { return count_; }

    RecordView record(uint32_t index) const {
        if (index >= count_) throw std::out_of_range("BSI2 record index");
        const uint8_t *p = data_ + records_offset_ + static_cast<uint64_t>(index) * BSI2_RECORD_SIZE;
        uint32_t fields[12] {};
        for (unsigned i = 0; i < 12; ++i) fields[i] = read_u32_le(p + i * 4);
        RecordView out;
        out.id = string_at(fields[0], fields[1]);
        out.kind = string_at(fields[2], fields[3]);
        out.display = string_at(fields[4], fields[5]);
        out.subtitle = string_at(fields[6], fields[7]);
        out.display_normalized = string_at(fields[8], fields[9]);
        out.search_text = string_at(fields[10], fields[11]);
        out.display_char_length = read_u32_le(p + 48);
        out.x = read_f64_le(p + 56);
        out.y = read_f64_le(p + 64);
        return out;
    }

    std::vector<Result> search(std::string_view normalized_query, std::size_t limit = 8) const {
        std::vector<Result> best;
        if (limit == 0 || normalized_query.empty()) return best;
        const auto tokens = split_words(normalized_query);
        best.reserve(limit);
        for (uint32_t i = 0; i < count_; ++i) {
            const RecordView item = record(i);
            Score score;
            if (!match_score(normalized_query, tokens, item, score)) continue;
            Result result {item, score};
            if (best.size() < limit) {
                best.push_back(result);
                if (best.size() == limit) std::sort(best.begin(), best.end(), result_less);
                continue;
            }
            if (!score_less(score, best.back().score)) continue;
            best.back() = result;
            for (std::size_t pos = best.size() - 1; pos > 0 && result_less(best[pos], best[pos - 1]); --pos)
                std::swap(best[pos], best[pos - 1]);
        }
        if (best.size() < limit) std::sort(best.begin(), best.end(), result_less);
        return best;
    }

private:
    std::string_view string_at(uint32_t offset, uint32_t length) const {
        const uint64_t begin = strings_offset_ + offset;
        const uint64_t end = begin + length;
        if (begin > size_ || end > size_) throw std::runtime_error("invalid BSI2 string span");
        return std::string_view(reinterpret_cast<const char *>(data_ + begin), length);
    }

    const uint8_t *data_ = nullptr;
    std::size_t size_ = 0;
    uint32_t count_ = 0;
    uint64_t records_offset_ = 0;
    uint64_t strings_offset_ = 0;
};

} // namespace brur::gps::search
