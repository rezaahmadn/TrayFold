# Plan: Phase 2 — Divider

## Summary
Add TrayFold's second menu bar item: a **divider** that sits immediately left of the chevron. Expanded (the default at launch) it is 10,000 pt wide and invisible, so every status item to its left is pushed off the left edge of the screen. Collapsed it is a thin, dimmed vertical line, so the user can see where to ⌘-drag icons. The chevron's menu gains "Show Hidden Icons" / "Hide Icons" with a one-line ⌘-drag hint. The divider's position survives relaunch through its `autosaveName`, and a first launch places it right next to the chevron by seeding macOS's own "Preferred Position" defaults.

## User Story
As a notched-MacBook user,
I want a divider I can ⌘-drag menu bar icons past to fold them away,
so that the icons I rarely need stop crowding (and overflowing) the space beside the notch.

## Problem → Solution
Only the chevron exists; nothing can be hidden → a `DividerController` owns a second `NSStatusItem` whose `length` toggles between a small visible separator and 10,000 pt, controlled from the chevron's menu.

## Metadata
- **Complexity**: Medium
- **Source PRD**: `.claude/PRPs/prds/trayfold.prd.md`
- **PRD Phase**: Phase 2 — Divider
- **Estimated Files**: 7 (1 new source, 1 new test, 3 updated sources/docs, generated project)
- **Execution**: subagent in its own worktree, in parallel with Phase 3 (Discovery). Stay out of Accessibility enumeration code. Don't edit the PRD (the coordinator does after both merge).

---

## UX Design

### Before
```
Menu bar:  [ … ]  Docker  WPS  Slice  (TrayFold)  Wi-Fi  Sound  CC  Clock
                                        └ menu: Accessibility line · Quit
```

