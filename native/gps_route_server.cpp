#include "gps_core.h"
#include "gps_mapped_data.h"
#include "gps_route_geometry.h"
#include "gps_route_protocol.h"

#include <arpa/inet.h>
#include <cerrno>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <netinet/in.h>
#include <sstream>
#include <string>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>

// Resident localhost adapter for native GPS routing.
//
// Dependencies:
// - gps_core owns snapping, legality, preferences, routing and ordered plan semantics.
// - gps_route_geometry expands chosen edges with BRH1 road-shape points before serialization.
// - gps_mapped_data owns POSIX file mapping/warming.
// - This file owns text parsing, JSON serialization, process priority and TCP only.

namespace {
using namespace brur::gps;
using brur::gps::adapter::MappedFile;
using brur::gps::adapter::MappedRoutingData;

template <class A, class B>
double elapsed_ms(A a, B b) {
    return std::chrono::duration<double, std::milli>(b - a).count();
}

std::string geometry_path_for_graph(const std::string &graph_path) {
    const auto separator = graph_path.find_last_of("/\\");
    const std::string parent = separator == std::string::npos ? "" : graph_path.substr(0, separator + 1);
    return parent + "routing_geometry.brh";
}

std::string error_json(const std::string &error) {
    return "{\"success\":false,\"adapter_error\":\"" + error + "\"}\n";
}

void append_json_result(std::ostringstream &out, const RouteResult &result,
                        double snap_ms, double route_ms) {
    out << std::setprecision(12)
        << "{\"success\":" << (result.success ? "true" : "false")
        << ",\"preference\":\"" << routing_preference_name(result.preference) << "\""
        << ",\"snap_ms\":" << snap_ms
        << ",\"route_ms\":" << route_ms
        << ",\"settled\":" << result.metrics.settled
        << ",\"relaxed\":" << result.metrics.relaxed
        << ",\"queue_peak\":" << result.metrics.queue_peak
        << ",\"distance_m\":" << result.metrics.distance_m
        << ",\"travel_time_s\":" << result.metrics.travel_time_s
        << ",\"steps\":" << result.metrics.steps;

    if (result.failed_leg_index == static_cast<std::size_t>(-1))
        out << ",\"failed_leg_index\":null";
    else
        out << ",\"failed_leg_index\":" << result.failed_leg_index;
    if (result.failure != RouteFailure::None)
        out << ",\"failure_reason\":\"" << route_failure_name(result.failure) << "\"";

    if (!result.snaps.empty())
        out << ",\"start_snap\":[" << result.snaps.front().x << ',' << result.snaps.front().y << ']';
    if (result.snaps.size() > 1)
        out << ",\"target_snap\":[" << result.snaps.back().x << ',' << result.snaps.back().y << ']';

    out << ",\"snaps\":[";
    for (std::size_t i = 0; i < result.snaps.size(); ++i) {
        if (i) out << ',';
        out << '[' << result.snaps[i].x << ',' << result.snaps[i].y << ']';
    }
    out << ']';

    out << ",\"legs\":[";
    for (std::size_t i = 0; i < result.legs.size(); ++i) {
        if (i) out << ',';
        const auto &leg = result.legs[i];
        out << "{\"index\":" << leg.leg_index
            << ",\"from_stop_index\":" << leg.from_stop_index
            << ",\"to_stop_index\":" << leg.to_stop_index
            << ",\"success\":" << (leg.success ? "true" : "false")
            << ",\"distance_m\":" << leg.metrics.distance_m
            << ",\"travel_time_s\":" << leg.metrics.travel_time_s
            << ",\"settled\":" << leg.metrics.settled
            << ",\"relaxed\":" << leg.metrics.relaxed
            << ",\"queue_peak\":" << leg.metrics.queue_peak
            << ",\"steps\":" << leg.metrics.steps
            << ",\"point_start_index\":" << leg.point_start_index
            << ",\"point_end_index\":" << leg.point_end_index;
        if (leg.failure != RouteFailure::None)
            out << ",\"failure_reason\":\"" << route_failure_name(leg.failure) << "\"";
        out << '}';
    }
    out << ']';

    out << ",\"points\":[";
    for (std::size_t i = 0; i < result.points.size(); ++i) {
        if (i) out << ',';
        out << '[' << result.points[i].x << ',' << result.points[i].y << ']';
    }
    out << "]}\n";
}

std::string handle_plan(const std::string &line, RoutingContext &core, const RouteGeometryView &geometry) {
    const auto parsed = parse_route_plan_request(line);
    if (!parsed.success) return error_json("bad_plan");

    RoutingPreference preference;
    if (!parse_routing_preference(parsed.request.preference, preference))
        return error_json("bad_preference");

    RoutePlanRequest request;
    request.preference = preference;
    request.stops.reserve(parsed.request.stops.size());
    double snap_ms = 0.0;
    for (std::size_t i = 0; i < parsed.request.stops.size(); ++i) {
        const auto started = std::chrono::steady_clock::now();
        auto snap = core.snap({parsed.request.stops[i].x, parsed.request.stops[i].y});
        const auto finished = std::chrono::steady_clock::now();
        snap_ms += elapsed_ms(started, finished);
        request.stops.push_back(std::move(snap));
        if (!request.stops.back().success) {
            RouteResult failed;
            failed.preference = preference;
            failed.failure = request.stops.back().failure;
            failed.failed_leg_index = i == 0 ? 0 : i - 1;
            for (const auto &stop : request.stops) {
                failed.snaps.push_back(stop.point);
                failed.snap_candidates.push_back(stop.candidates);
            }
            std::ostringstream out;
            append_json_result(out, failed, snap_ms, 0.0);
            return out.str();
        }
    }

    const auto route_started = std::chrono::steady_clock::now();
    auto result = core.route_plan(request);
    geometry.densify(result);
    const auto route_finished = std::chrono::steady_clock::now();
    std::ostringstream out;
    append_json_result(out, result, snap_ms, elapsed_ms(route_started, route_finished));
    return out.str();
}

std::string handle_direct(const std::string &line, RoutingContext &core, const RouteGeometryView &geometry) {
    std::istringstream input(line);
    double start_x = 0.0;
    double start_y = 0.0;
    double target_x = 0.0;
    double target_y = 0.0;
    if (!(input >> start_x >> start_y >> target_x >> target_y)) return error_json("bad_request");

    std::string preference_text = "fastest";
    input >> preference_text;
    std::string trailing;
    if (input >> trailing) return error_json("bad_request");

    RoutingPreference preference;
    if (!parse_routing_preference(preference_text, preference)) return error_json("bad_preference");

    const auto a = std::chrono::steady_clock::now();
    const auto start = core.snap({start_x, start_y});
    const auto target = core.snap({target_x, target_y});
    const auto c = std::chrono::steady_clock::now();

    RouteResult result;
    if (!start.success || !target.success) {
        result.preference = preference;
        result.failure = RouteFailure::SnapFailed;
        result.failed_leg_index = 0;
        result.snaps = {start.point, target.point};
        result.snap_candidates = {start.candidates, target.candidates};
    } else {
        result = core.route({start, target, preference});
        geometry.densify(result);
    }
    const auto d = std::chrono::steady_clock::now();

    std::ostringstream out;
    append_json_result(out, result, elapsed_ms(a, c), elapsed_ms(c, d));
    return out.str();
}

std::string handle_query(const std::string &line, RoutingContext &core, const RouteGeometryView &geometry) {
    if (line.rfind("plan ", 0) == 0) return handle_plan(line, core, geometry);
    return handle_direct(line, core, geometry);
}

bool send_all(int fd, const std::string &payload) {
    std::size_t sent = 0;
    while (sent < payload.size()) {
        const auto count = send(fd, payload.data() + sent, payload.size() - sent, 0);
        if (count <= 0) return false;
        sent += static_cast<std::size_t>(count);
    }
    return true;
}

void lower_background_priority() {
    if (setpriority(PRIO_PROCESS, 0, 8) != 0)
        std::cerr << "[native-gps-server] warning: could not lower process priority\n";
}
} // namespace

