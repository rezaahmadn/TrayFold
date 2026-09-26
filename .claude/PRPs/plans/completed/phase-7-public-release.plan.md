# Plan: Phase 7 — Public release

## Summary
Make TrayFold something a stranger can find, understand, install and report bugs against, without adding a single line of Swift. The README is rewritten for a public audience (what it is, how it works, permissions, privacy and how to verify it, install from a release zip or from source, known limitations taken from the phase reports). A tag-triggered GitHub Actions workflow, copied from the author's Slice project, builds an ad-hoc signed Release `TrayFold.app` on a macOS 26 runner, zips it with `ditto` and attaches it to a GitHub Release with generated notes. Short issue templates ask for exactly what a menu bar bug needs (macOS version, Mac model/notch, which item, other menu bar managers, a TrayFold log snippet). The PRD records Phase 5 as complete and the open questions it answered. No tag is pushed and no release is created: the author decides when.

## User Story
As a notched-MacBook user who found TrayFold on GitHub,
I want a README that tells me honestly what it does, what it needs and how to install it, plus a downloadable build,
so that I can try it in a few minutes and report problems in a way the author can act on.

## Problem → Solution
README describes an "early development" project for the author; there are no releases and no issue templates → a public README with install/Gatekeeper steps and known limits, a one-command release pipeline (`git tag v0.1.0 && git push origin v0.1.0`), and bug/feature templates.

## Metadata
- **Complexity**: Low (docs and CI only)
- **Source PRD**: `.claude/PRPs/prds/trayfold.prd.md`
- **PRD Phase**: Phase 7 — Public release
- **Estimated Files**: 9 (README, release workflow, 3 issue-template files, CONTRIBUTING, PRD, plan, report) + optional screenshot
- **Execution**: one subagent in its own worktree, in parallel with Phase 6 (live icons). This phase must not touch Swift sources, tests or the Xcode project. It owns the PRD for this change.

---

## UX Design

### Before
```
github.com/rezaahmadn/TrayFold
  README: "Status: early development", build-from-source only, no limitations section
  Releases: none            Issues: blank form
```

### After
```
github.com/rezaahmadn/TrayFold
  README: what it is · how it works · permissions · privacy (+ how to verify) · install
          (release zip + Gatekeeper steps, or build from source) · known limitations · requirements · license
  Releases: v0.1.0 → TrayFold-0.1.0.zip  (once the author pushes the tag)
  Issues → New issue: [Bug report] [Feature request]  (blank issues off)
```

### Interaction Changes
| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Install | Clone + build | Download zip, or clone + build | Zip is ad-hoc signed, not notarized |
| First launch of a downloaded build | — | Blocked by Gatekeeper once; README explains Open Anyway / `xattr` | |
| Releasing | — | `git tag vX.Y.Z && git push origin vX.Y.Z` | Version inside the app comes from the tag |
| Reporting a bug | Blank issue | Form with macOS version, Mac model, item, other managers, log | |

---

## Mandatory Reading

| Priority | File | Why |
|---|---|---|
| P0 | `README.md` | Current wording of usage (keep the parts that are accurate) |
| P0 | `.claude/PRPs/reports/phase-5-reveal-and-press-report.md` | What works, what doesn't, measured numbers, limitations |
| P0 | `/Users/reza/Projects/Slice/.github/workflows/release.yml` | Workflow to mirror |
| P0 | `/Users/reza/Projects/Slice/README.md` | Download/Gatekeeper wording and style |
| P1 | `.claude/PRPs/reports/phase-2-divider-report.md`, `phase-4-tray-popup-report.md` | Crowded-bar behavior, Control Center items |
| P1 | `.github/workflows/ci.yml`, `project.yml`, `Config/Signing.xcconfig` | Runner, action versions, how signing is overridden |
| P1 | `TrayFold/StatusBarController.swift`, `AppDelegate.swift`, `TrayView.swift` | Exact menu titles and behavior the README describes |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| Opening an app from an unidentified developer | Apple support "Open a Mac app from an unknown developer" | macOS 15+ removed the right-click → Open bypass for unnotarized apps; the path is System Settings → Privacy & Security → **Open Anyway** after one blocked launch. Mention right-click → Open only as "older macOS" wording, or not at all |
| Release action | `softprops/action-gh-release` | `files:` glob + `generate_release_notes: true`; needs `permissions: contents: write` |
| Issue forms | GitHub docs "Syntax for issue forms" | YAML forms in `.github/ISSUE_TEMPLATE/*.yml`; `config.yml` with `blank_issues_enabled` |

