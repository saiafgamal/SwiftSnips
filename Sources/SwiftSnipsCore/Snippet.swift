import Foundation

public struct SnippetVariable: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var kind: Kind
    public var value: String
    public var trim: Bool

    public enum Kind: String, Codable, CaseIterable, Sendable { case date, shell }

    public init(name: String, kind: Kind, value: String, trim: Bool = true) {
        self.name = name
        self.kind = kind
        self.value = value
        self.trim = trim
    }
}

public struct Snippet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var trigger: String
    public var replacement: String
    public var variables: [SnippetVariable]
    public var enabled: Bool
    public var source: String?

    public init(id: UUID = UUID(), trigger: String, replacement: String,
                variables: [SnippetVariable] = [], enabled: Bool = true, source: String? = nil) {
        self.id = id
        self.trigger = trigger
        self.replacement = replacement
        self.variables = variables
        self.enabled = enabled
        self.source = source
    }

    public var hasShell: Bool { variables.contains { $0.kind == .shell } }
}

public struct SnippetLibrary: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var snippets: [Snippet]
    public init(snippets: [Snippet] = []) { self.snippets = snippets }
}

public enum SnippetError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public enum LibraryValidation {
    public static func validate(_ snippets: [Snippet]) throws {
        guard snippets.count <= 5_000 else { throw SnippetError.invalid("A library can contain at most 5,000 snippets.") }
        var totalBytes = 0
        var seen = Set<String>()
        var ids = Set<UUID>()
        for snippet in snippets {
            guard ids.insert(snippet.id).inserted else {
                throw SnippetError.invalid("The library contains a duplicate snippet identifier.")
            }
            guard !snippet.trigger.isEmpty, snippet.trigger.count <= 128,
                  !snippet.trigger.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SnippetError.invalid("A trigger must contain 1–128 characters and no line breaks.")
            }
            guard seen.insert(snippet.trigger).inserted else {
                throw SnippetError.invalid("Duplicate trigger: \(snippet.trigger)")
            }
            guard snippet.replacement.utf8.count <= 1_000_000 else {
                throw SnippetError.invalid("The replacement for \(snippet.trigger) is too large.")
            }
            var variables = Set<String>()
            guard !snippet.replacement.unicodeScalars.contains(where: {
                ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
            }) else { throw SnippetError.invalid("Replacement text contains unsafe control characters.") }
            guard snippet.variables.count <= 16, (snippet.source?.utf8.count ?? 0) <= 1_024 else {
                throw SnippetError.invalid("Too many variables or oversized source metadata.")
            }
            totalBytes += snippet.replacement.utf8.count + snippet.trigger.utf8.count
            for variable in snippet.variables {
                guard !variable.name.isEmpty, variable.name.utf8.count <= 128, variable.value.utf8.count <= 8_192,
                      variable.name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                      variables.insert(variable.name).inserted else {
                    throw SnippetError.invalid("Invalid or duplicate variable in \(snippet.trigger).")
                }
            }
            let references = TemplateRenderer.references(in: snippet.replacement)
            totalBytes += snippet.variables.reduce(0) { $0 + $1.name.utf8.count + $1.value.utf8.count }
            guard totalBytes <= 6_000_000 else { throw SnippetError.invalid("Total snippet content exceeds 6 MB.") }
            for name in references where !variables.contains(name) {
                throw SnippetError.invalid("\(snippet.trigger) references the missing variable {{\(name)}}.")
            }
        }
    }
}
