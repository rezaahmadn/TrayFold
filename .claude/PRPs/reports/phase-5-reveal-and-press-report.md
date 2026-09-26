# Implementation Report: Phase 5 — Reveal & press

## Summary
Clicking an entry in the tray now opens that app's real menu, visibly, and the bar folds back once the menu closes. `TrayController.activate(_:)` hands focus back to the user's app and starts a reveal session in the new `RevealController`: it reads where the item is right now, shrinks the divider just enough to bring it on-screen (a partial collapse aimed at the notch's right edge, then a full collapse if macOS put it somewhere else), waits until Accessibility reports it on-screen, presses it with `AXPress` on a background thread, checks five times a second until its menu, panel or popover has closed, and expands the divider again. Items that are already on-screen (under the notch, or all icons shown) are pressed in place. Every failure path ends in the same fold-back. The divider and all Accessibility calls are injected into the session as closures, so the state machine is unit-tested without touching the real bar, and the hiding layer can be swapped for macOS 27.

## Assessment vs Reality

| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | High | High: one real bug only showed up at runtime (see Issues) |
| Files Changed | 11 | 13 (1 new source, 1 new test file, 5 updated sources, 1 updated test file, README, project, plan, report) |
| Swift (app) code lines | ≤ ~1,000 | **854** code lines (no comments / blank lines), +191 over main's 663; 1,376 by `wc -l` |
| Unit tests | ~12 new | 14 new (59 total, 8 suites) |

## Spike answers (details and tables in the plan)

| Question | Answer | Evidence |
|---|---|---|
| Reveal strategy | **Partial collapse from the live frame**, full collapse as fallback, press in place if already on-screen. Where the item lands doesn't matter as long as its AX frame is on-screen. | Shrinking by d moves items by exactly d; once the bar overflows macOS reorders items and hides any whose window is left of x ≈ 870. 1Password pressed at x 599 (left of notch), 855 (not drawn) and 915: menu fully visible each time. WPS at x 821 (under the notch): panel visible. Pressed off-screen: panel at x -4325. |
| Pressing | `AXPress` in `Task.detached`, element timeout 0.25 s. NSMenu apps return `-25204` after exactly 0.25 s with the menu already open (14–30 ms after the press); without the timeout 1.5 s. Panels/popovers/Control Center return `0` in 30–130 ms. UI stays responsive. | scratch press tool sampling AX on the main thread during the press; TrayFold logs |
| Menu-close signal | **Polled AX check, 5 Hz, only during a session**: item `AXSelected` OR item's `AXMenu` child has a size OR the app has more non-standard windows (`AXSystemDialog`/`AXDialog`) than before the press. Fold back 1.6 s after the press if nothing opened; cap 5 min. | `AXMenuOpened/Closed` work only on the app element (`-25207` on items) and were missed once in 11 runs; Control Center/Slice/WPS only produce window created/destroyed. Re-folding under an open menu makes it jump to the screen edge (measured), so the session waits. |
| Outside-click re-fold | Not installed during a reveal: `DividerController.reveal(length:)` changes only the length, never `collapse()`. | code; clicks inside menus/panels never folded the bar in any run |
| Focus | Clicking a tray entry makes TrayFold active (confirmed: `NSApp.isActive` true). `NSApp.hide(nil)` hands focus back in ~30 ms, well before the item reaches the screen (~110 ms). The frontmost app was the same before, during and after every session. Menus open and take Escape normally. | osascript frontmost checks around each run |

## Measurements (author's Mac, macOS 26.7, 14" MacBook Pro)

| What | Result | How |
|---|---|---|
| Click on entry → press starts | **113–140 ms** when a reveal is needed (1Password 113/118/133/134/135 ms, WPS 132/136/137, Bitwarden 139, Sound 140, test helper 132); **0–2 ms** in place | `Pressing … N ms after the click` |
| Click → menu visible | ≈ **130–170 ms** (press start + 14–30 ms) | above + `AXMenuOpened` timing from the spike |
| Where the reveal time goes | ~110 ms is macOS moving the items after the length change (item's AX frame unchanged for 5 polls, each read < 1 ms) | temporary per-poll log |
| Menu closed → bar folded | ≤ ~0.25 s | log timestamps |
| CPU idle / while a menu is open | **0.0 %** / 0.0–0.2 % | `top -pid`, 4 × 2 s |
| Memory | 16 MB footprint | `footprint` |

## Per-item results (all through the real tray: click ⌄, click the entry)

| Item | Kind | Divider | Result |
|---|---|---|---|
| 1Password (folded) | NSMenu | shrunk to 91–98 pt; macOS drew it right of the notch | [done] menu under the icon; Escape closes; bar folds back |
| WPS Office (folded, leftmost) | panel (`AXDialog`) | shrunk to 32 pt (12 pt when the test helper was also folded) | [done] panel visible; closing it folds back |
| Bitwarden (folded) | its left-click shows the main window | shrunk to 66 pt | [done] window comes to front (its real left-click behaviour); bar folds back after 1.6 s ("no menu opened") |
| Control Center **Sound**, ⌘-dragged into the tray for the test | Control Center panel (`AXSystemDialog`) | shrunk to 139 pt | [done] Sound panel anchored at the revealed icon; closes; bar folds back. Sound moved back afterwards (see Issues) |
| TFTest (scratch helper app, folded) | NSMenu | full collapse (12 pt) | [done] menu opened; helper quit while it was open → bar folded back within ~0.2 s |
| 1Password with icons shown ("Show Hidden Icons") | NSMenu | untouched | [done] pressed in place 2 ms after the click; divider stays collapsed as the user left it |
| Under-notch item right of the divider | — | — | not reproducible on this bar (the chevron is always the leftmost item right of the divider); the in-place path above is the same code, and the spike showed WPS at x 821 opening visibly |

## Robustness checks

| Scenario | Result |
|---|---|
| Another entry clicked while a menu is open | The click on ⌄ closes the open menu and opens the tray on the same click; the new entry folds the old session back, waits for the bar to settle, then reveals (log: `Reveal ended: cancelled`, `Pressing … 403 ms`) |
| Same entry clicked again while its panel is open | Same as above: the old session folds back, the new one reveals and presses again, then folds back when the panel closes |
| App quits while its menu is open | Fold back ≤ 0.2 s later (`its menu closed`) |
| Item never reaches the screen / app gone / Accessibility revoked | Unit-tested: no press, one fold-back. (Revoking the author's Accessibility grant wasn't done at runtime.) |
| Press error | Unit-tested: no `menuOpen`, one fold-back |
| Quit TrayFold mid-session (`quit` Apple event) | `Reveal ended: TrayFold is quitting` + `Divider expanded` before exit. After exit the divider is gone, so folded icons show until TrayFold runs again (inherent); relaunch folds them. |

## Tasks Completed

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Local signing | [done] Complete | Not committed |
| 2 | `MenuBarLayout.revealLength` / `isOnScreen` | [done] Complete | |
| 3 | `AXElement` helpers | [done] Complete | Deviated: open checks moved to `RevealController.System` |
| 4 | `DividerController.reveal(length:)` / `endReveal()` | [done] Complete | |
| 5 | `RevealController` | [done] Complete | Deviated: live frame + settle wait (runtime bug) |
| 6 | Wiring + focus | [done] Complete | Deviated: plain `NSApp.hide(nil)` |
| 7 | Tests, README, measure, report, PR | [done] Complete | |

## Validation Results

| Level | Status | Notes |
|---|---|---|
| Static Analysis (clean build) | [done] Pass | 0 errors, 0 warnings in our Swift (only the system `appintentsmetadataprocessor` note) |
| Unit Tests (local, signed) | [done] Pass | `✔ Test run with 59 tests in 8 suites passed` |
| Unit Tests (CI-like, `CODE_SIGN_IDENTITY=-`) | [done] Pass | 59 passed, `findsControlCenterItems()` skipped as designed |
| Mutation check | [done] Pass | Removing the settle wait makes `anotherEntryFoldsTheFirstBackBeforeRevealingAgain` fail |
| Runtime | [done] Pass | Table above; bar left folded, all menus closed |
| Size | [done] Pass | 854 code lines |

## Files Changed

| File | Action |
|---|---|
| `TrayFold/RevealController.swift` | CREATED (reveal session, live `System`) |
| `TrayFold/MenuBarLayout.swift` | UPDATED (`revealLength`, `isOnScreen`) |
| `TrayFold/AXElement.swift` | UPDATED (`bool`, `elements`, `press`) |
| `TrayFold/DividerController.swift` | UPDATED (`reveal(length:)`, `endReveal()`) |
| `TrayFold/TrayController.swift` | UPDATED (`activate` → focus back + reveal) |
| `TrayFold/AppDelegate.swift` | UPDATED (creates the controller; `applicationWillTerminate`) |
| `TrayFoldTests/RevealControllerTests.swift` | CREATED (10 tests) |
| `TrayFoldTests/MenuBarLayoutTests.swift` | UPDATED (+4 tests) |
| `README.md` | UPDATED (status, usage) |
| `TrayFold.xcodeproj/project.pbxproj` | REGENERATED |
| `.claude/PRPs/plans/completed/phase-5-reveal-and-press.plan.md` | CREATED |

## Deviations from Plan
- **Open checks live in `RevealController.System`**, not `AXElement`, which only gained generic helpers.
- **No `isRevealable` closure**: the divider's own `isExpanded` guard covers it.
- **Live frame + settle wait** (see Issues).
- **Focus handoff without a wait loop**: the wait was added while chasing an Escape problem that turned out to be the test harness.

## Issues Encountered
- **Stale positions right after a fold-back (fixed).** Clicking a second entry while a revealed menu was open re-expanded the divider and started the next session at once. Accessibility still reported the item's revealed position for ~110 ms, so the session judged it on-screen and pressed it while it slid off-screen (WPS's panel opened off-screen). The session now reads the frame live and waits out up to 250 ms after a fold-back.
- **Escape didn't close menus in early runs: a test-harness artefact.** My click tool posted Escape key-down and key-up with no gap. Menus opened through Accessibility ignored that, from TrayFold or from a scratch tool alike; with a 20 ms gap (like a real key press) Escape works every time. A real Escape key press was not tested (no way to press a physical key from the agent).
- **Stray clicks**: before I switched to a tool that finds tray entries by their Accessibility label, two test clicks meant for tray entries (at about x 1115, y 75) landed in Chrome's tab/toolbar area while the popup was closed. Soon after, a window titled "repov" was on screen; whether a stray click caused it is unknown. The author may want to check Chrome.
- **Control Center positions renumbered.** Sound was ⌘-dragged into the tray and back. The order and x positions are exactly as before (Wi-Fi 1226, Sound 1264, Control Center 1302, Clock 1344), but macOS renumbered the stored values: `com.apple.controlcenter` WiFi 245 → 258, Sound 207 → 220, BentoBox-0 165 → 178; TrayFold chevron/divider 554/588 → 486/517 (same relative order).
- Bitwarden's main window was shown twice by tests (its left-click action) and hidden again with System Events (it had been hidden before).
- Worktree isolation refused shell commands with variables or loops; scratch scripts were written to files and run with `bash`. The Fact-Forcing gate asked for facts before `git checkout --` (reverting my temporary spike hook) and `rm -rf build-ci`; both went ahead after stating them. Nothing was denied.

## Observations for the PRD (seen, not guessed)
- **Open question 1 (detecting "closed")**: answered: a polled Accessibility check (5 Hz, only while a menu is open, ≤ 0.2 % CPU). `AXMenuClosed` alone isn't enough: Control Center, popovers and panels don't send it, and one `AXMenuOpened` was missed in 11 runs.
- **Open question 3 (`AXPress` blocking)**: answered: with a 0.25 s per-element timeout it returns `-25204` after exactly 0.25 s while the menu is open; off the main actor the UI stays responsive.
- **Open question 4 (where a revealed item lands)**: answered: anywhere with an on-screen AX frame works, including under or left of the notch (menus drop below the bar, where the screen is visible). macOS 26 hides status item windows left of x ≈ 870 (20 pt right of the notch edge) and reorders items once the bar overflows.
- Status item windows on macOS 26 all belong to the Control Center process (`CGWindowList` owner), each item's window is its length + 16 pt wide, and hidden ones are ordered out rather than moved.
- The Accessibility tree of TrayFold's own popover isn't reachable through its app's `AXWindows` (only by hit-testing), which matters for anyone scripting TrayFold with VoiceOver-style tools.

## Review fixes (PR #6 code review)
- **HIGH: a superseded session could still press its item.** `run()` checked cancellation only inside the polling loops, not between `reveal()` returning and `AXPress`. A second tray click or quitting while an item was revealed but not yet pressed could still press the old item (a Control Center item would toggle something). `run()` now checks `Task.isCancelled` right after the reveal and again immediately before the press, and folds back with "cancelled" instead. New tests hold a session between reveal and press (the check just before the press waits on a semaphore) and then either start a second `open()` (`supersededItemIsNeverPressed`) or call `stop()` (`stopBeforeThePressMeansNoPress`); both assert the first item is never pressed. Both fail when the pre-press check is removed.
- **Runtime re-check.** 1Password from the tray: pressed 134 ms after the click, Escape closes it, bar folds back. Two rapid clicks on different entries (WPS, then 1Password as fast as the popup reopens, ~0.75 s apart): the WPS session ended as "cancelled" and only 1Password was pressed after the second click. Through the real UI the second click can't land inside the ~140 ms reveal window, so WPS had already been pressed by then; its panel doesn't close when other menu bar items are clicked and stayed open next to 1Password's menu (closed afterwards by pressing WPS again). This is how WPS's panel behaves, not something the fix changed. A later option: have a superseded session close what it opened.
- Tests: **61** (16 new in this phase), local and CI-like. App code: **856** code lines.

## Tests Written

| Test File | Tests | Coverage |
|---|---|---|
| `TrayFoldTests/RevealControllerTests.swift` | 12 | Happy path and states; press in place; fallback to full collapse; never on-screen; app gone / AX off; press error; `.success` counts; grace time when nothing opens; second entry cancels the first and waits for the bar to settle; `stop()` folds back once; no press after a second `open()` or `stop()` between reveal and press (review fix) |
| `TrayFoldTests/MenuBarLayoutTests.swift` | +4 | Reveal length (partial, clamped, no notch, already on-screen), on-screen check |

## Next Steps
- [ ] Review the pull request (CI must be green)
- [ ] Coordinating agent: update the PRD (Phase 5 → complete, open questions 1, 3, 4 answered, the line count)
- [ ] Possible follow-up ("Could"): right-click an entry to send the item's secondary action (Bitwarden keeps its menu there)
