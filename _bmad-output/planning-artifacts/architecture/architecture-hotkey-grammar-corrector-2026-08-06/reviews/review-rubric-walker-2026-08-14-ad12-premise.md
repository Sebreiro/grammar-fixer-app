# Rubric-walker review — ARCHITECTURE-SPINE.md, Update pass (AD-12 premise + Seed row)

- **Target:** `/workspace/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
- **Pass:** Update, 2026-08-14. Two hunks (`git diff` on the spine: 2 insertions, 1 deletion).
- **Lens:** rubric walker — the good-spine checklist, weighted onto the two amended clauses and everything adjacent they could have falsified.
- **Verified against:** the shipped tree under `/workspace/lib/` (read, not assumed), plus the earlier reviews in this directory for carry/duplicate status.

## Verdict

**Pass on both amendments — both are true against the shipped code, and the AD-12 conclusion still holds.** I re-derived every message-producing path rather than trusting the claim. The residue is not in what the two hunks assert but in what they leave under-pinned or now read against: one **high** finding (a divergence point the new Seed row names that no AD Rule decides), two **medium** wording collisions the amendment newly sharpened, and two carried **BLOCKER**s that the binding constraints forbid fixing in this pass.

---

## Amendment 1 — AD-12's fourth Rule bullet (`ARCHITECTURE-SPINE.md:327`)

### Is the amended premise TRUE against the shipped widget?

**Yes, on both halves.** `lib/src/ui/settings/hotkey_status_view.dart:126-130`:

```dart
  List<String> _unavailableLines(String message) => [
    message,
    'Whether this app or your desktop would own the shortcut is not known '
        'until one is registered.',
  ];
