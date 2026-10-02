# Quick Task 261002-bb8: Ctrl+Shift+tilde hotkey - Context

**Gathered:** 2026-10-02
**Status:** Ready for planning

## Task Boundary

Fix the reported Settings refusal when capturing Ctrl+Shift+~ and support the standard punctuation keys through the same path.

## Implementation Decisions

- The requested combination must be accepted, passed to the selected Linux hotkey adapter, and saved through the existing config path (CAP-12).
- Keep the existing physical-key capture and modifier model. Shift remains a modifier; tilde is the shifted character of the backquote key on a US layout.
- The user asked why all keys could not be added. The response explained the allowlist and stated the expanded scope: all 11 standard punctuation keys, with base and shifted characters handled through their physical key. This interprets the follow-up as a request for the broader punctuation option; it does not claim support for every HID/media/international key or AltGr.
- Run full-mode research, planning, plan checking, code review, and verification inline under the skill's spawn restriction.

## Canonical References

- AGENTS.md
- PLAN.md
- _bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md (CAP-12)
- Existing catalogue, X11 registrar, XDG trigger serializer, and Settings capture tests.
