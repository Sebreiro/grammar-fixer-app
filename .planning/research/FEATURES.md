# Feature Research

**Domain:** Local-first desktop assistant that stores user plaintext and relays it to a third-party LLM API (Linux tray daemon)
**Researched:** 2026-08-30
**Confidence:** MEDIUM

> **Scope note.** This is a **hardening** milestone against a frozen 14-capability SPEC. This
> document is deliberately lopsided: table stakes and anti-features carry the weight, and the
> Differentiators section exists mainly to name things that will be **rejected as out of scope**
> so they stop being re-proposed. The one sanctioned feature addition is DW-115 (a second,
> OpenAI-compatible provider); everything else here closes a gap in what already ships.

## Feature Landscape

### Table Stakes (Users Expect These)

Three clusters. Missing any of them is not "unpolished" — it is the class of defect that gets a
local-plaintext-plus-cloud-API tool banned by a security reviewer or uninstalled by a user who
reads the manpage.

#### Cluster A — Local history: retention, clearing, permissions

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **A1. History file readable only by its owner** (`0600` db, `0700` data dir) | Every comparable local-history tool keeps its store private. The daemon stores verbatim plaintext of everything the user pastes — routinely private messages, and in practice credentials pasted by accident. At the common `umask 022` the file is `0644`: every local account can read it. | **LOW** | Closes DW-106. `dart:io` has no `chmod`, so the fix is create-restricted-then-open, or set the mode on the data directory in `AppPaths`. **Must cover `-wal`, `-shm` and `-journal` sidecars, not just `history.sqlite`** — SQLite creates them at the umask independently. Directory-mode is the more robust of the two fixes for exactly that reason. Ship this first; it depends on nothing. |
| **A2. A bounded history** — cap by row count and/or age, with a configurable value and a sane default | Maccy, CopyQ and GPaste all ship a history-size setting; rolling old entries off is the default behaviour of the whole clipboard-manager category, not a power-user option. Today the daemon writes one row per correction forever. | **MEDIUM** | Closes DW-105 (growth half). Requires the port widening in A3 — `CorrectionRepository` is `save` + `recent` only, so nothing can delete a row. Prune-on-write is the cheap shape (prune inside the same terminal-event write the controller already performs). |
| **A3. "Clear history" — an explicit, user-invoked, complete erase** | Universal across the category (Maccy, CopyQ, GPaste all have it; every note app has "delete"). A store the user cannot empty is a store the user cannot trust. Reviewers treat "no delete path at all" as a finding, not a gap. | **MEDIUM** | Closes DW-105 (unclearable half). **This is the human-gated one:** the fix widens `CorrectionRepository` beyond its verbatim-fixed declaration, which per the project's own contract is a decision, not an implementation. Everything else in Cluster A is downstream of that call. Erase must `VACUUM` or otherwise not leave the plaintext recoverable in freelist pages. |
| **A4. A documented, discoverable data location** | "Where does my text actually live?" is the first question in every privacy thread about a local tool. Local-first tools (Obsidian, Logseq, Super Productivity) make on-disk location and format a headline property. | **LOW** | Docs + a settings-screen line showing the resolved path. Cheap and disproportionately reassuring. Partly satisfies the export expectation (E1) on its own: SQLite at a named path is an open format the user can already query. |
| **A5. Survive a corrupt `history.sqlite` without losing the daemon** | A resident daemon that refuses to start because one file is bad leaves the user no surface to fix it — the project already reasoned this way for `config.json` in AD-13 and must be consistent. | **MEDIUM** | Open ledger item (`AppDatabase.file` has no quarantine-and-recreate branch). Policy choice — rename-aside-and-recreate vs. surface-and-refuse — is a contract decision. Recommend **rename aside, recreate, log loudly, and surface degraded state on the tray**, matching AD-12's degradation shape. |
| **A6. Plaintext never reaches a log** | Already a stated project invariant and a `Logger` port contract. It is table stakes because a single `context: {text: …}` map in a future warning silently converts the systemd journal into a second, unclearable, world-readable history. | **LOW** | The behaviour holds today; what is missing is a *gate* that keeps it holding. An architecture test asserting no correction text or suggestion body reaches a `Logger` call site is the durable form. |

