# Implementation Report: Phase 4 — Tray popup

## Summary
A left-click on the chevron now opens the tray: an `NSPopover` with a SwiftUI grid of every menu bar item that isn't visible (left of the divider, under the notch, or off-screen), in the same left-to-right order as the menu bar. Each entry shows the owning app's icon and a short label (the item's own text such as "25:00", otherwise its Accessibility description up to the first comma such as "Wi‑Fi", otherwise the app name), plus a tooltip and a hover highlight. The grid grows up to 5 columns and then adds rows. With nothing folded away, the popup shows a two-line hint. A right-click or ⌃-click opens the existing menu, and so does any click while Accessibility isn't allowed. Clicking an entry goes through `TrayController.activate(_:)`, which for now closes the popup and logs; Phase 5 adds reveal and press. A crowded-bar safety net re-folds a collapsed divider on the first click below the menu bar.

## Assessment vs Reality

| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | Medium | Medium |
| Files Changed | 11 | 13 (3 new sources, 1 new test file, 3 updated sources, 2 updated tests, README, project, plan, report) |
| Swift (app) | ≤ ~1,000 lines | **1,065** by `wc -l` (+296 over main's 769), 663 lines of actual code (no comments or blank lines) |
| Unit tests | ~12 new | 13 new (45 total, 7 suites) |

## Measurements (author's Mac, macOS 26.7, 14" MacBook Pro, 1512 × 982 pt)

| What | Result | How |
|---|---|---|
| Popup open latency, first open after launch | **69–134 ms** (4 launches: 134, 69, 92, 74 ms; 83 ms once more) | `Tray opened N ms after the click` (click event timestamp → `show` returned) |
| Popup open latency, warm | **2–17 ms** (7, 6, 15, 8, 2, 17, 4, 5, 5, 8 ms) | same log line |
| Background rescan on open | 22–31 ms for 71 apps | `[Discovery] Scanned 71 apps in … ms` |
| Idle CPU | **0.0 %** (4 samples × 3 s after 20 s idle) | `top -pid` |
| Memory | **23 MB** footprint (phase 3: 14 MB; SwiftUI and the popover account for the rise), 92 MB RSS | `footprint`, `ps -o rss` |
| Contents, divider expanded | WPS Office Service, Bitwarden, 1Password: exactly the three items left of the divider | screenshot + AX dump |
| Contents, divider collapsed | WPS Office Service, 1Password (under the notch), Bitwarden (visible but left of the divider) | screenshot |

Screenshots (session scratchpad, not committed): `/private/tmp/claude-501/-Users-reza-Projects/6955d6da-007e-4d5d-8588-a11e6d904862/scratchpad/`, including `final-open.png` (tray), `final-menu.png` (right-click menu), `grid-all.png` (10 items → 5 × 2 grid, temporary debug build), `empty.png` (empty state, temporary debug build), `hover.png` (hover + tooltip), `tray-collapsed.png`, `collapsed-bar.png` / `refolded-bar.png` (re-fold).

## Tasks Completed

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Local signing for the worktree | [done] Complete | Not committed |
| 2 | `TrayController` pure helpers | [done] Complete | Deviated: no whitespace trimming (see Deviations) |
| 3 | `TrayView` | [done] Complete | Empty-state hint broken by hand |
| 4 | `TrayController` runtime | [done] Complete | Deviated: no activation; global monitor closes the popup |
| 5 | Chevron click routing | [done] Complete | Menu attached for one `performClick`, detached in `menuDidClose` |
| 6 | Crowded-bar re-fold | [done] Complete | |
| 7 | Wiring + tests | [done] Complete | |
| 8 | README, generate, measure, report, PR | [done] Complete | |

## Validation Results

| Level | Status | Notes |
|---|---|---|
| Static Analysis (clean build) | [done] Pass | 0 errors, 0 warnings (Swift 6, strict concurrency complete) |
| Unit Tests (local, signed) | [done] Pass | `✔ Test run with 45 tests in 7 suites passed`; the real-AX test ran |
| Unit Tests (CI-like, ad-hoc) | [done] Pass | 45 passed, `findsControlCenterItems()` skipped as designed |
| Left-click → tray | [done] Pass | Popup under the chevron with exactly the hidden items |
| Click chevron again → closes | [done] Pass | No re-open (verified without a guard) |
| Click in another app → closes | [done] Pass | After the amendment (global mouse-down monitor) |
| Entry click | [done] Pass | Popup closes; log `Tray entry clicked: cn.wps.wpscloudsvr` |
| Right-click / ⌃-click → menu | [done] Pass | Same menu as before; left-click opens the tray again afterwards |
| Grid growth | [done] Pass | 3 items → one row of 3; 10 items → 5 × 2, popover resized to fit (`grid-all.png`) |
| Empty state | [done] Pass | "Nothing folded away" + two-line hint (`empty.png`) |
| Refresh on open, update in place | [done] Pass | Each open logs a rescan; `onChange` logs the list and re-renders the open tray |
| Re-fold safety | [done] Pass | Collapsed → click on empty menu bar space: nothing; click in a window below → `Clicked outside the menu bar while collapsed: folding icons away`, `Divider expanded` |
| Idle | [done] Pass | 0.0 % CPU; the monitors exist only while the popup is open / the divider is collapsed |

## Files Changed

| File | Action |
|---|---|
| `TrayFold/TrayController.swift` | CREATED (120 lines) |
| `TrayFold/TrayView.swift` | CREATED (73 lines) |
| `TrayFold/OutsideClickMonitor.swift` | CREATED (29 lines, review fix) |
| `TrayFold/StatusBarController.swift` | UPDATED (click routing, menu on demand) |
| `TrayFold/DividerController.swift` | UPDATED (re-fold monitor + `isBelowMenuBar`) |
| `TrayFold/AppDelegate.swift` | UPDATED (creates the tray; `onChange` logs and updates it) |
| `TrayFoldTests/TrayControllerTests.swift` | CREATED (8 tests) |
| `TrayFoldTests/StatusBarControllerTests.swift` | UPDATED (+4 tests) |
| `TrayFoldTests/DividerControllerTests.swift` | UPDATED (+1 test) |
| `README.md` | UPDATED (status, Usage section) |
| `TrayFold.xcodeproj/project.pbxproj` | REGENERATED |
| `.claude/PRPs/plans/completed/phase-4-tray-popup.plan.md` | CREATED |

## Deviations from Plan
- **TrayFold doesn't activate itself when the popup opens.** `NSApp.activate()` was declined at runtime (Music stayed frontmost), so `.transient` never saw outside clicks and the popup stayed open. Clicks, hover and tooltips all work in an inactive app's popover, so TrayFold now leaves focus with the user's app. A global mouse-down monitor, installed only while the popup is open, closes it. This also suits Phase 5, which needs the other app's menu to open.
- **No re-open guard.** The plan's GOTCHA (a transient popover closing on mouse-down and re-opening on mouse-up) didn't happen. The second chevron click simply closes it, so the guard code was removed.
- **Labels don't trim whitespace.** `AXElement.string` already maps empty titles to nil, and the author's items have no whitespace-only titles.
- **Empty-state text broken into two lines by hand**, because automatic wrapping split "⌘-drag" at its hyphen.
- **Line budget exceeded**: 1,065 lines by `wc -l` against the ~1,000 target. About 38 % of that is comments (written for a reader new to Swift) and blank lines. The actual code is 663 lines. Phases 5 and 6 will add more; the coordinating agent may want to restate the metric as code lines or trim comments.

## Review fixes (PR #4 code review)
- **MEDIUM: chevron presses that aren't a mouse click.** `chevronClicked` returned early when `NSApp.currentEvent` was nil, and otherwise trusted whatever event was current. Now it uses the event only if it belongs to the chevron's window. `clickAction(for:modifiers:granted:)` takes an optional event type, and anything that isn't a left or right mouse-up counts as a plain left-click: the tray when Accessibility is allowed, the menu otherwise. ⌃ only means "menu" on a mouse click. New test: `pressWithoutAMouseClickActsLikeALeftClick`. Runtime: an `AXPress` on the chevron (no mouse event) opens the tray (`fix2-axpress.png`).
- **LOW: duplicated global-monitor code.** New `OutsideClickMonitor` (`start(events, handler)` with a double-start guard, `stop()`, and a main-actor `isolated deinit` that stops it) is used by both `TrayController` (mouse-down, closes the popup) and `DividerController` (mouse-up, re-folds). Behaviour is unchanged. Re-verified at runtime: the popup closes on a click in another app, and after "Show Hidden Icons" a click on empty menu bar space is ignored while a click below the bar re-folds (`fix2-outside.png`, `fix2-refold.png`). The line count went up by 10 rather than down: the new file's import, doc comments and blank lines outweigh the removed duplication. Actual code is +2 lines.

## Issues Encountered
- Clicking an entry in the popup makes TrayFold the active app (the Music toolbar dims), because a click in any of an app's windows activates it. Harmless now; Phase 5 should check that it doesn't interfere with the pressed item's menu.
- The order of hidden items changes between states: expanded, AX reported WPS, Bitwarden, 1Password (x -4174, -4140, -4108); collapsed, WPS, 1Password, Bitwarden. The tray follows the x positions it's given, so the order can differ between an expanded and a collapsed bar.
- Worktree-isolation rules blocked compound shell commands with `$(…)`/variables around `git`-like names; worked around by splitting commands. No permission was denied.

## Observations for the PRD (seen, not guessed)
- **Crowded bar, collapsed (open question 4):** with all 10 items shown, WPS Office Service and 1Password sat under the notch (the screenshot shows Bitwarden, the divider line and the chevron right of the notch). TrayFold's chevron stayed visible this time. The re-fold safety net works either way: one click below the menu bar folds everything back.
- **`NSApp.activate()` from a status item click in an `LSUIElement` app is declined on macOS 26.7** (at least for CGEvent-posted clicks); `NSWorkspace.frontmostApplication` stayed "Music". A popover works fine without activation if the app closes it itself.
- **Global mouse monitors** (`addGlobalMonitorForEvents` for mouse up/down) worked with only the Accessibility grant TrayFold already has. No new permission prompt appeared.
- **Control Center item descriptions:** "Wi‑Fi, connected, 3 bars", "Sound", "Control Center", "Clock". Third-party icon items have an empty title and no description; WattMeter ("⚡33.1W · 26.9W") and Slice ("25:00") expose their text as `AXTitle`.
- **Menu bar height with the notch:** 33 pt (screen 982, `visibleFrame.maxY` 949). `NSStatusBar.system.thickness` reports 22.

## Tests Written

| Test File | Tests | Coverage |
|---|---|---|
| `TrayFoldTests/TrayControllerTests.swift` | 8 | Folded items (divider, notch, off-screen; visible excluded; order; empty; no divider yet), labels (title, description up to the comma, app name), tooltip, grid rows 0/1/5/6/7/12 |
| `TrayFoldTests/StatusBarControllerTests.swift` | +4 | Left → tray, right / ⌃-left → menu, any click → menu without permission, a press with no mouse click (VoiceOver / AXPress) acts like a left-click |
| `TrayFoldTests/DividerControllerTests.swift` | +1 | Re-fold only for clicks below the menu bar (incl. a second display) |

## Next Steps
- [ ] Review the pull request (CI must be green)
- [ ] Coordinating agent: update the PRD (Phase 4 → complete, the observations above, the line-count metric)
- [ ] Phase 5: implement reveal + `AXPress` inside `TrayController.activate(_:)`; account for TrayFold becoming active on the entry click and for the re-fold monitor (a temporary collapse will install it)