```

- *"renders it verbatim"* — the adapter's `message` is element 0, unmodified, un-prefixed, un-suffixed. `build` (`:52-60`) maps `HotkeyUnavailable(:final message)` straight into it, and each line is rendered as its own `Text`, so nothing is concatenated onto the message either.
- *"appends nothing **about the fallback**"* — TRUE. The second string says nothing about the tray, the panel, or any way in. `grep -rn "tray" lib/src/ui/` returns only doc comments plus `daemon_home.dart`; no rendered string in `ui/` names the tray.
- *"the one line it does add states only that no ownership regime is known until something is registered"* — TRUE and exactly scoped: it is *one* line (the list is fixed-length two), and its content is precisely an ownership-regime disclaimer keyed to "until one is registered".

The pre-amendment premise ("because the screen appends nothing") was indeed false against this file. The amendment repairs it without weakening the contract it derives.

### Does the CONCLUSION still hold — does every `HotkeyUnavailable` in `lib/` end by naming the tray menu?

**Yes. All 15 production sites checked, no exception.** Enumerated by `grep -rn "HotkeyUnavailable" lib/`, then each traced to the literal it carries — including the indirect helpers the brief names:

| Site | Message ends with |
| --- | --- |
| `x11_global_hotkey.dart:176` (grab refused) | "…so the hotkey is inactive — the tray menu still opens the panel" |
| `x11_global_hotkey.dart:245` via `_refusedBeforeBackend`, caller `:117` (key not in catalogue) | "…the tray menu still opens the panel" |
| `x11_global_hotkey.dart:245` via `_refusedBeforeBackend`, caller `:137` (keypad/ISO variant) | "…so the hotkey is inactive and the tray menu still opens the panel" |
| `x11_global_hotkey.dart:265` `_shutDownDuringBind` | "…the tray menu still opens the panel" |
| `x11_global_hotkey.dart:302` (release refused, nothing held) | "…the tray menu still opens the panel" |
| `wayland_portal_global_hotkey.dart:247`, `:263` (`_deadConnection` latch, sourced from `_recordDeadConnection` → `_messageFor`) | inherits `_messageFor`'s arms, all four of which end in the tray sentence (`:1164`, `:1174`, `_noDesktopPortal`, `:1182`), as does `_unclassified` (`:1195`) |
| `wayland_portal_global_hotkey.dart:269` `_unusableBusAddress` (`:1276`) | "…the tray menu still opens the panel" |
| `wayland_portal_global_hotkey.dart:347` via `_PortalRefusal` — thrown at `:479`, `:526`, `:541`, and `_malformedReply` (`:1272`) | every one ends in the tray sentence |
| `wayland_portal_global_hotkey.dart:356` `_messageFor(error)` | as above |
| `wayland_portal_global_hotkey.dart:862` (`ShortcutsChanged` drop, pushed on `bindingChanges`) | "…so the hotkey is inactive — the tray menu still opens the panel" |
| `wayland_portal_global_hotkey.dart:948` `_recordDeadConnection` | as `_messageFor` |
| `wayland_portal_global_hotkey.dart:1061` `_shutDownDuringBind` | "…the tray menu still opens the panel" |
| `settings_controller.dart:432` (adapter threw — AD-12 breach backstop) | "…the tray menu still opens the panel" |
| `daemon_startup.dart:222` (startup twin of the same backstop) | "…the tray menu still opens the panel" |

Note the coverage this exercise incidentally proves: the `bindingChanges`-delivered value (`:862`) reaches the same widget through the same `switch` arm, so the "every `HotkeyUnavailable` this codebase produces" phrasing — rather than "every one `bind()` returns" — is the right scope and is satisfied. `main.dart` constructs none (its two hits are comments).

### Did the amendment falsify anything adjacent?

Three places were checked; one is clean, two are findings.

- **AD-9 / AD-10 (`:302-306`)** — clean. AD-10's "a returned `HotkeyUnavailable` is rendered as AD-12's degradation" is unchanged in meaning and still matches `settings_screen.dart:141-146`, where `_authority` is `null` on the `HotkeyUnavailable()` arm, and `hotkey_status_view.dart:58`.
- **AD-12's own bullet, first half** — see **F-2**.
- **Ratified Divergence (`:620`)** — see **F-3**.

---

## Amendment 2 — the new Structural Seed row (`ARCHITECTURE-SPINE.md:491`)

### Does the file exist, and is the description right?

**Both yes.** `lib/src/infrastructure/correction/unconfigured_correction_provider.dart` ships. `UnconfiguredCorrectionProvider` is an `async*` `CorrectionProvider` that yields exactly one `CorrectionFailed(kind: providerUnavailable, message: …)` and closes — which is the AD-3 sequence and the AD-4 single-subscription stream, both cited in its own doc.

"registry miss → providerUnavailable" is the **reachable** path, and correctly so. Tracing `active_correction.dart`, there are two construction sites:

1. `config.providers[preset.providerId] == null` — *not* a registry miss, but a backstop: `json_config_store.dart:119-121` already rejects a config whose preset names a provider absent from `providers`, so this branch only fires on a `ConfigStore` contract breach (the file's own doc calls it that).
2. `registry.create(id, cfg) == null` — the genuine registry miss (`provider_registry.dart`: `_factories[id]?.call(config)` returns null for an unshipped id). This is the path a real user config reaches, since `ConfigStore` validates the cross-reference to `providers` but not membership of the shipped factory table.

So the Seed comment names the live path. **AD-15, AD-19** are the right citations: AD-15 owns the map lookup, AD-19 owns "must not prevent the daemon from starting… the tray, panel, and settings all have to remain reachable for the user to fix the setting". Column alignment matches its neighbours; one public type per file (Consistency Conventions) holds.

What the row does *not* do is make the behaviour normative — **F-1**.

---

## Findings

### F-1 — HIGH — the divergence the new row names is decided only in a Seed comment, not by any Rule. *Autofixable.*

`ARCHITECTURE-SPINE.md:491`, against `ARCHITECTURE-SPINE.md:342-354` (AD-15) and `:390` (AD-19).

"A config that names a provider id this build does not ship" is a real divergence point for the level below, and one with at least three defensible answers a second implementer could pick: fail startup, silently substitute the shipped provider, or degrade to a first-correction `providerUnavailable`. The shipped code picks the third. After this pass the spine *mentions* that answer — but only in a `#` comment inside the Structural Seed, which is illustrative scaffolding, not an enforceable Rule.