#### Cluster B — Third-party API disclosure and the opt-out path

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **B1. In-app, contextual disclosure naming the provider** — "Your text is sent to Anthropic's Claude API" | This is now the codified industry bar, not a nicety: App Store guideline 5.1.2(i) requires the AI provider be **named**, the data described, the purpose stated, and the disclosure be in-app rather than buried in a policy. Linux has no equivalent gatekeeper, but the norm is what users and reviewers now measure against. | **LOW** | One block on the settings screen plus one line in the README. The disclosure must be **per-provider and derived from the selected provider**, not a static string — the moment DW-115 lands, a hardcoded "Anthropic" disclosure becomes an actively false statement for OpenAI-compatible users. |
| **B2. First-run consent before the first outbound send** | The dominant desktop pattern is: AI feature off by default, behind a toggle, the toggle screen carries the full disclosure, flipping it *is* the consent. A tray daemon that autostarts at login and ships text to a vendor on the first hotkey press with no prior screen is the exact shape that gets a tool blocked in regulated environments. | **MEDIUM** | Cheapest correct form: one persisted config flag; the panel's first summon shows the disclosure with Accept, and the correction is not dispatched until accepted. Must **not** block daemon startup (AD-19 shape) and must not make the panel un-dismissable. |
| **B3. Per-provider "where is this going" indicator on the settings surface** | Once there are two providers and a user-settable base URL, the daemon can send text to literally any host. The user needs the effective destination host visible without reading `config.json`. LanguageTool does exactly this: users who configure a custom server get a message explaining text goes to *that* server. | **LOW** | Show the resolved endpoint host next to the provider selection. Reuse the settings screen's existing status-view idiom (`hotkey_status_view.dart`) rather than inventing a surface. |
| **B4. A stated answer to "is my text logged or trained on?"** with a link to the provider's policy | The first question anyone asks about a text-relay tool. Verifiable primary-source answers exist for both shipped providers. | **LOW** | Docs, not code. Anthropic (primary source): *"Retained data is never used for model training without your express permission"*, with zero-data-retention available for `/v1/messages`. OpenAI: API inputs/outputs retained up to 30 days for abuse monitoring then deleted, **not** used for training unless the org opts in; ZDR available for eligible endpoints. State both, dated, and link — do not paraphrase into a guarantee the project cannot make. |
| **B5. A real opt-out that is not "stop using the app"** | Privacy-conscious users of this category expect a local path — this is precisely LanguageTool's answer (embedded HTTP server, self-hosted, nothing leaves the machine) and it is why LanguageTool survives privacy scrutiny that Grammarly does not. | **LOW** *(given DW-115)* | **Falls out of DW-115 for free** and is the strongest argument for its priority: an OpenAI-compatible adapter with a settable base URL points at Ollama or LM Studio and the daemon becomes fully offline. Requires only that the base URL setting permit `http://localhost:*` and that docs name the local-server recipe. Do **not** build a bespoke offline mode — see AF7. |
| **B6. No telemetry, no analytics, no phone-home, and say so** | Zero telemetry is the baseline expectation for local-first, and auditable absence-of-telemetry is a stated part of the value proposition for open-source tools in this space. | **LOW** | Holds today (no error tracking, no network beyond the provider). Make it an explicit README claim plus an architecture test that the only outbound network call site is the provider adapter. Claiming it without a gate is how it quietly stops being true. |

