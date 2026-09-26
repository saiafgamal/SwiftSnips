import Foundation

public enum ExpansionPolicy {
    // Embedded terminals cannot be identified by their host app's bundle ID.
    private static let terminalApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "dev.warp.Warp-Preview", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper"
    ]

    public static func allows(_ text: String, in bundleID: String?) -> Bool {
        // Check rendered output too: date formats can introduce control characters.
        guard !text.unicodeScalars.contains(where: {
            ($0.value < 32 && ![9, 10, 13].contains($0.value)) || (127...159).contains($0.value)
        }) else { return false }
        guard let bundleID, terminalApps.contains(bundleID) else { return true }
        return !text.unicodeScalars.contains {
            $0.value < 32 || $0.value == 0x2028 || $0.value == 0x2029
        }
    }
}