The two Rules that look like they cover it do not. AD-19's non-blocking rule is scoped by its own words to the **executable path**: "the executable path is a config value… A missing or non-executable host yields `CorrectionFailed(providerUnavailable, …)` on the first correction; it must not prevent the daemon from starting." AD-15's three-step integration rule says to register the provider in the table, and says nothing about a lookup that misses. AD-13 arguably points the other way — "a malformed file yields defaults plus a surfaced warning" — which is exactly the competing answer (substitute the default) an implementer could derive.

Before this pass the gap was invisible; the amendment surfaced it in the one place that cannot close it. This is the rubric's "every dimension the altitude owns is decided, deferred, or an open question" clause failing on a dimension the pass itself just touched.

**Fix (within constraints):** add one Rule bullet to the **existing** AD-15 — no AD added, retired, renumbered or reused; no CAP row touched; no verbatim type touched. Something of the shape: *"**Rule — a registry miss degrades, it does not fail.** A `providerId` the table does not hold resolves to a `CorrectionProvider` that reports `CorrectionFailed(providerUnavailable, …)` on its first correction and then closes; it never blocks startup, because the settings surface the user needs in order to fix the id is reachable only from a daemon that came up. The resolution and the logging live in `active_correction.dart` (AD-17's fourth part), so it is reachable by a test."*

### F-2 — MEDIUM — AD-12's bullet now argues against its own opening clause. *Autofixable.*

`ARCHITECTURE-SPINE.md:327`.

The bullet still opens "The settings screen renders `HotkeyUnavailable.message` **verbatim** and **claims nothing about the desktop or about who owns the binding**", and now closes by conceding that the screen *does* add a line — one whose text is "Whether this **app** or your **desktop** would **own** the shortcut is not known until one is registered." The two halves are reconcilable (denying knowledge of a regime is not asserting one), and the amendment plainly intends that reading. But the reconciliation lives in the reader's head, not on the page, and the first clause is the one written in the imperative register an implementer will lift as the contract.

The concrete risk is narrow and real: a second settings surface, or a rewrite of this one, reads "claims nothing about the desktop" and deletes the disclaimer line as a breach — losing the property `hotkey_status_view.dart:116-125` explicitly says "must not regress" ("no regime claimed, **stated rather than silent**"). The amendment made this collision sharper than it was, because before this pass the bullet never acknowledged a second line existed at all.

**Fix (within constraints):** reword the opening clause of the same bullet so it forbids the assertion rather than the subject — e.g. "…renders `HotkeyUnavailable.message` **verbatim** and **asserts** no desktop, no compositor, and no owner for the binding: …". Confined to AD-12's fourth bullet; touches no AD id, no CAP row, no verbatim type, no version number.

### F-3 — MEDIUM — the Ratified Divergence's regime claim is now unqualified against a spine that states the opposite two hundred lines up. *Autofixable, with a caveat for the human.*

`ARCHITECTURE-SPINE.md:620` vs `:327`.

"…and the settings screen **shows which regime is active** alongside the effective combination read back from the portal (AD-10, AD-11)."

Measured: `settings_screen.dart:141-146` yields `_authority == null` on the `HotkeyUnavailable` arm, and `hotkey_status_view.dart` prints no regime sentence on that arm — by design, and per AD-1, since the display server is a fact the `ui` ring cannot see. So the claim holds on the `HotkeyBound` path and is false on the `HotkeyUnavailable` path. That was already true before this pass; what changed is that AD-12 now says so **in the spine's own voice** ("the one line it does add states only that no ownership regime is known"), so the spine now contradicts itself on the page rather than only contradicting the tree. On a wlroots session — AD-12's headline case, and the case the Ratified Divergence exists to describe — the unavailable path is the *common* one, so the unqualified sentence is wrong exactly where a reader will most rely on it.

**Fix:** a scoping qualifier, not a rewrite — "…and the settings screen shows which regime is active **whenever a backend has answered with `HotkeyBound`**, alongside the effective combination read back from the portal (AD-10, AD-11); when no backend holds the shortcut, AD-12 governs and no regime is claimed."

