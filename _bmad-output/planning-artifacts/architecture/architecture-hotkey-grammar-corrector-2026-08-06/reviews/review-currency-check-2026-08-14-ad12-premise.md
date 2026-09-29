# Currency / reality-check review — the 2026-08-14 AD-12 premise + Seed-row Update pass

**Target:** `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
**Lens:** currency / reality-check — was every committed decision web-researched or reality-checked rather than asserted; are named versions and technologies still current; is anything out of date that was not confirmed against the web, the existing project, or the current starter.
**Project shape:** brownfield, shipped code. The two amended clauses are claims *about the shipped code*, so they were reality-checked against the tree rather than the web. Upstream (web) checks were run only where a claim's home is outside this repo.
**Scope of the pass under review:** two hunks — AD-12's fourth Rule bullet (premise correction) and one new Structural Seed row.
**Date:** 2026-08-14

Everything below is backed by a command run or a file read in this session. Where I could not substantiate something I say so rather than asserting it.

---

## Verdict

**Both amended clauses are true of the shipped tree — I re-derived each one independently rather than trusting the memlog, and all three sub-claims of the AD-12 premise and all four claims of the new Seed row hold.** The Stack table also still reconciles row-for-row against `pubspec.lock`. What the pass does not do is finish the job it started: it corrected the Seed by exactly one file while **twelve** other shipped files remain missing from the same `infrastructure/` block, two of them files the spine's own normative prose cites by name — including a file named in the sibling bullet of the very Rule this pass amended. That is the finding with live consequence. Everything else is small, and one Stack-note gap carried from the previous pass is still unfiled and still open.

---

## Region 1 — AD-12's fourth Rule bullet ("what the surfaces may claim")

### The amendment

Before → after (from `git diff` on the spine):

> ~~The contract is therefore on the **message**: because the screen appends nothing, every `HotkeyUnavailable` this codebase produces must itself end by naming the tray menu as the way in that still works.~~
>
> The contract is therefore on the **message**: the screen renders it verbatim and appends nothing **about the fallback**, and the one line it does add states only that no ownership regime is known until something is registered — so every `HotkeyUnavailable` this codebase produces must itself end by naming the tray menu as the way in that still works.

Three checkable claims. All three verified.

### Claim 1 — the settings screen renders `HotkeyUnavailable.message` verbatim ✅ CONFIRMED

`/workspace/lib/src/ui/settings/hotkey_status_view.dart:52-60` dispatches `HotkeyUnavailable(:final message) => _unavailableLines(message)`, and `_unavailableLines` (`:126-130`) puts `message` in the list unmodified — no interpolation, no prefix, no wrapper:

```dart
  List<String> _unavailableLines(String message) => [
    message,
    'Whether this app or your desktop would own the shortcut is not known '
        'until one is registered.',
  ];
