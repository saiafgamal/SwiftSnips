import Foundation
import Darwin

public enum TemplateRenderer {
    private static let pattern = #"\{\{\s*([\p{L}\p{N}_]+)\s*\}\}"#
    private static let expression = try! NSRegularExpression(pattern: pattern)

    public static func references(in template: String) -> Set<String> {
        let source = template as NSString
        return Set(expression.matches(in: template, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) })
    }

    public static func render(_ snippet: Snippet, date: Date = Date()) throws -> String {
        guard !snippet.hasShell else { throw SnippetError.invalid("Shell execution is disabled. Use text or date variables.") }
        if snippet.variables.isEmpty && !snippet.replacement.contains("{{") { return snippet.replacement }
        var values: [String: String] = [:]
        for variable in snippet.variables {
            switch variable.kind {
            case .date: values[variable.name] = try formatDate(date, format: variable.value)
            case .shell: throw SnippetError.invalid("Shell execution is disabled.")
            }
        }
        let source = snippet.replacement as NSString
        let matches = expression.matches(in: snippet.replacement, range: NSRange(location: 0, length: source.length))
        var result = snippet.replacement
        for match in matches.reversed() {
            let name = source.substring(with: match.range(at: 1))
            guard let value = values[name], let range = Range(match.range, in: result) else {
                throw SnippetError.invalid("Missing variable: \(name)")
            }
            result.replaceSubrange(range, with: value)
        }
        return result
    }

    public static func formatDate(_ date: Date, format: String) throws -> String {
        if format.isEmpty { return "" }
        var timestamp = time_t(date.timeIntervalSince1970)
        var time = tm()
        guard localtime_r(&timestamp, &time) != nil else {
            throw SnippetError.invalid("Could not format the date.")
        }
        var output = [CChar](repeating: 0, count: 8192)
        let count = strftime(&output, output.count, format, &time)
        guard count > 0 else { throw SnippetError.invalid("The date format is invalid or too long.") }
        return String(decoding: output.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
