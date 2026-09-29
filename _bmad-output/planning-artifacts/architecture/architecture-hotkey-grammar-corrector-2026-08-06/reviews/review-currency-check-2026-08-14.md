# Reviewer Gate — Currency Check (2026-08-14)

**Target:** `ARCHITECTURE-SPINE.md` (post-Update pass, `updated: '2026-08-14'`)
**Lens:** Verify every committed decision was reality-checked against the repository rather than asserted from training data.
**Method:** Every factual claim in the changed regions was re-derived from the shipped tree — `lib/`, `test/`, `.github/workflows/ci.yml`, `assets/sidecar/requirements.txt`, `pubspec.yaml`/`pubspec.lock`, the vendored `hotkey_manager_linux-0.2.0` plugin source, and the built ELF objects under `build/linux/x64/release/`. Nothing below is recalled; each line cites what was read or measured.

---

## Verdict

**Pass with findings.** Every one of the six currency corrections and both citation swaps is *correct against the shipped code* — I could not find a single claim in the changed regions that was asserted from training data rather than measured. The failures are of **scope, not accuracy**: the pass corrected exactly the rows it was told to correct and did not revisit the text immediately around them, so three regions it edited now disagree with their own neighbours. One of those (`drift_flutter`) is a live contradiction with `pubspec.yaml` sitting four rows below a cell the pass rewrote.

---

## Part 1 — Confirmations (what was checked and holds)

### AD-9's fixed declaration block

Compared line-by-line against the three domain files. **Declared fields and constructors are byte-identical**, and the member list is complete and correct.

| Spine declaration | Shipped | Verdict |
| --- | --- | --- |
| `enum HotkeyModifier { control, alt, shift, meta }` | `hotkey_binding.dart:3` | exact |
| `HotkeyBinding({required modifiers, required key})`, `Set<HotkeyModifier> modifiers`, `String key` | `hotkey_binding.dart:5-8` | exact |
| `enum BindingAuthority { application, compositor }` | `global_hotkey.dart:4` | exact |
| `HotkeyRegistration({required effective, required authority})`, `HotkeyBinding? effective`, `BindingAuthority authority` | `global_hotkey.dart:6-11` | exact |
| `sealed class HotkeyBindOutcome` | `hotkey_bind_outcome.dart:9-11` | exact |
| `HotkeyBound(this.registration)`, `HotkeyRegistration registration` | `hotkey_bind_outcome.dart:15-18` | exact |
| `HotkeyUnavailable({required this.message})`, `String message` | `hotkey_bind_outcome.dart:34-39` | exact |
| `Stream<void> get activations` | `global_hotkey.dart:32` | exact |
| `Stream<HotkeyBindOutcome> get bindingChanges` | `global_hotkey.dart:55` | exact |
| `Future<HotkeyBindOutcome> bind(HotkeyBinding binding)` | `global_hotkey.dart:63` | exact |
| `Future<void> dispose()` | `global_hotkey.dart:65` | exact |

`GlobalHotkey` has exactly those four members and no others — **the member list is complete**. The stale `Future<HotkeyRegistration> bind(...)` is gone from the spine (`grep 'Future<HotkeyRegistration>'` → no match).

The file-path headers in the block (`// domain/hotkey/hotkey_bind_outcome.dart`, `// domain/hotkey/global_hotkey.dart (continued)`) match where the types actually live.

### AD-9's new value-equality Rule — **correct**

`HotkeyRegistration` (`global_hotkey.dart:16-27`), `HotkeyBinding` (`hotkey_binding.dart:15-26`), `HotkeyBound` (`hotkey_bind_outcome.dart:20-29`) and `HotkeyUnavailable` (`:41-50`) each carry `operator==`/`hashCode` over exactly the declared fields and nothing else. The "`SettingsState` contains them transitively" justification holds: `settings_state.dart:2` imports `hotkey_bind_outcome.dart` and `SettingsState.hotkeyBindOutcome` is a `HotkeyBindOutcome?`, reaching `HotkeyRegistration` → `HotkeyBinding`; `AppConfig.hotkeyBinding` is the second path. The set-comparison claim is real — `hotkey_binding.dart:22` uses `setEquals(modifiers, other.modifiers)` from `domain/collection_equality.dart`, and `test/domain/value_equality_test.dart` pins it ("CAP-12: two bindings whose modifier sets differ only in order are the same combination"). Suite run: green.

