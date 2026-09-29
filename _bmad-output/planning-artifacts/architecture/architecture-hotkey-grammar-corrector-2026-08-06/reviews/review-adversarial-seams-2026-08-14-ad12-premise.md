# Adversarial seams review — ARCHITECTURE-SPINE.md, AD-12 premise + Seed pass (2026-08-14)

**Lens.** Attack the spine as an adversary: construct two units one level down that each obey every
AD to the letter yet still build incompatibly — clashing shared-data shapes, two owners of one
entity, conflicting state-mutation paths. Every pair found is a hole to close with a new or
tightened AD.

**Target.** `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
(status `final`, `updated: 2026-08-14`).

**Scope.** A narrow *Update*: `git diff` on the spine is exactly two hunks.

1. **AD-12 Rule bullet 4** (`:327`) — the premise of the message contract was loosened from an
   absolute to a scoped one: "because the screen appends nothing, every `HotkeyUnavailable` …" →
   "the screen renders it verbatim and appends nothing **about the fallback**, and the one line it
   does add states only that no ownership regime is known until something is registered — so every
   `HotkeyUnavailable` this codebase produces must itself end by naming the tray menu …".
2. **Structural Seed** (`:491`) — added
   `unconfigured_correction_provider.dart  # registry miss -> providerUnavailable (AD-15, AD-19)`
   under `infrastructure/correction/`.

The attack is concentrated on the seam bullet 4 governs (adapter author × settings-screen
maintainer × tray owner) and on the ownership question the new Seed line raises.

**Grounding.** Every claim below is checked against the shipped tree, not inferred from the spine:
`lib/src/ui/settings/hotkey_status_view.dart`, `lib/src/ui/settings/settings_screen.dart`,
`lib/src/application/settings_controller.dart`,
`lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`,
`lib/src/infrastructure/hotkey/x11_global_hotkey.dart`,
`lib/src/infrastructure/system/daemon_startup.dart`, `lib/main.dart`,
`lib/src/domain/hotkey/hotkey_bind_outcome.dart`, `lib/src/domain/tray/tray_port.dart`,
`lib/src/infrastructure/tray/tray_manager_tray.dart`,
`lib/src/infrastructure/correction/active_correction.dart`,
`lib/src/infrastructure/correction/provider_registry.dart`,
`lib/src/infrastructure/correction/unconfigured_correction_provider.dart`,
`test/ui/settings/settings_screen_hotkey_test.dart`.

**Verdict.** **Amendment 1 fixes the falsehood it was written to fix and immediately opens three
new seams**; amendment 2 is factually harmless but mis-assigns ownership of the decision it
documents. The tray-naming obligation on adapter messages survives intact and is honoured by every
shipped producer — that half is clean. What does not survive is the *screen* half: the bullet now
forbids the screen from naming the desktop in one sentence and canonises a line that names the
desktop in the next; it asserts a regime is unknowable on paths where a regime was known and is
still printed verbatim one line above; and it says nothing about the tray, whose unavailable flag
has exactly one writer and three producers.

Six findings: three high, two medium, one low. **One is a BLOCKER for the human** (S-3): closing it
honestly requires either a spine rule the shipped tray does not satisfy, or a change under `lib/`,
both of which this pass is barred from.

---

## S-1 (high, autofixable) — bullet 4 forbids in sentence 2 exactly what it mandates in sentence 3

**Where.** `ARCHITECTURE-SPINE.md:327`, against `hotkey_status_view.dart:126-131`.

The bullet now reads, in order:

> The settings screen renders `HotkeyUnavailable.message` **verbatim** and **claims nothing about
> the desktop or about who owns the binding** … The contract is therefore on the **message**: the
> screen renders it verbatim and appends nothing **about the fallback**, and **the one line it does
> add states only that no ownership regime is known until something is registered**.

The line it is describing is, verbatim in the tree:

```dart
// hotkey_status_view.dart:126-131
List<String> _unavailableLines(String message) => [
  message,
  'Whether this app or your desktop would own the shortcut is not known '
      'until one is registered.',
];
```

That line **names the desktop** and **is a claim about who owns the binding** — a negative one, but
the sentence enumerates both candidate owners by name. Sentence 2 says the screen makes no such
claim; sentence 3 says it makes exactly one, and blesses it.

