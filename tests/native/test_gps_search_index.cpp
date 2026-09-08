#include "../../native/gps_search_index.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <vector>

using brur::gps::search::IndexView;

namespace {

void put_u32(std::vector<uint8_t> &bytes, std::size_t offset, uint32_t value) {
    bytes[offset + 0] = static_cast<uint8_t>(value);
    bytes[offset + 1] = static_cast<uint8_t>(value >> 8);
    bytes[offset + 2] = static_cast<uint8_t>(value >> 16);
    bytes[offset + 3] = static_cast<uint8_t>(value >> 24);
}

void put_u64(std::vector<uint8_t> &bytes, std::size_t offset, uint64_t value) {
    for (unsigned i = 0; i < 8; ++i) bytes[offset + i] = static_cast<uint8_t>(value >> (8u * i));
}

void put_f64(std::vector<uint8_t> &bytes, std::size_t offset, double value) {
    uint64_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    put_u64(bytes, offset, bits);
}

uint32_t trigram_key(std::string_view value) {
    return static_cast<uint32_t>(static_cast<unsigned char>(value[0])) |
           (static_cast<uint32_t>(static_cast<unsigned char>(value[1])) << 8) |
           (static_cast<uint32_t>(static_cast<unsigned char>(value[2])) << 16);
}

struct FixtureRecord {
    std::string id;
    std::string kind;
    std::string display;
    std::string subtitle;
    std::string display_normalized;
    std::string search;
    double x;
    double y;
};

std::set<uint32_t> record_trigrams(const FixtureRecord &record) {
    std::set<uint32_t> keys;
    const std::string combined = record.display_normalized + " " + record.search;
    std::size_t start = 0;
    while (start < combined.size()) {
        while (start < combined.size() && combined[start] == ' ') ++start;
        if (start >= combined.size()) break;
        const std::size_t end = combined.find(' ', start);
        const std::size_t stop = end == std::string::npos ? combined.size() : end;
        if (stop - start >= 3) {
            for (std::size_t i = start; i + 3 <= stop; ++i)
                keys.insert(trigram_key(std::string_view(combined).substr(i, 3)));
        }
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return keys;
}

std::vector<uint8_t> make_index(bool accelerated) {
    const std::vector<FixtureRecord> records = {
        {"address:node:1", "address", "Kungsljusgatan 22", "24756 Dalby",
         "kungsljusgatan 22", "kungsljusgatan 22 24756 dalby", 1.25, 2.5},
        {"poi:node:2", "poi", "Södersjukhuset", "Stockholm",
         "sodersjukhuset", "sodersjukhuset stockholm hospital", 3.0, 4.0},
    };

    constexpr std::size_t header_size = brur::gps::search::BSI2_HEADER_SIZE;
    constexpr std::size_t record_size = brur::gps::search::BSI2_RECORD_SIZE;
    const std::size_t records_offset = header_size;
    const std::size_t strings_offset = records_offset + records.size() * record_size;

    std::vector<uint8_t> strings;
    struct Span { uint32_t offset; uint32_t length; };
    std::vector<std::vector<Span>> spans;
    for (const auto &record : records) {
        const std::vector<std::string> values = {
            record.id, record.kind, record.display, record.subtitle,
            record.display_normalized, record.search,
        };
        std::vector<Span> record_spans;
        for (const auto &value : values) {
            const uint32_t offset = static_cast<uint32_t>(strings.size());
            strings.insert(strings.end(), value.begin(), value.end());
            record_spans.push_back({offset, static_cast<uint32_t>(value.size())});
        }
        spans.push_back(record_spans);
    }

    std::vector<uint8_t> bytes(strings_offset + strings.size(), 0);
    std::memcpy(bytes.data(), "BSI2", 4);
    put_u32(bytes, 4, static_cast<uint32_t>(record_size));
    put_u32(bytes, 8, static_cast<uint32_t>(records.size()));
    put_u32(bytes, 12, 0);
    put_u64(bytes, 16, records_offset);
    put_u64(bytes, 24, strings_offset);

    for (std::size_t i = 0; i < records.size(); ++i) {
        const std::size_t base = records_offset + i * record_size;
        for (std::size_t field = 0; field < spans[i].size(); ++field) {
            put_u32(bytes, base + field * 8, spans[i][field].offset);
            put_u32(bytes, base + field * 8 + 4, spans[i][field].length);
        }
        put_u32(bytes, base + 48, static_cast<uint32_t>(records[i].display.size()));
        put_u32(bytes, base + 52, 0);
        put_f64(bytes, base + 56, records[i].x);
        put_f64(bytes, base + 64, records[i].y);
    }
    std::memcpy(bytes.data() + strings_offset, strings.data(), strings.size());

    if (!accelerated) return bytes;

    std::map<uint32_t, std::vector<uint32_t>> postings;
    for (uint32_t record_index = 0; record_index < records.size(); ++record_index)
        for (const uint32_t key : record_trigrams(records[record_index]))
            postings[key].push_back(record_index);

    const uint64_t entries_offset = bytes.size();
    uint32_t posting_start = 0;
    for (const auto &[key, values] : postings) {
        const std::size_t offset = bytes.size();
        bytes.resize(offset + brur::gps::search::BSA1_ENTRY_SIZE);
        put_u32(bytes, offset, key);
        put_u32(bytes, offset + 4, posting_start);
        put_u32(bytes, offset + 8, static_cast<uint32_t>(values.size()));
        posting_start += static_cast<uint32_t>(values.size());
    }

    const uint64_t postings_offset = bytes.size();
    for (const auto &[key, values] : postings) {
        (void)key;
        for (const uint32_t value : values) {
            const std::size_t offset = bytes.size();
            bytes.resize(offset + 4);
            put_u32(bytes, offset, value);
        }
    }

    const uint64_t footer_offset = bytes.size();
    bytes.resize(bytes.size() + brur::gps::search::BSA1_FOOTER_SIZE);
    std::memcpy(bytes.data() + footer_offset, "BSA1", 4);
    put_u32(bytes, footer_offset + 4, brur::gps::search::BSA1_ENTRY_SIZE);
    put_u32(bytes, footer_offset + 8, static_cast<uint32_t>(postings.size()));
    put_u32(bytes, footer_offset + 12, posting_start);
    put_u64(bytes, footer_offset + 16, entries_offset);
    put_u64(bytes, footer_offset + 24, postings_offset);
    put_u64(bytes, footer_offset + 32, footer_offset);
    return bytes;
}

void verify_queries(const IndexView &index) {
    assert(index.count() == 2);

    const auto exact = index.search("kungsljusgatan 22", 8);
    assert(exact.size() == 1);
    assert(exact[0].record.id == "address:node:1");
    assert(exact[0].record.subtitle == "24756 Dalby");
    assert(exact[0].score.tier == 0);
    assert(exact[0].record.x == 1.25);
    assert(exact[0].record.y == 2.5);

    const auto full_address = index.search("kungsljusgatan 22 24756 dalby", 8);
    assert(full_address.size() == 1);
    assert(full_address[0].record.id == "address:node:1");
    assert(full_address[0].score.tier == 4);

    const auto substring = index.search("sljus", 8);
    assert(substring.size() == 1);
    assert(substring[0].record.id == "address:node:1");
    assert(substring[0].score.tier == 3);

    const auto poi = index.search("sodersjukhuset", 8);
    assert(poi.size() == 1);
    assert(poi[0].record.display == "Södersjukhuset");
    assert(poi[0].score.tier == 0);

    const auto none = index.search("definitely missing", 8);
    assert(none.empty());
}

} // namespace

int main() {
    const auto legacy_bytes = make_index(false);
    const IndexView legacy(legacy_bytes.data(), legacy_bytes.size());
    assert(!legacy.has_accelerator());
    verify_queries(legacy);

    const auto accelerated_bytes = make_index(true);
    const IndexView accelerated(accelerated_bytes.data(), accelerated_bytes.size());
    assert(accelerated.has_accelerator());
    assert(accelerated.accelerator_entry_count() > 0);
    assert(accelerated.accelerator_posting_count() > 0);
    verify_queries(accelerated);

    std::cout << "native gps search-index tests: OK\n";
    return 0;
}
