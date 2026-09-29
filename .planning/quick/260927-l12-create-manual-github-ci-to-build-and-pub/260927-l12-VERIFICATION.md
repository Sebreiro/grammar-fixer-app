---
phase: 260927-l12-create-manual-github-ci-to-build-and-pub
verified: 2026-09-27T23:48:14Z
status: human_needed
score: 1/6 must-haves verified
behavior_unverified: 5
overrides_applied: 0
covered_files:
  - .github/workflows/release.yml
  - .planning/quick/260927-l12-create-manual-github-ci-to-build-and-pub/260927-l12-CONTEXT.md
  - .planning/quick/260927-l12-create-manual-github-ci-to-build-and-pub/260927-l12-PLAN.md
  - .planning/quick/260927-l12-create-manual-github-ci-to-build-and-pub/260927-l12-SUMMARY.md
  - README.md
  - lib/src/infrastructure/config/default_app_config.dart
  - lib/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart
  - linux/packaging/appimage/AppRun
  - linux/packaging/com.divertedriver.HotkeyGrammarCorrector.flatpak.yml
  - linux/packaging/sidecar-python
  - test/infrastructure/correction/claude_agent_sdk/sidecar_host_paths_test.dart
  - test/tool/release_version_test.dart
  - tool/package_linux_release.sh
  - tool/release_plan.dart
  - tool/release_version.dart
  - tool/run_linux_release.sh
  - tool/verify_linux_release.sh
covered_digest: "v1:sha256:3c883fb5d8eea4662250d906256919d11ecdb3b8421975cadceae48fdccc5c47"
behavior_unverified_items:
  - truth: "A manual main dispatch commits the selected version, atomically pushes its tag, and publishes a stable release."
    test: "Dispatch from main in GitHub after the workflow reaches the default branch."
    expected: "The selected bump is committed in pubspec.yaml; the matching annotated tag and four assets appear in a stable release."
    why_human: "Version arithmetic is tested, but no GitHub dispatch or remote ref mutation has run."
  - truth: "A non-main dispatch leaves its branch version untouched and publishes a sequenced, branch-labelled prerelease."
    test: "Dispatch from a disposable branch and inspect its ref, tag, and release."
    expected: "The branch ref is unchanged; the prerelease has the branch slug and next sequence."
    why_human: "The planner is tested, but the remote branch and publication transition is not."
  - truth: "A post-tag failure can recover the exact release without another bump or asset overwrite."
    test: "Retry a deliberately interrupted draft with retry_tag and compare tag and asset digests."
    expected: "The original tag and source remain; only missing matching assets are uploaded."
    why_human: "Stored-artifact and GitHub API recovery is wired but has no remote behavior test."
  - truth: "One build produces and verifies all four Linux packages before any remote mutation."
    test: "Run the package and verifier commands on a Linux runner that permits Flatpak Builder namespaces."
    expected: "All four packages pass extraction, desktop, sidecar, native dependency, and Flatpak sandbox probes before publication."
    why_human: "Three formats passed locally; Flatpak Builder was blocked by this container's namespace policy."
  - truth: "Stale main, foreign tags, failed checks, and rejected pushes fail safely."
    test: "Exercise those paths against a disposable remote or observe them in controlled GitHub runs."
    expected: "Each path fails without a force push, foreign tag reuse, or misleading release."
    why_human: "The guards are present, but the planned throwaway-remote simulation was not run."
human_verification:
  - test: "Run the first stable main dispatch after this workflow is available on the repository default branch."
    expected: "The chosen major, minor, or patch version is committed and tagged; four verified assets appear in a stable GitHub release."
    why_human: "No actual GitHub dispatch, tag push, or release upload occurred locally."
  - test: "Run a branch dispatch, then a controlled retry_tag dispatch after an interrupted draft."
    expected: "The branch remains unchanged, the prerelease name contains its slug and sequence, and retry reuses exact original asset digests."
    why_human: "The planner tests cannot observe GitHub refs, retained artifacts, or release asset APIs."
  - test: "Run the full package verifier on a Linux host whose Flatpak Builder can create namespaces."
    expected: "The Flatpak builds and passes its installed Python, CLI, permissions, and native library probes alongside the other three formats."
    why_human: "This container prevents the Flatpak build and install path."
  - test: "Exercise stale main, foreign tag, rejected push, and failed asset paths against a disposable remote."
    expected: "Each error stops before an incorrect tag or release is published."
    why_human: "No remote transition simulation exists yet."
---

# Quick Task 260927-l12 Verification Report

**Goal:** Provide a manual GitHub release workflow that versions and publishes four Linux package formats, using stable `main` releases and branch-labelled prereleases, with local testing.

**Verdict:** `human_needed`. The source has the requested wiring and the local checks below passed. A full Flatpak build and GitHub publication have not been observed. No implementation blocker was confirmed.

## Goal Achievement

