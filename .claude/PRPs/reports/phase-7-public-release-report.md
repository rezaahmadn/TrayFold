# Implementation Report: Phase 7 — Public release

## Summary
TrayFold is ready for its first public release, with no Swift changes. The README is rewritten for people who find the repo: what it is, a short "how it works" (divider, ⌘-drag, left-click tray, right-click menu, click an entry to get the real menu, the re-fold safety nets), permissions (Accessibility only, with a short generic Live icons section for Phase 6 to fill in), privacy with two commands to verify it, install from a release zip (Gatekeeper steps) or from source, and known limitations taken from the phase reports. It includes one real screenshot of the tray popup. A new `release.yml` workflow, mirroring Slice, builds an ad-hoc signed Release app on a macOS 26 runner for every `v*` tag, zips it with `ditto` and attaches it to a GitHub Release with generated notes. Issue forms (bug, feature) and a short CONTRIBUTING.md are added. The PRD marks Phase 5 complete, records the open questions it answered, and marks Phase 7 in progress. **No tag was pushed and no release was created.**

## Assessment vs Reality

| Metric | Predicted (Plan) | Actual |
|---|---|---|
| Complexity | Low | Low |
| Files Changed | 9 + optional screenshot | 10 (README, CONTRIBUTING, release workflow, 3 issue-form files, screenshot, PRD, plan, report) |
| Swift / tests / project changes | 0 | 0 |

## Release dry-run (local, same commands as the workflow)

| Check | Result |
|---|---|
| Version step, tag `v0.1.0` / manual run on a branch | `0.1.0` / `0.1.0-dev` |
| Release build, `CODE_SIGN_IDENTITY=-` | `** BUILD SUCCEEDED **`, no warnings |
| `codesign --verify --deep --strict` before and after zip → unzip | valid, satisfies its Designated Requirement |
| Zip | `TrayFold-0.1.0.zip`, **550 KB** (app 1.2 MB unzipped, universal arm64 + x86_64) |
| Info.plist | `CFBundleShortVersionString` 0.1.0 (from the tag), `CFBundleVersion` = run number |
| Signature | `Signature=adhoc`, `TeamIdentifier=not set`, identifier `com.rezaahmadn.TrayFold` |
| Entitlements | none (see Deviations) |
| Gatekeeper (`spctl -a -t exec`) | `rejected`, as expected for ad-hoc; README covers Open Anyway / `xattr` |
| `actionlint` (ci.yml + release.yml) | clean |
| Issue forms YAML | all three parse |