#### Cluster C — Multi-provider configuration (unlocked by DW-115)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **C1. API key stored in the OS secret store, never in `config.json`** | Both leading BYOK desktop implementations do exactly this: **Zed** — *"Keys saved through Zed are stored in the system keychain, not in `settings.json`"*; **Obsidian Copilot** — keys go in the Obsidian keychain, *"not in the vault's `data.json`"*. The project's own config file is one the app explicitly invites the user to open in an editor. | **MEDIUM-HIGH** | Already the recorded human decision on DW-115(a). `package:dbus` is already a direct dependency, so `org.freedesktop.secrets` (gnome-keyring / KWallet, via the Secret Service D-Bus API) is reachable with no new package. Document the honest limit: an unlocked session keyring is readable by any process in that session — it defends against other accounts and offline access, not same-session malware. |
| **C2. Absence of a secret service degrades visibly, never silently** | A headless or minimal session may have no Secret Service at all. Silent failure here means the user gets `providerError` forever with no clue why. | **MEDIUM** | AD-12 / AD-19 shape: report degraded, do not block startup. Accept an environment variable (`OPENAI_API_KEY`) as the documented escape hatch — Zed does the same and gives env vars precedence over the keychain. **Do not** silently fall back to writing the key into `config.json` (see AF3). |
| **C3. Base URL is a setting, defaulting to the provider's canonical endpoint** | The whole point of "OpenAI-compatible". Zed exposes `api_url` per compatible provider; LM Studio's compatible surface is a base-URL override. It is also what makes B5 (offline path) real. | **LOW** | Already the recorded DW-115(b) decision. Validate it is a syntactically valid absolute URL at save time. Warn — do not block — on a plaintext `http://` host that is not loopback. |
| **C4. Failure states the user can act on: key-absent vs. key-rejected vs. endpoint-unreachable vs. model-unknown vs. unparseable-response** | With one zero-config provider, `providerError` was survivable. With a user-entered key, a user-entered URL and a user-entered model name, a single opaque error makes misconfiguration undebuggable — the user cannot tell a typo'd key from a down endpoint. | **MEDIUM** | The sharpest table-stakes gap this milestone opens. Today `CorrectionFailureKind` has four values (`timeout`, `providerUnavailable`, `providerError`, `malformedResponse`) and cannot distinguish "no key configured" from "endpoint refused connection". Widening the enum crosses a frozen port declaration — **human-gated, same class of decision as A3.** At minimum, `providerError` must carry an actionable message; distinct kinds are the better answer. |
| **C5. The inline error offers the remedy** — "Open settings" from a configuration failure | CAP-13 already puts errors and Retry inline. Retry is the wrong and only affordance for a missing key: retrying a config error just fails again. | **LOW** | Depends on C4 — you cannot route to settings until you can tell a config failure from a transport failure. |
| **C6. Provider settings validated at save, not only at first correction** | Zed and Obsidian Copilot both validate lazily, and the resulting confusion is a documented, filed complaint (`zed-industries/zed#26106`: *"Confusing 'No LLM provider selected' after adding Anthropic API key"*). The comparables set the floor here, and the floor is low enough to step over. | **LOW** | Minimal correct version: at save, check the key is non-empty for a provider that requires one, and the base URL parses. That alone removes the entire silent-misconfiguration class. A live round-trip check is separate — see D1. |
| **C7. Settings screen and config file stay in sync for provider fields** | Already mandated by CAP-8 (either surface) and CAP-12 (the two stay synced). New fields must not be the exception. | **LOW** | The recorded DW-115(c) decision: *"a user must never have to open a text editor to switch providers."* The key is the deliberate asymmetry — it is in the keychain and appears on the settings screen but never in the file. |

---

### Differentiators (Competitive Advantage)

