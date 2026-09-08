#include "gps_search_index.h"

#include <arpa/inet.h>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <fcntl.h>
#include <iomanip>
#include <iostream>
#include <netinet/in.h>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

// Resident localhost adapter for portable BSI2 GPS search.
//
// Dependencies:
// - gps_search_index.h owns deterministic search over an immutable byte span.
// - This file owns POSIX mmap, localhost TCP transport and JSON serialization.
// - It contains no routing or Godot presentation logic.

namespace {

class MappedFile {
public:
    explicit MappedFile(const std::string &path) {
        fd_ = open(path.c_str(), O_RDONLY);
        if (fd_ < 0) throw std::runtime_error("could not open search index: " + path);
        struct stat info {};
        if (fstat(fd_, &info) != 0 || info.st_size <= 0) {
            close(fd_);
            fd_ = -1;
            throw std::runtime_error("invalid search index file: " + path);
        }
        size_ = static_cast<std::size_t>(info.st_size);
        void *mapped = mmap(nullptr, size_, PROT_READ, MAP_PRIVATE, fd_, 0);
        if (mapped == MAP_FAILED) {
            close(fd_);
            fd_ = -1;
            throw std::runtime_error("mmap failed for search index");
        }
        data_ = static_cast<const uint8_t *>(mapped);
    }

    ~MappedFile() {
        if (data_ != nullptr) munmap(const_cast<uint8_t *>(data_), size_);
        if (fd_ >= 0) close(fd_);
    }

    MappedFile(const MappedFile &) = delete;
    MappedFile &operator=(const MappedFile &) = delete;

    const uint8_t *data() const { return data_; }
    std::size_t size() const { return size_; }

private:
    int fd_ = -1;
    const uint8_t *data_ = nullptr;
    std::size_t size_ = 0;
};

double elapsed_ms(std::chrono::steady_clock::time_point start,
                  std::chrono::steady_clock::time_point end) {
    return std::chrono::duration<double, std::milli>(end - start).count();
}

std::string json_escape(std::string_view value) {
    std::string out;
    out.reserve(value.size() + 8);
    static constexpr char HEX[] = "0123456789abcdef";
    for (unsigned char c : value) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    out += "\\u00";
                    out += HEX[(c >> 4) & 0x0f];
                    out += HEX[c & 0x0f];
                } else {
                    out.push_back(static_cast<char>(c));
                }
        }
    }
    return out;
}

bool send_all(int fd, const std::string &payload) {
    std::size_t sent = 0;
    while (sent < payload.size()) {
        const ssize_t count = send(fd, payload.data() + sent, payload.size() - sent, 0);
        if (count <= 0) return false;
        sent += static_cast<std::size_t>(count);
    }
    return true;
}

std::string handle_query(std::string_view line, const brur::gps::search::IndexView &index) {
    constexpr std::string_view PREFIX = "search ";
    if (!line.starts_with(PREFIX))
        return "{\"success\":false,\"adapter_error\":\"bad_request\"}\n";
    line.remove_prefix(PREFIX.size());
    const std::size_t space = line.find(' ');
    if (space == std::string_view::npos)
        return "{\"success\":false,\"adapter_error\":\"bad_request\"}\n";

    std::size_t limit = 0;
    try {
        limit = static_cast<std::size_t>(std::stoul(std::string(line.substr(0, space))));
    } catch (...) {
        return "{\"success\":false,\"adapter_error\":\"bad_limit\"}\n";
    }
    if (limit == 0 || limit > 32)
        return "{\"success\":false,\"adapter_error\":\"bad_limit\"}\n";

    std::string_view query = line.substr(space + 1);
    while (!query.empty() && query.front() == ' ') query.remove_prefix(1);
    while (!query.empty() && query.back() == ' ') query.remove_suffix(1);
    if (query.empty())
        return "{\"success\":true,\"query_ms\":0,\"count\":0,\"results\":[]}\n";

    const auto started = std::chrono::steady_clock::now();
    const auto results = index.search(query, limit);
    const auto finished = std::chrono::steady_clock::now();

    std::ostringstream out;
    out << std::setprecision(12)
        << "{\"success\":true,\"query_ms\":" << elapsed_ms(started, finished)
        << ",\"count\":" << results.size() << ",\"results\":[";
    for (std::size_t i = 0; i < results.size(); ++i) {
        if (i) out << ',';
        const auto &result = results[i];
        out << "{\"id\":\"" << json_escape(result.record.id)
            << "\",\"kind\":\"" << json_escape(result.record.kind)
            << "\",\"display\":\"" << json_escape(result.record.display)
            << "\",\"subtitle\":\"" << json_escape(result.record.subtitle)
            << "\",\"x\":" << result.record.x
            << ",\"y\":" << result.record.y
            << ",\"score\":[" << result.score.tier
            << ',' << result.score.normalized_length_delta
            << ',' << result.score.display_char_length
            << ",\"" << json_escape(result.score.id) << "\"]}";
    }
    out << "]}\n";
    return out.str();
}

} // namespace

int main(int argc, char **argv) {
    try {
        const std::string index_path = argc > 1 ? argv[1] : "world_data/search_index.bsi";
        const int port = argc > 2 ? std::stoi(argv[2]) : 47742;

        const auto started = std::chrono::steady_clock::now();
        MappedFile mapped(index_path);
        brur::gps::search::IndexView index(mapped.data(), mapped.size());

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

        std::cerr << "[native-gps-search] ready on 127.0.0.1:" << port
                  << " | records " << index.count()
                  << " | mapped " << mapped.size() << " bytes"
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
                pending.append(buffer, static_cast<std::size_t>(count));
                while (true) {
                    const std::size_t newline = pending.find('\n');
                    if (newline == std::string::npos) break;
                    const std::string line = pending.substr(0, newline);
                    pending.erase(0, newline + 1);
                    if (line.empty()) continue;
                    try {
                        if (!send_all(client_fd, handle_query(line, index))) {
                            connected = false;
                            break;
                        }
                    } catch (const std::exception &error) {
                        const std::string response = "{\"success\":false,\"adapter_error\":\"" +
                            json_escape(error.what()) + "\"}\n";
                        if (!send_all(client_fd, response)) {
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
        std::cerr << "native gps search server error: " << error.what() << "\n";
        return 1;
    }
}
