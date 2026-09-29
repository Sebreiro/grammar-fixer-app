# Project Research Summary

**Project:** Hotkey Grammar Corrector — Ledger Hardening milestone
**Domain:** Linux tray-resident Flutter/Dart daemon (GTK3, X11 + Wayland XDG portal) with pluggable LLM correction providers and local plaintext SQLite history
**Researched:** 2026-08-30
**Confidence:** MEDIUM-HIGH

> **Read this as a sequencing document, not a scoping one.** The 88 v1 requirements already
> exist in `REQUIREMENTS.md`, derived one-to-one from open entries in the BMAD deferred-work
> ledger. Nothing below adds scope. Its job is to tell the roadmapper **what order the existing
> requirements can safely be built in, which clusters block which, and where a phase must stop
> and ask a human.**

## Executive Summary

This is a **hardening milestone over a shipped product**, not a build. The MVP is done: 11 BMAD
stories closed, all 14 frozen SPEC capabilities implemented on both display servers, a four-ring
hexagonal architecture with 19 frozen architecture decisions, and a dependency set that all four
research passes independently found healthy (nothing EOL, discontinued, retracted or superseded;
`hotkey_manager` is stale but binds a frozen C API on the X11 path only). The correct posture is
therefore *containment and evidence*, not renewal. STACK adds exactly three things and only
because one requirement (PROVIDER-02 / DW-115) demands them; ARCHITECTURE proposes no new ring
and no new paradigm, only placement decisions inside the existing four; FEATURES exists mostly to
name things that must be **refused** so they stop being re-proposed.

The single most consequential finding is about **evidence, not code**: `.github/workflows/ci.yml`
carries `STATUS: NEVER EXECUTED` in its own header, two test suites bind process-scoped resources
whose release is not synchronous with teardown, and the milestone's entire closure model is
"a mutation killed a test." PITFALLS 14/15/16 show that claim is unsound when drawn from an
unsound gate — under `zsh` an unquoted multi-directory `$SCOPE` is not word-split, so the gate
silently runs nothing and every mutation reports the same fabricated count. **Every other phase's
evidence is only as good as the gate that produced it, so the gate cluster (GATE-01…GATE-13) must
come first and nothing downstream should claim closure before it does.** The rule that follows:
every closure carries a negative control — delete the fix, show the *named* rows go red against a
*scoped* command whose unmutated baseline is verified at 0, restore.

The risks are concentrated in three places. First, **three fixes want to edit a verbatim-frozen
port declaration** (widening `CorrectionFailureKind`, adding a synchronous accessor to
`GlobalHotkey`, extending `CorrectionRepository` beyond `save` + `recent`) — these are human
decisions, not engineering tasks, and ARCHITECTURE and FEATURES actively *disagree* on one of
them (see Cross-Document Conflicts). Second, **the most fragile file in the tree — the ~1307-line
Wayland portal adapter — is touched by the hotkey cluster, the settings fan-out cluster and the
packaging decision**; taking three separate passes over it is how a hardening milestone
manufactures a regression nobody can bisect. Third, **a large fraction of what FEATURES calls
table stakes is not in v1 scope at all** — the data-safety cluster is `parked` in the ledger and
therefore absent from the 88 requirements. That is a deliberate scoping decision, and the
roadmapper must respect it rather than reconcile it.

## Key Findings

### Recommended Stack

The pinned set stays. Flutter 3.44.8 / Dart 3.12.2, Riverpod 3.4.2, Drift 2.34.3, sqlite3,
`hotkey_manager`, `tray_manager`, `window_manager`, `dbus`, and the Python `claude-agent-sdk`
sidecar were each checked against the pub.dev registry API and none is EOL, discontinued,
retracted or superseded. STACK's additions are scoped to exactly the surface PROVIDER-02 opens:
the second provider client, the credential that provider introduces, and the packaging decision
(ARCH-02 / DW-89) that is currently open.

