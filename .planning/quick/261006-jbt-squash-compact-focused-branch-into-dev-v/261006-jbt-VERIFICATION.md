---
quick_id: 261006-jbt
status: passed
score: 5/5 task must-haves verified
verification_mode: inline
source_commit: a5789fec07b292fc2be6303745063aba75a6299b
---

# Local 1.1 release verification

The task goal is the requested local integration, tests on dev, version bump,
equal main/dev commits, and a usable local AppImage. The user explicitly removed
remote publication from scope during execution. This report does not promote
the feature's existing unobserved desktop/performance claims to verified facts.

| Must-have | Evidence | Result |
|---|---|---|
| Complete feature integrated as one squash | Before commit, `git write-tree` equaled the pinned feature tree. Squash `d3c940c` has sole parent `f1bfc51`; committed tree comparison passed. | Passed |
| 1.1.0+2 tested on dev | Manifest assertion; clean analysis/format; 1,118 binding-free and 1,474 Flutter tests passed; native tests passed; 96.10% line and 90.00% branch coverage. | Passed |
| Main/dev share a local commit | Main fast-forwarded to dev; both resolved to `a5789fec07b292fc2be6303745063aba75a6299b` and `git diff main dev` was empty. Documentation finalization repeats this fast-forward and equality check. | Passed |
| Fresh executable AppImage and checksum | Final 1.1.0 file exists, executable, checksum validates; extracted code/resources match the release bundle; 75 dependencies and SDK/CLI check; actual final file passed isolated hotkey/focus smoke. | Passed |
| Existing user content preserved | Recorded hashes of the untracked design brief and 1.0 AppImage remain valid; generated SPEC diff is empty; original feature branch still names its source tip. | Passed |

## Executed checks

```text
flutter pub get
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed lib test tool
tool/provision_sidecar.sh
tool/test_native_panel_activation.sh
dart test --reporter=expanded --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart
flutter test --reporter=expanded --coverage --branch-coverage --exclude-tags=live test
dart run tool/check_coverage.dart coverage/lcov.info
flutter build linux --release
actionlint .github/workflows/ci.yml
node --check prototype/ui-baseline/{app,fixtures,state}.js  (each separately)
AppImage extraction, ELF code-section/resource comparisons, dependency/SDK/CLI and desktop-installer checks
Actual final AppImage under Xvfb/openbox and private D-Bus/XDG paths
sha256sum --check hotkey_grammar_corrector-1.1.0-linux-x86_64.AppImage.sha256
git diff --exit-code main dev
sha256sum --check build/verification/261006-jbt/preserved-files.sha256
```

The full Flutter logs include the fake CLI/provider and isolated X11 integration
tests. Explicitly live tests and nine existing skips are not claimed as passed.
Source/manifest/native/dependency files remain exactly at the tested release
commit; the final documentation commit changes planning artifacts only.

## Artifact identity

Path: `build/releases/hotkey_grammar_corrector-1.1.0-linux-x86_64.AppImage`

Size: 111,954,424 bytes.
SHA256: `52216c81e4f47e65fa4cfc2bec3d34e03ceac83988705576da78034950dff3c2`.

Native X11 startup and hotkey behavior are observed. Native Wayland, actual
provider responses, physical-desktop appearance, FUSE mounting, and CAP-1
latency/RAM measurements remain outside these checks. Original stacked-layout
authorization and generated CAP-4 wording are recorded in the task research;
the SPEC is untouched. No production settings or existing daemon was changed,
and no remote refs were pushed.
