# Plan: Phase 5 — Reveal & press

## Summary
Clicking an entry in the tray opens that app's real menu, visibly, and folds the bar back once the menu closes. `TrayController.activate(_:)` hands the item to a new `RevealController`, which runs one short "reveal session": shrink the divider by just enough that the item's Accessibility frame lands on-screen (a partial collapse; full collapse only when the item can't get further right), wait (bounded) until the item really is on-screen, press it with `AXPress` off the main actor, watch (bounded, cheap polling) until whatever it opened has closed, then re-expand the divider. Every failure path (item never on-screen, press error, app quit, Accessibility revoked, timeout) ends in the same re-fold. The hide/reveal layer (divider length) and the Accessibility layer (frame, press, "is something open") are injected into the session as closures, so the session is unit-tested without touching the real bar and the divider can be swapped for macOS 27.

## User Story
As a notched-MacBook user,
I want to click an icon in the TrayFold popup and get that app's own menu,
so that every hidden menu bar item is reachable in two clicks.

## Problem → Solution
A tray click only closes the popup and logs → the item's real menu (or Control Center panel, or popover) opens on-screen within ~0.1 s of the click, and the divider re-folds as soon as it closes.

## Metadata
- **Complexity**: High (runtime behaviour of other apps and of macOS's menu bar layout)
- **Source PRD**: `.claude/PRPs/prds/trayfold.prd.md`
- **PRD Phase**: Phase 5 — Reveal & press
- **Estimated Files**: 11 (1 new source, 1 new test file, 5 updated sources, 1 updated test file, README, regenerated project, report)
- **Execution**: one subagent in its own worktree (phases 1–4 merged). Do not edit the PRD; the coordinating agent does.

---

## Spike evidence (author's Mac, macOS 26.7, 14" MacBook Pro, 1512-pt screen, notch 665…850)

Tools: scratch Swift scripts (AX dump, press + observer, CG window list) and a temporary, uncommitted debug hook that set the divider's length from outside. Bar during the spike: WPS, Bitwarden, 1Password folded (x ≈ -4167, -4133, -4101 behind a 5,000-pt divider whose right edge is x = 941); chevron 947; Docker 978; Slice 1023; wattmeter 1099; Wi-Fi 1226; Sound 1264; Control Center 1302; Clock 1344.

### 1. Reveal strategy
| Divider length | What AX reported | Drawn? (screenshot + `CGWindowList` on-screen flag) |
|---|---|---|
| 5000 → 1000 | every folded item moved right by exactly 4000 pt (-4101 → -101) | — |
| 200 / 100 | bar overflowed: macOS **reordered** items (divider jumped right of Docker/Slice), chevron and Docker placed at x 831/862 | chevron, Docker, all folded items **not drawn** |
| 60 / 50 / 40 | 1Password moved **right of the divider** (x 915), WPS/Bitwarden under the notch | 1Password drawn at 915, chevron drawn |
| 30 / 12 | 1Password and Bitwarden swapped places | only items with window x ≳ 870 drawn |
| back to 5000 | original order restored every time | — |

- Shrinking the divider by *d* moves every item left of it right by exactly *d* — until the bar overflows; then macOS reorders and hides items unpredictably (status item windows left of x ≈ 870 are ordered out, even right of the notch's 850 edge). Predicted positions are therefore only a starting point; the session must **read the live AX frame** before pressing.
- **Where the item lands doesn't matter for its menu, as long as its AX frame is on-screen.** 1Password pressed at x 855 (not drawn), x 599 (left of the notch) and x 915 (drawn): its menu opened at x 852 / 596 / 912, fully visible every time. WPS pressed at x 821 (under the notch): its panel opened centred below it at x 654, fully visible. Pressed off-screen (divider expanded): WPS's panel opened at x = -4325, invisible (as in the original spike).
- ⇒ **Partial collapse**: shrink the divider so the item's left edge lands at the notch's right edge (or as far right as a fully collapsed divider allows). Items already on-screen (`.underNotch`, or a user-collapsed divider) are pressed with no reveal at all.

### 2. Pressing
- With the element's messaging timeout at 0.25 s (`AXElement.messagingTimeout`), `AXPress` on an NSMenu item returns `-25204` (`kAXErrorCannotComplete`) after **exactly 0.25 s** while the menu is already open (`AXMenuOpened` 14–30 ms after the press). Without a timeout it blocked **1.5 s** (as in the original spike). The menu is unaffected by the timeout.
- Control Center (Wi-Fi, Sound), Slice (popover), WPS (panel) and Bitwarden return `0` in 30–130 ms.
- The caller's thread stayed free throughout (the scripts sampled AX every 100 ms on the main thread while the press ran on a background queue). ⇒ press in `Task.detached`, treat `.success` and `.cannotComplete` as "pressed".
- Bitwarden's left-click action is to show its main window (its menu is on right-click): that is the item's real behaviour, and TrayFold reproduces it.

### 3. Detecting "closed"
| Item | What it opens | Signals while open | Signal when closed |
|---|---|---|---|
| 1Password, Docker, wattmeter | NSMenu | item `AXSelected` = 1; item's `AXMenu` child has a size (closed: `(0, 982, 0, 0)`); app-level `AXMenuOpened` | `AXSelected` 0 (lags ~0.1 s), menu child size 0; `AXMenuClosed` |
| Control Center (Wi-Fi, Sound) | panel | app `AXWindows` gains an `AXSystemDialog`; `AXWindowCreated` | window gone; `AXUIElementDestroyed` |
| Slice | NSPopover | app `AXWindows` gains an `AXSystemDialog` | window gone |
| WPS | panel | app `AXWindows` gains an `AXDialog` | window gone |
| Bitwarden | its main window (`AXStandardWindow`) | — (not a menu) | — |

- AX notifications can't be registered on the item itself (`-25207`), only on the app. In 1 of 11 1Password runs `AXMenuOpened` never arrived and `AXSelected` stayed 0 although the menu was open (not reproducible afterwards). No single signal is perfect.
- **Re-folding while a menu is open is harmful**: the 1Password menu jumped to the screen's left edge when the divider re-expanded under it. So the session must wait for "closed", and only fall back to a timeout.
- ⇒ One cheap, pure-AX check, polled only while a session is active: "open" = item `AXSelected` **or** item has a sized `AXMenu` child **or** the app has more non-standard windows than before the press. Poll every 0.2 s (≈1–30 ms of AX per poll, off the main actor). If nothing opens within 1.5 s (Bitwarden's window, an app that ignored the press), re-fold. Cap a session at 5 minutes.
- Global outside-click monitor: a reveal session doesn't call `DividerController.collapse()`, so the divider's re-fold monitor is never installed during a reveal; clicks inside another app's menu or panel can't re-fold it.

### 4. Focus
- Menus, panels and popovers of background apps opened while another app (WhatsApp, Warp) was frontmost; Escape reached the open NSMenu. Phase 4 found that clicking a tray entry activates TrayFold. To verify in the real app (Task 6): the menu still opens, and focus returns to the user's app afterwards (fix: `NSApp.hide(nil)` if TrayFold became active, so macOS reactivates the previous app).

---

## UX Design

### Before
```
Click ⌄ → popup [WPS] [Bitwarden] [1Password] → click 1Password → popup closes. Nothing else.
```

### After
```
Click ⌄ → popup → click 1Password
  → popup closes; divider shrinks just enough; 1Password's own menu drops down (~0.1 s)
  → user picks an item / presses Escape / clicks elsewhere → menu closes
  → divider re-expands within ~0.2 s: bar looks exactly as before.
Control Center items: their panel opens; closes as usual; bar re-folds.
Items under the notch: pressed in place (no divider change); their menu drops below the notch.
```

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Tray entry click | Close + log | Reveal → press → re-fold on close | ≤ 2 clicks total |
| Entry for an item already on-screen (under the notch, collapsed divider) | — | Pressed in place | No divider change |
| Another entry clicked while a menu is open | — | Old session re-folds, new one starts | Sessions run one at a time |
| Item never reaches the screen / press fails / app quit / AX revoked | — | Re-fold, log why | Same path for every failure |
| Nothing opens (Bitwarden shows its window) | — | Re-fold after 1.5 s | |
| Quit TrayFold mid-session | — | Divider set back to expanded first | Quitting removes the divider anyway |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `TrayFold/TrayController.swift` | 62-81 | `activate(_:)` (Phase 5 hook), `render()` screen/notch lookup |
| P0 | `TrayFold/DividerController.swift` | 18-27, 58-101 | Lengths, `screenMinX`, `expand()`/`collapse()` and the re-fold monitor a reveal must avoid |
| P0 | `TrayFold/AXElement.swift` | 12-81 | Timeout on every element; `value`/`element`/`children`/`frame` helpers to extend |
| P0 | `TrayFold/MenuBarLayout.swift` | 6-60 | Pure x-axis helpers; reveal math belongs here |
| P1 | `TrayFold/MenuBarItemStore.swift` | 25-45, 122-131 | Injected system closures; `Task.detached` for blocking AX |
| P1 | `TrayFold/AppDelegate.swift` | 15-51 | Wiring order; add `applicationWillTerminate` |
| P1 | `TrayFoldTests/MenuBarItemStoreTests.swift` | 8-43 | Fake system class + fake items |
| P1 | `.claude/PRPs/reports/phase-4-tray-popup-report.md` | Issues, Observations | Entry click activates TrayFold; re-fold monitor; bar height |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| `AXUIElementPerformAction` | `AXUIElement.h` (SDK 26.2) | Synchronous; bounded by the element's messaging timeout; `kAXErrorCannotComplete` when the app doesn't answer in time |
| `AXObserverAddNotification` | `AXUIElement.h` | Menu bar items don't support notifications (`kAXErrorNotificationUnsupported`, measured) |
| `NSApplication.hide(_:)` | AppKit docs | Hides the app and activates the next one: how TrayFold gives focus back |

---

## Patterns to Mirror

### INJECTED_SYSTEM (MenuBarItemStore.swift:25-45)
```swift
// The real system calls, injectable so tests don't depend on this Mac's apps and settings.
private let isTrusted: () -> Bool
private let candidateApps: @MainActor () -> [MenuBarItem.Owner]
/// `@Sendable` because it runs on a background thread.
private let scan: @Sendable ([MenuBarItem.Owner]) -> [MenuBarItem]
```

### BACKGROUND_AX (MenuBarItemStore.swift:124-127)
```swift
/// Runs the blocking scan on a background thread. `Task.detached` matters: a plain
/// `Task` started here would inherit the main actor and freeze the menu bar while it waits.
let found = await Task.detached(priority: .userInitiated) { scan(owners) }.value
```

### PURE_STATIC_HELPER (MenuBarLayout.swift:45-52)
```swift
static func notchRange(leftArea: CGRect?, rightArea: CGRect?) -> ClosedRange<CGFloat>? {
    guard let leftArea, let rightArea, !leftArea.isEmpty, !rightArea.isEmpty,
          leftArea.maxX < rightArea.minX else { return nil }
    return leftArea.maxX...rightArea.minX
}
```

### AX_READ (AXElement.swift:34-38, 69-74)
```swift
func string(_ attribute: String) -> String? {
    guard let text = value(attribute) as? String, !text.isEmpty else { return nil }
    return text
}
private func value(_ attribute: String) -> CFTypeRef? { … AXUIElementCopyAttributeValue … }
```

### LOGGING (TrayController.swift:10, 65)
```swift
private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Tray")
Self.logger.notice("Tray entry clicked: \(item.owner.bundleID ?? item.owner.name, privacy: .public)")
```

### TEST_FAKES (MenuBarItemStoreTests.swift:10-43, TrayControllerTests.swift:9-22)
```swift
final class FakeSystem { var trusted = true; var pids: [pid_t] = [1, 2] }
static func item(_ name: String, x: CGFloat, width: CGFloat = 34, …) -> MenuBarItem
```

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `TrayFold/RevealController.swift` | CREATE | The reveal session state machine; injected divider + AX closures |
| `TrayFold/MenuBarLayout.swift` | UPDATE | Pure `revealLength(...)` and `isOnScreen(...)` |
| `TrayFold/AXElement.swift` | UPDATE | `press()`, `bool(_:)`, `elements(_:)`, `isShowingMenu(...)` |
| `TrayFold/DividerController.swift` | UPDATE | `reveal(length:)` / `endReveal()` that bypass the collapsed look and the re-fold monitor |
| `TrayFold/TrayController.swift` | UPDATE | `activate(_:)` → focus back + `RevealController.open` |
| `TrayFold/AppDelegate.swift` | UPDATE | Create the reveal controller; `applicationWillTerminate` stops it |
| `TrayFoldTests/RevealControllerTests.swift` | CREATE | State machine, error → refold paths, cancellation |
| `TrayFoldTests/MenuBarLayoutTests.swift` | UPDATE | Reveal length and on-screen math |
| `README.md` | UPDATE | Status and usage lines |
| `TrayFold.xcodeproj/project.pbxproj` | REGENERATE | `xcodegen generate` |

## NOT Building
- Live icon images / Screen Recording (Phase 6); release packaging (Phase 7); hotkeys; settings.
- Right-click (secondary action) on entries — e.g. Bitwarden's menu lives there. Could be a later "Could".
- AXObserver-based close detection (measured: works, but one missed notification in 11 runs, and more code than a bounded poll).
- `CGWindowList` checks (they would work without Screen Recording but the PRD keeps discovery Accessibility-only).
- Auto-detecting items hidden by overflow that aren't left of the divider.

---

## Step-by-Step Tasks

### Task 1: Local signing for this worktree
- **ACTION**: `cp /Users/reza/Projects/TrayFold/Config/Signing.local.xcconfig Config/`.
- **GOTCHA**: git-ignored; never commit.
- **VALIDATE**: `git status` doesn't list it.

### Task 2: Pure reveal math in `MenuBarLayout`
- **ACTION**: Add two static functions.
- **IMPLEMENT**:
  ```swift
  /// How long the divider should be so the item at `itemFrame` (measured while the divider
  /// is `currentLength` long) moves right until its left edge reaches `targetMinX`.
  /// Clamped to `minimum...currentLength`: nil when no shrinking is needed.
  static func revealLength(itemFrame: CGRect, currentLength: CGFloat, targetMinX: CGFloat, minimum: CGFloat) -> CGFloat?
  /// Whether all of `frame` is within the screen's x range (its menu then opens visibly).
  static func isOnScreen(_ frame: CGRect, screenFrame: CGRect) -> Bool
  ```
- **MIRROR**: PURE_STATIC_HELPER.
- **GOTCHA**: target = notch's right edge; without a notch, `.infinity` (→ `minimum`, i.e. a full collapse). An already on-screen item needs no reveal regardless of the math.
- **VALIDATE**: tests with the spike's numbers (1Password -4101 → length 49; WPS -4167 → 12; item at 900 → nil).

### Task 3: AX additions in `AXElement`
- **IMPLEMENT**: `bool(_:)`, `elements(_:)` (array attribute such as "AXWindows"), `press() -> AXError`, and
  ```swift
  /// Whether the item's menu, panel or popover is showing (see the spike table).
  static func isShowingMenu(item: AXElement, app: AXElement, windowsBefore: Int) -> Bool
  static func popupWindowCount(of app: AXElement) -> Int   // non-`AXStandardWindow` windows
  ```
- **MIRROR**: AX_READ.
- **GOTCHA**: every element made through `AXElement.init` (0.25 s timeout). `press()` blocks up to 0.25 s: only call it from a background task.
- **VALIDATE**: runtime (Task 7).

### Task 4: `DividerController.reveal(length:)` / `endReveal()`
- **IMPLEMENT**: `reveal(length:)` sets `statusItem.length` only while `isExpanded` (no image, no monitor, `isExpanded` unchanged); `endReveal()` calls `expand()` only if still `isExpanded` (the user may have chosen "Show Hidden Icons" meanwhile).
- **GOTCHA**: don't call `collapse()`: it installs the outside-click re-fold monitor and the collapsed look.
- **VALIDATE**: runtime.

### Task 5: `RevealController`
- **IMPLEMENT**: `@MainActor final class RevealController` with
  - `enum State { case idle, revealing, menuOpen, refolding }`, `private(set) var state`, `onStateChange` (tests, logging);
  - `struct System` of injected closures: `isRevealable: @MainActor () -> Bool`, `setLength: @MainActor (CGFloat) -> Void`, `refold: @MainActor () -> Void`, `frame: @Sendable (AXElement) -> CGRect?`, `press: @Sendable (AXElement) -> AXError`, `openWindows: @Sendable (pid_t) -> Int`, `isShowingMenu: @Sendable (MenuBarItem, Int) -> Bool`, `sleep: @Sendable (Duration) async -> Void`; a `static let live` built from `DividerController` + `AXElement`;
  - `@discardableResult func open(_ item:, screen: CGRect, notch: ClosedRange<CGFloat>?) -> Task<Void, Never>`: cancels and awaits the running session, then runs a new one;
  - `func stop()` (quit): cancels and re-folds synchronously.
  - Session: `revealing` → (on-screen already? skip) set partial length, poll the live frame every 20 ms up to 1 s; if not on-screen, try a full collapse once more → press (detached) → `.success`/`.cannotComplete` ⇒ `menuOpen`, else re-fold → wait ≤ 1.5 s for "open", then poll every 0.2 s while open (≤ 5 min, or until cancelled) → `refolding` → `idle`.
- **MIRROR**: INJECTED_SYSTEM, BACKGROUND_AX, LOGGING.
- **GOTCHA**: loops check `Task.isCancelled`; `sleep` injected so tests don't wait; re-fold exactly once per session, also on cancel.
- **VALIDATE**: `RevealControllerTests`.

### Task 6: Wiring + focus
- **IMPLEMENT**: `TrayController.activate` → `close()`, give focus back if TrayFold became active (`NSApp.hide(nil)`), look up screen + notch, `reveal.open(...)`. `AppDelegate` creates `RevealController(system: .live(divider:))`, passes it to the tray, `applicationWillTerminate` → `stop()`.
- **GOTCHA**: verify focus at runtime: frontmost app before the tray click must be frontmost after the menu closes.
- **VALIDATE**: runtime.

### Task 7: Tests, README, generate, measure, report, PR
- **IMPLEMENT**: tests below; README usage/status; `xcodegen generate`; runtime checks (third-party folded item, Control Center item, under-notch item, app quit mid-session via a scratch helper app, second entry while open); latency from the click timestamp to "pressed"; code-line count.
- **VALIDATE**: commands below.

---

## Testing Strategy

### Unit Tests
| Test | Input | Expected |
|---|---|---|
| reveal length: partial | 1Password x -4101, length 5000, target 850 | 49 |
| reveal length: clamps to collapsed | WPS x -4167 | 12 |
| reveal length: nothing to do | item x 900 | nil |
| on-screen | x -30 / 0 / 1490 w 34 / 1500 w 34 | false / true / true / false |
| happy path | frame on-screen after reveal, press OK, open 2 polls then closed | states revealing → menuOpen → refolding → idle; one refold; length set once |
| already on-screen | under-notch item | no length change, pressed in place; the fold-back call is harmless |
| never on-screen | frame stays off-screen | partial then full collapse tried, no press, refold |
| press error | `.invalidUIElement` | no menuOpen, refold |
| cannotComplete counts as pressed | `-25204` | menuOpen |
| nothing opens | open check always false | refold after grace |
| second open cancels first | open A (menu stays open), open B | A refolds, then B runs; states in order |
| stop() | mid-session | refold once, idle |

### Edge Cases Checklist
- [ ] App quits mid-reveal (frame nil → timeout → refold)
- [ ] App quits while menu open (open check false → refold)
- [ ] Accessibility revoked (all AX reads fail → refold)
- [ ] User collapsed the divider meanwhile (`endReveal` leaves it collapsed)
- [ ] Quit TrayFold mid-session

---

## Validation Commands

### Static Analysis
```bash
xcodegen generate
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintentsmetadataprocessor
```
EXPECT: `** BUILD SUCCEEDED **`, no `warning:`.

### Unit Tests
```bash
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -destination 'platform=macOS' -derivedDataPath build test 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild … CODE_SIGN_IDENTITY=- test   # CI-like
```

### Runtime
```bash
Scripts/run.sh
# CGEvent click on ⌄, then on an entry; screenshot; Escape; AX dump shows items back at x ≈ -4100
/usr/bin/log show --last 2m --info --predicate 'subsystem == "com.rezaahmadn.TrayFold"' --style compact
```

### Size
Code lines (no comments / blank lines) of `TrayFold/*.swift` ≤ ~1,000.

---

## Acceptance Criteria
- [ ] Clicking a folded third-party entry opens its real menu on-screen; bar re-folds after it closes
- [ ] Control Center entry opens its panel; re-folds after it closes
- [ ] Under-notch entry opens without a divider change
- [ ] Every failure path re-folds; no permanent timers; 0 % idle CPU
- [ ] Focus returns to the user's app
- [ ] Zero warnings; all tests pass locally and in CI

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| macOS overflow reorder leaves the item off-screen at the partial length | M | M | Poll the live frame; retry with a full collapse |
| Open check misses a menu (1/11 runs lacked `AXMenuOpened`/`AXSelected`) | L | M | Three signals ORed; if missed, bar re-folds after 1.5 s and the menu jumps (still usable) |
| App keeps a non-standard window open for long | L | L | Baseline count taken before the press; 5-minute cap |
| Entry click makes TrayFold active and steals focus | H (phase 4) | M | `NSApp.hide(nil)` after closing the popup |
| Items that act on left-click instead of opening a menu (Bitwarden) | H | L | That is their real behaviour; right-click action is a later option |

## Notes
- **Amendment: the "is it open?" checks live in `RevealController.System` (`popupWindowCount`, `isShowingMenu`), not in `AXElement`.** `AXElement` only gained generic helpers (`bool`, `elements`, `press`); what counts as "a menu is showing" is reveal-specific.
- **Amendment: no `isRevealable` closure.** `DividerController.reveal(length:)` already does nothing while the divider is collapsed, and `endReveal()` leaves a user-collapsed divider alone.
- **Amendment: the reveal starts from the item's live frame, and waits for the bar to settle after a fold-back.** Runtime bug found in the "another entry while one is open" check: the new session read the old, still-revealed position (macOS needs ~110 ms to move items after the divider re-expands), judged the item on-screen and pressed it while it slid off-screen. Now a session reads the frame live, and one that starts within 250 ms of a fold-back waits out the rest first. Unit test `anotherEntryFoldsTheFirstBackBeforeRevealingAgain` fails without the wait.
- **Amendment: focus is handed back with a plain `NSApp.hide(nil)` before the reveal (no wait loop).** A first version waited until TrayFold had resigned active because Escape didn't close a revealed menu. That turned out to be the test harness: it posted key-down and key-up with no gap, which a menu opened through Accessibility ignores (a 20 ms gap, like a real key press, works; the same zero-gap Escape also failed on a menu pressed from a scratch tool). The handoff takes ~30 ms and the item needs ~110 ms to reach the screen, so the switch is done before the menu opens.
- **Amendment: under-notch items.** The author's bar has no item right of the divider under the notch (the chevron is always the leftmost item right of the divider). The "already on-screen → press in place" path was checked with the divider collapsed by the user (items at x 870–970), and the spike showed WPS pressed at x 821 (under the notch) opens its panel visibly.