int main(int argc, char **argv) {
    try {
        const std::string graph_path = argc > 1 ? argv[1] : "world_data/routing.brg";
        const std::string snap_path = argc > 2 ? argv[2] : "world_data/routing_snap.brs";
        const int port = argc > 3 ? std::stoi(argv[3]) : 47741;
        const std::string geometry_path = geometry_path_for_graph(graph_path);

        lower_background_priority();
        const auto started = std::chrono::steady_clock::now();
        MappedRoutingData mapped(graph_path, snap_path);
        MappedFile mapped_geometry(geometry_path);
        RoutingContext core(mapped.view());
        RouteGeometryView geometry(mapped_geometry.view());
        if (geometry.edge_count() != core.edge_count())
            throw std::runtime_error("BRH1/BRG1 edge count mismatch");

        const auto warm_started = std::chrono::steady_clock::now();
        const auto checksum = brur::gps::adapter::warm_mapped_file(mapped.graph) ^
                              brur::gps::adapter::warm_mapped_file(mapped.snap) ^
                              brur::gps::adapter::warm_mapped_file(mapped_geometry);
        const auto warm_finished = std::chrono::steady_clock::now();

        const int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) throw std::runtime_error("socket failed");
        int reuse = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        sockaddr_in address {};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = htons(static_cast<std::uint16_t>(port));
        if (bind(server_fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
            close(server_fd);
            throw std::runtime_error("bind failed on localhost:" + std::to_string(port));
        }
        if (listen(server_fd, 1) != 0) {
            close(server_fd);
            throw std::runtime_error("listen failed");
        }

        std::cerr << "[native-gps-server] ready on 127.0.0.1:" << port
                  << " | nodes " << core.node_count()
                  << " | edges " << core.edge_count()
                  << " | shape points " << geometry.point_count()
                  << " | startup " << elapsed_ms(started, std::chrono::steady_clock::now()) << " ms"
                  << " | page warm " << elapsed_ms(warm_started, warm_finished) << " ms"
                  << " | checksum " << checksum << "\n";

        while (true) {
            const int client_fd = accept(server_fd, nullptr, nullptr);
            if (client_fd < 0) {
                if (errno == EINTR) continue;
                break;
            }
            std::string pending;
            char buffer[4096];
            bool connected = true;
            while (connected) {
                const auto count = recv(client_fd, buffer, sizeof(buffer), 0);
                if (count <= 0) break;
                pending.append(buffer, static_cast<std::size_t>(count));
                while (true) {
                    const auto newline = pending.find('\n');
                    if (newline == std::string::npos) break;
                    const auto line = pending.substr(0, newline);
                    pending.erase(0, newline + 1);
                    if (line.empty()) continue;
                    try {
                        if (!send_all(client_fd, handle_query(line, core, geometry))) {
                            connected = false;
                            break;
                        }
                    } catch (const std::exception &error) {
                        if (!send_all(client_fd, error_json(error.what()))) {
                            connected = false;
                            break;
                        }
                    }
                }
            }
            close(client_fd);
        }
        close(server_fd);
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "native gps server error: " << error.what() << "\n";
        return 1;
    }
}
