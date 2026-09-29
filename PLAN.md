# Implementation Roadmap — Hotkey Grammar Corrector

A Flutter (Linux-first) tray-resident app: hotkey → panel with clipboard text → LLM corrects grammar into native-speaker English. Pluggable LLM providers (default: Claude Agent SDK on `claude-sonnet-5`), SQLite history, multiple suggestions.

**Source of truth — the SPEC, not this file:**
- **Contract:** `_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md` + its two companions
- Background: `_bmad-output/brainstorming/brainstorm-hotkey-grammar-corrector-2026-07-26/brainstorm-intent.md` (synced to the spec)
- Session log: `_bmad-output/brainstorming/brainstorm-hotkey-grammar-corrector-2026-07-26/.memlog.md`

**Rule: run each step in a fresh Claude session.** Check the box when done.

---

## Step 0 — Lock the WHAT (spec) ✅
- [x] Run: `/bmad-spec _bmad-output/brainstorming/brainstorm-hotkey-grammar-corrector-2026-07-26/brainstorm-intent.md`
- Output: `_bmad-output/specs/spec-hotkey-grammar-corrector/`
  - `SPEC.md` — 13 capabilities, 11 constraints, 9 non-goals. The contract everything else derives from.
  - `llm-provider-contract.md` — companion; the 5 abstraction principles, the default provider, `suggestions[]`-as-history-schema.
  - `risks.md` — companion; Wayland hotkeys, X11 primary selection, Flutter resident RAM.
- ✅ **All open questions closed.** No blockers into Step 2. Note CAP-6 is a retired id (it held the diff view) — the gap in numbering is intentional, don't reuse it.
- Note: bmad-spec is the spec's only writer — update it by re-running `/bmad-spec` on that folder, never by hand-editing `SPEC.md`.

## Step 1 — AGENTS.md + coding rules ✅
- [x] Ask: *"Create AGENTS.md with coding rules for this project — read PLAN.md and the intent doc first."*
- Rules to include: SOLID, small functions, single responsibility for classes/functions, use abstractions (provider interface!), best Flutter/Dart architecture & style practices, code readable by humans first.

## Step 2 — Implementation plan (architecture) ✅
- [x] Run: `/bmad-architecture` (quick spine mode; feed it SPEC.md **+ both companions** + AGENTS.md)
- Output: `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
  — hexagonal, **19 ADs**: provider port signature fixed verbatim (AD-2), layering + import lint (AD-1), folder structure (Structural Seed), SQLite schema (AD-7), hotkey port spanning X11 + Wayland portal (AD-9…AD-12).
- ✅ Now an **adopted companion** of SPEC.md, so AD ids are citable downstream. Do not hand-edit the spine from another skill — re-run `/bmad-architecture` (its `.memlog.md` is the authority).
- ⚠️ **SPEC.md was updated by this step:** CAP-12's success criterion is now split per display server. See "Ratified divergence" below.

## Step 3 — Split to tasks
- [ ] Run: `/bmad-create-epics-and-stories`, then `/bmad-sprint-planning`
- Output: epics → ordered implementable stories → sprint plan.

## Step 4 — Implement (repeat per story)
- [ ] Cycle: `/bmad-create-story` → `/bmad-dev-story` → `/bmad-code-review` until sprint plan is done.
- Alternative fast lane (allowed for this solo project): `/bmad-quick-dev` after Steps 0–1 instead of Steps 2–4.

---

## Decisions already made (do not re-litigate)
- Stack: **Flutter desktop**, Linux first (accepts ~96MB standing RAM). No Electron.
- Resident **tray daemon**; panel window pre-built and hidden, hotkey only toggles its visibility (<100ms target).
- Panel is an **editable micro-editor**: user can tweak/add text; shows **multiple suggestions** (register variants: formal/casual/shorter picked via 1/2/3).
- **One active LLM provider** at a time, chosen in config; config may describe many. **Stateless** sessions (no personalization in MVP). Default: **Claude Agent SDK** (`claude-agent-sdk`, formerly "Claude Code SDK") on **`claude-sonnet-5`**.
- **Settings live in two synced surfaces**: an in-app settings screen and the config file. Hotkey and active provider/model are changeable from both.
- Panel shows the **original alongside the corrections**; every suggestion has its own **copy button** (that's how corrected text gets back). Provider errors show **inline in the panel** with **Retry**.
- Panel **stays open after a copy**; hides on **focus loss**; hotkey is a **toggle** (second press hides).
- **No diff view in MVP** — decided out, moved to phase 2.
- **Privacy of clipboard text sent to a third-party LLM is explicitly out of scope.**
- Provider abstraction: text-in → stream-of-text-out (not HTTP-specific); prompt+model travel together as a **preset**; **structured response** (`suggestions[]`) that doubles as the history-DB schema.
- **SQLite history** of all corrections (future grammar-progress analytics).
- Known packages: `tray_manager`, `hotkey_manager`, `window_manager`, `sqflite`/`drift`.

### Resolved in Step 2 (architecture) — see the spine for the binding rules
- Paradigm: **hexagonal**, `domain` (pure Dart) ← `application` ← `ui` + `infrastructure`, enforced by an import lint.
- Persistence **drift**; state **Riverpod** (application + ui only, never domain); config **JSON** with write-through.
- Default provider: **Python sidecar** importing `claude_agent_sdk` — there is no Dart binding for the Agent SDK. The sidecar is a transport shim with no logic; register parsing stays pure Dart so it is testable. Chain is daemon → Python → `claude` CLI, so kill the process *group* on cancel.
- Hotkey: one port, two adapters — X11 via `hotkey_manager`/keybinder-3.0, Wayland via pure-Dart D-Bus to the GlobalShortcuts portal (`dbus` package; no Flutter plugin exists).

### Ratified divergence — CAP-12 on Wayland
The XDG GlobalShortcuts portal gives the **compositor and user** authority over the actual key combination; the app submits only a `preferred_trigger`. So in-app hotkey settings are **authoritative on X11, advisory on Wayland**, and the settings screen shows which regime is active. Ratified 2026-08-06 and folded into SPEC.md CAP-12.

## Phase 2 backlog (explicitly out of MVP)
- X11 primary-selection input (highlight text, no Ctrl+C)
- Invisible-replace mode (silent clipboard swap + toast; panel on long-press)
- Personalization from history (past mistakes fed into prompt)
- Per-suggestion diff view (highlight inserted/removed words) — considered and declined for MVP

## Known landmine — resolved in Step 2
- ~~**Wayland global hotkeys**~~: confirmed and designed for. `hotkey_manager` is X11-only (it wraps `keybinder-3.0`), so Wayland goes through the GlobalShortcuts portal over D-Bus. Three findings that bite if missed: the **portal owns the binding**; only **GNOME and KDE** ship a backend (wlroots does not — degrade visibly); and a non-sandboxed app must call **`Registry.Register(app_id)` first**, with a matching installed `.desktop` file, or the bind is silently discarded. Details in `risks.md` and spine AD-9…AD-12.
