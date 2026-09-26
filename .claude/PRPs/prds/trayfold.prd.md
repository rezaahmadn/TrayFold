# TrayFold

## Problem Statement

On MacBooks with a notch, macOS 26 silently hides menu bar items that don't fit to the right of the notch. There is no overflow indicator, so once more than ~5 third-party items are running, the extras become invisible and unclickable: you can't see that the app is running or reach its menu. Existing fixes either expand hidden items back into the same cramped bar (Ice, Hidden Bar), cost money (Bartender), or require the Screen Recording permission with a persistent capture indicator (Ice Bar, Thaw, Bartender) that some users won't trust.

## Evidence

- Author's own machine (notched MacBook Pro, macOS 26.7): the 5th+ menu bar item disappears under the notch and cannot be clicked.
- Tried Ice: hides/shows items in place, which doesn't help when the bar itself has no room.
- Tried Thaw 2.0.1 (Ice fork with a separate popup bar): solved visibility, but (a) dragging the Battery item into the hidden section did not make it appear in the popup, and (b) the Screen Recording permission plus the always-on capture indicator felt untrustworthy.
- Spike (2026-09-25): the Accessibility API exposed all 16 menu bar items on the test machine, including Apple's Control Center items (Wi-Fi, Sound, Clock) with `AXPress` actions, and items pushed off-screen by a divider.
- Market: macOS 27 (released 2026-09-14) adds a native `»` overflow button, but it expands inline and the author is staying on macOS 26 for now. macOS 27 also broke Bartender, Ice, Hidden Bar and Barbee.
- Demand beyond the author: Assumption - needs validation (GitHub stars/issues after public release).

## Proposed Solution

A tiny, open-source, Accessibility-only menu bar tray modeled on the Windows system tray. TrayFold places its own divider in the menu bar; the user ⌘-drags items to the left of it (native macOS behavior), and the divider expands to push them off-screen. A single chevron opens a popup grid listing everything that is hidden, drawn with each app's own icon (or the item's text label when it has one). Clicking an entry briefly collapses the divider so the item is on-screen, presses it via Accessibility so its real menu opens, then folds it away again. Live menu bar icon images are an optional, off-by-default toggle, and only that toggle requests Screen Recording. This beats the alternatives on trust (one permission, no network, small auditable codebase) and fits the "larger space" the author wants, which inline expansion can't provide.

## Key Hypothesis

We believe an Accessibility-only tray (divider + popup grid + reveal-on-click) will make every menu bar item reachable on a notched Mac for users who distrust Screen Recording.
We'll know we're right when the author uninstalls Thaw and uses TrayFold daily for 2 weeks, with every hidden item opening its menu in 2 clicks or fewer.

## What We're NOT Building

- Automatic tray population in v1 - user chose manual, Windows-style placement; auto-detect of notch-hidden items is a later "Could".
- Themes, spacing, per-display profiles, schedules, hotkeys, search - that's Bartender/Thaw territory and adds code and surface area.
- Auto-updater or any network access - "no network at all" is a trust requirement; users rebuild or download releases manually.
- Notarized/Developer ID builds - requires a paid Apple Developer account; ad-hoc / self-signed builds only for now.
- Guaranteed macOS 27 support - macOS 27 rewrote the menu bar into a single window; nice to have, not required.
- Intel Macs / macOS < 26.

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| Hidden items reachable | 100% of the author's hidden third-party items open their real, visible menu | Manual check against every item placed in the tray |
| Clicks to reach a hidden item's menu | ≤ 2 (chevron, then item) | Manual |
| Permissions requested by default | Accessibility only | System Settings → Privacy & Security |
| Network access | None (no network code, no updater) | `lsof -a -i -c TrayFold` shows nothing; code review |
| Idle CPU / memory | ~0% CPU, < 40 MB RSS | Activity Monitor after 1 hour idle |
| Codebase size | < ~1,000 lines of Swift code (excluding comments and blank lines), zero third-party dependencies | code-line count of `TrayFold/`, `project.yml` |
| Daily use | 2 weeks without reverting to Thaw | Self-report |

## Open Questions

