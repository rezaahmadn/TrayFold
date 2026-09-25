# Implementation Report: Phase 2 — Divider

## Summary
TrayFold now has a second menu bar item, the divider, placed immediately left of the chevron. It starts expanded (5,000 pt wide, invisible), which pushes every item to its left off-screen. Collapsed, it's a thin dimmed line. The chevron's menu toggles it ("Show Hidden Icons" / "Hide Icons", with the hint "⌘-drag icons left of the divider to hide them"). Its position survives relaunch. A first launch seeds macOS's own position defaults so the divider lands next to the chevron. The divider refuses to expand if it sits right of the chevron, and opening TrayFold again re-folds it. At the author's request, the chevron glyph is now the SF Symbol `chevron.down`.

## Assessment vs Reality

| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | Medium | Medium |
| Files Changed | ~7 | 9 (incl. generated project, plan, report) |
| Swift (app) | — | 386 lines total (+189 vs phase 1) |
| Unit tests | 13 in 3 suites | 12 in 3 suites (the template-glyph test went away with the custom glyph) |

## Tasks Completed

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | `DividerController` | [done] Complete | Deviated: 5,000 pt; guard uses stored positions; seeding inside `init` |
| 2 | Chevron menu toggle | [done] Complete | `NSMenuItem.subtitle` carries the ⌘-drag hint |
| 3 | Wiring | [done] Complete | Divider created before the chevron; + reopen → expand |
| 4 | Unit tests | [done] Complete | 7 divider tests |
| 5 | Project + README | [done] Complete | |
| + | Chevron glyph → `chevron.down` | [done] Complete | Added at the author's request; asset deletion pending (see Issues) |

## Validation Results

| Level | Status | Notes |
|---|---|---|
| Static Analysis (clean build) | [done] Pass | 0 errors, 0 warnings, Swift 6 strict concurrency |
| Unit Tests | [done] Pass | `✔ Test run with 12 tests in 3 suites passed` (local signing and CI-style `CODE_SIGN_IDENTITY=-`) |
| Placement | [done] Pass | Seeded `TrayFoldDivider = 547` next to `TrayFoldChevron = 546`. AX: divider x=868 w=14, chevron x=925 |
| Expand hides items | [done] Pass | AX: divider x=-4083 w=5002; a test item left of it at x=-4152; real Docker item at x=-4083 after a ⌘-drag; screenshots show them gone |
| Collapse restores | [done] Pass | Docker back at x=905, the divider shows as a dimmed line left of ⌄ |
| ⌘-drag writes position | [done] Pass | Simulated ⌘-drag of the divider: macOS rewrote `TrayFoldDivider` 500 → 580 at once (and renumbers neighbours) |
| Guard | [done] Pass | Stored divider = 500 (< chevron 546) → launch logs `Not hiding icons…` and stays collapsed; chevron stays visible |
| Relaunch | [done] Pass | Positions kept (588/554), divider back left of the chevron, expanded |
| Reopen | [done] Pass | Collapsed, then `open TrayFold.app` → `Divider expanded` |

## Files Changed

| File | Action |
|---|---|
| `TrayFold/DividerController.swift` | CREATED |
| `TrayFoldTests/DividerControllerTests.swift` | CREATED |
| `TrayFold/StatusBarController.swift` | UPDATED (toggle item, `autosaveName` constant, `chevron.down`) |
| `TrayFold/AppDelegate.swift` | UPDATED (creates/retains divider, reopen handler) |
| `TrayFoldTests/StatusBarControllerTests.swift` | UPDATED (`chevron.down`, template-asset test dropped) |
| `TrayFold.xcodeproj/project.pbxproj` | GENERATED |
| `README.md` | UPDATED (status + usage line) |

## Deviations from Plan
- **Expanded length 5,000 pt, not 10,000.** A 10,000-pt request produced a 5,016-pt window on macOS 26 (AX reports 5,002 wide for 5,000). Asking for more changes nothing; the PRD's "~5000" was right.
- **Ordering guard uses the stored "Preferred Position" values, not window frames.** Right after creation, the status item windows report `(0, 0, w, 0)` and then `(0, -33, w, 33)` until macOS places them. The first frame-based version wrongly refused to expand at launch. The defaults are always there (seeded or written by macOS on every ⌘-drag), so the check is exact and needs no timers.
- **Seeding moved into `DividerController.init`.** The divider is created before the chevron, so `AppDelegate` shrinks to one line. `StatusBarController.screenMinX` was dropped.
- **Added `applicationShouldHandleReopen` → `expand()`**, a recovery path for the overflow finding below.
- **Chevron glyph → SF Symbol `chevron.down` (added at the author's request).** `Icon`/`icon(granted:)` became `symbolName(granted:) -> String`, and the template-asset test was removed. The app icon is unchanged.

## Issues Encountered
- **Overflowing bar hides TrayFold's own items when collapsed.** A 71-pt test item left of the divider plus all current items overflowed the right-of-notch space by ~4 pt. On collapse, macOS 26 put the test item *right* of the chevron and hid both TrayFold items (AX still reported them at x≈844–900; screenshots show them undrawn). Mitigations: reopening the app re-folds, and a README note. Phase 4/5 should consider auto re-folding after a timeout.
- **Unused glyph removed.** After the author approved, `MenuBarIcon.imageset`, `Design/MenuBarIcon.svg` and their `render-icons.sh` lines were deleted in a follow-up commit.
- The Phase 3 agent's TrayFold instance ran at the same time for a while. It shares the bundle id and the `TrayFoldChevron` autosave name, so two chevrons appeared and positions shifted. Checks were repeated with only one instance running.

## Tests Written

| Test File | Tests | Coverage |
|---|---|---|
| `TrayFoldTests/DividerControllerTests.swift` | 7 | Lengths, menu titles, defaults key, seeding (fresh install / chevron placed / user-placed divider untouched), ordering guard |
| `TrayFoldTests/StatusBarControllerTests.swift` | 1 | Symbol per permission state |

## Next Steps
- [ ] Review the pull request (CI must be green)
- [ ] PRD: Phase 2 → complete; record the answers to the open questions (see PR)
