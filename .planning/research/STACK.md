# Stack Research

**Domain:** Linux desktop tray daemon (Flutter/Dart, GTK3, X11 + Wayland) with pluggable LLM correction providers
**Researched:** 2026-08-30
**Confidence:** HIGH on versions and library APIs (registry- and source-verified); MEDIUM on the packaging recommendation (a judgement call over verified constraints)

---

## Scope Note — What This Research Does NOT Touch

This is a **brownfield hardening milestone**. Nothing below proposes replacing anything that ships today.

Flutter 3.44.8 / Dart 3.12.2, Riverpod 3.4.2, Drift 2.34.3, sqlite3, `hotkey_manager`, `tray_manager`, `window_manager`, `dbus`, the four-ring hexagonal layout, and the Python `claude-agent-sdk` sidecar all **stay**. Every pinned dependency was checked against the pub.dev registry API and **none is EOL, discontinued, retracted, or superseded** (see [Dependency Health](#dependency-health-verdict-on-the-pinned-set)).

The additions below are scoped to exactly three things: the second provider (DW-115), the API key that second provider introduces, and the packaging decision that is currently open.

---

## Recommended Stack

### Core Additions

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `openai_dart` | `8.1.0` | The OpenAI-compatible correction provider (DW-115) | The only Dart OpenAI client that ships **explicit stream abort** — `createStream(request, {Future<void>? abortTrigger})` — which is the exact shape `CorrectionProvider` needs. Pure Dart (no plugin, no native build, no platform channel), 160/160 pub points, ~36k downloads/30d, active weekly releases, strict semver, MIT. Configurable `baseUrl` makes "OpenAI-compatible" a config value rather than a fork. |
| `http` | `1.6.0` | Transitive HTTP transport for `openai_dart` | `dart-lang/http`, first-party. Not currently in `pubspec.lock`; arrives with `openai_dart`. Declare it only if you need to pin it — the house style pins the direct dependency, not its graph. |
| `flutter_secure_storage` | `11.0.0` | API key at rest, behind a domain `SecretStore` port | 3.75M downloads/30d, 160/160 points, actively maintained (`juliansteenbakker/flutter_secure_storage`). Linux federated impl `flutter_secure_storage_linux 3.0.2` is a C++ libsecret client over the Secret Service, i.e. the correct XDG mechanism. v11's Linux fixes are precisely the failure modes a tray daemon hits: *"handle missing default keyring"* and *"fail closed on orphaned keyring data"*. |
| `fastforge` | `0.6.12` | Build `.deb` + AppImage from the Flutter release bundle | The maintained successor to `flutter_distributor`, which pub.dev now marks **discontinued**. Same repo (`fastforgedev/fastforge`), same config format, declarative `distribute_options.yaml`. Keeps packaging out of hand-rolled shell. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `anthropic_sdk_dart` | `7.0.0` | Direct-Dart Claude Messages API client | **Not now.** Add only if a future milestone wants a *third*, zero-runtime-dependency Claude provider alongside the sidecar. Same maintainer/monorepo as `openai_dart`, same config and streaming shape — so the OpenAI adapter you write now is ~80% of this adapter. |
| `dbus` | `0.7.15` | Existing Wayland portal transport | Routine patch bump from the pinned `0.7.14` (published 2026-08-20). Only take it with the spine's blessing — the portal adapter is one of the three files the codebase map flags fragile. |
| `sqlite3` | `3.5.2` | Existing history storage | Routine patch bump from `3.5.1` (published 2026-08-19). Low risk, but it is a native build-hooks dependency, so re-run the Linux build before merging. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `gnome-keyring-daemon` (in CI) | Makes the secret adapter testable in GitHub Actions | The CI workflow that *has never executed* is already a ledger item. When it does run, secret tests need: `eval $(dbus-launch --sh-syntax)` then `echo "" \| gnome-keyring-daemon --unlock --daemonize --components=secrets`. Without it, every Secret Service call fails. |
| `libsecret-1-dev` | Build dependency for `flutter_secure_storage_linux` | Add to `.devcontainer/Dockerfile` alongside the existing `libkeybinder-3.0-dev` / `libayatana-appindicator3-dev` line. Runtime needs `libsecret-1-0` plus a live Secret Service (gnome-keyring or kwalletd). |
| `desktop-file-validate` | Validates the two `.desktop` entries | AD-11's portal identity depends on the entry basename matching the registered app id **exactly**. A malformed entry silently costs you the GlobalShortcuts bind on GNOME. Cheap gate, high value. |
| `appstream-util` | Validates a MetaInfo file | Only needed if the Flatpak path is ever taken; Flathub requires it. Skip for `.deb`/AppImage. |

## Installation

```yaml
# pubspec.yaml — exact pins, matching the file's existing no-caret discipline
dependencies:
  openai_dart: 8.1.0
  flutter_secure_storage: 11.0.0

dev_dependencies:
  fastforge: 0.6.12   # or install globally: dart pub global activate fastforge
```

```bash
# Devcontainer / build host additions
sudo apt-get install -y libsecret-1-dev

# Runtime (end-user machine) — usually already present on GNOME/KDE
#   libsecret-1-0 + gnome-keyring  (GNOME/Ubuntu)
#   libsecret-1-0 + kwalletd6      (KDE Plasma)
```

**Resolution is clean against the current lock.** Verified field by field:

| `openai_dart 8.1.0` requires | `pubspec.lock` today | Verdict |
|---|---|---|
| Dart SDK `>=3.9.0 <4.0.0` | 3.12.2 | ✅ |
| `http ^1.6.0` | absent | ✅ new transitive, latest is 1.6.0 |
| `http_parser ^4.1.2` | 4.1.2 | ✅ |
| `logging ^1.3.0` | 1.3.0 | ✅ |
| `meta ^1.16.0` | 1.18.0 (Flutter-SDK-pinned) | ✅ |
| `web_socket ^1.0.1` | 1.0.1 | ✅ |

No conflict with the pinned `drift_dev 2.34.0` / `build_runner 2.15.1` renegotiation recorded in `pubspec.yaml` — `openai_dart` pulls no analyzer.

---

## Decision 1 — The OpenAI-Compatible Provider Client

**Recommendation: `openai_dart 8.1.0`. Do not hand-roll SSE over `package:http`.** *(Confidence: HIGH — verified by reading the upstream source, not just the README.)*

### Why not raw `package:http` + `dart:io`

Hand-rolling looks cheap and is not. An SSE client for chat-completions has to get right: chunk-boundary-safe `data:` framing (a JSON object routinely splits across two socket reads), `[DONE]` sentinel handling, per-vendor delta shapes, byte→UTF-8 decoding across chunk boundaries, backpressure, connection abort on cancel, and a total-deadline race that does not leak the socket. `openai_dart` already ships all of it and is tested in CI upstream. The existing sidecar adapter is 436 lines for a *simpler* transport (NDJSON over a pipe); the raw-HTTP equivalent would land in the same range and become a fourth outsized file next to the three the codebase map already flags fragile.

### Why `openai_dart` specifically fits this port

The port is `Stream<CorrectionEvent> correct({text, preset})` — text in, stream out, single-subscription, cancellable, never throws (AD-3/AD-4). Mapping:

| Port requirement | `openai_dart` mechanism | Evidence |
|---|---|---|
| Streamed deltas | `client.chat.completions.createStream(...)` → `Stream<ChatStreamEvent>`, plus a `.textDeltas()` extension yielding `String` | README §"How do I stream responses?" |
| **Cancellable** | `createStream(request, {Future<void>? abortTrigger})`. Independently: `StreamingResource.sendStream` builds a **dedicated `http.Client` per stream** and closes it on `abortTrigger` completion, on done, on error, **and in `controller.onCancel`** | Source read: `lib/src/resources/streaming_resource.dart` lines 69–142 — the code comment is explicit that this exists "to ensure client cleanup on ALL termination paths… including early subscription cancellation" |
| **Total wall-clock deadline** (AD-19) | Pass `abortTrigger: Future<void>.delayed(timeout)`. This gives *exactly* the semantics the sidecar has — total wall clock from listen, not idle time — reusing the existing `timeoutMillis` settings key | derived; `OpenAIConfig.timeout` is per-request and is **not** the same thing |
| Custom endpoint | `OpenAIConfig(baseUrl: ..., authProvider: ApiKeyProvider(key))` | README §Configuration |
| Typed failures to map | `RateLimitException` → `ApiException` → `OpenAIException` hierarchy | README §Error Handling |

Note that **streaming deliberately bypasses the retry and interceptor chain** upstream ("non-idempotent, body consumed"). That is correct for this app — a correction that half-streamed must not silently restart under the user's cursor. Retry stays a user action via CAP-13's Retry button.

### Reuse `RegisterTaggedStreamParser` — do not write a second parser

`lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart` consumes `Stream<String>` and is documented as stateless and transport-agnostic. It already enforces the `END` sentinel, the three-register ordering, AD-3's terminal-event contract, and AD-4's cancellation propagation.

`openai_dart`'s `.textDeltas()` produces exactly `Stream<String>`. **Hoist the parser to `lib/src/infrastructure/correction/shared/` and feed both adapters from it.** This is the single highest-leverage move in the whole feature: the truncation-detection logic that took a sentinel design to get right is shared rather than reimplemented, and it makes a fake-vs-real contract test (an existing ledger item) meaningful across both providers.

### Vendor containment (hexagonal constraint)

Everything `openai_dart` lives under `lib/src/infrastructure/correction/openai_compatible/`. `OpenAIClient`, `ChatStreamEvent`, `ApiException`, `OpenAIConfig` **never** appear in `lib/src/domain/` or `lib/src/application/`. The only crossing is `ProviderRegistry`'s existing `CorrectionProvider Function(ProviderConfig)` entry — one new map entry, no `switch`, per AD-15.

Suggested settings keys, owned by the adapter as `static const` (mirroring the sidecar's `interpreterSettingsKey` pattern so config/registry/tests cannot drift on a string literal):

```
baseUrl        e.g. https://api.openai.com/v1
model          e.g. gpt-5.5
apiKeyRef      an opaque secret NAME — never the key itself (see Decision 3)
timeoutMillis  reuses the existing bound-validation semantics
```

**Refactor flag:** `ProviderRegistry._timeoutFrom` currently hardcodes `ClaudeAgentSdkCorrectionProvider.timeoutSettingsKey`. Two providers need that validation (including the `_maxTimeoutMillis` overflow guard, whose reasoning is provider-independent). Lift it to a shared helper before adding the second entry, or the overflow bug it exists to prevent gets reintroduced in the new adapter.

**Lifecycle:** construct one `OpenAIClient` **per `correct()` call** and `close()` it on stream termination, mirroring the sidecar's "fresh run per call, never reused" statelessness. A long-lived client would hold a connection pool across a config change and violate the port's stateless contract.

### Compatibility caveat (be honest about this)

`openai_dart` targets the OpenAI spec. Its `baseUrl` is documented for Azure and proxies; the changelog shows deliberate accommodation of **OpenRouter** payloads (8.1.0 preserves `reasoning_details` round-trips). Chat Completions against spec-conformant gateways — OpenRouter, Groq, Together, vLLM, LM Studio, Ollama's `/v1` — is the well-trodden path. It is not a *guarantee* for every self-hosted server. Mitigation: make the acceptance test for DW-115 run the adapter against **two different endpoints**, and keep the failure mapping conservative — an unparseable event is `malformedResponse`, not a crash.

---

## Decision 2 — Keep the Python Sidecar (For Now)

**Recommendation: KEEP the `claude-agent-sdk` sidecar as the default Claude provider this milestone. Do not replace it.** *(Confidence: MEDIUM-HIGH — the capability difference is documented; the sizing is judgement.)*

A direct-Dart Claude path **is** viable in 2026 — `anthropic_sdk_dart 7.0.0` (2026-08-01) is pure Dart, streams SSE with cancellation, and takes a configurable `baseUrl` and `RetryPolicy`. So the question is real, not settled by absence of a library. Here is the honest trade:

| | Python sidecar (`claude-agent-sdk`) — shipped | Direct Dart (`anthropic_sdk_dart 7.0.0`) |
|---|---|---|
| **Auth** | Inherits the `claude` CLI's own credentials. **The app holds no API key.** | Requires an `ANTHROPIC_API_KEY` the app must store — pulls Claude into Decision 3's blast radius |
| **Runtime deps** | Python 3.11+, a venv, `claude-agent-sdk`, **and** the Node-based `claude` CLI as a grandchild | None. One binary. |
| **Process model** | One child process group per correction; teardown kills the grandchild | In-process HTTP; cancel closes a socket |
| **Failure surface** | Interpreter path, venv drift, sidecar asset path, CLI version skew — all already handled and all still real | HTTP status + parse. Far smaller. |
| **Capability** | The **agent loop**: tools, sessions, MCP, subagents | Messages API only. `anthropic_sdk_dart` does not reimplement the agent loop. |
| **Packaging cost** | Must bundle Python + Node runtime (see Decision 4) | Nothing to bundle |
| **Cold start** | Process spawn + interpreter start per correction | ~0 |

**Why keep it anyway, this milestone:**

1. **It is the only provider today.** Replacing it while simultaneously adding the *first alternative* means shipping a milestone with zero providers of proven provenance. DW-115 exists to give CAP-8 a *choice*; the way to prove the port is to add a second implementation, not to swap the first.
2. **The zero-key property is genuinely valuable.** Today the daemon stores no credential at all. Moving Claude to `anthropic_sdk_dart` would make an API key mandatory for the *default* provider — turning Decision 3 from "harden one new optional path" into "block the default path on a keyring."
3. **The sidecar's hard parts are already paid for.** Process-group teardown, backpressure, the stall deadline, `providerUnavailable`-not-crash on a missing interpreter — 436 lines of solved problems, tested, shipped. Deleting them is a rewrite dressed as a simplification, and PROJECT.md's Out of Scope is explicit that this milestone hardens rather than extends.
4. **The right time to revisit is the packaging decision.** If Flatpak is ever chosen, the sidecar's cost jumps sharply (Python *and* Node bundled inside the sandbox). That is the trigger to reopen this — not now.

**What to do instead:** write the OpenAI adapter first. It is the same streaming/cancellation/error-mapping shape as an eventual `anthropic_sdk_dart` adapter (same maintainer, same monorepo, near-identical config API), so the second provider is also the *prototype* for a possible third. Then the sidecar-vs-direct call can be made on evidence, with a working fallback in hand.

---

## Decision 3 — Secret Handling for the API Key

**Recommendation: a domain `SecretStore` port with two infrastructure adapters — `flutter_secure_storage 11.0.0` (primary) and a `0600` file (explicit, opt-in fallback). Store a *reference*, never the key, in `ProviderConfig.settings`.** *(Confidence: HIGH on the mechanism; MEDIUM on the fallback ergonomics.)*

### The threat this creates

Today the daemon stores **no credential** — the sidecar borrows the `claude` CLI's auth. `ProviderConfig.settings` is a `Map<String, String>` serialised straight into the JSON config file by `JsonConfigStore`. Putting an API key in that map writes it to a plaintext file, in exactly the same defect class as the *"history plaintext file permissions"* item already open in the ledger. PROJECT.md's Core Value names leakage as worse than no daemon at all. Treat this as a correctness requirement, not polish.

### The port

```
lib/src/domain/secret/secret_store.dart

abstract interface class SecretStore {
  Future<String?> read(String ref);
  Future<void> write(String ref, String value);
  Future<void> delete(String ref);
}
```

`ProviderConfig.settings['apiKeyRef']` holds an opaque name (e.g. `openai-compatible.default`). The adapter resolves it through `SecretStore` at `correct()` time. The config file then contains a *pointer*, and a leaked config is a leaked pointer. This also keeps `ProviderConfig`'s existing documented contract intact — settings stay opaque to the domain, and only the owning adapter interprets them (AD-15).

### Adapter A — `flutter_secure_storage 11.0.0` (primary)

Linux support is `flutter_secure_storage_linux 3.0.2`, a C++ plugin talking **libsecret → Secret Service over D-Bus** — the standard XDG mechanism, backed by gnome-keyring on GNOME/Ubuntu and kwalletd on KDE. It is the same store `git-credential-libsecret` and every native GNOME app uses, so the key lands where a Linux user expects to find and revoke it.

v11.0.0's Linux changes read like a list of exactly this daemon's edge cases: *handle missing default keyring* and *fail closed on orphaned keyring data*. A locked or absent keyring raises a catchable `PlatformException` with code `KeyringLocked` — map that to `CorrectionFailureKind.providerUnavailable` and surface it inline with Retry (CAP-13). Never let it throw past the port.

**Two frictions, stated plainly:**

- **It is a Flutter plugin, not pure Dart.** It uses method channels, so it needs a Flutter binding. Tests for this adapter cannot run under the merge gate's `dart test` — they need `flutter_test` with a mocked method channel. Given that "tests reachable from no gate" is already an open ledger item, put the *fake* `SecretStore` under `dart test` and the real adapter under a `flutter_test` target the CI workflow actually invokes.
- **It adds a native build dep** (`libsecret-1-dev`) and a runtime dep (a live Secret Service). Neither is exotic on a GTK3 desktop — the app already requires `libkeybinder`, `libayatana-appindicator3` and a D-Bus session bus — but headless CI has neither by default.

### Adapter B — `0600` file (explicit fallback, not silent)

There will be systems with no Secret Service: minimal WMs, some Sway/Hyprland setups, containers. A file adapter under `${XDG_CONFIG_HOME}` with mode `0600` and a `0700` parent directory is the honest fallback, and it is **pure Dart**, so it is fully covered by the existing `dart test` gate.

Two rules make it acceptable: (1) selection is **explicit config**, never an automatic downgrade — a daemon that silently drops from keyring to plaintext on a transient D-Bus hiccup is a leak with a good excuse; (2) it verifies its own mode on read and refuses on a permissive file, mirroring the fix the history-permissions ledger item needs. Consider sharing one permission-hardening helper between the two — it is the same defect twice.

### Why NOT drive `org.freedesktop.secrets` directly over `package:dbus`

Tempting: `dbus 0.7.15` is already a dependency, the D-Bus expertise is in the codebase, and it avoids a plugin. But a *correct* Secret Service client must implement `OpenSession` (including the `dh-ietf1024-sha256-aes128-cbc-pkcs7` handshake if you want the secret encrypted on the bus rather than sent `plain`), collection unlocking through the async `Prompt` interface with its window-parenting quirks, and item search/create with attribute schemas. That is several hundred lines of new cryptographic and prompt-lifecycle code — a fourth fragile file — to replace a maintained plugin with 3.75M downloads/30d. **There is no maintained pure-Dart Secret Service client on pub.dev**: `secret_service`, `libsecret`, `gnome_keyring` and `dart_keyring` do not exist; the generic `keyring 1.0.0` (2026-06-27) has 0 likes and 9 downloads/30d and is unproven. Do not build this.

### Why NOT the `org.freedesktop.portal.Secret` portal (unless Flatpak)

`RetrieveSecret` does **not** store arbitrary secrets. It returns an opaque **per-application master secret**, of unspecified length, which the app must expand with a KDF and then use to encrypt its own local store. It is the correct primitive for a *sandboxed* app, and it is the right answer **if and only if** Decision 4 goes Flatpak. For an unsandboxed `.deb`/AppImage it is strictly more work than libsecret for a worse UX — the user can neither see nor revoke the key in their keyring UI.

---

## Decision 4 — Packaging

**Recommendation: `.deb` + AppImage, built with `fastforge 0.6.12`. Explicitly defer Flatpak; reject Snap.** *(Confidence: MEDIUM — the constraints are verified HIGH; the ranking is a judgement over them.)*

### The constraint that decides this: portal identity

The codebase already solved a subtle problem. `linux/packaging/com.divertedriver.HotkeyGrammarCorrector.desktop` carries a comment that is the whole story:

> *"the Wayland adapter registers the app id `com.divertedriver.HotkeyGrammarCorrector` with the host portal registry, and GNOME discards the global-shortcut bind unless an installed desktop entry carries that exact basename"* (AD-11)

That is `org.freedesktop.host.portal.Registry.Register(app_id, options)`. Verified against the portal docs, its constraints are severe:

- **At most once.** Any subsequent call errors.
- **Before any other portal method call.** Registering after one errors.
- **Only for apps xdg-desktop-portal does not detect as sandboxed.** It refuses sandboxed callers outright.
- The id must match an installed `.desktop` basename.
- Apps should watch `NameOwnerChanged` and re-register if the portal service restarts.

The Registry exists because xdg-desktop-portal derives an unsandboxed app's id from the systemd unit name (`app-*.scope` only) and yields an **empty** id for D-Bus-activated or terminal-launched processes. An empty id breaks portal features that key on identity — and GlobalShortcuts persistence is keyed on application identity: `ListShortcuts` returns *"the shortcuts that were successfully bound in a previous session by this application."* Empty id, no persistence, re-bind dialog every launch.

**So packaging is not a distribution detail here — it selects the portal handshake:**

| Format | App id source | Effect on the shipped AD-11 code |
|---|---|---|
| `.deb` / AppImage | `Registry.Register(...)` + installed `.desktop` | **Unchanged.** The current handshake is correct as written. |
| Flatpak | `$FLATPAK_ID`, automatic | **The `Register` call must be deleted** — it errors for sandboxed callers. AD-11 changes meaning; the desktop-entry installer becomes dead code. |
| Snap (strict) | snap-derived id | Also changes; plus every D-Bus name needs an interface plug. |

### Why `.deb` + AppImage

1. **It is the only option that changes nothing in the fragile file.** The ~1307-line Wayland portal adapter is flagged fragile by the codebase map. This milestone's job is hardening. Rewriting its identity handshake in the same milestone that adds a provider and a keyring is how you get a regression nobody can bisect.
2. **The Python sidecar just works.** `Process.start` on a path outside a sandbox needs no `flatpak-spawn`, no `--talk-name=org.freedesktop.Flatpak`, no bundled interpreter.
3. **libsecret just works.** No `--talk-name=org.freedesktop.secrets` hole, no portal Secret + KDF + local encrypted store detour.
4. **AppImage covers the non-Debian long tail** with one artifact and no repository infrastructure, which matters for a single-maintainer desktop utility.
5. **`fastforge` builds both from one config**, and it is the maintained successor to the now-**discontinued** `flutter_distributor` — so this also retires a stale tool before it becomes a ledger entry.

### Why defer Flatpak (defer, not reject)

Flatpak is the better *distribution* story — Flathub, sandboxing, atomic updates, and GlobalShortcuts identity for free. It is the wrong *next* step because it compounds:

- The `claude-agent-sdk` sidecar spawns the Node-based `claude` CLI as a grandchild. Inside a sandbox that means bundling **both** a Python interpreter with its site-packages **and** a Node runtime with the CLI, plus `--share=network`. The alternative — `flatpak-spawn --host` — requires `--talk-name=org.freedesktop.Flatpak`, which is a sandbox escape that makes the sandbox mostly decorative and would be flagged in Flathub review.
- Secret handling would move from libsecret to the portal Secret + KDF design (Decision 3's rejected branch), i.e. a second design done twice.
- Flutter Flatpak tooling is community-maintained (`TheAppgineer/flatpak-flutter`, `o-murphy/flutpak`), not first-party, and Flathub requires offline builds with a vendored pub cache — real work, not a manifest.

That is three coupled rewrites (portal identity, sidecar hosting, secret storage) landing in a hardening milestone. **Revisit Flatpak when — and only when — the Claude provider no longer needs a Python+Node subprocess.** Decision 2 and Decision 4 are the same decision viewed twice; sequence them.

### Why reject Snap

Strict confinement gives no access to files, network, processes or D-Bus without an explicit interface plug, and this daemon needs a broad set at once: global shortcuts via the portal, clipboard, tray/appindicator, D-Bus session access, a spawned interpreter, and libsecret. Classic confinement would work but is unavailable on Flathub-equivalent terms and defeats the point. Snap also carries a distro-political cost outside Ubuntu for a tool aimed at all GTK3 desktops. Flutter's official docs favour Snap; that guidance is written for GUI apps that do not hold global shortcuts and do not fork interpreters. Do not follow it here.

### Free win to take while packaging

GlobalShortcuts is at **interface version 2**, which added `ConfigureShortcuts` — a portal-provided UI for rebinding. CAP-12 currently ships Wayland rebinding as *advisory* because the compositor owns the binding and `BindShortcuts` cannot be re-issued (the adapter says so at line ~902). `ConfigureShortcuts` is the sanctioned way to hand the user a real rebind dialog on Wayland. Cheap, additive, and it upgrades a known-weak capability. Guard on the interface `version` property — wlroots compositors (Sway, Hyprland, Niri) ship no GlobalShortcuts backend at all, which the adapter already handles at line ~1177.

---

## Dependency Health (Verdict on the Pinned Set)

Verified 2026-08-30 against the pub.dev registry API (`isDiscontinued`, `replacedBy`, `retracted`, publish dates) and, where relevant, GitHub repo activity.

| Package | Pinned | Latest | Published | Health | Action |
|---|---|---|---|---|---|
| `flutter_riverpod` | 3.4.2 | **3.4.2** | 2026-07-28 | Current | None |
| `drift` | 2.34.3 | **2.34.3** | 2026-07-27 | Current | None |
| `sqlite3` | 3.5.1 | 3.5.2 | 2026-08-19 | Healthy, one patch behind | Optional bump; native build hooks — rebuild before merge |
| `dbus` | 0.7.14 | 0.7.15 | 2026-08-20 | Healthy (Canonical, 6M dl/30d) | Optional bump; touches the fragile portal adapter |
| `tray_manager` | 0.5.3 | **0.5.3** | 2026-06-09 | Healthy, 160/160, 218k dl/30d | None |
| `window_manager` | 0.5.2 | **0.5.2** | 2026-07-04 | Healthy, 160/160, 650k dl/30d | None |
| `hotkey_manager` | 0.2.3 | **0.2.3** | **2024-05-18** | ⚠️ **Stale** — last repo commit 2025-05-13, 25 open issues, 140/160 points. Not discontinued, no replacement exists. | **Keep. Contain.** |
| `build_runner` | 2.15.1 | — | — | Deliberately renegotiated down; documented | None |
| `drift_dev` | 2.34.0 | — | — | 2.34.1+ need `analyzer ^13`; 2.34.0 is the ceiling on this Flutter | None |
| `flutter_lints` | 6.0.0 | — | — | Current major | None |

**Nothing is EOL, abandoned, retracted, or has a known-better 2026 replacement.** The pins are in good shape.

`hotkey_manager` is the only amber light and it is **not** actionable as a swap — there is no maintained alternative, and the leanflutter ecosystem it belongs to (`tray_manager`, `window_manager`, both healthy) is clearly still alive; only this one package has gone quiet. Two things make it a manageable risk: it is used **only on the X11 path** (Wayland goes through the portal adapter, which is this project's own code over `dbus`), and X11 global-hotkey semantics via `libkeybinder-3.0` are frozen — a stale binding to a frozen C API is far less risky than a stale binding to a moving one. **Action: keep it, and make sure the `GlobalHotkey` port's fake covers the same contract as the real adapter** (a contract-test gap already in the ledger). If it ever does break, the escape hatch is a direct XGrabKey binding over FFI behind the existing port — the hexagonal boundary means that stays a one-file change.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|---|---|---|
| `openai_dart 8.1.0` | `dart_openai 8.0.0` (`anasfik/openai`) | If you need something `openai_dart` lacks. Single-maintainer, no documented per-stream abort primitive — the property this port depends on most. |
| `openai_dart 8.1.0` | `langchain_openai 0.9.0` | If the app ever needs chains, RAG, or provider-swapping *inside* the adapter. Today it adds a second abstraction on top of a port that already abstracts, with vendor types to keep off the boundary. |
| `openai_dart 8.1.0` | Raw `package:http` + a hand-written SSE parser | Only if a target endpoint diverges so far from the spec that the typed models reject it. Budget ~400 lines and the chunk-boundary bugs that come with them. |
| Sidecar (Claude) | `anthropic_sdk_dart 7.0.0` | When the agent loop is confirmed unnecessary **and** an API key is acceptable for the default provider — or as the trigger for the Flatpak path. Not this milestone. |
| `flutter_secure_storage 11.0.0` | Direct Secret Service over `package:dbus 0.7.15` | Only if the plugin's method-channel test friction proves intolerable. Cost: DH session handshake, `Prompt` lifecycle, attribute schemas. |
| `flutter_secure_storage 11.0.0` | `org.freedesktop.portal.Secret` + KDF + local encrypted file | **The correct choice if and only if the app is Flatpak-packaged.** |
| `.deb` + AppImage | Flatpak | Once the Claude provider needs no Python/Node subprocess. Then Flatpak becomes clearly better and the portal handshake simplifies. |
| `fastforge 0.6.12` | Hand-rolled `dpkg-deb` / `appimagetool` scripts | Only if `fastforge` cannot express a needed control-file field. It wraps both. |

## What NOT to Use

| Avoid | Why | Use Instead |
|---|---|---|
| `flutter_distributor` | **Marked discontinued on pub.dev.** Same repo now publishes the successor. | `fastforge 0.6.12` |
| `keyring 1.0.0` (kingwill101) | 0 likes, 9 downloads/30d, published 2026-06-27. Unproven umbrella over `keyring_native`/`keyring_web`. Storing the app's only credential behind it is an unforced risk. | `flutter_secure_storage 11.0.0` |
| `eventflux 2.2.1` / `flutter_client_sse 2.0.3` | Generic SSE clients, both last published 2024. `openai_dart` already parses OpenAI SSE correctly, including the `[DONE]` sentinel and chunk-boundary framing. | `openai_dart`'s built-in streaming |
| Putting the API key in `ProviderConfig.settings` | `JsonConfigStore` serialises that map to a plaintext file. Same defect class as the open history-permissions item; Core Value names leakage as disqualifying. | `apiKeyRef` pointer + `SecretStore` port |
| A silent keyring→plaintext fallback | A transient D-Bus failure would downgrade the user's key to a plaintext file with no signal. | Explicit, configured backend choice; fail visibly as `providerUnavailable` |
| `flatpak-spawn --host` for the sidecar | Requires `--talk-name=org.freedesktop.Flatpak`, which makes the sandbox decorative and would be flagged in Flathub review. | Bundle the interpreter inside the sandbox — or stay unsandboxed (`.deb`/AppImage) |
| Snap strict confinement | Portal + clipboard + appindicator + D-Bus + spawned interpreter + libsecret all need separate plugs; several are fragile in strict mode. | `.deb` + AppImage |
| A second register parser for the new provider | `RegisterTaggedStreamParser` is transport-agnostic (`Stream<String>` in) and already encodes the truncation-sentinel design. | Hoist it to `infrastructure/correction/shared/` and share it |
| A long-lived `OpenAIClient` in the registry | Holds a connection pool across config changes; breaks the port's stateless contract. | One client per `correct()` call, closed on stream termination |

## Stack Patterns by Variant

**If the second provider must reach non-OpenAI gateways (OpenRouter, Groq, Ollama `/v1`, vLLM, LM Studio):**
- Use `openai_dart` with `baseUrl` set per-provider-entry in config. One registry entry can serve every compatible endpoint — `ProviderConfig` already keys them by id.
- Because it is spec-shaped rather than gateway-shaped, gate on an acceptance test against **two** distinct endpoints, and map anything unparseable to `malformedResponse`.

**If a target endpoint needs no API key (local Ollama / LM Studio):**
- Make `apiKeyRef` optional and pass a placeholder to `ApiKeyProvider`. Do not force a keyring interaction for a localhost endpoint — that would make the *easiest* configuration the one that fails hardest.

**If the deployment target has no Secret Service (Sway/Hyprland/Niri, minimal WMs, containers):**
- The `0600` file adapter, selected explicitly in config. Never automatic.
- Note the overlap: these are the same compositors that ship **no GlobalShortcuts backend** (adapter line ~1177). One "minimal Wayland" profile, two degradations — document them together rather than as unrelated caveats.

**If Flatpak is ever chosen:**
- Delete the `Registry.Register` call (it errors for sandboxed callers); take the app id from `$FLATPAK_ID`.
- Swap `flutter_secure_storage` for `org.freedesktop.portal.Secret` + KDF + local encrypted store.
- Bundle Python **and** Node inside the sandbox, or retire the sidecar first.
- Use `TheAppgineer/flatpak-flutter` to vendor the pub cache for Flathub's offline-build requirement.

## Version Compatibility

| Package A | Compatible With | Notes |
|---|---|---|
| `openai_dart 8.1.0` | Dart 3.12.2 | Requires `>=3.9.0 <4.0.0`. ✅ |
| `openai_dart 8.1.0` | existing `pubspec.lock` | Adds only `http 1.6.0`; `http_parser`/`logging`/`meta`/`web_socket` already satisfy. ✅ |
| `openai_dart 8.1.0` | Dart 3.13+ | 8.0.1 fixed a `LinkedHashMap` failure on 3.13.2 in streaming multipart. Take ≥8.0.1 before any Dart bump. |
| `flutter_secure_storage 11.0.0` | Flutter 3.44.8 | Requires `flutter >=3.19.0`, `sdk >=3.8.0`. ✅ |
| `flutter_secure_storage 11.0.0` | `flutter_secure_storage_linux 3.0.2` | Federated via `^3.0.1`. v11 removes v10 deprecations — **Android-only impact**, none on Linux. |
| `flutter_secure_storage_linux 3.0.2` | build/runtime | Needs `libsecret-1-dev` (build), `libsecret-1-0` + a live Secret Service (runtime). Headless CI needs `dbus-launch` + `gnome-keyring-daemon`. |
| `anthropic_sdk_dart 7.0.0` | `openai_dart 8.1.0` | Same monorepo, coordinated releases; co-installable if a third provider is ever added. |
| `dbus 0.7.15` | portal adapter | Patch bump over the pinned 0.7.14. No API break, but it touches a file the codebase map flags fragile. |
| `sqlite3 3.5.2` | Drift 2.34.3 | Patch bump; native build hooks — verify the Linux build, and mind the stale-`build/` gotcha noted in PROJECT.md. |
| `hotkey_manager 0.2.3` | Flutter 3.44.8 | Works today. Stale (2024-05-18) but binds a frozen C API (`libkeybinder-3.0`). X11 path only. |

## Sources

- **pub.dev registry API** (`https://pub.dev/api/packages/<name>` and `/score`) — authoritative version, publish date, `isDiscontinued`, `replacedBy`, `retracted`, pub points, likes, 30-day downloads, platform tags, and full latest-version pubspecs for: `openai_dart`, `anthropic_sdk_dart`, `flutter_secure_storage`, `flutter_secure_storage_linux`, `dbus`, `hotkey_manager`, `tray_manager`, `window_manager`, `drift`, `flutter_riverpod`, `sqlite3`, `http`, `fastforge`, `flutter_distributor`, `keyring`, `dart_openai`, `langchain_openai`, `eventflux`, `flutter_client_sse`. — **HIGH** (primary registry)
- **`davidmigloz/ai_clients_dart` upstream source, read directly** — `packages/openai_dart/lib/src/resources/streaming_resource.dart` (dedicated per-stream `http.Client`, `abortTrigger`, `controller.onCancel` teardown), `resources/chat_resource.dart` (`createStream` signature), `README.md`, `CHANGELOG.md`, `llms.txt`; `packages/anthropic_sdk_dart/README.md`. — **HIGH** (source of truth, not documentation about it)
- **XDG Desktop Portal documentation** — `org.freedesktop.portal.GlobalShortcuts` (version 2; `CreateSession`/`BindShortcuts`/`ListShortcuts`/`ConfigureShortcuts`; persistence keyed by application identity), `org.freedesktop.host.portal.Registry` (`Register(app_id, options)`; once-only, before-any-portal-call, refused for sandboxed callers, `.desktop` basename match, `NameOwnerChanged` re-registration), `org.freedesktop.portal.Secret` (`RetrieveSecret` returns an opaque per-app master secret, expand with a KDF). — **HIGH** (normative spec)
- **`juliansteenbakker/flutter_secure_storage` CHANGELOG** — v11.0.0 breaking changes (Android-scoped), Linux fixes *handle missing default keyring* / *fail closed on orphaned keyring data*. — **HIGH** (upstream changelog)
- **`leanflutter/hotkey_manager` GitHub API** — `pushed_at` 2025-05-13, 25 open issues, not archived, commit list. — **HIGH**
- **Ignacy Kuchciński, "Using Portals with unsandboxed apps"** (blogs.gnome.org, 2025-06-04) — systemd `app-*.scope` app-id derivation, empty-id consequences, Registry as the documented workaround, GTK's automatic registration at startup chain-up. — **MEDIUM** (maintainer-adjacent, corroborates the portal spec)
- **Web search** — `flatpak-spawn(1)` manpages, Flatpak sandbox-permissions docs, Snap confinement docs, Flutter Linux deployment docs, Flutter Flatpak community tooling (`TheAppgineer/flatpak-flutter`, `o-murphy/flutpak`), `flutter_secure_storage` headless-CI keyring setup. — **LOW–MEDIUM** individually; used only where corroborated by a primary artifact above.
- **Local codebase** — `pubspec.yaml`, `pubspec.lock`, `lib/src/domain/correction/{correction_provider,correction_event}.dart`, `lib/src/domain/config/provider_config.dart`, `lib/src/infrastructure/correction/provider_registry.dart`, `.../claude_agent_sdk/{claude_agent_sdk_correction_provider,register_tagged_stream_parser}.dart`, `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`, `linux/packaging/*.desktop`, `linux/runner/my_application.cc`. — **HIGH**

**Confidence method.** The `classify-confidence` seam scores `websearch`/`webfetch` transports as `LOW` and curated MCP doc providers as `MEDIUM`. No Context7/Ref MCP was available in this run, so every version claim was instead verified against the **pub.dev registry API** and, for behavioural claims, against **upstream source read directly**. Claims resting on a primary artifact I read are marked **HIGH**; claims resting only on search-result synthesis are marked **LOW–MEDIUM** and are not load-bearing for any recommendation. All eight research digests are cached via `research-store put` with the seam's own tier recorded.

---
*Stack research for: Linux tray daemon — second correction provider, secret storage, packaging*
*Researched: 2026-08-30*
