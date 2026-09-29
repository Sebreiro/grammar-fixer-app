---
title: 'Refresh ARCHITECTURE-SPINE.md to the shipped code, and give the two duplicated version pins one home'
type: 'chore'
created: '2026-08-14'
status: 'done'
baseline_revision: '8ca5685e42a283110f533551b2f802d8cf138baa'
final_revision: '36e2ad4'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/.memlog.md'
  - '{project-root}/.claude/skills/bmad-architecture/SKILL.md'
  - '{project-root}/.claude/skills/bmad-architecture/references/headless.md'
warnings: ['oversized']
---

<intent-contract>

## Intent

**Problem:** `ARCHITECTURE-SPINE.md` (`updated: 2026-08-06`) states six things the shipped code no longer does — AD-9's `bind()` signature and member list, AD-2/AD-9's verbatim blocks, AD-9's keybinder accelerator illustration, AD-17's one-line composition-root claim, and the CAP-4/CAP-11 map rows — and it restates two version numbers that already have an authoritative home elsewhere. Six stories each recorded the drift rather than hand-editing, which was right per story and is wrong as a standing state: a reader starting from the spine is misdirected in six places at once.

**Approach:** One `/bmad-architecture` **Update** pass, run headless, resuming from the run folder's `.memlog.md`: append one memlog entry per correction, amend the affected `AD` Rules and tables in place with `AD` IDs stable, re-distill the spine, and run the Reviewer Gate. Then rework `test/architecture/sidecar_pin_drift_test.dart` from a comparison between two writable copies of one fact into a check that the Stack table's new citations resolve.

## Boundaries & Constraints

**Always:**
- Regenerate through `bmad-architecture` (Update intent, headless) — never hand-patch the spine. Every change lands as a `memlog.py append` entry first, then the spine is re-distilled from the memlog.
- `AD` IDs stay stable: amend a Rule in place, never renumber, retire, or reuse an ID. No new `AD` is needed — every divergence here is a member-level addition already shipped and already justified.
- Declared **fields** and constructors of every verbatim-fixed type stay byte-identical to what ships. Only members already in the code are reflected.
- State what is true at refresh time. Where a row is known to change again — AD-9's accelerator, once DW-39's `dart:ffi` keybinder registrar lands — say so in the spine rather than pre-describing the future state.
- Spine frontmatter closes at `status: final`, `updated: '2026-08-14'`.
- The Stack table's two corrected rows must satisfy `lint_spine.py`'s `version_pin` rule (a non-empty version cell), exactly as the existing `` `claude` CLI … | on `PATH` `` row already does.

**Block If:**
- The Reviewer Gate surfaces a conflict that can only be resolved by adding, retiring, or contradicting an `AD`, or by changing a CAP or a frozen declaration's fields.
- `_bmad/scripts/memlog.py` cannot append to the existing run folder, so the update cannot be recorded before distillation.

**Never:**
- Edit `_bmad-output/implementation-artifacts/deferred-work.md` — the orchestrator records resolution.
- Edit `SPEC.md`, or add/remove/reword any CAP. The map keeps exactly 13 CAP rows.
- Change any Dart under `lib/`. The code is correct as shipped; the spine is what is stale.
- Restructure the composition root, invert `DaemonLifecycle`'s bare callbacks into an interface (one implementation — AGENTS.md §4.2), or add a Dart copy of the keybinder accelerator string.
- Restate the `claude_agent_sdk` or Flutter version number anywhere in the spine, or delete the pin gate.

## I/O & Edge-Case Matrix

Applies to the reworked reader in `test/architecture/sidecar_pin_drift_test.dart`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Citation resolves | Stack row version cell names a repo path; that file exists and pins exactly one version | Row passes | No error expected |
| Pin regrew a second home | Version cell restates a bare version (`3.44.8`) instead of citing a file | Row **fails**, naming the reintroduced duplicate | Explicit failure, not a skip |
| Citation dangles | Cell cites a path that does not exist, or the cited file pins nothing parseable | Row **fails** | Explicit failure |
| Cited file ambiguous | Cited file carries two pinning lines | Reader answers null; row **fails** | Ambiguity reads as absence |
| Row or section gone | No `## Stack` section, or no row of that name in it | Reader answers null; row **fails** rather than passing vacuously | Explicit failure |
| Same-named row elsewhere | A matching row in another table (Deferred, capability map, quoted example) | Reader answers null — only the `## Stack` section counts | Explicit failure |

</intent-contract>

## Code Map

