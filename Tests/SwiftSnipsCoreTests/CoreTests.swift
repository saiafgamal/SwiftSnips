import XCTest
@testable import SwiftSnipsCore

final class CoreTests: XCTestCase {
    func testDuplicateTriggersAndMissingVariablesAreRejected() {
        XCTAssertThrowsError(try LibraryValidation.validate([
            .init(trigger: "/x", replacement: "one"), .init(trigger: "/x", replacement: "two")
        ]))
        XCTAssertThrowsError(try LibraryValidation.validate([.init(trigger: "/x", replacement: "{{missing}}")]))
    }

    func testMatcherHandlesBackspaceResetDisabledAndCase() {
        let match = Snippet(trigger: "/em", replacement: "hello")
        var matcher = TriggerMatcher(snippets: [match, .init(trigger: "/off", replacement: "no", enabled: false)])
        XCTAssertNil(matcher.append("a long unrelated prefix "))
        XCTAssertNil(matcher.append("/eX"))
        matcher.backspace()
        XCTAssertEqual(matcher.append("m")?.id, match.id)
        XCTAssertNil(matcher.append("/off"))
        XCTAssertNil(matcher.append("/EM"))
        XCTAssertNil(matcher.append("/e"))
        matcher.reset()
        XCTAssertNil(matcher.append("m"))
        XCTAssertEqual(matcher.append("/em")?.id, match.id)
    }

    func testMatcherUsesUnicodeCharacters() {
        let snippet = Snippet(trigger: "/تاريخ", replacement: "اليوم")
        var matcher = TriggerMatcher(snippets: [snippet])
        for character in "/تاري" { XCTAssertNil(matcher.append(String(character))) }
        XCTAssertEqual(matcher.append("خ")?.id, snippet.id)
    }

    func testShellContentCannotRunOrMatch() throws {
        let snippet = Snippet(trigger: "/run", replacement: "{{output}}", variables: [
            .init(name: "output", kind: .shell, value: "touch /tmp/should-not-exist")
        ])
        XCTAssertThrowsError(try TemplateRenderer.render(snippet))
        var matcher = TriggerMatcher(snippets: [snippet])
        XCTAssertNil(matcher.append("/run"))
    }

    func testLiteralShellLookingTextStaysLiteral() throws {
        let text = "$(whoami); `id` <script>alert(1)</script> مرحباً"
        XCTAssertEqual(try TemplateRenderer.render(.init(trigger: "/text", replacement: text)), text)
    }

    func testDateUsesEspansoStyleStrftime() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12)))
        XCTAssertEqual(try TemplateRenderer.formatDate(date, format: "%Y-%m-%d"), "2026-09-06")
        XCTAssertEqual(try TemplateRenderer.formatDate(date, format: "%m/%d/%Y"), "09/06/2026")
    }

    func testPrivateSaveAndReadback() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        let snippet = Snippet(trigger: "/text", replacement: "مرحبا 👋\nSecond line")
        try store.save(.init(snippets: [snippet]))
        XCTAssertEqual(try store.load().snippets, [snippet])
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
}
