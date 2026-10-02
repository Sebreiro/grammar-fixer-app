# Quick Task 261002-cdz — Context

Gathered: 2026-10-02
Status: Ready for planning

## Task boundary

The panel sometimes opens underneath other windows and flashes in the taskbar.
The user wants it always above and confirmed the affected session is KDE Wayland.

## Decisions

- Keep the visible correction panel above other application windows.
- Preserve the taskbar entry requested in quick task 261002-3x4.
- Preserve CAP-14 focus-loss dismissal and hotkey toggle, and the warm hidden
  startup window. “Always above” applies while visible; it does not pin the panel
  open after a click away.
- The current request supersedes the earlier quick task's “no permanent
  always-on-top” restriction. No SPEC conflict was found.

## Discretion

Use a narrow KDE integration behind the existing native presentation boundary.
Do not change other applications or write KWin's persistent configuration.
Perform the workflow inline under the skill's Codex spawn restriction.

## Canonical references

AGENTS.md, PLAN.md, SPEC.md (CAP-1/CAP-14), risks.md, and the prior taskbar and
KDE activation quick-task artifacts.
