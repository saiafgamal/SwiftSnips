# Security

SwiftSnips uses macOS Accessibility access to observe typed shortcuts and replace them in other apps. That permission is broad. The app runs as the signed-in user; it is not sandboxed, does not have a privileged helper, and does not provide a network or shell execution interface.

Snippet files and backups are plaintext in the current user's Application Support folder. The app uses owner-only permissions, rejects linked or nonregular library files, bounds input sizes, and writes changes atomically. It does not log typed text or snippet contents in its health diagnostics. Expansion text briefly appears on the system clipboard; another app with clipboard access could read it during that interval.

SwiftSnips respects macOS Secure Input, but a destination app must enable Secure Input for sensitive fields. A known terminal app blocks multiline and control-character output. Embedded terminals and other apps can still act on pasted text. Do not use SwiftSnips as a password manager.

The local source build is signed ad hoc by default. It is not a notarized release. If you build with a personal signing certificate, protect that key and verify the resulting app before granting Accessibility access.

Please report suspected vulnerabilities privately through the repository's GitHub security advisory feature. Do not post private snippets, credentials, or a live exploit in a public issue.