```

Each entry is rendered as its own `Text` (`:84-88`). Nothing edits the string on the way.

### Claim 2 — appends nothing *about the fallback* ✅ CONFIRMED

The one added line says nothing about the tray, the panel, or any way in. The widget's doc comment states the same property and the same reason (`:96-102`): "every `HotkeyUnavailable` this codebase produces already ends by naming the tray as the way in that still works, and a screen that added the sentence itself printed it twice." The amendment's narrowing — *nothing about the fallback*, rather than the old *nothing at all* — is exactly the widget's own claim. The old premise was flatly false against `_unavailableLines`, which returns two entries; the correction is right and the correction's direction is right.

### Claim 3 — the one line it adds states only that no ownership regime is known ✅ CONFIRMED

Exactly one line is added, and it states only ownership-unknown: "Whether this app or your desktop would own the shortcut is not known until one is registered." No desktop claim, no compositor claim, no cause. The doc comment above it (`:116-125`) makes the property explicit and marks it as the part that must not regress (AD-1: the display server is a fact the `ui` ring cannot see; the SPEC's Ratified Divergence forbids guessing "this app owns it").

### Claim 4 — every `HotkeyUnavailable` this codebase produces ends by naming the tray menu ✅ CONFIRMED, by exhaustive sweep

I did not trust the memlog's count. I enumerated every construction site and every string that can reach one, including the indirect helpers named in the brief.

`grep -rn "HotkeyUnavailable" lib/` gives these **producing** sites (the rest are type references, doc comments, or `setHotkeyUnavailable` on the tray port, which is a `bool` and carries no text):

**`/workspace/lib/src/infrastructure/hotkey/x11_global_hotkey.dart` — 5 distinct messages**

| Site | Ends with |
|---|---|
| `:117` → `_refusedBeforeBackend` (unrepresentable key) | `…so the hotkey is inactive — the tray menu still opens the panel` |
| `:137` → `_refusedBeforeBackend` (keypad/terminal variant) | `…so the hotkey is inactive and the tray menu still opens the panel` |
| `:176` (grab refused) | `…the tray menu still opens the panel` |
| `:265` `_shutDownDuringBind` | `…the tray menu still opens the panel` |
| `:302` `_releaseBeforeRebinding`, nothing held | `…the tray menu still opens the panel` |

`_refusedBeforeBackend` (`:239-246`) is a pass-through — it either returns `HotkeyUnavailable(message: message)` with the caller's string or returns `HotkeyBound` naming the surviving combination. Both callers' strings end by naming the tray, so the helper introduces no untrayed message.

**`/workspace/lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`**

Every `HotkeyUnavailable` here takes its text from one of: a module-level `const String`, `_messageFor`, `_recordDeadConnection`, or a `_PortalRefusal`. I checked all four sources.

- Module-level constants (`:1268-1280`): `_noDesktopPortal`, `_malformedReply`, `_unusableBusAddress` — all three end `the tray menu still opens the panel`.
- `_messageFor` (`:1159-1186`) — five arms: `SocketException`, `OSError || DBusClosedException`, `DBusServiceUnknownException || DBusUnknownObjectException` (→ `_noDesktopPortal`), `DBusUnknownMethodException || DBusUnknownInterfaceException`, and `_unclassified` (`:1188-1197`). All five end `the tray menu still opens the panel`.
- `_recordDeadConnection` (`:1144-1149`) returns `_messageFor(error)` verbatim and latches it into `_deadConnection`, which is what `:247` and `:263` return. No new text.
- Every `_PortalRefusal` throw (`:437, 478, 487, 493, 526, 535, 540, 665, 667, 674, 740, 750, 1073, 1083`) carries either one of the constants, `_messageFor`/`_recordDeadConnection`, or one of three inline strings: the `CreateSession` refusal (`:478`), the `BindShortcuts` non-grant (`:526`, ends `…the hotkey is inactive; the tray menu still opens the panel`), and the app-id discard (`:540`, ends `…and the tray menu still opens the panel`). All name the tray last. `:347` returns `refusal.message` unchanged.
- Two more direct constructions: the `ShortcutsChanged` revocation (`:862`) and the post-dispose sentence (`:1061`). Both end `the tray menu still opens the panel`.

**`/workspace/lib/src/application/settings_controller.dart:432`** — the throw-guard's replacement outcome ends `…the tray menu still opens the panel`.
**`/workspace/lib/src/infrastructure/system/daemon_startup.dart:222`** — the startup twin, same sentence.

**No exception found.** The clause's conclusion is true of the tree as it stands today.

Also spot-checked while I was here: the bullet's unchanged "this state is reached from four different places" still holds — X11 adapter, portal adapter, `SettingsController._bind`'s catch, `DaemonStartup.requestBinding`'s catch. Four.

### F5 — LOW — the conclusion is true and unenforced, and that is already filed

The clause is a contract on adapter message text with no gate behind it: nothing fails if a future adapter ships a sentence that omits the tray, and the widget's doc explicitly states the cost of trusting the message rather than checking it (`hotkey_status_view.dart:99-102`). This is **already owned by DW-82** ("A6's 'the tray menu still opens the panel' clause is a contract on adapter message text that nothing enforces"), so it is *known / carried*, not new. Worth noting only because this pass has just widened the spine's reliance on the property: the amendment makes the tray-naming contract load-bearing for the settings surface's correctness, so the unenforced-ness now costs more than it did. A `test/architecture/` row asserting the property over the two adapter files would close it and would break none of this pass's constraints (the constraint bars Dart under `lib/`, not under `test/`) — but it is out of an Update pass's remit.

### F6 — LOW — a small internal tension the rewrite introduced

The bullet now says the screen "claims nothing about the desktop or about who owns the binding" and, a clause later, that the one line it adds "states only that no ownership regime is known". The shipped line does name the desktop ("Whether this app or your desktop would own the shortcut…") — as a disjunct being *disclaimed*, so the substance is right, but a literal reader hits the two clauses one after the other and has to reconcile them. One word ("claims nothing *positive* about the desktop", or moving the disclaimer clause ahead of the "claims nothing" clause) settles it. Autofixable; breaks no constraint.

---

## Region 2 — the new Structural Seed row

The row:

```
        unconfigured_correction_provider.dart       # registry miss -> providerUnavailable (AD-15, AD-19)