**Core additions (only for PROVIDER-02 and ARCH-02):**
- **`openai_dart 8.1.0`** — the OpenAI-compatible correction provider. Chosen because it is the
  only Dart OpenAI client shipping an explicit per-stream abort primitive
  (`createStream(request, {abortTrigger})`), the exact property `CorrectionProvider`'s
  cancellable-stream contract depends on. Pure Dart, no plugin, no native build. A configurable
  `baseUrl` makes "OpenAI-compatible" a config value rather than a fork. Verified by reading
  upstream source, not the README.
- **`flutter_secure_storage 11.0.0`** — the API key at rest, behind a domain `SecretStore` port.
  The Linux impl is a libsecret client over the Secret Service, i.e. the correct XDG mechanism.
  v11's Linux fixes are exactly this daemon's edge cases (missing default keyring; fail closed on
  orphaned keyring data).
- **`fastforge 0.6.12`** — builds `.deb` + AppImage from one config; the maintained successor to
  `flutter_distributor`, which pub.dev now marks **discontinued**.

**Two STACK conclusions that are sequencing constraints, not library choices:**
- **Keep the Python sidecar this milestone.** Replacing the only shipped provider in the same
  milestone that adds the first alternative would ship a milestone with zero providers of proven
  provenance. Revisit only when packaging forces it.
- **`.deb` + AppImage; defer Flatpak; reject Snap.** This is not a distribution detail — it
  *selects the portal handshake*. `Registry.Register` is refused for sandboxed callers, so a
  Flatpak build must delete the AD-11 call, changing the fragile portal adapter's identity
  handshake. That is the ARCH-02 decision, and it should be recorded before, not after, anything
  else touches that file.

Full detail: `.planning/research/STACK.md`.

### Expected Features

FEATURES is deliberately lopsided: table stakes and anti-features carry the weight, and the
differentiators section exists mainly to name refusals. **Critical scoping caveat for the
roadmapper:** FEATURES researched the *domain norm* for a local-plaintext-plus-cloud-API tool,
and much of what it identifies as table stakes maps to ledger entries that are `parked`
(DW-100, DW-104, DW-105, DW-106) and therefore **not among the 88 v1 requirements**. Treat those
rows as evidence for a future un-parking decision, not as scope.

**Must have — and actually in v1 scope:**
- A second, OpenAI-compatible provider so CAP-8's provider choice has something to choose between
  (PROVIDER-02 / DW-115), with its three recorded human decisions: key in the OS secret store and
  never in `config.json`; base URL as a setting; provider fields on the settings screen.
- An actionable failure taxonomy for that provider — with one opaque `providerError`, a user
  cannot tell a typo'd key from a down endpoint. **Contested** — see Cross-Document Conflicts.
- Per-provider, provider-*derived* destination disclosure. A disclosure hardcoded to "Anthropic"
  is correct today and false the day a user sets a base URL.

**Must have — but NOT in v1 (parked; recorded so the exclusion is deliberate):**
- `0600`/`0700` history permissions including the `-wal`/`-shm`/`-journal` sidecars (DW-106).
  FEATURES rates this the highest severity-to-effort item in the whole document and it depends on
  nothing. If any parked entry is ever un-parked, this is the one.
- Bounded/clearable history (DW-104) and corrupt-database recovery (DW-100).

**Free consequence, budget zero engineering:** a genuinely offline path falls out of the base-URL
setting pointed at Ollama or LM Studio. Do not build a bespoke offline mode.

**Refuse by name (so they stop being re-litigated):** silent provider fallback/cascade (makes the
destination disclosure a lie), always-on typing monitoring (the hotkey *is* this product's
consent boundary), auto-replace into the focused app, app-managed encryption of the history DB,
PII scrubbing, telemetry of any kind, a plaintext key fallback in `config.json`, and — explicitly
— deleting closed ledger entries, which is the append-only violation LEDGER-01 exists to fix.

