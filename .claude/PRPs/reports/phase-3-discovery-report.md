# Implementation Report: Phase 3 — Discovery

## Summary
TrayFold now keeps a live, sorted list of every other app's menu bar items, read through the Accessibility API. Nothing is polled: the list updates when an app launches or quits, when the Accessibility permission changes, and on an explicit `refresh()` (Phase 4's popup will call it on open). Scans run off the main actor with a 0.25 s per-call timeout, so a hung app costs at most 0.25 s and never blocks the menu bar. A pure function classifies any item as visible, hidden by the divider, under the notch, or off-screen. The only visible change is in the unified log.

## Assessment vs Reality

| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | Medium | Medium |
| Confidence | High (spike proved enumeration) | Met. One design change (launch detection, see Deviations) |
| Files Changed | 11 | 12 (5 new sources, 3 new test files, AppDelegate, project, plan, report) |
| Swift (app) | ~+250 lines | +383 lines (197 → 580), about half of it doc comments |
| Unit tests | ~18 | 20 new (26 total) |

## Measurements (author's Mac, macOS 26.7, 14" MacBook Pro, 1512-pt screen)

| What | Result | How |
|---|---|---|
| Running apps | 105 (10 regular, 43 accessory, 52 background-only) | scratch script |
| Apps asked per full scan | 55–56 (background-only and TrayFold skipped) | app log |
| First full scan (cold) | **233–249 ms** in the app; 221–483 ms in the test host | `[Discovery] Scanned 55 apps in 233 ms: 8 items` |
| First full scan, all 105 apps | 830 ms | scratch script (`swiftc -O`) |
| Later full scans (warm) | **19–28 ms** for all 105 apps | scratch script, passes 2–3 |
| One-app rescan after a launch | 8–9 ms | app log |
| Hung app (SIGSTOP) | exactly the timeout: 255 ms at 0.25 s, 1005 ms at 1.0 s; error -25204 | scratch helper app |
| Items found | **8–10** (Docker, WPS, Slice, wattmeter, 4 Control Center: Wi-Fi, Sound, Control Center, Clock; +2 from the Phase 2 build before self-exclusion was widened) | app log |
| Zero-size Control Center children skipped | 5 at first, 10 later | spike |
| Idle CPU / memory | 0.0 % (`top`, 3 samples) / 14 MB footprint | `top`, `footprint` |

Decision from the numbers: the first scan (~0.25 s, more with a hung app) is too slow for the main thread, so scans run in `Task.detached`. Later scans are cheap enough that Phase 4 can call `refresh()` on every popup open.

## Tasks Completed

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Local signing for the worktree | [done] Complete | Real-AX test runs locally; not committed |
| 2 | `AXElement` | [done] Complete | Generic `AXValue` reader replaced after a compiler warning |
| 3 | `MenuBarItem` + `MenuBarItemScanner` | [done] Complete | Deviated: also skips TrayFold's bundle id |
| 4 | `MenuBarItemStore` | [done] Complete | Deviated: key-value observing of `runningApplications` instead of launch/quit notifications |
| 5 | `MenuBarLayout` | [done] Complete | |
| 6 | `AppDelegate` wiring | [done] Complete | +8 lines, one block after `statusBar = …` |
| 7 | Tests | [done] Complete | |
| 8 | Generate, measure, report, PR | [done] Complete | |

## Validation Results

| Level | Status | Notes |
|---|---|---|
| Static Analysis (build) | [done] Pass | 0 errors, 0 warnings, Swift 6 strict concurrency complete |
| Unit Tests (local, signed) | [done] Pass | `✔ Test run with 26 tests in 5 suites passed`; real-AX test ran (0.22–0.48 s) |
| Unit Tests (CI-like, ad-hoc) | [done] Pass | `➜ Test findsControlCenterItems() skipped: "Needs the Accessibility permission (not available on CI)"`, 26 passed |
| Ordering guard | [done] Pass | `overlappingUpdatesApplyInOrder` fails (`[1, 2]` instead of `[2]`) when the update queue is removed, passes with it |
| Integration (runtime) | [done] Pass | Launch → full scan logged; `LSUIElement` helper launched → `Scanned 1 apps in 9 ms: 1 items` 2 s later; quit → item dropped; TextEdit launch → rescanned, no change logged |
| Idle | [done] Pass | 0.0 % CPU, no timers |