```

### The file exists ✅

`/workspace/lib/src/infrastructure/correction/unconfigured_correction_provider.dart` — present, at exactly the path the Seed places it.

### The comment is accurate ✅

`unconfigured_correction_provider.dart:28` yields `CorrectionFailureKind.providerUnavailable`, and `providerUnavailable` is a real member of the sealed failure enum (`/workspace/lib/src/domain/correction/correction_event.dart:50`). The "registry miss" trigger is right: `active_correction.dart:80` marks the lookup as "AD-15: a map lookup, never a `switch (providerId)`", and the null result routes to the unavailable provider. (Strictly, the same helper also covers a preset naming a provider the config never described; "registry miss" is the dominant case and the comment column is a clipped one, so this is not worth a word.)

### The AD citations are right ✅

- **AD-15** — `provider_registry.dart:7` states the AD-15 property this file sits on ("adding a provider is adding one map entry here, never a `switch`"), and `active_correction.dart:80` cites AD-15 on the lookup that produces the miss.
- **AD-19** — `unconfigured_correction_provider.dart:7`: "AD-19 is explicit that a provider the daemon cannot reach must not prevent…", and `provider_registry.dart:25` says the same ("a half-configured provider must never block daemon startup (AD-19)").

Both citations are earned by the file's own documented behaviour, not inferred. Citing both rather than AD-15 alone matches the sibling rows' style.

---

## Region 3 — the Structural Seed sweep (the pass's own standard, applied to the whole block)

The pass added one file because the Seed omitted a shipped file. Applying that same standard across `lib/src/` — `find lib -name '*.dart' | sort` against the Seed block — turns up **no listed-but-absent files** (every path the Seed names exists) and **twelve further omissions in the `infrastructure/` block alone**, plus eight more elsewhere.

The Seed's convention matters here: `application/composition/` and `ui/panel/` `ui/settings/` are *directory* entries with a summarising comment, so their leaves are legitimately not enumerated. Every other block, and the whole of `infrastructure/`, is file-level. Judged by its own convention, the `infrastructure/` block is meant to be exhaustive and is not.

### F1 — HIGH — the `infrastructure/hotkey/` block omits five shipped files, two of which the spine's own normative prose cites by name

Seed lists `display_server.dart`, `x11_global_hotkey.dart`, `wayland_portal_global_hotkey.dart`. The tree also ships:

| Missing from the Seed | Why it matters |
|---|---|
| `hotkey_key_catalogue.dart` | **The spine names it twice.** `ARCHITECTURE-SPINE.md:300` cites the path in full — "in `infrastructure/hotkey/hotkey_key_catalogue.dart`, which carries the probed evidence" — and `:325`, *the sibling bullet of the Rule this very pass amended*, makes it normative: "a key `HotkeyKeyCatalogue` finds unrepresentable *before* the backend is touched". A reader who trusts the file map is told this file does not exist while a Rule instructs them to reason about it. |
| `hotkey_registrar.dart` | The port the X11 adapter binds through. `:48` of it documents the AD-12 translation ("The adapter above turns any of them into `HotkeyUnavailable` (AD-12)"). |
| `hotkey_manager_registrar.dart` | The `hotkey_manager` adapter behind that port. |
| `hotkey_grab.dart` | Part of the same seam. |
| `xdg_shortcut_trigger.dart` | The portal's `preferred_trigger` serialization AD-11 turns on. |

The consequence is not cosmetic. The Stack note says "AD-9 makes replacing `hotkey_manager` a one-file change" and the Seed shows exactly one X11 file; the tree has a port/adapter split (`hotkey_registrar.dart` + `hotkey_manager_registrar.dart` + `hotkey_grab.dart`) that is what actually makes the swap cheap, and the Seed hides it. A builder reading the Seed reconstructs the wrong shape of the seam the spine promises.

**Severity high** because a normative Rule and the file map contradict each other inside the region this pass touched. **Autofixable within every stated constraint** — adding Seed rows touches no AD, no CAP row, no verbatim-fixed type, no Dart under `lib/`, neither `SPEC.md` nor the ledger, and states no version number. Not a BLOCKER.

### F2 — MEDIUM — seven further `infrastructure/` omissions, and eight more outside it

Rest of the `infrastructure/` block:

- `correction/claude_agent_sdk/sidecar_host_paths.dart`
- `panel/panel_window.dart`, `panel/window_manager_panel_window.dart`
- `tray/tray_icon.dart`, `tray/tray_manager_tray_icon.dart`, `tray/tray_menu_entry.dart`
- `config/default_app_config.dart` — the file that holds the shipped `claude-sonnet-5` constant the Stack table's last row states

Outside `infrastructure/` (reported here because the brief asked for the whole `lib/src/` sweep):

- `domain/collection_equality.dart` — and the spine has a collection-equality clause in AD-2/AD-9, so this is the file those clauses land in
- `domain/correction/correction_outcome.dart`
- `domain/config/config_load_result.dart`
- `domain/config/provider_config.dart` — **named in AD-15's own Rule 3**: "a `Map<String, CorrectionProvider Function(ProviderConfig)>`"
- `application/correction_state.dart`, `application/settings_state.dart`
- `ui/daemon_app.dart`, `ui/daemon_home.dart` — these sit at the `ui/` root, outside both directory entries the Seed lists, so the directory-summary convention does not cover them

Twenty files in total across `lib/src/`, none of them listed. Same autofix, same constraint clearance as F1.

Note on the pattern rather than the instances: the Seed has now been corrected one file at a time across at least three passes (the 2026-08-14 currency review's F2 fixed "three files", its F4 fixed `hotkey_bind_outcome.dart`, this pass fixed one more). Each correction makes the map *more* trustworthy while leaving it incomplete, which is the worse of the two failure modes — a reader stops cross-checking a map that looks maintained. One sweep, or an explicit "representative, not exhaustive" caption on the block, ends it. The second option is cheaper and is a legitimate architectural choice; what is not tenable is the current state, where the block reads exhaustive and is not.

---

## Region 4 — the Stack table, re-reconciled

Re-ran the reconciliation the heading note claims, against `pubspec.yaml` and `pubspec.lock` (lock parsed with a script rather than grepped, so indentation could not hide a row).

| Stack row | `pubspec.lock` | Verdict |
|---|---|---|
| Flutter (stable) — cited | `.github/workflows/ci.yml:88` → `flutter-version: 3.44.8` | citation resolves ✅ |
| Dart SDK 3.12.2 | lock `sdks: dart ">=3.12.2 <4.0.0"`, pubspec `sdk: ^3.12.2` | matches ✅ (its *existence* as a second writable copy is already filed — see below) |
| flutter_riverpod 3.4.2 | 3.4.2 | ✅ |
| drift 2.34.3 | 2.34.3 | ✅ |
| drift_flutter 0.3.1 | **absent** | **known // carried — DW-94** |
| drift_dev (dev) 2.34.0 | 2.34.0 | ✅ |
| build_runner (dev) 2.15.1 | 2.15.1 | ✅ |
| sqlite3 3.5.1 | 3.5.1 | ✅ |
| dbus 0.7.14 | 0.7.14 | ✅ |
| window_manager 0.5.2 | 0.5.2 | ✅ |
| tray_manager 0.5.3 | 0.5.3 | ✅ |
| hotkey_manager 0.2.3 | 0.2.3 | ✅ |
| flutter_lints (dev) 6.0.0 | 6.0.0 | ✅ |
| Python (sidecar interpreter) 3.11+ | no pin anywhere | see F7 |
| claude_agent_sdk — cited | `assets/sidecar/requirements.txt` → `claude-agent-sdk==0.2.132`, one pin | citation resolves ✅ |
| `claude` CLI — on `PATH` | not a version claim | ✅ |
| Default model `claude-sonnet-5` | `default_app_config.dart:41` `shippedModel = 'claude-sonnet-5'` | matches the tree ✅ |

**The gate is green.** `dart test test/architecture/sidecar_pin_drift_test.dart` → **44/44 pass**, including `the real files neither cited version has a second home anywhere in the spine`. So the pass's hardest constraint — no restated Flutter or `claude_agent_sdk` number anywhere in the spine — is verified by execution, not by inspection.

Also confirmed as *not* findings, because they are already filed as open ledger entries against this same spec (`spec-dw-2-spine-currency-refresh.md`), unnumbered block near the ledger's end: (a) the `Dart SDK 3.12.2` row being a second writable copy of a Flutter-determined fact; (b) the pin-renegotiation paragraph's `sqlite3_flutter_libs 0.6.0+eol` / `sqlcipher_flutter_libs 0.7.0+eol` warning being false now that `drift_flutter` is gone (both absent from the lock; DW-94 also names this paragraph); (c) CAP-5's *Lives in* path missing the `claude_agent_sdk/` segment; (d) CAP-11's *Governed by* omitting AD-18.

### F3 — MEDIUM — "one known exception" is still two, and the second was never filed

The heading note's headline is "Every **pub row** was checked … and matches the shipped dependency graph — with **one known exception**". Reconciling in the other direction turns up a second labelled divergence:

`/workspace/pubspec.yaml`, dev_dependencies:

```yaml
  # Not in the spine Stack table, but already in the dependency graph at this
  # exact version (riverpod 3.4.2 depends on it). A direct dev dependency is
  # required for the spec's own verification command `dart test` to run the
  # pure-Dart domain tests without a Flutter binding (AGENTS.md §7).
  test: 1.31.0