- `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md` -- the artifact being refreshed. Stale at :253-267 (AD-9 block), :270 (accelerator prose), :334 (AD-17), :392 + :406 (Stack rows), :537 (envelope), :549 + :555 (map rows).
- `.../.memlog.md` -- append-only run memory; the Update intent resumes from this, not from the rendered spine.
- `.claude/skills/bmad-architecture/{SKILL.md,references/headless.md,references/reviewer-gate.md,scripts/lint_spine.py}` -- the Update + headless contract and the deterministic lint.
- `lib/src/domain/hotkey/global_hotkey.dart` -- ships `Future<HotkeyBindOutcome> bind(...)` (:63), a fourth member `Stream<HotkeyBindOutcome> get bindingChanges` (:55), and `operator==`/`hashCode` on `HotkeyRegistration` (:16-27) with fields untouched.
- `lib/src/domain/hotkey/hotkey_bind_outcome.dart` -- the sealed `HotkeyBindOutcome` (`HotkeyBound` | `HotkeyUnavailable`) AD-9's block does not show.
- `lib/src/domain/correction/{suggestion,preset,correction_event}.dart`, `lib/src/domain/hotkey/hotkey_binding.dart` -- the AD-2/AD-9 types carrying added `operator==`/`hashCode`.
- `lib/src/infrastructure/hotkey/hotkey_key_catalogue.dart:7-11` -- records the probed GTK 3 output `<Shift><Control>g`, and why no Dart builds the accelerator.
- `lib/main.dart`, `lib/src/application/composition/{daemon_graph,port_providers,controller_providers}.dart`, `lib/src/infrastructure/system/{daemon_startup,daemon_lifecycle}.dart`, `lib/src/infrastructure/correction/active_correction.dart` -- the real four-part composition. See Design Notes for the ownership split.
- `lib/src/application/{correction_controller,correction_state}.dart` -- CAP-4's `selectSuggestion`/`_completedTextOf` and CAP-11's `copySuggestion`/`copyFailure` live here, one ring inward of the map's rows.
- `test/architecture/sidecar_pin_drift_test.dart` -- the gate to rework. Keeps `pinnedInRequirements`, `flutterVersionInWorkflow`, `venvDirectoryInScript`, `_stackSection`.
- `assets/sidecar/requirements.txt`, `.github/workflows/ci.yml:81` -- the surviving single homes of the two pins.

## Tasks & Acceptance

**Execution:**

1. `.../.memlog.md` -- append one `(decision)` entry per correction below via `uv run _bmad/scripts/memlog.py append --workspace <run folder> --type decision --text "…"`, each naming what it amends and the divergence it removes -- the Update intent distils the spine from the memlog, so an unlogged change cannot survive re-distillation.
2. `ARCHITECTURE-SPINE.md` AD-9 -- amend the fixed declaration block: `bind` returns `Future<HotkeyBindOutcome>`; add the fourth member `Stream<HotkeyBindOutcome> get bindingChanges`; add the sealed `HotkeyBindOutcome` (`HotkeyBound` | `HotkeyUnavailable`) to the block. `HotkeyRegistration`'s and `HotkeyBinding`'s fields and constructors are unchanged -- DW-2, DW-65.
3. `ARCHITECTURE-SPINE.md` AD-2 and AD-9 -- state that the fixed types carry value equality (`operator==`/`hashCode`) with declared fields untouched, rather than showing every override verbatim -- keeps the blocks readable while ending the false claim that the shipped types match them exactly (DW-7).
4. `ARCHITECTURE-SPINE.md` AD-9 prose (:270) -- replace the `<Ctrl><Shift>g` illustration: no Dart under `lib/` builds an accelerator; `hkm_register` builds it in C with `gtk_accelerator_name`, and the probed GTK 3 output for Ctrl+Shift+G is `<Shift><Control>g`. Add that this changes when DW-39's FFI registrar lands -- DW-41.
5. `ARCHITECTURE-SPINE.md` AD-17 (and the Design Paradigm line that calls `main.dart` "the only place that knows both sides") -- replace the one-line claim with the four-part shape and where a reader should expect each half; keep the reason the split exists (`main()` is reachable by no test) -- DW-24.
6. `ARCHITECTURE-SPINE.md` Capability → Architecture Map -- add `application/correction_controller.dart` to the CAP-4 (:549) and CAP-11 (:555) rows, matching CAP-13's row -- DW-56.
7. `ARCHITECTURE-SPINE.md` Stack table -- the `claude_agent_sdk` and `Flutter (stable)` version cells cite `assets/sidecar/requirements.txt` and `.github/workflows/ci.yml` instead of restating `0.2.132` / `3.44.8` -- DW-90.
8. `ARCHITECTURE-SPINE.md` Operational envelope (:537) -- stop claiming every runtime dependency merely degrades: `libkeybinder-3.0-0` is **hard** today (the plugin library carries it as `DT_NEEDED`, so the loader fails before `main()`), stated as a meanwhile clause until DW-39's registrar makes absence a caught error -- DW-40.
9. `ARCHITECTURE-SPINE.md` frontmatter -- `updated: '2026-08-14'`, `status: final`.
10. `test/architecture/sidecar_pin_drift_test.dart` -- add a citation reader over the `## Stack` section and rewrite the two real-file rows against the matrix above; rewrite the file's header doc, which currently describes two duplicated versions that no longer exist. Keep the venv/`SidecarHostPaths` row and every existing pure-parser self-test; add self-tests for the new reader.
11. `.github/workflows/ci.yml:76-79` -- rewrite the comment: the workflow is now the single home of the Flutter version and the spine cites it, rather than "pinned to the spine's Stack table … the third home of the version".

