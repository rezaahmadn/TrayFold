# Plan: Phase 3 — Discovery

## Summary
Teach TrayFold to list every menu bar item on the Mac through the Accessibility API, without polling. A small value type (`MenuBarItem`) describes one item (owning app, title, description, identifier, frame, and its Accessibility handle). A scanner asks every running app for its `AXExtrasMenuBar` children off the main actor, with a 0.25 s messaging timeout so a hung app can't stall it. A main-actor store keeps the list current on app launch/quit, on Accessibility permission changes, and whenever `refresh()` is called (Phase 4's popup will call it on open). A pure, unit-tested function classifies an item's frame as visible, hidden by the divider, under the notch, or off-screen. Nothing new is visible in the menu bar; the result shows up in the unified log.

## User Story
As a notched-MacBook user,
I want TrayFold to know which menu bar items exist and where they are,
so that the tray popup (Phase 4) can list exactly the items that are hidden.

## Problem → Solution
TrayFold only knows its own permission state → TrayFold keeps an up-to-date, sorted list of every other app's menu bar items (≈20 ms per rescan, 0% CPU while idle) and can say, for any item, whether it is visible, hidden by the divider, under the notch, or off-screen.

## Metadata
- **Complexity**: Medium
- **Source PRD**: `.claude/PRPs/prds/trayfold.prd.md`
- **PRD Phase**: Phase 3 — Discovery
- **Estimated Files**: 11 (4 new Swift sources, 4 new test files, 1 updated source, 1 regenerated project, report)
- **Execution**: implemented by a subagent in its own worktree, in parallel with Phase 2 (Divider). Do not edit the PRD; the coordinating agent updates it after both phases merge.

---

## UX Design

### Before
```
Menu bar:  [ … ]  TrayFold  Docker  WPS  25:00  🔋77%  Wi-Fi  Sound  CC  Clock
TrayFold knows nothing about the other items.
```

