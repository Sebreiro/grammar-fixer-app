---
phase: "1"
slug: "hotkey-truth"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-01"
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `01-RESEARCH.md` § *Validation Architecture*.

**Framing constraint (binding):** general test/gate/CI work was removed from this milestone on
2026-08-31 (`REQUIREMENTS.md` § *Removed: Test-Shaped Work*). This strategy proposes no general new
test files. Plan 01-25 specifically authorized one X11 shell regression harness for the
clipboard-safety gap. Every other row below observes a behaviour using the tree as it
stands today, or records a manual observation owed to a real desktop session.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `test` 1.31.0 (pure Dart) + `flutter_test` (SDK) |
| **Config file** | `dart_test.yaml` — `concurrency: 1` is a correctness requirement (DW-15); the `live` tag is skipped by default |
| **Quick run command** | `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` |
| **Full suite command** | quick run, plus `flutter test` for `test/ui`, `test/composition`, `test/platform` |
| **Estimated runtime** | ~58 seconds (quick run, measured 2026-09-01) |
| **Measured baseline** | quick run: **946 passed / 2 skipped / 0 failed**; `dart analyze`: **clean** |
| **Anti-pattern** | a bare `dart test` — fails to load 69 suites. Never use it as a gate. |

---

## Sampling Rate

- **After every task commit:** `dart analyze --fatal-infos`, then the quick run command
- **After every plan wave:** the quick run command, then `flutter test`
- **Before `/gsd-verify-work`:** both green, plus the `readelf` one-liner on a freshly
  `flutter clean`ed release build
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

**Bound to the plan set on 2026-09-01.** The table was seeded at the requirement level before the
plans existed; every Task ID, Plan, Wave and Automated Command below is now read off the committed
`01-NN-PLAN.md` files rather than left `TBD`. Task IDs use `{plan}-T{n}`, numbering tasks in the
order they appear in `<tasks>`. Where the seeded command differed from the command the owning task
actually runs, the **plan's command wins** and the change is footnoted — a contract that names a
command no task executes is a contract nothing checks.

