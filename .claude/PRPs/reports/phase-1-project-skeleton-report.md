# Implementation Report: Phase 1 — Project Skeleton

## Summary
TrayFold is now a buildable, menu-bar-only macOS 26 app. It checks the Accessibility permission, prompts once, links to the Settings pane, and updates its menu bar icon live when the permission changes. Builds on the author's Mac are signed with a self-signed local certificate, so the Accessibility grant survives rebuilds. Added at the author's request during implementation: an app icon ("notch + tray") and a matching template menu bar glyph.

## Assessment vs Reality

| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | Medium | Medium |
| Confidence | 8/10 | Met; 3 small fixes needed (see Deviations) |
| Files Changed | ~15 | 33 files incl. generated project and 12 icon PNGs |
| Swift (app) | ~200 lines | 197 lines |
| Unit tests | 5 | 6 |

## Tasks Completed

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Check tools | [done] Complete | XcodeGen 2.46.0, Xcode 26.2 |
| 2 | XcodeGen spec + signing config | [done] Complete | `$(TRAYFOLD_SIGN_IDENTITY)` resolves from xcconfig as planned |
| 3 | App entry + delegate | [done] Complete | Deviated: early return when running as a test host |
| 4 | Local signing script | [done] Complete | Run by the author; certificate trusted |
| 5 | `AccessibilityPermission` | [done] Complete | |
| 6 | `StatusBarController` | [done] Complete | Deviated: custom glyph instead of `chevron.left` |
| 7 | Unit tests | [done] Complete | +1 test for the template glyph |
| 8 | Dev loop script | [done] Complete | Deviated: signer display fixed twice |
| 9 | CI workflow | [done] Complete | Runs on push/PR |
| 10 | Generate project, README, PRD | [done] Complete | |
| + | App icon + menu bar glyph | [done] Complete | Added at author's request (was Phase 7) |

## Validation Results

| Level | Status | Notes |
|---|---|---|
| Static Analysis (build) | [done] Pass | 0 errors, 0 warnings, Swift 6 strict concurrency |
| Unit Tests | [done] Pass | `✔ Test run with 6 tests in 2 suites passed` |
| Build | [done] Pass | `AppIcon.icns` + `Assets.car` in bundle |
| Integration (runtime) | [done] Pass | `ApplicationType = UIElement`; no network sockets |
| Signing | [done] Pass | Designated requirement: `certificate leaf = H"8fb3…"` (no cdhash) |
| Permission survives rebuild | [done] Pass | cdhash `7b7f…` → `992e…` (build number changed), log: `Accessibility allowed: true` |
| Live permission update | [done] Pass | Log: `Accessibility allowed changed to true` without relaunch |

## Files Changed

| File | Action |
|---|---|
| `project.yml` | CREATED |
| `Config/Signing.xcconfig` | CREATED |
| `TrayFold/TrayFoldApp.swift` | CREATED |
| `TrayFold/AppDelegate.swift` | CREATED |
| `TrayFold/AccessibilityPermission.swift` | CREATED |
| `TrayFold/StatusBarController.swift` | CREATED |
| `TrayFold/Resources/Assets.xcassets/**` | CREATED (AppIcon ×10 PNG, MenuBarIcon ×2 PNG, 3 Contents.json) |
| `TrayFold/Info.plist`, `TrayFold.xcodeproj/**` | GENERATED |
| `TrayFoldTests/AccessibilityPermissionTests.swift` | CREATED |
| `TrayFoldTests/StatusBarControllerTests.swift` | CREATED |
| `Design/AppIcon.svg`, `Design/MenuBarIcon.svg` | CREATED |
| `Scripts/setup-signing.sh`, `Scripts/run.sh` | CREATED |
| `Scripts/render-icon.swift`, `Scripts/render-icons.sh` | CREATED |
| `.github/workflows/ci.yml` | CREATED |
| `.gitignore`, `README.md` | UPDATED |
| `.claude/PRPs/prds/trayfold.prd.md` | UPDATED (phase 1 complete) |

## Deviations from Plan
- **Icons moved into Phase 1** (author: "don't forget to create the icon for it"). App icon and menu bar glyph rendered from SVG like Slice. The menu bar shows the glyph when allowed and `exclamationmark.triangle` when not. `symbolName(granted:)` became `icon(granted:) -> Icon` (`.asset` / `.symbol`).
- **Test-host guard**: `xcodebuild test` launched the real app (menu bar item + Accessibility prompt) because tests run inside it. `AppDelegate` now returns early when `XCTestConfigurationFilePath` is set.
- **`Scripts/run.sh` signer display**: (1) `|| echo ad-hoc` never fired, so `${SIGNER:-ad-hoc}` is used; (2) `codesign -dv` has no `Authority=` line, so `-dvv` is needed; (3) awk's early `exit` caused SIGPIPE, which `pipefail` turned into a silent abort, so awk now reads all input.
- **Plan validation command**: `log show` → `/usr/bin/log show` (in zsh, `log` is a built-in command).

## Issues Encountered
- An Accessibility grant given to an ad-hoc build stopped applying after rebuild, as the plan predicted. Resolved by running `setup-signing.sh`, then `tccutil reset Accessibility com.rezaahmadn.TrayFold` and one final grant.
- One transient `Command CodeSign failed` during a test run in the icon work, most likely while the certificate was imported but not yet trusted (the signing script ran concurrently). Not reproduced in 5+ later runs.
- `touch` on a source file produced a byte-identical binary (same cdhash), so the persistence test used `CURRENT_PROJECT_VERSION=2` to force a real change.

## Tests Written

| Test File | Tests | Coverage |
|---|---|---|
| `TrayFoldTests/AccessibilityPermissionTests.swift` | 4 | Initial state, refresh, change-only callbacks incl. revoke, status titles |
| `TrayFoldTests/StatusBarControllerTests.swift` | 2 | Icon choice per permission state, glyph asset ships as template |

## Next Steps
- [ ] Review the pull request (CI must be green)
- [ ] `/prp-plan .claude/PRPs/prds/trayfold.prd.md` → Phases 2 (Divider) and 3 (Discovery), which can run as parallel subagents
