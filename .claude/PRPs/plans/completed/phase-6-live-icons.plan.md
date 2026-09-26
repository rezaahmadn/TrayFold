# Plan: Phase 6 — Live icons toggle

## Summary
An off-by-default "Show Live Icons" item in the chevron's right-click menu. When it is on and Screen Recording is allowed, tray entries show the item's real menu bar image (Docker's status whale, Slice's "25:00") instead of the app icon; on any failure the app icon stays. A new, isolated `LiveIcons` class owns the toggle (in `UserDefaults`), the permission check and a per-item image cache; every system call (permission check, permission request, live Accessibility frame, ScreenCaptureKit capture) comes in as an injected closure, and **none of them is called while the toggle is off**. The spike found that macOS 26 can only capture a status item while it is inside the screen, and folded items sit at x ≈ -4100, so images are captured at the two moments an item in the tray is on-screen anyway: when the tray opens (items under the notch, or all items while "Show Hidden Icons" is on) and while TrayFold has revealed an item to open its menu. Captures are one-shot, bounded, and triggered only by the user's click.

## User Story
As a notched-MacBook user who doesn't mind granting Screen Recording,
I want the tray to show each item's real menu bar image,
so that I can read status (Docker's state, a timer) at a glance, like in the menu bar itself.

## Problem → Solution
Tray entries show the owning app's generic icon → with the toggle on, entries show the item's own image once TrayFold has seen it on-screen; with the toggle off nothing changes and Screen Recording is never requested or used.

## Metadata
- **Complexity**: Medium (permission flow and capture behaviour of macOS, small code)
- **Source PRD**: `.claude/PRPs/prds/trayfold.prd.md`
- **PRD Phase**: Phase 6 — Live icons toggle
- **Estimated Files**: 9 (1 new source, 1 new test file, 5 updated sources, regenerated project, report)
- **Execution**: one subagent in its own worktree, in parallel with Phase 7 (README, release, PRD are Phase 7's: not touched here).

---

## Spike evidence (author's Mac, macOS 26.7, Xcode 26.2 / SDK 26.2, 1512-pt screen, notch 665…850)

Scratch Swift tools run from the agent's shell, which already holds Screen Recording (`CGPreflightScreenCaptureAccess()` = true). TrayFold itself has **no** Screen Recording grant; nothing here created one. Bar during the spike: WPS, Bitwarden, 1Password folded (AX x -4171, -4137, -4105); Docker 974; Slice "25:00" 1019; WattMeter 1095; Wi-Fi 1226, Sound 1264, Control Center 1302, Clock 1344.

### 1. Capture API and finding the item's window
- `CGWindowListCreateImage` is **obsoleted** in the SDK: `error: 'CGWindowListCreateImage' is unavailable in macOS: Please use ScreenCaptureKit instead … obsoleted in macOS 15.0`. Called anyway through `dlsym` (evidence only), it returned `nil` for the folded items too.
- ScreenCaptureKit works: `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` (45–50 ms, ~160 windows) → `SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow:), configuration:)`.
- **Every status item window belongs to Control Center (pid 632)** on macOS 26, including third-party ones and TrayFold's own (window titles `Item-0`, `TrayFoldDivider`, `TrayFoldChevron`, `WiFi`, `Clock`, a UUID for 1Password). Matching by owning pid is therefore impossible; **match by position**: layer 25 (`kCGStatusWindowLevel`), and the window that contains the AX item's centre. Offsets measured: third-party window = AX frame inset by 1 pt (Docker AX 974 w47 → window 975 w45); Control Center window = AX frame widened by 8 pt each side (Wi-Fi AX 1226 w22 → 1218 w38); every window y 0, height 33. The expanded divider's window (5,016 pt) never contains a folded item's centre; pick the narrowest match anyway.
- Hidden-but-on-display windows capture fine (Battery: `isOnScreen` false at x 1190, captured "100 %" + battery glyph).

### 2. Off-screen (folded) items
- Windows left of the screen (the three folded items) **fail**: `SCStreamErrorDomain -3811 "Failed to start stream due to audio/video capture failure"` after 30–85 ms. The obsoleted CG API returns nil for them as well. There is no public way to capture a folded item.
- The selection highlight is not part of the item's window: Docker captured while its menu was open, and at 0/50/100/200/400 ms after closing it, gives identical images. So capturing while TrayFold has revealed an item to open its menu is safe.
- ⇒ **Cheapest honest approach**: capture an item only when its live AX frame is inside the screen, cache the image per item, fall back to the app icon until one exists. Moments when a tray item is on-screen without extra work: (a) the tray opens while it is under the notch or while "Show Hidden Icons" is on; (b) a reveal session has brought it on-screen to open its menu. Rejected: briefly shrinking the divider on tray open (the whole bar would flicker).

### 3. Capture indicator (what the user sees)
- Watched `CGWindowListCopyWindowInfo` (reading it captures nothing) for WindowServer windows named `StatusIndicator`, and took screenshots.
- A single one-shot capture shows a **small purple dot right of the Control Center icon** in the menu bar (two `StatusIndicator` windows at x ≈ 1312). It appeared ~0.2 s after the capture started and stayed **3.5–3.9 s** (measured 3.1 s after a 13-capture burst ended, 3.85 s after one capture). A burst shares one dot. No other UI: no alert, no banner.
- **Only real capture calls raise it**: `SCShareableContent` alone does not; a capture that **fails** (off-screen window) **does**. ⇒ never attempt a capture for an item whose frame isn't on-screen.
- macOS's own `screencapture` raises the same dot.

### 4. Permission flow
- `CGPreflightScreenCaptureAccess()` only reads the state (no prompt); `CGRequestScreenCaptureAccess()` shows the system prompt (the first time only) and adds the app, switched off, to System Settings → Privacy & Security → Screen & System Audio Recording. Not run against TrayFold during the spike (it would create a TCC entry and a dialog on the author's screen); verified at runtime in Task 6 only as far as "request shown", and listed for the author.
- After the switch is flipped, System Settings offers "Quit & Reopen"; whether `CGPreflightScreenCaptureAccess()` turns true without relaunching can't be tested without the author. The menu says "then reopen TrayFold" while it's still false.
- macOS 15+ asks again **monthly** for apps that capture outside the system picker ("Allow For One Month" / "Open System Settings") ([9to5Mac](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/), [TidBITS](https://tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts/)). Not reproducible in a spike; documented for the author.

### 5. Images
- Glyphs on a **transparent** background; pixel size = window size × 2 on Retina (Slice 152 × 66 px for a 76 × 33-pt window). `SCContentFilter.pointPixelScale` / `contentRect` give the scale and size.
- Glyphs are tinted for the **menu bar's** appearance, which follows the wallpaper, not the system: the author runs Dark mode, but the bar draws black glyphs. A status item button's `effectiveAppearance` is `NSAppearanceNameVibrantLight` while `NSApp.effectiveAppearance` is `DarkAqua` (scratch app). A dark popup would show black glyphs on black. ⇒ while live icons are on, the popover takes the chevron button's appearance, so it looks like a piece of the menu bar and the images keep their contrast.
- Latency: first capture 85–90 ms (connection setup), then **30–40 ms per item**; `SCShareableContent` 45–50 ms; 13 windows in 0.48 s sequentially. The popup opens with app icons (or cached images) at once, and swaps live images in when they arrive.

---

## UX Design

### Before
```
Right-click ⌄ → Accessibility: Allowed / Show Hidden Icons / Quit.   Tray shows app icons.
```

### After
```
Right-click ⌄ → … / Show Hidden Icons / ☐ Show Live Icons  (subtitle: "Real menu bar images; needs Screen Recording") / Quit
Turn it on → macOS's Screen Recording prompt (first time) → subtitle "Allow Screen Recording, then reopen TrayFold"
             + "Allow Screen Recording…" item (opens the Settings pane)
Once allowed → ☑ Show Live Icons ("Captured while an icon is on-screen")
  Tray: app icons first; an item's real image once TrayFold has seen it on-screen
  (opened from the tray once, under the notch, or tray opened while icons are shown).
  macOS shows a purple dot by Control Center for ~3.5 s after each capture.
Turn it off → app icons again, cache dropped, no capture calls at all.
```

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Right-click menu | — | "Show Live Icons" checkbox + subtitle; "Allow Screen Recording…" while needed | Off by default |
| Tray open (toggle on, allowed) | App icons | Cached live images; on-screen tray items captured and swapped in | Nothing captured when no tray item is on-screen (the usual case) |
| Tray entry click (toggle on, allowed) | Reveal → press | Same, plus one capture of that item while its menu is open | Purple dot ~3.5 s |
| Toggle off | — | Zero ScreenCaptureKit / CG capture calls, no permission check or prompt | Unit-tested |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `TrayFold/TrayController.swift` | 35-87 | `toggle`, `activate`, `render` — where images are asked for and handed to the view |
| P0 | `TrayFold/TrayView.swift` | 55-88 | `TrayCell.icon` — the fallback path |
| P0 | `TrayFold/StatusBarController.swift` | 18-100 | Menu items, subtitle, `update()`, `menuWillOpen` |
| P0 | `TrayFold/RevealController.swift` | 103-128 | `run()`: the moment the item is on-screen with its menu open |
| P1 | `TrayFold/AccessibilityPermission.swift` | all | Permission + settings-URL pattern to mirror |
| P1 | `TrayFold/MenuBarLayout.swift` | 83-86 | `isOnScreen` reused as the capture guard |
| P1 | `TrayFoldTests/MenuBarItemStoreTests.swift`, `TrayControllerTests.swift` | fakes | Fake system class, `item(_:x:)` helper |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| `SCScreenshotManager.captureImage(contentFilter:configuration:)` | ScreenCaptureKit (macOS 14+) | One-shot capture; filter `init(desktopIndependentWindow:)` captures one window |
| `SCContentFilter.pointPixelScale`, `contentRect` | ScreenCaptureKit (macOS 14+) | Pixel size for the configuration |
| `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` | CoreGraphics (macOS 10.15+) | Check without prompting / prompt once |
| Monthly re-prompt | 9to5Mac, TidBITS (above) | macOS 15+ re-confirms capture permission monthly |

---

## Patterns to Mirror
- **INJECTED_SYSTEM** (`RevealController.System`, `MenuBarItemStore.init`): closures for every system call, `@Sendable` for those that run off the main actor.
- **BACKGROUND_AX** (`RevealController.background`): `Task.detached` for blocking Accessibility reads.
- **PERMISSION** (`AccessibilityPermission`): `settingsURL`, `openSettings()`, a pure `statusTitle`-style helper for menu text.
- **PURE_STATIC_HELPER** (`MenuBarLayout`): window matching as a pure function of rectangles.
- **LOGGING**: `Logger(subsystem: "com.rezaahmadn.TrayFold", category: "LiveIcons")`, bundle ids only.
- **TEST_FAKES**: `TrayControllerTests.item(_:x:)`; a `final class Fake…` with counters.

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `TrayFold/LiveIcons.swift` | CREATE | Toggle, permission, cache, window matching, live ScreenCaptureKit capture |
| `TrayFold/TrayController.swift` | UPDATE | Capture on-screen tray items on open; popover appearance; pass images to the view |
| `TrayFold/TrayView.swift` | UPDATE | Live image when available, app icon otherwise |
| `TrayFold/StatusBarController.swift` | UPDATE | "Show Live Icons" checkbox, subtitle, "Allow Screen Recording…" |
| `TrayFold/RevealController.swift` | UPDATE | `onMenuOpen` callback (item on-screen with its menu open) |
| `TrayFold/AppDelegate.swift` | UPDATE | Create `LiveIcons`, wire the reveal callback |
| `TrayFoldTests/LiveIconsTests.swift` | CREATE | Default off, off ⇒ nothing called, fallback, window matching, cache |
| `TrayFold.xcodeproj/project.pbxproj` | REGENERATE | `xcodegen generate` |

## NOT Building
- Settings window, per-item overrides, launch at login, README / release / PRD edits (Phase 7).
- Capturing folded (off-screen) items: impossible on macOS 26 (spike §2); no bar flicker to fake it.
- Periodic refresh, timers, or capture while nothing was clicked.
- `SCStream` (continuous capture) — one-shot screenshots only.
- `project.yml` changes: none needed (ScreenCaptureKit links automatically through `import`).

---

## Step-by-Step Tasks

### Task 1: Local signing for this worktree
- **ACTION**: copy `Config/Signing.local.xcconfig` from the main checkout. **GOTCHA**: git-ignored; never commit.

### Task 2: `LiveIcons` (new)
- **IMPLEMENT**:
  - `static let defaultsKey = "ShowLiveIcons"`; `isEnabled` reads `UserDefaults` (`bool(forKey:)` → false when unset).
  - `struct System { isAllowed: () -> Bool; requestAccess: () -> Void; frame: @Sendable (MenuBarItem) -> CGRect?; capture: @Sendable ([CGRect]) async -> [CGImage?] }` + `static let live`.
  - `isActive = isEnabled && system.isAllowed()` (short-circuit: the check isn't even made while off).
  - `setEnabled(_:)`: store; on → request access if not allowed; off → drop the cache.
  - `images: [String: NSImage]` — the cache while active, else empty.
  - `capture(_ items:, screen:) async -> Bool`: guard active; read live frames in the background; keep on-screen ones; nothing on-screen → return (no capture, no indicator); capture; store non-nil results; return whether anything was stored.
  - Pure `statusWindow(containing:among:) -> Int?`: index of the narrowest window containing the item's centre.
  - `static func captureMenuBar(_ frames:) async -> [CGImage?]`: one `SCShareableContent`, windows at `kCGStatusWindowLevel`, match, one `SCScreenshotManager` capture each; any error → nil.
  - `settingsURL` + `openSettings()`, pure `subtitle(enabled:allowed:)`.
- **GOTCHA**: `nonisolated` for the capture so it runs off the main actor; never call `SCShareableContent` while off (it would prompt).

### Task 3: Tray + view
- **IMPLEMENT**: `TrayController` takes `LiveIcons`; `render()` passes `liveIcons.images`; `toggle` sets `popover.appearance` to the chevron's `effectiveAppearance` while active (nil otherwise) and, after the store refresh, `if await liveIcons.capture(folded, screen:) { render() }`. `TrayCell` shows the live image (`aspectRatio(.fit)`, max 64 × 32) else the app icon.

### Task 4: Reveal hook
- **IMPLEMENT**: `RevealController.onMenuOpen: ((MenuBarItem) -> Void)?`, called when the state becomes `.menuOpen`; `AppDelegate` sets it to `Task { await liveIcons.capture([item], screen:) }`.
- **GOTCHA**: not in `System` (keeps phase 5 tests untouched); the callback does nothing while live icons are off.

### Task 5: Menu
- **IMPLEMENT**: "Show Live Icons" (`state` on/off, subtitle), "Allow Screen Recording…" (hidden unless on and not allowed); both refreshed in `update()` (runs on `menuWillOpen`).

### Task 6: Tests, generate, runtime, measure, report, PR
- **VALIDATE**: commands below; runtime: toggle off → no ScreenCaptureKit use, no dot; toggle on → request shown (TrayFold isn't allowed; granted path verified by the scratch tools only); toggle back off; relaunch author's copy.

---

## Testing Strategy

### Unit Tests
| Test | Input | Expected |
|---|---|---|
| default off | fresh defaults suite | `isEnabled` false, `images` empty |
| off ⇒ nothing called | toggle off, `capture` on on-screen items | capture, frame, isAllowed, requestAccess counters all 0 |
| turning on requests access | not allowed | `requestAccess` once; `isActive` false; nothing captured |
| on + allowed captures on-screen items only | one on-screen, one at x -4100 | capture called with the on-screen frame only; image cached under its id |
| nothing on-screen ⇒ no capture | all folded | capture never called (no indicator) |
| failure ⇒ fallback | capture returns nil | no image; earlier cached image kept |
| turning off drops the cache | on, capture, off | `images` empty |
| window matching | spike rectangles | Docker → its window; Wi-Fi → its wider window; divider never chosen; nothing → nil |
| subtitle texts | enabled/allowed combos | three strings |

### Edge Cases Checklist
- [ ] Permission revoked while on → `isActive` false → app icons, no capture attempts
- [ ] App quits → its id disappears from the tray; cache entry unused
- [ ] Item never on-screen → app icon forever (documented)
- [ ] Capture during a fold-back (item slides off) → capture fails → old image kept

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
defaults read com.rezaahmadn.TrayFold ShowLiveIcons      # absent / 0 by default
/usr/bin/log show --last 2m --info --predicate 'subsystem == "com.rezaahmadn.TrayFold"' --style compact
```

### Size
Code lines (no comments / blank lines) of `TrayFold/*.swift`: ≲ 956 (≤ ~100 new).

---

## Acceptance Criteria
- [ ] Toggle off by default; with it off, no capture API or permission API is called (unit test + code review: only `LiveIcons` imports ScreenCaptureKit)
- [ ] Turning it on requests Screen Recording; denied → app icons, menu shows what's needed
- [ ] Allowed → live image for items TrayFold has seen on-screen; app icon otherwise
- [ ] Popup opens as fast as before (images swap in later)
- [ ] Zero warnings; all tests pass locally and in CI

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Folded items can't be captured | H (measured) | M | Capture while revealed / on-screen, cache; documented honestly |
| Purple dot every time an item is opened from the tray | H (measured) | M | Only with the toggle on; documented in the menu subtitle / README |
| Preflight stays false until relaunch after granting | M | L | Menu says "then reopen TrayFold" |
| Monthly macOS re-prompt | H (macOS 15+) | L | Documented; the user can say no and TrayFold falls back to app icons |
| macOS 27 has one menu bar window → no per-item windows | H (on 27) | L | Match fails → nil → app icon |

## Notes
- Spike tools live in the session scratchpad (not committed).
- The PRP scope said "no background capturing while the popup is closed". Captures during a reveal session happen while the popup is closed, but only as the direct result of the user's tray click (one item, one shot, no timer). Without it, folded items could essentially never be captured (spike §2), so the feature would show app icons in practice. Called out in the report for the author.
- **Amendments (implementation):** `openSettings()` dropped (the menu opens `LiveIcons.settingsURL` itself); `TrayView` uses one `Image` for both kinds (`aspectRatio(.fit)` in 64 × 32: app icons stay 32 × 32); `render()` returns the items it listed instead of a second helper. Code size landed at +125 lines (981 total), over the ≤ ~100 phase target; see the report.