### AD-9's `bindingChanges` Rule and the "Broadcast" claim — **correct, including the edge case**

`WaylandPortalGlobalHotkey` holds a real broadcast `StreamController<HotkeyBindOutcome>` (`:147`), subscribes to `ShortcutsChanged` (`:785-786`) and republishes through `_onShortcutsChanged` → `_emitBindingChange` (`:832`, `:890-893`). `X11GlobalHotkey.bindingChanges` is `const Stream<HotkeyBindOutcome>.empty()` (`:93-94`) with a doc calling it "a measured absence" — exactly what AD-9 describes.

I checked the one place this could have been an over-claim: does an empty stream honour "Broadcast"? Measured on the installed Dart 3.12.2 — `const Stream<int>.empty()` reports `isBroadcast == true` and accepts repeat `listen()` calls, both firing `onDone`. **The claim survives.**

### AD-9's keybinder-accelerator prose — **correct, and verified at the C source**

Read `~/.pub-cache/hosted/pub.dev/hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc` directly:

- `hkm_register` calls `gtk_accelerator_name(key_code, (GdkModifierType)get_mods(modifiers))` and passes the result straight to `keybinder_bind`. The accelerator **is** built in C from the keyval and modifier names, exactly as the spine now says.
- `get_mods` compares the strings `"alt"`, `"capsLock"`, `"control"`, `"meta"`, `"shift"` — and `HotkeyKeyCatalogue.modifierNameFor` (`:176-181`) emits `'control' | 'alt' | 'shift' | 'meta'` from an exhaustive `switch` with no default. The spine's "a `HotkeyModifier` to the modifier name the plugin compares against" is precise.
- "no Dart under `lib/` builds one": `grep -rn 'gtk_accelerator\|<Control>\|accelerator' lib/` returns only doc comments. Confirmed.
- The probed `<Shift><Control>g` output matches `hotkey_key_catalogue.dart:11`, which records the same measurement independently.
- The X11 serialization really is `hotkey_key_catalogue.dart` — a label → USB HID usage (`usbHidUsageFor`, `:88-97`) plus the modifier name. Confirmed.
- The Wayland `CTRL+SHIFT+g` example is exact, not approximate: `XdgShortcutTrigger` (`:47-60`, `:92-98`, `:115-120`) emits modifiers in fixed `CTRL, ALT, SHIFT, LOGO` order and lower-cases letter keysyms, so Ctrl+Shift+G serializes to precisely `CTRL+SHIFT+g`.

### AD-17's four-part composition — **all four parts correct**

1. `main.dart:165-170` — `runApp(UncontrolledProviderScope(container: graph.container, child: const DaemonApp()))`. **`UncontrolledProviderScope` is right**, and it is genuinely over the container `DaemonGraph` already holds (`daemon_graph.dart:21`), not a `ProviderScope` that builds its own. `main.dart` also owns `_abort` (`:289-317`, the pre-lifecycle abort path with its own `_releaseWithoutLifecycle`) and `_installSignalHandlers` (`:441-466`). Confirmed.
2. `application/composition/` — `port_providers.dart` declares one throwing seam per port; `controller_providers.dart` constructs the three controllers with `ref.onDispose` backstops; `daemon_graph.dart:42-46` builds all three **eagerly** and `disposeControllers` (`:95-99`) fixes the order correction → panel → settings. Confirmed.
3. `daemon_startup.dart:64-124` — order is lock (AD-14) → config store (AD-13) → database → hotkey adapter (AD-9) → active pair (AD-5), with `_hotkeyFor` (`:251-270`) making the display-server choice from `DisplayServer.fromEnvironment`. **`daemon_lifecycle.dart` does own the teardown order** — `_run()` (`:208-227`) is an 11-step guarded sequence, and its doc calls the order "the contract, not a detail". Confirmed.
4. `active_correction.dart:33-43` — `ActiveCorrection.resolve` returns the `(CorrectionProvider, Preset)` pair through AD-15's registry lookup. Confirmed.

