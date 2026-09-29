# Rubric Walker — ARCHITECTURE-SPINE.md

**Lens:** good-spine checklist (`references/reviewer-gate.md`), run against the 2026-08-14 Update pass.
**Target:** `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
**Date:** 2026-08-14

## Verdict

The refresh is honest and mostly well-aimed — every factual claim it added checks out against shipped code, and it closed a real pre-existing contradiction — but it amended three ADs in place without re-reading the ADs those amendments re-home, leaving two invariants (AD-5's resolver, AD-12's refusal rule) stating something the rest of the document and the code no longer agree with. **Pass with two high findings to resolve before handoff.**

## Constraint compliance (the brief's five hard limits)

| Constraint | Result |
| --- | --- |
| 19 ADs, AD-1..AD-19, none renumbered / retired / added / reused | **PASS** — 19 `### AD-` headings; the id set is exactly AD-1..AD-19; the diff touches no heading. |
| Exactly 13 CAP rows, none added, removed, or reworded | **PARTIAL** — 13 rows, no additions or removals, capability text intact; but two rows' *Lives in* cells changed. See L-6. |
| AD-2 / AD-9 verbatim blocks: declared fields and constructors unchanged; only shipped members reflected | **PASS** — see below. |
| No `claude_agent_sdk` or Flutter version number restated anywhere | **PASS** — grep over the whole document returns no `3.44.x` and no `0.2.132`; the pin-renegotiation paragraph's "unsatisfiable on Flutter 3.44.8" correctly became "on the pinned Flutter stable". |
| Frontmatter `status: final`, `updated: '2026-08-14'` | **PASS** |

On the verbatim blocks specifically, verified against the tree rather than taken on trust:

- **AD-2** — the code block is byte-identical to the previous revision; the refresh added only a trailing Rule. That Rule's claims are exactly right: `Suggestion` (`suggestion.dart:13`), `Preset` (`preset.dart:18`) and `CorrectionFailed` (`correction_event.dart:35`) each carry `operator==`/`hashCode` over precisely their declared fields, and `SuggestionDelta`/`CorrectionCompleted` carry none. Nothing over-claimed.
- **AD-9** — `HotkeyRegistration` and `HotkeyBinding` keep their declared fields and constructors unchanged. `HotkeyBindOutcome`, `HotkeyBound`, `HotkeyUnavailable`, the `bindingChanges` member, and `bind()`'s widened `Future<HotkeyBindOutcome>` return are all shipped verbatim in `lib/src/domain/hotkey/global_hotkey.dart` and `hotkey_bind_outcome.dart` — reflection, not invention. The set-comparison claim holds too: `HotkeyBinding` uses `setEquals`/`setHash` from `domain/collection_equality.dart`, pure Dart, so no AD-1 breach was introduced by the reflection.

One nuance worth recording rather than scoring: `global_hotkey.dart`'s own doc comment says adding `bindingChanges` was "recorded in the deferred-work ledger and the story's Spec Change Log **rather than hand-edited into the spine**." This pass hand-edited it into the spine. That is the right call — the brief authorised reflecting shipped members, and leaving the port's declared surface stale was worse — but the code comment now describes a state of affairs that is no longer true and will mislead the next reader of that file.

## Findings

### H-1 — Who resolves the active `(CorrectionProvider, Preset)` pair now has two answers in one document

**Severity: high.** `ARCHITECTURE-SPINE.md:162` (AD-5, untouched), `:369` (AD-17 part 4, new), `:591` (CAP-8 row).

AD-5's Rule still reads: "`main.dart` reads `AppConfig`, **resolves the single active `(CorrectionProvider, Preset)` pair**, and injects it." AD-17's new part 4 reads: "`infrastructure/correction/active_correction.dart` — AD-5's `(CorrectionProvider, Preset)` pair resolution." CAP-8's map row still lists `main.dart`. Three statements, two answers.

Shipped code sides with AD-17: `ActiveCorrection.resolve(...)` lives in `lib/src/infrastructure/correction/active_correction.dart:33` and does the whole job — preset lookup, provider lookup, the unconfigured fallback — while `lib/main.dart` only reads `startup.active` back out (`main.dart:403`).

This matters more than a stale filename because AD-5 is the AD whose *Prevents* is "a `switch (providerId)` appearing inside the correction pipeline", and whose enforceable content is "**nothing below the composition root** selects a provider". After AD-17's edit, the composition root is four parts and two of them are under `lib/src/infrastructure/` — so "below the composition root" no longer maps onto a directory boundary, and AD-5 names the one file that no longer does the resolving. A builder trying to obey AD-5 literally would move resolution back into `main.dart`, undoing AD-17's stated reason for the split (that `main()` is reachable by no test).