```

Lock confirms `test 1.31.0` as a direct dev dependency. So `pubspec.yaml` names **two** divergences from this table — `drift_flutter` (table has it, graph doesn't) and `test` (graph has it, table doesn't) — and the spine acknowledges one. The asymmetry is load-bearing: "one known exception" is the sentence that tells a reader they may stop reconciling, and it tells them that one row early.

This was raised as F6 by the **previous** currency pass (`review-currency-check-2026-08-14-amendments.md`), was not fixed, and — I checked — was **not filed in `deferred-work.md` either** (`grep` for `1.31.0` and for `dev dependenc` in the ledger returns nothing). It has now survived two passes with no owner. Autofixable: add the row, or widen the exception sentence to name both. No constraint broken either way (`test 1.31.0` is neither of the two gated subjects).

### F4 — LOW — the pinned `claude_agent_sdk` is six patch releases behind upstream; the remedy is outside this pass

Checked against PyPI in this session (`curl https://pypi.org/pypi/claude-agent-sdk/json`):

- pinned in `assets/sidecar/requirements.txt`: **0.2.132**
- current released: **0.2.138**
- `requires_python`: `>=3.10`

The package exists, is published by Anthropic, and is the one AD-19 names — so this is staleness, not a dead technology, and it also re-confirms AD-19's distribution claim. It is **not a spine error**: the row cites a file, the file holds exactly one pin, and the heading note now explicitly scopes upstream currency out ("What was *not* re-checked this pass is whether any pin is still current **upstream**"), which closes the previous pass's F7. Recorded so the fact is not lost.