The "`main()` is reachable by no test" Rule is also true as stated: `composition_wiring_test.dart`'s own header says `main.dart` "is the one file no test can execute" and that its wiring is pinned by a **source scan**.

### CAP-4 / CAP-11 map rows — **correct**

`selectSuggestion` at `correction_controller.dart:179`, `_completedTextOf` at `:255`, `copySuggestion` at `:208`, `copyFailure` at `correction_state.dart:67` and rendered from `ui/panel/correction_panel.dart:280,287`. Both rows now name `application/correction_controller.dart`, matching where the behaviour lives. The map still holds exactly 13 CAP rows (`grep -c '^| CAP-'` → 13).

### Stack table's two citations — **both resolve and pin exactly one version**

- `.github/workflows/ci.yml` exists and carries exactly one `flutter-version: 3.44.8` (line 81). One pin.
- `assets/sidecar/requirements.txt` exists and carries exactly one `claude-agent-sdk==0.2.132`. One pin.
- `test/architecture/sidecar_pin_drift_test.dart` genuinely enforces what the note claims. I traced `citedPathInStackTable` against the *live* spine text: `pinnedInStackTable` slices to the `## Stack` section, the `(?![\w-])` guard clears both row names (`Flutter (stable)` with its parens, `claude_agent_sdk` against a longer namesake), and the single-backtick + contains-`/` + not-absolute rules resolve both cells. The bare-version branch is load-bearing and covered by its own self-test. Run: `dart test test/architecture/` → **160 passed, 1 skipped** (the skip is the pre-existing no-display row, DW-9).
- `grep '0\.2\.132\|3\.44\.8'` over the spine → **no match**. The second homes are gone.

### Operational envelope's `libkeybinder-3.0-0` claim — **correct, and measured**

```
readelf -d build/linux/x64/release/bundle/lib/libhotkey_manager_linux_plugin.so
  (NEEDED)  libkeybinder-3.0.so.0
readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector
  (NEEDED)  libhotkey_manager_linux_plugin.so
```

The spine's exact wording — "the **`hotkey_manager` plugin library** carries it as a `DT_NEEDED` entry" — is the correct form. Worth flagging as a *positive*: DW-39's original ledger text claimed the executable carried it directly, DW-40's decision corrected that, and the spine took the corrected version. The consequence stated ("the dynamic loader fails before `main()` runs") follows, since the runner has the plugin as a direct `NEEDED`. Also confirmed at build time: `hotkey_manager_linux-0.2.0/linux/CMakeLists.txt` makes a missing `keybinder-3.0` a `FATAL_ERROR`.

### Rest of the Stack table (spot-checked against `pubspec.yaml`)

`Dart SDK 3.12.2` (matches `dart --version` and `sdk: ^3.12.2`), `flutter_riverpod 3.4.2`, `drift 2.34.3`, `drift_dev 2.34.0`, `build_runner 2.15.1`, `sqlite3 3.5.1`, `dbus 0.7.14`, `window_manager 0.5.2`, `tray_manager 0.5.3`, `hotkey_manager 0.2.3`, `flutter_lints 6.0.0` — **all match.** One row does not; see Finding 1.

### Deterministic lint

`lint_spine.py` → 1 low finding: `possible unfilled template token (verify): '{sv}'` at line 317. That is the D-Bus signature `a{sv}` in AD-11's `Activated` signal, outside every changed region. **False positive, pre-existing, no action.**

---

## Part 2 — Findings