`/gsd-validate-phase` still owns the `nyquist_compliant` and `wave_0_complete` flags and the Status
column; binding the anchors does not set them. "File Exists" reads ✅ where the command runs against
the tree today.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-02-T2 | 01-02 | 2 | HOTKEY-01 | — | A refused grab is reported as refused, never as success | inspection | `grep -rn 'package:hotkey_manager' lib/ pubspec.yaml` → no matches | ✅ | ⬜ pending |
| 01-03-T1 | 01-03 | 3 | HOTKEY-01 | — | A refused rebind keeps the shortcut that was already working (acquire before release) | inspection | `grep -c '_releaseBeforeRebinding' lib/src/infrastructure/hotkey/x11_global_hotkey.dart`; `grep -n 'stillInEffect' …` [^b] | ✅ | ⬜ pending |
| 01-02-T2 | 01-02 | 2 | HOTKEY-02 | — | The runner does not resolve keybinder at load | automated | `flutter clean && flutter pub get && flutter build linux --release && readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector \| grep -c keybinder` → `0` | ✅ | ⬜ pending |
| 01-02-T2 | 01-02 | 2 | HOTKEY-02 | — | No plugin `.so` ships in the bundle | automated | `ls build/linux/x64/release/bundle/lib/ \| grep -c hotkey_manager` → `0` | ✅ | ⬜ pending |
| 01-06-T3 | 01-06 | 6 | HOTKEY-03 | — | Settings never echoes the requested combination on Wayland | inspection | `awk '/_boundLines/,/^  }$/' lib/src/ui/settings/hotkey_status_view.dart \| grep -c 'preference'` ≤ 1, and that one occurrence is inside the X11 combination branch [^a] | ✅ | ⬜ pending |
| 01-07-T2 | 01-07 | 7 | HOTKEY-04 | T-01-38, T-01-40 | The seven mis-binding labels are no longer special-cased | inspection | `grep -n 'labelsThatBindTheWrongKey' lib/ test/` — set empty or symbol gone; `grep -c 'bindsTheWrongKey' lib/src/infrastructure/hotkey/x11_global_hotkey.dart` → `0`; the three `hotkey_confinement_test.dart` rows re-pointed | ✅ | ⬜ pending |
| 01-07-T3 | 01-07 | 7 | HOTKEY-04 | T-01-36, T-01-37 | A capture the app knows will not fire is refused at capture, with the reason | automated | `flutter test test/ui/settings`; `grep -c 'KeyRepeatEvent' lib/src/ui/settings/hotkey_capture_field.dart` ≥ 1; `grep -c 'physicalKey' …` ≥ 1 | ✅ | ⬜ pending |
| 01-06-T1 | 01-06 | 6 | HOTKEY-06 | — | A settings screen mounting after a compositor rebind reads current state | inspection | `grep -n 'get current' lib/src/domain/hotkey/global_hotkey.dart` shows the member; `awk '/get current/,/;/' … \| grep -c 'Future\|async\|await'` → `0` (it is synchronous) [^a] | ✅ | ⬜ pending |
| 01-08-T1 | 01-08 | 8 | HOTKEY-07 | — | The precedence rule is written down where both writers are declared | inspection | `grep -c 'supersede\|precedence\|newer' lib/src/domain/hotkey/global_hotkey.dart` ≥ 1 [^a] | ✅ | ⬜ pending |
| 01-08-T2 | 01-08 | 8 | HOTKEY-07 | — | The rebind path carries the same "do not overwrite a newer fact" guard as the startup path | inspection | `awk '/changeHotkey\(HotkeyBinding/,/^  }$/' lib/src/application/settings_controller.dart \| grep -Ec 'generation\|newer'` ≥ 1 [^a] | ✅ | ⬜ pending |
| 01-04-T2 | 01-04 | 4 | HOTKEY-08 | T-01-17, T-01-21 | A consumer tells the three causes apart without parsing a string | inspection | `grep -rn 'HotkeyUnavailable(' lib/src/infrastructure lib/src/application \| grep -vc 'cause:'` → `0` — all 14 sites name a cause | ✅ | ⬜ pending |
| 01-04-T3 | 01-04 | 4 | HOTKEY-08 | T-01-18, T-01-20 | The screen switches on the cause, not on the message text, and nothing notifies | inspection | `grep -c 'noBackend\|keyRefused\|revoked' lib/src/ui/settings/hotkey_status_view.dart` ≥ 3; `grep -n "message.contains\|message ==\|message.startsWith" …` → no matches | ✅ | ⬜ pending |
| 01-09-T2 | 01-09 | 8 | HOTKEY-09 | — | `modifiers` cannot be mutated behind the constructor | inspection | `grep -c 'unmodifiable' lib/src/domain/hotkey/hotkey_binding.dart` ≥ 1; `grep -rc 'const HotkeyBinding(' lib/ test/ \| grep -v ':0$'` → no matches [^a] | ✅ | ⬜ pending |
| 01-10-T1 | 01-10 | 9 | HOTKEY-10 | — | The re-measure trigger names something observable, or is retired | inspection | `grep -c 'hotkey_manager' pubspec.lock` → `0`; the envelope clause at spine ~line 584 no longer names it | ✅ | ⬜ pending |
| 01-01-T3 | 01-01 | 1 | ARCH-02 | — | The packaging decision is recorded in the append-only ledger | inspection | `grep -n '^status: done' _bmad-output/implementation-artifacts/deferred-work.md \| awk -F: '$1==1348'`; `awk 'NR==1349 && /^resolution:/ …'`; `git diff --numstat` shows additions only [^c] | ✅ | ⬜ pending |
| 01-05-T1 | 01-05 | 5 | ARCH-02 | T-01-28 | The handshake honours the packaging decision: a sandboxed build never calls the host registry | inspection | `grep -c 'flatpak-info' lib/src/infrastructure/hotkey/portal_app_id_regime.dart` ≥ 1; `Register` sits inside a regime branch [^c] | ✅ | ⬜ pending |
| every task | all | all | ALL | — | Nothing existing broke | automated | quick run command → `946+ passed, 0 failed`; `dart analyze --fatal-infos` → clean | ✅ | ⬜ pending |

