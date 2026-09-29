# Architecture Research

**Domain:** Linux tray-resident Flutter/Dart daemon — integrating a second provider adapter, port state contracts, subscription lifecycle, and fake/real contract tests into an existing frozen hexagonal architecture
**Researched:** 2026-08-30
**Confidence:** MEDIUM-HIGH (repo-grounded claims verified by direct file read; ecosystem claims cross-checked across two or more sources)

## Framing

The architecture is frozen and correct. Nothing below proposes a new paradigm, a new ring, or a
different dependency direction. Every recommendation is a **placement decision inside the existing
four rings**, answering one question: where does each of this milestone's four changes go, and what
has to land before the second provider adapter can be added safely.

Three things constrain every answer:

1. **`domain/` imports only `dart:*`** (AD-1). This kills whole classes of ecosystem answers
   before they are considered — `BehaviorSubject`, `ValueStream`, `ValueListenable` and every
   other packaged current-value-stream type is unavailable *in a port declaration*. The
   hand-rolled accessor-plus-stream pair is not a stylistic preference here, it is the only
   conformant shape.
2. **Several declarations are frozen verbatim** (AD-2's correction types, AD-9's hotkey types).
   Two of this milestone's changes want to touch one. Both are flagged as human-gated below and
   neither is assumed.
3. **AD-15 says a new provider must not require a change to `domain/`, `application/`, or `ui/`.**
   DW-115's ratified decisions (secret store, settings surface) each want one. The resolution is
   that those are *platform and presentation* seams, not provider seams — argued explicitly in
   Pattern 2 and Anti-Pattern 6 rather than waved past.

## Standard Architecture

### System Overview — the delta only

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ui/                                                                      │
│   settings/  ── provider picker + token field ── NEW SURFACE             │
│                 (writes through SettingsController, never touches a key) │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ state in / intents out
┌───────────────────────────────▼──────────────────────────────────────────┐
│ application/                                                             │
│   SettingsController   ── gains provider-selection mutation              │
│   CorrectionController ── unchanged call site; may gain a pair *source*  │
│                           instead of a pair (runtime swap — DECISION 3)  │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ ports only
┌───────────────────────────────▼──────────────────────────────────────────┐
│ domain/                                                                  │
│   correction/correction_provider.dart   FROZEN — unchanged               │
│   correction/correction_event.dart      FROZEN — 4 failure kinds fixed   │
│   hotkey/global_hotkey.dart             FROZEN — wants an accessor (D1)  │
│   secret/secret_store.dart              ★ NEW PORT (no frozen AD)        │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ implemented by
┌───────────────────────────────▼──────────────────────────────────────────┐
│ infrastructure/                                                          │
│   correction/                                                            │
│     provider_registry.dart      ── ★ +1 map entry, +1 collaborator       │
│     active_correction.dart      ── unchanged resolution rules            │
│     wire/register_tagged_stream_parser.dart  ── ★ hoisted, shared        │
│     wire/failure_mapping.dart                ── ★ shared taxonomy rules  │
│     claude_agent_sdk/           ── unchanged                             │
│     openai_compatible/          ── ★ NEW ADAPTER DIRECTORY               │
│   secret/dbus_secret_store.dart ── ★ NEW ADAPTER (org.freedesktop.secrets)│
│   system/daemon_lifecycle.dart  ── ★ gains HttpClient close step         │
└───────────────────────────────┬──────────────────────────────────────────┘
                                ▲
┌───────────────────────────────┴──────────────────────────────────────────┐
│ composition root (AD-17, four parts) — still the only selection site     │
│   main.dart  ── constructs HttpClient + SecretStore, owns their teardown │
│   daemon_startup.dart ── unchanged order (lock → config → hotkey → AD-5) │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ test/  ── the load-bearing new structure                                 │
│   contract/                                                              │
│     correction_provider_contract.dart  ★ one suite, run 3×               │
│       ├─ FakeCorrectionProvider                                          │
│       ├─ ClaudeAgentSdkCorrectionProvider  (over test/support/fake_claude_cli) │
│       └─ OpenAiCompatibleCorrectionProvider (over a loopback HTTP server) │
│     correction_repository_contract.dart ★ fake + drift (closes DW-103)   │
│     panel_visibility_contract.dart      ★ fake + window_manager adapter  │
│     global_hotkey_contract.dart         ★ fake + X11 + Wayland-over-portal-double │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Change in this milestone |
|-----------|----------------|--------------------------|
| `ProviderRegistry` | id → factory lookup (AD-15) | +1 entry; constructor gains `SecretStore` and an HTTP transport collaborator, exactly as it already takes `Logger`. **The factory typedef `Map<String, CorrectionProvider Function(ProviderConfig)>` does not change** — closures capture the collaborators. |
| `ActiveCorrection` | Resolves the single `(provider, preset)` pair | No rule change. Stays **synchronous** — see Pattern 2 for why credentials must not be read here. |
| `OpenAiCompatibleCorrectionProvider` | Second adapter: HTTP + SSE, adapter-private | New. Owns endpoint, headers, model id, token read, SSE decode, failure mapping. |
| `SecretStore` (port) | `read(account)` / `write(account, secret)` / `delete(account)` over an opaque string | New domain port. Not frozen by any AD, so it can be declared freely — and must be declared with the current-state discipline of Pattern 4 baked in from line one. |
| `DbusSecretStore` | `org.freedesktop.secrets` over the existing `package:dbus` | New. Absence of a secret service and a locked collection are **values, not throws** — AD-12's degradation shape applied to a new seam. |
| `wire/register_tagged_stream_parser.dart` | Pure-Dart tag → `SuggestionDelta` decode (AD-16) | Hoisted out of `claude_agent_sdk/` so adapter #2 reuses it rather than copying it. Still a per-adapter *choice* (AD-16), now a shared *tool*. |
| Contract suites (`test/contract/`) | The port's observable behaviour, run against every implementation | New. This is the single highest-leverage artifact in the milestone. |
| `DaemonLifecycle` | Ordered, bounded teardown | Gains a step for the HTTP client and (Decision 4) a bound on `CorrectionController.dispose()`. |

