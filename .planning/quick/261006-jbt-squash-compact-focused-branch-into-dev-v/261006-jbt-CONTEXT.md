# Quick task 261006-jbt: Release the compact focused branch as 1.1

Gathered: 2026-10-06
Status: Ready for planning

## Task boundary

Squash the current feature branch into dev, test the result on dev, bump the app
to 1.1, merge it into the production branch while retaining identical branch
tips, and deliver a locally built AppImage for the user to test.

## Locked decisions

- The user confirmed that the existing `main` branch is the requested master
  branch, and that the manifest version is `1.1.0+2`.
- Squash `feature/design/compact-focused` into `dev`, retaining all its committed
  changes, including the eight commits that have not reached the feature remote.
- Test the integrated release on dev before advancing main. Fast-forward main
  so it shares the same final local commit with dev.
- The user subsequently instructed: "don't push. commits is enough". Keep all
  work local; no branch push or release publication is part of the final task.
- Deliver the AppImage under `build/releases/`, with an adjacent SHA256 checksum.
- Preserve the untracked `.planning/design/` content and the existing 1.0 AppImage.

## Implementation discretion

- Correct the obsolete CI branch triggers so pushes and pull requests for the
  actual branches run their existing checks.
- Use the repository packaging layout, pinned AppImage tooling, a fresh Linux
  release bundle, and freshly installed pinned sidecar dependencies.
- Execute workflow roles inline: the invoked skill permits this fallback when
  the user has not explicitly requested subagents. This is not an independent
  multi-agent review.

## Canonical references

- `AGENTS.md`, `PLAN.md`, and the generated SPEC plus its provider/risk companions.
- `.github/workflows/ci.yml` and `.github/workflows/release.yml`.
- `tool/package_linux_release.sh`, `linux/packaging/appimage/AppRun`, and
  `tool/test_native_panel_activation.sh`.
