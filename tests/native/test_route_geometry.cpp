#include "../../native/gps_route_geometry.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>

// Verifies portable BRH1 route densification for forward/reverse traversal and partial-edge snaps.
// Dependencies: native/gps_route_geometry.h and standard C++20 only.

namespace {

template <class T>
void append_value(std::vector<std::uint8_t> &bytes, T value) {
    const auto *raw = reinterpret_cast<const std::uint8_t *>(&value);
    bytes.insert(bytes.end(), raw, raw + sizeof(T));
}

void append_edge(std::vector<std::uint8_t> &bytes, std::uint32_t offset,
                 std::uint32_t count, bool reversed) {
    append_value(bytes, offset);
    append_value(bytes, count);
    bytes.push_back(reversed ? 1 : 0);
    bytes.insert(bytes.end(), 3, 0);
}

void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}

bool near(double a, double b) { return std::abs(a - b) < 1e-5; }

brur::gps::RouteResult one_edge_result(std::uint32_t edge_index,
                                       brur::gps::RoutePoint start,
                                       brur::gps::RoutePoint target) {
    brur::gps::RouteLegResult leg;
    leg.success = true;
    leg.failure = brur::gps::RouteFailure::None;
    leg.points = {start, target};
    leg.edge_indices = {edge_index};

    brur::gps::RouteResult result;
    result.success = true;
    result.failure = brur::gps::RouteFailure::None;
    result.points = leg.points;
    result.legs = {leg};
    return result;
}

} // namespace

int main() {
    try {
        std::vector<std::uint8_t> bytes;
        bytes.insert(bytes.end(), {'B', 'R', 'H', '1'});
        append_value<std::uint32_t>(bytes, 2);
        append_value<std::uint32_t>(bytes, 3);
        append_edge(bytes, 0, 3, false);
        append_edge(bytes, 0, 3, true);
        append_value<float>(bytes, 0.0f); append_value<float>(bytes, 0.0f);
        append_value<float>(bytes, 5.0f); append_value<float>(bytes, 8.0f);
        append_value<float>(bytes, 10.0f); append_value<float>(bytes, 0.0f);

        brur::gps::RouteGeometryView geometry({bytes.data(), bytes.size()});
        require(geometry.edge_count() == 2, "edge count");

        auto forward = one_edge_result(0, {0.0, 0.0}, {10.0, 0.0});
        geometry.densify(forward);
        require(forward.points.size() == 3, "forward curved edge must preserve middle shape point");
        require(near(forward.points[1].x, 5.0) && near(forward.points[1].y, 8.0),
                "forward middle shape point");

        auto reverse = one_edge_result(1, {10.0, 0.0}, {0.0, 0.0});
        geometry.densify(reverse);
        require(reverse.points.size() == 3, "reverse curved edge must preserve middle shape point");
        require(near(reverse.points.front().x, 10.0) && near(reverse.points.back().x, 0.0),
                "reverse geometry traversal order");
        require(near(reverse.points[1].x, 5.0) && near(reverse.points[1].y, 8.0),
                "reverse middle shape point");

        auto partial = one_edge_result(0, {2.5, 4.0}, {7.5, 4.0});
        geometry.densify(partial);
        require(partial.points.size() >= 3, "partial edge must keep curved geometry between snaps");
        require(near(partial.points.front().x, 2.5) && near(partial.points.back().x, 7.5),
                "partial route preserves anchors already on detailed shape");

        auto chord_snapped = one_edge_result(0, {2.5, 0.0}, {7.5, 0.0});
        geometry.densify(chord_snapped);
        require(chord_snapped.points.size() >= 3,
                "chord-snapped partial edge must keep detailed curved geometry");
        require(chord_snapped.points.front().y > 0.5 && chord_snapped.points.back().y > 0.5,
                "visible partial-edge endpoints must be projected onto detailed road shape");
        require(!(near(chord_snapped.points.front().x, 2.5) && near(chord_snapped.points.front().y, 0.0)),
                "raw BRG1 chord start must not create an off-road connector");
        require(!(near(chord_snapped.points.back().x, 7.5) && near(chord_snapped.points.back().y, 0.0)),
                "raw BRG1 chord target must not create an off-road connector");

        std::cout << "native route geometry tests: OK\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "native route geometry tests failed: " << error.what() << '\n';
        return 1;
    }
}