## Recommended Project Structure

```
lib/src/
├── domain/
│   └── secret/
│       └── secret_store.dart          # NEW port: opaque secrets by account key
├── infrastructure/
│   ├── correction/
│   │   ├── provider_registry.dart     # +1 entry, +2 constructor collaborators
│   │   ├── wire/                      # NEW: shared, transport-free decoding
│   │   │   ├── register_tagged_stream_parser.dart   # moved from claude_agent_sdk/
│   │   │   └── correction_failure_mapping.dart      # the taxonomy rules, one home
│   │   ├── claude_agent_sdk/          # unchanged; imports ../wire/
│   │   └── openai_compatible/         # NEW adapter directory
│   │       ├── openai_compatible_correction_provider.dart
│   │       ├── sse_line_decoder.dart  # SSE frames -> chunk objects, pure Dart
│   │       └── openai_wire.dart       # request/response shapes, adapter-private
│   └── secret/
│       └── dbus_secret_store.dart     # NEW adapter
└── ui/settings/                       # provider picker + token field
test/
├── contract/                          # NEW: port suites, parameterised by implementation
└── fakes/                             # every fake gains a close<Stream>() affordance
```

### Structure Rationale

- **`infrastructure/correction/wire/`** — AD-15 forbids naming a process, `Uri`, port, key, header
  or SDK type *outside* `infrastructure/correction/<provider>/`. A register-tag parser names none
  of those; it is pure text. Keeping it inside `claude_agent_sdk/` would force adapter #2 either to
  import across a sibling provider directory (which reads as coupling and will be copied instead)
  or to duplicate a 200-line parser with its own drift path. A neutral `wire/` peer directory keeps
  AD-15 literally true and gives the shared code an honest home.
- **`test/contract/` as a separate tree** — not under `test/infrastructure/`, because a contract
  suite is *the port's* test, not any implementation's. Placement signals ownership: when the port
  changes, this directory is what must change with it.
- **`domain/secret/` as its own port family** — not a member of `ConfigStore`. AD-13 makes
  `ConfigStore` the sole owner of the config *file*; a secret is deliberately not in that file
  (DW-115 decision (a)), so folding it in would make one port own two storage substrates with two
  failure modes and one `AppConfig` value type that must never serialize half of itself.

## Architectural Patterns

### Pattern 1: Second adapter = one file, one config entry, one map entry — and nothing else

**What:** AD-15 already prescribes the mechanism and the codebase already implements it: a
`Map<String, CorrectionProvider Function(ProviderConfig)>` in `ProviderRegistry`, a
`ProviderConfig.settings` map the owning adapter alone interprets, and `ActiveCorrection.resolve`
as the one selection site. The canonical literature agrees exactly: a port normally has several
adapters, and the mechanism that binds abstraction to implementation is dependency injection
performed once by a composition root.

