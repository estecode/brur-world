#include "gps_ch_runtime.h"

#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

// Small file/CLI adapter for the portable CH query core.
//
// Dependencies:
// - gps_ch_runtime owns routing decisions and fixed query workspace.
// - Standard file/iostream APIs are adapter-only and stay outside the core.

namespace {

std::vector<std::uint8_t> read_file(const std::string &path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) throw std::runtime_error("failed to open BCH file");
    const std::streamsize size = input.tellg();
    if (size <= 0) throw std::runtime_error("empty BCH file");
    input.seekg(0);
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
    if (!input.read(reinterpret_cast<char *>(bytes.data()), size)) {
        throw std::runtime_error("failed to read BCH file");
    }
    return bytes;
}

} // namespace

int main(int argc, char **argv) {
    using namespace brur::gps::ch;
    if (argc != 6) {
        std::cerr << "usage: gps_ch_cli <bch> <start> <target> <preference-code> <avoid-penalty>\n";
        return 2;
    }

    try {
        const auto bytes = read_file(argv[1]);
        const auto start = static_cast<std::uint32_t>(std::stoul(argv[2]));
        const auto target = static_cast<std::uint32_t>(std::stoul(argv[3]));
        const auto preference = static_cast<std::uint32_t>(std::stoul(argv[4]));
        const float penalty = std::stof(argv[5]);

        RoutingContext context({bytes.data(), bytes.size()});
        if (!context.valid()) throw std::runtime_error("invalid BCH1 data");

        std::array<std::uint32_t, 65536> route_edges{};
        const QueryResult result = context.route_nodes(
            start,
            target,
            preference,
            penalty,
            route_edges.data(),
            route_edges.size());

        std::cout << std::setprecision(17)
                  << "{\"success\":" << (result.success ? "true" : "false")
                  << ",\"failure\":\"" << query_failure_name(result.failure) << "\""
                  << ",\"cost\":" << result.cost
                  << ",\"settled\":" << result.stats.settled
                  << ",\"relaxed\":" << result.stats.relaxed
                  << ",\"queue_peak\":" << result.stats.queue_peak
                  << ",\"state_peak\":" << result.stats.state_peak
                  << ",\"shortcut_unpacked\":" << result.stats.shortcut_unpacked
                  << ",\"edges\":[";
        for (std::size_t i = 0; i < result.edge_count; ++i) {
            if (i) std::cout << ',';
            std::cout << route_edges[i];
        }
        std::cout << "]}\n";
        return result.success || result.failure == QueryFailure::Unreachable ? 0 : 1;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