### F1 — MEDIUM — the Stack table still lists `drift_flutter | 0.3.1`, which the shipped code does not depend on

The refresh rewrote two cells of the `## Stack` table and left, four rows below, a package that has been removed from the build.

- `grep -n 'drift_flutter' pubspec.yaml pubspec.lock` returns **only the explanatory comment**, never a dependency entry. It is not in the lockfile.
- `pubspec.yaml:15-23` states this outright: *"The divergence: the Stack table still lists drift_flutter 0.3.1, which the persistence story removed. … Do not re-add it to 'match the spine' — the divergence is recorded in the deferred-work ledger for the spine to absorb."*

The pass whose whole purpose was "end six places where the spine states something the shipped code no longer does" left a seventh, in a region it edited, that the code itself flags in a comment addressed to exactly this document.

The damage extends to the prose below the table: the **Pin renegotiation** paragraph still reasons that *"`drift_flutter 0.3.1` transitively resolves `sqlite3_flutter_libs 0.6.0+eol` / `sqlcipher_flutter_libs 0.7.0+eol` — end-of-life native sqlite builds; revisit when the drift slice lands"*. The drift slice landed, `drift_flutter` went with it, and per `pubspec.yaml:19-21` dropping it "also takes sqlite3_flutter_libs, sqlcipher_flutter_libs and the transitive jni FFI plugin out of the graph" — native sqlite now comes from `sqlite3 3.5.1`'s Dart build hooks. So the spine warns about an end-of-life risk the project no longer carries, and points at a revisit trigger that has already fired.

**Why it matters:** this is the same failure mode the citation change was made to end — the spine holding a writable second copy of a dependency fact that has diverged from the one that ships. A reader treating the Stack table as the decision would re-add `drift_flutter`, which `pubspec.yaml` explicitly tells them not to do.

**Note on scope:** the driving spec's task 7 named only the two version cells, so this is a miss of the *lens*, not a breach of the spec. It should be raised with the orchestrator rather than silently patched, since it is a third Stack correction the pass was not commissioned for.

---

### F2 — MEDIUM — AD-17's "four parts" is contradicted by the diagram above it and the tree below it

The pass rewrote AD-17 into four parts and rewrote the Design Paradigm line to say *"It is not one file — AD-17 fixes its four parts and which half of the knowledge each holds."* Two neighbouring artefacts still describe two parts, or none.

**(a) The mermaid `ROOT` node (line 54).** It reads `ROOT[composition root — main.dart + application/composition]` — parts 1 and 2 only. Parts 3 and 4 (`infrastructure/system/daemon_startup.dart`, `daemon_lifecycle.dart`, `infrastructure/correction/active_correction.dart`) are absent from the node text, one line under a sentence promising four. The node was edited by this pass, so it was in hand at the time.

**(b) The Structural Seed (lines 452-517).** AD-17's new Rule says *"a reader looking for one of them should expect it here"* — but a reader who then follows the Structural Seed finds none of parts 3 or 4:

- `infrastructure/system/` lists `single_instance_lock.dart`, `stderr_logger.dart`, `system_clock.dart` — **no `daemon_startup.dart`, no `daemon_lifecycle.dart`**, the two files AD-17 now names as owning the startup order and the teardown order.
- `infrastructure/correction/` lists `provider_registry.dart` and the `claude_agent_sdk/` directory — **no `active_correction.dart`**, AD-17's part 4.

The seed's `main.dart` comment *was* updated in this pass (`# composition root, platform half (AD-17)`), so the tree was open when the four-part Rule was written. The result is a spine that names four parts in one section and can locate two of them in another.

**Suggested fix:** widen the ROOT node to `composition root — main.dart, application/composition, daemon_startup/lifecycle, active_correction` (or simply `composition root (AD-17, four parts)`), and add the three files to the Structural Seed's `system/` and `correction/` blocks.

---

### F3 — MEDIUM — AD-2's new value-equality Rule names the right types but gives a reason that is false for one of them

The *classification* is correct and I verified all five types:

| Type | Spine says | Shipped | Verdict |
| --- | --- | --- | --- |
| `Suggestion` | carries `==` | `suggestion.dart:12-23` | correct |
| `Preset` | carries `==` | `preset.dart:17-30` | correct |
| `CorrectionFailed` | carries `==` | `correction_event.dart:34-45` | correct |
| `SuggestionDelta` | identity equality | no override (`:9-13`) | correct |
| `CorrectionCompleted` | identity equality | no override (`:16-19`) | correct |

`test/domain/value_equality_test.dart` pins all three positives; run green. `correction_event.dart:31-33` states the deliberate omission in the same words the spine uses.

The **reason** is where it breaks. The spine says all three carry equality *"because each is held by an immutable controller state whose `copyWith` consumers dedupe by value."* That is true of `CorrectionFailed` (`CorrectionState.failure`, `correction_state.dart:50`) and true of `Preset` only transitively (`SettingsState.config` → `AppConfig.presets`). It is **false of `Suggestion`**:

- `CorrectionState` holds `Map<SuggestionRegister, String> suggestionTexts` (`correction_state.dart:46`), **not** `List<Suggestion>`.
- `grep 'Suggestion\b' lib/src/application/*.dart` finds exactly one non-state occurrence: a local parameter type at `correction_controller.dart:714`. No controller state holds a `Suggestion`.
- The real reason is in the code's own comment (`suggestion.dart:9-11`): *"`CorrectionRecord` holds a `List<Suggestion>` and cannot compare by value while its elements compare by identity."* That is AD-7's persisted shape, a domain type — not a controller state.

**Why it matters under this lens specifically:** the classification was reality-checked; the *rationale sentence* was generalised from the AD-9 Rule written beside it (where "`SettingsState` contains them transitively" is accurate for all four types) and applied to AD-2 without re-deriving it. It is the one place in the changed regions where the spine states something the code does not support.

**Suggested fix:** split the reason — `CorrectionFailed` because `CorrectionState` renders it; `Preset` because `AppConfig` (and so `SettingsState`) holds a `List<Preset>`; `Suggestion` because AD-7's `CorrectionRecord` holds a `List<Suggestion>` and cannot compare by value while its elements compare by identity.

---

### F4 — LOW — the Structural Seed's `domain/hotkey/` omits `hotkey_bind_outcome.dart`, which AD-9 now declares

AD-9's block carries the header `// domain/hotkey/hotkey_bind_outcome.dart` and declares three types under it. The Structural Seed still lists only:

```
      hotkey/
        hotkey_binding.dart
        global_hotkey.dart               # port + HotkeyRegistration + BindingAuthority
```

A reader following AD-9 to the file layout finds no home for `HotkeyBindOutcome` / `HotkeyBound` / `HotkeyUnavailable`. The Consistency Conventions row "One public type per file; filename is the snake_case of the type" makes the missing file conspicuous rather than implied. Same root cause as F2(b) — the seed was not revisited when AD-9 grew a third file.

---

### F5 — LOW — the AD-9 prose edit orphaned two live code comments

`<Ctrl><Shift>g` no longer appears anywhere in the spine (verified by grep). Two shipped files still quote it *as the spine's text*:

- `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart:7-9` — *"AD-9 describes this adapter as serializing the binding \"to keybinder's own syntax — `<Ctrl><Shift>g`\". It does not, and cannot…"*. The whole paragraph is a rebuttal of a sentence AD-9 no longer contains; the spine has now adopted the rebuttal's own conclusion, so the comment argues against the current spine's agreement with it.
- `lib/src/infrastructure/config/default_app_config.dart:140` — *"Matches the spine's own `<Ctrl><Shift>g` example"*. The spine has no such example. The default binding (Ctrl+Shift+G) is still right; only the citation dangles.

The driving spec's `Never` clause forbids touching `lib/` in this pass, so **this is a follow-up to file, not a change to make here.** Recording it because the spine edit is what created the dangle, and nothing else will notice: both are comments, so neither `dart analyze` nor any test will ever go red on them.

