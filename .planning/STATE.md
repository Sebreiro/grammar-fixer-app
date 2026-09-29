---
gsd_state_version: "1.0"
status: Awaiting next milestone
stopped_at: Phase 02 complete — all phases complete
last_updated: "2026-09-27T23:18:00.000Z"
last_activity: 2026-09-27
last_activity_desc: Raised quick task 260927-l2c coverage gate to 90% for lines and branches
state_head: 57b0c6b764aa37c3d4cd1305f3e5f082a705563a
progress:
  total_phases: 2
  completed_phases: 2
  total_plans: 53
  completed_plans: 53
  percent: 100
current_phase: 02
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-26 after v1.0)

**Core value:** The daemon corrects text reliably on both display servers and never loses, corrupts, or leaks the user's text
**Current focus:** Planning the next milestone; no new phase is active

## Current Position

Phase: Milestone v1.0 complete
Plan: —
Status: Awaiting next milestone
Last activity: 2026-09-27 — Raised quick task 260927-l2c coverage gate to 90% for lines and branches

## Performance Metrics

**Velocity:**

- Total plans completed: 53
- Average duration: 25.4 min
- Total execution time: 10h 35m

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 — Hotkey Truth | 25 | 10h 35m | 25.4 min |
| 02 | 28 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 6 min | 3 tasks | 1 files |
| Phase 01 P02 | 64 min | 3 tasks | 23 files |
| Phase 01 P03 | 20 min | 2 tasks | 7 files |
| Phase 01 P04 | 1h 45m | 3 tasks | 13 files |
| Phase 01 P05 | 33 min | 2 tasks | 12 files |
| Phase 01 P06 | 26 min | 3 tasks | 14 files |
| Phase 01 P07 | 41 min | 2 tasks | 25 files |
| Phase 01 P08 | 15 min | 2 tasks | 3 files |
| Phase 01 P09 | 11 min | 1 tasks | 17 files |
| Phase 01 P10 | 38 min | 2 tasks | 1 files |
| Phase 01 P11 | 11 min | 2 tasks | 1 files |
| Phase 01 P12 | 50 min | 2 tasks | 10 files |
| Phase 01 P13 | 35 min | 2 tasks | 4 files |
| Phase 01 P14 | 22 min | 2 tasks | 8 files |
| Phase 01 P15 | 16 min | 2 tasks | 1 files |
| Phase 01 P16 | 15 min | 2 tasks | 2 files |
| Phase 01 P17 | 31 min | 2 tasks | 3 files |
| Phase 01 P18 | 11 min | 2 tasks | 5 files |
| Phase 01 P19 | 20 min | 2 tasks | 6 files |
| Phase 01 P20 | 14 min | 2 tasks | 1 files |
| Phase 01 P21 | 9 min | 3 tasks | 2 files |
| Phase 01 P22 | 5 min | 1 tasks | 1 files |
| Phase 01 P23 | 26 min | 2 tasks | 3 files |
| Phase 01 P24 | 5 min | 1 tasks | 1 files |
| Phase 01 P25 | 6 min | 2 tasks | 3 files |
| Phase 02 P01 | 8min | 2 tasks | 7 files |
| Phase 02 P05 | 10min | 2 tasks | 3 files |
| Phase 02 P02 | 9min | 2 tasks | 3 files |
| Phase 02 P06 | 13min | 2 tasks | 5 files |
| Phase 02 P13 | 7min | 2 tasks | 2 files |
| Phase 02 P03 | 12min | 2 tasks | 9 files |
| Phase 02 P07 | 20min | 2 tasks | 8 files |
| Phase 02 P04 | 9min | 2 tasks | 5 files |
| Phase 02 P08 | 5min | 2 tasks | 3 files |
| Phase 02 P14 | 11min | 2 tasks | 4 files |
| Phase 02 P09 | 18min | 2 tasks | 5 files |
| Phase 02 P11 | 11min | 2 tasks | 5 files |
| Phase 02 P15 | 17min | 2 tasks | 7 files |
| Phase 02 P16 | 11min | 2 tasks | 8 files |
| Phase 02 P10 | 10min | 2 tasks | 3 files |
| Phase 02 P17 | 12min | 2 tasks | 6 files |
| Phase 02 P12 | 7min | 2 tasks | 2 files |
| Phase 02 P18 | 9min | 2 tasks | 8 files |
| Phase 02 P20 | 4min | 2 tasks | 1 files |
| Phase 02 P19 | 18min-plus-continuation | 2 tasks | 5 files |
| Phase 02 P21 | 26min | 2 tasks | 9 files |
| Phase 02 P22 | 10min | 2 tasks | 6 files |
| Phase 02 P23 | 18min | 2 tasks | 5 files |
| Phase 02 P24 | 9min | 2 tasks | 7 files |
| Phase 02 P25 | 7min | 2 tasks | 1 files |
| Phase 02 P26 | 8min | 2 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [2026-09-23]: Phase 01 completed with explicit maintainer waivers: the CI merge-gate measurement remains 7/8, seven live UAT checks are accepted without observation, and two real-compositor truths remain unobserved. Plan 01-25 closed the clipboard-safety gap. The UAT and verifier records retain each evidence limit.
- [2026-08-31]: All test, gate, CI, runtime-observation and review-pass work removed from scope at the user's direction — 38 of 88 requirements deleted outright, taking Phase 1 (Gate Reality), Phase 9 (Runtime Observation) and Phase 10 (Deferred Review Passes) with them. Ledger entries stay `status: open` in `deferred-work.md`; the milestone simply does not schedule them.
- [2026-08-31]: LEDGER-01 (ledger append-only discipline) rehomed from the deleted gate phase to Phase 7, the surviving phase that owns documentation discipline.
- [Roadmap]: ARCH-02 (packaging) sits in Phase 1 rather than the documentation phase, because a Flatpak choice would delete the `Registry.Register` call the portal adapter rewrite builds on.
- [Roadmap]: PROVIDER-* is late by dependency, not by priority — three prerequisites gate it (`onDone` rule, bounded teardown, `SecretStore`).
- [Roadmap]: No data-safety phase. The history/sqlite cluster is entirely `parked` in the ledger and maps to zero of the 50 requirements.
- [Phase 01]: Packaging: three formats — .deb/tarball, Flatpak, AppImage — no primary build, none second-class. Supersedes DW-89 four-format decision of 2026-08-14; the native Arch PKGBUILD is dropped. — ARCH-02 asks only that the format be decided and recorded, and two ratified records disagreed by one format. Flatpak is in every candidate set and is the only member that changes the portal handshake, so the code consequence is identical either way; what the answer settles is what the ledger records and what the deferred packaging phase must build.
- [Phase 01]: GlobalHotkey current-registration member: status-type — HotkeyStatus? get current, returning a new domain type with outcome plus a nullable backendDescription, synchronous. HOTKEY-03 localized description rides the same member. — An addition to AD-9 verbatim block leaves every declared field of HotkeyRegistration, HotkeyBound and HotkeyUnavailable untouched, so the in-tree bindingChanges precedent covers it without a fresh spine ratification — and folding the HOTKEY-03 description carrier onto the same member spends one AD-9 gate instead of two.
- [Phase 01]: ARCHITECTURE-SPINE.md is not edited by Phase 1; the reconciliation for all four AD-9 declaration edits plus AD-11 step 1 is filed as a Phase-7 (ARCH-06) hand-off entry in the ledger. — The in-tree precedent forbids hand-editing the spine, so the hand-off entry is how the reconciliation survives the phase instead of being discovered late.
- [Phase 01]: X11 rebind is an atomic swap inside the seam: acquire the new grab, confirm it against the server, then release the old — so a refused grab leaves the previously working shortcut held — D-10 requires that a user who asks for a combination another application owns keeps the shortcut they had; the old release-first ordering existed only because the removed vendor plugin held two registrations, and X allows one client several passive grabs with synchronous BadAccess
- [Phase 01]: The already-held short-circuit compares against what is HELD, never what was REQUESTED — measured: X accepts a self re-grab and one XUngrabKey removes it, so an identical rebind without the short-circuit would silently leave nothing grabbed — The plan assumed X refuses a self re-grab with BadAccess; it does not. The short-circuit is still load-bearing, for the opposite reason, and a refusal is never recorded as held so the recovery path stays open
- [Phase 01]: 01-04: HotkeyUnavailable gains a required, defaultless HotkeyUnavailableCause{noBackend,keyRefused,revoked} beside the retained message — ratified 2026-09-01 as an edit to AD-9's verbatim field list (spine 274-278). Spine not edited; Phase 7 reconciles, ledger record owed to plan 01-10.
- [Phase 01]: 01-04: hotkey_status_view selects its first line from the cause, never from message content; none of the three cause sentences names the tray (the adapter messages already do), and _trayFallback covers D-07 only on the empty-message path.
- [Phase 01]: 01-05: BindShortcuts is bounded on a derived multiple of the injected budget (x12, one minute), not left unbounded — the must_haves truth requires a portal that never answers to return control in bounded time, and BindShortcuts is where a portal stops answering. — Leaving the dialog step unbounded would leave the widest hang open; a few seconds is not long enough for a person to read a dialog. Derived by a named integer factor so exactly one Duration is authored in the adapter.
- [Phase 01]: 01-05: A timeout abandons and sends nothing — an abandoned BindShortcuts leaves its session tracked (not closed, not forgotten), so a late Allow still toggles the panel and a rebind still closes it, while the bind's own answer stays HotkeyUnavailable(keyRefused). — Closing cancels the dialog the user is reading (plan prohibition); forgetting leaves an untracked live session on the compositor (threat T-01-26). Tracking satisfies both.
- [Phase 01]: 01-05: PortalAppIdRegime{hostRegistry,sandboxSupplied}.fromEnvironment keys ONLY on /.flatpak-info and FLATPAK_ID; resolved once in main.dart and injected through DaemonStartup.begin. Measured 2026-09-02: only /.dockerenv fires in this container — /run/.containerenv, $container and cgroup v2 do not — so all four stay rejected on the wider objection, not on a local measurement. — Answers the adapter's own recorded objection with a measurement instead of overruling it. Corrects the plan's claim that all four markers fire here.
- [Phase 01]: 01-06: GlobalHotkey gains HotkeyStatus? get current — synchronous, no I/O, null until a backend has answered; the portal's trigger_description is carried on it verbatim and never parsed, and the settings screen renders the reported combination on X11 and the desktop's own wording on Wayland with the authoritative/advisory regime label gone (D-03, D-04). — Names are as ratified in 01-01 (HotkeyStatus, outcome, backendDescription, current), so plan 01-10's ledger closure can quote the code. The description had to be plumbed through SettingsState (three files outside the plan's list) or Task 3's Wayland branch would have been an unreachable stub.
- [Phase 01]: 01-07: Task 1 answered `explain-in-place` (user, 2026-09-02): the capture shows a standing hint that the current shortcut cannot be re-captured plus a plain "keep current" affordance. No grab release during capture and no timeout heuristic. The hint renders BEFORE the first keypress, and only where authority == application, because under the portal ordinary key events do reach a focused window and claiming otherwise would be false. — A4 was measured on 2026-09-02: a held X11 grab means the focused window receives the modifier down/up events and never the terminating key, so absence of a key event is byte-identical to a user idly pressing Ctrl+Shift. Confirmed end-to-end this session on the real settings screen under Xvfb: pressing the held shortcut toggled the panel and never reached the capture box.
- [Phase 01]: 01-07: the registrable key vocabulary crosses AD-1's rings as a domain value, not an import — `RegistrableKeys` behind a new `registrableKeysProvider` seam (port_providers.dart:103), overridden only in main.dart with `HotkeyKeyCatalogue.registrableKeys()`, landing on `SettingsController.captureValidator` as a field rather than on SettingsState. — DW-71's "supplied by SettingsController" cannot mean the controller imports the catalogue: AD-1's application rule forbids it exactly as firmly as its ui rule, and both fail on the directive. A field rather than a state value because the vocabulary never changes, and 01-06 already paid the cost of threading a value through all five SettingsState transitions.
- [Phase 01]: 01-07: AltGr is refused on the LOGICAL LogicalKeyboardKey.altGraph, never on the physical altRight, and never folded into HotkeyModifier.alt; the dissolved seven-label wrong-key set and its predicate were removed outright rather than left empty. — Flagged assumption A3 is now measured, not assumed: ISO_Level3_Shift+g driven at the running daemon under Xvfb produced the Level-3 refusal with its own sentence. Keying on physicalKey.altRight instead would have refused a legitimate Alt combination on every layout with no Level 3. The label set was removed rather than emptied because an always-false predicate leaves branches that can never run (AGENTS.md 1); its measurement survives as a doc paragraph and DW-43 closes as resolved.
- [Phase 01]: 01-08: the precedence between GlobalHotkey's two writers is stated in the PORT, not the consumer — a bindingChanges event observed after a bind() was issued supersedes that bind's return value, same-turn arrivals included (the tie goes to the backend), with 'observed' defined as the moment the consumer's listener runs. Rationale (AD-10's compositor authority, D-01's currently-in-effect requirement) and the reachability boundary ride in the same doc: the startup inversion is protocol-legal but unreachable on the shipped adapter, which subscribes to ShortcutsChanged only after _bindShortcut returns.
- [Phase 01]: 01-08: the controller-side mechanism is SettingsController._backendChangeGeneration (final name; the plan's working name _bindGeneration was rejected because the counter counts changes observed, not binds issued) — an int beside the state, stamped before the bind is issued, bumped by _onBindingChanged, compared with != so any move supersedes. On a discard the surviving change's description is CARRIED, never re-read from GlobalHotkey.current, and the mutation's own SettingsFailure is still rendered: what is in effect and whether the user's change landed are two different facts.
- [Phase 01]: 01-09: HotkeyBinding's declared constructor drops `const` and assigns `Set<HotkeyModifier>.unmodifiable(modifiers)` in its initializer list, mirroring HotkeyGrab. Task 1's blocking-human gate was answered `defensive-copy` by the ORCHESTRATOR under an unattended run, NOT ratified by a human — Phase 7's ARCH-06 must re-confirm before editing the spine. — HOTKEY-09's text mandates a mechanism ("defensively copy or wrap"), which eliminates document-the-rule as prose-only, and a `const` constructor cannot call Set.unmodifiable, which eliminates unmodifiable-view-const. No live defect existed: every lib/ site already passed a fresh set literal. This is API hardening, and the field doc says so.
- [Phase 01]: 01-09: the plan's cost model was verified and corrected — 16 literal `const HotkeyBinding(` sites (count right, file list short by settings_screen_hotkey_test.dart) PLUS 34 further `const` keywords in implicit const contexts across 10 files, 7 of them undeclared. 50 non-declaration `const` keywords over 17 files; found by dart analyze in three cascading passes (40 -> 16 -> 7 -> 0) while the plan's grep already printed clean. — A `const` removal on a widely-constructed type has two cost classes and a literal-string grep only sees one. The mutation guarantee was proven by AMENDING the existing order-independence equality row rather than adding one, so the `test(` count stays 983 while HOTKEY-09's mechanism still has evidence.
- [Phase 01]: HOTKEY-10 closed as DISSOLVED, not implemented: plan 01-02 removed hotkey_manager/libkeybinder from the tree, so the re-measure trigger the requirement asked to re-key has no subject left. No re-keying was invented. — grep -c hotkey_manager pubspec.lock returns 0, and libX11.so.6 is already an unconditional DT_NEEDED of libgdk-3.so.0, so no new hard dependency appears and none needs a trigger. Manufacturing a target would have converted an honest closure into a fabricated one; the plan prohibits it.
- [Phase 01]: Six new open ledger entries filed rather than the plan four, and two supersessions stated in writing rather than papered over (DW-39 route, DW-71 per-display-server difference). — The plan must_haves require a Phase-7 record of every AD-9 declaration edit, and plan 01-05 SUMMARY explicitly asked 01-10 to file two entries not one. The +4 summary-count gate is therefore wrong by two; filing fewer would have lost owed work.
- [Phase 01]: 01-11: the toggle oracle classifies from an xev structure/focus stream by UnmapNotify/MapNotify counts and order inside a fixed 1000 ms settle window, never from xwininfo Map State; empty xev output is a halt, never the NOTHING verdict. Pre-fix baseline recorded: show=SHOW hide=FLICKER alternate=SHOW,FLICKER,FLICKER,FLICKER focus-steal=HIDE desktop-click=HIDE foreign-grab=HIDE. — Map State reads IsViewable on both sides of the measured 8-16 ms flicker, so a state oracle passes on a broken build. The event-stream oracle catches it: measured FocusOut(NotifyGrab) +0 ms, UnmapNotify +3 ms, MapNotify +14 ms on the unfixed 2026-09-04 bundle.
- [Phase 01]: 01-11: three measured <interfaces> facts were corrected — the daemon pid is resolved by /proc/<pid>/exe (the bracketed pattern also matches dbus-run-session's own command line), the toplevel filter needs _NET_WM_WINDOW_TYPE_NORMAL on top of _NET_WM_PID + Map State (the class also matches GTK's 10x10 group-leader window), and toplevel resolution retries on the live pid because a reaped daemon keeps its windows until X tears the connection down. — Each of the three halted every run with a named reason rather than producing a wrong verdict, which is the behaviour the plan's prohibition demanded; the fixes touched the plumbing only and the six predicted verdicts were then reproduced exactly.
- [Phase 01]: DW-9, DW-26 and DW-44 are NOT reopened: the refutation of the premise they were closed under is filed as DW-123, which names all three, because rewriting a closed entry status is the append-only violation DW-13 and DW-108 record. A human may reverse this call.
- [Phase 01]: Append-only is measured with git diff --numstat deletions column AND a required non-zero additions count, not by grepping the diff for a leading minus: a deleted markdown bullet defeats the grep form, and a deletions-only check passes vacuously post-commit.
- [Phase 01]: A test/platform skip reason may only lose a claim this container has ACTUALLY observed, and a retired claim is retired with its evidence rather than by deleting the sentence; desktop_entries_live_test.dart was left byte-identical because every claim in it is still true.
- [Phase 01]: 01-16: the X11 seam-refused arm reads the refusal CODE, not merely whether a previous binding was recorded — a workerGone/noBackend refusal mid-rebind clears _effective and returns HotkeyUnavailable(noBackend); keyRefused, badRequest and non-refusal rejections still return HotkeyBound naming the previous combination, so 01-03's acquire-before-release strength is not spent closing the gap
- [Phase 01]: 01-16: plan verify #4 ('dart test --plain-name workerGone' >= 3 rows) reported NOT MET and SUBSTITUTED rather than satisfied by renaming 01-15's frozen row — the proxy counts row NAMES and 01-15's rebind cell does not carry the token, while 01-17's live probe matches on that exact wording. Three distinct blocks DO arm HotkeyRefusalCode.workerGone. Needs a reviewer's blessing, not a code change
- [Phase 01]: 01-17: the workerGone rebind arm is proved by difference — the same probe, the same injected worker death, the same refusal code at both revisions, and only the answer changes (LOG=abandoned/REPORTED_IN_EFFECT at 4247446, LOG=refused/REPORTED_UNAVAILABLE at HEAD)
- [Phase 01]: 01-17: a source-level fault injection is applied only inside a detached git worktree under a named temp root and removed on every path including halts, so a live probe can build and run patched code without ever touching the developer's tree
- [Phase 01]: 01-17: a halt must not destroy its own evidence — the daemon log, the injection diff and the screenshots are written outside the directory the exit trap removes
- [Phase 01]: 01-19: WR-08 closed by DELETION (reviewer option a), not by keeping the branch behind a new assertion — RegistrableKey.hasPortalTrigger, HotkeyCaptureRefusal.noPortalTrigger, the branch and its user-facing sentence are gone; the capture validator now has four reachable refusal subjects — Measured, not preferred: registrableKeys() prints total=63 withoutPortalTrigger=0 missing=[], so the predicate was always false and the branch unreachable. The divergence it guarded is already asserted three times in both directions at build time (two rows in xdg_shortcut_trigger_test.dart's parity group, one in hotkey_key_catalogue_test.dart). A test stops the build in front of the developer who caused the divergence; the deleted branch reached a USER as a sentence about a key they just pressed. Same motion 01-07 recorded for labelsThatBindTheWrongKey.
- [Phase 01]: 01-19: the deleted guard's rationale moved into the replacement assertion's reason: string rather than being lost, and the reason deliberately does not spell the removed identifiers — The replacement row in hotkey_key_catalogue_test.dart collects every registrableKeys().all key whose XdgShortcutTrigger.keysymNameFor is null and expects the list empty — a failure names WHICH labels diverged, not only the first — against the real injected vocabulary, never a hand-built RegistrableKey (the plan's coverage-theatre prohibition). A first draft named hasPortalTrigger/noPortalTrigger verbatim and tripped the plan's own zero-match grep gate; reworded to name the deletion descriptively.
- [Phase 01]: 01-19: the xdg_shortcut_trigger.dart import in hotkey_key_catalogue.dart STAYS, decided by experiment rather than by a clean analyzer run — A clean dart analyze is consistent with two worlds (import needed, or unused imports never flagged here). Settled by rewriting the [XdgShortcutTrigger] doc link at :186 to backticks and re-running: warning - unused_import, exit 2. Restored from a scratchpad backup, never git checkout --. So the analyzer does catch it AND the square-bracket doc link is the sole thing keeping the import alive; the two backtick mentions at :58 and :193 do not.
- [Phase 01]: 01-19: WR-07 closed — both AltGr comments cite the XTEST observation and explicitly do NOT claim a physical keyboard — Assumption A3 was settled twice on a live GTK session: the 01-07 run (2026-09-02) and UAT test 9 (2026-09-04) on an altgr-intl layout. Both drove keys with XTEST. UAT test 9's own fidelity: note retracts the physical-keyboard framing as overstating what the claim needs, because the predicate is a GTK/Flutter keymap translation that cannot tell an injected event from a switch. The comments say why XTEST is sufficient rather than treating it as a caveat, keep the logical-altGraph-vs-physical-altRight reasoning, and keep the consequence clause.
- [Phase 01]: The UAT probe's teardown is guarded by DAEMON_STARTED and matches the worktree bundle path, never the app name — A harness never signals a process, nor clears a clipboard, it did not create: an unmet precondition on foreign state is a named halt, not a mutation
- [Phase 01]: Probe output directories are 0700, and the four pre-existing ones were restricted rather than deleted — Two are cited by full path in 01-VERIFICATION.md as its pre-fix/post-fix proof; a chmod closes the exposure without destroying the record's evidence
- [Phase 01]: 01-22: the capture validator doc counts four refusal subjects — the count in prose now matches HotkeyCaptureRefusal's four values (G-01-18 / WR-03 closed)
- [Phase 01]: 01-22: completeness sweeps are recorded with their pattern and proven to match the pre-fix site; DW-130's pattern required 'five' + space + plural and could not match the hyphenated singular 'five-subject'
- [Phase 01]: Portal-suite flakiness: the barrier moved to FakeGlobalShortcutsPortal's emit side as an ordered D-Bus round trip; _settle()'s 50-turn pump is retained unchanged as an in-process drain only
- [Phase 01]: The merge gate is recorded as a measured ratio (10 PASS / 0 FAIL over 10 runs; 3/3 on the Flutter-bound half), never again as one exit code; both AD-14 abstract-socket suites stay filed as ~1/7 residuals
- [Phase 01]: 01-24: DW-131 filed at severity high with status open — the merge gate's intra-file nondeterminism is recorded, not closed. 01-23's ratio was clean (10/10, 3/3) and the diagnosis is established, but both AD-14 abstract-socket suites remain residuals at ~1/7 whose mechanism the fix does not touch. — At p = 1/7 per run, ten clean runs occur about 21 percent of the time, so a ten-run sample cannot distinguish "fixed" from "not sampled". Closing on the improvement would repeat the sample-read-as-measurement error the entry exists to record. Severity is high on reach: "the suite is green" was the sole proof for several verified truths, so the defect is in the instrument rather than in one measurement.
- [Phase 01]: 01-24: the PRE-EXISTING check was re-run at this HEAD and its ANSWER CHANGED — the portal suite and the fake now appear in git diff --name-only 52cebe8..HEAD, from exactly one commit (9eb8a47, 01-23's own fix). Recorded as changed with the cause named; 01-VERIFICATION.md left as written, and its path slip for single_instance_lock_test.dart is corrected inside DW-131 rather than in the report. — Both texts must survive. This is the motion DW-129 made for plan 01-03's truth and DW-123 made for DW-9/26/44, and it is this project's standing rule.
- [Phase 02]: 02-01: Keep one CorrectionController and atomically replace its active provider/preset after committed config changes; capture the pair per run for history.
- [Phase 02]: Panel geometry is prepared from startup display size and text scale; D-16 limits placement to best effort.
- [Phase 02]: 02-02: Persist a structured effective hotkey when available; retain one configured restart seed when status is unavailable or Wayland reports only localized text.
- [Phase 02]: 02-02: Detect external config edits before replacement and retry Settings writes from the refreshed file.
- [Phase 02]: 02-06: Treat displayed digits as physical top-row positions while retaining logical and keypad shortcuts
- [Phase 02]: 02-06: Reserve a Settings gutter at normal widths and use a separate header below 200 logical pixels
- [Phase 02]: DaemonStartup.begin owns and releases the lock until startup returns.
- [Phase 02]: Abort uses the privacy-safe logger guard and exits from a finally tail.
- [Phase 02]: 02-03: SettingsController remains the one bindingChanges subscriber; DaemonGraph forwards typed snapshots to the tray.
- [Phase 02]: 02-03: The startup tray boolean hand-off remains; typed Settings snapshots own later status.
- [Phase 02]: 02-03: A retained X11 rebind refusal shares the visible Settings failure lifetime with the tray note.
- [Phase 02]: 02-07: Serialize clipboard writes in a controller-owned queue; monotonic generations own card feedback.
- [Phase 02]: 02-07: Bound stalled clipboard writes at eight seconds and report card-local failure; a timed-out platform future cannot be canceled by the current port.
- [Phase 02]: 02-04: Settings own-write echoes use a value set because overlapping mutations are refused.
- [Phase 02]: 02-04: Config load results keep detailed feedback, while startup logs only a generic problem and safe error type; CONFIG-01 remains pending Claude provider cleanup.
- [Phase 02]: 02-08: keep one CorrectionController for config refresh; observe explicit provider replacement at the panel boundary.
- [Phase 02]: 02-14: Startup abort and normal stop reuse the composition-root per-step teardown duration.
- [Phase 02]: 02-14: Stop signals the pending startup bind, joins startup ownership, then releases resources once.
- [Phase 02]: 02-09: Retain native panel call ownership through timeout and repair stale settlements after the latest intent completes.
- [Phase 02]: 02-09: Tag self focus at PanelWindow and count only user focus when releasing a deferred blur.
- [Phase 02]: 02-11: DaemonHome reports Settings visibility synchronously to PanelController for the hotkey view swap.
- [Phase 02]: 02-11: Focus loss remounts the capture field while panel text and correction remain owned by CorrectionController.
- [Phase 02]: 02-15: Require stop and DONE before an HTTP correction can complete — A clean socket close or visible END line alone can still be truncated
- [Phase 02]: 02-15: Accept remote HTTPS or explicit loopback HTTP only — Keep credentials and draft text on the configured destination without plaintext remote transport
- [Phase 02]: 02-16: Read unlocked Secret Service items by application/provider attributes; locked or unavailable keyring degrades to later sources.
- [Phase 02]: 02-16: Preserve only a user hand-placed config API key on later saves under D-17; never copy keyring or environment keys into config.
- [Phase 02]: 02-10: GTK hide callback is an unlabelled echo of the owning hide request; only the request may report its panel departure reason.
- [Phase 02]: 02-17: Save the selected compatible endpoint and model in one Settings mutation while preserving the preset prompt.
- [Phase 02]: 02-17: Accept remote HTTPS or explicit loopback HTTP for in-app Base URL saves; source lookup wiring remains in 02-18.
- [Phase 02]: 02-12: FakePanelWindow keeps GTK mapping and iconification as separate facts; native minimize and restore events change iconification.
- [Phase 02]: 02-18 keeps Claude/claude-sonnet-5 as default and uses one configured compatible adapter with no default live endpoint
- [Phase 02]: 02-18 unknown provider IDs warn and resolve to UnconfiguredCorrectionProvider without Claude fallback
- [Phase 02]: 2026-09-26 owner-approved controller frozen-block renegotiation: 13 error-handling cells re-derived from story 3 by Codex local BMAD workflow; CAP-2 success re-derived from append-only memlog.
- [Phase 02]: D-19 ratified HotkeyBinding defensive-copy constructor is current AD-9; earlier unattended choice keeps separate provenance.
- [Phase 02]: Unknown provider id warns and yields unconfigured provider; Wayland description remains localized text, not structured effective binding.
- [Phase 02]: Selectable providers must stream real partials; shipped tagged format requires END sentinel.
- [Phase 02]: Historical architecture reviews retain their original verdicts and gain dated source-grounded dispositions.
- [Phase 02]: 02-24: Ledger closure retains headings and historical text, dates status: done, and cites evidence in resolution.
- [Phase 02]: 02-24: Corrected six live deletion directives in stories.yaml as the source for future stories.
- [Phase 02]: 02-25: Ledger closure preserves original DW and flat provenance; dated resolutions state later phase-spec choices and evidence limits.
- [Phase 02]: 02-25: D-16 placement is best effort and D-17 config-key preservation is a strict-spec exception; native ordering remains unobserved.
- [Phase 02]: D-15 retains four failure kinds; AD-4 preserves active correction on panel hide.
- [Phase 02]: D-17 preserves only an existing hand-placed config key as the owner-approved exception to the literal no-write criterion.
- [Phase 02]: D-19 owner ratified the non-const defensive-copy HotkeyBinding constructor in generated AD-9.

### Pending Todos

None yet.

### Blockers/Concerns

- **CI gate now has local evidence only.** Quick task 260927-l2c added full headless tests and an 80% line/branch gate. The local suite passed; a GitHub runner has not executed the updated workflow. Native desktop observations are still separate.
- **Three human gates must be answered at planning time, not mid-execution.** Phase 1: whether `GlobalHotkey` gains a synchronous accessor (edits AD-9's verbatim-frozen declaration), and which packaging format ships (constrains AD-11's portal handshake). Phase 6: whether `CorrectionFailureKind` gains a fifth member — research recommends opposite answers.
- **No schema-changing work may be scheduled.** Drift's v1 schema snapshot can only be captured while v1 is the live schema; a phase that bumped `schemaVersion` would destroy the baseline every existing user is on.
- **Contingent closures broken by the scope cut.** DW-51 was contingent on GATE-01/DW-29, which is now out of scope, so DW-51 cannot close this milestone. DW-84 (on SETTINGS-02/DW-68) and DW-27 are unaffected — check before any further descope.
- 01-05 left one bind-path hang unbounded on purpose: _closeSessionBeforeRebinding's Session.Close. Bounding it would require restoring _session after abandoning a Close that may still land, which breaks the one-Close-in-flight-per-session invariant and would make dispose() send a second. Needs a "closing, unconfirmed" state; owed to plan 01-10 as a ledger entry alongside the NameOwnerChanged re-registration defect.
- 01-06: ListShortcuts is implemented and routed through _callThroughRequest but unexercised — the fake portal implements no ListShortcuts and always sends a trigger_description, so its only caller (a granted bind with no wording) never fires in the suite. First exercise owed to a real portal; WINDOWS.md 11.
- 01-07: two human-check rows are owed, not observed — the capture control's read-only state while a bind is in flight (an X11 grab resolves synchronously and this container has no portal to park a bind on), and that all seven dissolved labels now FIRE under a real window manager (Space and Tab were exercised live; F1-F4 were not exercised on any real X session). WINDOWS.md 13 and 14.
- 01-07: two A3/A15 widget assertions were narrowed from "the requested combination appears nowhere on screen" to "nowhere in the read-out". The capture control shows the combination it will request, which is what an input is, so the screen-wide form cannot hold. If the screen-wide invariant was intended, T-01-30 needs a product answer rather than a test edit.
- 01-08: two acceptance criteria did not pass literally and are declared as substituted in 01-08-SUMMARY.md, never as passes. (1) 'grep -c generation settings_state.dart prints 0' already printed 1 at baseline — the match is a pre-existing doc sentence at settings_state.dart:104; substituted with an empty git diff on that file plus the grep output. (2) 'total test( count across test/ unchanged' is not met (982 -> 983): the plan's own action block demands new coverage for the mid-flight discard and no existing row was redundant, so exactly one row was added in the existing group and mutation-checked. Both need a reviewer's blessing, not a code change.
- 01-08: the guard's live behaviour is OWED, not observed. A real compositor emitting ShortcutsChanged while a BindShortcuts dialog is open cannot be produced in this container (no GlobalShortcuts portal); the unit row reproduces the ordering against FakeGlobalHotkey.bindGate only. On X11 the guard is structurally inert (bind resolves synchronously, bindingChanges is an empty closed stream), stated rather than tested because there is no branch to reach. Belongs in WINDOWS.md beside 01-07 rows 13 and 14.
- 01-09: Task 1 was a blocking-human gate answered by the ORCHESTRATOR, not a human, so the AD-9 declaration edit at spine 239-243 has no human ratification. Filed as coverage entry D5 (human_judgment: true) in 01-09-SUMMARY.md. The reasoning is checkable (requirement text plus a documented `const`-constructor impossibility), but a human must ratify or reverse it before Phase 7 edits the spine. Also: 01-09 declares plan verify #4 (grep -rc 'const HotkeyBinding(') as PASSED-BUT-INSUFFICIENT, substituted by dart analyze — it printed clean while 40 analyzer errors stood. WINDOWS.md entry 18.
- Phase 7 (ARCH-06): 01-09 gate answer defensive-copy, dropping const from AD-9 declared HotkeyBinding constructor, was ORCHESTRATOR-SELECTED not human-ratified. Re-confirm with a human before editing ARCHITECTURE-SPINE.md:246. Recorded at the ledger FLAT-05 resolution and in the AD-9 hand-off correction entry.
- 01-11: Task 2's focus-ownership acceptance criterion does not hold and was reported as failing rather than smoothed. The FOCUS_BEFORE/FOCUS_AFTER pair differs on FOUR route names (show, alternate-1, focus-steal, desktop-click AND foreign-grab), not the two the plan predicted; it matches only where the panel ended as it started (hide, alternate-2..4). The <interfaces> table's foreign-grab "unchanged" row was sampled during the grab, this harness samples at the 1000 ms settle mark. Consequence for 01-12: a focus-owner discriminator validated on a post-settle sample is CIRCULAR on the foreign-grab route, because the focus is foreign only because the dismissal happened. 01-12 must key its discriminator on something available when the blur is handled (the X focus mode, or the registrar knowing its own grab is active). WINDOWS.md entry 22.
- STATE.md bookkeeping drift, not a phase-1 defect: "Plan: 5 of 24" and "Progress: 0%" disagree with disk, where 24 of 24 PLANs have SUMMARYs (confirmed by roadmap.update-plan-progress: plan_count 24, summary_count 24). state.update-progress recomputed completed=24 total=24 but returned "percent": 0 and left the bar at 0% — the same cosmetic tooling oddity plan 01-23 recorded and did not act on. The plan counter was already stale before this plan ran; not hand-edited here because the tooling owns these fields.
- Phase 02 suite remains red in Settings paths after 02-06: 18 full Dart failures in settings_controller_test.dart and two Flutter hotkey-screen failures (A1, A4); route to 02-02 owner.
- 02-19 halted: frozen controller matrix and generated CAP-2 SPEC require authorized BMAD update; authenticated Claude CLI was rejected by auto-review for private-document SaaS egress with write access.
- 02-19 authorized BMAD retry halted: Claude Code organization disables subscription access; it requires an authorized Anthropic API key or admin enablement. Frozen controller matrix and CAP-2 SPEC unchanged.
- 02-19 resolution (2026-09-26): the owner approved the narrow frozen matrix update and corrected the execution route to Codex running local BMAD instructions. The 13 error cells and CAP-2 success were re-derived and verified; the earlier Claude auth gate is closed. PANEL-17 remains pending its spine half in 02-21.

### Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 260927-l2c | Integration tests with 90% line and branch coverage on requested CI branches | 2026-09-27 | 9759922 | Verified | [260927-l2c-write-integration-tests-for-the-project-](./quick/260927-l2c-write-integration-tests-for-the-project-/) |
| 260927-l12 | Manual Linux binary releases with stable and branch versions | 2026-09-27 | b2a9a97 | Needs Review | [260927-l12-create-manual-github-ci-to-build-and-pub](./quick/260927-l12-create-manual-github-ci-to-build-and-pub/) |

### Roadmap Evolution

- Phase 2 edited: Phases 2-7 merged into a single Phase 2 with six internal waves (A settings/tray, B panel geometry, C panel window-events, D startup/teardown, E second provider, F spine currency); all 40 requirements retained

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-09-26T10:11:45.961Z
Stopped at: Phase 02 complete — all phases complete
Resume file: None

## Operator Next Steps

- Start the next milestone with $gsd-new-milestone