## Screenshot
`docs/tray.png` (532 × 204 px, 36 KB): the tray popup window alone, captured with `screencapture -o -l <window id>`, so there is no background and nothing from other apps. It shows the three items folded away on the author's Mac: WPS Office, Bitwarden, 1Password (app icons and names only). How: the chevron was found through TrayFold's own `AXExtrasMenuBar` (description "TrayFold", x 949), clicked once with a synthetic left-click to open the popup, the popup's window confirmed with `CGWindowListCopyWindowInfo` (TrayFold-owned, layer 25, 266 × 102 pt), captured, then the chevron was clicked again to close it (window gone, divider still expanded at 5002 pt). No click landed outside TrayFold's chevron. A wider region capture was discarded because Chrome's toolbar showed through the popup's translucent background. TrayFold (the main checkout's Debug build, pid 98514) was not restarted.

## Tasks Completed

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | README rewrite | [done] Complete | Claims checked against the code and phase reports |
| 2 | Release workflow | [done] Complete | Deviations: `workflow_dispatch` dry run, no injected entitlements |
| 3 | Issue templates + CONTRIBUTING | [done] Complete | |
| 4 | PRD update | [done] Complete | Also annotated the Gatekeeper question and fixed the `lsof` metric |
| 5 | Dry-run, screenshot, report, PR | [done] Complete | |

## Validation Results

| Level | Status | Notes |
|---|---|---|
| Static analysis | [done] Pass | `actionlint` clean; issue forms parse |
| Release dry-run | [done] Pass | Table above |
| README claims | [done] Pass | Privacy grep prints nothing on `TrayFold/*.swift`; `lsof -a -i -c TrayFold` prints nothing with TrayFold running; relative links (`LICENSE`, `CONTRIBUTING.md`, `docs/tray.png`) exist |
| CI | see PR | Only `ci.yml` runs on PRs; `release.yml` runs on tags / manual dispatch |

## Files Changed

| File | Action |
|---|---|
| `README.md` | REWRITTEN |
| `CONTRIBUTING.md` | CREATED |
| `.github/workflows/release.yml` | CREATED |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | CREATED |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | CREATED |
| `.github/ISSUE_TEMPLATE/config.yml` | CREATED (blank issues off) |
| `docs/tray.png` | CREATED |
| `.claude/PRPs/prds/trayfold.prd.md` | UPDATED |
| `.claude/PRPs/plans/completed/phase-7-public-release.plan.md` | CREATED |
| `.claude/PRPs/reports/phase-7-public-release-report.md` | CREATED |

## Deviations from Plan
- **`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` in the release build.** The first dry-run showed that an ad-hoc ("Sign to Run Locally") Release build still gets `com.apple.security.get-task-allow`, which lets other processes attach to the app. For an app that holds the Accessibility permission that is worth avoiding, and the release needs no entitlements. With the flag the app has none; the build and signature checks are unchanged. Slice's workflow has the same gap.
- **`workflow_dispatch` is a dry run.** A manual run on a branch builds `TrayFold-0.1.0-dev.zip` and keeps it as a workflow artifact (`actions/upload-artifact@v7`) instead of publishing a release; publishing only happens for tags.
- **A signature check step** (`codesign --verify --deep --strict`) and a SHA-256 line were added before publishing.
- **Not a pre-release on GitHub.** Marking `v0.x` releases as pre-releases would make the README's `releases/latest` link skip them, so the release is a normal one and the README says "pre-release (0.1.0)" instead.
- **Right-click → Open** is mentioned only as no longer working (macOS 15+ removed that Gatekeeper shortcut); the README leads with Open Anyway and `xattr -dr`.

## Issues Encountered
- Worktree isolation refused compound shell commands (loops over variables, heredoc + `cd` + a second command); split into plain commands and scratch scripts. Nothing was denied.
- The phase 5 report's measurements and limits are for one Mac; the README says so instead of generalising.

## Observations for the PRD (seen, not guessed)
- The Release build is universal (arm64 + x86_64) by default; only arm64 has been tested.
- Hardened Runtime is off (`ENABLE_HARDENED_RUNTIME: NO` in `project.yml`). Turning it on for releases would also block `DYLD_INSERT_LIBRARIES` injection into an app holding Accessibility. Not done here (project change, needs a runtime check); a small follow-up.
- Ad-hoc signatures are tied to the build's code hash, so every downloaded release is a new app to TCC: users re-allow Accessibility after updating (documented in the README).

## Publishing v0.1.0 (for the author, after this PR and Phase 6 are merged)

```sh
cd /Users/reza/Projects/TrayFold
git checkout main && git pull
git tag v0.1.0
git push origin v0.1.0
gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

The workflow creates the GitHub Release `v0.1.0` with `TrayFold-0.1.0.zip` and generated notes. Optional rehearsal first: `gh workflow run release.yml --ref main` (builds `TrayFold-0.1.0-dev.zip` as an artifact, publishes nothing).

## Next Steps
- [ ] Review the pull request (CI must be green)
- [ ] Coordinating agent: mark Phase 7 complete in the PRD after merge
- [ ] Phase 6 agent: replace the generic "Live icons" README section with the exact wording
- [ ] Author: push the `v0.1.0` tag when ready
- [ ] Follow-up: Hardened Runtime for release builds
