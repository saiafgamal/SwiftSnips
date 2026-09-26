import Foundation

/// Stores at most the longest trigger, never the surrounding document.
public struct TriggerMatcher: Sendable {
    private var snippets: [Snippet] = []
    private var buffer = ""
    private var maximumLength = 0

    public init(snippets: [Snippet] = []) { update(snippets) }

    public mutating func update(_ snippets: [Snippet]) {
        self.snippets = snippets.filter { $0.enabled && !$0.hasShell }.sorted { $0.trigger.count > $1.trigger.count }
        maximumLength = self.snippets.map { $0.trigger.count }.max() ?? 0
        reset()
    }

    public mutating func reset() { buffer.removeAll(keepingCapacity: true) }
    public mutating func backspace() { if !buffer.isEmpty { buffer.removeLast() } }

    public mutating func append(_ text: String) -> Snippet? {
        guard maximumLength > 0, !text.isEmpty else { return nil }
        // Navigation and control characters cannot belong to supported triggers.
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            reset()
            return nil
        }
        buffer += text
        buffer = String(buffer.suffix(maximumLength))
        if let match = snippets.first(where: { buffer.hasSuffix($0.trigger) }) {
            reset()
            return match
        }
        return nil
    }
}
