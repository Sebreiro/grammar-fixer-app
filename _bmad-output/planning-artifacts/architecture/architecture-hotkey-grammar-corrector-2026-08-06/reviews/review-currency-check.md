# Reviewer lens: currency / reality-check

**Question:** was every committed decision web-researched or reality-checked, rather than asserted from training data?

**Verdict:** PASS with two medium-confidence items now annotated in the spine.

| Claim in spine | Source | Confidence |
| --- | --- | --- |
| Flutter stable 3.44.8 / Dart 3.12.2 | `releases_linux.json` official manifest, fetched 2026-08-06 | High |
| All pub.dev package versions in Stack | pub.dev API, fetched 2026-08-06 | High |
| Claude Agent SDK has no Dart binding (Python + TypeScript only) | `claude-api` skill, authoritative | High |
| Model id `claude-sonnet-5`, no date suffix | `claude-api` skill model table | High |
| Portal: compositor/user chooses the combination; `preferred_trigger` is a hint | flatpak.github.io xdg-desktop-portal GlobalShortcuts docs | High |
| `Activated` signature `(o, s, t, a{sv})`; session/request handle-token pattern | Same upstream docs | High |
| `Registry.Register(app_id)` required first on portal ≥ 1.20; empty app id hard-rejected | Upstream Registry docs + electron/electron#51875 + practitioner writeup | High |
| app_id must be reverse-DNS **and** have a matching installed `.desktop` file | Practitioner writeup (GNOME "Discarded shortcut bind request") | Medium-high |
| `hotkey_manager` Linux = keybinder-3.0 | Package README (explicit `sudo apt-get install keybinder-3.0`) | High |
| keybinder-3.0 is X11-only, no Wayland path | Inferred from keybinder's XGrabKey design + the portal's existence + QHotkey's equivalent statement. Not directly verified in keybinder source. | Medium-high |
| wlroots (Sway/Hyprland/Niri) ship no GlobalShortcuts backend | Practitioner writeup; community tracking. Not an upstream support matrix. | **Medium** — annotated in AD-12 |
| `claude --print --output-format stream-json --verbose` | Claude Code docs + three third-party SDK CLI-protocol docs | **Medium-high on exact flags** — annotated in AD-15 |

**Findings applied:** AD-12 now says the wlroots gap was verified against community tracking rather than an upstream matrix and should be re-checked before promising a compositor. AD-15 now says to confirm the exact flag set against `claude --help` on the installed CLI, while noting the NDJSON transport shape is the stable part.

**Nothing in the Stack table was asserted from memory.** Every version was fetched during this run.

## Disposition — 2026-09-26

The original PASS and its 2026-08-06 source-confidence judgments remain historical. The current spine's `## Stack` cites checked-in manifests and labels its 2026-09-26 reconciliation as a repository check, not an upstream latest-version check; `pubspec.yaml` is the shipped pub graph. Thus the old version rows are **superseded as current-version evidence**, without rejecting what this reviewer fetched in 2026-08-06.

The two medium-confidence qualifications are **accepted and still open as verification limits**: AD-12 still attributes wlroots backend coverage to community tracking rather than an upstream support matrix, and AD-15's default sidecar still depends on the configured host/CLI protocol (`ARCHITECTURE-SPINE.md`, AD-12, AD-19; `assets/sidecar/claude_agent_sdk_sidecar.py`). This appendix did not query upstream releases, run `claude --help`, or observe a compositor. The old `hotkey_manager`/keybinder inference is **superseded** by the shipped libX11 FFI registrar (`lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart`, AD-9); it is not a current runtime claim.
