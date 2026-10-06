---
quick_id: 261006-jbt
mode: quick-full
autonomous: true
files_modified:
  - pubspec.yaml
  - .github/workflows/ci.yml
  - tool/uat/grab_probe.dart
must_haves:
  truths:
    - All committed compact-focused feature changes are integrated into dev in one squash commit.
    - Release 1.1.0+2 is tested on dev before main advances.
    - Local main and dev end at the same commit, without pushing.
    - A fresh executable 1.1.0 AppImage and checksum are available locally.
    - User design content and the older AppImage are preserved.
  artifacts:
    - pubspec.yaml
    - .github/workflows/ci.yml
    - build/releases/hotkey_grammar_corrector-1.1.0-linux-x86_64.AppImage
    - build/releases/hotkey_grammar_corrector-1.1.0-linux-x86_64.AppImage.sha256
  key_links:
    - The dev squash tree matches the pinned feature tree before release metadata edits.
    - CI branch filters name the branches that are actually pushed.
    - The AppImage contains code and resources from the verified 1.1.0 release bundle.
    - Main fast-forwards to dev and both local refs resolve to the same commit.
---

# Release compact focused changes as version 1.1

## Task 1: Squash the feature into dev

files: the committed feature-vs-dev diff observed at execution, excluding any
untracked user content.

action: Recheck worktree and remote branch tips. Preserve the feature branch,
switch to dev, squash the pinned feature tip, confirm the staged tree equals
the feature tree, and commit the integration as one commit. Do not force/reset
existing branches or stage unrelated untracked content.

verify: A clean merge index; `git write-tree` equals the feature commit's tree;
the squash has exactly one parent, the previous dev tip.

done: Dev contains the complete feature in one squash commit, and main is still
unchanged.

## Task 2: Version, test, and build on dev

files: `pubspec.yaml`, `.github/workflows/ci.yml`, generated logs/coverage under
`build/`, and generated AppImage/checksum under `build/releases/`.

action: Set `1.1.0+2`, update CI push/PR filters to main/dev and its cancellation
guard to main, and commit metadata atomically. Resolve only actual release
check failures, with meaningful regression coverage for any source correction.
Run fatal-info analysis, formatter check, provisioned binding-free tests, the
full non-live Flutter suite with coverage, the coverage gate, native activation
tests, and a Linux release build. Build the AppImage candidate using pinned
tools and fresh SDK dependencies. Verify contents/dependencies/desktop entries,
then exercise the actual image in an isolated X11 session. Rename the validated
candidate to its final filename and write/verify its checksum.

verify: Required test, analysis, formatter, coverage, native, build and package
checks exit successfully; failures block advancing main. Manifest is exactly
`1.1.0+2`; AppImage code matches
the fresh bundle and smoke tests pass. Inspect release metadata changes and
review the integration scope for actionable problems.

done: Verified dev release and runnable local 1.1.0 AppImage are available;
existing user files and 1.0 image remain unchanged.

Execution note: the broad formatter gate found an existing formatting issue in
`tool/uat/grab_probe.dart`. The metadata commit also contains Dart formatter
output for that file; no behavior changed. Changed CI workflow lint passes.
An optional lint of the unchanged release workflow found that installed
actionlint 1.7.12 rejects its existing `concurrency.queue` key; this task does not
change that workflow.

## Task 3: Record verification and synchronize branches

files: this task's CONTEXT/RESEARCH/PLAN/PLAN-CHECK/REVIEW/SUMMARY/VERIFICATION
documents and `.planning/STATE.md`; local main/dev refs.

action: Document exact checks, measured limitations, commits, artifact size and
digest; append the quick-task state row and commit only these artifacts. Switch
to main and fast-forward to dev. Compare exact local SHAs and leave the workspace
on dev for the user's local testing. The user's later no-push instruction
supersedes the original publication step; do not push branches or release tags.

verify: The quick verification status is usable; local main/dev resolve to the
same SHA, with empty committed-tree diffs. The
AppImage/checksum exist and validate. Status contains only preserved user content.

done: Both branches are synchronized locally at the tested 1.1 release tree;
the AppImage path is provided to the user. No changes are pushed.

<threat_model>
Security enforcement: ASVS level 1; block on high severity. Risks in this task
are stale/concurrent refs, accidental inclusion of user files, altered package
tooling, and affecting the user's running daemon or config during smoke tests.
Mitigations: pin/read refs, compare the squash tree, stage explicit paths, use
fast-forward-only local merges and no remote publication, check tool SHA256 pins,
and use private display/D-Bus/XDG locations with bounded child-process cleanup.
No new credential handling, API integration, or schema migration is introduced.
</threat_model>