**When to use:** Every provider, forever. If a provider cannot be added this way, the port is
wrong — not the caller (AD-15's own words).

**Trade-offs:** The registry's factories are *synchronous*, so anything a provider needs that
requires I/O to obtain (a credential, a probed endpoint capability) cannot be obtained at
construction. That is a feature — see Pattern 2 — but it means every such lookup is deferred into
`correct()` and every such failure is a `CorrectionFailed`, never a startup failure.

**Example — the shape that keeps the frozen typedef intact:**

```dart
ProviderRegistry({
  required Logger logger,
  required SecretStore secrets,        // NEW collaborator, same shape as logger
  required HttpTransport transport,    // NEW: composition-root-owned, closeable
}) : _factories = {
       ClaudeAgentSdkCorrectionProvider.providerId: (config) => /* unchanged */,
       OpenAiCompatibleCorrectionProvider.providerId: (config) =>
           OpenAiCompatibleCorrectionProvider(
             baseUrl: config.settings[OpenAiCompatibleCorrectionProvider.baseUrlKey]
                 ?? OpenAiCompatibleCorrectionProvider.defaultBaseUrl,
             secretAccount: config.settings[OpenAiCompatibleCorrectionProvider.accountKey] ?? '',
             secrets: secrets,          // captured, read lazily inside correct()
             transport: transport,
             logger: logger,
             timeout: _timeoutFrom(config, logger),
           ),
     };
```

Note what this preserves: the map value type is untouched, `create(id, config)` is untouched,
`ActiveCorrection` is untouched, and a missing setting still constructs a provider that reports
`providerUnavailable` on the first correction rather than blocking startup — the exact degradation
`ClaudeAgentSdkCorrectionProvider` already implements for a missing interpreter path.

### Pattern 2: Credentials are a platform port, read lazily inside the adapter

**What:** A `SecretStore` port in `domain/`, a D-Bus adapter in `infrastructure/`, injected into
the *registry* (not into `ActiveCorrection`, not into any controller), captured by the provider
factory closure, and **read inside `correct()` — not at construction.**

**When to use:** Any credential on Linux desktop. The freedesktop Secret Service spec makes the
reason concrete: items live in **collections that can be locked**, and unlocking may prompt the
user interactively. A credential read at startup therefore risks a modal prompt on a daemon whose
whole point is that it is already resident when the hotkey is pressed — and AD-13/AD-19 both say
startup never blocks on a provider being well-configured.

**Trade-offs:** One D-Bus round trip per correction. Measure it; if it is material, cache the
secret in the adapter for the process lifetime with an explicit invalidate on
`ConfigStore.changes`. **Do not cache it in `AppConfig`** — that value is written to a file the
app invites users to edit.

**The AD-15 tension, stated rather than dodged:** AD-15 says "if a new provider requires a change
to `domain/`, this is the wrong seam". Adding `SecretStore` *is* a `domain/` change. The
resolution: AD-15's rule is about the **provider contract** — nothing outside the adapter may name
a `Uri`, header, key or model id, and after this change nothing does. `SecretStore` is a *platform*
port in the same family as `ClipboardPort`, `TrayPort` and `ConfigStore`; it is provider-agnostic
by construction (its vocabulary is `account` and `secret`, never `openai` or `api key header`), and
a third provider needing a token adds zero further domain surface. That is the test to apply: **a
new port is legitimate when the second provider that needs it adds nothing.** Record the reasoning
in the port's doc comment; this codebase's convention is that a port explains why it exists.

**Failure shape:** no secret service on the bus, a locked collection the user declines to unlock,
and no stored item are all `CorrectionFailed(providerUnavailable, <sentence naming what to fix>)`.
Never a throw, never a startup abort, never a silent fall back to an unauthenticated request.

### Pattern 3: One failure taxonomy, two very different backends, published as a table

**What:** `CorrectionFailureKind` has exactly four members and is frozen inside AD-2's verbatim
block: `timeout`, `providerUnavailable`, `providerError`, `malformedResponse`. Adapter #2 gets no
new member. The uniformity problem is therefore entirely a **mapping** problem, and the fix is to
make the mapping an explicit, documented, tested artifact instead of a per-adapter judgement —
which is precisely what anti-corruption-layer practice prescribes (translate vendor codes into one
domain vocabulary *inside* the ACL, and test the translator's edge cases, because that is where
the bugs are).

**The recommended semantic axis** — chosen so a user reading the panel knows what to do, and so
both adapters answer the same question the same way:

| Kind | Means | Subprocess backend | HTTP backend |
|------|-------|--------------------|--------------|
| `providerUnavailable` | *The provider cannot serve at all until you change something.* | interpreter missing / not executable; spawn failed; `claude_agent_sdk` not importable | connection refused, DNS failure, TLS failure; 401 / 403; 404 on the model; no secret stored; no secret service; collection locked |
| `providerError` | *The provider was reached and failed this request. Retry is meaningful.* | non-zero exit with diagnostic output; sidecar `{"type":"error"}` frame | 429; 5xx; mid-stream SSE error payload; `finish_reason: "error"` |
| `timeout` | *The deadline elapsed.* | `_killGrace` / request deadline | request or inter-chunk deadline |
| `malformedResponse` | *Reached, answered, unintelligible.* | unparseable NDJSON; tags missing from the accumulated text | undecodable SSE frame; JSON that is not a chat chunk; tags missing from the accumulated text |

Existing behaviour already sits on this axis (AD-19: spawn failure → `providerUnavailable`;
non-zero exit or unparseable output → `providerError`), so adopting it is a codification, not a
change. AD-15 grants latitude here ("a missing executable, a refused connection, a 401 … are all
`providerUnavailable` or `providerError`"); this table spends the latitude once, in one place,
rather than twice in two adapters.

**The mid-stream trap, and it is the single most important HTTP finding:** once the server has sent
`200` and the SSE headers, a rate limit or upstream failure **does not arrive as an HTTP status**.
It arrives as an SSE payload carrying a top-level `error` object and `choices[0].finish_reason ==
"error"`. SDK-level retry logic is skipped entirely for stream reads — an adapter that only checks
`response.statusCode` will treat a rate-limited generation as a *successful, truncated* one, and
because `CorrectionCompleted` is authoritative over deltas (AD-3), the panel would render three
half-written suggestions and the history would persist `outcome: 'completed'`. The adapter must
inspect every chunk for `error` and for `finish_reason == "error"` and emit `CorrectionFailed`.

**Retry-After:** 429 responses carry `retry-after` / `retry-after-ms` and `x-ratelimit-*`. The
adapter must **not** implement retry or backoff — AGENTS.md §8 rules out fallback and cascade, and
CAP-13 makes Retry the user's action. Surface the wait in `CorrectionFailed.message` ("the
provider is rate limited; try again in 12 s") so the user's Retry is informed. This also matches
the wire reality: failover after streaming has begun is impossible, because partial content is
already committed.

**Local/compatible-server variance is a first-class hazard, not an edge case.** Ollama's `/v1`
endpoint has shipped builds where enabling tools silently collapses `stream=true` into a single
block; self-hosted servers have no rate limiter at all and fail by resource exhaustion rather than
429; JSON-schema `response_format` support varies per server. Two consequences: (1) keep AD-16's
register-tagged-lines wire format for adapter #2 rather than structured output — it degrades to a
single block gracefully (zero deltas, then `CorrectionCompleted`, which AD-16 explicitly permits)
where a schema-dependent adapter would break; (2) a server that streams nothing must still produce
one terminal event, which is a contract row, not a hope.

### Pattern 4: Current state and changes, as one port contract

**What:** The defect shape is a broadcast stream with no replay and no synchronous accessor. The
ecosystem's usual answer — RxDart's `BehaviorSubject`/`ValueStream`, which caches the latest value
and emits it to each new listener — **cannot be used in a port declaration here**, because
`domain/` imports only `dart:*`. The conformant shape is the one AD-8 already uses:

```dart
abstract interface class SomePort {
  /// Authority. Always current, never an IPC query, safe to read at any time.
  T get current;

  /// Notification only. Non-replaying broadcast. A consumer that missed events
  /// can always recover by reading [current].
  Stream<T> get changes;
}
```

**Three invariants that must be written on the port, because a doc comment is the only place they
can live:**

1. **Write-before-notify.** The accessor is updated to the new value *before* the corresponding
   event is emitted, so a listener reading `current` inside its own handler never sees an older
   value than the event it is handling.
2. **The accessor is authoritative; the stream is advisory.** Any consumer may be constructed at
   any time and be correct by reading `current` first, then subscribing. Correctness must never
   depend on a subscriber having existed since t=0.
3. **Transitions only.** A repeated identical state emits nothing, and the accessor still reads
   correctly. (`PanelVisibility.changes` already documents an asymmetric version of this and is
   the model to copy.)

**How it is tested — four rows, in the shared contract suite so every implementation faces them:**

| Row | Assertion |
|-----|-----------|
| Late subscriber | Mutate, *then* subscribe. `current` reflects the mutation; the stream delivers **no** replayed event. Both halves matter — asserting only the first would pass against a replaying implementation that would then double-apply. |
| Ordering | Inside a `changes` handler, `current == event`. |
| No-op suppression | Two identical states in a row emit once; `current` correct after both. |
| Resubscribe | Cancel, mutate, resubscribe: `current` is right, no backlog arrives. |

**Applied to `GlobalHotkey` — and this is Decision 1, human-gated.** `GlobalHotkey` declares
`Stream<HotkeyBindOutcome> get bindingChanges` and no accessor. `SettingsController` subscribes
eagerly at construction and holds the state in `SettingsState`, so the daemon is *currently*
correct by accident of wiring — verified by reading the constructor. The contract is nonetheless
broken in a way that bites the moment a second consumer appears, and one is already owed: AD-12's
tray half is unwired (`grep -rn setHotkeyUnavailable lib/` finds no caller). A tray consumer built
later, or a controller rebuilt after a config reload, reads nothing and renders stale. Adding
`HotkeyRegistration? get current` (or `HotkeyBindOutcome? get lastOutcome`) to AD-9's verbatim
block is the fix, and **it is a human-gated spine edit** — flagged, not assumed.

There is a precedent for how such a change has been handled here, and it is worth knowing before
the decision is made: `PanelVisibility.changes` already diverges from AD-8's snippet
(`Stream<bool>` in the spine, `Stream<PanelVisibilityState>` in the code), and the mechanism used
was a divergence note in the port's own doc comment plus an owed spine correction — the port file
says so in as many words. Neither `lib/` nor `test/` may edit the spine.

### Pattern 5: `onDone` is not optional on a long-lived port subscription, and teardown is bounded

**What:** Dart's `Stream.listen` takes `onError`, `onDone` and `cancelOnError`. An errored stream
leaves a log line and a live subscription; a **completed** stream leaves nothing at all, while the
consumer goes on looking healthy. For a resident daemon that is the worse failure by a wide margin,
and the project has already reasoned itself to this conclusion once (DW-36, closed) and then not
generalised it.

**Verified current state** (`grep -rn onDone lib/`, 2026-08-30): the arm exists at
`window_manager_panel_visibility.dart:207`, in three UI widgets, in the parser, in the sidecar
provider and in `single_instance_lock.dart`. It is **absent** at every remaining port-input seam:
`daemon_lifecycle.dart:136` (fed by `tray.panelRequests` *and* `lock.showRequests` — two
independently disposed objects, and the sharpest case, since that class's own doc says it cannot
see which implementation is behind the stream), `tray_manager_tray.dart:34`,
`x11_global_hotkey.dart:36`, `panel_controller.dart:20`, `correction_controller.dart:49`, and
`settings_controller.dart:56` and `:68`.

**The rule to adopt:** every subscription to a *port* stream that outlives one call guards both
arms; the `onDone` arm logs the **consequence**, not the event ("the tray request stream closed;
the tray menu can no longer open the panel"), because that is the whole difference from `onError`.
Log-only — no resubscribe, no retry, no dead-stream flag — matching the DW-36 resolution.

**How it is verified, and this is where it has failed before:** no existing suite can even reach
the case, because no fake can close its stream under a live consumer. Each fake needs the
`FakePanelWindow.closeEvents()` affordance — a method that closes the controller *without*
disposing the double. Then each arm gets a negative control: delete the arm, the row must fail.
The DW-36 resolution ran exactly this (three negative controls, scoped suite, reverted) and it is
the local standard; a row that stays green with the arm deleted is a row that tests nothing.

**Bounded teardown** is the same discipline pointed at shutdown. The established in-repo template
is `DaemonLifecycle`'s required `_stepTimeout` with `run().timeout(onTimeout: …)` reporting expiry
through a flag rather than by catching `TimeoutException` (so a `TimeoutException` thrown *by* the
step is not misread), plus `WindowManagerPanelVisibility`'s required `requestTimeout` — whose test
comment states the convention outright: **one policy, no site with a private default.** Two sites
violate it and both matter more once an HTTP adapter exists:

- `CorrectionController.dispose()` awaits `Future.wait(_pendingSaves)` **unbounded**. A rejecting
  save is survivable (fixed, pinned); a *hanging* one — a drift write on a background isolate
  against a locked database — leaves a daemon that cannot exit, contradicting that method's own
  doc ("a daemon that cannot exit is a worse failure than a lost history row").
- Nothing owns `AppDatabase`'s close, and `NativeDatabase.createInBackground`'s isolate outlives
  `main` — already proven by probe (a program that opens the DB, queries, and returns from `main`
  was killed at 30 s, exit 124).

**An HTTP adapter adds a third one of exactly this class.** A pooled `HttpClient` keeps
keep-alive sockets and therefore the isolate alive; it needs `close(force: true)`, which is the
HTTP analogue of AD-19's kill-the-process-*group* rule. And **`CorrectionProvider` has no
`dispose()`** — AD-2's frozen block is `correct()` and nothing else. Do not add one (that is a
frozen-declaration edit for no benefit). Instead the composition root constructs and owns the
client, hands it to `ProviderRegistry` as a collaborator, and closes it as a bounded
`DaemonLifecycle` step. This is Decision 2, and it is *not* human-gated: it needs no frozen edit.

### Pattern 6: Layered doubles — the fake and the real adapter face one suite, over a double one level down

**What:** A fake becomes trustworthy only when a suite runs against **both** the fake and the real
implementation, asserting the shared contract; without it, a diverged fake produces green tests and
broken production. This project has the pieces and not the assembly: `test/support/fake_claude_cli`,
`test/support/fake_global_shortcuts_portal.dart` and `test/fakes/fake_panel_window.dart` are
doubles *below* the adapter, which is the honest layer to cut at — it lets the real adapter's own
translation, queueing and failure mapping run for real. What is missing is the suite that both
sides face. `test/fakes_smoke_test.dart` is 53 lines and only proves the fakes *construct*.

**The shape:**

```dart
// test/contract/correction_provider_contract.dart
void correctionProviderContract({
  required String name,
  required Future<CorrectionProvider> Function() build,
  required Future<void> Function(ProviderScript script) arrange,
}) {
  group('CorrectionProvider contract: $name', () {
    test('AD-3: exactly one terminal event, then close', () { /* ... */ });
    test('AD-3: deltas are incremental fragments, never cumulative', () { /* ... */ });
    test('AD-3: no exception escapes correct()', () { /* ... */ });
    test('AD-3: CorrectionCompleted carries one Suggestion per register', () { /* ... */ });
    test('AD-4: cancelling the subscription emits nothing further', () { /* ... */ });
    test('AD-4: cancelling tears the backend down', () { /* ... */ });
    test('AD-16: a backend that streams nothing still terminates', () { /* ... */ });
    test('taxonomy: unreachable backend -> providerUnavailable', () { /* ... */ });
    test('taxonomy: reached-and-refused -> providerError', () { /* ... */ });
    test('taxonomy: reached-and-unintelligible -> malformedResponse', () { /* ... */ });
    test('deltas followed by failure is legal and terminal', () { /* ... */ });
  });
}
```

For adapter #2, the double one level down is a **loopback `HttpServer` on port 0** — no new
dependency, real sockets, real SSE framing, and it can script a mid-stream `error` chunk, a 429
with `retry-after`, a stall for the timeout row, and a truncated frame. That is the only way to
reach the mid-stream failure path at all.

**Keeping a fake honest about platform LAG.** The failure mode is a fake whose state is *true by
construction* while the real adapter's state is a *prediction reconciled later*. Verified example:
`WindowManagerPanelVisibility.show()` sets the mirror synchronously and *then* enqueues the real
request, which may be superseded by a later request, abandoned at disposal, or abandoned on its
own `requestTimeout` — and the window may later contradict the mirror through a window-driven
event. `FakePanelVisibility.show()` just calls `_emit(shown)`. The fake is honest about the
optimistic mirror and **structurally incapable of being wrong afterwards**, so no test written
against it can observe the reconciliation window that the real adapter's own port doc spends three
paragraphs describing ("a resolved future … does not mean the window moved").

Three rules that keep a fake honest about lag:

1. **Model the confirmation, don't skip it.** If the real backend confirms asynchronously, the
   double exposes an explicit `confirm()` / `deliverEvent()` / `settle()` the test must call. The
   default should be *unsettled*, so a test that forgets fails loudly rather than passing on an
   optimism the platform does not share.
2. **Give the double the ability to disagree.** `abandon()`, `supersede()`, `contradict(state)` —
   if the real adapter can end up with a mirror that was wrong, the fake must be able to reach that
   state too, or the whole class of bug is untestable.
3. **Put the lag rows in the contract suite, not in the adapter's own file.** The assertion "after
   `await show()` returns, the window may not have moved, and `changes` still reports the intent"
   is a statement about the *port*, and the fake must satisfy it identically.

DW-103 is the miniature version of the same failure and should be closed by the same mechanism:
`FakeCorrectionRepository.recent` is `saved.reversed.take(limit)` while `DriftCorrectionRepository`
orders by `created_at DESC, id DESC`, and the entire application layer is tested only against the
fake. One contract suite, two implementations, and the divergence becomes a failing test instead
of a ledger entry.

## Data Flow

### Correction with the HTTP adapter (new path, terminal-event view)

```
UI submit
   ↓
CorrectionController.onSubmitCorrection(text)      [captures submitted text — AD-18]
   ↓  CorrectionProvider.correct(text:, preset:)   [port; no Uri, no header, no key]
OpenAiCompatibleCorrectionProvider
   ├─ SecretStore.read(account)  ──── null / locked / no service ──► CorrectionFailed(providerUnavailable) ─┐
   ├─ POST {baseUrl}/chat/completions  stream:true                                                          │
   │     ├─ connect refused / 401 / 404 ─────────────────────────► CorrectionFailed(providerUnavailable) ───┤
   │     ├─ 429 / 5xx before headers ────────────────────────────► CorrectionFailed(providerError) ─────────┤
   │     └─ 200 + SSE
   │          ├─ chunk.delta.content ──► wire/RegisterTaggedStreamParser ──► SuggestionDelta* ──────────────┤
   │          ├─ chunk.error / finish_reason=="error" ───────────► CorrectionFailed(providerError) ─────────┤
   │          ├─ undecodable frame ──────────────────────────────► CorrectionFailed(malformedResponse) ─────┤
   │          ├─ inter-chunk deadline ───────────────────────────► CorrectionFailed(timeout) ───────────────┤
   │          └─ [DONE] ──► parser recovers 3 tags? yes ─────────► CorrectionCompleted ──────────┐          │
   │                                        no ─────────────────► CorrectionFailed(malformed) ──┤          │
   └─ subscription cancelled (Retry / new correction / shutdown)                                 │          │
        └─ abort request, no further events (AD-4)                                               ▼          ▼
                                                       CorrectionController → CorrectionRepository.save(record)
                                                       exactly once, one transaction, regardless of visibility
```

Every arm ends in **exactly one** terminal event and then closes — the same invariant the sidecar
adapter satisfies, reached through completely different mechanics. That equivalence is what the
contract suite exists to prove.

### Provider selection and the runtime-swap question

```
Settings screen                      SettingsController                ConfigStore            composition root
  pick provider  ──────────────────►  writeThrough(AppConfig')  ─────►  persist  ──changes──►  ??? re-resolve ???
  enter token    ──────────────────►  SecretStore.write(account, token)   (token never enters AppConfig)
```

Today `ActiveCorrection.resolve` runs **once**, in `daemon_startup.dart`, and
`CorrectionController` holds the resolved pair as a constructor field. A provider changed in
settings therefore takes effect **at next launch**. CAP-8's wording is "without touching application
code", not "without restarting" — so restart-required is defensible — but the settings screen must
then say so, or the user will believe the switch took. This is Decision 3.

- **Option A (restart-required).** Zero structural change; settings shows "takes effect on next
  start". Honest, cheap, slightly disappointing.
- **Option B (composition-root re-resolution).** The composition root subscribes to
  `ConfigStore.changes`, re-runs `ActiveCorrection.resolve`, and hands the new pair to
  `CorrectionController` through a small source seam. **Selection stays at the composition root, so
  AD-5 holds** — the "no runtime provider selection" anti-pattern forbids a `switch (providerId)`
  in the pipeline, not a re-run of the one resolution site. It touches `CorrectionController`'s
  constructor (application ring — *not* verbatim-frozen; the spine fixes port declarations, not
  controller signatures) and must carry one hard rule: **the pair is re-read at the start of each
  correction and never swapped mid-stream.**

Recommended: **Option B**, because DW-115's ratified decision (c) puts the provider picker on the
settings screen and a picker whose effect is invisible until relaunch is the kind of thing that
gets filed as a bug. But it is a real design change, not a wiring tweak, and it should be planned
as its own phase rather than smuggled into the adapter phase.

## Build Order

The dependency structure is the actionable output. Read it as: nothing to the right can be verified
without what is to its left.

```
[1] Contract-suite harness ──┬─► [2] Subscription lifecycle rule (onDone at 7 sites)
    + fake lag honesty       │        + fake close<Stream>() affordances
    + DW-103 closure         │
                             ├─► [3] Bounded-teardown policy (one injected bound;
                             │        CorrectionController.dispose, AppDatabase, HttpClient)
                             │
                             └─► [4] Port state-shape rule (accessor + changes)
                                      ├─ applied to the NEW SecretStore port (free)
                                      └─ applied to GlobalHotkey  ★ HUMAN-GATED (AD-9 verbatim)
                                                  │
                             ┌────────────────────┘
                             ▼
                       [5] SecretStore port + DbusSecretStore adapter
                             │
                             ▼
                       [6] OpenAiCompatibleCorrectionProvider
                           (+ wire/ hoist, + failure-mapping table, + loopback contract run)
                             │
                             ▼
                       [7] Settings surface (provider picker + token)
                             │
                             ▼
                       [8] Runtime re-resolution  ★ DECISION 3 (Option A ends here)
```

| # | Must land before adapter #2? | Why |
|---|------------------------------|-----|
| 1 Contract suite | **Yes** | Adapter #2's only claim to correctness is "it behaves like the port says". Without a suite the claim is untestable, and the sidecar adapter's behaviour becomes the de facto spec by accident. Building it *after* adapter #2 means writing the port's rules while looking at two implementations, which is how a contract gets weakened to fit what exists. |
| 2 `onDone` rule | **Yes** | An HTTP stream has more ways to end silently than a subprocess does (server closes the connection, proxy idle-timeout, keep-alive reap) and the parser/consumer chain is the same one that already lacks the arm. Adopting the rule after the adapter means retrofitting it under a live second consumer. |
| 3 Bounded teardown | **Yes** | A pooled `HttpClient` is a new isolate-alive resource of exactly the class that already produced two open ledger entries. Land the policy and the ownership convention first; then the adapter's close is one more step in an existing bounded sequence rather than a new invention. |
| 4 Port state shape | **Partly** | The *rule* must exist before the `SecretStore` port is declared, or the new port repeats the defect for free. Applying it to `GlobalHotkey` is independent of provider work and can be sequenced whenever the human gate clears. |
| 5 SecretStore | **Yes** | DW-115 decision (a): the token never enters `config.json`. Adapter #2 has nowhere to read a credential from until this exists — and a temporary "read it from settings for now" is exactly the shortcut that survives to production. |
| 6 Adapter #2 | — | One file, one config entry, one map entry, and a third run of suite [1]. |
| 7 Settings surface | After 6 | It must render something selectable. |
| 8 Runtime re-resolution | After 7 | Only observable once there are two providers and a picker. |

**Phases likely to need their own deeper research:** [6] (per-server compatibility variance across
OpenAI / OpenRouter / Groq / Together / Ollama / LM Studio — the "OpenAI-compatible" label hides
real divergence in streaming, error framing and structured-output support) and [5] (Secret Service
behaviour across gnome-keyring vs KWallet vs no service, and inside a Flatpak sandbox, which also
changes the AD-11 portal handshake). Phases [1]–[4] are standard patterns applied to a codebase
that already contains its own precedents; they need discipline, not research.

## Anti-Patterns

### Anti-Pattern 1: A `switch (providerId)` anywhere below the composition root
**What people do:** Branch on the active provider in the controller, the parser, or the settings
controller — "just for the token field".
**Why it's wrong:** Re-opens the seam AD-5 closed; the settings screen is the sneakiest site
because a provider-specific field feels like presentation.
**Instead:** The settings screen renders a *list of described providers* from config and a generic
credential field; which keys a provider needs is the adapter's business, surfaced as
`CorrectionFailed(providerUnavailable, "…")` when unset, not as a UI branch.

### Anti-Pattern 2: A replaying stream in a port declaration
**What people do:** Reach for `BehaviorSubject` / `ValueStream` to fix the late-subscriber bug.
**Why it's wrong:** `domain/` imports only `dart:*` (AD-1) — the analyzer test fails the merge. And
a replaying stream makes "did I already handle this?" ambiguous for every consumer.
**Instead:** Synchronous accessor + non-replaying `changes`, with write-before-notify documented on
the port. If a *consumer* wants replay semantics, it composes them in `application/`.

### Anti-Pattern 3: Silent stream completion
**What people do:** `stream.listen(handler, onError: log)` on a long-lived port stream.
**Why it's wrong:** Completion retires a capability with zero evidence — a completed
`panelRequests` retires AD-12's tray fallback; a completed `activations` retires CAP-1 for the
session — and the component keeps reporting healthy.
**Instead:** Both arms; the `onDone` message names the consequence; a negative control proves the
arm is load-bearing.

### Anti-Pattern 4: A fake that cannot be wrong
**What people do:** Fake settles state synchronously in the method the real adapter merely
*queues*, so every test observes a world the platform never produces.
**Why it's wrong:** Green tests, broken daemon — and worse, the bugs it hides are exactly the
reconciliation bugs that make X11/Wayland adapters hard.
**Instead:** Default-unsettled doubles with explicit `confirm()`/`abandon()`/`contradict()`, and
lag rows living in the shared contract suite.

### Anti-Pattern 5: Retry, backoff, or fallback inside a provider adapter
**What people do:** Handle 429 by sleeping `retry-after` and re-issuing; or fall back to the other
provider when one fails.
**Why it's wrong:** AGENTS.md §8 rules out fallback and cascade; AD-3 permits exactly one terminal
event; and after streaming has begun failover is *physically* impossible because partial content is
already committed. A hidden retry also silently multiplies the CAP-1 latency budget.
**Instead:** One attempt, one terminal event, the wait time in the message, and CAP-13's Retry
button as the only retry mechanism.

### Anti-Pattern 6: Widening `AppConfig` or `ConfigStore` to hold the token
**What people do:** `ProviderConfig.settings['api_key']`.
**Why it's wrong:** `config.json` is a file the app invites the user to open and edit, world-
readable under a default umask, and the same milestone is fixing history-file permissions for
exactly this reason.
**Instead:** A separate `SecretStore` port. The config holds an *account name*; the secret store
holds the secret.

### Anti-Pattern 7: Reading the credential at startup
**What people do:** Resolve the token in `ActiveCorrection.resolve` so the provider is "fully
constructed".
**Why it's wrong:** Makes `resolve` async, drags a D-Bus round trip into the startup order, and can
raise an interactive keyring-unlock prompt before the daemon is resident — against AD-13's and
AD-19's rule that a badly configured provider never blocks startup.
**Instead:** Capture the port, read inside `correct()`, degrade to `providerUnavailable`.

## Integration Points

### External Services

| Service | Integration Pattern | Notes / gotchas |
|---------|---------------------|-----------------|
| OpenAI-compatible HTTP API | `dart:io HttpClient` + SSE line decode, entirely inside `infrastructure/correction/openai_compatible/` | **Recommend `dart:io` over adding `package:http`**: zero new dependency (pubspec carries no HTTP package today), native streamed responses, `close(force: true)` for teardown, and per-request abort via subscription cancel. `package:http` buys nothing here and adds a pin. Client is composition-root-owned and closed as a bounded lifecycle step. |
| `org.freedesktop.secrets` | `package:dbus 0.7.14`, already a direct dependency (Wayland portal) | Items live in lockable collections; unlock may prompt. Absent service and locked collection are runtime values, not startup preconditions. gnome-keyring and KWallet both implement it; neither is guaranteed present. |
| Local model servers (Ollama, LM Studio, vLLM) | Same adapter, different `baseUrl` — DW-115 decision (b) | No rate limiter, so failure is exhaustion/timeouts rather than 429. Known Ollama `/v1` streaming regressions with tools. Do not depend on `response_format` JSON schema; AD-16's tagged lines degrade correctly where a schema does not. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `ProviderRegistry` ↔ adapters | Synchronous factory closures capturing composition-root collaborators | The factory typedef stays `CorrectionProvider Function(ProviderConfig)`; collaborators arrive via the registry's constructor, as `Logger` already does. |
| adapter ↔ `SecretStore` | Port call inside `correct()` | Async, lazy, failure-as-value. |
| composition root ↔ `HttpClient` | Constructed in `main.dart`, closed as a `DaemonLifecycle` step | `CorrectionProvider` has no `dispose()` and must not grow one. |
| `ui/settings` ↔ `SettingsController` | Existing write-through (AD-13) | Token goes to `SecretStore`, never to `AppConfig`; the two writes are one user intent and need one mutation guard. |
| contract suite ↔ implementations | One parameterised suite, N `main()` entry points | Suite lives in `test/contract/`, owned by the port. |

## Human-Gated Decisions

Flagged explicitly, per the constraint that a fix requiring an edit to a verbatim-frozen port
declaration is a human decision, not an engineering one.

| # | Decision | Frozen edit? | Recommendation |
|---|----------|--------------|----------------|
| **D1** | Add a current-registration accessor to `GlobalHotkey` (AD-9 verbatim block) | **Yes — human-gated** | Do it; the port contract is broken and AD-12's unwired tray consumer is the second subscriber that will expose it. The `PanelVisibility` divergence shows the mechanism (divergence note in the port doc + owed spine correction), but ratification is the human's. |
| **D2** | Composition root owns the `HttpClient` and closes it as a bounded step | No | Do it. Avoids adding `dispose()` to AD-2's `CorrectionProvider`, which would be a frozen edit for no gain. |
| **D3** | Runtime provider re-resolution vs restart-required | No (touches a controller signature, not a port) | Option B (re-resolve at the composition root, swap only between corrections). Plan as its own phase. |
| **D4** | The teardown bound's value (how long may a history save delay exit?) | No | Pick one policy value, injected at the composition root, reused at every site. The choice is a product call; the *shape* is settled. |
| **D5** | Whether `onDone` is a rule (all seven sites) or a per-site judgement | No | Make it a rule. A per-site judgement obliges every non-adopting site to say why, which is more text and more drift than the arm itself. |
| **D6** | `CorrectionFailureKind` has four members and adapter #2 gets no fifth | Would be — **not recommended** | Map into the existing four using the Pattern 3 table. A `rateLimited` member is tempting and would force a UI change, a schema change (`failure_kind` is persisted by name) and a spine renegotiation, to say something a message can say. |

## Sources

| Source | Used for | Confidence |
|--------|----------|------------|
| `/workspace/lib/**`, `/workspace/test/**` (direct read, 2026-08-30) | Every claim about current subscription arms, fake behaviour, registry shape, timeout precedents | **HIGH** — primary source, quoted with file:line |
| `ARCHITECTURE-SPINE.md` AD-1…AD-19 | Frozen declarations, AD-15's three steps, AD-19's teardown rules | **HIGH** — governing document |
| `deferred-work.md` (DW-36, DW-103, DW-115, and the parked dispose/`AppDatabase` entries) | Known defect shapes and their prior reasoning | **HIGH** — with the standing caveat that ledger status is hand-maintained; the code-level claims above were re-verified by grep |
| Cockburn, Garrido-Paz, Wikipedia on ports & adapters | Multiple adapters per port; DI at a composition root | MEDIUM |
| Azure Architecture Center / DevIQ / CodeOpinion on the anti-corruption layer | Adapter/translator/facade split; vendor error codes translated inside the ACL | MEDIUM |
| pythonspeed "verified fakes", ploeh "Fakes are Test Doubles with contracts" | Contract suites run against fake *and* real | MEDIUM |
| RxDart `BehaviorSubject`/`ValueStream` docs | Why replay solves late subscribers, and why it is unavailable in a `dart:*`-only ring | MEDIUM |
| dart:async `Stream.listen` / `StreamSubscription.cancel`; dart-lang/sdk#49777 | `onDone`/`cancelOnError`; cancel futures and non-exiting processes | MEDIUM |
| OpenRouter errors-and-debugging (fetched); OpenAI 429 guidance; openai-python#2699; ollama#9084 | Mid-stream SSE `error` + `finish_reason: "error"`; retry-after headers; failover impossible after streaming begins; compatible-server variance | MEDIUM (cross-checked, two+ independent sources) |
| freedesktop Secret Service spec (fetched) | Collections, items, lookup attributes, locking | MEDIUM |

**Gaps.** No claim here is made about how a *specific* OpenAI-compatible server behaves under this
adapter — none exists yet. Secret Service behaviour under a Flatpak sandbox was not researched and
interacts with the already-noted AD-11 packaging caveat.

---
*Architecture research for: second provider adapter + port contract hardening in a frozen hexagonal daemon*
*Researched: 2026-08-30*
