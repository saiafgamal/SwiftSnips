import AppKit
import Combine
import ServiceManagement
import SwiftSnipsCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    @Published var selectedID: UUID?
    @Published var message: String?
    @Published var showDeleteConfirmation = false
    @Published var drafts: [UUID: Snippet] = [:]
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    let keyboard = KeyboardService()
    let store = LibraryStore.standard

    init() {
        do { snippets = try store.load().snippets; selectedID = snippets.first?.id; keyboard.update(snippets) }
        catch { message = error.localizedDescription }
    }

    func save(_ snippet: Snippet) {
        var updated = snippets
        if let index = updated.firstIndex(where: { $0.id == snippet.id }) { updated[index] = snippet }
        else { updated.append(snippet) }
        if persist(updated) { drafts.removeValue(forKey: snippet.id) }
    }

    func add() {
        var suffix = 1
        while snippets.contains(where: { $0.trigger == "/new\(suffix)" }) { suffix += 1 }
        let snippet = Snippet(trigger: "/new\(suffix)", replacement: "Your text here")
        if persist(snippets + [snippet]) { selectedID = snippet.id }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        let updated = snippets.filter { $0.id != selectedID }
        if persist(updated) { drafts.removeValue(forKey: selectedID); self.selectedID = updated.first?.id }
    }

    @discardableResult private func persist(_ updated: [Snippet]) -> Bool {
        do {
            try store.save(SnippetLibrary(snippets: updated))
            snippets = updated
            keyboard.update(updated)
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func turnOn() {
        guard !snippets.isEmpty else { message = "Create a snippet first."; return }
        keyboard.start()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { message = "Approve SwiftSnips in System Settings → Login Items." }
        } catch { message = error.localizedDescription }
    }
}