```
KEY_INSIGHT: `ditto -c -k --keepParent` keeps extended attributes/resource forks and the code signature
intact, `zip -r` can break the signature. Unzipping a downloaded zip with Archive Utility propagates the
quarantine attribute to the app, which is why Gatekeeper blocks it once.
APPLIES_TO: release workflow, README install section.

GOTCHA: `workflow_dispatch` has no tag in `github.ref_name` (it's the branch name, e.g. "main"), so the
version must fall back to project.yml's MARKETING_VERSION and the zip must not be published as a release
unless the ref is a tag. Guard the publish step with `if: startsWith(github.ref, 'refs/tags/v')` and upload
the zip as a workflow artifact otherwise.
```

---

## Patterns to Mirror

### RELEASE_WORKFLOW (Slice)
```yaml
# SOURCE: /Users/reza/Projects/Slice/.github/workflows/release.yml
on:
  push:
    tags: ["v*"]
permissions:
  contents: write
jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - name: Build (Release, ad-hoc signed)
        run: |
          VERSION="${TAG#v}"
          xcodebuild … -configuration Release -derivedDataPath build \
            CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
            MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" build
      - name: Zip
        run: ditto -c -k --keepParent build/Build/Products/Release/Slice.app "Slice-${TAG#v}.zip"
      - uses: softprops/action-gh-release@v3
        with: { files: Slice-*.zip, generate_release_notes: true }
```

### README_DOWNLOAD (Slice)
```markdown
The app is ad-hoc signed (no Apple Developer account), so the first launch is blocked by Gatekeeper. Either:
1. Try to open it once, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**; or
2. In Terminal: `xattr -d com.apple.quarantine /Applications/Slice.app`
```

### CI_STYLE
```yaml
# SOURCE: .github/workflows/ci.yml — header comment explaining the job, macos-26, actions/checkout@v7,
# "Show Xcode" step, CODE_SIGN_IDENTITY=- on the command line.
```

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `README.md` | UPDATE (rewrite) | Public audience |
| `.github/workflows/release.yml` | CREATE | Tag → ad-hoc Release build → zip → GitHub Release |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | CREATE | Structured bug reports |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | CREATE | Keeps requests tied to the principles |
| `.github/ISSUE_TEMPLATE/config.yml` | CREATE | Disable blank issues |
| `CONTRIBUTING.md` | CREATE | Build/test commands, Swift 6, size budget, privacy rules |
| `.claude/PRPs/prds/trayfold.prd.md` | UPDATE | Phase 5 complete, open questions, Phase 7 in progress |
| `docs/tray.png` | CREATE (optional) | Real screenshot only if clean |
| `.claude/PRPs/reports/phase-7-public-release-report.md` | CREATE | Report |

## NOT Building

- Any Swift, test or `project.yml` change (Phase 6 is editing them in parallel).
- Notarization, Developer ID signing, Homebrew cask, website.
- Pushing a tag or creating a release.
- A detailed Live-icons section: Phase 6 supplies the wording; this phase leaves a short generic placeholder.
- Fabricated or mocked-up images.

---

## Step-by-Step Tasks

