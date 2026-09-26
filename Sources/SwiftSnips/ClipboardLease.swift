import AppKit

/// Consecutive expansions share the original clipboard until the last paste settles.
@MainActor
final class ClipboardLease {
    private var original: [[(NSPasteboard.PasteboardType, Data)]]?
    private var ownedChange: Int?
    private var restoration: Task<Void, Never>?

    func write(_ text: String) throws {
        restoration?.cancel()
        let board = NSPasteboard.general
        if original == nil || board.changeCount != ownedChange {
            var total = 0
            var snapshot: [[(NSPasteboard.PasteboardType, Data)]] = []
            for item in board.pasteboardItems ?? [] {
                var entries: [(NSPasteboard.PasteboardType, Data)] = []
                for type in item.types {
                    guard let data = item.data(forType: type) else { continue }
                    total += data.count
                    guard total <= 16_000_000 else {
                        throw NSError(domain: "SwiftSnips", code: 1, userInfo: [NSLocalizedDescriptionKey: "The clipboard is too large to preserve safely. Copy a smaller item and try again."])
                    }
                    entries.append((type, data))
                }
                snapshot.append(entries)
            }
            original = snapshot
        }
        board.clearContents()
        board.setString(text, forType: .string)
        // Advisory only: other apps with clipboard access can still read a lease.
        board.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        ownedChange = board.changeCount
    }

    func restoreAfterPaste() {
        restoration?.cancel()
        restoration = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            self?.restoreNow()
        }
    }

    func restoreNow() {
        let board = NSPasteboard.general
        if board.changeCount == ownedChange, let original {
            board.clearContents()
            board.writeObjects(original.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            })
        }
        original = nil
        ownedChange = nil
    }
}