- [x] How to reliably detect that a pressed item's menu has closed so TrayFold can re-hide it (AX `AXMenuClosed` notification, polling the menu child, or re-hide on the next tray open)? *Answered (phase 5): poll at 5 Hz, only while a revealed item is open: the item's `AXSelected`, its `AXMenu` child having a size, or the app having more panel windows (`AXSystemDialog`/`AXDialog`) than before the press. `AXMenuClosed` alone isn't enough (Control Center, panels and popovers don't send it). ≤ 0.2 % CPU while open, 0 % otherwise.*
- [ ] Can the Battery item (and other Control Center items) be ⌘-dragged past a third-party divider on macOS 26? This was the failure seen in Thaw. *Partly answered (phase 2): Wi-Fi (Control Center) moved past TrayFold's divider and hid; Battery not tested (not in this Mac's bar).*
- [x] `AXPress` on a menu bar item blocks for ~1.5 s while the menu is open (spike returned `kAXErrorCannotComplete`, -25204). Confirm that running it off the main thread keeps the UI responsive. *Answered (phase 5): `AXPress` runs off the main actor with a 0.25 s per-element timeout; NSMenu apps return -25204 after exactly 0.25 s with the menu already open, and the UI stays responsive.*
- [x] Where does a revealed item land when the bar is crowded: under the notch (menu still visible, since menus drop below the bar) or off the left edge (menu invisible)? May need to collapse only part of the divider. *Phase 2 finding: fully collapsing on a crowded bar let macOS drop TrayFold's own chevron and divider out of sight (AX still reported them). Phase 4/5 must reveal only what's needed and re-fold automatically; reopening the app re-folds today. Phase 4 added an automatic re-fold on the first click outside the menu bar while collapsed.* *Answered (phase 5): partial collapse, just enough to bring the item on-screen (full collapse as a fallback); items already on-screen are pressed in place. Any on-screen position works, including under or left of the notch, because menus drop below the bar.*
- [x] How to keep a stable code-signing identity so macOS doesn't drop the Accessibility grant on every rebuild without a paid developer account? *Answered (phase 1): local self-signed certificate via `Scripts/setup-signing.sh`.*
- [ ] Does the divider approach survive macOS 27's single-window menu bar?
- [ ] Unsigned builds trigger Gatekeeper warnings for other users. Is "build from source" acceptable for a public audience? *Partly answered (phase 7): releases ship an ad-hoc signed zip built by CI on each `v*` tag; the README walks through Open Anyway / `xattr`, and build from source stays documented. Whether that's acceptable to users needs feedback after release.*

---

## Users & Context

**Primary User**
- **Who**: A notched-MacBook user on macOS 26 running 5+ menu bar apps (dev tools like Docker, sync clients, utilities), privacy-conscious, prefers small open-source tools.
- **Current behavior**: Loses track of items under the notch; tried Ice, Hidden Bar-style tools and Thaw; either no room or a Screen Recording permission they don't trust.
- **Trigger**: Needs to open a specific app's menu (VPN, Docker, sync status) or check whether something is running, and its icon is hidden.
- **Success state**: One chevron → grid of hidden items → click → that app's real menu appears.

**Job to Be Done**
When I have more menu bar apps running than fit beside the notch, I want to open one popup that shows all of them, so I can see what's running and click into any app's menu in 2 clicks.

**Non-Users**
- People on macOS 27 happy with the native `»` overflow button.
- Power users wanting full menu bar styling and automation (use Bartender or Thaw).
- Users on non-notched Macs or external displays only (little benefit).

---

## Solution Detail

### Core Capabilities (MoSCoW)