### Task 1: README rewrite
- **ACTION**: Rewrite `README.md`.
- **IMPLEMENT**: Sections: title + one-line pitch + status (pre-release 0.1.0); The problem; How it works (divider, ⌘-drag, left-click chevron = tray, right-click/⌃-click = menu, click an entry = real menu opens and the bar re-folds, Show Hidden Icons to rearrange, click outside re-folds, reopen re-folds); Permissions (Accessibility only, why; "Live icons (optional, off by default)" 2–3 generic sentences); Privacy (no network/telemetry/updater, how to verify); Install (release zip + Gatekeeper; build from source + `Scripts/setup-signing.sh`); Known limitations; Requirements; Contributing; License.
- **MIRROR**: README_DOWNLOAD.
- **GOTCHA**: Only claim what the phase reports measured. Right-click → Open no longer bypasses Gatekeeper on macOS 15+; lead with Open Anyway. `lsof -i -c TrayFold` ORs its filters and lists every process's sockets; the correct form is `lsof -a -i -c TrayFold`. TrayFold isn't sandboxed, so there is no entitlement to point at; the verification is "no networking code" + `lsof`.
- **VALIDATE**: Every claim traceable to a report or the source; links resolve (`LICENSE`, `CONTRIBUTING.md`, releases).

### Task 2: Release workflow
- **ACTION**: Create `.github/workflows/release.yml`.
- **IMPLEMENT**: RELEASE_WORKFLOW for TrayFold, plus `workflow_dispatch`; version from the tag, else `project.yml`'s `MARKETING_VERSION` with a `-dev` suffix; zip `TrayFold-<version>.zip`; `codesign --verify` step; publish only on a tag, else `actions/upload-artifact`.
- **MIRROR**: RELEASE_WORKFLOW, CI_STYLE.
- **GOTCHA**: See the `workflow_dispatch` gotcha above. Pass `CODE_SIGN_IDENTITY=-` on the command line so it overrides the xcconfig.
- **VALIDATE**: `actionlint .github/workflows/*.yml`; local dry-run of the build and zip commands (Task 5).

### Task 3: Issue templates + CONTRIBUTING
- **ACTION**: Create `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml` and `CONTRIBUTING.md`.
- **IMPLEMENT**: Bug form: macOS version, Mac model / notch, TrayFold version, which item (app), what happened vs expected, other menu bar managers running (Thaw/Ice/Bartender/Hidden Bar/none), log snippet from `/usr/bin/log show --predicate 'subsystem == "com.rezaahmadn.TrayFold"' --last 5m` (note: TrayFold logs bundle ids, not item titles; check before pasting). Feature form: problem, proposal, a checkbox acknowledging no network / no new default permissions. `config.yml`: `blank_issues_enabled: false`. CONTRIBUTING: build/test commands, XcodeGen only if `project.yml` changes, Swift 6 strict concurrency, zero warnings, size budget (< ~1,000 code lines, no dependencies), privacy rules.
- **GOTCHA**: Keep them short; long forms get abandoned.
- **VALIDATE**: YAML parses (`ruby -ryaml` or `python3 -c yaml`), `actionlint` doesn't cover these.

### Task 4: PRD update
- **ACTION**: Edit `.claude/PRPs/prds/trayfold.prd.md`.
- **IMPLEMENT**: Phase 5 row → complete with plan/report links; open questions 1, 3, 4 ticked with the Phase 5 answers; Phase 7 → in-progress with this plan's link; leave Phase 6's row alone.
- **VALIDATE**: `git diff` shows only those lines (plus the Gatekeeper open question annotated if the release zip answers it).

### Task 5: Dry-run, optional screenshot, report, PR
- **ACTION**: Run the workflow's build + zip locally into the scratchpad; optionally capture the tray; write the report; move the plan to `completed/`; commit, push, PR; wait for CI.
- **GOTCHA**: The screenshot needs the author's running TrayFold. Open the tray with a synthetic click on the chevron only (found by Accessibility), confirm the popup via AX/screenshot, crop tightly, and inspect for private content; skip if anything is doubtful or Phase 6 is relaunching the app.
- **VALIDATE**: Zip unzips to a `TrayFold.app` that passes `codesign --verify --deep --strict` and reports `CFBundleShortVersionString` from the tag.