Full detail: `.planning/research/FEATURES.md`.

### Architecture Approach

The architecture is frozen and correct; every recommendation is a placement decision inside the
existing four rings. Three constraints bound every answer: `domain/` imports only `dart:*` (so
`BehaviorSubject`, `ValueStream` and every packaged current-value-stream type is unavailable *in
a port declaration* — the hand-rolled accessor-plus-stream pair is the only conformant shape);
several declarations are frozen verbatim; and AD-15 requires that adding a provider not change
`domain/`, `application/` or `ui/`. DW-115's ratified decisions each want one of those — resolved
by arguing they are *platform and presentation* seams, not provider seams.

**Major components / patterns the roadmapper should treat as phase boundaries:**
1. **Contract-suite harness** — one suite facing both the fake and the real adapter, over a
   double one level down. Adapter #2's only claim to correctness is "it behaves like the port
   says"; building the suite *after* the adapter is how a contract gets weakened to fit what
   already exists.
2. **Subscription lifecycle rule** — `onDone` is not optional on a long-lived port subscription
   (seven sites), plus bounded teardown with one injected bound reused at every site.
3. **Port state-shape rule** — accessor + changes. Free on the *new* `SecretStore` port; on
   `GlobalHotkey` it is a frozen edit and human-gated.
4. **`SecretStore` port + adapter**, then **the OpenAI-compatible adapter** (one file, one config
   entry, one map entry — never a `switch (providerId)` below the composition root), then the
   **settings surface**, then **runtime provider re-resolution**.

Full detail: `.planning/research/ARCHITECTURE.md`.

### Critical Pitfalls

1. **A CI workflow that has never executed (Pitfall 14).** `ci.yml` says so in its own header.
   Anything that depends on a green gate is downstream of proving the gate runs at all. First.
2. **Mutation claims drawn from an unsound gate (Pitfall 15).** Two suites bind process-scoped
   resources (an abstract-namespace socket; an in-process `DBusServer` on a unix path) whose
   release is not synchronous with teardown, so **a false red reads as a killed mutation**. Run
   mutation checks against a *scoped* command, and verify the unmutated baseline fails 0 rows
   before believing anything. Serialise mutation-running review layers; back the working tree up
   to scratch first.
3. **Closing a ledger entry with a fix whose test would not notice its removal (Pitfall 16).**
   The signature hardening-milestone failure. A `status: done` is trusted more than an `open`, so
   a bad closure makes the ledger actively lie. Every closure carries a negative control naming
   which rows go red. Beware **contingent** closures (DW-84 on DW-68, DW-51 on DW-29, DW-27 on
   there being no second focusable window) — descoping the dependency silently un-closes them.
4. **Displaying the requested binding as if it were the effective one (Wayland).** Under the
   portal the app is a supplicant, not an owner. Never echo `preferred_trigger` as fact; render
   `trigger_description` verbatim as the desktop's own wording and never re-parse it; refresh
   from three sources (`BindShortcuts` reply, `ListShortcuts`, every `ShortcutsChanged`).
5. **Three separate passes over the same fragile code.** PITFALLS explicitly groups the database
   open-path items, groups the process/teardown items, and warns that doing them as separate
   passes means repeated regression risk on one file. The same logic applies with more force to
   the Wayland portal adapter, which the hotkey, settings-fan-out and packaging work all touch.

Full detail: `.planning/research/PITFALLS.md`.

## Implications for Roadmap

The four documents converge on a **topical clustering with one hard ordering constraint at the
front and one at the back**. PITFALLS supplies phase labels (P-GATE, P-DATA, P-HOTKEY, P-PANEL,
P-EXIT, P-PROVIDER); ARCHITECTURE supplies a numbered build order inside the provider work. The
suggested phases below map the **existing 88 requirements** onto that structure. Requirement
counts are given so the roadmapper can judge phase size.