| Priority | Capability | Rationale |
|----------|------------|-----------|
| Must | Divider status item that expands to hide items to its left, collapses on demand | Creates the "tray" space using only public `NSStatusItem` API |
| Must | Popup grid (chevron click) of hidden items using app icon or item label | The Windows-tray experience; no Screen Recording needed |
| Must | Click-to-open: collapse divider → `AXPress` item → re-hide after menu closes | Spike proved `AXPress` on an off-screen item opens its menu off-screen |
| Must | Accessibility permission onboarding (check `AXIsProcessTrusted`, deep-link to Settings) | Nothing works without it |
| Should | Event-driven refresh (NSWorkspace launch/terminate notifications), no polling | "Light on resources" requirement |
| Should | Stable local signing so the Accessibility grant survives rebuilds | Otherwise the dev loop is painful |
| Could | Live icon toggle (off by default; requests Screen Recording) | User-requested optional feature |
| Could | Auto-include items hidden under the notch (via `NSScreen.auxiliaryTopRightArea`) | Covers items that overflow without manual placement |
| Could | Launch at login (`SMAppService`) | Convenience |
| Won't | Updater, telemetry, themes, profiles, hotkeys | Out of scope; trust and size |

### MVP Scope

Divider + chevron + popup grid (app icon / label) + reveal-and-press on click, Accessibility permission only, targeting macOS 26 on Apple silicon. Enough to replace Thaw on the author's machine.

### User Flow

1. First launch → TrayFold explains why Accessibility is needed → opens System Settings → user grants it.
2. User ⌘-drags items (e.g., Docker) left of the TrayFold divider → divider expands → items vanish from the bar.
3. User clicks the chevron → popup grid shows Docker, etc.
4. User clicks Docker → divider collapses briefly → Docker's own menu opens in its usual place → user picks an action → menu closes → divider re-expands.

---

## Technical Approach

**Feasibility**: HIGH

**Architecture Notes**
- **SwiftUI + AppKit, macOS 26, Swift 6 strict concurrency**, XcodeGen `project.yml`, `LSUIElement` (no Dock icon), ad-hoc signing. Mirrors the author's existing Slice menu bar app so the setup is proven on this machine.
- **Two own `NSStatusItem`s**: a chevron (opens popup) and a divider whose `length` toggles between ~0 and a large value (Thaw uses ~5000 pt) to push items to its left off-screen. Public API only.
- **Discovery via Accessibility**: for each running app, `AXUIElementCreateApplication(pid)` → `AXExtrasMenuBar` → children; read `AXPosition`/`AXSize`/`AXTitle`/`AXDescription`/`AXIdentifier`. Items whose x is left of the divider are "in the tray". Verified on the test machine for third-party and Control Center items.
- **Icons**: default is `NSRunningApplication.icon`, or the item's `AXTitle` when it has one (e.g., a timer showing "25:00"). Live images (optional toggle) via Screen Recording capture of the item's window. macOS 26 still has one window per item; macOS 27 does not.
- **Activation**: collapse divider → wait for item x ≥ 0 → `AXUIElementPerformAction(kAXPressAction)` on a background task (it blocks ~1.5 s while the menu tracks) → on menu close, re-expand divider.
- **No network entitlement, no dependencies.**

**Technical Risks**

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Pressing an off-screen item opens its menu off-screen (confirmed: menu at x = -4092) | H (confirmed) | Collapse divider before pressing; verify item x on-screen first |
| `AXPress` blocks while the menu is open | H (confirmed, ~1.5 s) | Run off the main actor; set `AXUIElementSetMessagingTimeout` |
| Accessibility grant invalidated on every ad-hoc rebuild | H | Local self-signed code-signing certificate; document in README |
| Conflict with another menu bar manager's divider (Thaw/Ice) | M | Detect known bundle IDs and warn; document "quit Thaw first" |
| Control Center items (Battery) can't be moved past divider | M | Test early; fallback: System Settings → Control Center → "Don't Show in Menu Bar" |
| Revealed item lands under the notch or off-screen when bar is crowded | M | Menus from under-notch items are still visible; partially collapse divider if needed |
| macOS 27 breaks the divider trick | M | Not required; the Accessibility discovery layer is isolated so the hide/reveal layer can be swapped |

---

## Implementation Phases

<!--
  STATUS: pending | in-progress | complete
  PARALLEL: phases that can run concurrently (e.g., "with 3" or "-")
  DEPENDS: phases that must complete first (e.g., "1, 2" or "-")
  PRP: link to generated plan file once created
-->