**The two units.** Screen maintainer A reads sentence 2 as the operative prohibition ("claims
nothing about the desktop") and deletes the second line as a breach — the message alone then stands,
which is what the *old* text described and what the widget's own class doc still says ("nothing is
appended to it", `hotkey_status_view.dart:96-99`, now stale). Screen maintainer B reads sentence 3
as the operative permission and keeps it. Both cite AD-12 bullet 4. One of them deletes a line that
`test/ui/settings/settings_screen_hotkey_test.dart:322` pins, so the disagreement surfaces as a red
test with two people each holding a spine quotation.

**Why it matters beyond wording.** The prohibition was written as though the screen authored the
text on this path. It does not: on the unavailable branch **100% of the primary text is the
adapter's**, rendered verbatim — and shipped adapter messages *do* name the desktop
(`_noDesktopPortal`: "no desktop portal is running on this session…",
`wayland_portal_global_hotkey.dart:1268`; the revoke message at `:862-868`: "your desktop no longer
holds this shortcut…"). So "the settings screen claims nothing about the desktop" is already false
of the shipped screen in the ordinary Wayland case, and the amendment did not notice because it only
audited the *appended* line.

**Close it by tightening AD-12 bullet 4** (no AD added, no CAP touched): make the prohibition
explicitly about text the screen *originates*, and state the message-side permission that shipped
code relies on. E.g.: "the screen originates no desktop fact and no regime of its own; the message
may state what a specific backend observed, and the screen renders that verbatim."

---

## S-2 (high, autofixable in the spine; code follow-up must be deferred) — "no ownership regime is known" is false on the two paths where a regime *was* known, and the screen contradicts itself on screen

**Where.** `ARCHITECTURE-SPINE.md:327` vs AD-9's `bindingChanges` (`:288`, `:298`), AD-10 (`:306`),
and the Ratified Divergence (`:620`); against `wayland_portal_global_hotkey.dart:854-878` and
`settings_controller.dart:68`, `:283`.

The Wayland adapter, obeying AD-9 and AD-12's "*after the fact* — a binding the compositor later
revokes", delivers a revocation on `bindingChanges` as:

```dart
// wayland_portal_global_hotkey.dart:862-868
_pushBindingChange(const HotkeyUnavailable(
  message: 'your desktop no longer holds this shortcut, so the hotkey is '
      'inactive — the tray menu still opens the panel',
));
```

`SettingsController` routes it straight into `SettingsState.hotkeyBindOutcome`
(`settings_controller.dart:68`), and `HotkeyStatusView` renders, in this order:

```
your desktop no longer holds this shortcut, so the hotkey is inactive — the tray menu still opens the panel
Whether this app or your desktop would own the shortcut is not known until one is registered.
```

Line 1 names the desktop as the holder. Line 2, now canonised by the spine, says which side would
own it is not known. **The screen contradicts itself in adjacent sentences**, and it does so on the
one path CAP-12's second half exists for.

It is worse against the surrounding ADs than against itself:

- **AD-10** requires the screen to present `authority == compositor` as a *preference* regime, and
  the user was looking at exactly that sentence ("Your desktop owns this shortcut…",
  `hotkey_status_view.dart:159-163`) one frame earlier — the bind succeeded, then the compositor
  revoked. The regime was known, displayed, and is not in doubt; only the *shortcut* went away.
- **The Ratified Divergence** (`:620`) states flatly that "the settings screen shows which regime is
  active". After a revocation the screen stops showing it for the rest of the session, and the spine
  now says that is correct.
- **AD-12's own second Rule bullet** distinguishes "nothing is held" from "something else is held".
  Bullet 4's added line collapses a third case — *a regime is known and nothing is held* — into "no
  regime is known".

**The two units.** The Wayland-adapter author (AD-9 + AD-12: revocation is a value on
`bindingChanges`, message names the desktop and ends with the tray) and the settings-screen
maintainer (AD-12 bullet 4: the added line says no regime is known) each obey to the letter and
jointly ship a screen that denies the fact it just printed.

**Root constraint, and why the obvious fix is barred.** `HotkeyUnavailable` carries `message` and
nothing else, and its declaration is verbatim-fixed (`:274-277`). The screen therefore *cannot*
consult an authority on this branch — carrying the last-known regime on the value would change a
frozen declaration's fields, which is out of bounds for this pass.

**Close it by tightening AD-12 bullet 4** to scope the claim to the outcome rather than to the
world: "…the one line it does add claims **no regime of its own**, because this outcome carries
none". That is a wording change inside an existing AD, permitted here. Note the consequence for the
human: the shipped sentence over-claims relative to the tightened rule ("not known **until one is
registered**" is a claim about the future), and `lib/` is frozen this pass — so the code half is a
deferred-work item, not something this review can land.

---

## S-3 (high) — **BLOCKER**: bullet 4 gives the tray a state with three producers and one writer

**Where.** `ARCHITECTURE-SPINE.md:327` first sentence, against `daemon_startup.dart:184`,
`settings_controller.dart:415-445`, `wayland_portal_global_hotkey.dart:862`,
`tray_port.dart:14`.

Bullet 4 opens: "The tray carries a **neutral** unavailable state (`setHotkeyUnavailable(bool)`) and
no per-cause text." It never says **who pushes it, or when**. The amendment reworked the screen half
of this bullet in detail and left the tray half at one sentence, which makes the asymmetry newly
conspicuous.

Measured on the tree: `setHotkeyUnavailable` has **exactly one caller in `lib/`** —
`DaemonStartup.bindHotkey` (`daemon_startup.dart:184`), the *startup* bind. Meanwhile three units
produce a `HotkeyUnavailable`:

| Producer | Reaches the settings screen | Reaches the tray flag |
| --- | --- | --- |
| `DaemonStartup.bindHotkey` (startup) | yes (`main.dart:239`) | **yes** |
| `SettingsController.changeHotkey` → `_bind` (`settings_controller.dart:432`) | yes | **no** |
| `bindingChanges` (compositor revoke, `wayland…:862`) | yes | **no** |

So: a user changes the hotkey in settings, the bind fails, the settings screen degrades correctly —
and the tray icon keeps saying the hotkey is fine for the rest of the daemon's life. Same for a
compositor revocation. AD-12's headline is "**Any** refusal to hold the hotkey degrades **visibly**";
on two of three paths it degrades on one surface and lies on the other, and the tray is the surface
AD-12 nominates as the fallback the user is supposed to reach for.

**The two units.** The settings-controller author (AD-13: every mutation goes through the store; the
controller holds `ConfigStore`, `GlobalHotkey`, `Logger` and deliberately **no** `TrayPort` — AD-1
would not forbid it, but nothing asks for it) and the tray owner (AD-12: the tray carries a neutral
unavailable state, pushed where the bind happens). Both obey. Neither owns "keep the tray current
after startup".

**Why this is a BLOCKER rather than an autofix.** Every honest closure is out of bounds for this
pass:

- Tightening bullet 4 to "every producer of a `HotkeyUnavailable` drives **both** surfaces" is a
  permitted wording change — but it would make a `status: final` brownfield spine assert something
  the shipped tree does not do, which is the currency failure this review series has been closing,
  not opening. It also needs a deferred-work entry, and `deferred-work.md` is not editable here.
- Making it true requires code under `lib/` (a tray push from `SettingsController` or a single
  outcome sink), which is barred.
- Scoping the sentence to "the tray reflects the **startup** bind only" is honest about the code but
  contradicts AD-12's own *Prevents* ("**any** path where a backend will not hold the combination")
  and the *after-the-fact* refusal it explicitly enumerates.

**Recommendation for the human:** ratify one of (a) spine states the invariant + a DW entry for the
code, or (b) spine records the current scope as a known gap in the same shape as the
StatusNotifier-host hole already carried in bullet 5. Do not let it stay unassigned.

---

## S-4 (medium, autofixable) — "the one line it does add" is a description, not a cap; the old text was a cap

**Where.** `ARCHITECTURE-SPINE.md:327`.

The replaced text — "because the screen appends nothing" — was an **absolute** from which the
message obligation followed necessarily. The replacement is a conjunction of a scoped prohibition
("appends nothing **about the fallback**") and a **descriptive** clause about one existing line
("**the one line it does add** states only that…"). Nothing in the amended sentence says *at most
one* line, and nothing constrains the content of a second one beyond the two named prohibitions
(fallback, and — per S-1's tangle — desktop/ownership).

**The two units.** Settings-screen maintainer adds a third `Text` under the unavailable branch that
is neither about the fallback nor about a regime: "You requested Ctrl+Shift+G.", or "See the log for
details.", or a Retry affordance's caption. Every letter of bullet 4 is satisfied. Meanwhile the
adapter author wrote a self-contained sentence on the premise — stated in the same bullet — that the
screen adds essentially nothing, and in particular wrote a message that already ends with the way
out. The result is a screen whose three lines re-litigate each other, and, in the "You requested…"
case, a near-miss of AD-10's own prohibition on presenting a preference where an effective binding
belongs (`hotkey_status_view.dart:170-176` reasons this out for the `HotkeyBound` branch; nothing
covers the unavailable branch).

**Close it** by restoring a cap: "…renders it verbatim, appends **exactly one line of its own**, and
that line …". One word of tightening inside an existing AD.

---

## S-5 (medium, autofixable) — the new Seed line puts the "provider could not be built" decision under the two ADs that do not own it, and invites a second owner

**Where.** `ARCHITECTURE-SPINE.md:491`, against `active_correction.dart:73-107`,
`provider_registry.dart:31-35`, `unconfigured_correction_provider.dart`.

The added line reads:

```text
unconfigured_correction_provider.dart       # registry miss -> providerUnavailable (AD-15, AD-19)
```

Two problems, both about ownership.

**(a) The trigger is under-described — there are two, and only one is a registry miss.**
`ActiveCorrection._providerFor` degrades on **two** distinct conditions:

```dart
// active_correction.dart:78-92
final providerConfig = config.providers[preset.providerId];
if (providerConfig == null) {            // never reaches the registry at all
  return _unavailable(logger, preset, 'is not described in the config file', …);
}
final provider = registry.create(preset.providerId, providerConfig);
if (provider == null) {                   // the registry miss
  return _unavailable(logger, preset, 'is not a provider this build ships', …);
}
```

The undescribed-provider path is a **config** failure and never touches `ProviderRegistry`. A reader
building to the Seed line implements the registry miss and leaves the config miss to whoever finds
it — and the two produce different user-visible sentences, so the divergence is not cosmetic.

**(b) The owner named is not the owner.** The decision is made in `active_correction.dart` — the
line *immediately above* in the same Seed block, cited `(AD-5, AD-17)`. `ProviderRegistry.create`
returns `null` on purpose and says so:

```dart
// provider_registry.dart:33-35
/// null means "no such provider id" — the caller decides how to surface
/// a config that names a provider this build does not ship.
```

Citing the fallback file to **AD-15** points a registry author at the registry: the natural reading
of "registry miss → providerUnavailable (AD-15)" is that `create()` should return an
`UnconfiguredCorrectionProvider` instead of `null`. **That is the two-owners pair.** If they do, one
of two things happens: `ActiveCorrection`'s `provider == null` branch becomes dead code and its
`logger.error` (which carries `preset_id` **and** `provider_id`) silently stops firing, or both wrap
and the message the panel renders depends on which layer got there first. AD-15's own text supports
neither — its three integration steps describe a lookup table, not a degradation policy.

**AD-19 is the wrong general authority too.** AD-19 is titled "the shipped default adapter hosts the
Claude Agent SDK out of process"; its "must not prevent the daemon from starting" rule
(`:390`) is scoped to *that adapter's* missing interpreter. The provider-agnostic principle the file
actually embodies — a config that names something unbuildable degrades rather than failing startup —
is closest to **AD-13** ("a malformed file yields defaults plus a surfaced warning — never a failed
startup for a resident daemon"), and the `_activePreset` fallback in the same file is squarely
AD-13's. So the "what happens when a provider cannot be built" decision currently has **three
candidate owners in the spine (AD-5 / AD-13 / AD-15) and cites a fourth (AD-19)**.

**Close it inside the Seed comment**, which is neither a CAP row nor a frozen declaration:

```text
unconfigured_correction_provider.dart       # unresolvable provider id -> providerUnavailable;
                                            # chosen in active_correction.dart (AD-5, AD-13, AD-19)
```

**Do not** promote this to a general invariant here: a binding "any unbuildable provider degrades to
`providerUnavailable` and never blocks startup" rule has no home in AD-1..AD-19 and would need a new
AD — out of bounds. Flag it to the human if they want the rule to bind rather than to be documented.

---

## S-6 (low, autofixable) — a `CorrectionProvider` that is not a provider, in the directory AD-15 reserves for providers

**Where.** `ARCHITECTURE-SPINE.md:491` against AD-15 (`:346-354`) and the Naming convention (`:414`).

`UnconfiguredCorrectionProvider` implements `CorrectionProvider` and now appears in the Seed
directly under `infrastructure/correction/`. AD-15 says integrating a provider is "**exactly these
three steps, and no others**" (one file under `infrastructure/correction/`, one config entry, one
registry entry) and that "**every** provider ships with a fake". This one has no config entry, no
registry entry, no `<provider>/` subdirectory, and no fake — correctly, because it is a null object
rather than a provider. Naming reinforces the confusion: the convention is `<Technology><Port>`
(`X11GlobalHotkey`, `ClaudeAgentSdkCorrectionProvider`); `Unconfigured` is a state, not a technology.

**The two units.** A future author who needs a second null object (a disabled-by-config provider, a
kill-switch stand-in) has no rule saying where it lives, and AD-15's letter tells them it needs a
config entry, a registry entry and a fake. Low, because nothing breaks today.

**Close it** with two words in the same Seed comment — "null object, never registered" — which also
pre-empts the S-5(b) misreading.

---

## Attacks that failed (checked, cleared)

These were the loosening hypotheses the lens brief named. Each was pushed and each holds.

- **"Does 'appends nothing *about the fallback*' license the screen to append a fallback hint after
  all?"** — **No.** The scoped clause is a prohibition, not a permission, and it is narrower than the
  old blanket "appends nothing" in coverage but *identical in force* on the fallback specifically.
  A screen that printed "use the tray menu" now breaches an explicit clause rather than an implied
  one. The amendment strengthened this, not weakened it.
- **"Can the screen silently drop the tray sentence?"** — **No.** "renders `HotkeyUnavailable.message`
  **verbatim**" survives untouched; truncating the message's final clause is not verbatim rendering.
- **"Is the tray-naming obligation still unambiguously binding on every adapter author?"** — **Yes.**
  The clause is stated as a `must` on "every `HotkeyUnavailable` **this codebase produces**", which
  correctly reaches past adapters to the two non-adapter producers (`settings_controller.dart:432`,
  `daemon_startup.dart:222`). Verified on the tree: **every** shipped construction site ends by
  naming the tray menu — `x11_global_hotkey.dart:121,143,179,268,305`;
  `wayland_portal_global_hotkey.dart:480,529,544,865,1064,1164,1174,1182,1195` and the constants at
  `:1268,1272,1276`; `settings_controller.dart:435`; `daemon_startup.dart:225`. No producer is
  currently in breach. The inferential "so" that introduces the obligation weakened (its premise is
  now a conjunction, one conjunct of which is a description — see S-4), but the obligation itself is
  imperative and does not dissolve with its premise.
- **"Does the amendment reopen the AD-9 doc-comment contradiction carried from the previous pass?"**
  — **No.** Bullet 4 does not touch which value is returned; the second Rule bullet still owns that,
  unchanged in this diff.
- **"Does the second amendment breach AD-15's transport-privacy rule?"**
  (`unconfigured_correction_provider.dart` sits outside a `<provider>/` directory) — **No.** The file
  names no process, `Uri`, port, key, header, SDK type or model id; its imports are three domain
  files. AD-1 and AD-15's privacy clause are both clean.
- **Frozen-declaration drift.** Neither hunk touches an AD-2 or AD-9 declaration block; `HotkeyUnavailable`
  still carries `message` and nothing else in both spine and tree.

---

## Constraint compliance for this pass

| Constraint | Status |
| --- | --- |
| No AD added / retired / renumbered / reused | Held — every fix proposed above is a wording tightening inside AD-12, or a Seed comment. S-5's general rule and S-3's cross-surface rule are **reported, not proposed**. |
| Exactly 13 CAP rows, unreworded | Held — no finding touches the map. |
| Verbatim-fixed types byte-identical | Held — S-2 explicitly declines the `authority`-on-`HotkeyUnavailable` fix for this reason. |
| No Dart under `lib/` changed | Held — S-2 and S-3's code halves are named as deferred, not applied. |
| `SPEC.md` / `deferred-work.md` untouched | Held. |
| No `claude_agent_sdk` / Flutter version restated | Held — no finding introduces a version number. |
| Only this review file written | Held. |

---

## Summary

| # | Severity | Seam | Autofixable within constraints |
| --- | --- | --- | --- |
| S-1 | high | AD-12 bullet 4 forbids desktop/ownership claims and mandates a line making both | Yes — reword to "originates no regime of its own" |
| S-2 | high | "no ownership regime is known" vs AD-9 `bindingChanges` / AD-10 / Ratified Divergence; screen denies the line above it | Spine: yes (scope to the outcome). Code: deferred, `lib/` frozen |
| S-3 | high | **BLOCKER** — tray unavailable flag has three producers and one writer; settings-bind and revoke never reach it | No — needs a rule the tree fails, or `lib/` |
| S-4 | medium | "the one line it does add" describes rather than caps; a second added line is licensed | Yes — "appends exactly one line of its own" |
| S-5 | medium | Seed cites AD-15/AD-19 for a decision AD-5 owns; invites `ProviderRegistry` to become a second owner | Yes — recite the Seed comment to `(AD-5, AD-13, AD-19)` + name `active_correction.dart` |
| S-6 | low | A non-registered `CorrectionProvider` in the directory AD-15's three steps describe | Yes — "null object, never registered" in the same comment |

---

## Disposition — 2026-09-26

This is a disposition of the historical findings, not a replacement verdict. The regenerated spine and current source were inspected; no compositor or tray host was exercised for this note.

| Finding | Status | Current evidence and limit |
| --- | --- | --- |
| S-1 | Superseded | AD-12 now explicitly permits a cause-specific screen line and requires the adapter message to remain verbatim. `HotkeyStatusView._unavailableLines` selects that line by `HotkeyUnavailableCause`, then renders the message and one ownership line (`lib/src/ui/settings/hotkey_status_view.dart`). The old blanket prohibition is gone. |
| S-2 | Still open in the screen copy | AD-9 now carries a `revoked` cause and AD-12 says no **active** regime is claimed, but `_unavailableLines` still appends “Whether this app or your desktop would own the shortcut is not known until one is registered” after `_causeLine(revoked)` says the desktop took it away. The source therefore still loses the distinction between a known former owner and no current binding. |
| S-3 | Accepted; source-level closure | `DaemonGraph.build` subscribes to every `SettingsState` change and `_publishHotkeyStatus` queues `TrayPort.setHotkeyStatus` calls (`lib/src/application/composition/daemon_graph.dart`); startup still publishes its bind result through `DaemonStartup.bindHotkey`. This covers refused settings rebinds and backend changes by inspection. A live StatusNotifier host was not observed; AD-12 still records that separate host gap. |
| S-4 | Superseded | AD-12 now specifies a cause line, the adapter message, and one ownership line rather than the former “one line” premise. `_unavailableLines` implements those three positions; the message position uses a tray fallback only for blank adapter text. |
| S-5 | Accepted; source-level closure | AD-5 and AD-17 now name `ActiveCorrection` as pair-resolution owner, and AD-15 names its unknown-ID degradation. `ActiveCorrection._providerFor` handles both an absent config description and a registry miss; `ProviderRegistry.create` remains a nullable lookup (`lib/src/infrastructure/correction/active_correction.dart`, `provider_registry.dart`). |
| S-6 | Superseded | AD-15 explicitly names `UnconfiguredCorrectionProvider` for an unregistered provider ID and forbids selecting a fallback provider. The current Structural Seed includes the null object, while `ProviderRegistry` registers only selectable adapters. The old ambiguity about treating the null object as a selectable provider is removed. |

The report's checked-clear attacks retain their historical status. Its original six-finding verdict remains above.

## Post-plan closure — 2026-09-26

**S-2 is now closed by source and existing widget-test evidence.** Commit `9514e54` makes `HotkeyStatusView._unavailableStatusLine` return “No shortcut is currently in effect” for `revoked`, while `noBackend` and `keyRefused` retain the ownership-unknown line (`lib/src/ui/settings/hotkey_status_view.dart:174-182`). The earlier S-2 disposition accurately records what was open when 02-22 committed; it is not a claim about this later source. The owner reports the existing settings widget suite passed 20/20 and analyzer was clean for that fix. No live compositor revocation was observed here.
