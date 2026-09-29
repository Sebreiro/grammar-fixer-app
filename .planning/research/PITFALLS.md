# Pitfalls Research

**Domain:** Linux tray-resident desktop daemon — dual display-server global hotkeys (X11 grab + Wayland XDG portal), per-request subprocess sidecar, local SQLite plaintext history, Flutter/GTK3 hidden-window panel
**Researched:** 2026-08-30
**Confidence:** MEDIUM-HIGH — every pitfall below is corroborated by an upstream primary source *and* verified against this repo's own code or its deferred-work ledger. Where only one of the two holds, it is marked.

## How to read this file

This milestone is a hardening pass, not a build. The interesting failures are therefore not "we forgot X" — they are **the mistakes hardening passes make**: fixing the symptom the ledger names while the shape that produced it survives, taking three separate passes over the most fragile file in the tree, and closing an entry with a test that a mutation would not kill.

`.planning/codebase/CONCERNS.md` already inventories *what is fragile here*. This file does not restate it. It answers the different question: **what do projects in this exact situation get wrong, how would you notice early, and which phase owns it.**

Each pitfall carries a **Detectability** line with one of three values:

| Value | Meaning |
|-------|---------|
| **Test** | A row in the suite can fail on this. If it is not caught, the test is missing or vacuous. |
| **Hardware** | Only observable on a real desktop session (compositor, X display, portal, tray host). No test in this container can reach it. Must go on the runtime-observation checklist (DW-9 / DW-26). |
| **Mixed** | The mechanism is testable against a fake; whether the fake matches reality is not. |

Suggested phase labels are topical, not prescriptive — the roadmap owns the names. They are used consistently below so the ordering constraints in the last section are readable.

| Label | Topic |
|-------|-------|
| **P-GATE** | Gate reality: make CI actually run, put every test directory behind a gate, root-cause the flake |
| **P-DATA** | Data safety: permissions, corruption recovery, schema baseline, retention, index |
| **P-HOTKEY** | Hotkey truth: X11 grab result, Wayland read-back, visible degradation |
| **P-PANEL** | Panel and window lifecycle: visibility reconciliation, geometry, focus, clipboard ordering |
| **P-EXIT** | Process and shutdown discipline: subprocess groups, bounded awaits, database ownership |
| **P-PROVIDER** | Second correction provider (DW-115) |

---

## Critical Pitfalls

### Pitfall 1: Displaying the requested binding as if it were the effective one (Wayland)

**What goes wrong:**
The XDG GlobalShortcuts portal takes `preferred_trigger` as a *suggestion*. The `BindShortcuts` reply returns `{description, trigger_description}` — and `trigger_description` is a localized, human-readable string describing the trigger **the compositor or the user actually chose**, which need not be what the app asked for. There is no machine-readable binding anywhere in the reply. Apps that keep rendering the combination the user typed into a settings field produce a screen that is confidently wrong: it names a combination that does nothing, while the working combination is never shown.

This project has already avoided the worst version — `effective` is always `null` on the Wayland adapter and the screen says "this backend cannot report the combination in effect" (DW-66). That is honest but it is not a read-back, and DW-80 records the consequence: a compositor rebind emits a state change that is *byte-identical* to what a fresh bind produced, so the user sees the same sentence before and after their own rebind.

**Why it happens:**
The mental model carried over from X11 is "I asked for Ctrl+Shift+G, therefore Ctrl+Shift+G is bound." Under the portal the app is a supplicant, not an owner. The second-order trap is worse: `trigger_description` *looks* parseable ("Press <Control><Alt>space"), so the tempting fix is to parse it back into a `HotkeyBinding`. That is silently wrong on a translated desktop and on any backend that words it differently, and it will fail as a wrong answer rather than as an error. DW-66's decision correctly rejects parsing and chooses to render the vendor prose as prose.

**How to avoid:**
Three rules, in order.
1. Never echo `preferred_trigger` to the user as a fact. It is a request.
2. Render `trigger_description` verbatim, labelled as the desktop's own wording, never re-parsed. This is the first place vendor prose reaches a user in this codebase — say so at the seam so a later reader does not "clean it up" into a parsed binding.
3. Refresh it from three sources, not one: the `BindShortcuts` reply, a `ListShortcuts` call (which returns the currently bound set, or shortcuts bound in *prior* sessions if `BindShortcuts` has not run this session), and every `ShortcutsChanged` signal. An app that reads only the bind reply goes stale the first time the user rebinds in system settings.