| # | Phase | Description | Status | Parallel | Depends | PRP Plan |
|---|-------|-------------|--------|----------|---------|----------|
| 1 | Project skeleton | XcodeGen project, menu-bar-only app, stable local signing, Accessibility onboarding | complete | - | - | [plan](../plans/completed/phase-1-project-skeleton.plan.md) · [report](../reports/phase-1-project-skeleton-report.md) |
| 2 | Divider | Own divider status item; expand/collapse; persists across relaunch | complete | with 3 | 1 | [plan](../plans/completed/phase-2-divider.plan.md) · [report](../reports/phase-2-divider-report.md) |
| 3 | Discovery | Accessibility enumeration of menu bar items + event-driven refresh | complete | with 2 | 1 | [plan](../plans/completed/phase-3-discovery.plan.md) · [report](../reports/phase-3-discovery-report.md) |
| 4 | Tray popup | Chevron + popup grid of hidden items (app icon / label) | complete | - | 2, 3 | [plan](../plans/completed/phase-4-tray-popup.plan.md) · [report](../reports/phase-4-tray-popup-report.md) |
| 5 | Reveal & press | Click → collapse → `AXPress` → re-hide on menu close | complete | - | 4 | [plan](../plans/completed/phase-5-reveal-and-press.plan.md) · [report](../reports/phase-5-reveal-and-press-report.md) |
| 6 | Live icons toggle | Optional Screen Recording capture of item images, off by default | pending | with 7 | 4 | - |
| 7 | Public release | README usage/build docs, GitHub release zip, issue templates | in-progress | with 6 | 5 | [plan](../plans/completed/phase-7-public-release.plan.md) |

### Phase Details

**Phase 1: Project skeleton**
- **Goal**: A buildable, menu-bar-only app that keeps its Accessibility grant across rebuilds.
- **Scope**: `project.yml`, `LSUIElement`, app entry, permission check + "Open Settings" flow, self-signed signing notes.
- **Success signal**: App shows a menu bar icon; `AXIsProcessTrusted()` is true after one grant and stays true after a rebuild.

**Phase 2: Divider**
- **Goal**: Hide items the user places left of the divider.
- **Scope**: Divider `NSStatusItem` with `autosaveName`, expand/collapse API, expanded by default.
- **Success signal**: ⌘-dragging Docker left of the divider makes it disappear; collapsing brings it back.

**Phase 3: Discovery**
- **Goal**: Know which items are hidden, without polling.
- **Scope**: Accessibility enumeration service, model (`app`, `title`, `frame`, `element`), refresh on app launch/terminate and on popup open.
- **Success signal**: Unit-testable list matches what the spike printed; items left of the divider flagged hidden.

**Phase 4: Tray popup**
- **Goal**: The Windows-tray UI.
- **Scope**: Chevron item → `NSPopover`/SwiftUI grid; app icon or label per item; empty state.
- **Success signal**: Popup shows exactly the hidden items within ~100 ms of clicking.

**Phase 5: Reveal & press**
- **Goal**: Clicking a tray entry opens that app's real menu, visibly.
- **Scope**: Collapse divider → wait for on-screen x → background `AXPress` → detect menu close → re-expand.
- **Success signal**: Every hidden item's menu opens on-screen in ≤ 2 clicks; bar returns to folded state afterwards.

**Phase 6: Live icons toggle**
- **Goal**: Optional true-to-life icons.
- **Scope**: Settings toggle, off by default; requests Screen Recording only when enabled; falls back to app icon on failure.
- **Success signal**: With toggle off, Screen Recording is never requested.

**Phase 7: Public release**
- **Goal**: Others can build and try it.
- **Scope**: README (why, permissions, build steps, Thaw conflict note), release zip, issue templates.
- **Success signal**: A fresh clone builds with documented steps.

### Parallelism Notes

Phases 2 and 3 are independent (one writes to the menu bar, the other only reads Accessibility state) and can run in parallel after the skeleton. Phase 6 and 7 can overlap once the core loop (5) works, since live icons are an isolated, optional rendering path.

