# Quick Task 261002-gk8 — Select and copy panel text

**Gathered:** 2026-10-02
**Status:** Ready for planning
**Execution:** Inline per the gsd-quick Codex spawn restriction.

## Task Boundary

Select all or part of corrected text and panel error messages with the mouse, then copy with the keyboard or the right-click menu.

## Decisions

- Use standard desktop selection: drag, Ctrl+A, Ctrl+C, and right-click → Copy.
- Keep text read-only and leave the panel open after copying (CAP-14).
- Retain per-suggestion copy buttons and register selection shortcuts (CAP-4/CAP-11).
- Keep streamed partials non-actionable until the authoritative result arrives (AD-3).
- Include provider failures and inline copy-failure messages.
- The user explicitly specified selection and copy interactions. An optional full-mode discussion question was presented while inspecting the implementation; proceed with the stated standard behavior under the task's authorization.

## Canonical References

- AGENTS.md; PLAN.md; SPEC.md CAP-4, CAP-5, CAP-10, CAP-11, CAP-13, CAP-14.
- Existing original editor's framework text selection and clipboard behavior.
- Generated specifications are not edited.