**Not autofixable within the constraints.** Both remedies are out: bumping `requirements.txt` is a real dependency change with a sidecar-protocol blast radius, well outside a spine Update; and writing the number into the spine is forbidden by the gate. Human call, and properly a ledger item rather than a spine edit.

### F7 — LOW — the `Python 3.11+` row is asserted, unenforced, and stricter than its own cause

Nothing in the repo pins or checks a Python version: no `python-version` in `.github/workflows/ci.yml`, no Python `ARG` in `.devcontainer/Dockerfile`. The only other copy of the number is a *message string* — `tool/provision_sidecar.sh:93` prints "the sidecar needs Python 3.11+" when no `python3` is on `PATH`, and the script does not then verify the version it found. Meanwhile the pinned SDK's own metadata says `requires_python >=3.10`. So the extra half-step from 3.10 to 3.11 has no source in the tree and no stated source in the spine, and no gate would catch it being wrong. It may well be right (a 3.11-only construct in the sidecar would justify it) but I could not find one, and a floor nobody can trace is a floor a packaging story will get wrong. One clause naming what needs 3.11, or a version check in `provision_sidecar.sh`, closes it. Autofixable in the spine half; breaks no constraint.

---

## Constraint check on everything proposed above

No finding's only remedy breaks a stated constraint, so **no BLOCKER is raised**.

