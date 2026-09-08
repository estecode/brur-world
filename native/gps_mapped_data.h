#pragma once

#include "gps_core.h"

#include <cstddef>
#include <cstdint>
#include <fcntl.h>
#include <stdexcept>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

// POSIX file/mmap adapter that supplies immutable routing bytes to gps_core.
//
// Dependencies:
// - gps_core.h data-view contract.
// - POSIX open/fstat/mmap/munmap; no routing decisions or transport behavior.

namespace brur::gps::adapter {

struct MappedFile {
    int fd = -1;
    std::size_t size = 0;
    const std::uint8_t *data = nullptr;

    explicit MappedFile(const std::string &path) {
        fd = open(path.c_str(), O_RDONLY);
        if (fd < 0) throw std::runtime_error("open failed: " + path);
        struct stat st {};
        if (fstat(fd, &st) != 0) {
            close(fd);
            fd = -1;
            throw std::runtime_error("stat failed: " + path);
        }
        size = static_cast<std::size_t>(st.st_size);
        data = static_cast<const std::uint8_t *>(mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0));
        if (data == MAP_FAILED) {
            data = nullptr;
            close(fd);
            fd = -1;
            throw std::runtime_error("mmap failed: " + path);
        }
    }

    ~MappedFile() {
        if (data) munmap(const_cast<std::uint8_t *>(data), size);
        if (fd >= 0) close(fd);
    }

    MappedFile(const MappedFile &) = delete;
    MappedFile &operator=(const MappedFile &) = delete;

    brur::gps::ByteView view() const { return {data, size}; }
};

struct MappedRoutingData {
    MappedFile graph;
    MappedFile snap;

    MappedRoutingData(const std::string &graph_path, const std::string &snap_path)
        : graph(graph_path), snap(snap_path) {}

    brur::gps::RoutingDataView view() const { return {graph.view(), snap.view()}; }
};

inline std::uint64_t warm_mapped_file(const MappedFile &file) {
    if (!file.data || file.size == 0) return 0;
    (void)madvise(const_cast<std::uint8_t *>(file.data), file.size, MADV_WILLNEED);
    const long configured = sysconf(_SC_PAGESIZE);
    const std::size_t page_size = configured > 0 ? static_cast<std::size_t>(configured) : 4096u;
    std::uint64_t checksum = 0;
    for (std::size_t offset = 0; offset < file.size; offset += page_size) checksum += file.data[offset];
    checksum += file.data[file.size - 1];
    return checksum;
}

} // namespace brur::gps::adapter