**Acceptance Criteria:**
- Given the refreshed spine, when a reader follows AD-9 to write a `GlobalHotkey` implementation, then the declarations they copy compile against `lib/src/domain/hotkey/global_hotkey.dart` unchanged.
- Given the refreshed spine, when the Capability → Architecture map is read for CAP-4 and CAP-11, then it names the application component their behaviour lives in, and the table still holds exactly 13 CAP rows.
- Given the refreshed spine, when the Stack table is searched for `0.2.132` or `3.44.8`, then neither appears anywhere in the file.
- Given `assets/sidecar/requirements.txt` is edited to a new pin and nothing else changes, when the architecture suite runs, then it stays green — the version now has one home, so there is nothing to diverge.
- Given the `claude_agent_sdk` Stack row is edited back to a bare version number, when the architecture suite runs, then it fails naming the reintroduced second home.
- Given the whole change, when `git diff --name-only` is inspected, then it lists only the spine, its memlog, `test/architecture/sidecar_pin_drift_test.dart`, and `.github/workflows/ci.yml` — no file under `lib/` and not `deferred-work.md`.

## Spec Change Log

No entries — no `bad_spec` loopback occurred.

## Review Triage Log

### 2026-08-14 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 1, medium 3, low 4)
- defer: 7: (high 0, medium 5, low 2)
- reject: 14
- addressed_findings:
  - `[high]` `[patch]` `citedPathInStackTable` caught only the *bare-number* revert: a cell reading ``3.44.8 (pinned in `.github/workflows/ci.yml`)`` returned the path and passed, restoring the second writable home while the gate stayed green (reproduced directly before the fix). The reader now strips the backticked span and rejects the cell if the remaining text still carries a version shape; fixtures added for the additive revert and for a version-shaped segment inside a cited path.
  - `[medium]` `[patch]` Both real-file rows validated the spine's claim against itself — `requirementsPath`/`workflowPath` survived only inside failure-message text, so any repo file that happened to parse passed. Both now assert `cited` equals the authoritative home before the existence and parse checks.
  - `[medium]` `[patch]` The new `.github/workflows/ci.yml` comment asserted the workflow is "the single home" and "nothing else needs editing", contradicted by `.devcontainer/Dockerfile:111` (`ARG FLUTTER_VERSION=3.44.8` plus a coupled `FLUTTER_SHA256`) and `pubspec.yaml:9`. Comment corrected to name both ungated copies; neither file edited.
  - `[medium]` `[patch]` The AD-5 amendment moved `(CorrectionProvider, Preset)` resolution out of `main.dart`, but the CAP-8 map row still named it — a contradiction this change created in the table it was correcting. Row repointed at `active_correction.dart`, `provider_registry.dart`, `domain/config`; capability text, *Governed by*, and the 13-row count untouched.
  - `[low]` `[patch]` The citation reader's containment guard rejected only a leading `/` while its doc claimed "inside this repository"; `../elsewhere/ci.yml` was accepted (reproduced). Now rejects `..` segments and `://`, with fixtures.
  - `[low]` `[patch]` Both new equality Rules constrained `operator==` and stopped, setting a trap for a reader copying the block (`Object.hash` over a `Set` is an identity hash; a `List` field compared with `==` is identity). One clause added to each Rule covering collection comparison and matching hashing.
  - `[low]` `[patch]` The `DT_NEEDED` claim was stated as timeless fact in a `status: final` document, though DW-40's history shows its first evidence was wrong. Now qualified with measurement date, tool, and the plugin package version, with a re-measure trigger.
  - `[low]` `[patch]` `_citingSpine` used paraphrased row names, so the unit group never exercised the real row-name shapes the real-file group depends on. Fixture now uses the real row strings verbatim plus a `claude_agent_sdk_extras` row above the real one, proving the name-boundary guard in the citing shape.