### After
```
Menu bar: unchanged.

Unified log (subsystem com.rezaahmadn.TrayFold):
  [Discovery] Scanned 53 apps in 412 ms: 9 items          (first scan, .info)
  [App]       Menu bar items: 9 (com.electron.dockerdesktop, cn.wps.wpscloudsvr, …)
  … an app launches or quits → one more pair of lines; nothing while idle.
```

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Launch | Permission check only | + one background scan of all apps | Off the main actor; the menu stays responsive |
| App launches / quits | — | That app is rescanned (after 2 s) / its items dropped | Event-driven: key-value observing of `NSWorkspace.runningApplications` (see Amendment) |
| Accessibility granted / revoked | — | List rebuilt / emptied | Same system broadcast `AccessibilityPermission` uses |
| Idle | — | No work at all | No timers, no polling |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `TrayFold/AccessibilityPermission.swift` | 10-39, 56-69 | Injectable system call, `onChange` callback, observer + `Task { @MainActor }` hop: mirror all three in the store |
| P0 | `TrayFold/AppDelegate.swift` | 5-26 | Where the store is created and retained, after the test-host early return |
| P0 | `TrayFoldTests/AccessibilityPermissionTests.swift` | 1-38 | Swift Testing style, fake class for injected state |
| P1 | `TrayFold/StatusBarController.swift` | 35-49 | Pure `static func` + small `enum` so the logic is testable without a menu bar |
| P1 | `project.yml` | 26-62 | Sources are whole folders: new files only need `xcodegen generate` |
| P1 | `.claude/PRPs/prds/trayfold.prd.md` | "Technical Approach", "Research Summary" | Discovery design, risks, spike results |
| P2 | spike `…/scratchpad/spike_ax.swift` | all | Proven enumeration calls (`AXExtrasMenuBar` → `AXChildren` → attributes) |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| AX messaging timeout | `AXUIElement.h` (MacOSX26.2.sdk), `AXUIElementSetMessagingTimeout` | Default is 6 s. Setting it on an element applies "only for that object, not for other accessibility objects that are equal to it"; the system-wide element sets a process-global value |
| Per-element timeout pitfall | [AXorcist PR #64](https://github.com/openclaw/AXorcist/pull/64), [vorssaint-utils #938](https://github.com/vorssaint/vorssaint-utils/issues/938) | Elements copied out of an app element keep the 6 s default unless the timeout is set on them too; a process-global value leaks into unrelated calls (Phase 5's `AXPress`) |
| `NSRunningApplication` | `NSRunningApplication.h` (SDK 26.2) | Marked `NS_SWIFT_SENDABLE`: safe to pass from notification closures |
| Notch geometry | `NSScreen.h`: `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` | Unobscured rects beside the notch; empty (Swift: `nil`) on screens without one |
| `@unchecked Sendable` | [Swift Forums](https://forums.swift.org/t/sendable-warning-with-thread-safe-property-wrapper/65053), [fatbobman](https://fatbobman.com/en/posts/sendable-sending-nonsending/) | Only for types that are thread-safe in a way the compiler can't see; say why in a comment |

```
KEY_INSIGHT: Measured on the author's Mac (macOS 26.7, 105 running apps): the FIRST scan from a
process costs ~830 ms (≈8–13 ms per app to set up the AX connection); later scans cost 19–28 ms.
Background-only (`.prohibited`) apps were 52 of 105 and none had a menu bar; skipping them halves
the first scan.
APPLIES_TO: Tasks 3, 4 — scanning runs off the main actor (Task.detached), candidates skip .prohibited.

KEY_INSIGHT: A stopped (SIGSTOP) app with a status item costs exactly the timeout and returns
kAXErrorCannotComplete (-25204): 255 ms at 0.25 s, 1005 ms at 1.0 s. A responsive app answers in < 1 ms
once connected.
APPLIES_TO: Task 2 — 0.25 s on every element we create.

KEY_INSIGHT: Control Center exposes extra children with a zero-size frame at x = 0 and no title,
description or identifier (5, later 10, on the author's Mac). They are modules macOS isn't drawing.
APPLIES_TO: Task 3 — skip items with zero width.

KEY_INSIGHT: While Phase 2's divider was running (TrayFold item at x = -4075, w = 5002), newly
launched apps' items appeared LEFT of it (x ≈ -4300 … -5016): new items are hidden by default.
APPLIES_TO: Phase 4 (informational); classification must treat far-negative x as hiddenByDivider.

GOTCHA: NSWorkspace launch notifications were never delivered to a command-line tool run from the
agent's shell (even with NSApplication running), so the launch path is verified in the real app.
```

---

## Patterns to Mirror

### INJECTABLE_SYSTEM_CALL + CALLBACK
```swift
// SOURCE: TrayFold/AccessibilityPermission.swift:17-30
    /// Last known answer. Changes only through `refresh()`.
    private(set) var isGranted: Bool

    /// Called on every change of `isGranted` (not on every refresh).
    var onChange: ((Bool) -> Void)?

    /// The actual system check, injectable so tests don't depend on this Mac's settings.
    private let isTrusted: () -> Bool
    private var observer: (any NSObjectProtocol)?

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
```
The store copies this shape: `private(set) var items`, `var onChange`, injected closures with real defaults.

### OBSERVER + MAIN-ACTOR HOP
```swift
// SOURCE: TrayFold/AccessibilityPermission.swift:57-68
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
```

### LOGGING
```swift
// SOURCE: TrayFold/AccessibilityPermission.swift:12, 37
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Accessibility")
        Self.logger.notice("Accessibility allowed changed to \(now, privacy: .public)")
```
New category `Discovery`. `.notice` for list changes, `.info` for per-scan timing (not persisted by default; read with `--info`), `.public` only for counts, timings and bundle ids. Item titles are never logged (a title can be personal, e.g. a timer or a VPN name).

### PURE, TESTABLE DECISION
```swift
// SOURCE: TrayFold/StatusBarController.swift:45-49
    /// TrayFold's own glyph once allowed, a warning triangle until then.
    /// Pure (no AppKit calls), so tests can check it without a menu bar.
    static func icon(granted: Bool) -> Icon {
        granted ? .asset("MenuBarIcon") : .symbol("exclamationmark.triangle")
    }
```
Classification and the notch helper follow this: `static func` on a namespace `enum`, no AppKit state.

### APP WIRING
```swift
// SOURCE: TrayFold/AppDelegate.swift:9-15
    // Kept alive for the app's lifetime; releasing them would remove the menu bar item.
    private var permission: AccessibilityPermission?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; skip the menu bar item and permission prompt there.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
```

### TEST_STRUCTURE
```swift
// SOURCE: TrayFoldTests/AccessibilityPermissionTests.swift:4-15
/// Drives `AccessibilityPermission` with a fake trust check, so tests never depend
/// on this Mac's real Accessibility settings. ...
@MainActor
struct AccessibilityPermissionTests {
    /// Mutable stand-in for the system's answer.
    final class FakeTrust { var value = false }

    @Test func startsWithTheSystemAnswer() {
```

---

## Files to Change

All paths relative to the repository root.

| File | Action | Justification |
|---|---|---|
| `TrayFold/AXElement.swift` | CREATE | `Sendable` wrapper around `AXUIElement` + attribute readers with the timeout applied |
| `TrayFold/MenuBarItem.swift` | CREATE | The model (`MenuBarItem`, nested `Owner`) |
| `TrayFold/MenuBarItemScanner.swift` | CREATE | Which apps to ask; the blocking AX scan |
| `TrayFold/MenuBarItemStore.swift` | CREATE | Event-driven, serialized, off-main refreshes; `onChange` |
| `TrayFold/MenuBarLayout.swift` | CREATE | Pure `Visibility` classification + notch-range helper |
| `TrayFold/AppDelegate.swift` | UPDATE | Create, retain, log and start the store (minimal: Phase 2 edits this file too) |
| `TrayFoldTests/MenuBarLayoutTests.swift` | CREATE | Classification and notch-range cases |
| `TrayFoldTests/MenuBarItemStoreTests.swift` | CREATE | Store behaviour with fake trust / apps / scan |
| `TrayFoldTests/MenuBarItemScannerTests.swift` | CREATE | Real AX scan; skipped without the permission (CI) |
| `TrayFold.xcodeproj/` | GENERATE | `xcodegen generate` picks up the new files |
| `.claude/PRPs/reports/phase-3-discovery-report.md` | CREATE | Implementation report |

## NOT Building

- The divider status item, or reading its frame (Phase 2). The classifier takes the divider's left edge as a plain `CGFloat?`.
- Any popup or UI (Phase 4). No change to `StatusBarController`.
- `AXPress`, revealing items, detecting menu close (Phase 5).
- Screen capture / live icons (Phase 6).
- Watching item moves (⌘-drag) with `AXObserver`: Phase 4 refreshes on popup open, which is enough and costs nothing while idle.
- Editing the PRD (the coordinating agent does it after merge).

---

## Step-by-Step Tasks

### Task 1: Local signing for this worktree
- **ACTION**: `cp /Users/reza/Projects/TrayFold/Config/Signing.local.xcconfig Config/`.
- **IMPLEMENT**: Nothing else.
- **MIRROR**: —
- **GOTCHA**: The file is git-ignored (`.gitignore:26`); never commit it. Without it the test host is ad-hoc signed, has no Accessibility grant, and the real-AX test is skipped instead of run.
- **VALIDATE**: `git check-ignore -v Config/Signing.local.xcconfig` prints the ignore rule; `xcodebuild … -showBuildSettings | grep CODE_SIGN_IDENTITY` shows `TrayFold Local Signing`.

### Task 2: `AXElement`
- **ACTION**: Create `TrayFold/AXElement.swift`.
- **IMPLEMENT**:
  ```swift
  import ApplicationServices

  /// A handle to one piece of another app's user interface (the app itself, its part
  /// of the menu bar, one menu bar item), as seen through the Accessibility API.
  ///
  /// Why `@unchecked Sendable`: Swift can't tell whether `AXUIElement`, a Core Foundation
  /// type, is safe to share between threads, so it refuses to send it from the background
  /// scan to the main actor. It is safe: the element is an immutable token (process id plus
  /// element id), reading an attribute only sends a message to the other app, and Core
  /// Foundation's reference counting is thread-safe. The one setting it carries, the
  /// messaging timeout, is set in `init` before the element is shared.
  struct AXElement: @unchecked Sendable, Equatable {
      /// Longest wait for another app to answer one question. macOS's default is 6 s,
      /// so a single hung app would stall a scan that long. Measured on the author's Mac:
      /// a stopped app costs exactly this timeout; a responsive one answers in under 1 ms.
      static let messagingTimeout: Float = 0.25

      let raw: AXUIElement

      /// Wraps `raw` and applies `messagingTimeout` to it. macOS applies a timeout only to
      /// the exact element it was set on, not to elements read from it, so every element
      /// TrayFold uses is created through here.
      init(_ raw: AXUIElement) {
          self.raw = raw
          AXUIElementSetMessagingTimeout(raw, Self.messagingTimeout)
      }

      /// The top-level element of the app with process id `pid`.
      static func application(pid: pid_t) -> AXElement {
          AXElement(AXUIElementCreateApplication(pid))
      }

      /// A text attribute such as "AXTitle", or nil when it's missing or empty.
      func string(_ attribute: String) -> String? { … }

      /// An attribute that points at another element, such as "AXExtrasMenuBar".
      func element(_ attribute: String) -> AXElement? { … CFGetTypeID check … }

      /// The element's children, in the order the app reports them.
      var children: [AXElement] { … }

      /// Position and size in screen points. x grows to the right from the left edge of
      /// the main display (the same x axis AppKit uses); y grows downward.
      var frame: CGRect? { … AXValueGetValue(.cgPoint / .cgSize) … }

      /// Two handles are equal when they point at the same UI element, even if they came
      /// from different scans.
      static func == (lhs: AXElement, rhs: AXElement) -> Bool { CFEqual(lhs.raw, rhs.raw) }
  }
  ```
- **MIRROR**: NAMING_CONVENTION (doc comment on every member, explain the macOS why).
- **IMPORTS**: `ApplicationServices`.
- **GOTCHA**: Use string literals ("AXPosition", "AXChildren") rather than `kAX…` constants; some are imported as global `var`s that Swift 6 rejects. Check `CFGetTypeID` before `as!` casting a `CFTypeRef` to `AXUIElement` / `AXValue` (a conditional `as?` on CF types always "succeeds").
- **VALIDATE**: Builds with zero warnings.

### Task 3: `MenuBarItem` + `MenuBarItemScanner`
- **ACTION**: Create `TrayFold/MenuBarItem.swift` and `TrayFold/MenuBarItemScanner.swift`.
- **IMPLEMENT**:
  ```swift
  struct MenuBarItem: Identifiable, Equatable, Sendable {
      struct Owner: Equatable, Sendable { let pid: pid_t; let bundleID: String?; let name: String }
      let id: String                        // "<pid>/<AXIdentifier or #index>"
      let owner: Owner
      let title: String?                    // AXTitle, e.g. "25:00"
      let accessibilityDescription: String? // AXDescription, e.g. "Wi‑Fi, connected, 3 bars"
      let identifier: String?               // AXIdentifier, e.g. "com.apple.menuextra.clock"
      let frame: CGRect
      let element: AXElement
  }
  ```
  ```swift
  enum MenuBarItemScanner {
      /// Should `app` be asked for menu bar items? Not TrayFold itself, not background-only apps.
      static func isCandidate(_ app: NSRunningApplication) -> Bool
      static func owner(of app: NSRunningApplication) -> MenuBarItem.Owner
      @MainActor static func candidateApps() -> [MenuBarItem.Owner]
      /// Blocks while other apps answer: call it off the main actor.
      static func scan(_ owners: [MenuBarItem.Owner]) -> [MenuBarItem]   // owners.flatMap(items(of:))
      static func items(of owner: MenuBarItem.Owner) -> [MenuBarItem]    // AXExtrasMenuBar → children, skip width 0
  }
  ```
- **MIRROR**: NAMING_CONVENTION; namespace-`enum` idiom.
- **IMPORTS**: `CoreGraphics` (model), `AppKit` (scanner).
- **GOTCHA**: The property is `accessibilityDescription`, not `description`: a `description` property reads like `CustomStringConvertible` and confuses `print`. Don't read `NSWorkspace.shared.runningApplications` off the main actor; collect `Owner` values (Sendable) on the main actor and pass them to `scan`. Skip zero-width children (see KEY_INSIGHT).
- **VALIDATE**: Task 7's scanner test.

### Task 4: `MenuBarItemStore`
- **ACTION**: Create `TrayFold/MenuBarItemStore.swift`.
- **IMPLEMENT**: `@MainActor final class MenuBarItemStore` with
  - `private(set) var items: [MenuBarItem]` (sorted by `frame.minX`), `var onChange: (([MenuBarItem]) -> Void)?` fired only when `items` really changes.
  - `init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }, candidateApps: @escaping @MainActor () -> [Owner] = MenuBarItemScanner.candidateApps, scan: @escaping @Sendable ([Owner]) -> [MenuBarItem] = MenuBarItemScanner.scan)`.
  - `start()`: observe `NSWorkspace.didLaunchApplicationNotification` (candidate apps only; wait `launchSettleTime` = 2 s, then `rescan(owner)`), `didTerminateApplicationNotification` (`forget(pid:)`), and the distributed `"com.apple.accessibility.api"` broadcast (wait 0.5 s, then `refresh()`); then run a first `refresh()`.
  - `refresh() async`: untrusted → `apply([])`; else scan `candidateApps()` in `Task.detached` and apply.
  - `rescan(_ owner:) async`: scan just that app; replace its items.
  - `forget(pid:) async`: drop that app's items (no AX needed).
  - `enqueue(_:)`: each update awaits the previous one, so a slow full scan can't land after (and overwrite) a newer per-app update.
  - `static func summary(_ items:) -> String`: `"9 (com.a, com.b, …)"` for the log.
  - Logs `.info` "Scanned N apps in X ms: M items" per scan.
- **MIRROR**: INJECTABLE_SYSTEM_CALL + CALLBACK, OBSERVER + MAIN-ACTOR HOP, LOGGING.
- **IMPORTS**: `AppKit`, `ApplicationServices`, `os`.
- **GOTCHA**: `AccessibilityPermission.onChange` is a single callback already owned by `StatusBarController`; don't overwrite it. Listen to the same broadcast instead. Keep observer tokens in a stored array or they're removed. `Task.detached` (not `Task {}`): a plain `Task` created on the main actor runs the blocking scan on the main actor. Everything captured by the detached closure must be `Sendable` (`owners`, the `scan` closure).
- **VALIDATE**: Task 7's store tests.

### Task 5: `MenuBarLayout`
- **ACTION**: Create `TrayFold/MenuBarLayout.swift`.
- **IMPLEMENT**:
  ```swift
  enum MenuBarLayout {
      enum Visibility: Equatable, Sendable { case visible, hiddenByDivider, underNotch, offScreen }

      /// Rules, first match wins:
      /// 1. centre left of `dividerMinX` → .hiddenByDivider (the tray, whether or not the divider is expanded)
      /// 2. centre left of `screenMinX` → .offScreen
      /// 3. any overlap with `notchRange` → .underNotch (macOS doesn't draw an item cut by the notch)
      /// 4. otherwise → .visible
      static func visibility(of frame: CGRect, dividerMinX: CGFloat?,
                             notchRange: ClosedRange<CGFloat>?, screenMinX: CGFloat) -> Visibility

      /// The gap between the two unobscured areas beside the notch, e.g. 665...850; nil without a notch.
      static func notchRange(leftArea: CGRect?, rightArea: CGRect?) -> ClosedRange<CGFloat>?
      @MainActor static func notchRange(of screen: NSScreen) -> ClosedRange<CGFloat>?
  }
  ```
- **MIRROR**: PURE, TESTABLE DECISION.
- **IMPORTS**: `AppKit`.
- **GOTCHA**: Only x matters. AppKit (origin bottom-left) and Accessibility (origin top-left) share the x axis, so no y flip is needed. An item touching the notch edge (`minX == 850`) is visible: use strict `<` / `>` for the overlap.
- **VALIDATE**: Task 7's layout tests.

### Task 6: Wire into `AppDelegate`
- **ACTION**: Update `TrayFold/AppDelegate.swift`.
- **IMPLEMENT**: One stored property `private var menuBarItems: MenuBarItemStore?`; after `statusBar = …`:
  ```swift
  let menuBarItems = MenuBarItemStore()
  menuBarItems.onChange = { items in
      Self.logger.notice("Menu bar items: \(MenuBarItemStore.summary(items), privacy: .public)")
  }
  menuBarItems.start()
  self.menuBarItems = menuBarItems
  ```
- **MIRROR**: APP WIRING.
- **GOTCHA**: After the test-host early return, so tests don't scan in the background. Keep the diff small and local; Phase 2 adds a line in the same function.
- **VALIDATE**: Build; runtime log check.

### Task 7: Tests
- **ACTION**: Create the three test files.
- **IMPLEMENT**: See Testing Strategy. The real-AX test uses `.enabled(if: AXIsProcessTrusted(), "…")`.
- **MIRROR**: TEST_STRUCTURE.
- **GOTCHA**: Fake scan closures must be `@Sendable`, so they can't mutate captured state. Make them pure: each fake item's title says how many apps were in the same scan ("batch of 2"), which proves a launch rescan asked only one app.
- **VALIDATE**: `✔ Test run with N tests in 5 suites passed` locally (real-AX test runs); CI shows it skipped.

### Task 8: Generate, measure, report, PR
- **ACTION**: `xcodegen generate`; full test run; one brief runtime check; write the report; move this plan to `completed/`; branch `feat/phase-3-discovery`; commit; push; `gh pr create`.
- **GOTCHA**: The Phase 2 agent owns `Scripts/run.sh` (it `pkill`s TrayFold). If a brief launch is needed, launch this worktree's build directly and quit only that pid.
- **VALIDATE**: CI green on the PR.

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|
| layout: visible right of the notch | x 967 w 47, divider 930, notch 665…850 | `.visible` | No |
| layout: left of the divider | x -4300, divider -4075 | `.hiddenByDivider` | Yes: far negative x |
| layout: left of a collapsed divider, still on-screen | x 900, divider 930 | `.hiddenByDivider` | Yes |
| layout: no divider, off the left edge | x -300, divider nil | `.offScreen` | Yes |
| layout: overlaps the notch | x 830 w 40 | `.underNotch` | Yes: partial overlap |
| layout: touches the notch edge | x 850 | `.visible` | Yes |
| layout: no notch | notch nil | `.visible` | Yes |
| notch range from areas | 0…665, 850…1512 | `665...850` | No |
| notch range missing / empty / overlapping areas | nil, `.zero`, left ≥ right | `nil` | Yes |
| store: refresh lists every app, sorted by x | apps [2, 1] | pids [1, 2] | No |
| store: no permission | trust false | `[]`, no `onChange` | Yes |
| store: recovers once allowed | false → true | items appear | Yes |
| store: revoked | true → false | `[]` | Yes |
| store: `onChange` only on change | refresh ×2 | 1 call | Yes |
| store: launch rescans only that app | rescan(3) | 1, 2 "batch of 2"; 3 "batch of 1" | No |
| store: quit drops that app | forget(1) | only pid 2 | No |
| store: summary text | 2 items | "2 (a, b)" | No |
| scanner (real AX, needs permission) | this Mac | Control Center items present, no zero-width, none from TrayFold | Skipped in CI |

### Edge Cases Checklist
- [x] Permission missing / granted later / revoked
- [x] Hung app (timeout, measured with SIGSTOP)
- [x] Items with zero size (skipped)
- [x] Overlapping scans (serialized)
- [x] App without a menu bar (`AXExtrasMenuBar` missing → no items)
- [ ] Multiple displays: x axis shared, notch taken from the screen passed in; checked by hand later

---

## Validation Commands

Run from the worktree root.

### Static Analysis (build = type check)
```bash
xcodegen generate
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintentsmetadataprocessor
```
EXPECT: `** BUILD SUCCEEDED **`, zero `error:` / `warning:` lines.

### Unit Tests
```bash
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug -derivedDataPath build test 2>&1 | grep -E "error:|Test run with|skipped|TEST (SUCCEEDED|FAILED)"
```
EXPECT: all tests pass; with the local certificate, the real-AX test runs (not skipped).

### Runtime
```bash
/usr/bin/log show --last 2m --info --predicate 'subsystem == "com.rezaahmadn.TrayFold" AND category IN {"Discovery", "App"}' --style compact
```
EXPECT: a `Scanned … apps in … ms` line and a `Menu bar items: N (…)` line after launch; one more pair after an app launches or quits; nothing while idle.

### Size
```bash
wc -l TrayFold/*.swift
```
EXPECT: roughly +250 lines.

### Manual Validation
- [ ] Launch, then open/quit an app with a menu bar item: the log gains a line each time.
- [ ] Activity Monitor: TrayFold at 0% CPU while idle.

---

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Build: zero errors, zero warnings (Swift 6, strict concurrency complete)
- [ ] All unit tests pass locally; real-AX test skipped (not failed) in CI
- [ ] No timers or polling; scans off the main actor
- [ ] Measured full-scan time and item count recorded in the report
- [ ] CI green

## Completion Checklist
- [ ] Doc comments on every type and member, explaining the macOS why
- [ ] `.notice` for changes, `.info` for timings, `.public` only for non-sensitive fields
- [ ] Tests use Swift Testing and injected fakes
- [ ] No Phase 2/4/5 scope; PRD untouched
- [ ] Generated project committed; `Config/Signing.local.xcconfig` not committed

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Launched app adds its item after the 2 s rescan | M | L | Phase 4 refreshes on popup open; list is also rebuilt on any later launch/quit of that app |
| Several hung apps slow a refresh (0.25 s each) | L | M | Off the main actor; Phase 4 can show the cached list first and update on `onChange` |
| An app turns from background-only into a menu bar app after launch | L | L | `refresh()` rechecks all candidates every time |
| `AXUIElement` thread-safety assumption wrong | L | M | Only immutable reads cross threads; documented in `AXElement` |
| Merge conflict with Phase 2 in `AppDelegate` | M | L | Additions only, grouped after `statusBar = …` |

## Notes
- Scan-time numbers come from a scratch script (`swiftc -O`), and are re-measured in the app for the report.
- Divider position is not read here; Phase 4 passes the divider's window `frame.minX` into `MenuBarLayout.visibility`.
- **Amendment (during implementation): launches and quits are observed with key-value observing on `NSWorkspace.shared.runningApplications`, not `didLaunchApplicationNotification` / `didTerminateApplicationNotification`.** The runtime check showed no rescan when a menu-bar-only test app launched: Apple documents that those notifications are not posted for `LSUIElement` or background apps, which covers most menu bar apps. KVO on `runningApplications` reports every app (verified: the `LSUIElement` helper was rescanned 2 s after launch and dropped on quit). The observation closure is `@Sendable` and hops to the main actor like the other observers.
- **Amendment: `isCandidate` also skips apps with TrayFold's own bundle id**, not just its own pid. The runtime check ran while the Phase 2 agent's development build was running, and its chevron and divider showed up as items.