**Warning signs:**
- The settings screen shows the same string before and after a compositor-side rebind (DW-80's exact symptom).
- A test proving "a rebind updates the UI" passes only because the *fake* is scripted with a non-null `effective` that no shipped Wayland adapter can produce. DW-80 caught precisely this; treat every `FakeGlobalHotkey` script with a non-null `effective` as suspect unless the row is explicitly about X11.
- Any `RegExp` or `split` applied to a portal string.

**Detectability:** **Mixed.** The subscription, buffering and emit mechanism are testable against an in-process `DBusServer` (and are). Whether the compositor's chosen trigger differs from the request is **Hardware** — GNOME, KDE and Hyprland each word it differently and each will hand back a different string.

**Phase to address:** P-HOTKEY.

---

### Pitfall 2: Silent degradation when the GlobalShortcuts backend does not exist

**What goes wrong:**
GlobalShortcuts backend coverage is not uniform and the gaps are not edge cases. `xdg-desktop-portal-wlr` ships **no** GlobalShortcuts implementation at all, so on sway, niri and wlroots-based Hyprland setups `BindShortcuts` simply fails (error code 5 observed on niri). Separately, `xdg-desktop-portal` 1.21+ hard-rejects an empty app id and requires a non-sandboxed app to call `Registry.Register(app_id)` first, answering `NOT_ALLOWED "An app id is required"` otherwise; GNOME's backend additionally rejects app ids that are not reverse-DNS *and* backed by an installed `.desktop` file. Portals older than 1.20 lack the `Registry` interface entirely.

The failure that hurts is not the error — it is what the app does with it. A daemon whose only visible surface is a tray icon, on a compositor with no backend, becomes a process that consumes RAM and answers nothing, with no statement anywhere about why.

**Why it happens:**
The portal handshake has four independent ways to half-succeed: no portal at all, a portal with no GlobalShortcuts backend, a portal that refuses the app id, and a portal that accepts the session and returns an **empty shortcuts list** as a success response (this codebase's own note: "Portal must have installed `.desktop` file or bind silently fails with success response"). Only the first is an exception. The other three arrive as values that a naive `try/catch` treats as fine.

**How to avoid:**
- Enumerate the four outcomes explicitly as distinct values, not as one `HotkeyUnavailable`. The user action differs per outcome: install a portal backend / install the `.desktop` file / re-grant a dismissed permission / nothing-can-be-done-on-this-compositor.
- Treat **an accepted bind returning zero shortcuts as a failure**, not a success. This is the one that reaches production.
- Make the degradation reachable from the surface that still works: the tray. DW-114 is load-bearing here for a reason unrelated to quitting — the tray is the only guaranteed surface, and this project's tray already carries a `setHotkeyUnavailable(bool)` seam. Widen what it can say rather than adding a second surface.
- Check `Registry.Register` is called and the app id is reverse-DNS before blaming the compositor. Portal 1.21+ makes this a hard gate.

**Warning signs:**
- Startup logs a bind success on a machine where the hotkey does nothing.
- The degradation path is only reachable in tests by forcing an exception — meaning the empty-list and refused-app-id cases have no row.
- Permission dialogs: a *dismissed* portal dialog persists in the permission store and blocks all later attempts until the store is cleared. If the daemon retries and gets the same silent refusal forever with no message, users will conclude the app is broken.

**Detectability:** **Mixed.** All four outcomes are drivable against an in-process `DBusServer` and should have a row each. Which outcome a given desktop actually produces is **Hardware** and needs at least one wlroots session, one GNOME and one KDE on the checklist.

**Phase to address:** P-HOTKEY.

---

### Pitfall 3: "A failed grab must not report success" is unsatisfiable through a wrapper that discards the result

**What goes wrong:**
X11 `XGrabKey` is asynchronous. If another client already owns the combination on the same window, the server answers `BadAccess` **through the error handler in the event loop**, not as a return value — so a naive caller sees nothing. `keybinder-3.0` closes this properly: it wraps the grab in `gdk_error_trap_push`/`gdk_error_trap_pop`, releases the ignorable-modifier variants it just took, and `keybinder_bind` returns `FALSE`.

The truth therefore exists at the C layer and is destroyed one level up. `hotkey_manager_linux_plugin.cc:96` calls `keybinder_bind(...)` and **throws away the `gboolean`**, then answers `fl_method_success_response_new(fl_value_new_bool(true))` unconditionally at :99-100 (DW-39, verified). The commonest real-world failure — the user picked a combination their desktop environment already grabs — arrives in Dart as success. The tray then states hotkeys are available and the settings screen displays a shortcut that does nothing.

**Why it happens:**
Two compounding reasons. First, a wrapper library's job is to hide the platform, and "hide the platform" and "preserve the platform's refusal" are in tension; wrapper authors resolve it toward a simpler API. Second — and this is the part that generalises — **no amount of care in the consuming codebase can recover a discarded result.** This project's own adapter is meticulous about the boundary (`X11GlobalHotkey`'s doc states outright that a `HotkeyBound` here is not a claim keybinder succeeded), and that meticulousness cannot close the gap. The fix has to change the dependency.

**How to avoid:**
- Audit every vendor plugin on a load-bearing path for a discarded native return value. This repo has found the same defect shape **twice**: `keybinder_bind` here and `tray_manager`'s `set_icon` in story 6. Two instances is a pattern, not a coincidence — assume a third exists and go looking before it is found by a user.
- The decided fix (DW-39) is a `dart:ffi` registrar over `libkeybinder-3.0.so.0`. It is correct and it closes four entries at once (DW-39 grab result, DW-40 missing library, DW-42 uninitialised-pointer UB, DW-43 the seven shadowed keyvals). Take it as one change, not four.
- Its own risk must be planned for, not discovered: keybinder calls GDK and installs an X11 event filter, so it must run on the **GTK main thread**, while Dart FFI runs on the Flutter UI thread. That means `g_idle_add` marshalling plus a `NativeCallable.listener` to bring the result back. This is the single largest threading surface in the milestone and **no test in this container can touch any of it** — there is no X display here.

**Warning signs:**
- A registrar whose failure path is reachable only by disposing the seam, never by a refusal from the backend. That is this codebase today: `HotkeyManagerRegistrar.grab` rejects when disposed (a gap it *can* close) and cannot reject on a refused grab.
- `ldd`/`objdump -p` showing a hard `DT_NEEDED` on a library the operational envelope claims is degrading-not-blocking. Measured here: the executable needs `libhotkey_manager_linux_plugin.so`, which needs `libkeybinder-3.0.so.0`, so a host without it starts nothing, degrades nothing, and offers no tray menu to fix it from (DW-40). `DynamicLibrary.open` turns that into a caught error.
- A bind that "succeeded" while a second app's shortcut still fires.

**Detectability:** **Hardware** for the grab result itself and for the whole threading surface. **Test** for the FFI seam's *shape*: that a refused `keybinder_bind` becomes `HotkeyUnavailable` is provable against a fake `DynamicLibrary` lookup, and that a missing library is caught rather than fatal is provable by pointing `DynamicLibrary.open` at a nonexistent soname.

**Phase to address:** P-HOTKEY. Schedule this where a real X session is available; if none is, plan it as build-plus-owed-observation and put every threading claim on DW-9's checklist explicitly rather than implicitly.

---

### Pitfall 4: Bumping `schemaVersion` before the v1 snapshot exists — an irreversible loss

**What goes wrong:**
Drift's migration testing works from committed JSON schema snapshots under `drift_schemas/`, produced by `dart run drift_dev schema dump lib/.../app_database.dart drift_schemas/`. **The snapshot for version N can only be taken while N is the live schema.** This project ships schema v1 with no snapshot and no `onUpgrade` branch — `MigrationStrategy` supplies only `beforeOpen`, leaving drift's default `onUpgrade`, which throws in *both* the upgrade and downgrade directions (DW-101, verified against drift 2.34.3).

The trap is that this milestone contains at least two schema changes: DW-105 wants an index on `(created_at, id)`, and DW-104's retention policy will plausibly want a column or a second index. The moment either lands and `schemaVersion` goes to 2, the v1 baseline is **gone forever** — every user in the field is on v1, no test can ever verify a migration *from* it, and the first upgrade a released daemon performs will be unverified against the schema it is actually migrating.

**Why it happens:**
The snapshot feels like tooling, so it gets scheduled with "migrations", which get scheduled when the first migration is needed. By then it is too late. Nothing fails loudly at the moment of loss; the cost is paid one release later.

**How to avoid:**
- **Take the v1 dump first, in its own commit, before any schema-touching work in this milestone.** This is a five-minute task with a hard ordering constraint, which makes it the single highest leverage item in P-DATA.
- Then `dart run drift_dev schema generate` for the verification test code, and `drift_dev schema steps` for a `stepByStep` `onUpgrade` so the default throwing handler stops being the shipped behaviour.
- Add a gate row that fails when `schemaVersion` is incremented without a corresponding new file in `drift_schemas/`. Without it the same mistake recurs at v2→v3.

**Warning signs:**
- `drift_schemas/` does not exist (today's state).
- `MigrationStrategy` names only `beforeOpen`.
- A plan that lists "add the (created_at, id) index" before "dump the v1 schema".

**Detectability:** **Test** — and this is the rare case where a test can only exist if it is written *before* the thing it guards is destroyed.

**Phase to address:** P-DATA, first item, before every other P-DATA item.

---

### Pitfall 5: Fixing file permissions only for new files

**What goes wrong:**
SQLite creates database files at `SQLITE_DEFAULT_FILE_PERMISSIONS` (0644), further masked by the process umask, so under the common umask 022 `history.sqlite` lands **0644 and world-readable** (DW-106, verified: `AppDatabase.file` hands the path straight to drift's `NativeDatabase` with no explicit mode, and no test asserts one). Every row holds the verbatim plaintext of everything the user has ever corrected — which, for a clipboard-driven corrector, routinely includes private messages and credentials.

The pitfall is not missing the problem. It is fixing it **halfway**: pre-creating the file at 0600 (or setting the umask around the open) protects only *new* installs. Every existing user's history stays 0644 forever, and the fix ships with a test that passes because the test always creates a fresh file.

**Why it happens:**
`dart:io` has no `chmod`, so the ergonomic fix is "create it restricted before opening", which by construction only runs on the create path. The repair path for an already-wrong file needs a different mechanism and nobody writes it because the create path's test is green.

**How to avoid:**
- Do both: create restricted **and** repair-on-open. Check the mode every startup and tighten it if wrong; log once when a repair happens.
- Fix the **directory** too, and prefer it as the primary lever: 0700 on the data directory in `AppPaths` is one call, covers the `-wal` and `-shm` sidecars, covers `config.json`, and does not depend on drift's open path. The WAL/SHM detail matters — they inherit the main database's mode, so a 0644 database yields 0644 WAL, and a fix that only touches the main file during a WAL checkpoint window leaves plaintext readable in `-wal`.
- Write the test against a **pre-existing 0644 file**, not against a fresh directory. A test that only ever exercises the create path is the exact shape that lets this ship half-done.

**Warning signs:**
- The permissions test's `setUp` creates a temp directory and immediately opens the database. No pre-existing-file row.
- `-wal` / `-shm` unmentioned anywhere in the fix.
- A fix in `AppDatabase` and none in `AppPaths` (or vice versa) — the two protect different things and both are needed.

**Detectability:** **Test.** `File.statSync().mode` is readable from `dart:io`; both the fresh-create and pre-existing-0644 cases are ordinary rows.

**Phase to address:** P-DATA. Group with Pitfalls 6 and 7 — all three touch the database open path and doing them as three separate passes means three rounds of regression risk on the same code.

---

### Pitfall 6: No recovery path for a truncated or corrupt database — and the wrong recovery when one is added

**What goes wrong:**
Today a corrupt or truncated `history.sqlite` throws from open onward and the resident daemon can never repair itself (DW-100). Meanwhile AD-13 gives the *config* file an explicit "malformed yields defaults, never a failed startup" rule. The two on-disk artifacts have opposite policies and only one was decided.

The second-order pitfall is the recovery that gets written: **in-place repair**. SQLite corruption is not reliably repairable in place. The sanctioned responses are restore-from-backup or `sqlite3 .recover` (3.29.0+), and a truncated file recovers only up to the truncation point — the missing pages were never written and cannot be reconstructed. An app that catches `SQLITE_CORRUPT` and retries the open has written a loop, not a recovery.

**Why it happens:**
Corruption is rare enough to feel hypothetical, and the daemon-specific causes are invisible in development: interrupted write on logout, power loss during `fsync`, a backup tool copying a live database. A daemon that runs all day on a laptop meets all three.

**How to avoid:**
- Decide the policy explicitly, because both answers are defensible and the ledger flags it as a contract decision: **quarantine-and-recreate** (rename aside, open fresh, tell the user where the old file went) versus **surface-and-refuse**. For a history feature whose loss costs a nice-to-have and whose unavailability costs the whole daemon, quarantine-and-recreate is the right default — but say so, and match AD-13's shape so the two artifacts stop diverging.
- Gate the open on `PRAGMA quick_check` (cheap; skips index cross-checks) rather than full `integrity_check` on a hot path. Run the full `integrity_check` only when `quick_check` is not `ok`, and again on any rebuilt file.
- Do not attempt in-place repair. Quarantine, then optionally offer `.recover` as an explicit user action.
- Whatever the policy, the daemon must **start**. A history database is not a startup dependency.

**Warning signs:**
- `catch (SqliteException) { retry }` anywhere near the open.
- A recovery path with no test for a *truncated* file (the commonest real shape — cut the file to N bytes and reopen).
- The recovery decision documented in a code comment rather than as a contract next to AD-13.

**Detectability:** **Test.** A truncated file, a zero-byte file, a file of random bytes and a valid-but-wrong-schema file are all constructible in a temp directory. The *causes* (power loss, live-copy) are Hardware and not worth chasing; the *responses* are fully testable.

**Phase to address:** P-DATA, with Pitfalls 5 and 7.

---

### Pitfall 7: Unbounded growth, no retention, and no way to delete — with a port that has nowhere to put the fix

**What goes wrong:**
One row per correction, forever, holding full plaintext, with **no cap, no expiry, and no operation on the port that can delete any of it** (DW-104). `CorrectionRepository` is `save` + `recent` only. So even a settings-level "Clear history" has nothing to call — the fix is not a feature, it is a port widening, and this project treats port declarations as frozen spine text.

**Why it happens:**
CAP-7 says the record must exist and survive restart. Nothing says for how long. "Persist it" is a complete-sounding requirement that silently omits the other half of every storage contract.

**How to avoid:**
- Treat retention and deletion as **one decision with two surfaces**: an automatic policy (age or row cap, pruned on open or on a low-frequency timer) and a user-initiated "clear history" / "delete this entry". Shipping only the automatic policy leaves a user who pasted a password with no recourse for up to the retention window; shipping only the manual one leaves the file unbounded.
- Widen the port once, deliberately, in the same change — `prune(before:)` plus `deleteAll()`. Two separate widenings of a frozen declaration is two human-gated decisions where one would do.
- Prune inside the same open path as the permissions repair and the corruption check, so there is one startup pass over the database rather than three.
- `DELETE` does not shrink the file. If the privacy claim is "it is gone", a `VACUUM` (or `PRAGMA auto_vacuum` set at creation — which cannot be turned on later without a vacuum) is part of the fix, not a polish item.

**Warning signs:**
- A "clear history" menu item designed before anyone checked whether the port can express it.
- Retention implemented as `DELETE` with no size measurement afterward.
- A retention window chosen in the plan with no statement of what it protects against.

**Detectability:** **Test** for prune correctness, boundary rows and the port contract. **Test** for file-size-after-vacuum. Nothing here needs hardware.

**Phase to address:** P-DATA, with Pitfalls 5 and 6.

---

### Pitfall 8: An index that exists, a test that proves it exists, and a query plan nobody checked

**What goes wrong:**
AD-7 mandates `CREATE INDEX corrections_created_at_idx ON corrections (created_at)` verbatim. `recent()` orders by `(created_at DESC, id DESC)` — the `id` is a deliberate tie-break so two corrections in the same millisecond come back deterministically. An index on `created_at` alone **does not satisfy that sort**: SQLite materialises a temp B-tree for the tie-break, which shows up as `USE TEMP B-TREE FOR ORDER BY` in `EXPLAIN QUERY PLAN` (DW-105).

The instructive part is the ledger's own note: *"The schema test proves the index exists, never that the query uses it, and no test would notice the plan changing."* That is the general failure — schema assertions are not performance assertions, and a project that has one will believe it has the other.

**Why it happens:**
The index and the `ORDER BY` are written in different files by different concerns (spine SQL vs. repository query) and nothing joins them. Adding the tie-break is obviously correct for determinism and its cost is invisible until the table is large.

**How to avoid:**
- Index `(created_at, id)`. SQLite walks a composite index backwards for an all-`DESC` ordering, so explicit `DESC` on the index columns is optional. **Note:** SQLite has **no `INCLUDE` clause** — a covering index here means every column the query touches is in the index column list. Any guidance suggesting `CREATE INDEX ... INCLUDE (...)` is Postgres/SQL Server syntax and will not parse. (Flagged because a plausible-looking search result asserted exactly this.)
- Assert the **plan**, not the schema: run `EXPLAIN QUERY PLAN` for `recent()` in a test and fail on `TEMP B-TREE`. That is the row that would have caught this and would catch the next one.
- AD-7's `CREATE INDEX` text is spine-verbatim, so this needs a spine renegotiation rather than a local edit. Budget for the human gate; do not discover it mid-execution.
- **Before adding `OFFSET`:** `recent({required int limit})` has no offset today. Large `OFFSET` is O(offset) even with a perfect index, because SQLite still walks the skipped rows. If pagination is genuinely wanted, use keyset pagination on `(created_at, id)` — `WHERE (created_at, id) < (?, ?)` — rather than `LIMIT/OFFSET`. Adding `OFFSET` on top of the wrong index is the version of this pitfall that actually bites users.

**Warning signs:**
- Any schema test whose assertion is "the index is present".
- An `ORDER BY` whose column list is longer than the index's.
- `OFFSET` appearing in a repository method.

**Detectability:** **Test.** `EXPLAIN QUERY PLAN` is a plain query; the assertion is a string match on the plan rows. Slowness at scale is only observable with a large table, but the *cause* is assertable today at any size.

**Phase to address:** P-DATA — **after** Pitfall 4's v1 snapshot, because this bumps `schemaVersion`.

---

### Pitfall 9: A daemon that cannot exit

**What goes wrong:**
Three independent mechanisms in this tree each hold the process open past `main()` returning, and each was introduced for a good reason:

1. **`NativeDatabase.createInBackground`** keeps a background isolate alive, and **no code in `lib/` constructs or closes `AppDatabase`** (DW-110). Measured by adversarial review: a program that opens `AppDatabase.file`, runs one query and returns from `main` **never terminates** — killed at a 30s timeout, exit 124. No test catches it because every test closes explicitly.
2. **Unbounded awaits at teardown.** `CorrectionController.dispose()` awaits pending saves with no timeout — a drift write on a background isolate against a locked database can *hang* rather than reject. `DaemonLifecycle._step` bounds a step that throws, not one that hangs (DW-20). And `shutdown()` issues two cancels back to back where `SingleInstanceLock`'s socket stream cancel can plausibly block.
3. **Exit paths that skip teardown.** `shutdown()` runs only on SIGINT/SIGTERM/SIGHUP; there is no tray Quit (DW-114) and no window-close route.

`dispose()`'s own doc argues *"a daemon that cannot exit is a worse failure than a lost history row"* — and the hang case contradicts it.

**Why it happens:**
Each mechanism is locally correct. Background isolates keep the UI thread free (a CAP-1 requirement). Awaiting a save honours CAP-7. Bounding only failures is the obvious reading of "handle errors". The composite behaviour — a daemon that survives `systemctl stop` until SIGKILL — is nobody's local concern.

**How to avoid:**
- Give `AppDatabase` an owner in the composition root and `await close()` after `disposeControllers()`. Document the obligation on the constructor.
- Bound **every** teardown step with a policy timeout that logs the step by name, continues the remaining steps, and always reaches `exit()`. "Bounded" must mean duration, not just failure.
- Give the tray a Quit that runs the **same** ordered teardown as a signal (DW-114 and DW-20 should land in a consistent order, or the new exit route inherits the unbounded one).
- Route the window close button to `hide()`, not to shutdown: on a tray daemon, close means "put this away". `setPreventClose(true)` plus a close listener keeps exactly two exit routes, both ordered.

**Warning signs:**
- `await` inside a `dispose()` with no `.timeout(...)`.
- A teardown test that proves ordering (this repo has excellent ones — nine mutations, nine failures) but no test that proves *termination*.
- The word "unawaited" near a resource handle.
- Any new exit route added without checking which teardown it reaches.

**Detectability:** **Test** — and the test that is missing is a *process-level* one, not a unit test. Spawn the daemon binary, send SIGTERM, assert it exits within N seconds. Every existing test closes explicitly, which is exactly why none of them catch this. That harness needs a display (DW-9) for the full binary, but a headless `dart run` of a minimal open-query-return program reproduces the isolate half today, in this container, in seconds.

**Phase to address:** P-EXIT.

---

### Pitfall 10: Killing a PID when the child spawns a grandchild — and killing a recycled PGID

**What goes wrong:**
`dart:io` can only signal a single process: `Process.kill` and `Process.killPid` take one pid, and killing a process group is a long-standing unimplemented SDK request (dart-lang/sdk#22470). A Python sidecar that spawns the `claude` CLI is a two-level tree, so a SIGTERM to the interpreter leaves the CLI orphaned and holding a network connection.

**This project already gets the mechanism right** and the correct pattern is worth stating because it is the one to preserve: spawn under `setsid` so the child is a session and process-group leader, then signal the **negated pgid** so the whole chain receives it; SIGTERM first (which lets the SDK abort its network call cleanly), a 2-second grace, then SIGKILL. It also guards the sharp edge most implementations miss — `_processExited` exists because *"after that point its pgid may already belong to an unrelated process, so no signal may be sent."* A negative-pid kill after reap can signal a stranger. That guard is load-bearing and must not be refactored away.

**What is still open** is the surrounding discipline, not the kill:
- `_teardown()` is reached from `onCancel` and from the terminal funnel, but a stream cancelled *during spawn* has a window where the process exists and nothing owns it. The `if (_terminated)` re-check after `Process.start` closes it — that re-check is the second load-bearing line in the file.
- The kill is bounded; the *save* on the same shutdown path is not (Pitfall 9). A correctly-bounded subprocess teardown inside an unbounded shutdown is still an unbounded shutdown.
- `Process.start('setsid', ...)` inherits the environment with no seam, so the adapter's translation of a real sidecar's output is proven against fakes on one side and against the real script on the other, **never joined** (DW-93 / the fake-CLI harness entry).

**Why it happens:**
The single-pid API is the path of least resistance and works perfectly in development, where the sidecar is fast and nothing is cancelled. The grandchild only survives when the user cancels mid-request — which they do, repeatedly, because rapid re-triggering is exactly how a hotkey-driven tool is used.

**How to avoid:**
- Keep `setsid` + negated pgid + SIGTERM/grace/SIGKILL. Do not "simplify" to `process.kill()`.
- Keep the reaped-pid guard and add a comment-anchored test for it — a group kill issued after `exitCode` completes must send nothing.
- Add a row that asserts **no orphan survives** a cancel: spawn a fake sidecar that itself spawns a sleeping grandchild, cancel, then assert the grandchild's pid is gone. Without a grandchild in the fake, the group-kill logic is untested and a refactor to `process.kill()` stays green.
- `setsid` is itself a host dependency and swallows a missing interpreter into an exit code — this codebase pre-probes the paths and maps 126/127 to "not installed" rather than "crashed", which is the right shape. Preserve it when the second provider (DW-115) lands, or the new provider will re-derive it worse.

**Warning signs:**
- Any `Process.killPid(process.pid)` on this path.
- A cancel test whose fake sidecar has no child of its own.
- Orphaned `python`/`claude` processes after a session of rapid hotkey presses — the observable production symptom.

**Detectability:** **Test.** The whole thing is drivable with a shell-script fake sidecar in a temp directory; no display needed. That the *real* SDK aborts cleanly on SIGTERM is **Hardware** (needs a live network call in flight) and belongs on the checklist.

**Phase to address:** P-EXIT, with Pitfall 9. Re-verify under P-PROVIDER when the second provider lands.

---

### Pitfall 11: `gtk_window_present` re-maps the window you just hid

**What goes wrong:**
GTK3's `gtk_window_present` **explicitly calls `gtk_widget_show()` when the window is hidden**. Any "focus the panel" call that lands after a hide therefore resurrects a dismissed window. In a system with no cancellation — Dart has none — a `focus()` issued for a superseded request and abandoned at timeout can arrive *after* the user's dismissal and map the panel back. This is DW-30, already mitigated with a `_visible` gate on the `restore` arm.

The reason it belongs in a pitfalls file rather than a concerns file is that **the shape recurs on every new call added to that adapter**. DW-50's decided geometry work makes `setSkipTaskbar` something the visibility adapter drives *on every transition* rather than a startup constant — a new platform call on the same abandoned-call path, with the same late-arrival hazard, in the same 1292-line file.

**Why it happens:**
`present` reads as "raise and focus", and its show-if-hidden behaviour is a one-line footnote in the GTK docs. The Flutter `window_manager` plugin's `focus()` maps onto it, so a Dart-level reader sees "focus" and reasons about focus.

**How to avoid:**
- Every new platform call added to the visibility adapter must be classified against the three axes the module already uses (echo-capable, mirror claim, visibility state) **before** it is written, not after a review pass finds the race.
- Any call that can map a window must be gated on the current visibility mirror, exactly as the `restore` arm now is.
- For the panel toplevel: it is a utility window, so `skip-taskbar-hint`, `skip-pager-hint` and a UTILITY type hint are the GTK3 levers. DW-50's decision makes the taskbar entry *conditional* (present while showing, absent while in tray) — which is a state machine, not a hint, and it must live in the adapter that owns the transitions.
- Wayland ignores most positioning hints. A remembered position (DW-50's rule b) is an X11 guarantee and a Wayland aspiration; state that asymmetry where the setting is described or users on Wayland will file it as a bug.

**Warning signs:**
- A new `windowManager.*` call added outside the queue, or without a `_visible` / `_disposed` re-check after each await.
- `hidden_window_test.dart`'s allowlist being widened without a written justification — that allowlist exists precisely to force the justification, and widening it silently is how this pitfall enters.
- The panel flickering on dismiss, or reappearing after focus loss.

**Detectability:** **Mixed.** The abandoned-call races are drivable against `FakePanelWindow` (and DW-30/DW-31/DW-36's rows show it works — with mutation verification). Whether the real GTK event ordering matches the fake's is **Hardware**, and the module's comments already document version-specific `window-state-event` vs `configure-event` timing that a GTK update can change under it.

**Phase to address:** P-PANEL.

---

### Pitfall 12: A blur that dismisses a panel that never held the keyboard

**What goes wrong:**
The Linux plugin emits `focus`/`blur` as a pair from `focus-in-event`/`focus-out-event`. The adapter handled `blur` destructively and ignored `focus` entirely — so it could not know whether the window ever *had* the keyboard, and read any `focus-out` as a user dismissal. On a window manager with focus-stealing prevention, `show()` (= `gtk_widget_show` + `gtk_window_present`) maps the window *without* giving it focus, a transient `focus-out-event` arrives, and **the panel the user just summoned takes itself down** (DW-33; reproduced against the shipped tree, now resolved by the panel-event-reconciliation bundle).

This is the archetype for the whole category: **a focus-loss-hide interacting with a toggle hotkey turns the product's core gesture into a coin flip**, and the trigger is a window-manager policy that is completely absent in a development container.

**Why it happens:**
CAP-14 says "hides on focus loss", and `blur` is literally the focus-loss event. The missing premise — that you must first *have* focus in order to lose it — is invisible until a WM with focus-stealing prevention supplies the counterexample.

**How to avoid:**
- Require an observed `focus` before `_onBlur` may act. (Done.) Preserve it: a refactor that "simplifies" the focus tracking away reintroduces the worst user-visible bug in the product.
- Enumerate the *other* blur sources before adding any second focusable window. DW-27 was closed as unreachable specifically because the settings surface is an in-tree view swap rather than a second toplevel — that closure is contingent, and the first modal, tooltip window or portal dialog this app opens re-opens it. Re-file against that change, do not rediscover it.
- The toggle-hotkey interaction deserves its own row: a hotkey pressed while the panel is showing must hide it; a hotkey pressed while the settings *view* is showing currently hides the window instead of returning to the panel (DW-81). Decide that transition table explicitly rather than letting it fall out of two independent handlers.

**Warning signs:**
- A `blur` handler with no corresponding `focus` handler.
- Any new focusable toplevel (dialog, tooltip, portal prompt) with no accompanying review of the blur path.
- Users reporting "the panel flashes and disappears" — that is this, and it will be reported as "the hotkey doesn't work".

**Detectability:** **Hardware** for the trigger (focus-stealing prevention is a WM policy; no container has one). **Test** for the guard: a bare `blur` with no preceding `focus` must be a no-op, drivable against the fake window today.

**Phase to address:** P-PANEL.

---

### Pitfall 13: An `onError`-only backstop on a stream that can *complete*

**What goes wrong:**
`Stream.listen` takes `onData`, `onError` and `onDone`, all optional. `cancelOnError` defaults to **false**, so an error does *not* end the subscription. A **done** event does — permanently — and with `onDone` null, the Dart docs say "nothing happens": no log, no signal, no trace. The consumer keeps looking healthy while receiving nothing forever.

So an `onError`-only backstop guards the case that was never fatal and is blind to the one that is. This project found it twice: DW-36 on the window-event subscription (now fixed, with a three-row test and three negative controls) and the same shape on `X11GlobalHotkey`'s press subscription, whose own comment says *"this is the only route from a key press to the panel, so an error that ended the subscription would silently retire CAP-1"* — correct reasoning applied to the wrong half of the contract.

**Why it happens:**
"Handle errors" is a habit; "handle completion" is not. And the asymmetry in visibility is exactly backwards from the asymmetry in severity: an errored stream leaves a log line and a live subscription; a completed one leaves a dead adapter that still reports healthy.

**How to avoid:**
- Rule: **every long-lived subscription in the daemon gets an `onDone` arm**, even where the source provably cannot close today. DW-36's reasoning is the right one — `PanelWindow.dispose()`'s doc *advertises* closing `events`, so the shape is reachable by design rather than by accident.
- Make the `onDone` message state the *consequence*, not the event ("window events can no longer reconcile the panel visibility mirror"), because that is the whole difference from `onError`.
- Sweep for the pattern rather than fixing instances: `grep -n "onError:" lib/` and check each for a sibling `onDone:`. Candidates today include the hotkey press subscription, the visibility subscription in `CorrectionController`, and the sidecar's stdout/stderr/parser subscriptions.

**How to test a completed stream under a live consumer:**
This is the part that is genuinely hard and the reason the arm goes untested. On the ordinary path the consumer's own `dispose()` cancels the subscription *before* the source closes, so the done event is never delivered and any test that disposes normally proves nothing. The fake must expose a way to **close the source without disposing the consumer** — this repo's `FakePanelWindow.closeEvents()` is exactly that affordance and is the pattern to copy. Three rows are the right shape:
1. Source closed under a live consumer → exactly one log line naming the close and the lost capability.
2. Ordinary `dispose()` → zero lines (proves the cancel precedes the close).
3. A logger whose `error` throws → nothing escapes as an uncaught async error, asserted via the shared `ThrowingLogger`'s `attempts`, **not** merely "nothing escaped".

Row 3's detail is load-bearing: an earlier revision of DW-36 asserted only that nothing escaped, and that row **stayed green when the `onDone` arm was deleted outright.** A vacuous test is worse than none, because it retires the ledger entry.

**Warning signs:**
- `listen(` with `onError:` and no `onDone:`.
- A fake with `dispose()` but no way to close its stream independently.
- Any test row that passes when the code it covers is deleted — always run the negative control.

**Detectability:** **Test**, given the right fake affordance. The absence of that affordance is why it looks like Hardware.

**Phase to address:** P-PANEL for the sweep, but the *rule* belongs in the project's engineering conventions so new subscriptions inherit it.

---

### Pitfall 14: A CI workflow that has never executed

**What goes wrong:**
`.github/workflows/ci.yml` exists, is well reasoned, and carries its own header: **"STATUS: NEVER EXECUTED"** (DW-88). Every claim in it is a claim about what the file *says*. A never-run workflow is not a gate — it is a document about a gate, and it will fail on its first real run for reasons that have nothing to do with the code under test.

Two compounding gaps:
- **Test directories no gate runs.** `test/platform/`, `test/ui/` and `test/composition/` need a Flutter binding, so they run only under `flutter test` — which the workflow deliberately excludes (ci.yml:16-19). Those directories hold the *only* proof of `MethodChannel` routing, CAP-2's re-seed reaching a widget, CAP-4's digit keys, CAP-11's copy button, CAP-13's inline error and CAP-12's entire user-facing contract (DW-29, DW-51, DW-74). The mitigation those entries originally rested on — "`flutter test` is also in the gate" — stopped being true when CI became the gate that matters.
- **Directories discovered by convention.** None of the three is named in `dart_test.yaml` or anywhere else. A new `test/<something>/` inherits the same invisibility silently.

**Why it happens:**
CI authored in an environment with no runner is unverifiable by construction, and the honest header makes it *feel* handled. Meanwhile the local `dart test` command is scoped by an explicit directory list, which makes "is my test in a gate?" a question nobody thinks to ask.

**How to avoid:**
- **Run the workflow before trusting it**, via `workflow_dispatch` (already present in the file for exactly this reason). Treat the first run as the verification and budget for fixing it there.
- Add the `flutter test` job. One edit closes DW-29, DW-51 and DW-74.
- Add a **meta-test**: enumerate directories under `test/` and fail if any is not covered by a named gate command. That converts "discovered by convention" into "discovered by a red build" and is the only fix that survives the next new directory.
- Provision the sidecar in CI, as the workflow already does — without it all five fake-CLI rows skip, and `dart test` reports a skip as green.

**Warning signs:**
- A workflow file with no run history.
- A test directory that appears in no config file.
- A green suite whose skip count is nonzero and unexamined. **Skips are the silent version of this pitfall** and this repo runs at 2 skips today.

**Detectability:** **Test** (a meta-test over the directory listing) for the coverage gap. The workflow's own correctness is only observable by running it — which is Hardware in the specific sense that it needs a GitHub runner this container does not have.

**Phase to address:** P-GATE. This must be **first**, because every later phase's evidence is only as good as the gate that produced it.

---

### Pitfall 15: Mutation-verification claims drawn from an unsound gate

**What goes wrong:**
Two suites bind **process-scoped** resources whose release is not synchronous with suite teardown — `single_instance_lock.dart:103` binds an abstract-namespace socket, and the portal suite stands up an in-process `DBusServer` on a unix path. The next suite in the same process can start before the kernel has freed them. `concurrency: 1` removed the overlap but **not the flake** (DW-46): one observed sequence gave a failure in run 1, a *different* failure in run 2, and a clean run 3.

The operational consequence is the durable part and it is the reason this belongs among critical pitfalls: **a false red reads as a killed mutation.** Any claim of the form "I deleted the guard and the suite went red, therefore the test is not vacuous" is unsound when drawn from a single full-suite run. A hardening milestone whose entire evidence model is "the ledger entry is closed because a mutation killed a test" is built on that claim, hundreds of times.

**Why it happens:**
More serialisation is the intuitive fix and it *looks* like it worked — DW-15 asserted the flakes were retired and the assertion was false as written. Flakes that appear at ~1-in-3 and then do not reproduce (the 2026-08-14 sweep measured three clean runs) invite the conclusion that they are gone.

**How to avoid:**
- Fix the **shape**, not the symptom: a teardown that waits for the resource to actually be released, or collapse both socket-binding suites into one file. `concurrency: 1` stays for its own stated reason, not this one.
- Until then, run every mutation check against a **scoped** command that touches neither resource (story 9 used `flutter test test/ui`; the DW-36 work used the scoped panel suite). Scoped, not full-suite, is the rule.
- **Verify the baseline is zero before counting failures.** Repo-specific and non-obvious: under `zsh`, an unquoted `$SCOPE` variable is not word-split, so a gate that interpolates a multi-directory scope silently runs nothing and every mutation reports the same fabricated count. Always confirm the unmutated baseline fails 0 rows before believing a mutation killed N.
- **Serialise mutation-running review layers.** Two reviewers mutating one working tree collide; re-verify counts serially.
- Back up the working tree to scratch before any mutation gate — `git checkout --` during a gate discards the very patch under review.
- Never quote DW-46's failure rate as a fact. The structural cause is verified; the rate is not.

**Warning signs:**
- Two consecutive full-suite runs failing in *different* files.
- A mutation gate reporting an identical failure count for every distinct mutation.
- A ledger `resolution:` citing a full-suite mutation run.

**Detectability:** **Test** — run the scoped command three times and compare. This is cheap and nobody does it.

**Phase to address:** P-GATE, alongside Pitfall 14.

---

### Pitfall 16: Closing a ledger entry with a fix whose test would not notice its removal

**What goes wrong:**
The specific hardening-milestone failure mode. An entry is closed, the code changed, a row added, the suite green — and the row asserts something the fix did not cause. DW-36's own resolution documents a caught instance: an earlier revision's throwing-logger row asserted only that nothing escaped, and **stayed green when the `onDone` arm was deleted outright.** The entry would have been closed with the defect intact and the ledger would then actively lie, because a `status: done` is trusted more than an `open`.

A related shape: DW-63 records two entries that stated test counts *already wrong when written*, and DW-51's resolution notes its own quoted count is stale. Numbers in a ledger rot faster than prose.

**Why it happens:**
Append-only ledgers make closure feel expensive and therefore final; the incentive is to close. And "the suite is green after my fix" is evidence for the wrong proposition — it shows the fix broke nothing, not that anything observes it.

**How to avoid:**
- **Every closure carries a negative control**: delete the fix, show the named rows go red, restore. Record which rows and how many. This repo's best resolutions already do this (DW-36 lists three mutations and their failure counts); make it the standard, not the exception.
- Run the negative control against the **scoped** suite (Pitfall 15), and confirm the baseline is 0.
- **Assert consequences, not artifacts.** `attempts` on the throwing logger, not "nothing escaped". The plan, not the index's existence. The exit, not the teardown order.
- Do not put counts in ledger prose. Reference the file; let the reader run it.
- Re-verify every `open` entry against current code before promoting it to a requirement — PROJECT.md already commits to this, and DW-84, DW-51 and DW-27 are all entries that later work made stale or contingent. Note especially the **contingent** closures: DW-84 is closed *contingent on DW-68*, DW-51 *contingent on DW-29*, DW-27 *contingent on there being no second focusable window*. If the entry they depend on is descoped, they silently un-close and nobody is told.

**Warning signs:**
- A `resolution:` with no mutation evidence.
- A test whose assertion names an implementation detail rather than a behaviour.
- Two entries closed by one change with only one of them verified.
- The `status: done` count rising faster than the row count.

**Detectability:** **Test** — the negative control *is* the test. There is no other way to know.

**Phase to address:** P-GATE establishes the discipline; every phase applies it.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems — scored for *this* milestone.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Ship the permissions fix on the create path only | One-line change, green test | Every existing user's plaintext stays world-readable forever; the gap is invisible because the test only creates fresh files | **Never** — pair with repair-on-open in the same change |
| Bump `schemaVersion` before dumping the v1 snapshot | Lets the index fix land first | The v1 baseline is destroyed permanently; no migration from the schema every field user has can ever be verified | **Never** — this is the one truly irreversible ordering in the milestone |
| Parse the portal's `trigger_description` back into a binding | The settings screen finally shows a combination on Wayland | Silently wrong on translated desktops and on any backend that words it differently; fails as a wrong answer, not an error | **Never** — render as prose (DW-66's decision) |
| Fix panel-visibility items one entry at a time | Small, reviewable diffs | Three to five separate passes over the most fragile file in the tree, each invalidating the previous pass's mutation verification | Only if each pass re-runs the *whole* scoped panel suite's mutation set |
| Keep `concurrency: 1` as the flake answer | Costs nothing, already in place | Every mutation claim in the milestone rests on a gate that can produce a false red | Acceptable **only** while all mutation checks run scoped (state it in the plan) |
| Close a ledger entry contingent on another entry | Retires two entries for one decision | If the depended-on entry is descoped, the contingent one silently un-closes with nothing to notice | Acceptable if the dependency is recorded on *both* entries and the sweep re-checks contingencies |
| Widen `CorrectionRepository` twice (prune now, delete later) | Each change is smaller | Two human-gated decisions against a frozen port declaration where one would do | **Never** — decide retention and deletion together |
| Keep `SqliteException` crossing the port boundary | Matches the spec's own I/O matrix; no new domain type | Any caller distinguishing disk-full from constraint-violation must import drift; swapping the storage engine becomes a breaking change for the application layer (DW-111) | Acceptable while nothing above the port branches on the exception — check that assumption before adding retention error handling |
| Skip the process-level "does it exit" test because the unit tests all close explicitly | No new harness | The only failure mode that matters (a daemon that survives `systemctl stop`) is the one nothing observes | **Never** — the headless `dart run` reproduction takes seconds |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `xdg-desktop-portal` GlobalShortcuts | Treating "no exception" as "bound" | Enumerate four outcomes: no portal, no GlobalShortcuts backend (wlroots ships none), refused app id, and **accepted-with-empty-shortcuts-list**. The last is a success response and reaches production. |
| `xdg-desktop-portal` ≥ 1.21 | Assuming the app id is optional for a non-sandboxed app | Call `Registry.Register(app_id)` with a reverse-DNS id backed by an **installed** `.desktop` file, or GNOME's backend refuses. Pre-1.20 portals have no `Registry` at all — detect, do not assume. |
| Portal permission store | Retrying after a user dismissed the dialog | A dismissal persists. Retrying gets the same silent refusal forever. Detect and tell the user the store must be cleared. |
| `keybinder-3.0` via `hotkey_manager` | Trusting the plugin's `true` | The `gboolean` is discarded at `hotkey_manager_linux_plugin.cc:96`. Go direct via `dart:ffi`, marshalled onto the GTK main thread with `g_idle_add`, results returned through `NativeCallable.listener`. |
| Any Flutter platform plugin | Assuming the Dart return reflects the native return | Read the plugin's `.cc`. This repo has found the same discarded-result defect in `keybinder_bind` **and** `tray_manager`'s `set_icon`. Audit the rest. |
| `tray_manager` teardown | Assuming `destroy` destroys | `tray_manager_plugin.cc:106-111` only sets `app_indicator_set_status(PASSIVE)` and leaves the static indicator non-null, so a late `setIcon` re-shows the icon **after** teardown with nothing left to undo it. |
| `window_manager` / GTK3 | `focus()` means focus | `gtk_window_present` calls `gtk_widget_show()` on a hidden window. Gate every mapping call on the visibility mirror. |
| Drift + `NativeDatabase.createInBackground` | Assuming the isolate dies with `main` | It does not. `await close()` from the composition root, or the daemon never exits. |
| SQLite file creation | Relying on umask | Mode is 0644 masked by umask; `-wal`/`-shm` inherit the main file's mode. Restrict the **directory** (0700) as the primary lever, since `dart:io` has no `chmod`. |
| `setsid` + Python sidecar spawning a CLI | `Process.kill(pid)` | `dart:io` cannot signal a group. Spawn under `setsid`, signal the **negated pgid**, SIGTERM → grace → SIGKILL, and never signal after reap (recycled pgid). |
| D-Bus session bus | Holding a `DBusClient` for the process lifetime | The client goes stale when the session bus dies (logout, session restart) and the hotkey then fails silently with no reconnection. Detect the disconnect and *say so*; a daemon that must be restarted should say it must be restarted. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `ORDER BY created_at DESC, id DESC` over an index on `created_at` alone | Nothing, until the table is large; then `recent()` slows on a path that must finish inside CAP-1's budget | Index `(created_at, id)`; assert the plan with `EXPLAIN QUERY PLAN` and fail on `TEMP B-TREE` | Low tens of thousands of rows; sooner on spinning disks or an encrypted home |
| Unbounded history growth | The database file grows monotonically; queries and backups slow together | Retention policy + prune on open; `VACUUM` (or `auto_vacuum` at creation) if deletion must reclaim space | One row per correction, all day, every day — years, but the privacy cost lands immediately |
| `LIMIT`/`OFFSET` pagination | Later pages get progressively slower even with a correct index | Keyset pagination on `(created_at, id)`: `WHERE (created_at, id) < (?, ?)` | O(offset) regardless of index; visible past a few thousand rows |
| Serialized panel-visibility queue | A single hung platform call parks the whole chain; every subsequent hotkey press waits out `_requestTimeout` | Bounded per-request timeout (accepted trade-off: reordering costs one press, parking costs every press until restart) | Any slow or wedged window manager — user-visible immediately |
| Startup work on the database open path | The three P-DATA fixes (permissions repair, `quick_check`, prune) each add a startup pass | Do them as **one** pass in one open path, and keep `quick_check` (not `integrity_check`) on the hot path | Noticeable once the file is large; `integrity_check` walks the whole file |
| 60s correction timeout with no feedback | User waits a full minute in silence, then sees a timeout | Progress indication and a cancel affordance; the timeout is already configurable but not adaptive | Slow model or slow network — routine, not exceptional |

## Security Mistakes

Domain-specific — this daemon's threat model is *local*, not network.

| Mistake | Risk | Prevention |
|---------|------|------------|
| `history.sqlite` at 0644 | Every local account reads the verbatim plaintext of everything the user has corrected. For a clipboard-driven tool that routinely includes private messages, tokens and credentials | 0700 data directory **and** 0600 file, created restricted **and** repaired on open; cover `-wal` and `-shm` |
| Retention with no deletion | A user who pastes a secret has no recourse; it is retained for the whole window with no way to remove it | Ship automatic retention *and* a user-initiated delete in the same port widening |
| `DELETE` treated as erasure | Rows are unlinked but pages remain readable in the file | `VACUUM` after bulk delete, or `auto_vacuum` set at creation (it cannot be enabled later without a vacuum) |
| Correction text reaching logs | Privacy constraint says input text and suggestion bodies are never logged — but new error paths are exactly where it leaks back in | Every new log line on a correction path is reviewed for payload; assert it with a test that fails if the input string appears in captured log output |
| Sidecar spawned with the inherited environment | The sidecar receives every environment variable the daemon holds, including any provider credentials, with no seam to scope them | An explicit environment seam on the spawn — which also closes the fake-vs-real test join gap (DW-93) |
| Config file permissions | Provider settings (and any key added by DW-115's second provider) sit next to the history in the same directory | The 0700 directory covers both — which is the argument for making the directory the primary lever |
| Portal permission granted once, silently | The user grants a global shortcut and has no in-app reminder that the compositor can see the trigger | Not a vulnerability, but state the grant on the settings surface so revocation is discoverable |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Showing a hotkey that is not bound | The user rebinds, sees the new combination, presses it, nothing happens — and concludes the app is broken rather than that the binding failed | Never render a requested combination as a fact; on Wayland render the desktop's own wording, on X11 render the grab's actual result |
| A tray daemon with no Quit | The one surface guaranteed to be present offers no way out; the user's only option is `kill` or logout (DW-114) | Quit in the tray menu, running the same ordered teardown as a signal |
| Silent degradation | On a wlroots compositor the daemon runs, consumes ~96 MB, and answers nothing, with no statement anywhere | Degrade *visibly* through the tray — the surface that still works when the hotkey does not |
| Panel with no geometry | CAP-10's "readable at the same time" is verified only at a size the *test* chose; the real window could be 200px tall with the first variant clipped away (DW-50) | Fixed size on every summon, remembered position, minimum size tied to the text scale |
| Panel dismissing itself on summon | The product's core gesture becomes a coin flip on any WM with focus-stealing prevention | Require an observed `focus` before a `blur` may hide |
| Two overlapping copies | The panel shows the newest copy's verdict over a clipboard that may hold the *other* variant — the user pastes the wrong text and the UI said it was fine | Serialise `writeText` in the controller so the last press is the last write applied; keep every variant copyable |
| A successful copy that renders nothing | A working clipboard and a hung write look identical (DW-59) | Acknowledge the copy |
| Digit keys as the only selection route | A pointer user cannot select a variant at all, and on a non-QWERTY layout the `1`/`2`/`3` hint names keys that select nothing (DW-52, DW-57) | Pointer affordance plus physical-key handling |
| Restart-only recovery | DBus dies, portal vanishes, database corrupts — the app becomes unresponsive with no explanation and the user just closes it | Every recover-by-restart path must *say* that a restart is needed, on the tray |

## "Looks Done But Isn't" Checklist

- [ ] **File permissions:** often missing the repair path for existing files, and the `-wal`/`-shm` siblings — verify with a test that pre-creates a 0644 file, and check all three modes after a write
- [ ] **Corruption recovery:** often missing the *truncated* case (the commonest real shape) — verify by cutting the file to N bytes and reopening, then by a zero-byte file and by random bytes
- [ ] **Schema migration:** often missing the committed v1 snapshot — verify `drift_schemas/` exists and holds a file *per* shipped version, and that a `schemaVersion` bump without one fails the gate
- [ ] **Index fix:** often missing the plan assertion — verify `EXPLAIN QUERY PLAN` for `recent()` contains no `TEMP B-TREE`, not merely that the index exists
- [ ] **Retention:** often missing the manual delete and the space reclamation — verify the port can express both, and that the file shrinks
- [ ] **Grab failure reporting:** often missing the *refused-by-another-client* path because it cannot be reached in a container — verify the FFI seam maps a `FALSE` return to `HotkeyUnavailable` against a fake lookup, and put the real refusal on the hardware checklist
- [ ] **Missing shared library:** often missing because the dev container has it installed — verify with `objdump -p` on the built bundle, and by pointing `DynamicLibrary.open` at a nonexistent soname
- [ ] **Portal degradation:** often missing the accepted-but-empty-shortcuts-list case — verify all four outcomes have a row, not just the throwing one
- [ ] **Subprocess teardown:** often missing the grandchild — verify with a fake sidecar that spawns its own sleeping child, and assert the grandchild's pid is gone after cancel
- [ ] **Daemon exit:** often missing because every test closes explicitly — verify by spawning the process, sending SIGTERM, and asserting exit within a bound
- [ ] **`onDone` backstops:** often missing the affordance to close a source without disposing the consumer — verify each arm with a negative control that deletes it
- [ ] **CI:** often missing an actual run — verify via `workflow_dispatch` before trusting any claim in the file, and check the skip count is examined, not just the pass count
- [ ] **Every ledger closure:** often missing the negative control — verify the named rows go red when the fix is removed, from a scoped run, against a baseline confirmed at 0 failures

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| v1 schema snapshot lost (`schemaVersion` bumped first) | **HIGH — partially unrecoverable** | Reconstruct a v1 schema by hand from `history.drift`'s git history into `drift_schemas/`, and label it clearly as reconstructed rather than dumped. It will verify the migration but cannot prove it matches what shipped |
| Plaintext history already readable in the field | MEDIUM | Repair-on-open tightens the mode at next start; the exposure window cannot be undone. Do not describe the fix as if it were retroactive |
| Ledger entry closed on a vacuous test | MEDIUM | The negative control is the detector *and* the remedy — run it across already-closed entries in this milestone's scope, not only new ones. A `status: done` with no mutation evidence is a candidate |
| Contingent closure orphaned by a descoped dependency | LOW | Re-check every `contingent on DW-n` at each sweep; if the dependency left scope, flip the dependent back to `open` with a note |
| FFI registrar destabilises the GTK main thread | HIGH | Keep `HotkeyManagerRegistrar` in the tree behind the same `HotkeyRegistrar` port until the FFI version has been observed on a real X session. AD-9 confines the choice to one file, which makes the fallback a one-line composition-root change |
| Corrupt database in the field with no recovery shipped | MEDIUM | User-side: rename the file aside; the daemon recreates. This is the argument for quarantine-and-recreate as the default policy — it makes the recovery automatic instead of a support instruction |
| Orphaned sidecar processes accumulating | LOW | Users can `pkill`; the daemon should not need them to. Fix the group kill, then verify with the grandchild row |
| First CI run red for CI reasons | LOW | Expected. The workflow already says so. Run it early via `workflow_dispatch` so it is not discovered while blocking a merge |

## Pitfall-to-Phase Mapping

| # | Pitfall | Prevention Phase | Verification |
|---|---------|------------------|--------------|
| 14 | CI never executed; test dirs in no gate | **P-GATE** | A completed `workflow_dispatch` run; a meta-test failing on any uncovered `test/` directory |
| 15 | Unsound mutation gate | **P-GATE** | Three consecutive scoped runs clean; baseline failure count confirmed 0 before any mutation claim |
| 16 | Closure on a vacuous test | **P-GATE** (discipline) + every phase | Every `resolution:` names the mutation, the scoped command, and the row count that changed |
| 4 | `schemaVersion` bumped before the v1 dump | **P-DATA** (first) | `drift_schemas/` holds a v1 file, committed *before* any schema edit; gate fails on a bump without a new snapshot |
| 5 | Permissions fixed only for new files | **P-DATA** | Test over a pre-existing 0644 file; modes asserted on `.sqlite`, `-wal`, `-shm` and the directory |
| 6 | No corruption recovery / wrong recovery | **P-DATA** | Truncated, zero-byte, random-bytes and wrong-schema files each open successfully with the daemon started |
| 7 | Unbounded growth, no delete | **P-DATA** | Port expresses prune and delete; file size shrinks after bulk delete |
| 8 | Index does not cover the tie-break | **P-DATA** (after #4) | `EXPLAIN QUERY PLAN` asserts no `TEMP B-TREE` for `recent()` |
| 1 | Requested binding shown as effective | **P-HOTKEY** | Settings renders portal prose sourced from bind reply, `ListShortcuts` **and** `ShortcutsChanged`; no parse of a portal string exists in `lib/` |
| 2 | Silent degradation when the portal is absent | **P-HOTKEY** | Four distinct outcome values, one row each, including accepted-with-empty-list; tray states the reason |
| 3 | Failed grab reports success | **P-HOTKEY** | FFI seam maps `FALSE` → `HotkeyUnavailable`; missing soname is caught, not fatal; real refusal on the hardware checklist |
| 11 | `gtk_window_present` re-maps a hidden window | **P-PANEL** | Every mapping call gated on the mirror; `hidden_window_test.dart` allowlist widened only with written justification |
| 12 | Blur without prior focus dismisses the panel | **P-PANEL** | Bare `blur` with no preceding `focus` is a no-op; toggle-hotkey transition table written down |
| 13 | `onError`-only backstop on a completable stream | **P-PANEL** (sweep) | Every `onError:` in `lib/` has a sibling `onDone:`; each arm has a negative control |
| 9 | Daemon that cannot exit | **P-EXIT** | Spawn-and-SIGTERM test exits within bound; every teardown `await` carries a timeout; tray Quit reaches the same teardown |
| 10 | PID kill instead of process-group kill | **P-EXIT** | Fake sidecar spawns a grandchild; after cancel the grandchild is gone; no signal is sent after reap |
| — | New provider re-derives the sidecar's hard-won lifecycle | **P-PROVIDER** | The second provider reuses the spawn/teardown seam rather than copying it; the grandchild and reap rows run against both |

### Ordering constraints the roadmap must honour

1. **P-GATE before everything.** Every later phase's evidence is a mutation claim, and a mutation claim from an unverified gate is not evidence.
2. **Pitfall 4 (v1 snapshot) before Pitfall 8 (index) and before any retention schema change.** This is the only *irreversible* ordering in the milestone: the v1 baseline can be captured only while v1 is live.
3. **Pitfalls 5, 6 and 7 in one phase.** All three touch the database open path; three passes means three rounds of regression risk on the same code and one startup pass instead of three.
4. **All panel-visibility work in one phase.** DW-30, DW-31, DW-33, DW-36 and DW-50 all edit the 1292-line reconciliation module, and DW-50 turns `setSkipTaskbar` from a startup constant into a per-transition call. Scattering them means repeated passes over the most fragile file, each invalidating the last pass's mutation verification.
5. **Pitfall 3's FFI registrar wants a real X session.** If none is available, plan it as build-plus-owed-observation with the threading claims itemised on DW-9's checklist, and keep `HotkeyManagerRegistrar` in the tree as the one-line fallback.
6. **P-EXIT before P-PROVIDER.** A second provider inheriting an unbounded shutdown doubles the surface; fix the lifecycle first, then add the provider against a settled seam.

### Phases most likely to need deeper, phase-specific research

- **P-HOTKEY** — highest. The FFI/GDK threading model (`g_idle_add` + `NativeCallable.listener` across the Flutter UI isolate and the GTK main thread) is not something this file resolves, and the portal's per-backend behaviour differs on every desktop.
- **P-DATA** — moderate. The mechanics are settled; the *policies* (retention window, quarantine vs. refuse, whether deletion must reclaim space) are product decisions needing a human, not more research.
- **P-PANEL** — moderate, and specifically about GTK3/`window_manager` event ordering under real window managers, which no container can supply.
- **P-GATE, P-EXIT** — low. Standard patterns; the work is doing them, not learning them.

## Sources

**Verified against this repository (primary evidence — HIGH confidence).** `_bmad-output/implementation-artifacts/deferred-work.md` (DW-9, DW-12, DW-20, DW-26, DW-27, DW-29, DW-30, DW-31, DW-33, DW-36, DW-39, DW-40, DW-42, DW-43, DW-46, DW-50, DW-51, DW-52, DW-55, DW-57, DW-59, DW-63, DW-66, DW-74, DW-80, DW-81, DW-84, DW-88, DW-93, DW-98–DW-115); `lib/src/infrastructure/hotkey/x11_global_hotkey.dart`; `lib/src/infrastructure/hotkey/hotkey_manager_registrar.dart`; `lib/src/infrastructure/persistence/history.drift`; `lib/src/infrastructure/persistence/app_database.dart`; `lib/src/infrastructure/persistence/drift_correction_repository.dart`; `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart`; `.github/workflows/ci.yml`; `pubspec.yaml`.

**Upstream primary documentation (MEDIUM confidence — official docs, cross-checked against the above).**
- [org.freedesktop.portal.GlobalShortcuts](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html) — `preferred_trigger` is advisory; the reply carries `trigger_description`; one `BindShortcuts` per session; `ListShortcuts` semantics
- [XGrabKey(3)](https://www.x.org/releases/current/doc/man/man3/XGrabKey.3.xhtml) — `BadAccess` on a conflicting grab, delivered asynchronously
- [keybinder `libkeybinder/bind.c`](https://github.com/kupferlauncher/keybinder/blob/master/libkeybinder/bind.c) — `gdk_error_trap_pop` → `success = FALSE`; the result exists and is discarded one layer up
- [How To Corrupt An SQLite Database File](https://www.sqlite.org/howtocorrupt.html) — corruption causes and the non-repairability of in-place fixes
- [Gtk.Window.present (GTK3)](https://docs.gtk.org/gtk3/class.Window.html) — "If the window is hidden, this function calls `gtk_widget_show()` as well"
- [Gtk.Window.set_skip_taskbar_hint](https://docs.gtk.org/gtk3/method.Window.set_skip_taskbar_hint.html) / [set_skip_pager_hint](https://docs.gtk.org/gtk3/method.Window.set_skip_pager_hint.html)
- [Stream.listen — dart:async](https://api.dart.dev/stable/3.4.4/dart-async/Stream/listen.html) — `cancelOnError` defaults false; a null `onDone` means "nothing happens"
- [Drift: Testing migrations](https://drift.simonbinder.eu/migrations/tests/) and [Exporting schemas](https://drift.simonbinder.eu/migrations/exports/) — `schema dump` / `schema generate` / `schema steps`
- [dart-lang/sdk#22470 — Add support for killing a process group](https://github.com/dart-lang/sdk/issues/22470)

**Community / field reports (LOW–MEDIUM confidence — single-source, corroborated where marked).**
- [Wayland global shortcuts via the XDG GlobalShortcuts portal](https://github.com/aaddrick/claude-desktop-debian/blob/main/docs/learnings/wayland-global-shortcuts-portal.md) — wlroots ships no GlobalShortcuts backend (error 5 on niri); portal 1.21+ requires `Registry.Register`; GNOME requires reverse-DNS app id + installed `.desktop`; dismissed permissions persist
- [XDG Desktop Portal — ArchWiki](https://wiki.archlinux.org/title/XDG_Desktop_Portal) — backend inventory
- [autokey#1088 — XGrabKey passive grabs not released on restart](https://github.com/autokey/autokey/issues/1088)

**Explicitly corrected.** A search result asserting `CREATE INDEX ... INCLUDE (...)` for SQLite is **wrong** — `INCLUDE` is Postgres/SQL Server syntax and does not parse in SQLite. Recorded so it is not repeated downstream.

---
*Pitfalls research for: Linux tray-resident hotkey daemon (Flutter/GTK3, X11 + Wayland portal, subprocess sidecar, local SQLite plaintext history)*
*Researched: 2026-08-30*
