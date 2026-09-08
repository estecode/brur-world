#include "../../native/gps_search_index.h"

#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
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

std::vector<uint8_t> make_index() {
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
    return bytes;
}

} // namespace

int main() {
    const auto bytes = make_index();
    const IndexView index(bytes.data(), bytes.size());
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

    const auto poi = index.search("sodersjukhuset", 8);
    assert(poi.size() == 1);
    assert(poi[0].record.display == "Södersjukhuset");
    assert(poi[0].score.tier == 0);

    const auto none = index.search("definitely missing", 8);
    assert(none.empty());

    std::cout << "native gps search-index tests: OK\n";
    return 0;
}