### Phase 1: Gate reality
**Rationale:** PITFALLS 14/15/16 are unanimous and unhedged — every later phase's evidence is
only as good as the gate that produced it, and the gate has never run. This is the only phase
whose position is not a judgement call.
**Delivers:** the first real execution of `ci.yml` and fixes for what it finds; every orphan test
directory named in a gate; a reproducible 0-failure baseline; the negative-control discipline
adopted as the project's closure standard.
**Covers:** GATE-01…GATE-13 (13 requirements), plus LEDGER-01 (append-only contract), which is
the same integrity concern expressed in the ledger rather than the suite.
**Avoids:** Pitfalls 14, 15, 16.
**Note:** GATE-02, GATE-10, GATE-11 are marked `⚠ unconfirmed` — three idle runs passed clean,
which cannot disprove a flake its own entry describes as load-dependent. Plan them as shape-fixes
(a teardown that waits for release, or collapsing the two socket-binding suites), not as
"reproduce then fix." Size this phase generously: a first CI run finds unknown work by definition.

### Phase 2: Hotkey truth (X11 grab result, Wayland read-back, visible degradation)
**Rationale:** the largest cluster of user-visible correctness defects, and it owns the most
fragile file. Doing it as one pass rather than three is the explicit PITFALLS recommendation.
**Delivers:** a grab that reports failure when it fails; a compositor binding read back rather
than echoed; a missing `libkeybinder` degrading visibly instead of preventing startup.
**Covers:** HOTKEY-01…HOTKEY-12 (12 requirements).
**Avoids:** Pitfalls 1, 2, 3.
**★ Contains a human gate:** HOTKEY-06 (a synchronous current-registration accessor on
`GlobalHotkey`) edits AD-9's verbatim-frozen block. Surface this at the top of the phase, before
any implementation task. ARCHITECTURE recommends doing it; ratification is the human's.

### Phase 3: Settings & tray fan-out
**Rationale:** immediately downstream of Phase 2 — AD-12's second consumer is the tray, and the
"after the fact" refresh cases are what expose the accessor gap Phase 2 gates. Sequencing it
adjacent to the hotkey work means one pass over the shared surface rather than two.
**Delivers:** hotkey availability reaching *both* AD-12 consumers on every transition rather than
only at startup; the bind-before-write divergence closed; preset changes taking effect without a
daemon restart.
**Covers:** SETTINGS-01…SETTINGS-10 (10 requirements) and CONFIG-01.
**Dependency note:** SETTINGS-02 (DW-68) is the entry DW-84's closure is **contingent** on —
descoping it silently un-closes another entry.

### Phase 4: Panel & correction UI
**Rationale:** the largest cluster (19), and largely independent of Phases 2–3 — it owns the
panel/window reconciliation surface rather than the hotkey surface, so it is the best candidate
for parallelisation. Several items are cheap and self-contained (copy feedback, clipboard
serialisation, non-QWERTY digit selection).
**Delivers:** panel geometry actually chosen rather than inherited; blur/focus/present races
closed so a click-away plus a summon cannot discard the user's typed text; selection affordances
that work for pointer and non-QWERTY users.
**Covers:** PANEL-01…PANEL-19 (19 requirements).
**Avoids:** Pitfalls 11, 12, 13.

### Phase 5: Startup, abort & teardown discipline
**Rationale:** ARCHITECTURE's build order puts the bounded-teardown policy and the `onDone` rule
**before** the second provider, because an HTTP stream has more ways to end silently than a
subprocess does, and a pooled client is a new isolate-alive resource of exactly the class that
already produced two ledger entries. Landing the policy first makes the adapter's close one more
step in an existing bounded sequence rather than a new invention.
**Delivers:** one injected teardown bound reused at every site; an abort path that cannot leave a
resident windowless process; `onDone` adopted as a rule across all seven subscription sites.
**Covers:** STARTUP-01…STARTUP-05 (5 requirements).
**Avoids:** Pitfalls 9, 10, 13.