Deferred findings were listed under this pass's `## Auto Run Result` block rather than appended to the deferred-work ledger: that invocation stated the orchestrator records ledger changes and forbade this run from editing it. That block is rewritten each run and has since been rotated out, so those seven findings now live only in commit `ad3abb1`'s revision of this file (`git show ad3abb1:_bmad-output/implementation-artifacts/spec-dw-2-spine-currency-refresh.md`, under **Deferred: 7**). They were never filed in the ledger — see this run's `## Auto Run Result` residual risks.

### 2026-08-14 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 8: (high 1, medium 4, low 3)
- defer: 12: (high 0, medium 7, low 5)
- reject: 14
- addressed_findings:
  - `[high]` `[patch]` The anti-regrowth check the previous pass added reads only the row's **version** cell, so the number could be fully restored in the row *name* cell, in the `## Stack` section's prose, or as an added row of another name, with the gate green. Reproduced against the committed reader before fixing (name-cell revert and duplicate row both returned the cited path). `citedPathInStackTable` now runs the version-shape test over the whole row, and a new section-wide row asserts the spine states neither cited version anywhere — reading both numbers *from the homes the spine cites*, so the assertion cannot itself become a third copy. All four bypass shapes were probed red after the fix and the spine restored clean.
  - `[medium]` `[patch]` `pinnedInStackTable` used `firstMatch`, so two Stack rows of one name were answered by the first — a citation row with a bare-number row beneath it passed. Its two sibling readers refuse ambiguity by design; this one guessed. Now `allMatches` with a single-match requirement, and the failure message says which of the two conditions fired.
  - `[medium]` `[patch]` AD-12's Rule was portal-only (`CreateSession`/`BindShortcuts`) while the previous pass made `HotkeyUnavailable` the universal degradation arm of AD-9's sealed type and made the Structural Seed attribute it to `(AD-9, AD-12)` — a contradiction that pass created, with seven shipped sites citing AD-12 for non-portal cases. Rule widened in place through one `bmad-architecture` Update pass. The widening falsified two adjacent claims, both amended in the same pass: the old Rule's "unavailable on this compositor" wording (false when a working backend refuses one key) and AD-12's own heading, now *Any refusal to hold the hotkey degrades visibly*, with a generalising *Prevents* clause that keeps the wlroots sentence verbatim as the worked example. No `AD` added, retired, or renumbered; **Binds** byte-identical.
  - `[medium]` `[patch]` `.github/workflows/ci.yml`'s new comment asserted the ungated `.devcontainer/Dockerfile` and `pubspec.yaml` Flutter copies were "carried as deferred work"; the ledger had zero entries naming any of them. Made true by filing the entry rather than by softening the claim — the gap is real and worth tracking. (The spine's parallel wording, "further hand-maintained copies that no gate covers", was already accurate and was left alone.)
  - `[medium]` `[patch]` The envelope's new hard-dependency clause sat in a list that annotates `libkeybinder-3.0-0` as `(X11 hotkey)`, beside a Stack note binding `hotkey_manager` "for the X11 adapter only" — so a packager would reasonably scope the hardness to X11 hosts and ship a Wayland build that cannot start. Re-measured: the runner's own `DT_NEEDED` carries the plugin `.so`, which carries `libkeybinder-3.0.so.0`, and `generated_plugins.cmake` links every plugin unconditionally, so the loader resolves the chain before `main()` and therefore before `DisplayServer.fromEnvironment`. Clause now states the hardness precedes the adapter choice.
  - `[low]` `[patch]` `citedPathInStackTable` never trimmed the backticked span, so a padded citation answered `" .github/workflows/ci.yml "` and the real-file row went red on a substantively correct spine with a diff of invisible whitespace — a false red on a gate DW-88 records as never having run. Now trimmed, with an empty-citation guard.
  - `[low]` `[patch]` `_uncitedFailure` re-derived the reader's version-detection rule by copy, so changing the rule (as the high finding required) would have left the gate failing for one reason and naming another. Both now call one `_restatesAVersion` helper, and the message quotes the same row text the rule was applied to.
  - `[low]` `[patch]` The Stack heading note claimed the numbers "have not been re-verified since" 2026-08-06 while this change's own Reviewer Gate currency report re-verified every row on 2026-08-14 and found `drift_flutter 0.3.1` is no longer a dependency — so the note disclaimed work that happened and shielded a row known to be false. Restated to say what was re-verified, that upstream currency was not, and that the one stale row is carried under DW-94 rather than silently wrong. The row itself and the pin-renegotiation paragraph were left to DW-94.

