import XCTest
@testable import SwiftSnipsCore

final class StressTests: XCTestCase {
    private func fixture() -> [Snippet] {
        (0..<5_000).map { index in
            let trigger = String(format: "/stress-%04d", index)
            let replacement: String
            switch index {
            case 0:
                replacement = "avery.long+tag/with=unusual?characters@example.technology"
            case 1:
                replacement = "مرحبا بالعالم 👋\nSecond line\tTabbed detail"
            case 2:
                replacement = String(repeating: "Long label with no natural break ", count: 600)
            default:
                replacement = "Fixture \(index): normal text"
            }
            return Snippet(trigger: trigger, replacement: replacement)
        }
    }

    func testMaximumLibraryRoundTripsWithoutTouchingUserData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftSnipsStress-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let snippets = fixture()
        let store = LibraryStore(folder: folder)
        let start = ProcessInfo.processInfo.systemUptime
        try store.save(SnippetLibrary(snippets: snippets))
        let saved = ProcessInfo.processInfo.systemUptime
        let loaded = try store.load().snippets
        let finished = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(loaded, snippets)
        XCTAssertEqual(loaded.count, 5_000)
        print(String(format: "STRESS maximum library: save %.3f s, load %.3f s, file %lld bytes",
                     saved - start, finished - saved, (try store.file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? -1))
    }

    func testMaximumLibraryTypingCostAndEdgeTriggers() throws {
        var snippets = fixture()
        snippets[4_999].trigger = "/" + String(repeating: "Z", count: 127)
        try LibraryValidation.validate(snippets)
        var matcher = TriggerMatcher(snippets: snippets)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<10_000 { XCTAssertNil(matcher.append("x")) }
        let finished = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(matcher.append("/stress-0001")?.replacement, snippets[1].replacement)
        XCTAssertEqual(matcher.append(snippets[4_999].trigger)?.id, snippets[4_999].id)
        print(String(format: "STRESS 10,000 unmatched key events across 5,000 snippets: %.3f s (%.3f ms/key)",
                     finished - start, (finished - start) / 10))
    }

    func testMaximumReplacementAndRejectedOversize() throws {
        let maximum = String(repeating: "x", count: 1_000_000)
        XCTAssertNoThrow(try LibraryValidation.validate([.init(trigger: "/maximum", replacement: maximum)]))
        XCTAssertThrowsError(try LibraryValidation.validate([.init(trigger: "/too-big", replacement: maximum + "x")]))
    }
}