**Fix:** amend AD-5's Rule to name the composition root and cite AD-17 part 4, rather than `main.dart`. CAP-8's row is frozen by the brief — flag it for the next unfrozen pass rather than editing it here.

### H-2 — AD-12's Rule is still portal-only, but AD-9's refreshed block made `HotkeyUnavailable` the shared refusal value for both adapters

**Severity: high.** `ARCHITECTURE-SPINE.md:262` and `:274` (AD-9, new), `:325` (AD-12, untouched).

AD-9's block now declares `HotkeyUnavailable` with the comment "Unavailability is a value, never a throw **(AD-12)**", and `bind()` returns the sealed outcome for every adapter. But AD-12's Rule, untouched, covers only "a failed `CreateSession` or `BindShortcuts`" — a Wayland portal sequence — and its *Prevents* names only wlroots compositors with no GlobalShortcuts implementation.

The X11 adapter already resolves four non-portal cases to `HotkeyUnavailable` — unrepresentable key, backend refusal, a key the backend would bind wrongly, and a disposed adapter (`lib/src/infrastructure/hotkey/x11_global_hotkey.dart:176,245,265,302`) — and cites AD-12 as its authority at lines 21–23 and 235. `hotkey_key_catalogue.dart` likewise cites "AD-12's 'an unrepresentable key is a value, not a throw'". **That rule is not in AD-12.** The code obeys an invariant the spine does not state.

