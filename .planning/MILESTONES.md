# Project Milestones: Hotkey Grammar Corrector

## v1.0 Ledger Hardening (Shipped: 2026-09-26)

**Delivered:** The Linux tray daemon now reports hotkey, Settings, panel, provider, and shutdown state through the shipped contracts; its architecture and deferred-work ledger match the implementation.

**Phases completed:** 1–2 (53 plans, 100 tasks; 50 in-scope requirements)

**Key accomplishments:**

- Replaced the X11 key grab path, preserved working shortcuts on refused replacement, and made backend unavailability a typed state on X11 and Wayland.
- Wired live Settings changes through config and the tray; the retained Wayland refusal now preserves the old shortcut and restart seed while showing the refusal.
- Corrected panel selection, copy feedback, warm-window geometry, and window-event handling without discarding an active editor session.
- Unified bounded startup/stop cleanup and added a selectable OpenAI-compatible correction provider beside the default Claude Agent SDK sidecar.
- Reconciled the 19-decision architecture spine and closed all 40 Phase 02 requirement-linked deferred-work entries with their original provenance intact.

**Verification:** [v1.0 audit](milestones/v1.0-MILESTONE-AUDIT.md) passed with 50/50 requirement cross-references and no source-proven integration blocker. Phase 02 has 18/18 truths passed for milestone acceptance: 13 verified and five by D-20 waiver. Its eight live checks are passed by waiver and remain unobserved. The final local gate passed: 982 Dart tests (2 skipped), 165 Flutter tests (7 skipped), analyzer clean. Phase 01 has two verification overrides. No CI, live compositor, tray-host, Secret Service, or provider endpoint pass is claimed. The pre-close GSD open-artifact audit found 0 items.

**Archive:** [roadmap](milestones/v1.0-ROADMAP.md) · [requirements](milestones/v1.0-REQUIREMENTS.md) · [phase records](milestones/v1.0-phases/)

**What's next:** Select the next milestone from the live checks, CI reliability, and parked data-safety work. None is scheduled yet.

---