The twelve deferred findings were appended to `_bmad-output/implementation-artifacts/deferred-work.md` as new entries, per this invocation's instruction; no existing entry was modified, re-opened, or rewritten (the ledger diff's only deletions are the orchestrator's own seven `status: open` flips, which predate this run).

### 2026-08-14 — Review pass (follow-up 2)

- intent_gap: 0
- bad_spec: 0
- patch: 11: (high 3, medium 2, low 6)
- defer: 9: (high 0, medium 3, low 6)
- reject: 17
- addressed_findings:
  - `[high]` `[patch]` `_restatesAVersion` stripped **every** backticked span before testing for a version, so the number could be restored inside backticks and be invisible to the rule written to refuse it. Reproduced against the committed reader: `` | Flutter (stable) `3.44.7` | pinned in `.github/workflows/ci.yml` | `` cited the right file, restated a wrong number, and passed 34/34. Backticks in a Stack name cell are ordinary here — `` `claude` CLI `` is a real row. Only spans a new `_looksLikePath` accepts are stripped now, so a path keeps its digits hidden and a version cannot hide behind punctuation.
  - `[high]` `[patch]` The section-wide anti-regrowth assertion was **value**-scoped (`spine.contains(version)`), so it saw a duplicate row only while the duplicate still *agreed* with the cited home — the one state in which a second copy is harmless. Reproduced: `| Flutter toolchain | 3.44.7 |` added to the Stack table left all 34 rows green; the same row with `3.44.8` went red. Replaced with three subject-scoped checks: exactly one Stack row may name each subject, no table row anywhere in the spine may state a version for either subject in any column, and no prose line may name a subject beside its cited number.
  - `[high]` `[patch]` The same unanchored substring scan produced a false red on a correct spine, falsifying this spec's own acceptance criterion that editing the pin and nothing else keeps the suite green. Reproduced: bumping `claude-agent-sdk` to `0.7.14` — a plausible next version — turned the suite red against the unrelated `| dbus | 0.7.14 |` row, with a message accusing the spine of holding a second writable copy that did not exist. Six of the sdk's real version numbers are already literals in this table. Gone with the subject scoping; re-probed green.
  - `[medium]` `[patch]` `_stackRow`'s regex ended at the second pipe while `citedPathInStackTable`'s doc said the version check "runs over the whole row", so a version in a third column was outside every rule that reads a row. Row capture now reaches end of line, with a fixture for the third-column shape.
  - `[medium]` `[patch]` AD-12's Rule justified its message contract on "because the screen appends nothing" — false against `hotkey_status_view.dart:126-130`, which appends one line. The widget's own doc shows the intended claim is that nothing is appended *about the fallback*, and that the added line (claiming no ownership regime) "must not regress". Corrected through one `bmad-architecture` Update pass, not a hand-patch. Its Reviewer Gate caught three defects in the first draft and one adjacent claim the correction falsified — the Ratified Divergence's unqualified "the settings screen shows which regime is active", true only while a combination is in effect (`settings_screen.dart:141-146` returns null authority on the `HotkeyUnavailable` arm) — amended in the same pass with every ratified word preserved.
  - `[low]` `[patch]` `!cited.contains('/')` made a repo-root citation unrepresentable, so the reader forbade `pubspec.yaml` — the next home the ledger itself plans to gate — and reported it as "cites no file this gate can resolve". Replaced with a path-shape test; the extension requirement is what now separates a citation from a version.
  - `[low]` `[patch]` The cited path was trimmed but not normalised, so `./a/b.txt`, `a//b.txt` and `a/./b.txt` resolved as files and then failed the caller's equality assert with a diff of punctuation — the same false-red class the trim was added for one pass earlier.
  - `[low]` `[patch]` An empty version cell fell through to the branch that interpolates the cell, producing `Stack row reads "null"` — text quoting nothing and naming no edit. Its own branch now, pointing at `lint_spine.py`'s `version_pin` rule, which catches that one shape faster.
  - `[low]` `[patch]` The Structural Seed omitted `unconfigured_correction_provider.dart`, the AD-15/AD-19 fallback provider, in the one directory the previous pass had just completed. Added in the same Update pass.
  - `[low]` `[patch]` This spec shipped an unresolved `{deferred_work_file}` template token, and pointed the first pass's seven deferrals at an `## Auto Run Result` section no longer in the file. Token resolved; the pointer now names the revision those seven survive in (`ad3abb1`) and the entry filed for them.
  - `[low]` `[patch]` `pubspec.yaml:11-14` still claimed versions are "pinned to the architecture spine's Stack table (verified 2026-08-06)" — false for Flutter since the table now cites `ci.yml` — and `:47` still read "unsatisfiable on Flutter 3.44.8" where the spine's identical sentence was de-numbered in this change. Both corrected; the header now names the two ungated hand-maintained copies. Not forbidden by the Never list, which covers Dart under `lib/`.