**All of these are out of scope for this milestone.** They are listed so they are refused by name
rather than re-litigated. None is required for a reviewer or a user to accept the product.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **D1. "Test connection" — a live round-trip check with the entered key** | Neither Zed nor Obsidian Copilot ships one, and both collect bug reports about the confusion that follows. Shipping it is a genuine, cheap edge. | **LOW-MEDIUM** | **P2, defer.** C6's save-time validation captures most of the value at a fraction of the risk. Requires a cheap probe endpoint (`GET /v1/models`), which not every compatible server implements — so a failed probe must be a warning, never a block. |
| **D2. Pause / disable history recording (a session-local "don't record this")** | Well-precedented (CopyQ can disable monitoring; Maccy can clear on quit). Useful when pasting something genuinely sensitive. | **LOW** | **P2.** Only coherent once A3 exists. A cheaper 80% is A2's cap plus A3's clear. |
| **D3. One-click JSON export of history** | Local-first norm: readable formats plus built-in export; locked formats with no export are the named anti-pattern. | **MEDIUM** | **P2.** A4 (documented SQLite path) discharges most of this expectation — the data is already in an open, queryable format. A first-class export is a nicety, not the minimum bar. |
| **D4. Source exclusion list (never record corrections initiated from app X)** | The single most valued clipboard-manager privacy feature — Maccy honours the macOS "concealed" pasteboard flag so password-manager copies are never stored. | **HIGH** | **P3, and probably never.** X11/Wayland have no portable equivalent of the concealed flag, and on Wayland the source app is often unknowable. The honest substitute is A2 + A3 + D2. |
| **D5. Encryption at rest for history** | CopyQ ships encrypted items. Sounds like the obvious answer to A1. | **HIGH** | **P3 — and see AF6.** With an app-managed key this is security theatre. Only defensible with a user-supplied passphrase, which costs a prompt on every daemon start. |
| **D6. History browser UI** | Makes CAP-7 visible instead of merely durable. | **MEDIUM** | **P3.** Out of scope by the frozen SPEC — this is a new user-facing capability, which this milestone explicitly excludes. |