## Files Changed

| File | Action |
|---|---|
| `TrayFold/AXElement.swift` | CREATED |
| `TrayFold/MenuBarItem.swift` | CREATED |
| `TrayFold/MenuBarItemScanner.swift` | CREATED |
| `TrayFold/MenuBarItemStore.swift` | CREATED |
| `TrayFold/MenuBarLayout.swift` | CREATED |
| `TrayFold/AppDelegate.swift` | UPDATED (+8) |
| `TrayFoldTests/MenuBarLayoutTests.swift` | CREATED (10 tests) |
| `TrayFoldTests/MenuBarItemStoreTests.swift` | CREATED (8 tests) |
| `TrayFoldTests/MenuBarItemScannerTests.swift` | CREATED (2 tests, 1 needs the permission) |
| `TrayFold.xcodeproj/project.pbxproj` | REGENERATED |
| `.claude/PRPs/plans/completed/phase-3-discovery.plan.md` | CREATED |

## Deviations from Plan
- **Launch/quit detection uses key-value observing of `NSWorkspace.shared.runningApplications`.** The planned `didLaunchApplicationNotification` never fired for a menu-bar-only test app. Apple documents that it isn't posted for `LSUIElement` or background apps, and most menu bar apps are `LSUIElement`. KVO reports every app.
- **Self-exclusion by bundle id as well as pid.** The runtime check ran next to the Phase 2 agent's development build, whose chevron and divider appeared as discovered items.
- **Permission changes**: the store listens to the `com.apple.accessibility.api` broadcast itself instead of using `AccessibilityPermission.onChange`, which is a single callback already used by `StatusBarController`. Changing either class would have collided with Phase 2.
- **Zero-width items are skipped** in the scanner (Control Center modules macOS isn't drawing: no title, description or identifier).

## Issues Encountered
- NSWorkspace notifications were never delivered to a command-line tool started from the agent's shell (even with `NSApplication.run()`), so launch timing was checked in the real app instead.
- `AXValueGetValue` into a generic `T` produced a compiler warning ("forming 'UnsafeMutableRawPointer' to a variable of type 'T'"); replaced with concrete `CGPoint` / `CGSize` reads.
- One CI-like test run reported `** TEST FAILED **` with no failing test; the next two clean runs passed. Most likely the test host was killed mid-run by the parallel Phase 2 agent's `pkill -x TrayFold`, as warned.

## Observations for the PRD (seen, not guessed)
- While Phase 2's divider was expanded (TrayFold item at x = -4075, width 5002), four newly launched helper items appeared **left** of it (x ≈ -4315 … -5016): new apps' items land in the tray by default and stay enumerable.
- `AXUIElementSetMessagingTimeout` bounds the wait for a hung app exactly, returning `kAXErrorCannotComplete` (-25204). This supports the PRD's mitigation for Phase 5's blocking `AXPress`: set the timeout on the item element, not process-wide.
- The notch areas were `0–665` / `850–1512` again. It was not possible to overflow the bar into the notch during this phase (the divider hid the test items), so what Accessibility reports for notch-hidden items is still unknown.

## Tests Written

| Test File | Tests | Coverage |
|---|---|---|
| `TrayFoldTests/MenuBarLayoutTests.swift` | 10 | Visible, hidden by expanded/collapsed divider, off-screen, notch overlap and edge, no notch, precedence, notch range and invalid areas |
| `TrayFoldTests/MenuBarItemStoreTests.swift` | 8 | Sorted refresh, no permission, recovery and revocation, change-only callbacks, one-app rescan, quit, update ordering, log summary |
| `TrayFoldTests/MenuBarItemScannerTests.swift` | 2 | Real scan finds Control Center items (skipped without permission); TrayFold excluded |

## Next Steps
- [ ] Review the pull request (CI must be green)
- [ ] Coordinating agent: merge with Phase 2, update the PRD
- [ ] Phase 4: pass the divider's window `frame.minX` to `MenuBarLayout.visibility`; show the cached `items` right away and update on `onChange` after `refresh()`