**Caveat for the human:** this sentence sits under "**Ratified by the user on 2026-08-06**". The proposed edit narrows a *ratified* statement. I read it as making explicit what the ratification always meant rather than changing it, so I class it autofixable — but if the reviewer treats the ratified paragraph as frozen text, this becomes a BLOCKER and should go back to the user with the qualifier as the proposal.

### F-4 — LOW (BLOCKER, carried) — CAP-5's row cites a path that does not exist, and the Seed disagrees with it.

`ARCHITECTURE-SPINE.md:597` says `infrastructure/correction/register_tagged_stream_parser.dart`. The file ships at `lib/src/infrastructure/correction/**claude_agent_sdk/**register_tagged_stream_parser.dart`, which is what the Seed (`:495`) has, and what AD-16's "this is a **per-adapter** choice, not a system-wide one" requires. The map's path implies a shared, system-wide parser — the exact structure AD-16 forbids.

Adjacent to this pass in the sense that both hunks are path-and-message accuracy work, and the Seed half of the disagreement is in the block this pass edited. **Not autofixable here:** the only remedy is rewording a CAP row, which the binding constraints forbid. **Already reported** by the currency-check lens (`review-currency-check-2026-08-14.md:198-200`) and the adversarial-seams lens (`review-adversarial-seams-2026-08-14.md:174`) on this date; it is still open. Recommend the human lift the CAP-row freeze for this one token.

### F-5 — LOW (BLOCKER, no Dart may change) — the widget's own doc now contradicts the code the spine just ratified.

`hotkey_status_view.dart:96-99`: "The adapter's [message] is rendered as it stands and **nothing is appended to it**". The method three lines below appends a second line. The spine's amendment is now the *more* accurate of the two descriptions — which is the right outcome, but it leaves the code's doc as the stale copy, and a reader who trusts the doc will re-derive the false premise this pass just removed from the spine.

**Not autofixable:** `lib/` is frozen for this pass. Recommend filing it as a one-line doc-comment correction for the next dev pass (the sentence wants "nothing is appended to **the message itself**, and the one line that follows it names no regime").

### F-6 — LOW (informational, no fix proposed) — the Seed is now exhaustive in one directory and a sample in its own subdirectory.

The amendment completed `infrastructure/correction/` (all three top-level files now listed) while `claude_agent_sdk/` still omits shipped `sidecar_host_paths.dart`, and the tree at large has ~25 shipped files no Seed row names (`hotkey_registrar.dart`, `hotkey_key_catalogue.dart`, `default_app_config.dart`, `panel_window.dart`, `tray_icon.dart`, …). A Seed is scaffolding, not an inventory, so this is not a defect on its own terms — flagged only because selectively completing one directory invites the next reader to treat the block as an inventory and "fix" the rest. Either add `sidecar_host_paths.dart` for local symmetry or leave the block alone; both are defensible, neither is required.

---

## Checklist walk (items not already covered above)

| Checklist item | Result |
| --- | --- |
| Fixes the real divergence points for the level below | **One gap** — F-1. Everything else the two hunks touch is pinned. |
| Every AD's Rule enforceable and prevents its stated divergence | AD-12's amended bullet is now enforceable *and* true — the contract lands on the adapter's message, and all 15 shipped messages satisfy it. The absence of a mechanism line for "never throws" is the prior pass's carried low finding (`review-rubric-walker-2026-08-14-amendments.md`), unchanged here. |
| Nothing under Deferred could let two units diverge | Deferred section untouched and still clean; note that F-1's dimension is *not* in Deferred — it is undeclared, which is why it is a finding rather than an accepted deferral. |
| Named tech verified-current | Untouched by this pass. The `claude_agent_sdk` and Flutter cells still cite rather than restate — `grep` confirms no version number was reintroduced by either hunk. Constraint honoured. |
| Ratifies rather than contradicts the brownfield codebase | The amendments *improve* this (that is their point). Residual contradictions: F-4 (map path), F-5 (code doc, other direction). |
| Covers the driving spec's capabilities | 13 CAP rows, unchanged, `binds` frontmatter still lists the same 13. The new Seed row's subject is CAP-8 territory; CAP-8's row (`:599`) does not name the new file, but the "Lives in" column has never been exhaustive and correcting it would be a forbidden reword — no finding raised. |
| Every dimension the altitude owns decided/deferred/open | **F-1** is the one exception. |