---

### F6 — LOW — "Verified current on 2026-08-06" now heads a table revised on 2026-08-14

The `## Stack` section still opens with `Verified current on 2026-08-06.` while two of its rows were rewritten on 2026-08-14 and the frontmatter reads `updated: '2026-08-14'`. A reader deciding whether to re-verify the table takes that date at face value. Either restate it as `2026-08-14`, or split it (`Versions verified 2026-08-06; the two cited rows refreshed 2026-08-14`).

The same 2026-08-06 stamp on the **Pin renegotiation** paragraph is correct and should stay — that is a user ratification with its own date, and it was rightly left alone even though its Flutter reference was reworded to "the pinned Flutter stable".

---

### F7 — LOW — CAP-5's map row cites a path that does not exist

`| CAP-5 streaming partials | infrastructure/correction/register_tagged_stream_parser.dart | … |`

The file is at `lib/src/infrastructure/correction/**claude_agent_sdk/**register_tagged_stream_parser.dart`. The Structural Seed has it right (`:489`), so the spine disagrees with itself. Immediately adjacent to the CAP-4 row this pass edited, and a one-token fix.

---

### F8 — LOW — CAP-11's "Governed by" column was not revisited when its "Lives in" was corrected

CAP-11 now reads `… | AD-6`. AD-6 is register ordering and persist-by-name; it says nothing about copying. What actually governs CAP-11 is **AD-18**'s third Rule — *"the panel stays open after a copy and every variant remains copyable (CAP-14). Copying is never implicit in selection — selecting with 1/2/3 only highlights."* — which is precisely the invariant `copySuggestion` and `selectSuggestion` implement as separate paths (`correction_controller.dart:179` vs `:208`), and `copyFailure` (`correction_state.dart:60-67`) is a CAP-11 concept AD-6 cannot account for. Adding AD-18 would also make the row consistent with CAP-13's, which the spec used as the template for this fix.

---

## Part 3 — Checked and clean (no finding)

- **AD-10's rewrite.** "renders the `HotkeyRegistration` inside the returned `HotkeyBound` … a returned `HotkeyUnavailable` is rendered as AD-12's degradation … republish it on AD-9's `bindingChanges`" — matches `settings_controller.dart:68` (`_hotkey.bindingChanges.listen(...)`), `:282-283`, and `settings_state.dart:66-70`. No contradiction with AD-9's new block.
- **AD-9 ↔ AD-12 ↔ AD-2 type names.** No AD cites a type another AD renamed. `HotkeyBindOutcome`, `HotkeyBound`, `HotkeyUnavailable`, `HotkeyRegistration` are used consistently in AD-9, AD-10, AD-12 and the Consistency Conventions "Errors" row (which already listed `HotkeyUnavailable` before this pass).
- **AD-17 "constructs the vendor adapters"** is a mild over-claim — `DaemonStartup` constructs the lock, config store, database and hotkey adapter, as `port_providers.dart`'s own header says — but part 3 of the same Rule immediately assigns those to `daemon_startup.dart`, so the two halves reconcile. Not worth an edit.
- **Structural Seed's `main.dart` comment** (`# composition root, platform half (AD-17)`) matches `main.dart:28-38`'s own doc.
- **Operational envelope's remaining bullets** — portal backend, Python 3.11+, `claude_agent_sdk`, `claude` on `PATH` — all genuinely degrade rather than block, per `active_correction.dart:93-111` (`UnconfiguredCorrectionProvider`) and AD-19's config-value rule. The "All but one" split is accurate.
- **Acceptance greps.** `0.2.132` / `3.44.8` / `Future<HotkeyRegistration>` absent; 13 CAP rows; `git diff --name-only` = spine, memlog, `sidecar_pin_drift_test.dart`, `ci.yml` — no file under `lib/`, and `deferred-work.md` untouched. All as the spec required.

---

## Recommended disposition

