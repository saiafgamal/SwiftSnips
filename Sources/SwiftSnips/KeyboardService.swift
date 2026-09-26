import AppKit
import Carbon
import Combine
import SwiftSnipsCore

@MainActor
final class KeyboardService: ObservableObject {
    @Published private(set) var state = "Paused"
    @Published private(set) var detail = "Turn on expansion when you’re ready."
    @Published private(set) var enabled = false
    @Published private(set) var expansions = 0
    @Published private(set) var recoveries = 0
    @Published private(set) var lastExpansion: Date?
    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var secureInput = IsSecureEventInputEnabled()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var matcher = TriggerMatcher()
    private var generation: UInt64 = 0
    private var rendering: Task<Void, Never>?
    private var queuedEvents: [CGEvent] = []
    private var injecting = false
    private var injectionToken: UInt64?
    private let clipboard = ClipboardLease()
    private var lastObserved = Date.distantPast
    private var lastRecovery = Date.distantPast
    private var lastDispatchMilliseconds: Double?
    private var lastInputHoldMilliseconds: Double?
    private let eventSource = CGEventSource(stateID: .privateState)
    private var observers: [NSObjectProtocol] = []
    private static let eventMarker: Int64 = 0x5357494654534E50

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHealth() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recover() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancelPending() }
        })
    }

    func update(_ snippets: [Snippet]) { cancelPending(); matcher.update(snippets) }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibility()
    }

    func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func start() {
        permissionGranted = AXIsProcessTrusted()
        guard permissionGranted else { state = "Permission needed"; detail = "Allow SwiftSnips in Accessibility, then turn on expansion."; return }
        enabled = true
        UserDefaults.standard.set(true, forKey: "expansionEnabled")
        installTap()
        checkHealth()
    }

    func stop(persist: Bool = true) {
        enabled = false
        if persist { UserDefaults.standard.set(false, forKey: "expansionEnabled") }
        cancelPending()
        if !injecting { removeTap() }
        state = "Paused"
        detail = "Your keyboard input is not being monitored."
    }

    func shutdown() { stop(persist: false); clipboard.restoreNow() }

    func recover() {
        guard enabled, !injecting else { return }
        cancelPending()
        removeTap()
        permissionGranted = AXIsProcessTrusted()
        secureInput = IsSecureEventInputEnabled()
        guard permissionGranted, !secureInput else { checkHealth(); return }
        recoveries += 1
        lastRecovery = Date()
        installTap()
    }

    private func installTap() {
        guard tap == nil, enabled else { return }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            // This source is installed only on the main run loop.
            let suppress = MainActor.assumeIsolated {
                Unmanaged<KeyboardService>.fromOpaque(context).takeUnretainedValue().receive(type, event) == nil
            }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }, userInfo: context)
        guard let tap else {
            state = "Listener unavailable"
            detail = "Check Accessibility and Input Monitoring permissions, then use Recover listener."
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lastObserved = Date()
        state = "Ready"
        detail = "Expands your shortcuts in other apps."
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func cancelPending() {
        generation &+= 1
        rendering?.cancel()
        matcher.reset()
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if enabled, let tap, !IsSecureEventInputEnabled(), AXIsProcessTrusted() {
                CGEvent.tapEnable(tap: tap, enable: true)
                recoveries += 1
            }
            cancelPending()
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.eventMarker { return Unmanaged.passUnretained(event) }
        if injecting {
            if let copy = event.copy() { queuedEvents.append(copy) }
            return nil
        }
        guard enabled, !IsSecureEventInputEnabled() else { matcher.reset(); return Unmanaged.passUnretained(event) }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            cancelPending()
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty { cancelPending() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        lastObserved = Date()
        generation &+= 1
        rendering?.cancel()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              event.flags.intersection([.maskCommand, .maskControl]).isEmpty else {
            matcher.reset()
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if key == 51 { matcher.backspace(); return Unmanaged.passUnretained(event) }
        if [36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(key) {
            matcher.reset()
            return Unmanaged.passUnretained(event)
        }
        guard let text = NSEvent(cgEvent: event)?.characters, let snippet = matcher.append(text) else {
            return Unmanaged.passUnretained(event)
        }
        let token = generation
        let matchedAt = ProcessInfo.processInfo.systemUptime
        let application = NSWorkspace.shared.frontmostApplication?.processIdentifier
        injecting = true
        injectionToken = token
        rendering = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try TemplateRenderer.render(snippet)
                guard ExpansionPolicy.allows(output, in: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else {
                    self.finishInjection(token: token)
                    self.state = "Expansion blocked"
                    self.detail = "This expansion contains unsafe control characters, or multiline text in a terminal app."
                    return
                }
                guard !Task.isCancelled, self.generation == token, self.enabled,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == application else {
                    self.finishInjection(token: token)
                    return
                }
                self.injecting = true
                self.injectionToken = token
                await self.insert(output, replacing: snippet.trigger, application: application, token: token,
                                  matchedAt: matchedAt)
            } catch {
                self.finishInjection(token: token)
                if !Task.isCancelled {
                    self.state = "Expansion failed"
                    self.detail = error.localizedDescription
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func insert(_ text: String, replacing trigger: String, application: pid_t?, token: UInt64,
                        matchedAt: TimeInterval) async {
        let holdStarted = ProcessInfo.processInfo.systemUptime
        // This Task runs after the event-tap callback returns the final trigger key.
        // Post deletion and paste in order on the same event stream, without sleeps
        // between them. Shell execution is not supported.
        guard enabled, !Task.isCancelled, !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == application else {
            finishInjection(token: token)
            return
        }
        if !text.isEmpty {
            do { try clipboard.write(text) }
            catch {
                finishInjection(token: token)
                state = "Expansion failed"
                detail = error.localizedDescription
                return
            }
        }
        for _ in trigger {
            postKey(51, down: true)
            postKey(51, down: false)
        }
        if !text.isEmpty {
            postKey(9, down: true, flags: .maskCommand)
            postKey(9, down: false, flags: .maskCommand)
        }
        lastDispatchMilliseconds = (ProcessInfo.processInfo.systemUptime - matchedAt) * 1000
        // Keep a brief paste/input ordering margin. Clipboard cleanup has its own
        // delayed lease and must never extend the time we hold subsequent typing.
        if !text.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
        lastInputHoldMilliseconds = (ProcessInfo.processInfo.systemUptime - holdStarted) * 1000
        expansions += 1
        lastExpansion = Date()
        finishInjection(token: token)
        state = "Ready"
        detail = "Expanded \(trigger)."
        if !text.isEmpty { clipboard.restoreAfterPaste() }
    }

    private func postKey(_ key: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: down)
        event?.flags = flags
        event?.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        event?.post(tap: .cgSessionEventTap)
    }

    private func finishInjection(token: UInt64) {
        guard injecting, injectionToken == token else { return }
        injecting = false
        injectionToken = nil
        let queued = queuedEvents
        queuedEvents.removeAll(keepingCapacity: true)
        for event in queued {
            // Replayed user input must still be eligible for subsequent triggers.
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker + 1)
            event.post(tap: .cgSessionEventTap)
        }
        if !enabled { removeTap() }
    }

    private func checkHealth() {
        defer { writeDiagnostics() }
        permissionGranted = AXIsProcessTrusted()
        let wasSecure = secureInput
        secureInput = IsSecureEventInputEnabled()
        guard enabled else {
            if !permissionGranted {
                state = "Permission needed"
                detail = "Allow this installed copy of SwiftSnips in Accessibility."
            } else if state == "Permission needed" {
                state = "Paused"
                detail = "Accessibility is ready. Turn on expansion when you’re ready."
            }
            return
        }
        guard permissionGranted else {
            if !injecting { removeTap() }
            state = "Permission needed"
            detail = "Restore Accessibility access to resume expansion."
            return
        }
        if secureInput {
            cancelPending()
            state = "Secure Input"
            detail = "macOS is protecting a sensitive field. Expansion resumes when it closes."
            return
        }
        if wasSecure { recover(); return }
        if tap == nil { installTap(); return }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { recover(); return }
        // An idle keyboard is healthy. Recover only when recent keyboard activity is
        // visible to macOS but our callback has not observed it for several seconds.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        if !injecting, idle < 2, Date().timeIntervalSince(lastObserved) > 8,
           Date().timeIntervalSince(lastRecovery) > 15,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            recover()
        }
    }

    private func writeDiagnostics() {
        let folder = LibraryStore.standard.folder
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        var status: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "processID": ProcessInfo.processInfo.processIdentifier,
            "bundlePath": Bundle.main.bundleURL.path,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "enabled": enabled, "state": state, "accessibility": permissionGranted,
            "secureInput": secureInput, "listenerAttached": tap != nil,
            "listenerEnabled": tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
            "expansions": expansions, "recoveries": recoveries, "injectionInProgress": injecting
        ]
        status["lastDispatchMilliseconds"] = lastDispatchMilliseconds
        status["lastInputHoldMilliseconds"] = lastInputHoldMilliseconds
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? LibraryStore.standard.saveDiagnostics(data)
        }
    }
}