### After
```
Launch (expanded, the default): items left of the divider are off-screen.
Menu bar:  [ … ]  WPS  Slice  (TrayFold)  Wi-Fi  Sound  CC  Clock
           ▲ Docker was ⌘-dragged left of the divider → gone

Chevron menu:
┌──────────────────────────────────────────────┐
│ Accessibility: Allowed                       │ (disabled)
│ ──────────────────────────────────────────── │
│ Show Hidden Icons                            │
│   ⌘-drag icons left of the divider to hide   │ (subtitle)
│ ──────────────────────────────────────────── │
│ Quit TrayFold                            ⌘Q  │
└──────────────────────────────────────────────┘

Collapsed ("Show Hidden Icons" clicked):
Menu bar:  [ … ]  Docker  │  (TrayFold)  WPS  Slice  Wi-Fi …
                          ▲ dimmed divider line; click it (or "Hide Icons") to fold again
```

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Launch | Chevron only | Chevron + divider (expanded, invisible) | Items left of the divider are off-screen |
| Chevron menu | Permission line, Quit | + "Show Hidden Icons" / "Hide Icons" with ⌘-drag hint | Title follows the divider state |
| Divider (collapsed) | — | Thin dimmed line; click → folds (expands) | Cell disabled while expanded, so clicks on empty bar space do nothing |
| ⌘-drag | — | User moves icons across the divider; position remembered | Divider can't be dragged out of the bar |
| Relaunch | — | Divider returns to where the user left it; always starts expanded | `autosaveName = "TrayFoldDivider"` |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `TrayFold/StatusBarController.swift` | 1-78 | The chevron item: status item creation, menu, `menuWillOpen`, static pure helpers |
| P0 | `TrayFold/AppDelegate.swift` | 1-27 | Launch wiring, test-host early return, retained controllers |
| P0 | `TrayFoldTests/StatusBarControllerTests.swift` | 1-18 | Swift Testing style, "don't construct real menu bar items in tests" |
| P1 | `TrayFold/AccessibilityPermission.swift` | 10-39 | Logger, injected dependency, doc-comment density |
| P1 | `TrayFoldTests/AccessibilityPermissionTests.swift` | 1-44 | Test suite doc comment, fakes |
| P2 | `.claude/PRPs/prds/trayfold.prd.md` | "Technical Approach", "Phase 2" | Divider requirements and risks |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| Ice divider | `github.com/jordanbaird/Ice` `Ice/MenuBar/ControlItem/ControlItem.swift` | `Lengths.expanded = 10_000`; while hiding: `button.cell?.isEnabled = false`, `button.isHighlighted = false`, `button.image = nil` |
| Ice defaults keys | `Ice/Utilities/StatusItemDefaults.swift` | macOS stores item order in `UserDefaults.standard` as `"NSStatusItem Preferred Position <autosaveName>"` (a `CGFloat`) |
| Ice first-launch seeding | `ControlItem.swift` init | If no stored position: app icon = `0`, hidden divider = `1`, written **before** the `NSStatusItem` is created |
| Thaw (Ice fork) | `github.com/thaw-app/Thaw` `Thaw/MenuBar/ControlItem/ControlItem.swift` | Same `expanded = 10000`; seeds only when nothing is stored (re-seeding every launch yanked user-placed dividers back, issue #895) |
| `NSStatusItem.behavior` | Apple docs | Default is `[]`: without `.removalAllowed`, ⌘-dragging the item out of the bar is refused |

```
KEY_INSIGHT: "Preferred Position" is the item's distance from the RIGHT edge of the screen. Measured on this Mac: chevron stored at 546, AX shows it at x=933, w=36 on a 1512-pt screen (1512-933-36 = 543 ≈ 546). Bigger number = further left.
APPLIES_TO: Task 1 (seeding)
GOTCHA: a brand-new item with no stored position is placed at the FAR LEFT of the status area, which on a crowded notched bar can be under the notch. Seeding "chevron position + 1" puts the divider immediately left of the chevron. On a fresh install neither exists: seed chevron = 0 (rightmost third-party slot, always visible) and divider = 1, exactly like Ice/Thaw.

KEY_INSIGHT: Seed only when the divider has no stored position. macOS rewrites the value itself whenever the user ⌘-drags; overwriting it on every launch would undo the user's placement (Thaw #895).
APPLIES_TO: Task 1

KEY_INSIGHT: 10,000 pt (not ~5,000) is what both Ice and Thaw use today; it covers displays up to ~5K wide. The PRD's spike used 5,002 pt, which also worked on this 1512-pt display.
APPLIES_TO: Task 1

KEY_INSIGHT: While expanded, the divider's (mostly off-screen) button covers the empty menu bar between the app menus and the chevron. A disabled cell keeps clicks there from highlighting it or firing its action.
APPLIES_TO: Task 1

KEY_INSIGHT: If the user ⌘-drags the divider to the RIGHT of the chevron, expanding would push the chevron itself off-screen and TrayFold becomes unreachable (it starts expanded on every launch). Guard: refuse to expand while the divider is not left of the chevron, and log it.
APPLIES_TO: Tasks 1, 3
```

---

## Patterns to Mirror

### STATUS_ITEM_CREATION
```swift
// SOURCE: TrayFold/StatusBarController.swift:12-17
init(permission: AccessibilityPermission) {
    self.permission = permission
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()
    // macOS remembers where the user ⌘-dragged an item with this name.
    statusItem.autosaveName = "TrayFoldChevron"
```

### PURE_STATIC_HELPER (testable without a menu bar)
```swift
// SOURCE: TrayFold/StatusBarController.swift:45-49
/// TrayFold's own glyph once allowed, a warning triangle until then.
/// Pure (no AppKit calls), so tests can check it without a menu bar.
static func icon(granted: Bool) -> Icon {
    granted ? .asset("MenuBarIcon") : .symbol("exclamationmark.triangle")
}
```

### MENU_REFRESH
```swift
// SOURCE: TrayFold/StatusBarController.swift:69-73
// Called just before the menu shows: the cheapest moment to re-check the permission.
func menuWillOpen(_ menu: NSMenu) {
    permission.refresh()
    update()
}
```

### LOGGING
```swift
// SOURCE: TrayFold/AccessibilityPermission.swift:12, 37
private static let logger = Logger(subsystem: "com.rezaahmadn.TrayFold", category: "Accessibility")
Self.logger.notice("Accessibility allowed changed to \(now, privacy: .public)")
```

### APP_WIRING
```swift
// SOURCE: TrayFold/AppDelegate.swift:9-15, 24
// Kept alive for the app's lifetime; releasing them would remove the menu bar item.
private var permission: AccessibilityPermission?
private var statusBar: StatusBarController?
func applicationDidFinishLaunching(_ notification: Notification) {
    // Unit tests run inside this app; skip the menu bar item and permission prompt there.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
    ...
    statusBar = StatusBarController(permission: permission)
```

### TEST_STRUCTURE
```swift
// SOURCE: TrayFoldTests/StatusBarControllerTests.swift:5-11
/// Only the icon choice and the bundled glyph are unit-tested; the real menu bar item is checked by hand.
@MainActor
struct StatusBarControllerTests {
    @Test func iconShowsWarningUntilAllowed() {
        #expect(StatusBarController.icon(granted: false) == .symbol("exclamationmark.triangle"))
```

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `TrayFold/DividerController.swift` | CREATE | Divider status item, expand/collapse, position seeding, pure helpers |
| `TrayFold/StatusBarController.swift` | UPDATE | Toggle menu item + hint; shared `autosaveName` constant; exposes chevron x for the ordering guard |
| `TrayFold/AppDelegate.swift` | UPDATE | Seed positions, create and retain the divider (test-host return stays first) |
| `TrayFoldTests/DividerControllerTests.swift` | CREATE | Lengths, titles, seeding, ordering guard |
| `TrayFold.xcodeproj/` | GENERATE | `xcodegen generate` picks up the new files |
| `README.md` | UPDATE | Status line + one usage line |

## NOT Building

- Accessibility enumeration of other apps' items, "is this item hidden?" logic (Phase 3).
- Popup grid, chevron click behavior beyond its menu (Phase 4).
- Reveal-and-press, auto re-hide timers (Phase 5).
- Extra spacer items for > 5K displays (Thaw does this; not needed on the target Mac).
- Remembering expanded/collapsed across launches (always starts expanded, per PRD).
- Any PRD edit.

---

## Step-by-Step Tasks

### Task 1: `DividerController`
- **ACTION**: Create `TrayFold/DividerController.swift`.
- **IMPLEMENT**:
  - `@MainActor final class DividerController: NSObject` with `static let autosaveName = "TrayFoldDivider"`, a `Logger` (category `"Divider"`), `private let statusItem`, `private(set) var isExpanded`.
  - `enum Lengths { collapsed = 12, expanded = 10_000 }` and `static func length(isExpanded:) -> CGFloat`.
  - `static func preferredPositionKey(_ autosaveName: String) -> String` → `"NSStatusItem Preferred Position \(autosaveName)"`.
  - `static func seedPositions(in defaults: UserDefaults = .standard, chevron: String)`: if the divider key is missing, write chevron = 0 when missing, then divider = chevron + 1. Logs what it seeded.
  - `static func isSafeToExpand(dividerMinX: CGFloat?, chevronMinX: CGFloat?) -> Bool`: true when either is unknown, else `dividerMinX < chevronMinX`.
  - `init(chevronMinX: @escaping () -> CGFloat?)`: create the item with the collapsed length, set `autosaveName`, `behavior = []`, button target/action (click on collapsed line → `expand()`), then `expand()`.
  - `expand()`: guard `isSafeToExpand`, else log `.error` and stay collapsed; set length, `image = nil`, `cell?.isEnabled = false`, `isHighlighted = false`.
  - `collapse()`: length collapsed, `cell?.isEnabled = true`, image = separator (thin rounded line drawn into a template `NSImage`, `appearsDisabled = true` to dim it, accessibility description "TrayFold divider").
  - `toggle()`, `var screenMinX: CGFloat? { statusItem.button?.window?.frame.minX }` (documented: same x axis as Accessibility positions on the main display).
- **MIRROR**: STATUS_ITEM_CREATION, PURE_STATIC_HELPER, LOGGING.
- **IMPORTS**: `AppKit`, `os`.
- **GOTCHA**: Seed **before** any `NSStatusItem` with that autosave name exists (macOS reads the key when `autosaveName` is set). Never call `NSStatusBar.removeStatusItem`/`isVisible = false`: both delete the stored position (Ice comments). The `NSImage` drawing handler must not capture actor-isolated state.
- **VALIDATE**: Build: zero warnings.

### Task 2: Chevron menu toggle
- **ACTION**: Update `TrayFold/StatusBarController.swift`.
- **IMPLEMENT**: `static let autosaveName = "TrayFoldChevron"` (used for the item and by the seeding); `init(permission:divider:)`; a `dividerItem` `NSMenuItem` (target self, action `toggleDivider`) with `subtitle = dividerHint`; separators so the menu reads status / toggle / quit; `static func dividerTitle(isExpanded:)` → "Show Hidden Icons" / "Hide Icons"; `update()` sets the title; `var screenMinX: CGFloat?` for the guard. Doc comment no longer says "later phases add the divider".
- **MIRROR**: MENU_REFRESH, PURE_STATIC_HELPER.
- **IMPORTS**: —
- **GOTCHA**: `NSMenuItem.subtitle` is macOS 14.4+, fine for a macOS 26 target. The divider must exist before the chevron's menu reads it, so `divider` is passed in (not created here).
- **VALIDATE**: Build.

### Task 3: Wiring
- **ACTION**: Update `TrayFold/AppDelegate.swift`.
- **IMPLEMENT**: After the test-host return: `DividerController.seedPositions(chevron: StatusBarController.autosaveName)`; create the divider with `chevronMinX: { [weak self] in self?.statusBar?.screenMinX }`; create the status bar with the divider; keep both in stored properties.
- **MIRROR**: APP_WIRING.
- **GOTCHA**: Seeding before either item is created. The chevron is created after the divider, so its frame is unknown during the divider's first `expand()`; the guard treats "unknown" as safe, and the seeding makes the order correct on first launch. Re-run the guard once the chevron exists (`divider.expand()` after creating the status bar) so a divider the user dragged right of the chevron is caught on launch.
- **VALIDATE**: `Scripts/run.sh`, then the runtime checks below.

### Task 4: Unit tests
- **ACTION**: Create `TrayFoldTests/DividerControllerTests.swift`.
- **IMPLEMENT**: tests for `length(isExpanded:)`, `StatusBarController.dividerTitle`, `preferredPositionKey`, `seedPositions` on a throwaway `UserDefaults(suiteName:)` (fresh install, chevron already placed, divider already placed = untouched), `isSafeToExpand` (unknown, left, right/equal).
- **MIRROR**: TEST_STRUCTURE.
- **GOTCHA**: Never construct `DividerController` in tests (it would put a 10,000-pt item into the real menu bar). Remove the suite's persistent domain at the end of each test.
- **VALIDATE**: `✔ Test run with N tests in 3 suites passed`.

### Task 5: Project + README
- **ACTION**: `xcodegen generate`; README status line and one usage line.
- **VALIDATE**: `git status` shows the new files in `TrayFold.xcodeproj/project.pbxproj`; `Config/Signing.local.xcconfig` not listed.

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|
| `lengthsPerState` | expanded / collapsed | 10,000 / 12 | No |
| `menuTitleFollowsState` | expanded / collapsed | "Show Hidden Icons" / "Hide Icons" | No |
| `preferredPositionKeyMatchesAppKit` | `"TrayFoldDivider"` | `"NSStatusItem Preferred Position TrayFoldDivider"` | No |
| `freshInstallSeedsChevronThenDivider` | empty defaults | chevron 0, divider 1 | Yes |
| `dividerIsSeededJustLeftOfPlacedChevron` | chevron 546 | divider 547, chevron untouched | Yes |
| `userPlacedDividerIsLeftAlone` | divider 800 | unchanged | Yes |
| `expandIsRefusedWhenDividerIsRightOfChevron` | combos | true when unknown or left, false otherwise | Yes |

### Edge Cases Checklist
- [x] First launch with no stored positions
- [x] Existing chevron position (author's machine)
- [x] User moved the divider (don't re-seed)
- [x] Divider dragged right of the chevron (refuse to expand)
- [ ] Multiple displays / >5K width: out of scope (Thaw spacer items)

---

## Validation Commands

### Static Analysis (build = type check)
```bash
xcodegen generate
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintentsmetadataprocessor
```
EXPECT: `** BUILD SUCCEEDED **`, no `error:`/`warning:` lines.

### Unit Tests
```bash
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Debug -derivedDataPath build test 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"
```
EXPECT: `✔ Test run with 13 tests in 3 suites passed`, `** TEST SUCCEEDED **`.

### Runtime
```bash
Scripts/run.sh; sleep 2
defaults read com.rezaahmadn.TrayFold | grep "Preferred Position"
/usr/bin/log show --last 2m --predicate 'subsystem == "com.rezaahmadn.TrayFold"' --style compact
screencapture -x -R0,0,1512,40 /tmp/…/bar.png
```
EXPECT: a `TrayFoldDivider` position one above the chevron's; log lines for seeding/expand; an AX listing (read-only spike) shows the divider's width 10,000 when expanded and a test item left of it at negative x, back on-screen after collapse.

### Manual Validation
- [ ] Divider appears immediately left of the chevron on first launch.
- [ ] Launch: nothing visible for the divider; items left of it are gone.
- [ ] "Show Hidden Icons" → thin line appears, hidden icons return; title becomes "Hide Icons".
- [ ] ⌘-drag an icon left of the line, "Hide Icons" → the icon disappears.
- [ ] Relaunch → divider in the same place, expanded.
- [ ] ⌘-dragging the divider off the bar is refused.

---

## Acceptance Criteria
- [ ] All tasks completed
- [ ] Build: zero errors, zero warnings (Swift 6 strict concurrency)
- [ ] All unit tests pass
- [ ] Runtime: expanded pushes items left of the divider off-screen; collapsing brings them back
- [ ] Position persists across relaunch

## Completion Checklist
- [ ] Doc comments explain the macOS-specific why (lengths, Preferred Position, disabled cell)
- [ ] State changes logged with `.notice`, refused expand with `.error`
- [ ] Pure logic in `static` functions, tested without a menu bar
- [ ] No Accessibility scanning code, no PRD edit
- [ ] Generated project committed; local signing file not committed

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Seeded position ignored on macOS 26 | L | M | Runtime check of AX x-positions; fallback: user ⌘-drags once, autosave keeps it |
| User drags divider right of chevron → chevron hidden | M | H | `isSafeToExpand` guard + `.error` log |
| Merge conflict with Phase 3 in `AppDelegate` | M | L | Keep wiring to a few lines; Phase 3 adds its own property |
| 10,000-pt item confuses macOS 26 overflow handling | L | M | Same value as Ice/Thaw on macOS 26; PRD spike confirmed off-screen items stay enumerable |

## Notes
- **Amendments made during implementation** (details in `.claude/PRPs/reports/phase-2-divider-report.md`):
  - Expanded length is 5,000 pt, not 10,000: macOS 26 capped a 10,000-pt request at a 5,016-pt window.
  - The ordering guard compares the stored "Preferred Position" values, not window frames: frames read `(0, 0, w, 0)` / `(0, -33, w, 33)` until macOS places the item a moment after launch. Seeding moved into `DividerController.init`, so `AppDelegate` just creates the divider before the chevron. The chevron no longer exposes `screenMinX`.
  - `applicationShouldHandleReopen` re-folds the divider: on a crowded bar, collapsing can make macOS hide the chevron itself.
  - Chevron glyph switched to the SF Symbol `chevron.down` (author's request); `icon(granted:) -> Icon` became `symbolName(granted:) -> String`.