The nine deferred findings were appended to `_bmad-output/implementation-artifacts/deferred-work.md` as new entries, per this invocation's instruction; no existing entry was modified, re-opened, or rewritten — the ledger diff is purely additive (45 insertions, 0 deletions).

## Design Notes

**The four-part composition (task 5), verified in the code:**

- `main.dart` — constructs the vendor adapters, installs `UncontrolledProviderScope` over the container `DaemonGraph` holds (note: *not* `ProviderScope`, as AD-17 currently says), sequences the platform half of startup, owns the pre-lifecycle abort path and the signal handlers. Reachable by no test — `composition_wiring_test.dart` scans it as **text**, 25 rows.
- `application/composition/` — `port_providers.dart` declares one typed seam per port; `controller_providers.dart` constructs the controllers; `daemon_graph.dart` eagerly builds them and owns controller dispose order.
- `infrastructure/system/daemon_startup.dart` — the pre-Flutter startup order (AD-14 → AD-13 → AD-9 → AD-5), including the display-server adapter choice. `daemon_lifecycle.dart` — the 11-step runtime teardown order.
- `infrastructure/correction/active_correction.dart` — AD-5's `(CorrectionProvider, Preset)` pair resolution.

The two infrastructure files sit there deliberately: `main()` is reachable by no test, so anything left inside it is unverifiable. AD-1 is not violated on any reading — `ad1_import_rule_test.dart` is untouched and green.

**Shape of the reworked gate (task 10)** — a citation reader beside the existing pin readers, sliced to the `## Stack` section by the existing `_stackSection`:

```dart
/// The repo-relative path the `## Stack` row for [rowName] cites, or null when
/// the cell cites nothing — including when it restates a bare version, which is
/// the second home growing back.
String? citedPathInStackTable(String source, {required String rowName});
```

The bare-version check is the load-bearing half: without it the gate would pass a row that quietly reverted to restating the number.

## Verification

**Commands** (prefix with `export PATH="$PATH:/home/vscode/flutter/bin"`):
- `python3 .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06` -- expected: zero `placeholder`, `ad_id`, `ad_fields`, and `version_pin` findings.
- `dart analyze --fatal-infos` -- expected: no issues found.
- `dart test test/architecture/sidecar_pin_drift_test.dart` -- expected: all rows pass, including the new citation self-tests.
- `dart test test/architecture/` -- expected: green, `ad1_import_rule_test.dart` and `composition_wiring_test.dart` unchanged and passing.
- `grep -n '0\.2\.132\|3\.44\.8\|Future<HotkeyRegistration>' <spine>` -- expected: no matches.
- `grep -c '^| CAP-' <spine>` -- expected: `13`.
- `git diff --name-only` -- expected: exactly the four files named in the last acceptance criterion.

**Manual checks:**
- The Update pass returned headless JSON with `status: complete` (or `partial` with `open_questions[]` recorded), `intent: update`, and no entry in `conflicts_with_prior_decisions[]`.
- `git diff` on the spine shows no `AD` renumbered, none retired, and no new `AD` added.

## Auto Run Result

Status: done
Blocking condition: none

### Summary

A second follow-up review pass over the shipped spine refresh. The previous pass closed with `followup_review_recommended: true`; this run confirms that was right, and for the same reason twice over. Four review layers ran in parallel; **11 findings were patched, 9 deferred, 17 rejected**, with no `intent_gap` and no `bad_spec`.

The load-bearing result is that **the anti-regrowth gate was still open, in the shape the previous pass believed it had closed**. That pass hardened the check against a version restored in the row's *name* cell and recorded all four bypass shapes as "probed red". They were — but only while the reintroduced number still *equalled* the cited home. Two shapes were reproduced green against the committed reader: a stale `3.44.7` restored inside backticks (`_restatesAVersion` stripped every backticked span before testing), and a stale `3.44.7` in an added `| Flutter toolchain |` row (the section-wide assertion asked only whether the current number appeared anywhere). In both cases the gate saw the second writable home exactly while it was harmless and went blind the moment it drifted — the inverse of what it was written for.

The same value-scoped rule also produced a **false red on a correct spine**, falsifying this spec's own acceptance criterion that editing the pin and nothing else keeps the suite green: bumping `claude-agent-sdk` to `0.7.14` collided with the unrelated `| dbus | 0.7.14 |` row. Six of the sdk's real released versions are already literals in this table.

The fix replaces value scoping with subject scoping — one Stack row per subject, no table row anywhere stating a number for either subject in any column, no prose line naming a subject beside its cited number — and stops backticks hiding a version while still letting a cited path keep its digits. All four regrowth shapes were re-probed red afterwards and the false red re-probed green.

One spine amendment was needed and went through a `bmad-architecture` Update pass (memlog entry first, then re-distil, then Reviewer Gate — the spine is never hand-patched). AD-12's Rule justified its message contract on "because the screen appends nothing", which is false against the widget it describes.

### Files changed

- `test/architecture/sidecar_pin_drift_test.dart` — path-aware backtick stripping, whole-row capture, path-shape and normalisation rules for citations, three subject-scoped section checks replacing the substring scan, and an empty-cell failure branch. **44 rows (was 34)**, including regression fixtures for every shape reproduced in this pass.
- `.../ARCHITECTURE-SPINE.md` — 3 hunks, +3/−2: AD-12's fourth Rule bullet (premise corrected, `claims nothing` → `adds no claim of its own`), one Structural Seed row, and the Ratified Divergence scoped to "whenever a combination is in effect". Still 19 ADs (`AD-1`..`AD-19`, none renumbered, retired or added), 13 CAP rows, `status: final`, `updated: '2026-08-14'`.
- `.../.memlog.md` — 7 appended entries (2 amendment decisions, 1 consequence decision, 2 events, 1 gate record, 1 carried-questions entry).
- `pubspec.yaml` — two comments the re-homing falsified: the header's "pinned to the spine's Stack table (verified 2026-08-06)", and `3.44.8` restated in the pin-renegotiation note.
- `_bmad-output/implementation-artifacts/deferred-work.md` — 9 new entries, appended only.
- `_bmad-output/implementation-artifacts/spec-dw-2-spine-currency-refresh.md` — this record, plus the unresolved `{deferred_work_file}` token and the dangling `## Auto Run Result` pointer.
- Three `reviews/review-*-2026-08-14-amendments.md` — the previous pass's gate reports, untracked until now and part of this run's reviewed diff, so committed here.

No file under `lib/` was touched. No `AD` added, retired or renumbered; no CAP added, removed or reworded; no declared field or constructor of any verbatim-fixed type changed.

### Review findings

- **Patched: 11** (high 3, medium 2, low 6) — see the triage log entry above.
- **Deferred: 9** (medium 3, low 6), appended as new entries. The three with live consequence: `setHotkeyUnavailable` has one production caller, so a settings-initiated failed bind and a compositor revocation never reach the tray while AD-12's *Prevents* now covers exactly those paths (raised independently by the edge-case lens and by the architecture Reviewer Gate, which reported it as a blocker it would not resolve); AD-12's three widened obligations are ungated across 20 production sites; and **nothing gates the spine's code-shape claims at all** — reverting AD-9's `bind` return type to the stale signature this spec corrected leaves the whole architecture suite green (178 passed, 1 skipped), so the seventh drift would be as silent as the first six.
- **Rejected: 17** — chiefly: that the run exceeded the spec's "exactly four files" criterion and its "never edit `deferred-work.md`" prohibition (both are superseded by the orchestrator's standing instruction to append ledger entries, and the same argument was triaged reject last pass); that `review_loop_iteration: 0` and `final_revision` are stale (both are set by the workflow — the counter is reset for a follow-up review, the revision at finalize); that AD-9's block ships paraphrased doc comments (the intent freezes fields and constructors, and the paraphrase's meaning matches the code); that the memlog and gate reports restate the two numbers (a memlog entry recording what was removed necessarily names it); that the Stack note's "one known exception" is false (its claim is that every *row* matches the graph, which holds — the unfiled dependency behind the objection is deferred instead); that AD-12's message contract is unsatisfiable on a tray-less session (the same AD discloses that hole one bullet later); plus items already carried by open ledger entries and the intent-alignment layer's descriptive-only observations.