### Phase 6: Second correction provider
**Rationale:** ARCHITECTURE's build order is explicit that the contract suite, the `onDone` rule
and the bounded-teardown policy must land *before* adapter #2, and that the `SecretStore` port
must exist before it, because "read the key from settings for now" is exactly the shortcut that
survives to production. This is why the milestone's only feature-shaped requirement is late.
**Delivers:** `SecretStore` port + adapter; the `openai_dart` adapter contained under
`infrastructure/correction/openai_compatible/`; the register parser hoisted to `shared/` and fed
by both adapters; the failure-mapping table published; a contract run against a loopback endpoint.
**Covers:** PROVIDER-01, PROVIDER-02, PROVIDER-03 (3 requirements).
**Uses:** `openai_dart 8.1.0`, `flutter_secure_storage 11.0.0`.
**★ Contains a contested human gate:** whether `CorrectionFailureKind` gains a fifth member. See
Cross-Document Conflicts — surface it before planning the adapter, not after.

### Phase 7: Architecture & spine currency, runtime observation, deferred reviews
**Rationale:** documentation-and-evidence work that is cheap, largely independent, and mostly
*describes* what the earlier phases changed — so it is honest only once they have landed. The
runtime-observation items are open by construction (they assert an observation was never made)
and can only be closed on a real desktop session.
**Delivers:** the spine reconciled with shipped code; a recorded packaging decision; the
runtime-observation checklist actually performed and registered; the seven damping-capped review
passes run.
**Covers:** ARCH-01…ARCH-09 (9), RUNTIME-01…RUNTIME-08 (8), REVIEW-01…REVIEW-07 (7) —
24 requirements.
**★ Contains a human gate:** ARCH-02 (DW-89, packaging format). STACK recommends `.deb` +
AppImage with Flatpak deferred; the decision is the human's, and it retroactively constrains the
AD-11 portal handshake — so if it can be taken *earlier* than this phase, it should be.
**Scheduling note:** the RUNTIME cluster needs a real X/Wayland session. If none is available,
plan it as build-plus-owed-observation with every claim explicitly on the checklist — recording
observations as done by sweep bundle is the exact defect FLAT-25 exists to report.

### Phase Ordering Rationale

- **The gate is first and this is not negotiable.** All four documents agree; PITFALLS states it
  as a hard precondition and ARCHITECTURE independently puts the contract-suite harness at
  position [1] of its build order for the same reason.
- **The provider is late, not early**, despite being the milestone's only feature-shaped
  requirement. Four prerequisites gate it (contract suite, `onDone` rule, bounded teardown,
  `SecretStore`), three of which are separate requirement clusters.
- **Group by the file that is touched, not by the ledger id.** PITFALLS groups the database
  open-path items and the process/teardown items explicitly; the same reasoning applies to the
  Wayland portal adapter, which the hotkey and settings clusters share.
- **Cheap-and-independent early wins** exist mostly in the panel cluster (clipboard
  serialisation, copy feedback, non-QWERTY digit selection) and in the documentation-only ARCH
  items. The gate cluster is cheap only in code and expensive in discovery.
- **The three human gates are the schedule's real risk**, not any implementation. Each must be
  surfaced at the top of its phase, and the packaging one should be pulled forward if possible.

### Cross-Document Conflicts (resolve before planning the affected phase)

1. **`CorrectionFailureKind` — widen or not.** FEATURES (C4) calls the four-value enum "the
   sharpest table-stakes gap this milestone opens" and argues distinct kinds are the better
   answer. ARCHITECTURE (D6) recommends *against* it: widening forces a UI change, a schema
   change (`failure_kind` is persisted by name) and a spine renegotiation, to say something an
   actionable message can say — and proposes mapping into the existing four via a published
   failure table. **Both agree it is human-gated; they disagree on the answer.** Put the choice
   in front of a human before Phase 6 is planned. The fallback that satisfies both: at minimum,
   `providerError` must carry an actionable message.
