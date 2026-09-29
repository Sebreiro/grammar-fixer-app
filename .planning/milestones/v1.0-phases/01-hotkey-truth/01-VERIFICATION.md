---
phase: 01-hotkey-truth
verified: 2026-09-23T22:22:37Z
status: passed
score: 29/31 must-haves verified
behavior_unverified: 2
accepted_unverified: 2
overrides_applied: 2
overrides:
  - must_have: "The gates this phase's record rests on actually pass — the CI merge-gate command in .github/workflows/ci.yml is green"
    reason: "CI is not required for this milestone under the 2026-08-31 scope cut. The 2026-09-14 run measured 7/8, so this accepts the filed residual flakiness (DW-131 and deferred-work.md:354) without claiming that the gate is green."
    accepted_by: "project maintainer (user)"
    accepted_at: "2026-09-23T14:49:25Z"
  - must_have: "The remaining real-compositor behavior and live UAT observations are accepted for Phase 01 progression."
    reason: "The project maintainer explicitly requested that all human-needed checks be marked passed. This waives UAT tests 2, 4, 5, 6, 7, 11, and 12 and both behavior_unverified_items without claiming a live portal, Flatpak, or tray-host observation. UAT-OVERRIDE-2026-09-23 preserves their original skip reasons."
    accepted_by: "project maintainer (user)"
    accepted_at: "2026-09-23T22:22:37Z"