So AD-12's Rule fails the checklist's core test — it does not prevent its stated divergence once the type is general. A second X11-family adapter could throw on an unrepresentable key and be fully spine-compliant, and AD-9 announces exactly such an adapter is coming (DW-39's `dart:ffi` registrar). This is a divergence the spine exists to close, and the refresh walked past it while generalising the type one AD above.

**Fix:** widen AD-12's Rule to "no `GlobalHotkey` adapter throws from `bind()` — every refusal, portal or otherwise, resolves to `HotkeyUnavailable`", keeping the wlroots case as the worked example and the visible-degradation requirement unchanged. This is an amendment in place; no new AD needed.

### M-3 — The paradigm diagram and the ring table now contradict AD-17's four-part composition root, in a ring nothing enforces

**Severity: medium.** `ARCHITECTURE-SPINE.md:46`, `:54` (diagram), `:39-44` (ring table), `:365-370` (AD-17, new).

Two layers here, the second the real one.

*Surface:* the paradigm prose now says "It is not one file — AD-17 fixes its **four parts**", but the mermaid `ROOT` node names two of them ("composition root — main.dart + application/composition"), and the graph draws `ROOT --> INF`, placing the root outside infrastructure. AD-17 parts 3 and 4 are inside `lib/src/infrastructure/`. The sentence and the diagram it introduces disagree about the same object.

*Structural:* the ring table's infrastructure row says "Never imports: **application**, ui". That is the one ring rule AD-1's own Rule text never states — AD-1 states only the domain rule and the application rule — and the one `test/architecture/ad1_import_rule_test.dart` never checks; its docstring is explicit: "Three rings are checked here" (domain, application, ui). So the ring table declares four constraints and the mandatory mechanical gate covers three.

The refresh moved startup order, teardown order, and provider/preset resolution — code whose entire job is to know both sides — into exactly the unenforced ring. AD-17's third Rule carefully explains why `main.dart` sits *outside* AD-1's gate, but says nothing about parts 3 and 4 sitting *inside* a ring whose outward-import ban has no gate. That `daemon_lifecycle.dart:20` carries a hand-written comment about what "the spine forbids" is what an unenforced rule looks like in practice.

No live violation today: nothing under `lib/src/infrastructure/` imports `application/` (verified by grep — the only hit is that comment). This is a mechanism gap the refresh widened, not a break.

**Fix:** either extend `ad1_import_rule_test.dart` with the fourth scan and say so in AD-1's Mechanism note, or state in AD-17 that parts 3 and 4 hold *infrastructure-and-domain* knowledge only and that anything needing application types belongs in `application/composition/`. Also correct the `ROOT` node label so the diagram and the "four parts" sentence agree.

### M-4 — AD-9's new serialization paragraph is a second copy of a code comment, at the wrong altitude

**Severity: medium.** `ARCHITECTURE-SPINE.md:300`.

One line ("each adapter serializes it to its own syntax … neither syntax appears above infrastructure") became ~150 words of vendor internals: `hotkey_manager`'s C plugin, `gtk_accelerator_name`, a GTK 3 probe result, USB HID usages, and a named infrastructure file. Every word of it is accurate — it is also transplanted near-verbatim from `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart`'s doc comment, which already holds it and is where it is verifiable.

That is the exact pattern this same refresh argues against three sections later: "A number written here as well would be a second writable copy of one fact, free to disagree with the copy that actually ships." The pass applied that principle to two version pins and violated it for an implementation rationale in the same commit. A probe result fixed at spine level will rot the first time `hotkey_manager` or GTK changes, and the spine is the copy nobody runs.

SKILL.md is direct about the altitude: "Record decisions, not rationale (rationale lives in the memlog)." The decision here is one sentence — the domain type is translated inside infrastructure and neither backend syntax rises above the port. The rest is why.

Two smaller defects inside the same paragraph: it closes "**This row** changes when DW-39 … lands", but it is no longer a row — the table cell it inherited that phrasing from is gone; and it hard-codes `infrastructure/hotkey/hotkey_key_catalogue.dart` as the serialization site while the Structural Seed tree lists no such file, so the document names it in one section and omits it in another.

**Fix:** cut to the invariant plus a one-clause pointer ("the X11 adapter's serialization lives in `hotkey_key_catalogue.dart`, which documents why it is not an accelerator string"), and drop "This row".

### M-5 — DW-39 is load-bearing in two sections and resolvable from neither

**Severity: medium.** `ARCHITECTURE-SPINE.md:300`, `:576`, and the Deferred section by omission.

The refresh made two spine-level claims conditional on DW-39: AD-9's serialization "changes when DW-39's `dart:ffi` keybinder registrar lands", and `libkeybinder-3.0-0` "rejoins the degrading set" once DW-39 `dlopen`s it. Neither has an entry under Deferred, a revisit condition, or a pointer to where DW ids live. A build substrate that conditions an invariant on a work item its reader cannot resolve has a dangling dependency.

The libkeybinder correction itself is the most valuable thing in this refresh — it replaces a false blanket claim ("Each missing dependency degrades one capability visibly and never blocks startup") with the truth that one dependency is a `DT_NEEDED` hard link that kills the process before `main()`. But that makes it the system's **only** hard startup-failure mode, and it is recorded in the operational envelope, which SKILL.md classifies as seed — "true at cold-start, owned by the code once it exists" — rather than under an AD or Deferred. The one failure mode no AD governs is sitting in the section the code is allowed to take ownership of.

**Fix:** add a Deferred entry for the DW-39 transition naming both consequences and its revisit condition, so the two conditional claims resolve inside the document.

### L-6 — Two frozen CAP rows were reworded, against the brief

**Severity: low.** `ARCHITECTURE-SPINE.md:588` (CAP-4), `:594` (CAP-11).

Both rows gained `application/correction_controller.dart` in the *Lives in* column. Both additions are factually right — key selection and per-suggestion copy do go through the controller, not straight from the widget. But the brief froze all 13 rows: "none added, removed, or **reworded**." Row count, capability text, governing-AD columns and the frontmatter `binds` list (13 entries, matching) are all intact, so the breach is cosmetic and improves accuracy. Recording it because the brief made it a finding by construction, not because the edit is wrong.

### L-7 — Stack still stamped "Verified current on 2026-08-06" after a 2026-08-14 edit to that table

**Severity: low.** `ARCHITECTURE-SPINE.md:424`.

The refresh rewrote two Stack rows, added a paragraph, and edited the pin-renegotiation note, without touching the currency date above them. The checklist item is "named tech is verified-current"; the table now asserts a verification date eight days older than its own last edit, so a reader cannot tell whether the citations were checked on the 14th or inherited unexamined from the 6th. Either re-verify and restamp, or say explicitly that the 08-06 verification still stands and only the two cited rows changed shape.

## What the refresh got right

Recorded so the next pass does not undo it:

- **The citation mechanism is real, not a promise.** `test/architecture/sidecar_pin_drift_test.dart` genuinely resolves both cited paths, fails when a citation does not exist, fails when the cited file pins nothing parseable, and — the load-bearing half — returns null for a cell that has reverted to a bare version, with an explicit test for that case. The spine's claim about it is accurate in every clause.
- **It closed a pre-existing contradiction.** Consistency Conventions already listed `HotkeyUnavailable` as a modelled error value for a type AD-9 did not declare. The refresh made the type real in the spine, so that row now refers to something.
- **AD-10's amendment is precise.** Rendering "the `HotkeyRegistration` inside the returned `HotkeyBound`" and routing `ShortcutsChanged` onto `bindingChanges` is exactly the seam the old `Future<HotkeyRegistration>` could not express, and AD-9's second new Rule states why in one sentence — the right length for that call.
- **`lint_spine.py` is clean.** One low finding: `'{sv}'` at line 317, a false positive on the D-Bus signature `a{sv}` in AD-11's `Activated` signal, pre-existing and untouched by this pass. The two citation cells pass the `version_pin` check (non-empty, no template token), so the citation format does not trip the gate's own deterministic half.
- **All three mermaid blocks are valid.** The flowchart's new `ROOT` label introduces no bracket, paren or quote characters; the sequence and ER diagrams are untouched. (M-3 is about what the label *says*, not whether it parses.)

## Dimension sweep

Every dimension this altitude owns is decided, deferred, or open — none silent. Boundary rules (AD-1, AD-17), state mutation (Consistency Conventions, AD-18), shared-data ownership (AD-7, AD-13), error model (AD-3, AD-12, Errors row), concurrency and cancellation (AD-4), process topology (AD-14, AD-19), and the operational/environmental envelope are all present; the envelope in particular is the dimension domain-focused spines usually skip, and this one is now more truthful than it was. The gaps found above are contradictions and under-reach, not absences.

## Disposition — 2026-09-26

The original “Pass with two high findings” remains the 2026-08-14 verdict. The following classifies those findings against the regenerated 2026-09-26 spine and shipped source, without rerunning its checklist or observing a desktop session.

| Finding | Current disposition | Evidence and limit |
| --- | --- | --- |
| H-1, active pair has two resolvers | **Accepted, resolved.** | AD-5 and AD-17 both name `infrastructure/correction/active_correction.dart`; `lib/src/infrastructure/correction/active_correction.dart` performs the registry lookup, and the CAP-8 row names that file. |
| H-2, AD-12 portal-only refusal rule | **Accepted, resolved in scope.** | AD-12's heading, *Prevents*, and Rule now cover both adapters and failures after a successful bind. AD-9 defines the value and `bindingChanges` channels; the newer wording mismatch in the presentation Rule is recorded in this review set's AD-12-premise and amendments dispositions. |
| M-3, four-part diagram and infrastructure import enforcement | **Accepted; diagram resolved, enforcement still open.** | The root diagram now names four parts and AD-17 constrains its infrastructure parts to domain/infrastructure knowledge. AD-1 and Deferred explicitly say `test/architecture/ad1_import_rule_test.dart` does not scan infrastructure imports; the missing mechanical check is still open under the phase's no-new-gate restriction. |
| M-4, keybinder-specific serialization prose | **Superseded.** | AD-9 now states the backend-independent translation rule briefly and identifies the shipped libX11 FFI path. The old GTK/keybinder paragraph and “This row” wording are absent. |
| M-5, dangling DW-39 and loader risk | **Superseded.** | `hotkey_manager`/libkeybinder no longer ship, and AD-9, the Stack, and Operational envelope describe the libX11 FFI registrar. The old conditional DW-39 transition is no longer the current design. |
| L-6, CAP-row edit outside that review brief | **Accepted as a historical process finding; current rows resolved.** | The 2026-08-14 brief's freeze was breached as recorded above; that past fact cannot be undone. The present CAP-4/CAP-11 rows point at shipped `lib/src/application/correction_controller.dart`, and the current spine's 13-row map is an authorized regenerated snapshot. |
| L-7, old Stack date | **Accepted, resolved for repository pins.** | The Stack now says it was reconciled to checked-in manifests on 2026-09-26 and disclaims an upstream latest-version check. |

The old note about `global_hotkey.dart` saying the spine had not yet been updated is **superseded** by AD-9's regeneration; the current source comment should still be read against its own date. No upstream package currency or native compositor behavior is established by this appendix.

### Closure follow-up — 2026-09-26

The newer AD-12 presentation mismatch mentioned in H-2's disposition is now closed by the generated surface Rule (`606ba50`, `ARCHITECTURE-SPINE.md`, AD-12), the neutral startup `TrayPort` comment (`89b4487`), and the `noBackend` wording correction (`21c26bd`). The rule matches the checked-in three-line Settings view and later typed, cause-specific tray menu status. This does not change H-2's historical finding or close the missing infrastructure-import gate in M-3. No native compositor or StatusNotifier-host behavior was observed here.