2. **Data safety — table stakes vs. out of scope.** FEATURES and PITFALLS both treat history
   permissions, retention/clearing and corrupt-DB recovery as high priority; the ledger has those
   entries `parked`, so REQUIREMENTS excludes them from v1 and PITFALLS' P-DATA label maps to
   **no v1 requirement at all**. This is a real scoping decision, not an oversight. The
   roadmapper should not create a data-safety phase; it should note that un-parking DW-106 alone
   would be the highest severity-to-effort addition available, and leave that to a human.
3. **Where the documents agree, they agree hard.** Gate-first ordering, provider-last ordering,
   no `switch (providerId)` below the composition root, no retry/fallback inside an adapter, and
   no plaintext credential anywhere are each asserted independently by two or more documents.

### Research-Surfaced, Unfiled — NOT in scope

**Recorded here for a human to decide whether to file. Do not silently promote into scope.**

FEATURES surfaced a gap that has **no ledger entry and therefore no requirement**: once a second,
key-bearing provider ships, `CorrectionFailureKind` cannot distinguish *"no key configured"* from
*"endpoint refused connection"*. With one zero-config provider this was survivable; with a
user-entered key, a user-entered base URL and a user-entered model name it makes every
misconfiguration undebuggable — and it makes Retry, the only affordance CAP-13 offers, the wrong
one, since retrying a config error just fails again. This overlaps Conflict 1 but is strictly
broader than it: even if the enum is not widened, the *diagnostic* gap remains.

**Status: research-surfaced, unfiled.** If a human wants it, the correct action is to file a new
ledger entry so it enters scope through the same provenance as every other requirement.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 6 (second provider):** per-server compatibility variance. "OpenAI-compatible" hides real
  divergence in streaming framing, error shapes and structured-output support across OpenAI /
  OpenRouter / Groq / Together / Ollama / LM Studio. STACK and ARCHITECTURE flag it
  independently. Gate acceptance on **two distinct endpoints**.
- **Phase 6 (secret storage):** Secret Service behaviour across gnome-keyring vs KWallet vs no
  service at all, plus headless CI (needs `dbus-launch` + `gnome-keyring-daemon`), plus the
  Flatpak variant, which changes the mechanism entirely.
- **Phase 7 (ARCH-02 packaging):** the portal-identity constraint chain is subtle and decides
  whether AD-11's handshake survives. STACK researched it thoroughly; the *decision* still needs a
  human with the deferral criteria in front of them.

Phases with standard patterns (skip `--research-phase`):
- **Phase 1 (gate):** the failure modes are fully characterised and repo-specific; this needs
  discipline, not research.
- **Phases 2–5:** standard patterns applied to a codebase that already contains its own
  precedents. ARCHITECTURE says so explicitly of its items [1]–[4].

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH on versions and APIs; MEDIUM on packaging | Every version claim verified against the pub.dev registry API; behavioural claims verified by reading upstream source directly, not READMEs. The packaging *ranking* is a judgement over verified constraints. |
| Features | MEDIUM | Table-stakes claims rest on cross-checked vendor docs and comparable products; two claims (export as a minimum bar; the Claude retention *window*) are inference or secondary-source only and are flagged in place. No Linux-specific review gate equivalent to Apple's rule was found. |
| Architecture | MEDIUM-HIGH | Repo-grounded claims verified by direct file read with file:line quotes; ecosystem claims cross-checked across two or more sources. Governed by the frozen spine document. |
| Pitfalls | MEDIUM-HIGH | Every pitfall corroborated by an upstream primary source *and* verified against this repo's code or its ledger; the few with only one of the two are marked in place. |

