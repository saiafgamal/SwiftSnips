import AppKit
import SwiftUI
import Combine
import SwiftSnipsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let appMenu = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "About SwiftSnips", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit SwiftSnips", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.submenu = submenu
        menu.addItem(appMenu)
        let editItem = NSMenuItem()
        editItem.title = "Edit"
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "SwiftSnips")
        statusItem?.button?.toolTip = "SwiftSnips — Paused"
        model.keyboard.$state.sink { [weak self] state in self?.refreshMenu(state) }.store(in: &subscriptions)
        if UserDefaults.standard.bool(forKey: "expansionEnabled") { model.turnOn() }
        refreshMenu(model.keyboard.state)
        showWindow()
    }

    @objc func showWindow() {
        if window == nil {
            let root = LibraryView(model: model, keyboard: model.keyboard)
            let controller = NSHostingController(rootView: root)
            let created = NSWindow(contentViewController: controller)
            created.title = "SwiftSnips"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.contentMinSize = NSSize(width: 820, height: 590)
            created.setContentSize(NSSize(width: 980, height: 720))
            created.titlebarAppearsTransparent = false
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }

    func applicationWillTerminate(_ notification: Notification) { model.keyboard.shutdown() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !model.drafts.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "You have unsaved snippet changes."
        alert.informativeText = "Return to the library to save them, or quit and discard these edits."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Discard and quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    private func refreshMenu(_ state: String) {
        statusItem?.button?.toolTip = "SwiftSnips — \(state)"
        let menu = NSMenu()
        menu.autoenablesItems = false
        let status = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let library = NSMenuItem(title: "Open snippet library…", action: #selector(showWindow), keyEquivalent: "")
        library.target = self
        menu.addItem(library)
        let toggle = NSMenuItem(title: model.keyboard.enabled ? "Pause expansion" : "Turn on expansion", action: #selector(toggleExpansion), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let recover = NSMenuItem(title: "Recover keyboard listener", action: #selector(recoverListener), keyEquivalent: "")
        recover.target = self
        recover.isEnabled = model.keyboard.enabled
        menu.addItem(recover)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SwiftSnips", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func toggleExpansion() {
        if model.keyboard.enabled { model.keyboard.stop() }
        else { model.turnOn(); if !model.keyboard.enabled { showWindow() } }
    }
    @objc private func recoverListener() { model.keyboard.recover() }
}

func runCLI() throws -> Bool {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--version"] { print("SwiftSnips 0.1.0"); return true }
    if !args.isEmpty { throw SnippetError.invalid("Only --version is supported. Manage snippets in the app.") }
    return false
}

do {
    if try !runCLI() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
} catch {
    FileHandle.standardError.write(Data("SwiftSnips: \(error.localizedDescription)\n".utf8))
    exit(1)
}
