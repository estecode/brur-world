#include "gps_snap_runtime.h"

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

// Small file/CLI adapter for the portable BRS3 snap core.
//
// Dependencies:
// - gps_snap_runtime owns fixed-point candidate selection and snap decisions.
// - Standard file/iostream APIs are adapter-only and stay outside the core.

namespace {

std::vector<std::uint8_t> read_file(const std::string &path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) throw std::runtime_error("failed to open BRS3 file");
    const std::streamsize size = input.tellg();
    if (size <= 0) throw std::runtime_error("empty BRS3 file");
    input.seekg(0);
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
    if (!input.read(reinterpret_cast<char *>(bytes.data()), size)) {
        throw std::runtime_error("failed to read BRS3 file");
    }
    return bytes;
}

} // namespace

int main(int argc, char **argv) {
    using namespace brur::gps::snap;
    if (argc < 4 || argc > 5) {
        std::cerr << "usage: gps_snap_cli <brs3> <x> <y> [max-distance-m]\n";
        return 2;
    }

    try {
        const auto bytes = read_file(argv[1]);
        const double x = std::stod(argv[2]);
        const double y = std::stod(argv[3]);
        const double max_distance = argc == 5 ? std::stod(argv[4]) : 250.0;
        RoutingSnapContext context({bytes.data(), bytes.size()});
        if (!context.valid()) throw std::runtime_error("invalid BRS3 data");
        const SnapResult result = context.snap(x, y, max_distance);

        std::cout << std::setprecision(17)
                  << "{\"success\":" << (result.success ? "true" : "false")
                  << ",\"failure\":\"" << snap_failure_name(result.failure) << "\""
                  << ",\"x\":" << result.x
                  << ",\"y\":" << result.y
                  << ",\"distance_m\":" << result.distance_m
                  << ",\"candidates\":" << result.candidates
                  << ",\"directions\":[";
        for (std::uint8_t i = 0; i < result.direction_count; ++i) {
            if (i) std::cout << ',';
            std::cout << "{\"edge\":" << result.directions[i].edge_index
                      << ",\"fraction\":" << result.directions[i].fraction << '}';
        }
        std::cout << "]}\n";
        return result.success || result.failure == SnapFailure::NotFound ? 0 : 1;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