[^a]: Command replaced with the one the owning task actually runs. The seeded forms — `grep -n 'preference' …`, `grep -n 'current' …`, `grep -n 'Set<HotkeyModifier>.unmodifiable' …`, and the prose rule for HOTKEY-07 — were written before the plans and are either unscoped (they match doc comments and unrelated identifiers) or name a spelling no task commits to.
[^b]: HOTKEY-01 has two halves and the seed carried only one. 01-02 proves a refusal is *reported*; 01-03 proves a refused rebind does not *cost the user the shortcut they had*. Both are bound rather than folded, because a green 01-02 says nothing about 01-03's behaviour.
[^c]: ARCH-02 spans two plans — the decision is written to the ledger in wave 1 and the code honours it in wave 5 — so the seeded single row could not carry one anchor. Split, not invented: both commands are lifted from the plans' own `<verify>` blocks.

**Nothing in this table is `TBD`.** Every row's owning task exists in a committed plan. What remains
unbound is the **Threat Ref** column for the rows outside plans 01-04 and 01-07: those plans' STRIDE
registers are the only two whose threat IDs map cleanly onto a single map row, and assigning IDs from
the other registers would be an invented anchor rather than a read one. Left `—` deliberately for
`/gsd-validate-phase`.

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

The table above is the plan-time sampling map for the original 01-01 through 01-14
sequence. Its ⬜ marks describe that historical plan-time state. The execution summaries
and the 2026-09-23 audit below carry later-plan outcomes; the table is not being
silently presented as a current test-run result.

---

## Wave 0 Requirements

**No new test infrastructure is proposed and none may be authored.** What Wave 0 owes is
maintenance of the *existing* gate — a direct consequence of deleting `hotkey_manager` (D-12),
not test-shaped work. Omitting it turns the suite red:

- [ ] Re-point `test/architecture/hotkey_confinement_test.dart` rows at `:48-62`, `:78-112`,
      `:221-313`, `:366`, `:379` — five rows, plus the `_seamFile` constant at `:535-536`
- [ ] Re-point `test/architecture/composition_wiring_test.dart` rows at `:864`, `:895`, `:901`
      (`:864` asserts the literal `'final hotkeyRegistrar = HotkeyManagerRegistrar();'`)
- [ ] Delete `test/platform/hotkey_manager_registrar_test.dart` (608 lines) with the seam it drives
- [ ] Fix the stale doc reference in `test/fakes/fake_hotkey_registrar.dart:24`
- [ ] Check `test/infrastructure/hotkey/x11_global_hotkey_test.dart:437`'s comment about the
      shipped seam's disposal behaviour still describes the new registrar

---

## Manual-Only Verifications

**Anchored to the task that owes each observation (2026-09-01).** Every row below is a
`<human-check>` block (or, for 01-05, a `<verification>` clause) that already exists in a committed
plan; the Owed-By column names it so the observation has somewhere to be recorded and somewhere to
be chased from. No new observation was invented and no test file is proposed.

| Behavior | Requirement | Owed By | Why Manual | Test Instructions |
|----------|-------------|---------|------------|-------------------|
| A grab another X11 client owns is reported as taken, and the previous shortcut keeps firing | HOTKEY-01 | **01-02-T2** (wave 2), human-check 1 | Needs two X clients contending for one grab | Start the daemon; from another terminal hold `Ctrl+Shift+G` with a second client (the `ctypes` probe in RESEARCH.md § *Code Examples*, same display); apply the same shortcut in Settings; the screen states it is taken and the previous shortcut still fires. Reproducible under `Xvfb` — proved against `Xvfb :77` during research. **Not owed: runnable here.** |
| The daemon starts with `libkeybinder-3.0.so.0` removed | HOTKEY-02 | **01-02-T2** (wave 2), human-check 2 | Needs a tray host; none in this container | Rename `libkeybinder-3.0.so.0`, launch under `xvfb-run`; tray icon present, panel opens from the tray, Settings reports the shortcut unavailable. **Owed to a real session.** |
| Settings shows the portal's own description text, not the app's re-rendering | HOTKEY-03 | **01-06-T3** (wave 6), human-check row 2 | Needs a real Wayland compositor and portal | On a real GNOME/KDE session, bind the shortcut and confirm the shown text is the compositor's (e.g. a German desktop renders `Strg+Umschalt+G`). **Owed to a real session.** |
| A capture the app knows will not fire is rejected at capture, with the reason | HOTKEY-04 | **01-07-T3** (wave 7), human-check rows 1–3 | User-interaction behaviour | Open Settings; press a bare key → refused with a reason; press `Ctrl` alone → nothing committed; press AltGr+G → refused. Runnable under `xvfb-run`. **Not owed: runnable here.** |
| A settings screen mounting after a compositor rebind reads current state | HOTKEY-06 | **01-06-T3** (wave 6), human-check row 3 | Needs a compositor that rebinds behind the app | On a real session, rebind in the desktop's own settings with the app's Settings screen closed, then open it — it shows the new combination. **Owed to a real session.** |
| A shortcut the desktop takes away renders as `revoked`, distinctly from the other two causes | HOTKEY-08 | **01-04-T3** (wave 4), human-check row 3 | Needs a compositor that revokes a live binding; nothing in this container can produce one | Drive a revocation from the compositor with the daemon bound; the screen states the shortcut was taken away — a different sentence from "no backend" and from "that key was refused" — and nothing notifies (D-09). **Owed to a real session.** [^d] |
| A sandboxed build never calls the host portal registry; an unsandboxed one still does | ARCH-02 | **01-05-T1** (wave 5), `<verification>` clause 7 | Needs a real Flatpak sandbox; the predicate is deliberately built not to fire in this devcontainer | Run the packaged build inside a Flatpak sandbox and confirm `Register` is never called, and on an ordinary session confirm it still is. **Owed to a real session.** [^d] |