| # | Severity | Action |
| --- | --- | --- |
| F1 | medium | Raise with the orchestrator — a third Stack correction outside this pass's commission. Drop the `drift_flutter` row and rewrite the pin-renegotiation paragraph's last sentence. |
| F2 | medium | Fix in this pass. Widen the mermaid `ROOT` node; add `daemon_startup.dart`, `daemon_lifecycle.dart`, `active_correction.dart` to the Structural Seed. |
| F3 | medium | Fix in this pass. Split AD-2's rationale so `Suggestion`'s reason names `CorrectionRecord` (AD-7), not a controller state. |
| F4 | low | Fix in this pass. Add `hotkey_bind_outcome.dart` to the seed's `domain/hotkey/`. |
| F5 | low | File as follow-up. `lib/` is out of scope here; the two comments will not self-correct. |
| F6 | low | Fix in this pass. Date the Stack heading. |
| F7 | low | Fix in this pass. Correct CAP-5's path. |
| F8 | low | Fix in this pass. Add AD-18 to CAP-11's "Governed by". |

None of these meets the spec's **Block If** bar: no finding requires adding, retiring or contradicting an `AD`, changing a CAP, or altering a frozen declaration's fields. F2, F3, F4, F6, F7 and F8 are all amendments to existing prose and tables with `AD` IDs stable.

## Disposition — 2026-09-26

This appendix classifies the 2026-08-14 findings against the regenerated spine and checked-in source. The verdict and measurements above remain a record of that review, not a current dependency or native-runtime audit.

| Finding | Current disposition | Evidence and limit |
| --- | --- | --- |
| F1, stale `drift_flutter` and EOL warning | **Accepted, resolved.** | The current spine's Stack and pin-renegotiation text omit `drift_flutter` and the old live EOL warning (`ARCHITECTURE-SPINE.md`, `## Stack`); `pubspec.yaml` explains the removed dependency. This checks the repository graph, not upstream freshness. |
| F2, two-part diagram and missing root files | **Accepted, resolved.** | The diagram now labels AD-17's four-part root, and the Structural Seed lists `daemon_startup.dart`, `daemon_lifecycle.dart`, and `active_correction.dart` (`ARCHITECTURE-SPINE.md`, Design Paradigm, AD-17, Structural Seed). |
| F3, `Suggestion` equality rationale | **Accepted, resolved.** | AD-2 now names `CorrectionRecord`'s `List<Suggestion>` separately from `AppConfig`'s presets and the panel's failure (`ARCHITECTURE-SPINE.md`, AD-2; `lib/src/domain/correction/correction_record.dart`). |
| F4, missing hotkey outcome file | **Accepted, resolved.** | The Structural Seed lists `lib/src/domain/hotkey/hotkey_bind_outcome.dart`, matching AD-9 and the shipped file. |
| F5, comments citing the removed accelerator example | **Accepted, resolved.** | The old claimed spine quotation is absent from `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart` and `lib/src/infrastructure/config/default_app_config.dart`. AD-9 now describes the shipped libX11 FFI registrar; the prior keybinder path was removed. |
| F6, Stack verification date | **Accepted, resolved for checked-in pins.** | The Stack is dated as reconciled to checked-in manifests on 2026-09-26 and explicitly does not claim an upstream latest-version check. |
| F7, CAP-5 parser path | **Accepted, superseded in location.** | The map points to `infrastructure/correction/shared/register_tagged_stream_parser.dart`, which exists. Phase 2 moved the reusable tagged parser to `shared/`; AD-16 still treats the wire format as adapter-specific. |
| F8, CAP-11 governing AD | **Accepted, resolved.** | The CAP-11 row now includes AD-18 alongside AD-6, matching selection and explicit copy in `lib/src/application/correction_controller.dart`. |

The historical review's confirmations of the old plugin bundle and installed Dart toolchain remain dated observations. The current `pubspec.yaml` and spine no longer ship `hotkey_manager`; no native display-server session or current upstream release was checked for this disposition.
