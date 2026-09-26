import XCTest
import Darwin
@testable import SwiftSnipsCore

final class SecurityTests: XCTestCase {
    func withFolder(_ body: (URL, LibraryStore) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        _ = try store.load()
        try body(folder, store)
    }

    func testSymlinkLibraryCannotReadOrOverwriteTarget() throws {
        try withFolder { folder, store in
            let victim = folder.appendingPathComponent("unrelated.txt")
            let data = Data("do not change".utf8)
            try data.write(to: victim)
            try FileManager.default.createSymbolicLink(at: store.file, withDestinationURL: victim)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(.init(snippets: [])))
            XCTAssertEqual(try Data(contentsOf: victim), data)
        }
    }

    func testHardLinkedLibraryIsRejected() throws {
        try withFolder { folder, store in
            let victim = folder.appendingPathComponent("other.json")
            try Data("{}".utf8).write(to: victim)
            XCTAssertEqual(link(victim.path, store.file.path), 0)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(.init(snippets: [])))
        }
    }

    func testFIFOIsRejectedWithoutBlocking() throws {
        try withFolder { _, store in
            XCTAssertEqual(mkfifo(store.file.path, 0o600), 0)
            let start = Date()
            XCTAssertThrowsError(try store.load())
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        }
    }

    func testOversizedFileIsRejectedBeforeDecode() throws {
        try withFolder { _, store in
            FileManager.default.createFile(atPath: store.file.path, contents: Data())
            let handle = try FileHandle(forWritingTo: store.file)
            try handle.truncate(atOffset: 8_000_001)
            try handle.close()
            XCTAssertThrowsError(try store.load())
        }
    }

    func testSymlinkDirectoryAndBackupsAreRejected() throws {
        try withFolder { folder, store in
            let redirected = folder.appendingPathComponent("redirected")
            try FileManager.default.createSymbolicLink(at: redirected, withDestinationURL: folder)
            XCTAssertThrowsError(try LibraryStore(folder: redirected).load())
            try store.save(.init(snippets: []))
            let backups = folder.appendingPathComponent("Backups")
            try FileManager.default.createSymbolicLink(at: backups, withDestinationURL: folder)
            XCTAssertThrowsError(try store.save(.init(snippets: [])))
        }
    }

    func testDiagnosticSymlinkCannotOverwriteUnrelatedFile() throws {
        try withFolder { folder, store in
            let victim = folder.appendingPathComponent("unrelated.txt")
            try Data("safe".utf8).write(to: victim)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("health.json"), withDestinationURL: victim)
            XCTAssertThrowsError(try store.saveDiagnostics(Data("{}".utf8)))
            XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "safe")
        }
    }

    func testControlCharacterPayloadsAndTriggersAreRejected() {
        for character in ["\u{0}", "\u{1B}", "\u{7F}"] {
            XCTAssertThrowsError(try LibraryValidation.validate([.init(trigger: "/x", replacement: "text" + character)]))
        }
        XCTAssertThrowsError(try LibraryValidation.validate([.init(trigger: "/x\t", replacement: "text")]))
        XCTAssertNoThrow(try LibraryValidation.validate([.init(trigger: "/x", replacement: "العربية\nSecond\tline")]))
    }

    func testTerminalsBlockAutomaticCommandSubmission() {
        for app in ["com.apple.Terminal", "dev.warp.Warp-Stable", "com.googlecode.iterm2", "com.mitchellh.ghostty"] {
            XCTAssertFalse(ExpansionPolicy.allows("echo harmless\n", in: app))
            XCTAssertFalse(ExpansionPolicy.allows("text\r", in: app))
            XCTAssertFalse(ExpansionPolicy.allows("text\t", in: app))
            XCTAssertTrue(ExpansionPolicy.allows("plain text", in: app))
        }
        XCTAssertTrue(ExpansionPolicy.allows("First\nSecond", in: "com.apple.TextEdit"))
    }

    func testRenderedControlsAreBlockedInEveryApp() throws {
        for control in ["\u{0}", "\u{1B}", "\u{7F}", "\u{85}", "\u{9B}"] {
            XCTAssertFalse(ExpansionPolicy.allows("text" + control, in: "com.apple.TextEdit"))
            XCTAssertFalse(ExpansionPolicy.allows(control, in: nil))
        }
        let snippet = Snippet(trigger: "/date", replacement: "{{date}}", variables: [
            .init(name: "date", kind: .date, value: "%Y\u{1B}")
        ])
        XCTAssertFalse(ExpansionPolicy.allows(try TemplateRenderer.render(snippet), in: "com.apple.TextEdit"))
        XCTAssertTrue(ExpansionPolicy.allows("العربية\u{200D}\nSecond\tline", in: "com.apple.TextEdit"))
        XCTAssertFalse(ExpansionPolicy.allows("text\u{2028}", in: "com.apple.Terminal"))
    }

    func testVariableAndLibraryCountsAreBounded() {
        let variables = (0..<17).map { SnippetVariable(name: "v\($0)", kind: .date, value: "%Y") }
        XCTAssertThrowsError(try LibraryValidation.validate([.init(trigger: "/x", replacement: "text", variables: variables)]))
        XCTAssertThrowsError(try LibraryValidation.validate((0..<5_001).map { .init(trigger: "/\($0)", replacement: "x") }))
        XCTAssertThrowsError(try LibraryValidation.validate([.init(trigger: "/x", replacement: "{{date}}", variables: [
            .init(name: "date", kind: .date, value: String(repeating: "a", count: 8_193))
        ])]))
    }

    func testLegacyShellLibraryRoundTripsButCannotExecute() throws {
        try withFolder { _, store in
            let snippet = Snippet(trigger: "/shell", replacement: "{{out}}", variables: [
                .init(name: "out", kind: .shell, value: "arbitrary command")
            ])
            try store.save(.init(snippets: [snippet]))
            let loaded = try store.load().snippets
            XCTAssertEqual(loaded, [snippet])
            var matcher = TriggerMatcher(snippets: loaded)
            XCTAssertNil(matcher.append("/shell"))
            XCTAssertThrowsError(try TemplateRenderer.render(loaded[0]))
        }
    }
}
