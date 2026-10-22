// Bounded reader for untrusted files (C++ only; empty when Swift's C importer reads it). pread in pieces, every offset and length checked
// against the size taken at open. No mmap: a file that shrinks while being read (a game updating) fails a read cleanly instead of SIGBUS.
#pragma once
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace cosmo {
class File {
    int fd_ = -1;
    uint64_t size_ = 0;
public:
    explicit File(const char *path) noexcept {
        fd_ = ::open(path, O_RDONLY | O_CLOEXEC);
        struct stat st;
        if (fd_ >= 0 && (::fstat(fd_, &st) != 0 || !S_ISREG(st.st_mode))) { ::close(fd_); fd_ = -1; }
        else if (fd_ >= 0) size_ = uint64_t(st.st_size);
    }
    ~File() { if (fd_ >= 0) ::close(fd_); }
    File(const File &) = delete;
    File &operator=(const File &) = delete;
    bool ok() const noexcept { return fd_ >= 0; }
    uint64_t size() const noexcept { return size_; }
    // true only when all n bytes at off exist and were read
    bool read(uint64_t off, void *dst, size_t n) const noexcept {
        if (fd_ < 0 || off > size_ || n > size_ - off) return false;
        auto *p = static_cast<uint8_t *>(dst);
        while (n) {
            const ssize_t r = ::pread(fd_, p, n, off_t(off));
            if (r <= 0) return false;
            p += r; off += uint64_t(r); n -= size_t(r);
        }
        return true;
    }
    bool u16(uint64_t off, uint32_t &v) const noexcept {
        uint8_t b[2];
        if (!read(off, b, 2)) return false;
        v = uint32_t(b[0]) | uint32_t(b[1]) << 8;
        return true;
    }
    bool u32(uint64_t off, uint32_t &v) const noexcept {
        uint8_t b[4];
        if (!read(off, b, 4)) return false;
        v = uint32_t(b[0]) | uint32_t(b[1]) << 8 | uint32_t(b[2]) << 16 | uint32_t(b[3]) << 24;
        return true;
    }
};
} // namespace cosmo
#endif
