#define main brur_gps_route_cli_main
#include "gps_route_cli.cpp"
#undef main

#include <arpa/inet.h>
#include <cerrno>
#include <netinet/in.h>
#include <sstream>
#include <sys/socket.h>

// Resident localhost adapter for Godot GPS queries.
//
// Dependencies:
// - gps_route_cli.cpp owns route polyline construction and JSON semantics.
// - gps_runtime.cpp owns BRG1/BRS2 loading, snapping and A*.
// - Godot sends one projected-coordinate request per line over localhost TCP.
//
// The graph, snap index and routing context are created once and stay resident,
// avoiding a process launch plus graph/context setup for every gameplay query.

namespace {
std::string route_json(const Snap &start, const Snap &target, const RoutePolylineResult &route,
                       double start_snap_ms, double target_snap_ms, double route_ms) {
    std::ostringstream out;
    out << std::setprecision(12);
    out << "{\"success\":" << (route.metrics.ok ? "true" : "false")
        << ",\"start_snap_ms\":" << start_snap_ms
        << ",\"target_snap_ms\":" << target_snap_ms
        << ",\"route_ms\":" << route_ms
        << ",\"start_candidates\":" << start.candidates
        << ",\"target_candidates\":" << target.candidates
        << ",\"settled\":" << route.metrics.settled
        << ",\"relaxed\":" << route.metrics.relaxed
        << ",\"queue_peak\":" << route.metrics.queue_peak
        << ",\"distance_m\":" << route.metrics.distance_m
        << ",\"travel_time_s\":" << route.metrics.travel_time_s
        << ",\"steps\":" << route.metrics.steps
        << ",\"start_snap\":[" << start.x << ',' << start.y << ']'
        << ",\"target_snap\":[" << target.x << ',' << target.y << ']'
        << ",\"points\":[";
    for (size_t i = 0; i < route.points.size(); ++i) {
        if (i) out << ',';
        out << '[' << route.points[i].first << ',' << route.points[i].second << ']';
    }
    out << "]}\n";
    return out.str();
}

bool send_all(int fd, const std::string &payload) {
    size_t sent = 0;
    while (sent < payload.size()) {
        const ssize_t count = send(fd, payload.data() + sent, payload.size() - sent, 0);
        if (count <= 0) return false;
        sent += static_cast<size_t>(count);
    }
    return true;
}

std::string handle_query(const std::string &line, SnapIndex &snap_index, Router &router) {
    std::istringstream input(line);
    double start_x = 0.0;
    double start_y = 0.0;
    double target_x = 0.0;
    double target_y = 0.0;
    if (!(input >> start_x >> start_y >> target_x >> target_y)) {
        return "{\"success\":false,\"adapter_error\":\"bad_request\"}\n";
    }

    const auto a = std::chrono::steady_clock::now();
    const Snap start = snap_index.snap(start_x, start_y);
    const auto b = std::chrono::steady_clock::now();
    const Snap target = snap_index.snap(target_x, target_y);
    const auto c = std::chrono::steady_clock::now();
    const RoutePolylineResult route = route_with_polyline(router, start, target);
    const auto d = std::chrono::steady_clock::now();
    return route_json(start, target, route, elapsed_ms(a, b), elapsed_ms(b, c), elapsed_ms(c, d));
}
} // namespace

int main(int argc, char **argv) {
    try {
        const std::string graph_path = argc > 1 ? argv[1] : "world_data/routing.brg";
        const std::string snap_path = argc > 2 ? argv[2] : "world_data/routing_snap.brs";
        const int port = argc > 3 ? std::stoi(argv[3]) : 47741;

        const auto started = std::chrono::steady_clock::now();
        Graph graph(graph_path);
        SnapIndex snap_index(graph, snap_path);
        Router router(graph, snap_index.max_legal_speed_kmh);

        const int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) throw std::runtime_error("socket failed");
        int reuse = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        sockaddr_in address {};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = htons(static_cast<uint16_t>(port));
        if (bind(server_fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
            close(server_fd);
            throw std::runtime_error("bind failed on localhost:" + std::to_string(port));
        }
        if (listen(server_fd, 1) != 0) {
            close(server_fd);
            throw std::runtime_error("listen failed");
        }

        std::cerr << "[native-gps-server] ready on 127.0.0.1:" << port
                  << " | startup " << elapsed_ms(started, std::chrono::steady_clock::now()) << " ms\n";

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
                const ssize_t count = recv(client_fd, buffer, sizeof(buffer), 0);
                if (count <= 0) break;
                pending.append(buffer, static_cast<size_t>(count));
                while (true) {
                    const size_t newline = pending.find('\n');
                    if (newline == std::string::npos) break;
                    const std::string line = pending.substr(0, newline);
                    pending.erase(0, newline + 1);
                    if (line.empty()) continue;
                    if (!send_all(client_fd, handle_query(line, snap_index, router))) {
                        connected = false;
                        break;
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
