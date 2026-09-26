import Foundation

public struct LibraryStore: Sendable {
    public let folder: URL
    public var file: URL { folder.appendingPathComponent("snippets.json") }
    public init(folder: URL) { self.folder = folder }

    public static var standard: LibraryStore {
        LibraryStore(folder: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/org.swiftsnips.app", isDirectory: true))
    }

    public func load() throws -> SnippetLibrary {
        var result = SnippetLibrary()
        try PrivateFiles.directory(folder, create: true) { fd in
            if let data = try PrivateFiles.read("snippets.json", from: fd) { result = try decode(data) }
        }
        return result
    }

    public func save(_ library: SnippetLibrary) throws {
        try LibraryValidation.validate(library.snippets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(library)
        try PrivateFiles.directory(folder, create: true) { fd in
            if let previous = try PrivateFiles.read("snippets.json", from: fd) {
                _ = try decode(previous)
                let backups = folder.appendingPathComponent("Backups", isDirectory: true)
                try PrivateFiles.directory(backups, create: true) { backupFD in
                    try PrivateFiles.write(previous, name: "snippets-\(UUID().uuidString).json", in: backupFD)
                }
            }
            try PrivateFiles.write(data, name: "snippets.json", in: fd)
            guard let saved = try PrivateFiles.read("snippets.json", from: fd),
                  try decode(saved).snippets == library.snippets else {
                throw SnippetError.invalid("Library verification failed.")
            }
        }
    }

    public func saveDiagnostics(_ data: Data) throws {
        try PrivateFiles.directory(folder, create: false) { fd in
            try PrivateFiles.write(data, name: "health.json", in: fd, durable: false)
        }
    }

    private func decode(_ data: Data) throws -> SnippetLibrary {
        let library = try JSONDecoder().decode(SnippetLibrary.self, from: data)
        guard library.schemaVersion == 1 else { throw SnippetError.invalid("Unsupported library version.") }
        try LibraryValidation.validate(library.snippets)
        return library
    }
}