**Overall confidence:** MEDIUM-HIGH. The requirements themselves are the strongest artifact —
85 of 88 were re-verified against current code rather than trusted from the ledger.

### Gaps to Address

- **The three `⚠ unconfirmed` flake requirements (GATE-02, GATE-10, GATE-11).** Three idle runs
  passed clean at 946 passed / 2 skipped, establishing the 0-failure baseline, but cannot
  disprove a load-dependent flake. Handle by fixing the *shape* (synchronous resource release, or
  collapsing the two socket-binding suites) rather than trying to reproduce.
- **The three frozen-declaration edits.** Two are recommended by research (the `GlobalHotkey`
  accessor; and, from FEATURES, `CorrectionRepository` beyond `save` + `recent` — though the
  latter serves parked entries only); one is contested (`CorrectionFailureKind`). None should be
  planned until a human ratifies. Surface each at the top of its phase.
- **Runtime observations cannot be closed from a container.** FLAT-25, FLAT-29, FLAT-35, FLAT-40
  and FLAT-42 are open by construction until someone performs and records the observation. If no
  real session is available, plan them as owed observations with an explicit checklist mechanism.
- **Contingent closures.** DW-84 (on DW-68), DW-51 (on DW-29) and DW-27 (on there being no second
  focusable window) silently un-close if their dependency is descoped. Check before any descope.
- **Packaging decision timing.** ARCH-02 sits in the last suggested phase but constrains the
  portal adapter that Phase 2 rewrites. If it can be decided earlier, it should be.

## Sources

Aggregated from the four research documents; see each for the full list and per-claim tiering.

### Primary (HIGH confidence)
- **Local codebase, read directly** — `lib/**`, `test/**`, `pubspec.yaml`/`pubspec.lock`,
  `wayland_portal_global_hotkey.dart`, `provider_registry.dart`,
  `register_tagged_stream_parser.dart`, `json_config_store.dart`, `linux/packaging/*.desktop`,
  `linux/runner/my_application.cc`, `.github/workflows/ci.yml`.
- **`ARCHITECTURE-SPINE.md` AD-1…AD-19** and the frozen SPEC — governing documents for every
  frozen-declaration and import-direction claim.
- **`_bmad-output/implementation-artifacts/deferred-work.md`** — provenance of all 88
  requirements, with the standing caveat that ledger status is hand-maintained and was re-verified
  by reading code.
- **pub.dev registry API** — authoritative version, publish date, `isDiscontinued`, `replacedBy`,
  `retracted`, pub points and download counts for the full pinned set plus every candidate.
- **`davidmigloz/ai_clients_dart` upstream source** — per-stream `http.Client`, `abortTrigger`,
  `controller.onCancel` teardown; read directly rather than via documentation.
- **XDG Desktop Portal specs** — `GlobalShortcuts` (v2), `host.portal.Registry`, `portal.Secret`.
- **Anthropic API data-retention documentation**; **Zed** BYOK key-storage documentation.

### Secondary (MEDIUM confidence)
- OpenAI data-controls / enterprise-privacy documentation (retention window, training posture).
- LanguageTool self-hosting and custom-server consent behaviour; Maccy / CopyQ / GPaste history
  and privacy behaviours; Obsidian Copilot key storage; `zed-industries/zed#26106`.
- `flutter_secure_storage` and `leanflutter/hotkey_manager` upstream changelogs and repo activity.
- Ports-and-adapters literature (Cockburn), anti-corruption-layer guidance, verified-fakes and
  contract-suite writing.
- GNOME maintainer-adjacent writing on portals with unsandboxed apps.

### Tertiary (LOW confidence — not load-bearing for any recommendation)
- Web-search synthesis on Flatpak/Snap confinement, Flutter Linux deployment guidance, community
  Flutter Flatpak tooling, headless-CI keyring setup. Used only where corroborated by a primary
  artifact above.

---
*Research completed: 2026-08-30*
*Ready for roadmap: yes*