[^d]: These two rows were **not** in the seeded table but the observations they name already existed
in the plans, unanchored. Binding them here is what makes the owed-count below true; the alternative
was a contract that silently under-reported what the phase cannot see.

**Owed-to-a-real-session rule:** **four** observations above cannot be made in this container —
HOTKEY-02 (no tray host), HOTKEY-03 and HOTKEY-06 (no Wayland compositor or portal), and HOTKEY-08's
`revoked` cause (no compositor that revokes). ARCH-02's sandbox row is a **fifth**, owed for the same
reason. The two remaining rows — HOTKEY-01's grab contention and HOTKEY-04's capture refusals — are
runnable in this container under `Xvfb`/`xvfb-run` and are **not** owed. All of them are recorded as
**owed** or as **observed**, never as passed. A phase gate that cannot see one must say so rather
than claim it.

One further observation is **conditionally** owed and is deliberately not tabled: 01-04-T3's
`noBackend` row reads *"Owed to a real session **if** it cannot be produced here."* Whether it is
owed is an execution-time finding, so the SUMMARY records the answer rather than this contract
pre-judging it.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or are listed under Manual-Only above
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all suite-maintenance rows (no general new test files; the 01-25 shell harness is a specific gap exception)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] The five owed manual observations (HOTKEY-02, HOTKEY-03, HOTKEY-06, HOTKEY-08 `revoked`,
      ARCH-02 sandbox) are recorded as owed, not claimed; the two runnable ones are recorded as
      observed with what was seen
- [ ] `nyquist_compliant: true` set in frontmatter — **`/gsd-validate-phase`'s to set, not the
      planner's.** Binding the map above deliberately did not flip it.

**Approval:** validated, partial — 2026-09-23. Automated coverage and manual-only debt
were classified from committed summaries; no general test additions were authorized.
`nyquist_compliant` remains false because real-portal behavior and judgment-tier
items are not automated. The 01-25 X11 harness is the one specifically approved
gap exception.

## Validation Audit 2026-09-23

The original map covers plans 01-01 through 01-14. I classified the `coverage:`
blocks in the eleven later committed summaries (01-15 through 01-25): 55
deliverables, 43 with passing automated evidence and 12 requiring human
judgment. This is an artifact audit, not a fresh execution of every historical
test. The new 01-25 harness was run directly at this HEAD: three dedicated X11
cases passed after the recorded 0/3 fail-first run. Its §7 keyword check and
`bash -n` passed. The two 01-25 judgment items are in `01-UAT.md` as tests 20
and 21. The earlier UAT's skip decisions for real-portal tests remain in force.

| Plans | Deliverables | Automated pass in summaries | Human judgment |
| --- | ---: | ---: | ---: |
| 01-15 through 01-20 | 33 | 25 | 8 |
| 01-21 through 01-25 | 22 | 18 | 4 |
| **Total** | **55** | **43** | **12** |

**Result:** partial. No new general test work was added or inferred. The two
real-compositor behaviours and outstanding reviewer judgments remain manual;
phase completion waits on the UAT handoff. `wave_0_complete` and
`nyquist_compliant` stay false rather than asserting a gate this audit did not
prove.