---

## Testing Strategy

### Checks

| Check | Input | Expected Output | Edge Case? |
|---|---|---|---|
| actionlint | `.github/workflows/*.yml` | no findings | No |
| Release dry-run | `TAG=v0.1.0` | `TrayFold-0.1.0.zip`, app version 0.1.0, signature valid | No |
| Dispatch dry-run | `TAG=main` | version `0.1.0-dev`, no release step | Yes |
| Issue forms | YAML parse | valid | No |
| README links | relative links | files exist | No |

### Edge Cases Checklist
- [ ] `workflow_dispatch` on a branch (no tag)
- [ ] Tag that doesn't start with `v` (not triggered)
- [ ] Screenshot collides with Phase 6 relaunching TrayFold (skip image)

---

## Validation Commands

### Static Analysis
```bash
actionlint .github/workflows/ci.yml .github/workflows/release.yml
ruby -ryaml -e 'Dir[".github/ISSUE_TEMPLATE/*.yml"].each { |f| YAML.load_file(f); puts "ok #{f}" }'
```
EXPECT: no actionlint output; every form "ok".

### Release dry-run
```bash
TAG=v0.1.0; VERSION="${TAG#v}"
xcodebuild -project TrayFold.xcodeproj -scheme TrayFold -configuration Release -derivedDataPath "$SCRATCH/rel" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION=1 build
ditto -c -k --keepParent "$SCRATCH/rel/Build/Products/Release/TrayFold.app" "$SCRATCH/TrayFold-$VERSION.zip"
ditto -x -k "$SCRATCH/TrayFold-$VERSION.zip" "$SCRATCH/unzipped" && codesign --verify --deep --strict "$SCRATCH/unzipped/TrayFold.app"
```
EXPECT: `** BUILD SUCCEEDED **`, zip of a few MB, signature valid, version 0.1.0.

### CI
```bash
gh pr checks --watch
```
EXPECT: `test` green (the release workflow doesn't run on PRs).

---

## Acceptance Criteria
- [ ] README covers what/how/permissions/privacy/install/limitations/requirements/license, and every claim is backed by a report or the code
- [ ] `release.yml` passes actionlint and the local dry-run
- [ ] Issue templates + config parse; blank issues disabled
- [ ] PRD: Phase 5 complete, questions annotated, Phase 7 in-progress, Phase 6 untouched
- [ ] No Swift/test/project changes; CI green
- [ ] No tag pushed, no release created

## Completion Checklist
- [ ] Report written
- [ ] Plan moved to `completed/`, PRD link updated
- [ ] PR opened against `main`, CI green, not merged

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Gatekeeper wording outdated for macOS 26 | M | M | Lead with Open Anyway + `xattr`; right-click → Open mentioned as possibly not offered |
| Release zip built on the runner differs from the local dry-run (Xcode version) | L | L | Same runner image and command as CI, which is green |
| README drifts once Phase 6 lands | H | L | Live-icons section is deliberately generic; Phase 6 agent owns its wording |
| Screenshot leaks personal info | L | H | Crop to the popup + icons; inspect; skip if doubtful |

## Notes
- Version comes from the tag (Slice pattern). `project.yml` already says 0.1.0, so `v0.1.0` matches the source.
- **Amendment (during implementation): `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` in the release build.** The first dry-run showed the ad-hoc Release app carrying `get-task-allow`; the flag removes it (the release needs no entitlements).
- **Amendment: releases are not marked pre-release on GitHub**, because `releases/latest` (linked from the README) skips pre-releases. The README's status line says "pre-release" instead.
- **Amendment: the screenshot is the popup window alone** (`screencapture -o -l <id>`), because a region capture showed another app through the popup's translucent background.
