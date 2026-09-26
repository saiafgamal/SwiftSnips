import Foundation
import Darwin

/// Owner-only files accessed relative to a checked directory descriptor.
enum PrivateFiles {
    static let maximumBytes = 8_000_000

    static func directory(_ url: URL, create: Bool, body: (Int32) throws -> Void) throws {
        if create {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw error("Cannot open private library directory") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, fchmod(fd, 0o700) == 0 else {
            throw error("Library directory must be owned by your account")
        }
        try body(fd)
    }

    static func read(_ name: String, from directory: Int32) throws -> Data? {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw error("Cannot open private library file") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= maximumBytes,
              fchmod(fd, 0o600) == 0 else {
            throw error("Library files must be private regular files under 8 MB")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw error("Cannot read library file") }
            if count == 0 { return data }
            guard data.count + count <= maximumBytes else { throw error("Library file exceeded 8 MB") }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    static func write(_ data: Data, name: String, in directory: Int32, durable: Bool = true) throws {
        guard data.count <= maximumBytes else { throw error("Library file exceeded 8 MB") }
        var existing = stat()
        if fstatat(directory, name, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            guard existing.st_mode & S_IFMT == S_IFREG, existing.st_uid == getuid(), existing.st_nlink == 1 else {
                throw error("Refusing to replace a linked or nonregular library file")
            }
        } else if errno != ENOENT { throw error("Cannot inspect library destination") }
        let temporary = ".write-\(UUID().uuidString)"
        let fd = openat(directory, temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw error("Cannot create private temporary file") }
        defer { close(fd); unlinkat(directory, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw error("Cannot save library file") }
                offset += count
            }
        }
        guard (!durable || fsync(fd) == 0), renameat(directory, temporary, directory, name) == 0 else {
            throw error("Cannot commit library file")
        }
    }

    private static func error(_ message: String) -> SnippetError { .invalid(message) }
}