---

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **AF1. Silent provider fallback / cascade** ("if OpenAI fails, retry on Claude") | Looks like resilience; makes DW-115 feel more valuable. | Sends the user's text to a vendor they did not choose, silently — the precise failure the whole of Cluster B exists to prevent. A user who picked a local Ollama endpoint for privacy and gets silently failed over to a cloud API has been actively harmed. Already ruled out by the project's own rules. | Report `CorrectionFailed` with an actionable kind (C4) and let the human choose. Retry stays a user action. |
| **AF2. Cloud sync of correction history** | "Use it on my laptop too." | Converts a local-plaintext store into a hosted-plaintext store and drags in accounts, auth, conflict resolution, and a privacy policy — inverting the product's core value in one step. | The DB is a single SQLite file at a documented path (A4). Users who want sync already own Syncthing. |
| **AF3. "Convenient" plaintext key fallback in `config.json` when no Secret Service exists** | Makes C1 shippable on headless boxes without extra work. | Guarantees that the least-secure path becomes the common path — the first user with a stripped session writes their key to a `0644` file and every later user copies that recipe from a forum. It also silently defeats C1 for exactly the users who noticed the problem. | Degrade visibly (C2) and document the `OPENAI_API_KEY` environment variable as the supported escape hatch, following Zed's precedence order. |
| **AF4. Always-on typing monitoring / correct-as-you-type** | The obvious "next step" from a hotkey-summoned corrector; it is what Grammarly does. | It is also exactly why Grammarly is banned by law firms, tech companies and government agencies — the objection is never intent, it is *scope of access*. **The hotkey is this product's consent boundary and its main structural privacy advantage.** Removing it makes every table stake in Cluster B unwinnable. | Keep the hotkey as the explicit, per-invocation act of consent. Say so in the README; it is a selling point. |
| **AF5. Auto-replace — write the corrected text back into the focused app** | Removes the copy-paste step; the most-requested convenience in this category. | Requires synthetic input injection (impossible to do reliably under Wayland's security model), and turns a wrong or truncated LLM output into **silent destruction of the user's original text** — the exact failure the project's stated core value forbids. | Per-suggestion copy (CAP-11), which already ships. The user pastes; the user stays in control. |
| **AF6. SQLCipher / app-managed encryption of `history.sqlite`** | Feels like the strong version of A1. | The key must live somewhere the daemon can read unattended, so it lives next to the database, and an attacker who can read the DB can read the key. It buys nothing over `0600` while adding a native dependency and a migration. Note also that the `sqlcipher_flutter_libs 0.7.0+eol` package is a deliberately empty tombstone. | A1 (`0600` + `0700`) plus A2/A3. Point users at full-disk or `$HOME` encryption for the threat model that actually needs it. |
| **AF7. A bespoke "offline mode" with a bundled local model runtime** | Delivers B5 without depending on DW-115. | Ships and updates model weights, GPU detection, and a second inference stack inside a ~96 MB tray daemon — an order of magnitude more scope than the entire milestone. | B5 via C3: point the OpenAI-compatible base URL at the user's existing Ollama or LM Studio. Zero new code, and the runtime is theirs to manage. |
| **AF8. Redaction / PII scrubbing before sending** | "Strip the secrets so cloud use is safe." | Regex-grade redaction is unreliable by construction, and unreliable redaction is worse than none because it manufactures confidence that leads users to paste things they otherwise would not. | Honest disclosure (B1–B4) and a real local path (B5). Let the user decide what to paste. |
| **AF9. Multi-provider parallel query / "compare providers side by side"** | Natural-looking once two providers exist. | Multiplies cost, latency and — decisively — sends the same text to *two* vendors per invocation. Also collides with the three-register variant layout the panel already owns. | One provider per correction. The three registers are already the comparison surface. |
| **AF10. Anonymous usage telemetry, even opt-in** | "We need to know what fails." | A daemon holding user plaintext gains an outbound channel that is not the provider, and the no-phone-home claim (B6) becomes conditional and unverifiable at a glance. The cost of ever getting the payload filter wrong is unbounded. | stderr / journald logs the user can read, plus GitHub issues. B6 stays an absolute. |
| **AF11. A vendor-hosted key proxy or bundled free tier** | Removes the key-entry step entirely for new users. | Makes the project a data processor for its users' text, with all the retention, policy and liability that implies — and puts a server in the middle of a local-first product. | BYOK (C1–C3), which is what every comparable BYOK desktop tool does. |
| **AF12. Deleting closed entries from the deferred-work ledger** | Tidier file. | Explicitly forbidden by the ledger's append-only contract, and already the recorded cause of two logged violations (DW-13, DW-108). Deletion destroys the traceability the whole milestone's scope is derived from. | Flip `status:` to `done` with a date and add a `resolution:` line. |

---

## Feature Dependencies

```
A1 (0600 file perms)                         ── independent, ship first ──> [no dependencies]

A3 (clear history)
    └──requires──> [HUMAN GATE: widen CorrectionRepository port beyond frozen declaration]
                       └──unblocks──> A2 (retention cap)
                       └──unblocks──> D2 (pause recording)
                       └──eases─────> D3 (JSON export)

A5 (corrupt-db recovery) ──requires──> [contract decision: quarantine vs. refuse]

B2 (first-run consent) ──requires──> B1 (named-provider disclosure)
B1 ──requires──> C3 (base URL setting)     # disclosure must name the *effective* destination
B3 (destination indicator) ──requires──> C3

B5 (offline path) ──is a free consequence of──> C3 + C1
B5 ──conflicts──> AF7 (bundled local runtime)

DW-115 (second provider)
    ├──requires──> C1 (secret-storage port + Secret Service adapter)
    │                  └──requires──> C2 (visible degradation when absent)
    ├──requires──> C3 (base URL setting)
    ├──requires──> C7 (settings surface)
    └──forces────> C4 (failure taxonomy)
                       └──requires──> [HUMAN GATE: widen CorrectionFailureKind]
                       └──unblocks──> C5 ("Open settings" from the error)
                       └──unblocks──> C6 (save-time validation)
                                          └──enhances──> D1 (live test connection)

A6 (no-plaintext-in-logs gate) ──enhances──> B6 (no-telemetry claim)

AF1 (silent fallback) ──conflicts──> B1, B3, B5   # destination disclosure becomes a lie
AF4 (always-on monitoring) ──conflicts──> B2      # destroys the consent boundary
AF3 (plaintext key fallback) ──conflicts──> C1    # defeats the feature it appears to support
```

### Dependency Notes

- **A3 gates all of Cluster A except A1.** `CorrectionRepository` is `save` + `recent` only, and
  the port declaration is frozen — a settings-level "Clear history" has literally nothing to call.
  Retention, clearing, pause-recording and a first-class export all sit behind one human decision.
  **Get that decision made early; it is the milestone's longest pole in Cluster A.**
- **A1 depends on nothing.** It is the highest severity-to-effort item in the document and should
  not wait on the A3 gate. Ship it standalone.
- **C4 gates the usability of DW-115.** Ship the second provider with an opaque `providerError`
  and every misconfiguration becomes a support burden with no diagnostic path. Like A3 it crosses
  a frozen declaration, so it needs its decision made **before** the adapter is planned, not after.
- **B1 depends on C3, not the other way round.** A disclosure hardcoded to "Anthropic" is correct
  today and false the day a user sets a base URL. Build the disclosure to read the effective
  provider and endpoint from config from the start.
- **B5 is not a feature to build.** It is a consequence of C3 plus one paragraph of documentation.
  Budget zero engineering for it and count it as delivered.
- **AF1 conflicts with the entire disclosure cluster.** Any fallback or cascade makes B1/B3's
  destination statement untrue at exactly the moment it matters most.

---

## MVP Definition

Reframed for a hardening milestone: **"Launch With"** = ships in this milestone.

### Launch With (this milestone)

- [ ] **A1** — restrictive permissions on `history.sqlite` **and its `-wal`/`-shm`/`-journal` sidecars` — the plaintext of everything the user ever corrected is currently world-readable; no dependencies, closes DW-106
- [ ] **A3** — clear history (with the port-widening decision taken explicitly) — a plaintext store with no erase path is the finding a reviewer opens with
- [ ] **A2** — bounded history with a configurable cap — closes the growth half of DW-105; the whole comparable category ships this
- [ ] **A5** — corrupt-database recovery consistent with AD-13's config-file reasoning — a resident daemon must not be bricked by one bad file
- [ ] **A4** — documented, surfaced data location — cheap, and discharges most of the export expectation
- [ ] **A6** — architecture gate keeping plaintext out of logs — the invariant holds today; without a gate it silently stops holding
- [ ] **B1 + B3** — provider-derived, in-app disclosure naming the destination — the codified industry bar, and it becomes load-bearing the moment C3 lands
- [ ] **B2** — first-run consent before the first outbound send — a login-autostarted daemon that relays text with no prior screen is the shape that gets tools banned
- [ ] **B4 + B6** — documented retention/training posture per provider, and an explicit no-telemetry claim backed by a gate — documentation and one test
- [ ] **C1 + C2** — secret-storage port and Secret Service adapter, degrading visibly — the recorded DW-115(a) decision; both leading BYOK comparables do exactly this
- [ ] **C3 + C7** — base URL setting and provider fields on the settings screen — recorded DW-115(b)/(c); C3 also delivers B5 for free
- [ ] **C4 + C5** — actionable failure taxonomy and "Open settings" from a config error — without it, DW-115 ships an undebuggable product
- [ ] **C6** — save-time validation of key presence and URL syntax — removes the whole silent-misconfiguration class for near-zero cost

### Add After Validation (next milestone)

- [ ] **D1** (live Test connection) — add once real users report C6's static validation is insufficient
- [ ] **D2** (pause recording) — add if users ask for finer control than A2's cap plus A3's clear
- [ ] **D3** (JSON export) — add if A4's documented SQLite path proves insufficient in practice

### Future Consideration (v2+)

- [ ] **D6** (history browser) — new user-facing capability; the SPEC's 14 capabilities are frozen
- [ ] **D5** (at-rest encryption) — only with a user-supplied passphrase, and only if a threat model demands it that A1 does not already cover
- [ ] **D4** (source exclusion) — no portable Wayland mechanism exists; revisit only if the platform gains one

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| A1 — file permissions | HIGH | LOW | **P1** |
| A3 — clear history | HIGH | MEDIUM (human gate) | **P1** |
| A2 — retention cap | MEDIUM | MEDIUM | **P1** |
| A5 — corrupt-db recovery | MEDIUM | MEDIUM | **P1** |
| A4 — documented data location | MEDIUM | LOW | **P1** |
| A6 — no-plaintext-in-logs gate | HIGH | LOW | **P1** |
| B1 — named-provider disclosure | HIGH | LOW | **P1** |
| B2 — first-run consent | HIGH | MEDIUM | **P1** |
| B3 — destination indicator | MEDIUM | LOW | **P1** |
| B4 — retention/training posture doc | MEDIUM | LOW | **P1** |
| B5 — offline path | HIGH | LOW (free with C3) | **P1** |
| B6 — no-telemetry claim + gate | MEDIUM | LOW | **P1** |
| C1 — key in OS secret store | HIGH | MEDIUM-HIGH | **P1** |
| C2 — visible degradation, no secret service | MEDIUM | MEDIUM | **P1** |
| C3 — base URL setting | HIGH | LOW | **P1** |
| C4 — failure taxonomy | HIGH | MEDIUM (human gate) | **P1** |
| C5 — "Open settings" from error | MEDIUM | LOW | **P1** |
| C6 — save-time validation | MEDIUM | LOW | **P1** |
| C7 — provider fields on settings screen | HIGH | LOW | **P1** |
| D1 — live Test connection | MEDIUM | LOW-MEDIUM | P2 |
| D2 — pause recording | LOW | LOW | P2 |
| D3 — JSON export | LOW | MEDIUM | P2 |
| D6 — history browser | MEDIUM | MEDIUM | P3 |
| D5 — at-rest encryption | LOW | HIGH | P3 |
| D4 — source exclusion list | MEDIUM | HIGH | P3 |

**Priority key:** P1 = ships this milestone · P2 = next milestone · P3 = deferred indefinitely

---

## Competitor Feature Analysis

| Feature | Maccy / CopyQ / GPaste (clipboard managers) | LanguageTool (text checker, desktop + self-host) | Zed / Obsidian Copilot (BYOK desktop) | Grammarly (the cautionary case) | Our Approach |
|---------|--------------------------------------------|--------------------------------------------------|---------------------------------------|--------------------------------|--------------|
| **History cap** | Configurable size; old entries roll off by default | N/A (does not retain) | N/A | Server-side | **A2** — configurable cap, sane default |
| **Clear history** | Universal; plus optional clear-on-quit | N/A | N/A | Account-level deletion | **A3** — explicit clear; clear-on-quit deferred (D2) |
| **Exclude sensitive sources** | Maccy honours the macOS *concealed* pasteboard flag (1Password/Bitwarden never recorded); app ignore-lists | N/A | N/A | None — this is the core objection | **D4 deferred** — no portable Wayland equivalent; substitute A2 + A3 |
| **At-rest protection** | CopyQ encrypted items (opt-in, manual) | N/A | N/A | N/A | **A1** — `0600`/`0700`; **AF6** rejects app-managed encryption |
| **Data stays local** | Yes, by default | Optional: self-hosted server, nothing leaves the machine | Local vault / local project | No — everything typed goes to the server | **B5** — local endpoint via C3's base URL |
| **Third-party disclosure** | N/A | Privacy notice on first use, shown again for Premium (different server), and a distinct message when a custom local server is set | Provider named in settings; no first-run consent gate | Privacy page; scope is the complaint | **B1–B3** — named provider, first-run consent, effective-destination indicator (LanguageTool's per-destination messaging is the model) |
| **Key storage** | N/A | N/A | **Zed:** system keychain, *not* `settings.json`. **Copilot:** Obsidian keychain, *not* `data.json`. Env var takes precedence (Zed) | N/A | **C1/C2** — Secret Service via `package:dbus`; env var as the documented escape hatch |
| **Custom base URL** | N/A | Yes (local server in options) | Yes — `api_url` per OpenAI-compatible provider; "Add Provider" in the UI | N/A | **C3** — the same, defaulting to the canonical endpoint |
| **Key validation** | N/A | N/A | **Neither validates at entry** — lazy failure at first request; a filed, confusing bug (`zed-industries/zed#26106`) | N/A | **C6** at save (beats both); **D1** live probe deferred |
| **Access scope** | Clipboard only, on copy | Text submitted for checking | Explicit invocation | Everything typed, continuously → enterprise bans | **AF4** — hotkey stays the consent boundary |
| **Telemetry** | None / minimal | Configurable | Varies | Extensive | **B6** — none, claimed and gated |

---

## Sources

**Primary (HIGH confidence):**
- Anthropic — *API and data retention*, platform.claude.com — "Retained data is never used for model training without your express permission"; ZDR eligibility per endpoint (`/v1/messages` eligible; code-execution containers not, up to 30 days)
- Zed — *Use API Access* — keys stored in the system keychain not `settings.json`; env vars take precedence; `openai_compatible.<name>.api_url` custom endpoints; no documented entry-time validation

**Secondary, cross-checked (MEDIUM confidence):**
- OpenAI — data controls / enterprise privacy: up to 30-day API retention for abuse monitoring, no training on API data by default, ZDR for eligible endpoints
- LanguageTool — embedded HTTP server / self-hosting docs; browser-addon privacy-notice and custom-server consent behaviour
- Maccy, CopyQ, GPaste — history-size, clear, ignore-list, concealed-flag and encrypted-item behaviours (vendor docs and category guides)
- Apple App Store guideline 5.1.2(i) third-party AI consent rule — named provider, specific data, stated purpose, contextual in-app opt-in
- Grammarly privacy criticism and enterprise-ban coverage — scope-of-access as the objection, not intent
- libsecret / Secret Service (`org.freedesktop.secrets`), GNOME Keyring / KWallet, PAM unlock, `~/.local/share/keyrings` — ArchWiki and Flatpak secrets-management guidance, including the unlocked-session caveat
- `zed-industries/zed#26106` — lazy key validation producing "No LLM provider selected" confusion
- Local-first data-portability and zero-telemetry norms (Super Productivity, Obsidian, Logseq comparisons)

**Project-internal (HIGH confidence — read directly):**
- `.planning/PROJECT.md`; `.planning/codebase/CONCERNS.md`, `INTEGRATIONS.md`
- `_bmad-output/implementation-artifacts/deferred-work.md` — DW-105 (unbounded/unclearable history), DW-106 (umask permissions), the corrupt-database entry, DW-115 (second provider, with the three recorded human decisions), DW-13/DW-108 (append-only violations)
- `lib/src/domain/history/`, `lib/src/domain/config/provider_config.dart`, `lib/src/domain/correction/correction_event.dart`, `lib/src/infrastructure/config/json_config_store.dart`

**Confidence caveats:**
- The exact current default log-retention window for the Claude API (7 vs. 30 days, post-Sept-2025) is **secondary-source only** and was not confirmed on the primary page fetched. Cite the training commitment and ZDR availability, which are primary; date any retention-window number and link rather than assert.
- The "minimum bar" for **export** (D3) is inference from local-first norms rather than a directly evidenced rejection criterion — hence its P2 classification rather than table stakes.
- No evidence was found of a Linux-specific review gate equivalent to Apple's 5.1.2(i). Cluster B is grounded in the cross-platform norm and in LanguageTool's shipping behaviour, not in a rule this project is legally bound by.

---
*Feature research for: local-first LLM text-correction desktop daemon (hardening milestone)*
*Researched: 2026-08-30*