| # | Observable truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | A `main` run selects major, minor, or patch, commits the bumped `pubspec.yaml`, atomically pushes a tag, and publishes a stable release | Present, behavior unverified | `workflow_dispatch` choice, `ReleaseVersionPlanner`, `run_linux_release.sh` commit and `git push --atomic`; planner tests pass, remote transition unrun |
| 2 | Another branch publishes a sequenced, branch-labelled prerelease without changing that branch | Present, behavior unverified | Planner uses `origin/main` core, slug and sequence; runner makes only a temporary version edit and pushes only a tag; remote transition unrun |
| 3 | A post-tag failure retries the exact tag and asset set without advancing version or overwriting remote assets | Present, behavior unverified | Annotated tag records run ID, attempt and manifest; recovery downloads the retained artifact and checks SHA-256, release metadata and remote digests; no remote retry run |
| 4 | One build produces tarball, `.deb`, AppImage and Flatpak, all verified before remote mutation | Present, behavior unverified | Packaging command creates four outputs and calls verifier; workflow awaits it before upload and push. Local entry point built and probed three formats; Flatpak Builder stopped at container namespace restriction |
| 5 | Flatpak grants precisely the approved network, display, IPC and Secret Service access, without host filesystem or Flatpak bus access | Verified | `flatpak-builder --show-manifest` returned the five approved finish args and neither banned grant; verifier compares installed metadata against the same set |
| 6 | Stale main, foreign tags, failed assets and rejected pushes fail safely | Present, behavior unverified | Freshness, provenance and digest guards plus non-force push are wired in runner; no throwaway-remote simulation or GitHub failure run |

**Score:** 1/6 verified; five runtime truths are present and wired but lack the required end-to-end behavior evidence.

## Required Artifacts and Links

| Artifact or link | Status | Evidence |
| --- | --- | --- |
| Manual workflow → release runner → package builder → verifier | Wired | `.github/workflows/release.yml` invokes `tool/run_linux_release.sh prepare` then `publish`; prepare invokes the package and verifier scripts |
| Version helper → build version, tag, Debian version and title | Wired | `release_version.dart` returns one `ReleasePlan`; runner uses its version, tag, title and prerelease fields; package script derives Debian `~` form |
| Installed sidecar path → packaged wrapper and SDK CLI | Wired and locally exercised | `DefaultAppConfig` uses `SidecarHostPaths`; 16 path tests passed; local package verifier imported SDK and ran bundled CLI for three formats |
| Four checked assets → publication | Wired, full behavior unverified | `verify_assets` checks recorded hashes and calls the four-format verifier before `publish_assets`; no remote upload happened |
| Retry tag → original source and retained verified assets | Wired, behavior unverified | Annotated provenance checks, `gh run download`, SHA-256 manifest and remote asset comparisons exist; no remote retry happened |
| Data-flow trace | N/A | These artifacts are build tools and configuration; none renders dynamic UI data |

The GSD artifact/key-link parser returned zero items for this quick-plan format, so the entries above were checked directly against source. All six declared artifact paths exist and contain substantive code or configuration.

## Behavioral Spot-Checks and Probe Results

| Check | Result |
| --- | --- |
| `dart test test/tool/release_version_test.dart` | Passed, five value/behavior tests |
| `dart test test/infrastructure/correction/claude_agent_sdk/sidecar_host_paths_test.dart` | Passed, 16 path behavior tests |
| `dart analyze --fatal-infos` | Passed, no issues |
| `bash -n` and `shellcheck` on release shell files, AppRun and wrapper | Passed |
| Parse workflow and Flatpak manifest | Manual-only `workflow_dispatch`, three bump choices, five approved finish args and four Flatpak source directories confirmed |
| Vendored Flatpak tray library notices | Five required package copyright files exist locally; packaging stages them as `native-notices` and the manifest installs them beside the bundled library documentation |
| Local tarball, `.deb` and AppImage | Real files present; `.deb` reports version `1.0.1` and the Ayatana dependency; tarball contains app, wrapper and desktop installer; earlier verifier log shows installed desktop and CLI probes for all three |
| `tool/verify_linux_release.sh --version 1.0.1 --output-dir /tmp/hgc-release-local-1.0.1` | Failed closed on the missing Flatpak, as required; a full four-format pass is unavailable here |
| Full local Flutter suite | Executor recorded 1,214 passed and nine skipped with `--exclude-tags=live`; this verifier did not rerun it. The workflow's coverage command has not been run locally |
| Full package entry point | Executor log shows tarball, `.deb` and AppImage creation, then Flatpak Builder fails at the container's namespace boundary; no GitHub publication was attempted |

No separate `probe-*.sh` file is declared for this quick task. The package and verifier scripts are its runnable probes. The verifier's full pass is blocked by the missing Flatpak output.

## Requirements, Decisions, and Test Quality

No roadmap requirement IDs are mapped to this quick task, and no later active milestone explicitly defers any of its acceptance criteria. The CONTEXT decisions are reflected in source: `main` as stable branch; run-form bump; branch prerelease suffix; four outputs; committed stable version; and the owner-approved Flatpak network grant. The automated decision-coverage query reported no trackable entries because this quick context is Markdown rather than XML.

The two focused test files have 21 active tests and no disabled cases. Their assertions check specific versions and path behavior. They do not cover the remote publication, failure or retry transitions. No `TBD`, `FIXME`, `XXX`, placeholder, or dead-code marker was found in the release implementation files.

## Human Verification Required

1. Dispatch the workflow from `main` after the workflow file is on the default branch; inspect the version commit, tag, four assets and stable release.
2. Dispatch from a non-main branch and exercise a controlled `retry_tag`; inspect the unchanged branch ref, sequenced prerelease and exact asset digests.
3. Build and install the Flatpak on a Linux runner with user namespaces; run the verifier's in-sandbox SDK, CLI, permission and native-library checks.
4. Exercise stale-main, foreign-tag, rejected-push and asset-mismatch cases against a disposable remote; confirm every path fails without incorrect publication.

The plan requested an automatic replan after an external prerelease tag race. The implementation instead fails safely and requires a fresh manual dispatch to choose the next sequence. This preserves the verified asset names and digests; it is documented in SUMMARY.md and does not change the user's required branch-version behavior.

_Verified: 2026-09-27T23:48:14Z_
_Verifier: gsd-verifier_