| Constraint | Any proposed fix touch it? |
|---|---|
| No AD added / retired / renumbered / reused | No — F1/F2 are Seed rows, F3/F7 are Stack prose, F6 is one word inside an existing AD-12 bullet |
| Exactly 13 CAP rows, none added/removed/reworded | No — nothing proposed touches the CAP map (the two known CAP defects are already filed and deliberately left alone here) |
| Verbatim-fixed types byte-identical | No — no declaration or constructor is restated by any proposal |
| No Dart under `lib/` changed | No — F5's optional gate would live under `test/`, and I am not proposing it in this pass |
| `SPEC.md` and `deferred-work.md` untouched | No — F3/F4 are *recommended* for filing, which is the orchestrator's action, not this pass's |
| No `claude_agent_sdk` / Flutter version numbers restated in the spine | No — F4 deliberately proposes **no** spine edit for exactly this reason; F3's `test 1.31.0` is neither gated subject; re-ran `dart test test/architecture/sidecar_pin_drift_test.dart` → 44/44 green |

---

## Findings, ranked

| # | Sev | Autofix within constraints | Finding |
|---|---|---|---|
| F1 | **high** | yes | Seed's `infrastructure/hotkey/` omits 5 shipped files, incl. `hotkey_key_catalogue.dart`, which AD-12's own amended sibling bullet (`:325`) and AD-9's prose (`:300`) both cite by name — the file map denies a file a Rule reasons about |
| F2 | medium | yes | 7 further `infrastructure/` omissions + 8 more across `domain/`, `application/`, `ui/` root — 20 shipped files total absent from a block that reads exhaustive; incl. `provider_config.dart`, named in AD-15's Rule 3 |
| F3 | medium | yes | Stack note's "one known exception" is two — `test: 1.31.0` is a pinned direct dev dependency in `pubspec.yaml`+lock and absent from the table, labelled as a divergence by pubspec itself. Raised by the previous pass, never fixed, never filed |
| F4 | low | **no** (remedy is a dependency bump or a forbidden restatement) | `claude-agent-sdk` pinned 0.2.132, PyPI latest 0.2.138 — staleness only; the row and the note are both correct as written |
| F5 | low | known // carried (DW-82) | The tray-naming contract holds across all 20 producing messages but nothing enforces it, and this amendment makes the spine lean on it harder |
| F6 | low | yes | AD-12's amended bullet says the screen "claims nothing about the desktop" one clause before describing a line that names the desktop to disclaim it |

