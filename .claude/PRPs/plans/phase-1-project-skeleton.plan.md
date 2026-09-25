# Plan: Phase 1 — Project Skeleton

## Summary
Bootstrap TrayFold into a buildable, menu-bar-only macOS app that knows whether it has the Accessibility permission, helps the user grant it, and keeps that grant across rebuilds by signing with a stable, self-signed local certificate. After this phase, `Scripts/run.sh` builds and launches `TrayFold.app`: a chevron (or a warning triangle while permission is missing) appears in the menu bar, its menu shows the permission state, and there is no Dock icon. No divider, discovery, or tray popup yet.

## User Story
As a notched-MacBook user building TrayFold for myself,
I want a menu bar app that asks for Accessibility once and keeps it across rebuilds,
so that every later phase can read and press menu bar items without re-granting permission after each build.

## Problem → Solution
Empty repo (README, LICENSE, PRD only) → XcodeGen project with an AppKit status item, permission handling, stable local signing, unit tests, CI, and build docs.

## Metadata
- **Complexity**: Medium
- **Source PRD**: `.claude/PRPs/prds/trayfold.prd.md`
- **PRD Phase**: Phase 1 — Project skeleton
- **Estimated Files**: 15 (10 hand-written, 2 generated, 3 updated)
- **Execution**: implement via a subagent (author's instruction). Task 4 needs the author at the keyboard: macOS shows a password dialog.

---

## UX Design

### Before
```
Menu bar:  [ … other apps … ]  Wi-Fi  Sound  CC  Clock
(no TrayFold)
```

### After
```
First launch, permission missing:
┌──────────────────────────────────────────────────────────┐
│ System dialog: "TrayFold" would like to control this     │
│ computer using accessibility features. [Open Settings]   │
└──────────────────────────────────────────────────────────┘
Menu bar:  [ … ]  ⚠  Wi-Fi  Sound  CC  Clock
                  └─ click ─┐
                  ┌──────────────────────────────┐
                  │ Accessibility: Not allowed   │ (disabled)
                  │ Allow Accessibility Access…  │ → opens Settings pane
                  │ ──────────────────────────── │
                  │ Quit TrayFold            ⌘Q  │
                  └──────────────────────────────┘

After the user flips the switch (no relaunch needed):
Menu bar:  [ … ]  ‹  Wi-Fi  Sound  CC  Clock
                  ┌──────────────────────────────┐
                  │ Accessibility: Allowed       │ (disabled)
                  │ ──────────────────────────── │
                  │ Quit TrayFold            ⌘Q  │
                  └──────────────────────────────┘
```

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Launch | — | Status item appears; no Dock icon; system Accessibility prompt if not yet allowed | `LSUIElement`; prompt shown by macOS at most once |
| Status item icon | — | `exclamationmark.triangle` when not allowed, `chevron.left` when allowed | Updates live when the setting changes |
| Menu | — | Permission line, "Allow Accessibility Access…" (only when missing), Quit | Re-checks permission every time the menu opens |
| Rebuild | — | Permission survives when built with the local certificate | Ad-hoc builds still lose it, by design |

---

## Mandatory Reading

TrayFold has no code yet. Patterns come from the author's sibling app **Slice** (`/Users/reza/Projects/Slice`), which uses the same toolchain on this Mac.

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `/Users/reza/Projects/Slice/project.yml` | all | XcodeGen layout, signing, test target settings to mirror |
| P0 | `/Users/reza/Projects/Slice/Slice/SliceApp.swift` | 1-59 | App entry and doc-comment style |
| P0 | `/Users/reza/Projects/Slice/Slice/Notifications.swift` | 1-26 | `os.Logger` usage, error-handling style, namespace-enum idiom |
| P1 | `/Users/reza/Projects/Slice/SliceTests/AlertStyleTests.swift` | 1-29 | Swift Testing style |
| P1 | `/Users/reza/Projects/Slice/SliceTests/PomodoroTimerTests.swift` | 1-20 | `@MainActor` test struct pattern |
| P1 | `/Users/reza/Projects/Slice/.github/workflows/release.yml` | 1-31 | Runner (`macos-26`), xcodebuild flags for CI |
| P2 | `/Users/reza/Projects/Slice/.gitignore` | all | Already copied into TrayFold |
| P2 | `.claude/PRPs/prds/trayfold.prd.md` | "Technical Approach" | Architecture decisions and risks |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| XcodeGen spec | https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md | Root-level `configFiles` attaches an `.xcconfig` per configuration; `info.properties` writes `Info.plist` |
| Stable dev signing | https://evoleinik.com/posts/macos-dev-signing-preserve-permissions/ | Self-signed cert with `extendedKeyUsage=codeSigning`, imported with `-T /usr/bin/codesign`, then trusted for code signing |
| Same technique (yabai) | https://github.com/koekeishiya/yabai/wiki/Installing-yabai-(from-HEAD) | Self-signed "Code Signing" root is the standard fix for Accessibility grants that vanish on rebuild |
| Accessibility trust API | Apple docs: `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions` | The prompt option shows the system dialog and adds the app to the list, switched off |

```
KEY_INSIGHT: Ad-hoc signatures ("-") give macOS a designated requirement based on the binary's hash, so every rebuild looks like a new app and the Accessibility grant stops applying. A certificate-anchored signature has a stable requirement (identifier + certificate), so the grant survives.
APPLIES_TO: Tasks 2, 4
GOTCHA: `security find-identity -v -p codesigning` lists only TRUSTED identities. Until `add-trusted-cert` runs, the new cert is missing from `-v` output and Xcode cannot sign with it.

KEY_INSIGHT: `/usr/bin/openssl` on this Mac is LibreSSL 3.3.6. It supports `-addext` and writes a PKCS#12 file the keychain accepts WITHOUT `-legacy` (verified 2026-09-25). Homebrew OpenSSL 3 (`/opt/homebrew/bin/openssl`) would need `-legacy`.
APPLIES_TO: Task 4
GOTCHA: Call `/usr/bin/openssl` by full path; `which -a openssl` shows both, and PATH order could change.

KEY_INSIGHT: `kAXTrustedCheckOptionPrompt` is imported as a global `var`; Swift 6 strict concurrency rejects reading it ("not concurrency-safe"). Its value is the string "AXTrustedCheckOptionPrompt"; use the literal.
APPLIES_TO: Task 5

KEY_INSIGHT: macOS has no API callback when Accessibility is toggled, but it posts the distributed notification "com.apple.accessibility.api" whenever the list changes. `AXIsProcessTrusted()` may still return the old value for a moment, so re-check after ~0.5 s.
APPLIES_TO: Task 5

KEY_INSIGHT: XcodeGen 2.46.0 is installed at /opt/homebrew/bin/xcodegen. Slice's test target needed `GENERATE_INFOPLIST_FILE: YES` or `xcodebuild test` fails with "Cannot code sign because the target does not have an Info.plist file".
APPLIES_TO: Task 2

KEY_INSIGHT: `xcodebuild test` prints "Executed 0 tests" (the XCTest counter). The Swift Testing result is the line "✔ Test run with N tests in M suites passed".
APPLIES_TO: Validation
```

---

## Patterns to Mirror

### NAMING_CONVENTION
```swift
// SOURCE: /Users/reza/Projects/Slice/Slice/AlertStyle.swift:3-11
/// How Slice gets your attention when a phase ends.
/// Stored in `UserDefaults` under `alertStyle` as its raw string.
enum AlertStyle: String, CaseIterable {
    /// A normal macOS notification banner with one sound.
    case banner
    ...
    static let defaultsKey = "alertStyle"
```
One type per file, file named after the type, UpperCamelCase types, lowerCamelCase members. Every type and non-trivial member gets a `///` doc comment written for a reader new to Swift/macOS (the author is). Explain the *why* of macOS-specific calls.

### ERROR_HANDLING + LOGGING_PATTERN
```swift
// SOURCE: /Users/reza/Projects/Slice/Slice/Notifications.swift:8-26
enum Notifications {
    /// `os.Logger` writes to the unified system log. Read it with
    /// `log show --predicate 'subsystem == "com.rezaahmadn.Slice"'`.
    private static let logger = Logger(subsystem: "com.rezaahmadn.Slice", category: "Notifications")
    ...
            // `.notice` (not `.info`) so the line is persisted and `log show` can find it.
            logger.notice("Notification permission granted: \(granted, privacy: .public)")
        } catch {
            logger.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
        }
```
TrayFold uses subsystem `com.rezaahmadn.TrayFold`, one `private static let logger` per type, `.notice` for state changes and `.error` for failures, `privacy: .public` on non-sensitive values. No `print`. Failures are logged and the app keeps running; nothing throws to the top level.

### APP_ENTRY
```swift
// SOURCE: /Users/reza/Projects/Slice/Slice/SliceApp.swift:3-6, 37-41
/// The app's entry point. SwiftUI creates exactly one `SliceApp` and asks it for scenes.
/// Slice has no regular window — its only scene is the menu bar item.
@main
struct SliceApp: App {
    ...
    var body: some Scene {
        // `MenuBarExtra` puts an item in the macOS menu bar (macOS 13+).
        MenuBarExtra {
```
TrayFold keeps the SwiftUI `App` entry but **does not use `MenuBarExtra`**: later phases need `NSStatusItem.length` (the divider) and precise popover control, which `MenuBarExtra` doesn't expose. The status item is created in AppKit via `@NSApplicationDelegateAdaptor`.

### TEST_STRUCTURE
```swift
// SOURCE: /Users/reza/Projects/Slice/SliceTests/PomodoroTimerTests.swift:1-10
import Foundation
import Testing
@testable import Slice

/// Drives `PomodoroTimer` with synthetic dates so no test ever waits on real time.
/// `@MainActor` because the model is main-actor isolated.
@MainActor
struct PomodoroTimerTests {
```
```swift
// SOURCE: /Users/reza/Projects/Slice/SliceTests/NotificationsTests.swift:4-10
/// Only the pure text mapping is unit-tested; actual delivery is checked by hand.
struct NotificationsTests {
    @Test func workEndingSaysTakeABreak() {
        let c = Notifications.content(for: .work, next: .breakStarted)
        #expect(c.title == "Work done")
```
Swift Testing (`import Testing`, `@Test`, `#expect`), a doc comment on each suite saying what is and isn't tested, and injected dependencies instead of real system calls.

### PROJECT_CONFIG
```yaml
# SOURCE: /Users/reza/Projects/Slice/project.yml:1-20, 44-54
name: Slice
options:
  bundleIdPrefix: com.rezaahmadn
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    ...
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
...
  SliceTests:
    type: bundle.unit-test
    ...
        # Test bundles need an Info.plist too; let Xcode generate it.
        GENERATE_INFOPLIST_FILE: YES
```
The generated `.xcodeproj` and `Info.plist` are committed so cloners don't need XcodeGen.

---

## Files to Change

All paths relative to `/Users/reza/Projects/TrayFold`.

| File | Action | Justification |
|---|---|---|
| `project.yml` | CREATE | XcodeGen spec (app + tests + scheme) |
| `Config/Signing.xcconfig` | CREATE | Default ad-hoc identity + optional local override |
| `TrayFold/TrayFoldApp.swift` | CREATE | `@main` entry, hooks in the AppKit delegate |
| `TrayFold/AppDelegate.swift` | CREATE | Launch wiring: permission check, status item |
| `TrayFold/AccessibilityPermission.swift` | CREATE | Trust check, prompt, Settings deep link, change observation |
| `TrayFold/StatusBarController.swift` | CREATE | The `NSStatusItem` and its menu |
| `TrayFoldTests/AccessibilityPermissionTests.swift` | CREATE | Unit tests for permission state and labels |
| `TrayFoldTests/StatusBarControllerTests.swift` | CREATE | Unit test for icon choice |
| `Scripts/setup-signing.sh` | CREATE | One-time local certificate setup |
| `Scripts/run.sh` | CREATE | Build + (re)launch for the dev loop |
| `.github/workflows/ci.yml` | CREATE | Build + test on push/PR |
| `TrayFold/Info.plist` | GENERATE | Written by `xcodegen generate`, committed |
| `TrayFold.xcodeproj/` | GENERATE | Written by `xcodegen generate`, committed |
| `.gitignore` | UPDATE | Ignore `Config/Signing.local.xcconfig` |
| `README.md` | UPDATE | Status, build and signing instructions |
| `.claude/PRPs/prds/trayfold.prd.md` | UPDATE | Phase 1 → complete when done |

## NOT Building

- Divider status item or hiding anything (Phase 2).
- Accessibility enumeration of other apps' items (Phase 3).
- Tray popup or chevron click behavior beyond the menu (Phase 4).
- App icon / asset catalog, release workflow, notarization (Phase 7).
- Launch at login, settings window, live icons.
- Any network code or third-party dependency.

---

## Step-by-Step Tasks

### Task 1: Check tools
- **ACTION**: Run `xcodegen --version` and `xcodebuild -version`.
- **IMPLEMENT**: Nothing.
- **MIRROR**: —
- **IMPORTS**: —
- **GOTCHA**: If `xcodegen` is missing: `brew install xcodegen`.
- **VALIDATE**: `Version: 2.46.0` (or newer) and `Xcode 26.x`.

### Task 2: XcodeGen spec + signing config
- **ACTION**: Create `project.yml` and `Config/Signing.xcconfig`; add the local override to `.gitignore`.
- **IMPLEMENT**: `project.yml`:
  ```yaml
  name: TrayFold
  options:
    bundleIdPrefix: com.rezaahmadn
    deploymentTarget:
      macOS: "26.0"
    createIntermediateGroups: true
    generateEmptyDirectories: true

  # Signing identity lives in an .xcconfig so a git-ignored local file can
  # override it (see Scripts/setup-signing.sh).
  configFiles:
    Debug: Config/Signing.xcconfig
    Release: Config/Signing.xcconfig

  settings:
    base:
      SWIFT_VERSION: "6.0"
      MARKETING_VERSION: "0.1.0"
      CURRENT_PROJECT_VERSION: "1"
      CODE_SIGN_STYLE: Manual
      # Ad-hoc ("-") unless Config/Signing.local.xcconfig names a local certificate.
      CODE_SIGN_IDENTITY: "$(TRAYFOLD_SIGN_IDENTITY)"
      DEVELOPMENT_TEAM: ""
      ENABLE_HARDENED_RUNTIME: NO

  targets:
    TrayFold:
      type: application
      platform: macOS
      sources:
        - path: TrayFold
      info:
        path: TrayFold/Info.plist
        properties:
          CFBundleDisplayName: TrayFold
          CFBundleName: TrayFold
          CFBundleShortVersionString: $(MARKETING_VERSION)
          CFBundleVersion: $(CURRENT_PROJECT_VERSION)
          # Menu-bar-only app: no Dock icon, no app menu.
          LSUIElement: true
          NSHumanReadableCopyright: "MIT License"
      settings:
        base:
          PRODUCT_BUNDLE_IDENTIFIER: com.rezaahmadn.TrayFold
          SWIFT_STRICT_CONCURRENCY: complete

    TrayFoldTests:
      type: bundle.unit-test
      platform: macOS
      sources:
        - path: TrayFoldTests
      dependencies:
        - target: TrayFold
      settings:
        base:
          PRODUCT_BUNDLE_IDENTIFIER: com.rezaahmadn.TrayFoldTests
          # Test bundles need an Info.plist too; let Xcode generate it.
          GENERATE_INFOPLIST_FILE: YES

  schemes:
    TrayFold:
      build:
        targets:
          TrayFold: all
          TrayFoldTests: [test]
      run:
        config: Debug
      test:
        config: Debug
        targets:
          - TrayFoldTests
  ```
  `Config/Signing.xcconfig`:
  ```
  // Code-signing identity for TrayFold builds.
  //
  // Default: ad-hoc ("-"). Builds anywhere, but macOS treats every rebuild as a
  // new app and forgets the Accessibility permission.
  //
  // Scripts/setup-signing.sh creates Signing.local.xcconfig (git-ignored) that
  // switches this Mac to a stable self-signed certificate. `#include?` means
  // "include if it exists", so clones and CI keep working without it.
  TRAYFOLD_SIGN_IDENTITY = -
  #include? "Signing.local.xcconfig"
  ```
  Append to `.gitignore`:
  ```
  # Local signing override (Scripts/setup-signing.sh)
  Config/Signing.local.xcconfig
  ```
- **MIRROR**: PROJECT_CONFIG.
- **IMPORTS**: —
- **GOTCHA**: Don't put a literal `CODE_SIGN_IDENTITY` in target settings; target settings beat the xcconfig, and the override would be ignored. Don't hand-write `TrayFold/Info.plist`; XcodeGen generates it. Don't add `CFBundleIconName` (no icon until Phase 7). Create the source folders first (`mkdir -p TrayFold TrayFoldTests`), or XcodeGen errors on missing paths.
- **VALIDATE**: After Tasks 3–6 exist, `xcodegen generate` prints `Created project at .../TrayFold.xcodeproj`.

### Task 3: App entry + delegate
- **ACTION**: Create `TrayFold/TrayFoldApp.swift` and `TrayFold/AppDelegate.swift`.
- **IMPLEMENT**:
  ```swift
  import SwiftUI

  /// The app's entry point. TrayFold has no regular window: everything lives in
  /// the menu bar item that `AppDelegate` creates. SwiftUI's `MenuBarExtra` isn't
  /// used because later phases need direct `NSStatusItem` control (its width is
  /// how the divider hides other icons).
  @main
  struct TrayFoldApp: App {
      /// Lets an AppKit delegate receive the launch callback.
      @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

      var body: some Scene {
          // An `App` must declare at least one scene. An empty Settings scene opens
          // nothing at launch (unlike `WindowGroup`, which would show a blank window).
          Settings { EmptyView() }
      }
  }
  ```
  ```swift
  import AppKit
  import os

  /// Wires TrayFold together once the app has launched.
  @MainActor
  final class AppDelegate: NSObject, NSApplicationDelegate {
      private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "App")

      // Kept alive for the app's lifetime; releasing them would remove the menu bar item.
      private var permission: AccessibilityPermission?
      private var statusBar: StatusBarController?

      func applicationDidFinishLaunching(_ notification: Notification) {
          let permission = AccessibilityPermission()
          permission.startObserving()
          Self.logger.notice("Launched; Accessibility allowed: \(permission.isGranted, privacy: .public)")
          if !permission.isGranted {
              // macOS shows its own dialog (at most once per app) and adds TrayFold,
              // switched off, to the Accessibility list, so the user only flips the switch.
              permission.promptIfNeeded()
          }
          statusBar = StatusBarController(permission: permission)
          self.permission = permission
      }
  }
  ```
- **MIRROR**: APP_ENTRY, LOGGING_PATTERN.
- **IMPORTS**: `SwiftUI`; `AppKit`, `os`.
- **GOTCHA**: No `WindowGroup`. Keep `statusBar` in a stored property; a local variable would be deallocated and the icon would vanish.
- **VALIDATE**: Builds once Tasks 5–6 exist.

### Task 4: Local signing script (needs the author present)
- **ACTION**: Create `Scripts/setup-signing.sh` (executable), then run it once.
- **IMPLEMENT**:
  ```bash
  #!/bin/bash
  # One-time, per Mac: create a self-signed code-signing certificate so macOS keeps
  # TrayFold's Accessibility permission across rebuilds. Safe to re-run.
  # macOS asks for your login password once, to trust the certificate.
  set -euo pipefail

  NAME="TrayFold Local Signing"
  KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  LOCAL="$ROOT/Config/Signing.local.xcconfig"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  if ! security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Creating certificate \"$NAME\"…"
    # /usr/bin/openssl is LibreSSL; its PKCS#12 output imports as-is (no -legacy).
    /usr/bin/openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
      -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=codeSigning" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -in "$TMP/cert.pem" -inkey "$TMP/key.pem" \
      -out "$TMP/identity.p12" -password pass:trayfold
    # -T lets codesign use the private key without a keychain prompt on every build.
    security import "$TMP/identity.p12" -k "$KEYCHAIN" -P trayfold -T /usr/bin/codesign
  fi

  if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "Trusting \"$NAME\" for code signing (macOS will ask for your password)…"
    security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$TMP/trust.pem"
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/trust.pem"
  fi

  printf '// Generated by Scripts/setup-signing.sh. Not committed.\nTRAYFOLD_SIGN_IDENTITY = %s\n' "$NAME" > "$LOCAL"
  echo "Done. Builds on this Mac now sign as:"
  security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME"
  ```
- **MIRROR**: Comment density of `Slice/project.yml` (explain the why of each non-obvious step).
- **IMPORTS**: —
- **GOTCHA**: `add-trusted-cert` opens a macOS password dialog and blocks until answered. **A subagent must not run this unattended.** Hand it back to the main session, which tells the author first. If the author declines, everything else still works with ad-hoc signing; only the "survives rebuild" check fails. The script writes nothing outside the login keychain and `Config/Signing.local.xcconfig`.
- **VALIDATE**: `security find-identity -v -p codesigning | grep "TrayFold Local Signing"` prints one line; `cat Config/Signing.local.xcconfig` shows the identity; `git status` does NOT list that file.

### Task 5: `AccessibilityPermission`
- **ACTION**: Create `TrayFold/AccessibilityPermission.swift`.
- **IMPLEMENT**:
  ```swift
  import AppKit
  import ApplicationServices
  import os

  /// Whether TrayFold may read and press other apps' menu bar items, which is
  /// macOS's Accessibility permission (System Settings → Privacy & Security →
  /// Accessibility). macOS gives no direct callback when the user flips the
  /// switch, so `refresh()` runs at launch, whenever the menu opens, and when
  /// the system broadcasts that the Accessibility list changed.
  @MainActor
  final class AccessibilityPermission {
      private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Accessibility")

      /// Opens System Settings directly on the Accessibility list.
      static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

      /// Last known answer. Changes only through `refresh()`.
      private(set) var isGranted: Bool

      /// Called on every change of `isGranted` (not on every refresh).
      var onChange: ((Bool) -> Void)?

      /// The actual system check, injectable so tests don't depend on this Mac's settings.
      private let isTrusted: () -> Bool
      private var observer: (any NSObjectProtocol)?

      init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
          self.isTrusted = isTrusted
          self.isGranted = isTrusted()
      }

      /// Re-reads the permission and notifies `onChange` if it flipped.
      func refresh() {
          let now = isTrusted()
          guard now != isGranted else { return }
          isGranted = now
          Self.logger.notice("Accessibility allowed changed to \(now, privacy: .public)")
          onChange?(now)
      }

      /// Shows macOS's own permission dialog (the system shows it at most once per app).
      func promptIfNeeded() {
          // String literal instead of `kAXTrustedCheckOptionPrompt`: that constant is a
          // global `var`, which Swift 6 strict concurrency refuses to read.
          let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
          _ = AXIsProcessTrustedWithOptions(options)
      }

      /// Opens the Accessibility pane in System Settings.
      func openSettings() {
          if !NSWorkspace.shared.open(Self.settingsURL) {
              Self.logger.error("Could not open System Settings at \(Self.settingsURL.absoluteString, privacy: .public)")
          }
      }

      /// Listens for the system-wide "Accessibility list changed" broadcast.
      func startObserving() {
          observer = DistributedNotificationCenter.default().addObserver(
              forName: Notification.Name("com.apple.accessibility.api"),
              object: nil,
              queue: .main
          ) { [weak self] _ in
              // The new value can lag the broadcast slightly; check again shortly after.
              Task { @MainActor in
                  try? await Task.sleep(for: .milliseconds(500))
                  self?.refresh()
              }
          }
      }

      /// Text for the (disabled) status line in the menu.
      static func statusTitle(granted: Bool) -> String {
          granted ? "Accessibility: Allowed" : "Accessibility: Not allowed"
      }
  }
  ```
- **MIRROR**: ERROR_HANDLING + LOGGING_PATTERN, NAMING_CONVENTION.
- **IMPORTS**: `AppKit`, `ApplicationServices`, `os`.
- **GOTCHA**: Don't use `kAXTrustedCheckOptionPrompt` (Swift 6 error). Don't poll with a timer ("light on resources"); the broadcast plus the re-check when the menu opens is enough. Don't call `promptIfNeeded()` from the menu; the system ignores repeat prompts, so the menu opens Settings instead.
- **VALIDATE**: Unit tests in Task 7.

### Task 6: `StatusBarController`
- **ACTION**: Create `TrayFold/StatusBarController.swift`.
- **IMPLEMENT**:
  ```swift
  import AppKit

  /// Owns TrayFold's menu bar item. Phase 1: an icon plus a small menu with the
  /// permission state and Quit. Later phases add the divider and the tray popup.
  @MainActor
  final class StatusBarController: NSObject, NSMenuDelegate {
      private let permission: AccessibilityPermission
      private let statusItem: NSStatusItem
      private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
      private let allowItem = NSMenuItem(title: "Allow Accessibility Access…", action: nil, keyEquivalent: "")

      init(permission: AccessibilityPermission) {
          self.permission = permission
          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
          super.init()
          // macOS remembers where the user ⌘-dragged an item with this name.
          statusItem.autosaveName = "TrayFoldChevron"

          let menu = NSMenu()
          menu.delegate = self
          statusLine.isEnabled = false
          allowItem.target = self
          allowItem.action = #selector(openSettings)
          menu.addItem(statusLine)
          menu.addItem(allowItem)
          menu.addItem(.separator())
          // No target: the action travels up to NSApplication, which quits.
          menu.addItem(NSMenuItem(title: "Quit TrayFold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
          statusItem.menu = menu

          permission.onChange = { [weak self] _ in self?.update() }
          update()
      }

      /// SF Symbol shown in the menu bar: a chevron once allowed, a warning until then.
      static func symbolName(granted: Bool) -> String {
          granted ? "chevron.left" : "exclamationmark.triangle"
      }

      private func update() {
          let granted = permission.isGranted
          statusItem.button?.image = NSImage(
              systemSymbolName: Self.symbolName(granted: granted),
              accessibilityDescription: "TrayFold"
          )
          statusLine.title = AccessibilityPermission.statusTitle(granted: granted)
          allowItem.isHidden = granted
      }

      // Called just before the menu shows: the cheapest moment to re-check the permission.
      func menuWillOpen(_ menu: NSMenu) {
          permission.refresh()
          update()
      }

      @objc private func openSettings() {
          permission.openSettings()
      }
  }
  ```
- **MIRROR**: NAMING_CONVENTION, APP_ENTRY comment style.
- **IMPORTS**: `AppKit`.
- **GOTCHA**: Create the `NSStatusItem` inside `init`, not as a property default (it must run on the main actor after launch). SF Symbol images are template images automatically, so they recolor for light/dark menu bars; don't set `isTemplate = false`.
- **VALIDATE**: App launches with the icon; the menu shows the correct line.

### Task 7: Unit tests
- **ACTION**: Create `TrayFoldTests/AccessibilityPermissionTests.swift` and `TrayFoldTests/StatusBarControllerTests.swift`.
- **IMPLEMENT**:
  ```swift
  import Testing
  @testable import TrayFold

  /// Drives `AccessibilityPermission` with a fake trust check, so tests never depend
  /// on this Mac's real Accessibility settings. The system prompt, the Settings link
  /// and the distributed notification are checked by hand.
  @MainActor
  struct AccessibilityPermissionTests {
      /// Mutable stand-in for the system's answer.
      final class FakeTrust { var value = false }

      @Test func startsWithTheSystemAnswer() {
          let trust = FakeTrust(); trust.value = true
          #expect(AccessibilityPermission(isTrusted: { trust.value }).isGranted)
      }

      @Test func refreshPicksUpAGrant() {
          let trust = FakeTrust()
          let permission = AccessibilityPermission(isTrusted: { trust.value })
          #expect(!permission.isGranted)
          trust.value = true
          permission.refresh()
          #expect(permission.isGranted)
      }

      @Test func onChangeFiresOnlyWhenTheAnswerFlips() {
          let trust = FakeTrust()
          let permission = AccessibilityPermission(isTrusted: { trust.value })
          var calls: [Bool] = []
          permission.onChange = { calls.append($0) }
          permission.refresh()            // still false → no call
          trust.value = true
          permission.refresh()            // flips → call
          permission.refresh()            // unchanged → no call
          trust.value = false
          permission.refresh()            // revoked → call
          #expect(calls == [true, false])
      }

      @Test func statusTitles() {
          #expect(AccessibilityPermission.statusTitle(granted: true) == "Accessibility: Allowed")
          #expect(AccessibilityPermission.statusTitle(granted: false) == "Accessibility: Not allowed")
      }
  }
  ```
  ```swift
  import Testing
  @testable import TrayFold

  /// Only the icon choice is unit-tested; the real menu bar item is checked by hand.
  @MainActor
  struct StatusBarControllerTests {
      @Test func iconShowsWarningUntilAllowed() {
          #expect(StatusBarController.symbolName(granted: false) == "exclamationmark.triangle")
          #expect(StatusBarController.symbolName(granted: true) == "chevron.left")
      }
  }
  ```
- **MIRROR**: TEST_STRUCTURE.
- **IMPORTS**: `Testing`, `@testable import TrayFold`.
- **GOTCHA**: Don't construct `StatusBarController` in tests; it would add a real item to the menu bar of the machine running tests.
- **VALIDATE**: `✔ Test run with 5 tests in 2 suites passed`.

### Task 8: Dev loop script
- **ACTION**: Create `Scripts/run.sh` (executable).
- **IMPLEMENT**:
  ```bash
  #!/bin/bash
  # Build TrayFold (Debug) and (re)launch it. Output goes to ./build (git-ignored).
  set -euo pipefail
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  cd "$ROOT"
  xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug \
    -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintentsmetadataprocessor || true
  APP="build/Build/Products/Debug/TrayFold.app"
  [ -d "$APP" ] || { echo "Build failed: $APP missing"; exit 1; }
  pkill -x TrayFold 2>/dev/null && sleep 0.5 || true
  open "$APP"
  echo "Launched $APP (signed as: $(codesign -dv "$APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}' || echo ad-hoc))"
  ```
- **MIRROR**: Slice validation commands (grep filter on xcodebuild output).
- **IMPORTS**: —
- **GOTCHA**: Always launch from the same path (`build/…`); keeps the dev loop predictable. `grep` exits non-zero when nothing matches, hence `|| true` under `set -e`.
- **VALIDATE**: `Scripts/run.sh` prints `** BUILD SUCCEEDED **` and a `Launched …` line.

### Task 9: CI workflow
- **ACTION**: Create `.github/workflows/ci.yml`.
- **IMPLEMENT**:
  ```yaml
  # Builds and tests TrayFold on every push and pull request to main.
  # Ad-hoc signed: CI has no local certificate (Config/Signing.local.xcconfig is git-ignored).
  name: CI

  on:
    push:
      branches: [main]
    pull_request:

  jobs:
    test:
      runs-on: macos-26
      steps:
        - uses: actions/checkout@v7

        - name: Show Xcode
          run: xcodebuild -version

        - name: Build and test
          run: |
            xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug \
              -derivedDataPath build CODE_SIGN_IDENTITY=- test
  ```
- **MIRROR**: `/Users/reza/Projects/Slice/.github/workflows/release.yml:13-31`.
- **IMPORTS**: —
- **GOTCHA**: No release job here (Phase 7).
- **VALIDATE**: After push, `gh run list -R rezaahmadn/TrayFold --limit 1` shows `completed success`.

### Task 10: Generate project, README, PRD status
- **ACTION**: Run `xcodegen generate`; update `README.md`; mark Phase 1 in the PRD.
- **IMPLEMENT**:
  - README: change the status line to "**Status: early development.** Phase 1 (project skeleton) done; nothing is hidden yet." Add a section:
    ```markdown
    ## Build from source

    Requires Xcode 26 on macOS 26.

    ```sh
    git clone https://github.com/rezaahmadn/TrayFold.git
    cd TrayFold
    Scripts/run.sh          # or: open TrayFold.xcodeproj, then Cmd+R
    ```

    On first launch, allow TrayFold in **System Settings → Privacy & Security → Accessibility**.

    ### Keep the permission across rebuilds (optional, recommended for development)

    Default builds are ad-hoc signed, so macOS forgets the Accessibility permission every time you rebuild. Run once:

    ```sh
    Scripts/setup-signing.sh
    ```

    It creates a self-signed "TrayFold Local Signing" certificate in your login keychain (macOS asks for your password to trust it) and a git-ignored `Config/Signing.local.xcconfig` that uses it.
    ```
  - PRD Implementation Phases table, row 1: status `complete`, PRP Plan column `.claude/PRPs/plans/phase-1-project-skeleton.plan.md`.
- **MIRROR**: Slice README "Build from source" section.
- **IMPORTS**: —
- **GOTCHA**: Commit `TrayFold.xcodeproj/` and `TrayFold/Info.plist` (generated but committed on purpose); `xcuserdata/` is already ignored.
- **VALIDATE**: `git status` shows the project and plist as new files, not `Config/Signing.local.xcconfig` or `build/`.

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|
| `startsWithTheSystemAnswer` | fake trust = true | `isGranted == true` | No |
| `refreshPicksUpAGrant` | false → true, refresh | `isGranted == true` | No |
| `onChangeFiresOnlyWhenTheAnswerFlips` | false, true, true, false | callbacks `[true, false]` | Yes: revocation, no-op refresh |
| `statusTitles` | granted true/false | exact strings | No |
| `iconShowsWarningUntilAllowed` | granted true/false | SF Symbol names | No |

### Edge Cases Checklist
- [x] Permission denied: warning icon, "Allow…" item, app keeps running
- [x] Permission revoked while running: covered by `onChange` test + manual check
- [x] Rebuild with ad-hoc signing: permission lost (expected, documented)
- [ ] Empty input / max size / concurrency: N/A this phase
- [x] Network failure: N/A, no network code by design

---

## Validation Commands

Run from `/Users/reza/Projects/TrayFold`.

### Static Analysis (build = type check)
```bash
xcodegen generate
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintentsmetadataprocessor
```
EXPECT: `** BUILD SUCCEEDED **`, zero `error:` and zero `warning:` lines (strict concurrency is `complete`).

### Unit Tests
```bash
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug -derivedDataPath build test 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"
```
EXPECT: `✔ Test run with 5 tests in 2 suites passed` and `** TEST SUCCEEDED **`.

### Signing (after Task 4)
```bash
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -showBuildSettings 2>/dev/null | grep -E '^\s+CODE_SIGN_IDENTITY ='
codesign -dr - build/Build/Products/Debug/TrayFold.app 2>&1 | tail -1
```
EXPECT: `CODE_SIGN_IDENTITY = TrayFold Local Signing`; the designated requirement contains `certificate root = H"…"` and NOT `cdhash`.

### Runtime
```bash
Scripts/run.sh
sleep 2
pgrep -x TrayFold
lsappinfo info -only ApplicationType TrayFold
log show --predicate 'subsystem == "com.rezaahmadn.TrayFold"' --last 2m --style compact | grep Launched
lsof -nP -i -a -c TrayFold || echo "no network sockets"
```
EXPECT: a PID; `"ApplicationType"="UIElement"` (no Dock icon); a `Launched; Accessibility allowed: …` line; `no network sockets`.

### Size
```bash
wc -l TrayFold/*.swift
```
EXPECT: roughly 200 lines total.

### Manual Validation
- [ ] First launch (never allowed): system dialog appears; menu bar shows ⚠; menu says "Accessibility: Not allowed" and offers "Allow Accessibility Access…".
- [ ] "Allow Accessibility Access…" opens System Settings on the Accessibility list, with TrayFold listed.
- [ ] Flip TrayFold on: within ~1 s and without relaunch, the icon becomes ‹ and the menu says "Allowed".
- [ ] Rebuild with `Scripts/run.sh` (local certificate in place): log line says `Accessibility allowed: true` with no re-grant.
- [ ] No Dock icon; Quit (⌘Q from the menu) exits.
- [ ] If an earlier ad-hoc build polluted the list: `tccutil reset Accessibility com.rezaahmadn.TrayFold`, then grant again.

---

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Build: zero errors, zero warnings
- [ ] 5 unit tests pass
- [ ] Permission survives a rebuild with the local certificate
- [ ] No Dock icon, no network sockets
- [ ] CI green on GitHub
- [ ] Matches UX design above

## Completion Checklist
- [ ] Code follows Slice patterns (doc comments, one type per file, `os.Logger`)
- [ ] Errors logged with `.error`, state changes with `.notice`
- [ ] Tests use Swift Testing with injected dependencies
- [ ] No hardcoded values beyond named constants (`settingsURL`, symbol names, cert name)
- [ ] README updated
- [ ] No scope from later phases (no divider, no enumeration, no popup)
- [ ] Generated project + Info.plist committed; local signing file not committed

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `add-trusted-cert` dialog blocks an unattended subagent | H | M | Task 4 runs in the main session with the author present |
| `$(TRAYFOLD_SIGN_IDENTITY)` not resolved (XcodeGen/xcconfig precedence) | L | M | Signing validation command; fallback: pass `CODE_SIGN_IDENTITY="TrayFold Local Signing"` in `Scripts/run.sh` |
| Settings deep link changed in macOS 26 | L | L | Manual check; fallback opens `x-apple.systempreferences:com.apple.preference.security` |
| Distributed notification not posted on toggle | L | L | Menu-open re-check still updates state |
| Stale TCC entry from an earlier ad-hoc build | M | L | `tccutil reset Accessibility com.rezaahmadn.TrayFold` |

## Notes
- The macOS spike scripts (Accessibility enumeration, off-screen `AXPress`) that informed the PRD live outside the repo; their findings are recorded in the PRD's Research Summary.
- `NSStatusItem.autosaveName` is set now so the chevron's position is stable before the divider arrives in Phase 2.
- Subagent guidance: Tasks 1–3 and 5–10 can run unattended; Task 4 needs the author. Phases 2 and 3 can start in parallel worktrees once this phase is merged.
