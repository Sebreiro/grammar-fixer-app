# Phase 2: Daemon Truth — Settings, Panel, Teardown, Provider & Spine - Discussion Log

> **Audit trail only.** Downstream planning, research and execution use `02-CONTEXT.md`; this log records the alternatives discussed.

**Date:** 2026-09-24  
**Phase:** 02-Daemon Truth — Settings, Panel, Teardown, Provider & Spine  
**Areas discussed:** Panel size and placement; copy and selection cues; hotkey status in the tray; OpenAI-compatible provider targets.

---

## Panel size and placement

| Question | Options presented | User's choice |
|----------|-------------------|---------------|
| Where should the panel appear when summoned? | 1. Center of active display; 2. Near pointer; 3. Top center of active display; 4. Other | **1. Center of active display** |
| How large should it open? | 1. About 640 × 520 logical pixels; 2. About 500 × 400; 3. About 800 × 600; 4. Other | **1. About 640 × 520** |
| Which display is active on multiple monitors? | 1. Display containing pointer; 2. Display containing focused application; 3. Primary display; 4. Other | **1. Pointer display** |
| How should space be divided? | 1. Current 40% editor / 60% suggestions; 2. Equal; 3. Editor gets more; 4. Other | **1. Current split** |

**Notes:** The phase spec already requires shrink-to-fit on small displays and a startup fallback when geometry is unreadable. The user's desired pointer-display placement may require preparation while the panel is hidden because the hotkey path is limited to toggling the warm window.

---

## Copy and selection cues

| Question | Options presented | User's choice |
|----------|-------------------|---------------|
| Where should copy status appear? | 1. On affected card; 2. Shared line above suggestions; 3. Banner at panel bottom; 4. Other | **1. On affected card** |
| How long should “Copied” remain? | 1. Until next copy or correction; 2. Briefly; 3. Until panel hides; 4. Other | **1. Until next copy or correction** |
| What appears during a pending write? | 1. “Copying…” beside button; 2. Spinner replacing Copy icon; 3. Status below card text; 4. Other | **1 and 2. Spinner plus “Copying…”** |
| How should selected variant stand out? | 1. Highlight and check mark; 2. Border and highlight; 3. Current color highlight; 4. Other | **1. Highlight and check mark** |

**Notes:** The user combined two compatible pending-write options. Copy buttons remain usable so a later request can take priority. The locked spec says only the last copy request gets final feedback and card selection never copies.

---

## Hotkey status in the tray

| Question | Options presented | User's choice |
|----------|-------------------|---------------|
| How much cause detail should the menu show when unavailable? | 1. Specific cause and tray remedy in one line; 2. Existing generic line; 3. Short unavailable label; 4. Other | **1. Specific cause and remedy** |
| How long should a refused rebind be mentioned if the old binding still works? | 1. Until next attempt; 2. Until menu closes; 3. Only while Settings shows refusal; 4. Other | **3. Track Settings error** |
| What happens when availability is restored? | 1. Normal icon and warning removed immediately; 2. Brief restored line; 3. Persistent active-shortcut line; 4. Other | **1. Normal state immediately** |
| Where should the status line sit? | 1. Below “Open the panel”; 2. Above it; 3. Above “Quit”; 4. Other | **1. Below “Open the panel”** |

**Notes:** An old working binding remains visibly available after a refused replacement. No desktop notification was proposed; Phase 1 already chose quiet, on-look discovery of shortcut loss.

---

## OpenAI-compatible provider targets

| Question | Options presented | User's choice |
|----------|-------------------|---------------|
| Which two endpoints matter most? | 1. OpenAI API + local Ollama; 2. OpenAI API + self-hosted vLLM; 3. Two named endpoints; 4. Other | **1. OpenAI + Ollama** |
| Where should API-key source appear? | 1. Always-visible line under provider settings; 2. Badge beside provider; 3. Collapsible details; 4. Other | **1. Always-visible line** |
| How should a config-file plaintext key be flagged? | 1. Warning below source line; 2. “Plaintext” in source line; 3. Information icon; 4. Other | **1. Warning below** |
| When should missing Base URL or Model be flagged? | 1. Mark field Required but allow save; 2. Warning above fields; 3. Explain on first correction; 4. Other | **Other: mark Required and forbid saving incomplete provider settings** |
| What does that save guard block? | 1. OpenAI-compatible provider settings only; 2. All Settings changes; 3. Other | **1. Provider settings only** |

**Notes:** The user clarified that Settings must have explicit editable Base URL and Model fields. An incomplete provider form cannot be saved in-app. Incomplete hand-edited config still starts and produces the actionable inline failure required by `02-SPEC.md`. The Model field updates a prompt-and-model preset, not an independent provider model id.

---

## The agent's Discretion

The user did not delegate any of the four discussed areas. Technical mechanism choices remain with research and planning under the locked specs and architecture.

## Deferred Ideas

None.
