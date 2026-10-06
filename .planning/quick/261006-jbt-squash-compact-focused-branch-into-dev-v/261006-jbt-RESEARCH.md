# Release research: 261006-jbt

## Observed state

At planning time, local and remote main/dev both point at
`f1bfc516caa8458fd47acfe7a09e435db4cef2ed`. The feature tip is
`57fe4a471c668e72fe60fb6284367a53e1ba2a55`; its remote is eight commits behind.
The only untracked user content is `.planning/design/`. The manifest is
`1.0.0+1`; the installed toolchain is Flutter 3.44.8 and Dart 3.12.2.

## Integration approach

`git merge --squash` on dev preserves the complete committed feature tree in one
new commit. Compare that tree to the source tip before committing. Advance main
only through `git merge --ff-only dev`, after tests and AppImage validation.
An atomic push of the two refs keeps remote main/dev synchronized and fails
without updating either if a concurrent change prevents a fast-forward.

CI currently names nonexistent `master` and `Dev` branches. Replace those names
with `main` and `dev`, including the cancellation guard. The release workflow is
manual; pushing main does not publish a package or create a release tag.

## Build and validation

The full CI test gate is Flutter tests with line/branch coverage excluding the
explicitly live provider tests. Provision the SDK first to avoid misleading
fake-CLI skips. Run binding-free application/domain/architecture/infrastructure
tests, native activation tests, and fatal-info analysis on dev as well.

The aggregate packaging script requires Flatpak to build all four formats. The
requested scope is one local AppImage. Use its AppImage construction steps with
the same resources, wrappers, and SDK requirement; do not publish remotely.
Cached linuxdeploy and type-2 runtime match the release workflow SHA256 pins:

- linuxdeploy: `c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d`
- runtime: `2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d`

Use the AppImage plugin's bundled appimagetool with two compression workers to
avoid container thread limits. Extract the candidate to compare application
code sections/assets with the release bundle, check native dependencies, verify
the pinned SDK and bundled CLI, and test desktop installation in private XDG
directories. Run the actual AppImage under Xvfb/openbox and a private D-Bus session
to observe hidden startup, hotkey focus, and hotkey dismissal.

## Limits and existing decisions

No Wayland compositor or physical desktop observation is available here. Real
provider calls are unnecessary for this integration and remain opt-in. Existing
feature verification records prior owner authorization for stacked suggestions
despite CAP-4's generated side-by-side wording; retain the authorized branch
behavior and do not edit the generated SPEC. Full native Wayland/performance
claims remain outside the automated evidence.

Git transport can read origin. GitHub CLI has no logged-in account. No external
API or database schema changes are introduced by this release task.

Scope update during execution: a push dry-run found no HTTPS credentials or SSH
agent. No remote refs were changed. The user then explicitly removed publication
from scope: "don't push. commits is enough". Final completion requires equal
local branch tips only; do not attempt a push or request authentication.
