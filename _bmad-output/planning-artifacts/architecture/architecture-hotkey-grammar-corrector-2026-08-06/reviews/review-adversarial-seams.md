# Reviewer lens: adversarial seams

**Question:** construct two units one level down that each obey every AD to the letter yet still build incompatibly. Every pair is a hole.

**Verdict:** six pairs constructed; five were real holes and are now closed, one was already covered.

## Closed — AD-3 extended: delta semantics

Adapter author emits cumulative text per tick (`"Hello"`, `"Hello world"`); panel author concatenates. Renders `HelloHello world`. Both obeyed the original AD-3, which only said "deltas then one terminal event".
**Fix:** AD-3 now states `textDelta` is an incremental fragment, never cumulative, and that deltas may interleave across registers.

## Closed — AD-3 extended: completion authority

Panel author treats accumulated deltas as final and ignores `CorrectionCompleted.suggestions`; repository author persists `CorrectionCompleted.suggestions`. UI and history then disagree about the same correction — which quietly poisons CAP-7's analytics dataset.
**Fix:** AD-3 now states `CorrectionCompleted.suggestions` is authoritative and replaces accumulated delta text for both display and persistence.

## Closed — AD-4 rewritten: does hiding cancel?

This was a genuine **contradiction between two capabilities**, not just an under-specification. AD-4's original *Prevents* clause said "a hidden panel … leaving an orphaned subprocess running", implying hide cancels. But CAP-7 requires every correction be retained, and cancelling before the terminal event means no record. One unit honours AD-4 and cancels; another honours CAP-7 and lets it run.
**Fix:** AD-4 now enumerates exactly three cancellation triggers — Retry, a new correction, shutdown — and states explicitly that hiding does **not** cancel, grounded in CAP-14's assumption that hiding discards nothing.

## Closed — AD-7 extended: who writes history

`CorrectionController` persists at the terminal event (per the sequence diagram); a provider-adapter author also persists, reasoning that the adapter is closest to the completion. A diagram is not a rule, so both obeyed AD-7. Result: every correction double-counted.
**Fix:** AD-7 now names `CorrectionController` the sole caller of `CorrectionRepository.save`, once, at the terminal event.

## Closed — new AD-18: panel session lifecycle

Three independent divergences in one seam:
1. **Re-seeding.** One unit seeds the editor from the clipboard only on first show; another re-seeds on every show. CAP-2 says "current clipboard text content", which favours re-seeding — but nothing said so.
2. **Retry identity.** CAP-13 says Retry re-runs "on the same input text". One unit re-reads the editor at retry time; another replays the submitted string. They differ the moment the user types after a failure.
3. **Selection vs. copy.** SPEC's assumption that these are distinct acts lived only in the SPEC, not in an enforceable rule.

**Fix:** AD-18 fixes all three — every `show()` starts a fresh session and re-seeds; the controller captures the submitted string and Retry replays that captured string; selection highlights and only the copy button transfers.

## Not a hole — hotkey binding authority

Attempted: an X11 adapter author and a Wayland adapter author return different things from `bind()`. Already prevented by AD-10's `HotkeyRegistration` + `BindingAuthority`, which forces both to state what is actually in effect and who owns it. This was the pair the original draft anticipated.

## Coverage check

Every structural dimension the feature altitude owns is decided, deferred, or an open question. The operational envelope (single binary, runtime system dependencies, autostart, `.desktop` requirement, no staging tier) is covered in Structural Seed rather than left silent. The one open question — CAP-12 versus Wayland portal semantics — is surfaced to the user as a SPEC-level decision rather than resolved in the architecture.

---

## Disposition — 2026-09-26

The earlier “closed” labels above describe that review pass. The regenerated spine and current source support the following current readings; this is source inspection, not a native runtime observation.

| Historical seam | Status | Current anchor |
| --- | --- | --- |
| Delta semantics and completion authority | Accepted | AD-3 still requires incremental `SuggestionDelta.textDelta` and makes `CorrectionCompleted.suggestions` authoritative; `CorrectionController` handles the terminal suggestions and saves through its repository port (`lib/src/application/correction_controller.dart`). |
| Hide versus cancellation | Accepted | AD-4 still limits cancellation to Retry, new correction, and shutdown. AD-18 now distinguishes dismissal from iconification/focus loss for editor sessions; `CorrectionController._onVisibilityChanged` preserves an active run across hide. |
| Single history writer | Accepted | AD-7 still names `CorrectionController` sole caller of `CorrectionRepository.save`; the current `_save` call remains in that controller. |
| AD-18 session, Retry, selection/copy | Superseded in part | AD-18 now seeds only a summon **after dismissal**; returning after iconification or focus loss preserves the editor and reads no clipboard. Its submitted-text Retry and select-versus-copy rules remain, reflected in `CorrectionController` and `CorrectionPanel`. The original “every show re-seeds” wording above is no longer the rule. |
| Hotkey authority “not a hole” | Accepted with a known limit | AD-9/AD-10 now carry authority, a cached status, and the portal's localized wording. The Wayland portal reports no structured effective binding, so AD-10 and Deferred leave the SPEC's literal effective-combination criterion unproven. |
| Coverage check | Superseded | The current spine explicitly defers Wayland signal timing, tray-host absence, infrastructure import enforcement, and packaging format. The old statement that only one open question remained is historical, not a present completeness claim. |