prior_re_verification:
  previous_status: gaps_found
  previous_score: 23/26
  previous_head: 307f7f2
  head: c63db14
  scope_change: >-
    The predecessor predated the four-plan `--gaps-only` closure set (01-21 … 01-24)
    entirely. One row per closure plan was added, so the denominator moved 26 -> 30. The
    predecessor's twenty-six rows were regression-checked — cheaply and soundly, because
    `git diff --numstat 02ccfef..HEAD` touches exactly ONE line of `lib/` (the 01-22 doc
    comment) and no frozen port. The one FAILED row (24) and the two
    PRESENT_BEHAVIOR_UNVERIFIED rows (3, 11) got full three-level re-verification.
  gaps_closed:
    - >-
      `gaps[1]` — "a closure artifact is isolated to what it created". CLOSED, and closed
      properly. `DAEMON_STARTED=0` at `worker_gone_probe.sh:63`; `stop_daemon`'s FIRST
      statement is `[ "$DAEMON_STARTED" = 1 ] || return 0` (`:99`); the flag is set at
      `:372`, immediately after the background launch and BEFORE the readiness loop, which
      is the correct place because a daemon that launched but never resolved to a pid is
      still this run's to stop. `pkill`/`pgrep` are re-anchored from the application-name
      pattern `DAEMON_PAT` to `"${WORKTREE}/${BUNDLE_REL}"` (`:103`, `:105`), and `WORKTREE`
      is assigned in `preflight` from a `mktemp -d` root before anything can set the flag,
      so the pattern is never the degenerate suffix. `stop_daemon` has exactly one caller
      (`cleanup`), so the guard covers every teardown path including all five `die` paths.
      Measured with `/usr/bin/grep -n DAEMON_STARTED` = 3 hits, at `:63`, `:99`, `:372`.
      The surviving `pgrep -f "$DAEMON_PAT"` at `:249` is a preflight CHECK, not teardown.
    - >-
      `gaps[0]`, FIRST half (the world-readable half) — CLOSED, in the script and on disk,
      both verified by me rather than read. `chmod 700 "$OUT_DIR" || die "could not restrict
      $OUT_DIR"` at `:262`, on the statement pair that creates the directory, matching the
      treatment `$XDG_ROOT/rt` already got. On disk: `ls -ld /tmp/worker-gone-probe-out/*`
      reports `drwx------` for ALL FIVE run directories, including the three from 2026-09-11
      that the predecessor measured as `drwxr-xr-x`, and including both directories the
      predecessor cites by full path as its pre-fix/post-fix proof — restricted rather than
      deleted, so the evidence survives. (The SECOND half did not close; see `gaps[0]` below.)
    - >-
      `gaps[2]` — 01-19's sweep-completeness truth. CLOSED and complete.
      `hotkey_capture_field.dart:61` now reads "The four-subject capture validator".
      Re-measured here with `/usr/bin/grep` (GNU 3.11), not the shell's ugrep:
      `-rniE "five[ -](subject|thing)" lib/ test/` = 0 hits; a broader
      `-rni "\bfive\b" lib/ test/` filtered for subject/refus/captur/enum/value = 0 hits.
      Counted rather than trusted: `HotkeyCaptureRefusal` has exactly 4 values
      (`hotkey_capture.dart:67-76`) and `verdictFor` has exactly 4 `HotkeyCaptureRefused(`
      RETURN sites (`:130`, `:139`, `:145`, `:155`) plus the constructor at `:97`.
      `git diff --numstat 02ccfef..HEAD -- lib/` is `1 1` — one line, one file, nothing else
      in `lib/` moved.
    - >-
      `gaps[3]`, the MECHANISM — the portal suite's nondeterminism is genuinely diagnosed and
      genuinely fixed, and I proved it FAIL-FIRST in my own process rather than reading
      01-23's numbers. I created a detached worktree at the pre-change revision `02ccfef`,
      ran `flutter pub get`, and ran the portal suite five times under 16 busy-loop subshells
      (one per core): **PRECHANGE_CONTENDED_FAILS=5/5**, and the failing rows are exactly the
      `_settle()`-waiting rows the record names (A16, A19, A19d, C2, D-17). The identical
      command at HEAD under the identical contention: **CONTENDED_FAILS=0/5**, `+71` each
      time. The worktree was then removed and `git worktree list` is back to one entry. The
      replacement is structurally ordered and not a bigger turn budget: `_emitSettled`
      (`fake_global_shortcuts_portal.dart:351`) pings every synchronisable client before the
      emit and pings from the sender to every client after it — a D-Bus round trip, not a
      wait. `_settle()` survives, demoted to an in-process drain with a doc that says so.
    - >-
      `gaps[3]`, the DISCIPLINE — no assertion was weakened to reach green, measured here:
      `expect(` = 237 (baseline 237), `test(` = 69 (baseline 69), `skip:|retry:` = 0,
      `git diff --numstat 02ccfef..HEAD -- dart_test.yaml` EMPTY. And the recorded ratio is
      a real measurement, not a claim: the executor's ten run logs are still on disk with
      distinct mtimes one minute apart and **ten distinct md5sums**, each tailing
      `+982 ~2: All tests passed!`.
    - >-
      `gaps[3]`, the LEDGER — DW-131 exists at `deferred-work.md:1873`, `status: open`,
      citing `merge-gate-flakiness-observation.md` for its numbers rather than restating
      them, distinguishing what was measured from what was read (§2's "nobody read the bus's
      wire order to check this"), stating its relationship to DW-15 without touching DW-15,
      and — the part that matters most — REFUSING to call the two AD-14 residuals fixed on a
      clean ten, with the arithmetic (p=1/7 gives 0.21 for zero-in-ten). Append-only held
      mechanically: `git diff --numstat 02ccfef..HEAD -- …/deferred-work.md` = `15 0`, and a
      per-commit sweep of every commit in range found exactly one commit touching the file,
      with **deletions=0**.
    - "Frozen ports untouched across the closure set: `git diff --numstat 02ccfef..HEAD` over `panel_visibility.dart`, `global_hotkey.dart`, `hotkey_binding.dart` and `hotkey_bind_outcome.dart` is EMPTY."
    - "Row 0 (the phase goal's first clause) regression-checked at HEAD, not inherited: the disjunct `if (stillInEffect == null || cause == HotkeyUnavailableCause.noBackend)` is live at `x11_global_hotkey.dart:227`, and `_causeOf` still maps `workerGone => noBackend` and ONLY `noBackend`/`workerGone` to it (`:490-496`). `grep -rn workerGone test/` = 31."
  gaps_remaining:
    - >-
      `gaps[0]`, SECOND half — "no capture can contain the user's text". NOT closed, only
      relocated onto a predicate I reproduced defeating. See `gaps[0]` below. The
      predecessor's second `missing:` bullet ("no capture taken while the panel is up")
      was deliberately not implemented; the substitute does not hold.
    - >-
      `gaps[3]`, the GATE ITSELF — still not green. My own eight serial runs at HEAD:
      **7 PASS / 1 FAIL**. The remediation actions are all discharged and the residual is
      now filed rather than unmeasured, so this is a materially smaller gap than the
      predecessor's 2/7, but the truth as the predecessor stated it is still false.
  regressions: []
  new_gaps:
    - >-
      The clipboard gate that the privacy fix now rests on is defeated by command
      substitution. Reproduced on a throwaway Xvfb in my own process, not inherited from
      01-REVIEW.md CR-01.
    - >-
      A residual flaky row the ledger filed in 2026-08 as UNCONFIRMED is now CONFIRMED by
      this run: `claude_agent_sdk_correction_provider_test.dart`'s "AD-19: sidecar stderr
      lines are forwarded to the Logger port" failed in run 6 of my eight. It is named in
      neither DW-131 nor `merge-gate-flakiness-observation.md` §5.
re_verification:
  previous_status: gaps_found
  previous_score: 27/30
  previous_head: c63db14
  head: b6fa26b
  scope_change: >-
    Plan 01-25 adds one must-have row, raising the denominator from 30 to 31.
    Since c63db14, only the probe, its operator record, and a new X11 harness changed
    under lib/, test/, and tool/; lib/ and every production port are unchanged.
    Rows 0-25 and 27-29 retain the previous verifier's evidence. Row 26 was
    re-tested against the new owner predicate and its bounded dedicated-display
    wording; row 30 is new. The two real-compositor rows remain unverified.
  gaps_closed:
    - >-
      G-01-20: the same harness command returned 0/3 before the fix and 3/3 after.
      Newline-only text retained 3/3 bytes and TARGETS, an empty image/png owner
      retained its TARGETS, and a later invalid-revision refusal made zero xclip
      writes. Both owned cases stopped on the named clipboard-owner refusal.
    - >-
      The separate CI gap is resolved by the project maintainer's 2026-09-23
      override. Its measured result remains 7/8; this report does not claim green CI.
  gaps_remaining: []
  regressions: []
  new_gaps: []
gaps:
  - truth: >-
      01-21 must-have truth 6 — "No window capture the probe writes can contain the user's
      text, because the run refuses to start while the clipboard of its display holds
      anything … the refusal establishes the precondition rather than destroying a clipboard
      the probe did not fill."
    status: resolved
    resolution: >-
      Plan 01-25 replaced the payload check with two TARGETS ownership checks,
      moved the sole empty-selection write after every preflight refusal, and
      corrected the operator record's conditional screenshot claim. The dedicated
      X11 harness proved both old counterexamples red and the corrected path green.
      The old absolute screenshot wording is superseded by the bounded contract
      stated in plan 01-25 and §7 of the operator record.
    reason: >-
      Stated absolutely, in two clauses, and BOTH are falsified. I adjudicated 01-REVIEW.md
      CR-01 by reproducing it rather than inheriting it.

      CLAUSE ONE — "the run refuses while the clipboard holds anything". The gate is
      `clip=$(xclip -selection clipboard -o -d "$DISPLAY" 2>/dev/null) || clip=""` then
      `[ -n "$clip" ]` (`worker_gone_probe.sh:213-216`). Command substitution strips ALL
      trailing newlines. Measured on a throwaway `Xvfb :77` I started and tore down: with
      `printf '\n\n\n' | xclip -selection clipboard` owning the selection, `xclip -o | wc -c`
      = **3** — the selection demonstrably holds three bytes — while the gate's own
      expression reads `clip len=0` and the branch prints `GATE PASSES`. The shell semantics
      alone confirm it independently: `v=$(printf "\n\n\n")` gives `${#v}` = 0. So a
      selection holding only whitespace-that-is-newlines walks through a gate whose comment
      says it exists so the probe can "clear only once the read has proved there was nothing
      there to destroy."

      CLAUSE TWO — "the refusal establishes the precondition rather than destroying a
      clipboard the probe did not fill". False on EVERY run, not only the newline one. Two
      lines after the gate the probe executes
      `printf '' | xclip -selection clipboard -d "$DISPLAY" &` (`:218`) and takes ownership.
      X selection ownership is exclusive and the prior payload is unrecoverable: measured on
      the same `:77`, a selection holding `image/png` data reported `bytes=0` for that target
      after the seizure. The probe does not refuse INSTEAD of clearing; it refuses AND THEN
      clears, and in the newline case it clears something real.

      Why this is the Core Value and not a tooling nit: the artifact still photographs the
      correction panel. I opened
      `/tmp/worker-gone-probe-out/post-privacy-fix-1ff58eb-20260914104208/step-settings-gear-before.png`
      from the executor's own live run — it is the "Your text" editor with the three register
      cards, empty in that run. 01-21's SUMMARY is honest that the capture was KEPT as a
      deliberate trade (`:141`). That trade is sound only to the strength of the
      precondition, and the precondition is this predicate. The executor DID execute the
      refusal branch — with the seeded string `[secret]`, which is a sample, not a
      measurement of the predicate's domain. This phase's record has now been caught reading
      a sample as a measurement three times.

      The record makes it worse rather than bounding it. `worker-gone-observation.md:318-321`
      — the section that publishes the re-run command — tells the next operator the probe
      "refuses rather than clearing the selection itself … this probe does not destroy state
      it did not create" and that "the panel it captures is empty by construction". The first
      is false unconditionally against `:218`; the second is exactly as strong as the gate.
      So 01-21 truth 7 ("§7 states … the clipboard precondition, so a future operator
      inherits the reasoning") is satisfied in form and false in content.
    artifacts:
      - path: "tool/uat/worker_gone_probe.sh"
        issue: "`:213-216` — the emptiness gate tests a shell string that has had its trailing newlines stripped, so it answers \"is the default target's payload non-empty after mangling\" rather than \"does anything own this selection\". `:218` — the seizure runs unconditionally once the gate passes, on state the probe did not create."
      - path: "test/platform/worker-gone-observation.md"
        issue: "`:318-321` — states that the probe refuses rather than clearing (false against `:218`) and that the captured panel is empty \"by construction\" (true only to the strength of the defeated predicate), in the one section a future operator reads before re-running."
    missing:
      - "Gate on OWNERSHIP, not on the payload: `xclip -selection clipboard -o -t TARGETS -d \"$DISPLAY\" >/dev/null 2>&1 && die \"…\"`. TARGETS is offered by any owner regardless of what it holds, which is the question actually being asked."
      - "If a payload check is also wanted, byte-count it (`| wc -c`) rather than shell-stringing it."
      - "Move the seizure to the END of `preflight`, after the last `die` — taking the selection is destructive and four refusals currently follow it, so a run that refuses to do anything has already taken the operator's clipboard (01-REVIEW.md WR-01, confirmed by reading `:213-254`)."
      - "Rewrite `worker-gone-observation.md:318-321` to state what the code does — it refuses while another client OWNS the selection, then takes the selection itself with an empty payload — and to bound the guarantee to the predicate rather than asserting construction."
  - truth: >-
      `gaps[3]` carried forward — the gates this phase's record rests on actually pass; the
      CI merge-gate command in `.github/workflows/ci.yml` is green.
    status: resolved
    resolution: "Accepted by project maintainer override on 2026-09-23: CI is not needed for this milestone; 7/8 remains the measured result and the residual flakes stay filed. No green-gate claim is made."
    reason: >-
      Materially better and still not true. I ran the exact scoped CI command
      (`dart test --exclude-tags=live test/application test/architecture test/domain
      test/infrastructure test/fakes_smoke_test.dart`) **eight times, serially, in my own
      process, with nothing else running**: **7 PASS / 1 FAIL** (97-101 s per run; the seven
      passes each `+982 ~2`). Against the predecessor's 2 PASS / 5 FAIL that is a real
      improvement and the mechanism behind it is proven load-bearing (see
      `re_verification.gaps_closed` — 5/5 → 0/5 fail-first, measured by me at two revisions).
      Every one of the gap's three `missing:` bullets is discharged. But "the merge gate is
      green" remains false, and the single failing run is instructive rather than noise:

      (a) `test/infrastructure/system/single_instance_lock_test.dart` — "AD-14: release frees
      the address for the very lock that held it". This is DW-131 residual (a) verbatim.
      DW-131 refuses to call it fixed on a clean ten and does the arithmetic for why. **My
      run vindicates that refusal**: 1 failure in 8 at HEAD, consistent with the ≈1/7 the
      predecessor observed. The honest ledger entry is the one thing in this gap that was
      already right.

      (b) `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart`
      — "AD-19: sidecar stderr lines are forwarded to the Logger port", `Expected: true /
      Actual: <false>`. **This is new information.** It is filed in `deferred-work.md:354` as
      `status: parked 2026-08-13`, explicitly as UNCONFIRMED — "it did not reproduce here in
      9 consecutive full-suite runs on the post-patch tree, so it is filed as unconfirmed
      rather than established." It reproduced here. It appears in neither DW-131's residual
      list nor `merge-gate-flakiness-observation.md` §5, both written five weeks later, so
      the phase's own flakiness record is incomplete on a row the ledger already suspected.

      Also, and separately, a record defect the ledger itself was written to correct is
      repeated: `merge-gate-flakiness-observation.md:277` names
      `test/architecture/single_instance_lock_test.dart`. `find test -name
      single_instance_lock_test.dart` returns exactly one path and it is
      `test/infrastructure/system/single_instance_lock_test.dart`. DW-131's `location:`
      gets it right and closes with a paragraph existing solely to correct this slip — and
      then the record DW-131 defers to repeats it, in §5, the one section a reader chasing a
      residual opens.
    artifacts:
      - path: "test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider_test.dart"
        issue: "\"AD-19: sidecar stderr lines are forwarded to the Logger port\" failed once in eight full-suite runs at HEAD. Previously filed as an unconfirmed suspicion (`deferred-work.md:354`); now observed."
      - path: "test/infrastructure/system/single_instance_lock_test.dart"
        issue: "\"AD-14: release frees the address…\" failed once in eight full-suite runs at HEAD — the residual DW-131 carries open and correctly declines to call fixed."
      - path: "test/platform/merge-gate-flakiness-observation.md"
        issue: "`:277` names `test/architecture/single_instance_lock_test.dart`, which does not exist — the exact path slip DW-131 was written to correct. §5 also omits the sidecar row now that it is confirmed."
    missing:
      - "Correct `merge-gate-flakiness-observation.md:277` to `test/infrastructure/system/single_instance_lock_test.dart`. (DW-131 is append-only and is already correct; only the observation record needs the edit.)"
      - "Add the `claude_agent_sdk_correction_provider_test.dart` AD-19 stderr row to the residual list with its now-observed frequency (1 in 8 at HEAD), and note that `deferred-work.md:354` filed it as unconfirmed in 2026-08 and it is no longer unconfirmed."
      - "OR: accept this gap by override. All three of the predecessor's `missing:` bullets are discharged, both remaining rows are pre-existing, out of this phase's code, and now ledgered open — see the override block in the report body."
deferred:
  # Re-mapped this run: the ROADMAP merged the former phases 2-7 into one Phase 2
  # (`9aba184`), so the predecessor's "Phase 4"/"Phase 5"/"Phase 2" targets all resolve to
  # Phase 2's internal waves. Each was re-checked against the merged phase's stated criteria.
  - truth: "CR-03 / WR-01(prior) — a dead X11 worker is never detected or replaced: `_failPending` never clears `_commands`/`_worker`, `_ask` attaches no timeout, so the next `grab()` never completes and the settings surface latches off"
    addressed_in: "Phase 2 (Wave D)"
    evidence: "Phase 2 SC11: awaits 'bounded by one injected teardown bound reused at every site, so the … path cannot hang'. Re-confirmed unchanged: `x11_key_grab_registrar.dart` is not in `git diff --name-only 02ccfef..HEAD`."
  - truth: "CR-04 — the worker readiness handshake has no terminal arm, so a worker that dies before `_readyTag` leaves `_ensureWorker` pending forever"
    addressed_in: "Phase 2 (Wave D)"
    evidence: "Same SC11 clause. Carried forward unchanged."
  - truth: "WR-10 — `dispose()` racing an in-flight spawn leaks the worker and re-arms `_commands` after disposal"
    addressed_in: "Phase 2 (Wave D)"
    evidence: "Phase 2 SC11: 'a stop request arriving during startup's `bindHotkey` portal wait does not run the ordered teardown underneath the rest of startup'."
  - truth: "CR-05 — the `hide` arm's gate admits the late-echo case its own comment excludes, producing a spurious `dismissed` that discards typed text"
    addressed_in: "Phase 2 (Wave C)"
    evidence: "Phase 2 SC7, verbatim: 'An abandoned `hide` whose late echo lands after a completed `show` is not attributed `dismissed`'. PRE-EXISTING (`81c1fa7`/`3f6ffdc`)."
  - truth: "WR-12 — the unavailable read-out's third line contradicts the `revoked` cause line"
    addressed_in: "Phase 2 (Wave A / Wave F)"
    evidence: "SETTINGS-09 appears in Phase 2 SC17 ('`hotkey_status_view.dart`'s doc comment matches the method beneath it'). Also filed as DW-128 for the dead-worker overstatement."
  - truth: "WR-13 — `ConfigLoadResult.warning` interpolates a vendor exception's `toString()` into a logged line"
    addressed_in: "Phase 2 (Wave A), and ledger DW-23"
    evidence: "Phase 2 SC18, verbatim: 'No logged line interpolates an exception's `toString()`' (CONFIG-01)."
behavior_unverified_items:
  - truth: "On Wayland the settings screen displays the desktop's own description text verbatim, read back from the compositor rather than echoed (ROADMAP SC3, first half; HOTKEY-03; plan 01-06)"
    test: "On a real GNOME or KDE session (ideally a non-English locale), bind a shortcut, read the settings screen, then rebind in the desktop's own keyboard settings with the app's settings screen closed and reopen it."
    expected: "The screen shows the compositor's own wording verbatim under the whose-words line — e.g. `Strg+Umschalt+G` on a German desktop — and after the desktop-side rebind the reopened screen shows the NEW description, never the combination the app requested."
    why_human: "Re-measured at THIS HEAD, not inherited: `/usr/bin/grep -rn ListShortcuts test/` = 0 matches, so the re-read branch still has zero test exercise of any kind, and the whole Wayland path runs only against `FakeGlobalShortcutsPortal`, whose replies always carry a `trigger_description` — the branch's single production trigger never fires in the suite. `wayland_portal_global_hotkey.dart` is not in `git diff --name-only 02ccfef..HEAD`. No session bus, no `xdg-desktop-portal`, no compositor in this container. WINDOWS rows 10 and 11."
    disposition: "Accepted by maintainer override on 2026-09-23; live behavior remains unobserved."
  - truth: "A shortcut the desktop accepts but assigns differently counts as bound, and a revoked shortcut is reflected with no re-claim attempt (plan 01-06; D-02, D-08)"
    test: "On a real portal-backed session, have the compositor grant a different combination than requested, then revoke the shortcut from the desktop's settings while the daemon is resident."
    expected: "The divergent grant renders as bound (the desktop's wording), not as a refusal; the revocation renders 'Your desktop took this shortcut away…' and the daemon issues no re-bind of any kind."
    why_human: "Both are state transitions driven only by the fake portal's `ShortcutsChanged`. No real compositor has been observed producing either; presence and wiring cannot stand in for them. IMPROVED but not discharged by 01-23: the rows covering this file are no longer the nondeterministic ones — I measured the portal suite 5/5 green under 16-core saturation where the pre-change tree was 5/5 red — so the evidence these rows give is now trustworthy. It is still fake-portal evidence."
    disposition: "Accepted by maintainer override on 2026-09-23; live behavior remains unobserved."
coincidental_reliance_items:
  - truth: "01-21 truth 5 — the four pre-existing output directories under `/tmp/worker-gone-probe-out/` are restricted to 0700 rather than deleted"
    reason: undeclared-precondition
    harden: >-
      Verified true on this host (`ls -ld` reports `drwx------` for all five). But it holds
      because a human ran `chmod` out of band, and nothing in the tree records or re-asserts
      it: the script deliberately does not reach into its predecessors' directories (01-21
      SUMMARY `:152`, and correctly so). A fresh checkout on another host with older output
      directories inherits nothing. Declare it as a one-time operator step in the observation
      record, or accept that the truth is about this disk and not about the artifact.
      Advisory only — the truth is VERIFIED and this changes no score.
human_verification:
  - test: "Decide whether a phase may close a core-value defect using an artifact that carries a different core-value defect — now on its second iteration."
    expected: "An explicit maintainer decision. This report says no, for the second time, and reports it as a gap. The shape has changed: the LEAK half is genuinely closed (0700 in the script, 0700 on disk) and what remains is the LOSE half — a gate that a newline-only selection walks through, and a seizure the record denies happening."
    why_human: "A judgment-tier trade between two clauses of the same Core Value sentence. Reversible by an override."
    resolution: "Plan 01-25 removed the reproduced loss and corrected the record; the dedicated-display condition is explicit. Reverified on 2026-09-23."
  - test: "Decide whether `gaps[3]` (the merge gate) should be accepted by override rather than carried as a gap."
    expected: "A maintainer ruling. All three remediation bullets are discharged, the mechanism fix is fail-first proven, and both residual rows are pre-existing, outside this phase's code, and filed open (DW-131 and `deferred-work.md:354`). The counter-argument is that 7/8 is not green and this phase's record still leans on suite-green claims."
    why_human: "A scope judgment about a pre-existing test-harness defect no ROADMAP phase owns — re-checked this run: no Phase 2 success criterion covers test-harness reliability."
    resolution: "Project maintainer accepted the documented CI override on 2026-09-23; the 7/8 result and residual flakes remain disclosed."
  - test: "WINDOWS row 32 — 01-16's plan verify #4 ('at least three rows NAME `workerGone`') was met by substituted evidence rather than literally."
    expected: "A reviewer's blessing, which the record explicitly says is owed and which no reviewer has given."
    why_human: "Unchanged from the predecessor. Not settled by any grep."
    resolution: "Reviewer accepted the disclosed substitution in UAT test 15 on 2026-09-23; the literal row-name count was not claimed."
  - test: "WINDOWS row 35 — WR-04's allocate-before-publish reorder shipped with no behavioural coverage, and WR-01 says the reorder opened an X-connection leak on the `calloc`-throws path."
    expected: "A reviewer reads the change with WR-01 in hand. The SIGSEGV was never reproduced and the plan prohibited manufacturing a row that hand-sets private state."
    why_human: "Unchanged. The change with no coverage is the one to look at hardest."
    resolution: "Reviewer accepted the documented untested path and leak concern in UAT test 16 on 2026-09-23; no runtime proof is claimed."
  - test: "WINDOWS rows 33 and 34 — 01-17's two open deviations (one probe run halted undiagnosed at warm-up; the config is asserted rather than seeded)."
    expected: "Both are disclosed rather than hidden; both are open."
    why_human: "Unchanged."
    resolution: "Reviewer accepted both disclosed deviations with their limits in UAT test 17 on 2026-09-23."
  - test: "Four `human_judgment: true` coverage items — 01-18 D6, 01-19 D3, 01-20 D6, and 01-21's 'the panel capture is empty, read by eye'."
    expected: "A human reads the artifacts. I discharged the fourth myself by opening the PNG (it is the panel editor, and it is empty in that run); the first three stand."
    why_human: "No grep settles any of them."
    resolution: "Reviewer accepted the three remaining judgment-dependent artifacts in UAT test 18 on 2026-09-23; the 01-21 PNG check remains historical evidence."
  - test: "Bookkeeping: `.planning/REQUIREMENTS.md`'s status table reads `Gaps Found` for nine of this phase's ten requirement IDs."
    expected: "A decision on whether to restore the statuses the last two verifications measured as satisfied. Only HOTKEY-04 reads `Complete` (flipped by 01-22); HOTKEY-01 and HOTKEY-08 read `Complete` at the predecessor's HEAD and do not now."
    why_human: "A record-keeping decision, not a codebase gap. The table understates the codebase."
    resolution: "Reviewer approved UAT test 19 on 2026-09-23; eight satisfied IDs were marked Complete on both ledger surfaces. HOTKEY-03 and ARCH-02 retain Gaps Found pending real-portal evidence."
  - test: "Review plan 01-25's revised operator contract against its probe preflight and cleanup."
    expected: "The reader accepts that another CLIPBOARD owner causes a no-write refusal, while an accepted run takes an empty selection, and that a dedicated display is the condition for the screenshot expectation."
    why_human: "The plan's D3 coverage marks operator clarity as a human judgment; keyword checks alone do not settle it."
    resolution: "Reviewer accepted the bounded §7 operator contract in UAT test 20 on 2026-09-23."
  - test: "Review plan 01-25's retained 0700 output, scoped teardown, and prior workerGone observation."
    expected: "The earlier live observation remains credible for the unchanged bundle and capture path, while the new preflight-only harness proves the ownership change."
    why_human: "The plan's D4 coverage is a human judgment because this closure did not repeat a full bundle/capture run."
    resolution: "Reviewer accepted the retained output, teardown, and prior capture evidence in UAT test 21 on 2026-09-23."
---

# Phase 1: Hotkey Truth Verification Report

**Current verdict (2026-09-23):** Phase 01 is passed with two explicit maintainer
overrides: the CI merge-gate result and the remaining live human checks. The
clipboard gap is closed under plan 01-25's bounded dedicated-display contract.
The 2026-09-14 analysis below is retained as historical evidence; its earlier
`gaps_found` statements and row 26 verdict are superseded by the current
re-verification addendum at the end of this report. Two real-compositor truths
remain unobserved and are accepted by override, as detailed below.

**Phase Goal:** A binding the daemon reports is the binding the display server actually
holds, and a backend that is missing or refuses degrades visibly instead of lying or
preventing startup
**Verified:** 2026-09-14T16:40:00Z
**Status:** gaps_found — 1 unresolved clipboard-safety gap; the CI gap was accepted by maintainer override on 2026-09-23
**Re-verification:** **Yes.** Previous verdict `gaps_found`, 23/26, at HEAD `307f7f2`. This
one is at HEAD `c63db14`, after the four-plan `--gaps-only` closure set 01-21 … 01-24 and
the scoped review `c63db14`.
**Mode:** ROADMAP records `Mode: mvp` for this phase, but the goal is not in User Story
form. Per the MVP-mode guard this is a standard goal-backward verification. Flagged for the
third time: either the goal or the mode marker is wrong.

## The verdict in one paragraph

**Three of the four gaps closed, two of them cleanly, and the fourth closed its
remediation without closing its truth.** The daemon-teardown gap is properly dead — the
guard, the anchoring and the single call site all check out. The stale prose count is dead
and I counted the enum rather than trusting either the code or the review. The merge gate's
portal-suite mechanism is genuinely fixed and I proved it fail-first in my own process at
two revisions: 5/5 red before, 0/5 red after, under identical 16-core contention. What did
not close is the half of the privacy gap that mattered most. The probe still photographs the
correction panel — I opened the capture and it is the "Your text" editor — and the only
thing now standing between that file and the user's text is a shell predicate that
`$(...)` defeats. I reproduced that on a throwaway Xvfb: a selection holding three bytes
reads back as length zero, the gate passes, and the next line takes the selection away from
its owner irrecoverably. The observation record then tells the next operator the probe
refuses rather than clearing, which is false on every run. **01-REVIEW.md's CR-01 is
upheld on my own evidence, not inherited.** The phase traded a world-readable leak for a
narrow destructive loss, and the two halves of the Core Value sentence are still being
played against each other.

## What this verification did rather than read

1. **Reproduced CR-01 on a throwaway `Xvfb :77` I started and tore down.** With a
   newline-only selection owned: `xclip -o | wc -c` = **3**, the gate's own expression
   reads `len=0`, `GATE PASSES`. Then confirmed the seizure is irrecoverable — a `image/png`
   selection reports `bytes=0` for its own target afterwards.
2. **Proved 01-23's fix fail-first in a detached worktree at `02ccfef`.** `flutter pub get`,
   then five contended runs: **5/5 FAIL**. Same command at HEAD: **0/5 FAIL**. Worktree
   removed; `git worktree list` back to one entry; `git status --porcelain -uno -- lib/
   test/ tool/` empty.
3. **Ran the CI merge gate eight times** instead of trusting either 10/10 or 2/7.
   **7 PASS / 1 FAIL.**
4. **Opened the panel capture from the executor's own live run** rather than reading its
   transcription. It is the "Your text" editor with three register cards, and it is empty.
5. **Checked the executor's ten measurement logs are ten runs** — ten distinct md5sums, one
   minute apart — rather than accepting a recorded ratio.
6. **Tested the EXIT-trap semantics with the probe's actual flags.** `set -e` propagates a
   trap's `return 1`; `set -uo pipefail`, which is what the probe uses (`:28`), does not.
   WR-03 stands.
7. **Counted the enum and the return sites** (4 values, 4 `HotkeyCaptureRefused(` returns +
   1 constructor) rather than trusting the fix, the review, or the SUMMARY.
8. **Used `/usr/bin/grep` (GNU 3.11) for every count**, because this shell's `grep` is
   ugrep 7.8.4.

## Tree state and gates — re-run here, not read

| Gate | Command | Result |
| --- | --- | --- |
| Analyzer | `dart analyze --fatal-infos` | **No issues found**, exit 0 |
| Binding-free suite (the CI command verbatim) | `dart test --exclude-tags=live test/application test/architecture test/domain test/infrastructure test/fakes_smoke_test.dart` | **7 PASS / 1 FAIL over 8 serial runs.** Passing runs: `+982 ~2`. See gap 2. |
| Flutter-bound suite | `flutter test test/ui test/platform test/composition` | **165 passed / 7 skipped**, exit 0 |
| Portal suite, contended (HEAD) | 16 busy loops + 5 serial runs of the portal file | **0/5 FAIL**, `+71` each |
| Portal suite, contended (pre-change worktree at `02ccfef`) | identical | **5/5 FAIL** |
| Assertion budget | `expect(` / `test(` / `skip:\|retry:` in the portal suite | 237 / 69 / 0 — baselines held exactly |
| Ledger append-only | `git diff --numstat 02ccfef..HEAD -- …/deferred-work.md` + per-commit sweep | `15 0`; one commit touches it, **deletions=0** |
| Frozen ports | `git diff --numstat 02ccfef..HEAD` over the 4 declared port files | empty |
| `lib/` blast radius | `git diff --numstat 02ccfef..HEAD -- lib/` | `1 1` — one line, one file |
| Formatter | `dart format --output=none --set-exit-if-changed lib test` | 1 file would change — `window_manager_panel_visibility_test.dart`, **not** in the closure diff, and not a CI gate. INFO only. |

`lib/`, `test/`, `tool/` and `_bmad-output/` are clean at HEAD.

## Goal Achievement

### Observable Truths

Rows 0–25 are the predecessor's. They are regression-checked rather than re-derived, and
that is sound here for a mechanical reason: the entire closure set changes **one line of
`lib/`**, no frozen port, and no adapter. Rows 24, 3 and 11 — the failed and the
behavior-unverified — got full three-level re-verification. Rows 26–29 are new, one per
closure plan.

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 0 | **GOAL, first clause** — a binding the daemon reports is the binding the display server actually holds | ✓ VERIFIED | Re-checked at HEAD: the disjunct `if (stillInEffect == null \|\| cause == HotkeyUnavailableCause.noBackend)` is live at `x11_global_hotkey.dart:227`; `_causeOf` maps `workerGone => noBackend` and bounds it (`:490-496`). `grep -rn workerGone test/` = 31 (was 27). The observed-on-screen proof at two revisions stands, and the committed post-fix PNG is still tracked. |
| 1 | **SC1** — the two human decisions recorded before any implementation task is planned | ✓ VERIFIED | Regression-checked; the ledger's only in-range commit is DW-131, additive. |
| 2 | **SC2** — a grab another X11 client owns reports failure; a missing backend leaves the daemon running | ✓ VERIFIED | Regression-checked; no adapter in the closure diff. |
| 3 | **SC3** — a Wayland binding is read back rather than echoed; a key refused on X11 cannot be entered by name | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Second half verified. First half unchanged and unexercised: `/usr/bin/grep -rn ListShortcuts test/` = **0**, re-measured this run. |
| 4 | **SC4** — a consumer can tell "no backend" from "this key refused" from "binding revoked" without parsing a string | ✓ VERIFIED | Unchanged; row 0's fix is what makes it genuine. |
| 5 | **SC5** — precedence stated; `modifiers` unmutatable; the re-measure trigger observable | ✓ VERIFIED | Regression-checked; `lib/` blast radius is one doc comment. |
| 6 | **01-01** — DW-89 closed without contradicting its `decision:`; AD-9 shape recorded before any `lib/` edit; Phase-7 hand-off filed | ✓ VERIFIED | Regression-checked; zero ledger deletions in range. |
| 7 | **01-02** — refused grab reported as a refusal; libkeybinder gone; registrar inert at construction | ✓ VERIFIED | Regression-checked. |
| 8 | **01-03** — a refused rebind leaves the previous shortcut firing; at most one grab held | ✓ VERIFIED | Regression-checked; DW-129 (the amendment) untouched and not deleted. |
| 9 | **01-04** — three causes readable from a field, three distinguishable sentences, no default | ✓ VERIFIED | Regression-checked. |
| 10 | **01-05** — a sandboxed build never calls `Registry.Register`; steps bounded; budget injected | ✓ VERIFIED (code) | Not in the closure diff. Wire behaviour still owed to a real portal. |
| 11 | **01-06** — a later-mounting screen reads what is in effect synchronously; the desktop's wording verbatim | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Rolls into row 3. Improved in evidence quality: the rows covering this file are no longer the flaky ones (5/5 green under saturation where the pre-change tree was 5/5 red), but they are still fake-portal rows. |
| 12 | **01-07** — set by pressing; no free-text field; capture-time refusals; neither ui nor application names the catalogue | ✓ VERIFIED | Regression-checked. |
| 13 | **01-08** — precedence in the port; same-turn backend change wins; startup seed rule unchanged | ✓ VERIFIED | Frozen-port diff empty. |
| 14 | **01-09** — a caller mutating its own set cannot change equality; exactly one constructor | ✓ VERIFIED | Regression-checked. |
| 15 | **01-10** — every closed entry dated with `resolution:` and file:line evidence; nothing deleted | ✓ VERIFIED | Per-commit sweep in range: one commit touches the ledger, deletions = 0. |
| 16 | **01-11** — a committed harness classifies one press from a timestamped X event stream | ✓ VERIFIED | `panel_toggle_probe.sh` not in the closure diff. |
| 17 | **01-12** — one press at a visible panel hides it and leaves it hidden; CAP-14's genuine hides still fire | ✓ VERIFIED | Not in the closure diff. |
| 18 | **01-13** — all six baselined routes re-run and compared; the behaviour change named as a change | ✓ VERIFIED | `panel-toggle-observation.md` unchanged in range. |
| 19 | **01-14** — defect, cause and fix recorded as a closed ledger entry; residuals filed open | ✓ VERIFIED | DW-122…DW-130 unchanged; DW-131 appended beside them. |
| 20 | **01-15** — a fail-first oracle for the `workerGone` rebind, recorded RED before any fix | ✓ VERIFIED | Regression-checked; `workerGone` test hits grew 27 → 31, none removed. |
| 21 | **01-16** — the refusal CODE decides the seam-refused arm; `current` agrees with `bind()` | ✓ VERIFIED | Re-read at HEAD: `_causeOf`'s five arms still map only `noBackend`/`workerGone` to `noBackend`. |
| 22 | **01-17** — the arm reached FOR REAL and read off the screen; the pre-fix commit reads the false report; the source trees provably untouched | ✓ VERIFIED **as written** | Unchanged, and the predecessor's caveat still applies: the truths are narrower than the isolation property they were written to establish, which is where gap 1 continues to live. See also WR-03 in Anti-Patterns — `assert_no_trace` cannot fail the run, pre-existing and untouched by 01-21. |
| 23 | **01-18** — both halves of the witness seam carry the AD-15 backstop; `_open` cannot publish a half-opened state | ✓ VERIFIED (with warning WR-01) | Regression-checked; the leak-on-`calloc`-throw warning stands. |
| 24 | **01-19** — no unreachable branch in the capture validator; …**every prose site agrees with the new count**; no frozen port moved | ✓ **VERIFIED (was FAILED)** | Closed by 01-22 and re-measured here with `/usr/bin/grep`: `five[ -](subject\|thing)` = 0 in `lib/` and `test/`; the broader `\bfive\b` sweep filtered for subject/refusal/enum terms = 0; enum = 4 values; 4 refusal return sites. |
| 25 | **01-20** — WR-05 filed open; 01-03's truth amended IN THE LEDGER; 01-01…01-14 byte-identical; zero deletions | ✓ VERIFIED | Regression-checked. Note 01-24 repeated the motion for DW-131's path disagreement. |
| 26 | **01-21** — teardown is a no-op until the run launched something; the match is worktree-scoped; the output dir is 0700 from creation; the four old dirs restricted; **no capture can contain the user's text**; §7 carries the reasoning | ✗ **FAILED** | Four of the seven truths hold and I verified each mechanically (`DAEMON_STARTED` at `:63`/`:99`/`:372`; `"${WORKTREE}/${BUNDLE_REL}"` at `:103`/`:105`; `chmod 700` + `die` at `:262`; five `drwx------` directories on disk). **Truth 6 is falsified in both clauses and truth 7 is satisfied in form while stating two falsehoods.** See gap 1 — reproduced on a live Xvfb, not inherited. |
| 27 | **01-22** — 01-19's truth 4 true as written; the three sites agree; the sweep is proved by a pattern that would have caught the miss; nothing else moves | ✓ VERIFIED | All four hold, all re-measured. "Nothing else moves" is mechanical: `git diff --numstat 02ccfef..HEAD -- lib/` = `1 1`. This is the only change in the set with no defect of its own — a finding I reached independently of, and agreeing with, 01-REVIEW.md. |
| 28 | **01-23** — ONE named mechanism; a fail-first reproduction with a NON-ZERO pre-change count; an ordered barrier, not a bigger budget; no assertion weakened; `concurrency: 1` untouched; the ratio measured over N≥10; every residual named with its frequency | ✓ VERIFIED | Every one checked, and the two load-bearing ones re-run by me at two revisions: **5/5 → 0/5** under identical 16-core contention. The barrier is a D-Bus ping round trip (`_emitSettled`, `:351`), structurally ordered; `_settle()` survives only as a documented in-process drain. `expect(` 237, `test(` 69, `skip:\|retry:` 0, `dart_test.yaml` diff empty. The ten measurement logs are ten distinct runs (ten md5sums). |
| 29 | **01-24** — the residual filed with its own id, anchors, diagnosis and ratio; it CITES the measurement; it distinguishes measured from reasoned; DW-15 not rewritten; zero deletions; **open, not closed on an improvement** | ✓ VERIFIED | DW-131 at `:1873`, `status: open`. It refuses to call the AD-14 residuals fixed and does the arithmetic (p=1/7 → 0.21 for zero-in-ten). **My eight-run sample vindicates that refusal** — the lock row failed once. `15 0` on the file, one commit, zero deletions. Its `location:` also corrects the predecessor's path slip without editing the predecessor. |

**Score:** 27/30 truths verified (2 present, behavior-unverified; 1 failed).

The merge-gate gap is adjudicated below rather than folded into a truth row: 01-23's and
01-24's own truths are all satisfied, and the thing still false — "the gate is green" — is a
phase-level truth no plan claimed. That gap/row split is deliberate and is the same one the
predecessor drew.

### Deferred Items

| # | Item | Addressed In | Evidence |
| --- | --- | --- | --- |
| 1 | CR-03 — dead worker never replaced; `_ask` unbounded | Phase 2, Wave D | SC11's bounded-await clause. Registrar not in the closure diff. |
| 2 | CR-04 — readiness handshake has no terminal arm | Phase 2, Wave D | Same clause. |
| 3 | WR-10 — `dispose()` racing an in-flight spawn leaks the worker | Phase 2, Wave D | SC11: "…does not run the ordered teardown underneath the rest of startup". |
| 4 | CR-05 — the `hide` gate's late echo → spurious `dismissed` → discarded text (**pre-existing**) | Phase 2, Wave C | SC7 names this case verbatim. |
| 5 | WR-12 — the unavailable read-out contradicts itself on `revoked`; also DW-128 | Phase 2, Waves A/F | SETTINGS-09 appears in SC17. |
| 6 | WR-13 — vendor `toString()` in a logged config warning (**pre-existing**) | Phase 2, Wave A + ledger DW-23 | SC18: "No logged line interpolates an exception's `toString()`". |

**Re-mapped this run.** `9aba184` merged the former Phases 2–7 into one Phase 2, so the
predecessor's "Phase 4"/"Phase 5" targets had to be re-resolved rather than copied. Each of
the six was re-checked against the merged phase's stated success criteria; all six still land
inside one. **Nothing in Phase 2 covers test-harness reliability**, which is why gap 2 is not
deferred.

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `tool/uat/worker_gone_probe.sh` | teardown touches only what the run created; durable output cannot carry or expose the user's text | ⚠️ **PARTIALLY REMEDIATED** | 635 lines (was 595). The teardown half is properly fixed and I verified every piece. The privacy half moved from a file-mode defect to a predicate defect: `chmod 700` + `die` at `:262` is right, and the gate at `:213-216` is defeated by `$(...)`. `contains: DAEMON_STARTED` satisfied (3 hits). |
| `test/platform/worker-gone-observation.md` | §7 states what the output dir holds, its mode, and the clipboard precondition | ⚠️ **PRESENT, TWO CLAIMS FALSE** | 322 lines; `contains: 0700` satisfied. `:318-321` states the probe "refuses rather than clearing the selection itself" (false against `:218`) and that the panel is "empty by construction" (only as strong as the defeated gate). |
| `lib/src/ui/settings/hotkey_capture_field.dart` | the validator doc states the count the enum has | ✓ VERIFIED | `:61` reads "The four-subject capture validator". `contains: four-subject` satisfied. One line changed, nothing else. |
| `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart` | the shared barrier replaced by one that does not depend on machine load | ✓ VERIFIED | 2300+ lines, above `min_lines: 2200`. `+16/−4`. `_settle()` retained and demoted with a doc that states why; no row deleted, no assertion relaxed (237/69/0). |
| `test/support/fake_global_shortcuts_portal.dart` | the emit-side ordered barrier | ✓ VERIFIED | `+99/−5`. `_emitSettled` at `:351`; all five `emit*` route through it. `contains: emitSignal` satisfied. Warning WR-07 below. |
| `test/platform/merge-gate-flakiness-observation.md` | the measured ratio over N≥10, per-run outcomes, diagnosis, residuals with frequency | ⚠️ VERIFIED **with one false path** | 372 lines, new. `contains: PASS` satisfied. Honest in register ("A 10/10 is a result, not a proof of a fixed gate"). `:277` names a file that does not exist; §5 omits the now-confirmed sidecar row. |
| `_bmad-output/implementation-artifacts/deferred-work.md` | DW-131 | ✓ VERIFIED | `contains: DW-131` satisfied at `:1873`. `status: open`. `15 0`, zero deletions in every commit in range. |
| `lib/src/infrastructure/hotkey/x11_global_hotkey.dart` | the cause decides the seam-refused arm | ✓ VERIFIED (regression) | Not in the closure diff; the disjunct and `_causeOf` re-read at HEAD. |
| `test/platform/evidence/worker-gone-rebind-sentence-pair.png` | the post-fix screen, committed | ✓ VERIFIED (regression) | Still tracked (`git ls-files`). |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `worker_gone_probe.sh` | processes it did not start | `stop_daemon` returns before any signal unless this run set the started flag; the pattern names the worktree bundle | ✓ **WIRED (was NOT WIRED)** | `:99` guard, `:103`/`:105` anchoring, `:372` set point, single caller. The blocker link of the predecessor is closed. |
| `worker_gone_probe.sh` | the output directory the `RESULT` line names | chmod-700 on the statement pair that creates it, with a halt on failure | ✓ WIRED | `:261-262`. `contains: chmod 700` satisfied; `die` branch present. |
| `worker_gone_probe.sh` | the clipboard of `$DISPLAY` | a preflight gate that refuses on a non-empty selection before anything is captured | ✗ **NOT WIRED** | The gate reads a shell string with its trailing newlines stripped. Reproduced: a 3-byte selection reads `len=0` and the gate passes. The link exists; it does not carry the property. |
| `worker-gone-observation.md` | `worker_gone_probe.sh` | §7 carries the privacy properties the script enforces, so record and script cannot drift | ✗ **NOT WIRED** | They have already drifted, in the direction that matters: the record says the script refuses rather than clears; `:218` clears. `contains: worker-gone-probe-out` satisfied — the pattern matched, the property did not. |
| `wayland_portal_global_hotkey_test.dart` | `fake_global_shortcuts_portal.dart` | the wait is the shared mechanism; the barrier is established on the emit side | ✓ WIRED — **and measured** | Proven by difference at two revisions in my own process: 5/5 red → 0/5 red under identical contention. |
| `merge-gate-flakiness-observation.md` | `.github/workflows/ci.yml` | the record measures the exact scoped command the CI file runs, quoted verbatim | ✓ WIRED | `contains: --exclude-tags=live` satisfied; I re-read `ci.yml:100-105` and ran that command verbatim eight times. |
| `deferred-work.md` (DW-131) | `merge-gate-flakiness-observation.md` | the entry cites the record for its numbers rather than restating them | ✓ WIRED | The `location:` field names the record; §1 explicitly defers to §3/§4. |
| `deferred-work.md` (DW-131) | `dart_test.yaml` | the entry names the comment citing DW-15 and splits the two halves | ✓ WIRED | `dart_test.yaml:11-26` and `:27` cited; DW-15 left `status: done` and unrewritten. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `hotkey_status_view.dart` | `registration.effective` → "In effect: …" | `HotkeyStatus` from the adapter's `current`/`bindingChanges` | Yes — and correctly produces NOTHING when the backend is gone | ✓ FLOWING |
| `hotkey_status_view.dart` | the `noBackend` cause line + the registrar's message | `HotkeyUnavailable(cause, message)` from the cleared arm | Yes — read off a live screen at `49c5f9f` | ✓ FLOWING |
| `hotkey_status_view.dart` | `backendDescription` | `trigger_description` from three cache sources incl. the `ListShortcuts` re-read | Two exercised against a fake; the third by nothing (`ListShortcuts` = 0 in `test/`) | ⚠️ STATIC-RISK — unchanged |
| `worker_gone_probe.sh` | `step-settings-gear-before.png` | `import` of the live toplevel while the **correction panel** is up | Yes — I opened it; it is the "Your text" editor + three register cards, empty in that run | ⚠️ **HOLLOW GUARANTEE** — the file's emptiness is produced by the clipboard gate, and the gate does not hold |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| The clipboard gate refuses a non-empty selection | seeded `[secret]`, ran the gate expression | refuses | ✓ PASS |
| The clipboard gate refuses a **newline-only** selection | `printf '\n\n\n' \| xclip -sel clip` on `Xvfb :77`, then the gate expression verbatim | selection holds **3 bytes**; gate reads `len=0`; **GATE PASSES** | ✗ **FAIL** — gap 1 |
| The seizure is recoverable | seized an owned selection, re-read its own target | `bytes=0` | ✗ **FAIL** — gap 1 (destructive) |
| The probe clears the selection | `/usr/bin/grep -n "printf '' \| xclip"` | `:218`, unconditional once past the gate | ✗ **FAIL** vs the record's claim — gap 1 |
| The probe guards its teardown | `/usr/bin/grep -n DAEMON_STARTED` | 3 hits: `:63`, `:99` (first line of `stop_daemon`), `:372` | ✓ PASS |
| Teardown is worktree-scoped | read `:103`, `:105` | `"${WORKTREE}/${BUNDLE_REL}"`, not `DAEMON_PAT` | ✓ PASS |
| The probe restricts its output dir | `/usr/bin/grep -n chmod` | two hits; `:262` is `$OUT_DIR` with a `die` | ✓ PASS |
| The old output dirs are restricted | `ls -ld /tmp/worker-gone-probe-out/*` | `drwx------` × 5 | ✓ PASS |
| The capture is the panel | opened `post-privacy-fix-…/step-settings-gear-before.png` | "Your text" editor + 3 cards, **empty** | ✓ PASS (empty) / ⚠️ it is still the panel |
| Every prose site says four | `/usr/bin/grep -rniE "five[ -](subject\|thing)" lib/ test/` | 0 | ✓ PASS |
| The capture enum is four | counted values and return sites | 4 values, 4 returns + 1 ctor | ✓ PASS |
| The barrier is load-bearing (fail-first) | contended portal suite at `02ccfef` in a detached worktree | **5/5 FAIL** | ✓ PASS (oracle is red) |
| The barrier works | same command at HEAD | **0/5 FAIL**, `+71` each | ✓ PASS |
| No assertion weakened | `expect(` / `test(` / `skip:\|retry:` | 237 / 69 / 0 | ✓ PASS |
| The recorded ratio was measured | md5 + mtime of the executor's ten logs | ten distinct sums, one minute apart, each `+982 ~2` | ✓ PASS |
| The merge gate passes | the CI command verbatim, ×8 | **7 PASS / 1 FAIL** | ✗ **FAIL** — gap 2 |
| The flutter gate passes | `flutter test test/ui test/platform test/composition` | 165 passed / 7 skipped, exit 0 | ✓ PASS |
| Analyzer | `dart analyze --fatal-infos` | No issues found | ✓ PASS |
| Ledger append-only | `--numstat` + per-commit sweep | `15 0`; deletions=0 in the one touching commit | ✓ PASS |
| `assert_no_trace` can fail the run | reproduced the trap with the probe's `set -uo pipefail` | **exit 0** (with `set -e` it would be 1; the probe deliberately has no `-e`) | ✗ FAIL — WR-03, pre-existing |
| `ListShortcuts` is exercised | `/usr/bin/grep -rn ListShortcuts test/` | 0 | ✗ FAIL — feeds rows 3 and 11 |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist. The phase's probes are the two UAT harnesses.

| Probe | Command | Result | Status |
| ----- | ------- | ------ | ------ |
| `tool/uat/worker_gone_probe.sh` | **not executed by this verification** | — | SKIP — deliberate, and for a narrower reason than last time. The teardown defect that made running it hazardous is fixed and I verified the fix. What remains is that running it would take the clipboard of whatever display it inherits (`DISPLAY="${DISPLAY:-:99}"`, `:49`) and build a release bundle per run. Its **outputs** were verified instead — including the live post-fix run's own capture, which I opened — and the gate it now depends on was tested directly on a throwaway server, which is stronger evidence about the defect than a clean run would have been. |
| `tool/uat/panel_toggle_probe.sh` | not re-executed | — | SKIP — not in the closure diff. |

### Requirements Coverage

All 10 phase requirement IDs appear in `REQUIREMENTS.md`'s traceability table mapped to
Phase 1, and all 10 are claimed by at least one plan. **No orphans.** The closure set
declares only HOTKEY-04 (01-22); 01-21, 01-23 and 01-24 declare `requirements: []` with
reasoning I checked and accept — none of the three serves a ROADMAP requirement, and naming
one would read to a coverage audit as re-work on a satisfied requirement.

| Requirement | Source Plan | Status | Evidence |
| --- | --- | --- | --- |
| HOTKEY-01 | 01-02, 01-03, 01-04, 01-15, 01-16, 01-17 | ✓ SATISFIED | Row 0 re-checked at HEAD. Unchanged by the closure set. |
| HOTKEY-02 | 01-02 | ✓ SATISFIED | Unchanged. Whole-daemon tray quit still owed (UAT test 4). |
| HOTKEY-03 | 01-06 | ? NEEDS HUMAN | `ListShortcuts` = 0 in `test/`; never observed against a real portal. Evidence quality improved (the covering rows are no longer flaky) but the kind of evidence has not changed. |
| HOTKEY-04 | 01-07, 01-19, **01-22** | ✓ SATISFIED **(now cleanly)** | The predecessor's "with one stale comment" caveat is gone: `:61` says four, the enum has four, the sweep is 0. This is the only requirement the closure set touched, and it closed. |
| HOTKEY-06 | 01-01, 01-06 | ✓ SATISFIED | Unchanged; frozen-port diff empty. |
| HOTKEY-07 | 01-08 | ✓ SATISFIED | Unchanged. **Caveat lifted:** its portal-ordering rows were the ones in the nondeterministic suite; that suite is now 5/5 green under saturation where it was 5/5 red. |
| HOTKEY-08 | 01-04, 01-15, 01-16, 01-17 | ✓ SATISFIED | Unchanged. |
| HOTKEY-09 | 01-09 | ✓ SATISFIED | Unchanged. |
| HOTKEY-10 | 01-10 | ✓ SATISFIED | Unchanged. |
| ARCH-02 | 01-01, 01-05 | ✓ SATISFIED (code) / ? NEEDS HUMAN (wire) | Unchanged; needs a Flatpak build against a real portal. |

**Bookkeeping inconsistency (not a codebase gap), and it has moved the wrong way.**
`REQUIREMENTS.md`'s status table now reads `Gaps Found` for NINE of the ten — only HOTKEY-04
reads `Complete`, flipped by 01-22. At the predecessor's HEAD, HOTKEY-01 and HOTKEY-08 also
read `Complete`; `7bea699` reverted them and nothing restored them. Three verifications have
now measured most of these as satisfied and the table still understates the codebase.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `tool/uat/worker_gone_probe.sh` | 213-216 | a predicate that cannot answer the question its own comment states | 🛑 **BLOCKER** | Falsifies 01-21 truth 6. Reproduced: a 3-byte selection reads `len=0`. The whole privacy claim rests here. |
| `tool/uat/worker_gone_probe.sh` | 218 | destroying state the tool did not create | 🛑 **BLOCKER** | Contradicts 01-21's own prohibition ("not a clipboard it did not fill") and the record's §7. X selection ownership is exclusive; the prior payload is unrecoverable. |
| `test/platform/worker-gone-observation.md` | 318-321 | a record that outruns its implementation, in the section that publishes the re-run command | 🛑 **BLOCKER** | The next operator inherits two false guarantees. |
| `tool/uat/worker_gone_probe.sh` | 212-224 vs 236-254 | the destructive step runs BEFORE four refusals | ⚠️ WARNING (WR-01) | A run that halts on a dirty tree, a bad revision, a running daemon or a failed `mktemp` has already taken the selection. The file applies this ordering discipline correctly elsewhere (`SOURCE_TREES_WERE_CLEAN`). |
| `tool/uat/worker_gone_probe.sh` | 217-224, 119 | `pgrep -f` without `-u`; last-wins into a single scalar; a fixed 0.5 s with no check | ⚠️ WARNING (WR-02) | The same class gap 2 of the predecessor was about, at smaller scale: `cleanup` `kill`s a pid derived from an all-user match inside a race window. Bounded in practice by uid permissions, not by the code. |
| `tool/uat/worker_gone_probe.sh` | 134-169 | an `EXIT`-trap assertion whose `return 1` cannot reach the exit code | ⚠️ WARNING (WR-03) | **Pre-existing** — `assert_no_trace` is untouched by the closure diff, so 01-21's "do not weaken existing guarantees" prohibition holds. Reproduced with the probe's own `set -uo pipefail`: a run that leaves the injected `throw` in a tracked `lib/` file still exits 0 and still prints a `VERDICT=` line. |
| `tool/uat/worker_gone_probe.sh` | 49 | `DISPLAY="${DISPLAY:-:99}"` | ⚠️ WARNING (WR-04) | Pre-existing, now more consequential: inheriting a live `DISPLAY` means the probe takes that session's clipboard. The halt text advises a dedicated display; nothing enforces it. |
| `test/platform/merge-gate-flakiness-observation.md` | 277 | a cited path that does not exist | ⚠️ WARNING (WR-05) | The same slip DW-131 was written to correct, repeated in the record DW-131 defers to. Confirmed: `find test -name single_instance_lock_test.dart` returns one path, under `test/infrastructure/system/`. |
| `test/support/fake_global_shortcuts_portal.dart` | 853-872 | an exclusion keyed on a bare method name, justified by an unasserted grep | ⚠️ WARNING (WR-07) | `if (name == 'Ping')` skips `methodCalls` recording. The barrier's ping is `org.freedesktop.DBus.Peer.Ping`; keying on the interface costs nothing. A future portal method named `Ping` would vanish from the list AD-11's step-4-comes-last row reads — silently passing it rather than failing it. |
| `tool/uat/worker_gone_probe.sh` | 260-262 | no `umask`, so files inside the 0700 directory are `0644` | ℹ️ INFO (IN-04) | Measured: every file is `-rw-r--r--`, protected only by the containing directory's mode. One `PROBE_OUT_DIR` pointed at an existing shared leaf and the captures are world-readable again. |
| `test/support/fake_global_shortcuts_portal.dart` | 379-381 | a lazy `where` view over a mutable list, iterated across `await` | ℹ️ INFO (IN-05) | Not reachable today; the hooks exist so a row can run arbitrary code inside a handler. |
| `test/infrastructure/panel/window_manager_panel_visibility_test.dart` | — | `dart format` would change it | ℹ️ INFO | Pre-existing; not in the closure diff and not a CI gate (`ci.yml` runs analyze + tests only). |
| all closure-set files | — | debt markers | ℹ️ INFO | **Zero.** `/usr/bin/grep -nE "TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER"` over all six modified source/doc files returns only `worker-gone-probe.XXXXXXXX` `mktemp` templates at `:24` and `:253`. |

### Human Verification Required

Routed to `01-UAT.md`. See the `human_verification` block in the frontmatter for the seven
items; the two behavior-unverified Wayland truths are in `behavior_unverified_items`.

**On gap 2, an override looks defensible and I am saying so rather than leaving it
implicit.** Every one of the predecessor's three `missing:` bullets for the merge gate is
discharged, the mechanism fix is proven load-bearing fail-first, the pass rate moved from
2/7 to 7/8, and both surviving rows are pre-existing, outside this phase's code, and filed
open in the ledger. If the maintainer accepts that a filed-and-measured residual is the
right resting place for a pre-existing harness flake no phase owns, add to this file's
frontmatter:

```yaml
overrides:
  - must_have: "The gates this phase's record rests on actually pass — the CI merge-gate command in .github/workflows/ci.yml is green"
    reason: "All three remediation bullets discharged; the portal mechanism is fail-first proven fixed (5/5 -> 0/5 contended); the two residual rows are pre-existing, outside phase-1 code, and filed open (DW-131, deferred-work.md:354). 7/8 measured at HEAD."
    accepted_by: "{name}"
    accepted_at: "{ISO timestamp}"
```

**I am not suggesting an override for gap 1.** The must-have is falsified on reproduced
evidence, the artifact still photographs the user's panel, and the fix is four lines the
review already wrote out.

### Gaps Summary

Three of four gaps closed, and two of those are model closures. The daemon-teardown fix is
guarded, anchored and single-caller, and I checked each of the three properties rather than
the presence of a keyword. The four-subject fix is complete and I counted the enum. The
merge-gate work is the strongest engineering in the set: one named mechanism, a fail-first
oracle with a non-zero pre-change count, an ordered barrier rather than a bigger budget, not
one assertion weakened, a ratio instead of an exit code, and a ledger entry that refuses to
call its residuals fixed. I re-proved the load-bearing half myself at two revisions, and
DW-131's refusal to round its residuals away was vindicated three hours later when one of
them failed in my eighth run.

**The fourth did not close, and it did not close on the half that names the Core Value.**
The predecessor asked for two things: restrict the directory, and stop capturing a populated
panel. The first was done thoroughly — in the script, with a `die`, and retroactively on
disk for every directory an earlier run left. The second was replaced with a different
design: keep the capture, guarantee the panel is empty. That design is legitimate, and the
guarantee is a single shell predicate that I reproduced failing. A selection holding three
bytes reads back as length zero; the gate passes; the next line takes the selection away
from its owner and it is gone. The blast radius is narrow — a clipboard holding only
newlines — and the direction is the wrong one: the phase has now converted a "leak" into a
"lose", and both words are in the same sentence of the Core Value. The record then makes it
harder to catch by telling the next operator the probe refuses rather than clears, which is
false on every single run.

This is the third time in this phase's record that a sample has been presented as a
measurement. The executor tested the gate with the string `[secret]` and it refused,
correctly; that is one point in a domain. The barrier work in the same closure set is the
counter-example and the standard: it did not stop at one green run, it built an oracle that
was red first. The clipboard gate deserved the same treatment and did not get it.

Nothing here falsifies the daemon. The phase goal — both clauses — is achieved in the
shipped code, and row 0 is stronger now than at any previous verification. What is not
achieved is a clean close, and the two things standing in the way are four lines of shell
and two sentences of prose.

---

_Verified: 2026-09-14T16:40:00Z_
_Verifier: Claude (gsd-verifier)_

## Maintainer amendment — 2026-09-23

The project maintainer accepted the CI merge-gate gap by override because CI is not required for this milestone. The historical measurement remains 7 passes in 8 serial runs, and the residual flakes remain filed; this decision does not say the gate is green. The `gaps:` entry and the corresponding human decision are resolved for current GSD audits. The 2026-09-14 verification score and `overrides_applied` count remain the result of that verifier run; the override will be applied to the score on the next verification.

The clipboard-safety gap remains open until plan 01-25 is executed and verified.

## Re-verification amendment — 2026-09-23, plan 01-25

**Status: passed by maintainer override. Score: 29/31 must-haves verified; two real-compositor behaviors remain unobserved and accepted.** This is a current verdict over the historical 2026-09-14 report, not a claim that its old counterexample never occurred.

### Goal and scope

The ROADMAP goal's production hotkey behavior has not changed since `c63db14`. `git diff --name-only c63db14..b6fa26b -- lib/` is empty, as is the diff over the frozen domain ports. The ten Phase 01 requirement IDs retain the mapping and evidence in the Requirements Coverage table above; plan 01-25 declares `requirements: []` because it repairs the evidence artifact, not a new product capability. The previous verifier's rows 0-25 and 27-29 therefore remain applicable. Rows 3 and 11 still require a real portal-backed desktop.

The predecessor's row 26 bundled a true 0700/teardown result with an **absolute** claim that no capture could contain user text. The old payload gate made that claim false and destroyed a foreign selection. Plan 01-25 supersedes that absolute wording with a checked ownership precondition and a dedicated-display operating condition. This verification credits row 26 only under that bounded contract. A shared display can change CLIPBOARD after the last check; neither the probe nor this report promises an unconditional screenshot guarantee there.

### Direct evidence for G-01-20 and new row 30

I ran `bash -n tool/uat/worker_gone_probe.sh test/platform/worker_gone_probe_preflight_test.sh` and `bash test/platform/worker_gone_probe_preflight_test.sh` at the corrected HEAD: syntax passed; all three cases passed. The same harness command had failed all three cases before the probe edit. Its newline case recorded `3 → 0` bytes and TARGETS disappearance before the fix, then `3 → 3` bytes and `TARGETS,UTF8_STRING` on both sides afterward. Its non-text case recorded an empty default payload with `TARGETS,image/png → absent` before the fix and `TARGETS,image/png → TARGETS,image/png` afterward. Both green owner cases exited 2 on `HALT (preflight): another clipboard owner...`, before the invalid-revision branch. The later-refusal case moved from one xclip write to zero, with CLIPBOARD unowned afterward. These are real selection owners on separate Xvfb/openbox servers, and each child invoked the current probe file by absolute path from a clean scratch Git repository.

Source review found `require_unowned_clipboard` called once before the dirty-tree gate and once immediately before the only empty-selection write. That write is after the revision, running-daemon, temporary-root, output-directory, and `chmod 700` refusal paths; no `die` follows it in `preflight`. The pre-existing `DAEMON_STARTED` guard, `CLIPBOARD_OWNER_PID` teardown, 0700 restriction, and earlier workerGone observation remain. The §7 re-run instructions now say what a refusal and accepted run each do and recommend a dedicated Xvfb display. The earlier screenshot was not recreated by this preflight-only harness; 01-21's live observation remains its evidence.

**Row 30 — 01-25:** ✓ VERIFIED. The fail-first harness, two owned-selection refusals, late-refusal no-write check, and truthful operator record meet the plan's six must-have truths under the stated display condition. Row 26 is now ✓ VERIFIED under the same revised condition. No new production or requirement regression was observed.

### Accepted human checks and CI override

The two behavior-unverified items remain unobserved: the compositor's own localized wording after a desktop-side rebind, and divergent grant/revocation behavior without an automatic re-claim. The maintainer accepted both for phase progression on 2026-09-23. The seven previously skipped UAT checks are also accepted by the same explicit waiver, with their prior skip reasons retained in `01-UAT.md`; the waiver does not assert a real portal, Flatpak, or tray-host result. The reviewer accepted UAT tests 15–21 separately. The accepted operator and prior capture judgments retain plan 01-25's dedicated-display and unchanged-bundle limits; this review did not add a new full bundle run.

The maintainer's 2026-09-23 CI override is applied once. The merge-gate measurement remains **7 passes in 8 serial runs** with residual flakes filed. This verifier did not re-run that long gate or claim it is green.

The phase's human checks are accepted by maintainer override. The active security hook
found that `01-SECURITY.md` covered only plans 01-01 through 01-14, then checked
the 18 high/critical later threat rows at ASVS L1 depth; their mitigations were
found and `threats_open` is zero at the configured high threshold. The report
remains partial because 36 medium/low later rows await register integration.
No executable gap plan remains.