## Mechanical invariants

| Invariant | Result |
| --- | --- |
| 19 `### AD-` headings, ids AD-1..AD-19 monotonic | Pass |
| Exactly 13 `\| CAP-` rows, none added/removed/reworded | Pass — diff touches no map line |
| Verbatim-fixed type declarations byte-identical | Pass — diff touches no fenced Dart block |
| No `lib/` Dart, `SPEC.md`, or `deferred-work.md` change | Pass — diff is spine-only |
| `claude_agent_sdk` / Flutter version numbers absent | Pass |
| Seed row alignment and one-type-per-file convention | Pass |

## Disposition — 2026-09-26

The 2026-08-14 review body and verdict above are preserved. These outcomes compare its findings with the regenerated spine and current source; they are not a new compositor observation.

| Finding | Current disposition | Evidence and limit |
| --- | --- | --- |
| F-1, unknown provider ID governed only by Seed | **Accepted, resolved.** | AD-15 now explicitly requires an unknown registered-adapter ID to log a warning and use `UnconfiguredCorrectionProvider`; `lib/src/infrastructure/correction/active_correction.dart` and `unconfigured_correction_provider.dart` implement that value path. |
| F-2, AD-12's unavailable-screen premise | **Superseded; a current wording mismatch remains open.** | AD-12 now distinguishes cause, message, and ownership, but its surface Rule says Settings renders the message followed by one ownership line (`ARCHITECTURE-SPINE.md`, AD-12). `lib/src/ui/settings/hotkey_status_view.dart:164-182` renders a cause line, the verbatim message or blank-message fallback, then a status line. The old two-line premise is obsolete; the three-line contract still needs a generated AD-12 wording correction. |
| F-3, unqualified ratified regime statement | **Accepted, resolved.** | The spine's Ratified Divergence now scopes effective-binding wording to a held shortcut and says AD-12 governs when none is held. `HotkeyStatusView` does not claim an active regime on `HotkeyUnavailable`. The portal's localized description is not a machine-readable effective combination. |
| F-4, CAP-5 path | **Accepted, superseded in location.** | The current CAP-5 row points to shipped `lib/src/infrastructure/correction/shared/register_tagged_stream_parser.dart`. Phase 2 moved the parser; AD-16 still limits the tagged format to adapters that use it. |
| F-5, stale widget doc | **Accepted, resolved.** | `hotkey_status_view.dart:139-163` now explains the message, cause line, blank-message fallback, and appended status line. Its prior claim that nothing follows the message is gone. |
| F-6, Seed exhaustiveness ambiguity | **Rejected as a defect, now clearer.** | The current Structural Seed calls itself the tracked file map and lists `sidecar_host_paths.dart` and the shipped files then missing. Its status is explicit; the 2026-08-14 concern was informational, with no required fix. |

This disposition does not close the separate AD-12 presentation mismatch in F-2 by reinterpretation: a follow-up must update the generated Rule or the shipped surface after a source-grounded decision.

### Closure follow-up — 2026-09-26

**F-2's later presentation mismatch is resolved in the checked-in wording.** The Codex BMAD regeneration at `606ba50` changed AD-12's surface Rule to name Settings' cause line, verbatim message or blank-message fallback, and current-status line (`ARCHITECTURE-SPINE.md`, AD-12). Those are the three elements in `lib/src/ui/settings/hotkey_status_view.dart:164-182`; `revoked` gets its distinct status line. The rule also distinguishes startup's boolean tray notice from later typed, cause-specific `HotkeyTrayStatus` menu lines. This note updates the disposition above; it does not alter the 2026-08-14 review or claim a native session was observed.

The related `noBackend` copy now says global shortcuts are unavailable **to this app right now**, rather than asserting that the desktop has no global-shortcut capability (`21c26bd`, `hotkey_status_view.dart` and `hotkey_bind_outcome.dart`). The existing widget assertions were updated in that commit. The missing StatusNotifier host remains an unobserved operational limit, not a closure from this wording change.
