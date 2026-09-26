# SwiftSnips

SwiftSnips is a native macOS text expander built with SwiftUI and AppKit. It replaces a typed shortcut with text or a formatted date. Matching is case-sensitive and supports Unicode shortcuts, including Arabic.

SwiftSnips runs locally. It has no account, cloud sync, network service, third-party package dependency, or shell-command expansion. The editor, library, and keyboard listener are included in this repository.

## Requirements

- macOS 14 or later to run the app
- Apple silicon, macOS 26.6 or later, and full Xcode 27 to build from source (the Xcode 26.6 compiler crashes while optimizing the current app target)
- Python 3 for the packaging script

## Build and run from source

```sh
git clone https://github.com/saiafgamal/SwiftSnips.git
cd SwiftSnips
swift test -c release
bash scripts/build.sh
open dist/SwiftSnips.app
```

Select Xcode 27 with `xcode-select` or set `DEVELOPER_DIR` if `swift` resolves to Command Line Tools or an older Xcode. `scripts/build.sh` packages a local app and verifies its code signature. It signs ad hoc by default; that is suitable for trying the app locally but can cause macOS to ask for Accessibility access again after rebuilding. To use your own persistent code-signing certificate, run the build with `SWIFTSNIPS_SIGN_IDENTITY` set to that certificate's fingerprint or identity name. No signing key is included in the repository. This source build is not notarized for redistribution as a binary.

After launching, allow the app in macOS **System Settings → Privacy & Security → Accessibility**, then turn on expansion in SwiftSnips. This access lets the app observe shortcuts and post replacement keystrokes across apps. It is a broad macOS permission; review the source before granting it.

The app stores snippets at `~/Library/Application Support/org.swiftsnips.app/snippets.json` and keeps prior versions in a `Backups` folder. Both are plaintext and restricted to the current user account. This separate folder avoids changing data from a personal SwiftSnips installation. Do not store passwords or other secrets as snippets.

## Features and limits

- Text and strftime-style date variables
- Search, enable or disable, and edit snippets in the native window
- Optional launch at login and menu-bar pause/recovery controls
- No shell variables; legacy entries are visible but cannot execute
- Secure Input pauses expansion when a destination app enables it
- Temporary clipboard use for pasting, followed by restoration when the clipboard has not changed

Terminal apps with known bundle IDs block multiline and control-character expansions to reduce accidental command submission. Embedded terminals and unusual destination apps may not be recognized. Text replacement across macOS apps is not atomic, so focus changes can still interrupt a paste. See [SECURITY.md](SECURITY.md) for the trust boundary and [the stress-test report](STRESS_TEST_2026-09-26.md) for large-library results.

## Contributing

Run `swift test -c release` before opening a pull request. Keep issue reports and test fixtures free of personal snippets, credentials, and copied clipboard content. See [CONTRIBUTING.md](CONTRIBUTING.md).

Licensed under [MIT](LICENSE).