**Execution:** implement with subagents (author's instruction). Run phases 2 and 3 as parallel subagents in separate worktrees after phase 1 lands, then phases 6 and 7 in parallel after phase 5. Each subagent gets one phase's PRP plan and returns a build-green, reviewed change.

---

## Decisions Log

| Decision | Choice | Alternatives | Rationale |
|----------|--------|--------------|-----------|
| Build vs adopt | Build | Thaw, Ice, Bartender, MenuBarShelf, upgrade to macOS 27 | Thaw worked but needs Screen Recording and mis-handled Battery; staying on macOS 26 |
| Discovery mechanism | Accessibility API | Window-list capture (Ice/Thaw) | No Screen Recording; spike showed all items incl. Control Center are exposed |
| Tray population | Manual (⌘-drag past divider) | Automatic notch detection | User preference, Windows-style; auto is a later "Could" |
| Icon rendering | App icon / item label; live icons optional | Live capture by default | Keeps default permission set to Accessibility only |
| Platform | macOS 26, Apple silicon | macOS 14+ / macOS 27 | Author's machine; 27 rewrote the menu bar |
| Project setup | XcodeGen + ad-hoc signing (as in Slice) | Raw Xcode project, SwiftPM app | Proven on this machine; diff-friendly |
| Network | None | Sparkle updater | Trust requirement |
| License | MIT | GPL-3.0, Apache-2.0 | Permissive; matches author's other projects |
| Visibility | Public on GitHub from the PRD stage | Publish after MVP | Author's choice |
| Implementation method | Subagents per phase | Single-thread implementation | Author's instruction; phases 2/3 and 6/7 parallelize |
| Size budget | Count code lines only (~660 after phase 4) | Count all lines incl. comments (1,065 after phase 4) | Author is new to Swift; explanatory comments are kept, not traded for budget |
| Popup activation | Popup never activates TrayFold; a global mouse monitor (only while open) closes it | `NSApp.activate()` + transient popover | Keeps focus in the user's app; no extra permission |

---

## Research Summary

**Market Context**
- [Ice](https://github.com/jordanbaird/Ice): free, open source; hides items in place; optional "Ice Bar" needs Screen Recording; buggy on macOS 26 ([#665](https://github.com/jordanbaird/Ice/issues/665)) and broken on 27.
- [Thaw](https://github.com/thaw-app/Thaw): GPL-3.0 Ice fork, actively maintained, popup bar; needs Screen Recording.
- Bartender 6: paid ($12+), closed source; macOS 27 support in beta.
- [MenuBarShelf](https://menubarshelf.talkiplanet.com/): popover list that activates original items; closest in spirit; minimal.
- [HiddenBarIcons](https://github.com/mekedron/HiddenBarIcons) (MIT, archived) used an Accessibility list of hidden items; [toe #178](https://github.com/theclifmeister/toe/issues/178) describes `AXExtrasMenuBar` + `AXPress` for a tray.
- macOS 27 "Golden Gate" (public 2026-09-14) adds a native inline `»` overflow button and renders the menu bar as one window, breaking window-based managers ([Badgeify](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/), [DevsReview](https://devsreviews.com/reviews/macos-27-menu-bar-managers/), [BTT forum](https://community.folivora.ai/t/macos-27-golden-gate-menu-bar-management-broken-solutions-ice-thaw-bartender-barbee-etc/47232)).
- Gap: no tool markets an Accessibility-only, no-Screen-Recording tray.

**Technical Context** (spike on macOS 26.7, 2026-09-25)
- `AXExtrasMenuBar` exposed 16 items across third-party apps and `com.apple.controlcenter` (Wi-Fi, Sound, Control Center, Clock have `AXIdentifier`s like `com.apple.menuextra.wifi`); all support `AXPress`.
- Items pushed off-screen by a divider remain enumerable (x ≈ -4000 behind a 5002-pt divider).
- `AXPress` on an off-screen item returned -25204 after ~1.5 s and opened its menu at x = -4092 (invisible): reveal-before-press is mandatory.
- Notch geometry available: `auxiliaryTopLeftArea` (0–665) / `auxiliaryTopRightArea` (850–1512) on a 1512-pt-wide display.

---

*Generated: 2026-09-25*
*Status: DRAFT - needs validation*
