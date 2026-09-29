# Manual Linux release CI — Research

**Researched:** 2026-09-27  
**Confidence:** MEDIUM (official platform docs and inspected repo; no live runner or complete package build)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- `main` is the release branch; this repository has no `master` branch.
- The manual run form chooses `major`, `minor`, or `patch` for the next version.
- A stable `main` release commits the bumped version to `pubspec.yaml` and tags that commit.
- Non-`main` runs publish GitHub prereleases with a branch and sequence suffix, such as `1.1.0-feature-x.1`.
- Publish a Linux Flutter bundle tarball, a `.deb`, an AppImage, and a Flatpak.
- The project already ratified a three-format packaging set: `.deb`/tarball, Flatpak, and AppImage, with none designated second class. This request implements all named outputs.

### Agent's Discretion
- Choose robust tooling, tag lookup, branch-name normalization, collision handling, and local validation details that honor the decisions above.
- Keep branch prereleases from changing `pubspec.yaml` on the source branch unless needed for a correct build.

### Deferred Ideas (OUT OF SCOPE)
None recorded.
</user_constraints>

## Summary and recommended plan

Use one new `workflow_dispatch` release workflow and one locally runnable packaging script. Keep the existing merge gate separate: its trigger and read-only token are defined in `.github/workflows/ci.yml` as `workflow_dispatch:` and `contents: read` [VERIFIED: .github/workflows/ci.yml:33-53]. GitHub requires the dispatched workflow file on the default branch, allows choosing another branch, and exposes that branch as `refs/heads/...` [CITED: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow] [CITED: https://docs.github.com/en/actions/reference/workflows-and-actions/variables].

**Resolve before publishing a functional Flatpak:** the ratified finish args are exactly `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc`, `--talk-name=org.freedesktop.secrets`, with no host filesystem or Flatpak bus grant [VERIFIED: .planning/milestones/v1.0-phases/01-hotkey-truth/01-01-SUMMARY.md:143-149]. Flatpak denies network access by default; `--share=network` grants it [CITED: https://docs.flatpak.org/en/latest/sandbox-permissions.html]. The current default is a remote Claude Agent SDK sidecar and the alternate provider is HTTP [VERIFIED: README.md:8-35] [VERIFIED: .planning/PROJECT.md:83-84]. **Inference:** under those locked permissions, a sandboxed remote correction cannot work. A build can be made, but calling it a working app would contradict the source docs. The planner needs an explicit permission decision; do not silently add `--share=network` or escape to the host.

## Architecture Patterns: release workflow and version rules

- **Version source.** `pubspec.yaml` currently says `version: 1.0.0+1` [VERIFIED: pubspec.yaml:5-5]. Parse its three-component core and ignore the `+1` build metadata for release tags. The existing tag is `v1.0` [VERIFIED: local `git tag --list 'v*'`, 2026-09-27]; do not parse it as `vMAJOR.MINOR.PATCH`. From the current core, a patch/minor/major choice yields `1.0.1`/`1.1.0`/`2.0.0`; write the chosen stable version to `pubspec.yaml` and use `vX.Y.Z` for the Git tag. Dart supports both prerelease and build suffixes [CITED: https://dart.dev/tools/pub/pubspec].
- **Branch prerelease.** Read the selected ref from `github.ref`; reject tags and require `refs/heads/`. Normalize the complete branch name to lowercase ASCII `[a-z0-9-]`, map all other runs to one hyphen, trim edge hyphens, and reject an empty slug. Keep a short deterministic hash of the original branch name if two distinct refs normalize to the same slug. SemVer prerelease identifiers allow ASCII letters, digits, and hyphens, with dots separating identifiers [CITED: https://semver.org/]. Use the selected bump against the latest stable `main` version, then find the first unused remote `vX.Y.Z-slug.N` tag by querying/fetching remote tags. This naming policy is a recommendation [ASSUMED], not a preexisting project decision. Do not commit the temporary prerelease version to the source branch.
- **Race safety.** Give all release runs one workflow concurrency group with `cancel-in-progress: false` and `queue: max` if supported by the runner; GitHub's default single pending slot cancels older pending runs, while `queue: max` queues up to 100 [CITED: https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency]. At run start, fetch `main` and tags; for stable runs, require the selected checkout SHA still equals `origin/main`. Build all four assets before mutating remote refs. Commit only the version file, tag that commit, then push branch and tag together with `git push --atomic origin HEAD:refs/heads/main refs/tags/vX.Y.Z`; Git says an atomic push updates all refs or none, and fails if the remote lacks support [CITED: https://git-scm.com/docs/git-push]. Recheck on push rejection and **fail rather than force or auto-rebase a built binary**. Tag branch prereleases at the dispatched SHA, push the tag, then publish. Use `gh release create ... --verify-tag --prerelease` for prereleases and `--verify-tag` for stable releases so `gh` never silently creates a tag at the default branch [CITED: https://cli.github.com/manual/gh_release_create].
- **Permissions and real GitHub gates.** Scope the publishing job to `contents: write`; the Release API requires Contents write [CITED: https://docs.github.com/en/rest/releases/releases]. A branch protection/ruleset may reject the stable version commit even with that token [CITED: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches]. Also, GitHub's Release API can reject a prerelease whose target branch changes `.github/workflows/` relative to default, because `GITHUB_TOKEN` cannot obtain Workflow write [CITED: https://docs.github.com/en/rest/releases/releases]. Check these repository settings and the first real run before claiming release automation works. A push made with `GITHUB_TOKEN` does not trigger ordinary push workflows, so the release job must run its own needed checks [CITED: https://docs.github.com/en/enterprise-cloud@latest/actions/concepts/security/github_token].

## Standard Stack and packaging architecture

Build once with pinned Flutter `3.44.8` [VERIFIED: .github/workflows/ci.yml:73-88], using `flutter build linux --release`; the output is `build/linux/x64/release/bundle/`, including executable, `lib/`, and `data/` [CITED: https://docs.flutter.dev/platform-integration/linux/building]. Keep those siblings together in every format and inspect native dependencies with `ldd`. The repo's executable and application ID are exactly `hotkey_grammar_corrector` and `com.divertedriver.HotkeyGrammarCorrector` [VERIFIED: linux/CMakeLists.txt:5-24]; the desktop file is `com.divertedriver.HotkeyGrammarCorrector.desktop` with `Exec=hotkey_grammar_corrector` and `Icon=com.divertedriver.HotkeyGrammarCorrector` [VERIFIED: linux/packaging/com.divertedriver.HotkeyGrammarCorrector.desktop:10-18]. Package that file and its icon; a bare Flutter tarball also needs install instructions for the Wayland desktop entry [VERIFIED: README.md:38-65].

**Build commands:** `flutter build linux --release`; `tar -C build/linux/x64/release -czf dist/hotkey_grammar_corrector.tar.gz bundle`; `dpkg-deb --build staged-deb dist/app.deb`; `linuxdeploy --appdir AppDir --output appimage`; `flatpak-builder --force-clean --repo=repo builddir manifest.yml` then `flatpak build-bundle repo dist/app.flatpak com.divertedriver.HotkeyGrammarCorrector`. The latter three require the staging tree/manifest described below. [CITED: https://docs.flutter.dev/platform-integration/linux/building] [CITED: https://manpages.debian.org/bookworm/dpkg/dpkg-deb.1.en.html] [CITED: https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html] [CITED: https://docs.flatpak.org/en/latest/first-build.html]

| Output | Recommended build path | Check |
|---|---|---|
| Tarball | Archive the **whole** Flutter bundle; include installer/readme for the desktop entry. [CITED: https://docs.flutter.dev/platform-integration/linux/building] | Extract; verify binary, `lib/`, `data/`, sidecar asset and executable mode. |
| `.deb` | Stage the intact bundle under an application directory; install a launcher, desktop file, and icon into standard system paths; create `DEBIAN/control`; run `dpkg-deb --build`. [CITED: https://manpages.debian.org/bookworm/dpkg/dpkg-deb.1.en.html] | `dpkg-deb --info`, `--contents`, dependency inspection, install/remove in disposable VM. For prereleases use Debian `~` ordering in control `Version` (e.g. `1.1.0~feature-x.1`) while retaining SemVer in the release/tag filename. [CITED: https://www.debian.org/doc/debian-policy/ch-controlfields.html] |
| AppImage | Stage intact bundle in an AppDir with one entry point, matching `.desktop` and icon; use official `linuxdeploy`/AppImage tooling to finish dependencies and produce the image. [CITED: https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html] [CITED: https://docs.appimage.org/reference/appdir.html] | Verify AppDir and extract-and-run on systems without FUSE. [CITED: https://docs.appimage.org/user-guide/troubleshooting/fuse.html] |
| Flatpak | Use a manifest with a GTK-capable runtime, install the intact bundle into `/app`, install the exact-ID desktop file/icon, then `flatpak-builder --repo=...` and `flatpak build-bundle ...`. [CITED: https://docs.flatpak.org/en/latest/first-build.html] [CITED: https://docs.flatpak.org/en/latest/conventions.html] | Install and run inside a real Flatpak sandbox on X11 and Wayland; verify portal, tray, filesystem, network decision, and correction. |

## Common Pitfalls and Don't Hand-Roll

The sidecar script is an asset at `assets/sidecar/claude_agent_sdk_sidecar.py`; the bundled asset root is `data/flutter_assets`, while the interpreter probe is `.venv-sidecar/bin/python3`, falling back to `python3` [VERIFIED: lib/src/infrastructure/correction/claude_agent_sdk/sidecar_host_paths.dart:32-48]. The provision script creates `.venv-sidecar` beside the checkout, **outside** the Flutter bundle [VERIFIED: tool/provision_sidecar.sh:19-28]. Copying that venv into a distributable is unsafe because Python venv scripts encode absolute interpreter paths [CITED: https://docs.python.org/3.13/library/venv.html]. Plan an installed or app-local Python environment and explicit interpreter configuration for all formats, then test from a clean config; do not infer functionality from a successful Flutter build. Anthropic's SDK type documents use of a bundled CLI when `cli_path` is unset, so verify the pinned SDK wheel's bundled binary before assuming a separate host `claude` is needed [CITED: https://github.com/anthropics/claude-agent-sdk-python/blob/main/src/claude_agent_sdk/types.py].

For Flatpak, host `.venv-sidecar` and host `claude` are outside the sandbox, and `flatpak-spawn --host` needs `org.freedesktop.Flatpak` bus access, which the ratified permissions reject [CITED: https://docs.flatpak.org/en/latest/sandbox-permissions.html] [CITED: https://docs.flatpak.org/en/latest/flatpak-command-reference.html]. Bundle Python, the pinned SDK and its CLI into `/app` or make a separately approved change to the provider architecture; do not use host escape. Flatpak sets sandboxed XDG config/data directories itself [CITED: https://docs.flatpak.org/en/latest/conventions.html]. The app already selects its sandbox portal mode from exactly `/.flatpak-info` or `FLATPAK_ID` [VERIFIED: lib/src/infrastructure/hotkey/portal_app_id_regime.dart:65-88].

## Local validation and gaps

The container has Flutter `3.44.8`, Dart `3.12.2`, `gh`, `dpkg-deb`, CMake and Ninja [VERIFIED: local `flutter --version` and command probes, 2026-09-27]. It lacks `flatpak`, `flatpak-builder`, `linuxdeploy`, `appimagetool`, `desktop-file-validate`, and `bwrap` [VERIFIED: local command probes, 2026-09-27]. The default command sandbox itself fails with `bwrap: No permissions to create a new namespace`; a Flatpak sandbox run here is therefore not presently testable. `flutter build linux --release`, tar creation, `.deb` construction/inspection, version/slug tests, and workflow syntax checks remain locally feasible; a full four-format run needs another Linux host or suitably configured runner. No package build or real workflow run was executed in this research pass. The existing CI file explicitly records that it has never run on GitHub [VERIFIED: .github/workflows/ci.yml:1-6].

**Planner gates:** (1) obtain a decision on Flatpak network permission and an in-sandbox Python/SDK delivery path; (2) verify branch protection and prerelease workflow-file behavior on GitHub; (3) make one local packaging command the CI entry point; (4) publish only after all four artifacts and their structural checks pass; (5) use the first manual GitHub run as the runner verification.

## Project Constraints (from AGENTS.md)

Linux X11 and Wayland, resident tray daemon, and no Electron/webview are required [VERIFIED: AGENTS.md:15-16]. Do not add fallback or cascade providers [VERIFIED: AGENTS.md:75-85]. Keep platform work behind interfaces and do not put network calls in widgets [VERIFIED: AGENTS.md:43-65]. A clean `dart analyze` is required; capability success criteria need regression tests [VERIFIED: AGENTS.md:155-157] [VERIFIED: AGENTS.md:184-191]. Never construct the panel on hotkey press or revise the generated spec to match code [VERIFIED: AGENTS.md:193-206].

## Assumptions log

| Claim | Why still open |
|---|---|
| [ASSUMED] Branch prerelease version derives from `main`'s current stable core and uses the selected bump. | CONTEXT requires a bump input and branch suffix but does not define their relationship. |
| [ASSUMED] Repository settings permit `GITHUB_TOKEN` to push a version commit to `main` and create tags. | Settings are not available from this checkout; branch rules may prevent it. |
| [ASSUMED] A GTK-capable Flatpak runtime can satisfy every native `.so` found by the release build without extra modules. | Requires `ldd` inside the actual sandbox. |