**Known // carried, reported as such and not counted as findings:** `drift_flutter 0.3.1` in the Stack table (DW-94); the pin-renegotiation paragraph's EOL transitive claim (DW-94 + the unnumbered DW-2 entry); the `Dart SDK 3.12.2` row as a second writable copy; CAP-5's truncated path; CAP-11's *Governed by*.

---

## Commands and sources used

- `git diff` on the spine, `pubspec.yaml`, `test/architecture/sidecar_pin_drift_test.dart`, `.memlog.md`
- `find lib -name '*.dart' | sort` — 79 files, swept against the Structural Seed block by hand
- `grep -rn "HotkeyUnavailable" lib/` plus direct reads of every producing site and every helper named in the brief (`_refusedBeforeBackend`, `_messageFor`, `_recordDeadConnection`, all 14 `_PortalRefusal` throws, the three module-level `const String` messages)
- `pubspec.lock` parsed with a Python script for all 14 relevant packages
- `.github/workflows/ci.yml:88`, `.devcontainer/Dockerfile:111`, `assets/sidecar/requirements.txt`, `tool/provision_sidecar.sh`
- `dart test test/architecture/sidecar_pin_drift_test.dart` → 44/44 pass
- `curl https://pypi.org/pypi/claude-agent-sdk/json` → `info.version` 0.2.138, `requires_python >=3.10`
- `_bmad-output/implementation-artifacts/deferred-work.md` — searched for DW-82, DW-94, and for prior filings of F3 (none found)

No file was edited by this review except this review file.

---

## Disposition — 2026-09-26

The historical checks and version observations above remain dated 2026-08-14. This appendix compares repository claims to current checked-in source and the regenerated spine; it makes no current upstream-version or native-compositor claim.

| Finding | Status | Current evidence and limit |
| --- | --- | --- |
| F1 and F2 (Seed omissions) | Accepted; source-level closure | The Structural Seed now identifies itself as the current tracked `lib/` file map and lists `hotkey_key_catalogue.dart`, `hotkey_registrar.dart`, `x11_key_grab_registrar.dart`, `provider_config.dart`, the root UI files, and the other then-omitted paths. The old `hotkey_manager_registrar.dart` path is intentionally absent because the plugin was removed; `pubspec.yaml` names that removal. This is a current source/map comparison, not proof future edits cannot drift. |
| F3 (Stack “one exception”) | Accepted | The Stack no longer claims one exception, includes `test (dev)`, and omits removed `drift_flutter`; `pubspec.yaml` and `pubspec.lock` retain `test: 1.31.0` and no `drift_flutter`. |
| F4 (then-current SDK patch gap) | Superseded as a dated observation | The Stack cites `assets/sidecar/requirements.txt`, which still pins `claude-agent-sdk==0.2.132`, and explicitly limits its reconciliation to checked-in manifests. No PyPI query was made in this disposition, so the 2026-08-14 “six patch releases” statement is not a current count. Upstream freshness remains unverified. |
| F5 (unenforced tray sentence) | Still open as enforcement | AD-12 still relies on adapter messages naming the tray, and `HotkeyStatusView._unavailableLines` uses a fallback only for blank messages. Source inspection finds no exhaustive message-contract gate; this phase's locked scope excludes a new test or gate. |
| F6 (AD-12 phrasing tension) | Superseded | AD-12 now explicitly permits a cause-specific line, the verbatim adapter message, and one ownership line. The old “claims nothing about the desktop” prohibition is no longer the rule. The separate revoked-shortcut ownership contradiction is recorded in the adversarial review's S-2 disposition. |
| F7 (Python floor) | Accepted in the spine; source message remains open | The Stack now says the provisioner checks for `python3` presence, not its version, matching `tool/provision_sidecar.sh`. That script still prints “needs Python 3.11+” on the missing-interpreter path without enforcing a version floor. The architecture no longer presents the floor as a checked runtime dependency. |

The old report's confirmed AD-12 message-site sweep remains historical evidence only; this appendix does not repeat it as a current exhaustive sweep.
