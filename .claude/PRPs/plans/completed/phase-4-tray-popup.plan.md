# Plan: Phase 4 — Tray popup

## Summary
Turn the chevron into the tray. A left-click opens an `NSPopover` anchored to the chevron with a small SwiftUI grid of every menu bar item that is folded away: everything `MenuBarLayout.visibility(...)` does not classify as `.visible` (left of the divider, under the notch, off-screen), in left-to-right bar order. Each entry shows the owning app's icon and a short label (the item's own text, else the first part of its Accessibility description, else the app name), with a longer tooltip. The grid starts at one cell and grows up to 5 columns, adding rows as needed; with nothing folded away it shows a two-line hint. A right-click or ⌃-click opens the existing menu (and so does a left-click while Accessibility isn't allowed). Clicking an entry goes through one method, `TrayController.activate(_:)`, which only closes the popup and logs for now (Phase 5 adds reveal + `AXPress`). Finally, a cheap safety net: while the divider is collapsed, a global mouse monitor re-folds it on the first click outside the menu bar, so a crowded bar can never leave the user without a chevron.

## User Story
As a notched-MacBook user,
I want to click one chevron and see every menu bar icon that is folded away or stuck under the notch,
so that I can tell what is running without making room in the bar.

## Problem → Solution
The chevron only opens a settings menu; hidden items are invisible → left-click shows a grid of exactly the hidden items within ~100 ms, right-click keeps the menu, and a collapsed divider folds itself back once the user clicks elsewhere.

## Metadata
- **Complexity**: Medium
- **Source PRD**: `.claude/PRPs/prds/trayfold.prd.md`
- **PRD Phase**: Phase 4 — Tray popup
- **Estimated Files**: 11 (2 new sources, 1 new test file, 3 updated sources, 2 updated tests, README, regenerated project, report)
- **Execution**: one subagent in its own worktree (phases 1–3 merged). Do not edit the PRD; the coordinating agent does.

---

## UX Design

### Before
```
Menu bar:  [ … ]  (TrayFold ⌄)  Docker  Slice 25:00  ⚡33W  Wi-Fi  Sound  CC  Clock
                   └ any click → menu: Accessibility line · Show Hidden Icons · Quit
Folded away (off-screen): WPS, Bitwarden, 1Password — no way to see them without collapsing.
```

### After
```
Left-click ⌄ (Accessibility allowed):
                   ⌄
          ┌─────────────────────────┐
          │  [W]     [B]     [1]    │   app icons, left-to-right as in the bar
          │  WPS…  Bitwarden 1Pass… │   short label; tooltip "Bitwarden"
          └─────────────────────────┘
  6+ items → 5 columns, a second row appears.  Clicking an entry closes the popup (Phase 5 opens its menu).

Nothing folded away:
          ┌──────────────────────────────┐
          │     Nothing folded away      │
          │ Right-click ⌄ → Show Hidden  │
          │ Icons, then ⌘-drag icons     │
          │ left of the divider.         │
          └──────────────────────────────┘

Right-click / ⌃-click ⌄ (or any click while Accessibility isn't allowed): the existing menu.

"Show Hidden Icons" → divider collapses → user ⌘-drags → clicks anywhere below the menu bar
→ divider re-folds automatically (log: "Divider expanded (icons hidden)").
```

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Left-click ⌄ | Menu | Tray popup (toggle) | Menu instead while Accessibility isn't allowed |
| Right-click / ⌃-click ⌄ | Menu | Menu | Menu attached only for that click |
| Popup open | — | Cached items at once, `refresh()` in the background, grid updates in place | ~20 ms warm rescan (phase 3) |
| App launches/quits while open | — | Grid updates | Via the store's `onChange` |
| Click entry | — | Popup closes, log line | Phase 5: reveal + press |
| Click outside popup | — | Popup closes | `.transient` |
| Divider collapsed, click below the menu bar | Stays collapsed until "Hide Icons" / reopen | Re-folds | Global mouse monitor, installed only while collapsed |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `TrayFold/StatusBarController.swift` | 19-46, 73-85 | The chevron item and menu; `statusItem.menu` must go (it swallows left-clicks) |
| P0 | `TrayFold/MenuBarLayout.swift` | 20-43, 54-59 | The visibility rules the tray filters on; notch range of a screen |
| P0 | `TrayFold/MenuBarItemStore.swift` | 19-23, 79-85 | `items` (sorted by x), single `onChange`, `refresh()` returns when up to date |
| P0 | `TrayFold/DividerController.swift` | 52-94 | `screenMinX`, `expand()` / `collapse()`: where the re-fold monitor is installed/removed |
| P0 | `TrayFold/AppDelegate.swift` | 15-38 | Creation order (divider first) and the store's logging `onChange` |
| P1 | `TrayFold/MenuBarItem.swift` | 17-32 | `title`, `accessibilityDescription`, `owner.name` for labels |
| P1 | `TrayFoldTests/MenuBarItemStoreTests.swift` | 16-35 | How to build fake `MenuBarItem`s |
| P1 | `.claude/PRPs/reports/phase-2-divider-report.md` | "Issues Encountered" | Crowded bar hides the chevron when collapsed |
| P1 | `.claude/PRPs/reports/phase-3-discovery-report.md` | "Next Steps" | Pass the divider window's `frame.minX`; show cache, then refresh |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| Left vs right click on a status item | [onmyway133 #707](https://github.com/onmyway133/blog/issues/707), [Ivan Sapozhnik](https://isapozhnik.com/articles/status-item/) | `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`, branch on `NSApp.currentEvent?.type`. Setting `statusItem.menu` permanently makes every click open the menu. `popUpMenu(_:)` is deprecated; attach the menu for one `performClick(nil)` and detach it again |
| Tahoe right-click bug | [Apple forums 811718](https://developer.apple.com/forums/thread/811718) | On macOS 26 a right-click at the very top screen edge doesn't reach the status item's action (left-click does). Nothing to fix on our side; ⌃-click is the fallback |
| Popover sizing | [`NSHostingController.sizingOptions`](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions), [TomatoBar PR #3](https://github.com/cartfisk/TomatoBar/pull/3) | `.preferredContentSize` keeps `preferredContentSize` equal to the SwiftUI ideal size; `NSPopover` follows it, so the popup grows with the grid |
| Popover in an `LSUIElement` app | AppKit docs `NSPopover.Behavior.transient`, common practice | A menu-bar-only app is not active; call `NSApp.activate()` before `show(relativeTo:of:preferredEdge:)` so the popover becomes key and `.transient` closes it on outside clicks |
| Global mouse monitor permission | [Apple: Monitoring Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html), [`addGlobalMonitorForEvents`](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)) | Only **key** events need Accessibility; mouse events need nothing extra (and TrayFold has Accessibility anyway). Handler runs on the main thread; sees other apps' events only |

```
KEY_INSIGHT (measured, author's Mac, divider expanded):
  hidden:  WPS Office Service x=-4174, Bitwarden x=-4140, 1Password x=-4108 (divider window x=-4068)
  visible: Docker x=971, Slice x=1016 title "25:00", WattMeter x=1092 title "⚡33.1W · 26.9W",
           Control Center: Wi-Fi desc "Wi‑Fi, connected, 3 bars", Sound "Sound", CC "Control Center", Clock "Clock"
  Third-party icon items have title "" (AXElement.string → nil) and no description.
  Screen 1512×982, visibleFrame maxY 949 → menu bar 33 pt tall; NSStatusBar.system.thickness says 22.
APPLIES_TO: labels (title → first comma part of description → app name), re-fold (menu bar height from
the screen's visibleFrame, thickness only as a floor).

GOTCHA: `.transient` closes the popover on mouse-down outside it, including on the chevron itself, so a
naive "toggle" can close-then-reopen. Verify at runtime; if it happens, ignore a toggle within ~0.3 s of
the popover closing.
```

---

## Patterns to Mirror

### PURE_STATIC_HELPER
```swift
// SOURCE: TrayFold/StatusBarController.swift:48-58
    /// SF Symbol shown in the menu bar: a downward chevron (the tray opens below it)
    /// once allowed, a warning triangle until then.
    /// Pure (no AppKit calls), so tests can check it without a menu bar.
    static func symbolName(granted: Bool) -> String {
        granted ? "chevron.down" : "exclamationmark.triangle"
    }
```
Click routing, tray filtering, labels, grid rows and the re-fold test are all `static func`s like this.

### STATUS_ITEM_TARGET_ACTION
```swift
// SOURCE: TrayFold/DividerController.swift:47-48, 101-105
        statusItem.button?.target = self
        statusItem.button?.action = #selector(dividerClicked)
    …
    @objc private func dividerClicked() {
        expand()
    }
```

### LOGGING
```swift
// SOURCE: TrayFold/DividerController.swift:13, 81
    private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Divider")
        Self.logger.notice("Divider expanded (icons hidden)")
```
New category `Tray`. Bundle ids only, never item titles (they can be personal).

### APP_WIRING
```swift
// SOURCE: TrayFold/AppDelegate.swift:26-38
        let divider = DividerController(chevronAutosaveName: StatusBarController.autosaveName)
        statusBar = StatusBarController(permission: permission, divider: divider)
        …
        let menuBarItems = MenuBarItemStore()
        menuBarItems.onChange = { items in
            Self.logger.notice("Menu bar items: \(MenuBarItemStore.summary(items), privacy: .public)")
        }
```

### TEST_STRUCTURE / FAKE ITEMS
```swift
// SOURCE: TrayFoldTests/MenuBarItemStoreTests.swift:22-35
    nonisolated static func fakeScan(_ owners: [MenuBarItem.Owner]) -> [MenuBarItem] {
        owners.map { owner in
            MenuBarItem(
                id: "\(owner.pid)/#0",
                owner: owner,
                title: "batch of \(owners.count)",
                …
                element: AXElement.application(pid: owner.pid)
```

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `TrayFold/TrayController.swift` | CREATE | Popover, open/refresh/update, `activate(_:)`, pure helpers (folded items, label, tooltip, grid rows) |
| `TrayFold/TrayView.swift` | CREATE | SwiftUI grid + empty state |
| `TrayFold/StatusBarController.swift` | UPDATE | Left/right/⌃ click routing; menu attached only on demand |
| `TrayFold/DividerController.swift` | UPDATE | Re-fold monitor while collapsed + pure "outside the menu bar" test |
| `TrayFold/AppDelegate.swift` | UPDATE | Create the tray; `onChange` logs and updates the tray |
| `TrayFoldTests/TrayControllerTests.swift` | CREATE | Filtering, ordering, labels, tooltip, grid rows |
| `TrayFoldTests/StatusBarControllerTests.swift` | UPDATE | Click routing |
| `TrayFoldTests/DividerControllerTests.swift` | UPDATE | Re-fold decision |
| `README.md` | UPDATE | Status + usage (left-click tray, right-click menu, auto re-fold) |
| `TrayFold.xcodeproj/` | GENERATE | `xcodegen generate` |
| `.claude/PRPs/reports/phase-4-tray-popup-report.md` | CREATE | Report |

## NOT Building

- `AXPress`, revealing the item, re-hiding after its menu closes (Phase 5). `activate(_:)` only closes and logs.
- Live icon images / Screen Recording (Phase 6); SF Symbol per Control Center item (Control Center entries share its app icon and are told apart by label).
- Settings window, hotkeys, search, drag-to-reorder in the popup.
- An observer framework on `MenuBarItemStore` (it keeps its single `onChange`; `AppDelegate` fans it out to the log and the tray).
- Multi-display handling beyond "use the primary screen".
- Editing the PRD.

---

## Step-by-Step Tasks

### Task 1: Local signing for this worktree
- **ACTION**: `cp /Users/reza/Projects/TrayFold/Config/Signing.local.xcconfig Config/`.
- **GOTCHA**: git-ignored; never commit.
- **VALIDATE**: `git check-ignore -v Config/Signing.local.xcconfig`.

### Task 2: `TrayController` pure helpers
- **ACTION**: Create `TrayFold/TrayController.swift` with `// MARK: - Pure helpers`.
- **IMPLEMENT**:
  ```swift
  static let maxColumns = 5
  /// Items the tray lists: every item not `.visible`, left to right.
  static func foldedItems(_ items: [MenuBarItem], dividerMinX: CGFloat?, notchRange: ClosedRange<CGFloat>?, screenMinX: CGFloat) -> [MenuBarItem]
  /// "25:00" (title) → "Wi‑Fi" (description up to the first comma) → "Docker Desktop" (app name).
  static func label(for item: MenuBarItem) -> String
  /// "Control Center: Wi‑Fi, connected, 3 bars", "Slice: 25:00", or just the app name.
  static func tooltip(for item: MenuBarItem) -> String
  /// Splits entries into grid rows of at most `maxColumns`: 3 → [3], 6 → [5, 1], 12 → [5, 5, 2].
  static func rows<Element>(_ elements: [Element], columns: Int = maxColumns) -> [[Element]]
  ```
- **MIRROR**: PURE_STATIC_HELPER.
- **GOTCHA**: Sort by `frame.minX` inside `foldedItems` too (cheap; doesn't rely on the store's order). Titles can be whitespace; trim before deciding.
- **VALIDATE**: Task 7 tests.

### Task 3: `TrayView`
- **ACTION**: Create `TrayFold/TrayView.swift`.
- **IMPLEMENT**: `struct TrayView: View { let items: [MenuBarItem]; let onSelect: (MenuBarItem) -> Void }`. Non-empty: `Grid` of `GridRow`s from `TrayController.rows(items)`; each cell is a plain `Button` with a 32-pt `NSRunningApplication(processIdentifier:)?.icon`, a one-line caption label (64 pt wide, truncating) and `.help(tooltip)`; a hover highlight via a small `TrayCell` subview with `@State isHovered`. Empty: "Nothing folded away" + one caption line, fixed width, wrapping. `.padding(12)`.
- **GOTCHA**: Wrapping `Text` inside a size-to-fit popover needs `.fixedSize(horizontal: false, vertical: true)` and a fixed width, or it lays out on one very long line. `Image(nsImage:)` needs `.resizable()` before `.frame`.
- **VALIDATE**: Build; screenshot at runtime.

### Task 4: `TrayController` runtime
- **ACTION**: Same file.
- **IMPLEMENT**:
  - `init(store:divider:)`: `NSHostingController(rootView: TrayView(items: [], onSelect: { _ in }))`, `sizingOptions = .preferredContentSize`; `popover.contentViewController = hosting`, `.behavior = .transient`, `.animates = false` (snappier, matches a menu).
  - `toggle(relativeTo button: NSView)`: if shown → `close()`; else `render()`, `NSApp.activate()`, `popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)`, log latency since the click (`NSApp.currentEvent.timestamp` vs `ProcessInfo.systemUptime`) at `.info`, then `Task { await store.refresh(); render() }`.
  - `close()`, `itemsChanged()` (render only while shown), `activate(_ item:)` (close, `.notice` log with bundle id, `// Phase 5:` note).
  - `render()`: screen = `NSScreen.screens.first` (Accessibility x is measured on the primary display), `foldedItems(store.items, dividerMinX: divider.screenMinX, notchRange: MenuBarLayout.notchRange(of: screen), screenMinX: screen.frame.minX)`, assign `hosting.rootView`.
- **GOTCHA**: `NSApp.activate()` (macOS 14+) instead of the deprecated `activate(ignoringOtherApps:)`. `divider.screenMinX` is nil for a fraction of a second after launch; `visibility` treats nil as "no divider".
- **VALIDATE**: Runtime: popup lists exactly WPS, Bitwarden, 1Password.

### Task 5: Chevron click routing
- **ACTION**: Update `StatusBarController`.
- **IMPLEMENT**:
  ```swift
  enum ClickAction: Equatable { case tray, menu }
  static func clickAction(for type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags, granted: Bool) -> ClickAction
  ```
  Keep the menu in a property instead of `statusItem.menu`; `button.target/action = chevronClicked`, `sendAction(on: [.leftMouseUp, .rightMouseUp])`. `.menu` → `tray.close()`, `statusItem.menu = menu`, `button.performClick(nil)`, `statusItem.menu = nil` (in `menuDidClose`). Refresh the permission before deciding.
- **MIRROR**: STATUS_ITEM_TARGET_ACTION, PURE_STATIC_HELPER.
- **GOTCHA**: `performClick` with an attached menu shows the menu instead of sending the action (no recursion). Clear the menu afterwards or every later click opens it.
- **VALIDATE**: Runtime: left → popup, right → menu, ⌃-left → menu.

### Task 6: Crowded-bar re-fold
- **ACTION**: Update `DividerController`.
- **IMPLEMENT**: `private var clickMonitor: Any?`. `collapse()` installs `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp])` once; the handler re-folds when the click is below the menu bar of the screen it hit. `expand()` removes it. Pure: `static func isBelowMenuBar(_ point: CGPoint, screenFrame: CGRect, menuBarHeight: CGFloat) -> Bool`. Height = `max(frame.maxY - visibleFrame.maxY, NSStatusBar.system.thickness)`.
- **GOTCHA**: Global monitors see only other apps' events, so clicks in TrayFold's own menu/popup never re-fold. Mouse-*up*, so a ⌘-drag that ends in the bar is ignored and another app's menu selection completes before the bar shifts. A click on no screen (the very top edge) is ignored. No new permission: mouse monitors don't need one.
- **VALIDATE**: Runtime: collapse → click on the desktop → log "Divider expanded"; ⌘-drag in the bar doesn't re-fold.

### Task 7: Wiring + tests
- **ACTION**: Update `AppDelegate`, add/extend tests.
- **IMPLEMENT**: Create store and tray before the status bar; `onChange` logs, then `tray?.itemsChanged()`.
- **VALIDATE**: all tests pass.

### Task 8: README, generate, measure, report, PR
- **ACTION**: README status/usage; `xcodegen generate`; tests; runtime checks (latency, contents, empty state, right-click, re-fold); idle CPU/memory; report; move plan; branch, commit, push, PR; watch CI.

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|
| folded: hidden by divider, under notch, off-screen listed; visible excluded | 5 items | 3 items | No |
| folded: ordering left to right | unsorted input | sorted by x | Yes |
| folded: nothing hidden | all visible | `[]` | Yes |
| folded: no divider yet (nil) | items right of notch | `[]`; under-notch still listed | Yes |
| label: title wins | title "25:00", desc "Timer" | "25:00" | No |
| label: description up to comma | "Wi‑Fi, connected, 3 bars" | "Wi‑Fi" | No |
| label: whitespace title ignored | title " " | description / name | Yes |
| label: app name fallback | nil / nil | "Docker Desktop" | No |
| tooltip | CC Wi-Fi / plain app | "Control Center: Wi‑Fi, …" / "Docker Desktop" | No |
| rows | 0, 1, 5, 6, 12 | [], [1], [5], [5,1], [5,5,2] | Yes |
| click routing | left / right / ⌃-left / left without permission | tray / menu / menu / menu | Yes |
| re-fold | point inside bar, just below, far below, custom height | false / true / true | Yes |

### Edge Cases Checklist
- [x] Nothing folded away (empty state)
- [x] Accessibility not allowed (menu instead of an empty popup)
- [x] More than 5 items (second row)
- [x] App quits while popup open (store `onChange` → re-render)
- [x] Divider not placed yet (nil)
- [ ] Multiple displays (primary screen assumed; not tested)

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
# CGEvent left click on the chevron; screencapture -x -R<x>,0,<w>,<h>; log show:
/usr/bin/log show --last 2m --info --predicate 'subsystem == "com.rezaahmadn.TrayFold"' --style compact
```
EXPECT: `Tray opened in N ms` with N ≲ 100, popup shows the folded items only; right-click shows the menu.

### Size
```bash
wc -l TrayFold/*.swift
```
EXPECT: app target ≤ ~1,000 lines.

---

## Acceptance Criteria
- [ ] Left-click opens the popup with exactly the not-visible items, in bar order, within ~100 ms
- [ ] Right-click / ⌃-click (and any click without Accessibility) opens the menu
- [ ] Empty state shown when nothing is folded away
- [ ] Popup refreshes on open and updates in place; log line for store changes kept
- [ ] Entry click routes through `TrayController.activate(_:)` (closes + logs)
- [ ] Collapsed divider re-folds on the first click below the menu bar; reopen recovery kept
- [ ] Zero warnings; all tests pass locally and in CI; idle CPU ~0%

## Completion Checklist
- [ ] Doc comments explain the macOS why, in the existing style
- [ ] No polling or timers; monitor exists only while collapsed
- [ ] PRD untouched; `Signing.local.xcconfig` not committed

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Transient popover closes on mouse-down on the chevron, toggle re-opens it | M | L | Verify; ignore re-open within 0.3 s of close if needed |
| Attaching the menu for one `performClick` misbehaves on macOS 26 | L | M | Fallback: `menu.popUp(positioning:at:in:)` under the button |
| Popover doesn't resize with SwiftUI content | L | L | `sizingOptions = .preferredContentSize`; else set `contentSize` from `fittingSize` |
| Re-fold fires mid-arrangement (user clicks a window while ⌘-dragging) | M | L | Only mouse-up below the bar; user re-opens Show Hidden Icons |
| Cached frames stale after collapse/expand | M | L | Refresh on every open; classification is relative to the divider either way |

## Notes
- The store's single `onChange` stays; `AppDelegate` calls both the log and `tray.itemsChanged()` from it, which is the smallest change that keeps logging.
- Latency is logged from the click event's timestamp to just after `show(...)` returns; a screenshot confirms the popup is drawn.
- **Amendment (during implementation): no `NSApp.activate()`; a global mouse-down monitor closes the popup instead.** At runtime `NSApp.activate()` was declined (Music stayed frontmost), so `.transient` never closed the popup on outside clicks. Clicks, hover and tooltips work in the popup of an inactive app, so TrayFold now leaves focus with the user's app and installs `NSEvent.addGlobalMonitorForEvents([.leftMouseDown, .rightMouseDown])` only while the popup is open.
- **Amendment: no re-open guard.** The GOTCHA above didn't happen: a second click on the chevron closes the popup (verified without the guard), so the 0.3 s guard was removed.
- **Amendment: labels don't trim whitespace titles.** `AXElement.string` already turns empty titles into nil, and no whitespace-only title was seen; trimming also made the tooltip drop the description for such a title.
- **Amendment: the empty-state hint is broken into two lines by hand**, because automatic wrapping split "⌘-drag" at its hyphen.