**Follow-up review recommended: true** — three high-severity patches set the flag regardless of score; the medium/low remainder scores 3×2 + 6 = 12. Independently warranted: the subject-scoping rules are new and their correctness depends on regexes that must not claim `flutter_riverpod`, `drift_flutter` or `flutter_lints`, which is asserted by fixture rather than by the real table's shape.

### Verification

| Check | Outcome |
|---|---|
| `lint_spine.py` | 1 low finding — `{sv}`, the D-Bus variant-dict false positive, unchanged from baseline. Zero `placeholder` / `ad_id` / `ad_fields` / `version_pin`. |
| `dart analyze --fatal-infos` | No issues found |
| `dart format --set-exit-if-changed` | 172 files, 0 changed |
| `dart test test/architecture/sidecar_pin_drift_test.dart` | 44/44 pass (was 34) |
| `dart test test/architecture/` | 178 pass, 1 pre-existing skip (DW-9, needs a display) |
| `grep '0\.2\.132\|3\.44\.8\|Future<HotkeyRegistration>'` on spine | No matches |
| `grep -c '^\| CAP-'` / `grep -c '^### AD-'` | 13 / 19; ids 1..19 monotonic, none missing or reused |
| Adversarial probe, pre-fix | Committed reader passed 34/34 with a stale pin restored in backticks, and again with a stale duplicate row |
| Adversarial probe, pre-fix | Committed reader went red on a legitimate `0.7.14` pin bump |
| Adversarial probe, post-fix | Backticked name cell, duplicate row, third column and Stack prose all go red; the `0.7.14` bump goes green; spine and `requirements.txt` restored clean afterwards |
| Ungated-spine probe | AD-9's `bind` reverted to `Future<HotkeyRegistration>` → 178 pass, 1 skip (green), reproducing the deferred verification gap; spine restored |
| Ledger append is additive | 45 insertions, 0 deletions |

### Residual risks and artifacts

- **Residual artifacts, left uncommitted** (`git status --porcelain` shows them): the three `reviews/review-*-2026-08-14-ad12-premise.md` gate reports this pass's Update emitted. They arrived after the reviewed diff was constructed, so they are not part of the reviewed change; the substance is in the committed memlog. Note the asymmetry this leaves — the previous pass's three `-amendments.md` reports *were* in the reviewed diff and are committed here. Either state is defensible and the orchestrator can normalise it; the underlying complaint about undisposed frozen gate reports is already an open ledger entry.
- **The Ratified Divergence gained a scoping qualifier.** Correcting AD-12 falsified its unqualified claim that "the settings screen shows which regime is active", so the Update pass added "whenever a combination is in effect". Every ratified word is preserved and the ratification itself (authoritative on X11, advisory on Wayland) is untouched, and the qualifier is verified against `settings_screen.dart:141-146`. Flagged because it is a human-ratified sentence: if it is held frozen verbatim, reverting costs one clause and reopens a spine self-contradiction.
- **The prose half of the anti-regrowth rule has a stated residual.** A prose line that states either number without naming its subject anywhere on that line is not caught. This is deliberate: subject-and-value-on-one-line is what removes the false-red class, and the residual fails in the safe direction only in the sense that it stays green — it is documented in the test rather than hidden.
- **Subject scoping rests on two regexes.** `(?<![\w-])[Ff]lutter(?![\w-])` must keep excluding `flutter_riverpod`, `drift_flutter` and `flutter_lints`, all of which are real Stack rows with versions of their own. A future row named, say, `Flutter Engine` would be read as a second home for the toolchain. Fixtures cover both directions; the failure direction is red, not green.
- **`.github/workflows/ci.yml` was not re-edited** in this pass. DW-88 still records that it has never executed, so the Flutter citation points at a file no runner has run — a spec-directed choice, disclosed at `ci.yml:3` and carried on the ledger.
- The full `dart test` suite still shows intermittent failures in `wayland_portal_global_hotkey_test.dart` / `single_instance_lock_test.dart` with a count that differs between runs — pre-existing cross-suite flakiness (DW-46), unrelated to this change and unchanged by it.
