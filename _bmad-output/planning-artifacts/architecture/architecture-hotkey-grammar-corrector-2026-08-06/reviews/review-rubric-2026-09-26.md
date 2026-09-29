# Reviewer Gate — rubric walker (2026-09-26)

**Target:** `ARCHITECTURE-SPINE.md`, current Phase 2 regenerated draft. **Lens:** good-spine checklist in `.claude/skills/bmad-architecture/references/reviewer-gate.md`, product SPEC, D-16–D-19, and checked-in source. This is an independent review of the draft, not an edit to the generated spine.

**Gate verdict: changes requested.** The 19-AD structure, core dependency direction, and explicit operational envelope are intact. The remaining high-severity finding is a rule that promises a provider extension path which the shipped second provider already disproves. Other findings below identify narrower claims or missing links that can direct two units to different behavior.

## High

### H1 — AD-15's exact three-step provider extension promise is false in this brownfield system

**Evidence:** Spine `:363-376`, especially `:367-373`, says HTTP fields stay behind adapters and any new provider is exactly one adapter file, one config entry/preset, and one registry entry, with *no* UI or application changes. The shipped second provider required `lib/src/infrastructure/correction/openai_compatible/chat_completion_sse_decoder.dart`, `openai_compatible_correction_provider.dart`, `api_key_resolver.dart`, `api_key_source.dart`, `secret_service_secret_store.dart`, `domain/config/secret_store.dart`, Settings form and controller integration, plus registry registration (`provider_registry.dart:21-43`). `domain/config/provider_config.dart:17-38` even defines the OpenAI provider id and validates its HTTP base URL with `Uri`, contrary to the adapter-private wording. Phase 2 D-12–D-15 (`02-CONTEXT.md:68-72`) intentionally require source display, base URL and model editing, validation, and incomplete-config handling. AGENTS.md §5 promises extension without correction-pipeline changes, not literally one implementation file or no Settings changes.

**Divergence:** A future provider author following the Rule can put endpoint and credential input in a generic `ProviderConfig.settings` map and omit in-app Settings, violating product CAP-8's two synchronized surfaces. Another can follow shipped code and add provider-specific infrastructure and Settings presentation, violating the Rule's “exactly” and “no ui” text. The frozen `CorrectionProvider` seam still holds; the three-step accounting does not.

**Disposition: discuss.** Keep the invariant that provider selection stays at `ActiveCorrection`/`ProviderRegistry` and that application correction flow and the port do not change. Replace the file-count promise with a minimum integration checklist that permits adapter-private helpers and synchronized Settings support for user-facing provider configuration. Decide whether the domain's OpenAI URL parser moves behind a port or AD-15 explicitly permits a provider-specific validation value in domain; the current rule and code cannot both be authoritative.

### H2 — AD-16 permits a provider that cannot satisfy CAP-5

**Evidence:** Spine `:383` expressly permits a provider with no streaming to emit zero `SuggestionDelta` events and only `CorrectionCompleted`, saying CAP-5 degrades for that provider. Product SPEC `:38-40` requires partial suggestion text to render before the provider response finishes; `:86` rules out latency fake-outs and names token streaming as the speed mechanism. AGENTS.md `:140-142` requires every implementation to stream partials under Liskov substitution. The companion provider contract `:7` fixes stream output, and the three-event protocol in AD-3 (`:147-149`) is the architecture's means for CAP-5.

**Divergence:** The panel can be built to show partials for every selectable provider, while a new adapter can follow AD-16 and supply none. A stream containing one final event is a Dart stream but does not meet CAP-5's visible-progress success criterion. This is a product contract exception introduced inside an AD, without an owner-ratified divergence or a capability limit in the SPEC.

**Disposition: autofix in the authorized generator.** Preserve freedom to choose any wire format, including a native structured stream, but require partial events before completion for a selectable production provider. If a provider truly cannot stream, surface the capability conflict to the owner before making it selectable; do not silently designate it as a supported degraded provider.

### H3 — AD-11's prescribed portal order has a missed-change window

**Evidence:** Spine `:333-338` requires `BindShortcuts` read-back before the `ShortcutsChanged` subscription. AD-9 `:318-319` and AD-10 `:327` depend on that stream plus `current` to keep compositor changes visible. The Wayland adapter follows the order at `wayland_portal_global_hotkey.dart:466-467,540-550,1198-1212`; it performs the post-subscription read only if `_backendDescription == null` (`:544-550`). CAP-12 (`SPEC.md:64-67`) requires reflecting compositor rebinds without restart.

**Divergence:** A compositor can change A to B after the bind read-back but before the signal listener exists. The adapter's cache stays at A, and the settings consumer cannot recover B from `current` or a missed event. Both adapter and consumer can obey the spine yet display a stale binding indefinitely. No live-compositor occurrence is claimed; the written order permits the interleaving.

**Disposition: discuss.** Specify an ordering that covers the gap, such as an unconditional read/reconciliation after subscribing, with session and sender filtering preserved. Subscription before read-back may have its own activation/security implications, so the generator should record the selected protocol deliberately.

## Medium

### M1 — The compositor change event omits the displayed fact

**Evidence:** Spine `:289-308` declares `HotkeyStatus(outcome, backendDescription)` but `bindingChanges` emits only `HotkeyBindOutcome`. On Wayland the effective binding is null and the description is the only available display text (`:327`). The adapter updates `_backendDescription` and publishes just the outcome (`wayland_portal_global_hotkey.dart:1331-1368`); Settings separately reads `current.backendDescription` (`settings_controller.dart:543-558,607-620`). AD-9 also gives `HotkeyBound` value equality over a registration with the same null effective and compositor authority (`:317`).

**Divergence:** Two distinct compositor rebinds can emit equal outcomes with different descriptions. A second consumer can deduplicate the equal values or pair a queued event with a newer cache snapshot and still satisfy the declared port. The current Settings controller handles every event, but the port does not require that behavior or an atomic status snapshot.

**Disposition: discuss.** Emit an immutable `HotkeyStatus` (or a revision carrying both fields) for each backend change, then make `current` the last emitted snapshot. This touches AD-9's fixed member shape and needs the appropriate frozen-contract decision before regeneration.

### M2 — A late clipboard seed can overwrite a deliberate empty edit

**Evidence:** AD-18 (`:401-402`) places clipboard reading after `shown` and says user edits supply correction input, but gives no precedence rule while that asynchronous read is pending. Product CAP-3 (`SPEC.md:30-32`) says the original clipboard content is unused once edited. `correction_controller.dart:145-148,447-510` tracks the session token but skips a late seed only while editor text is nonempty or correction status is non-idle. The user can type and erase before the read finishes, returning both guards to their initial values; the old clipboard text then lands at `:510`.

**Divergence:** One controller can treat an empty editor as untouched, another can track any edit in the current session. Both meet the literal AD-18 text; only the latter preserves a deliberate deletion. This is an implementation defect as well as an unwritten ordering rule.

**Disposition: autofix.** State that any user edit, including one leaving an empty string, supersedes the pending clipboard seed. A session-scoped edit revision makes the rule observable and implementable without delaying CAP-1's show path.

### M3 — AD-12's exact unavailable-state layout contradicts the shipped Settings screen

**Evidence:** AD-12 (`:348`) says Settings renders `HotkeyUnavailable.message` verbatim and appends **exactly one** line of its own. `hotkey_status_view.dart:125-171` renders three lines: a screen-authored cause line, the adapter message (or tray fallback), and a screen-authored ownership line. D-08 (`02-CONTEXT.md:62`) also requires cause-specific guidance in the tray, so the cause vocabulary is deliberate.

**Divergence:** A replacement Settings widget following AD-12 removes the cause line, while one following the source retains it. The screen-authored line count is a precise, falsified brownfield claim.

**Disposition: autofix in the authorized generator.** Retain the shipped cause-specific explanation and amend AD-12's wording and count to match the rendered contract, while preserving the adapter-owned tray fallback and no invented ownership regime.

### M4 — The infrastructure ring's outward-import ban has no mechanical gate

**Evidence:** The ring table says `lib/src/infrastructure/` never imports `application` or `ui` (`:39-44`); AD-17 explicitly relies on this at `:393` and AD-1 calls dependency-direction enforcement mandatory (`:66-71`). `test/architecture/ad1_import_rule_test.dart:11-13,31-121` checks domain, application, and UI, with a UI symbol check at `:123-180`; it has no infrastructure scan. The same directory contains two composition-root parts whose role is to know adjacent boundaries (`:390-395`).

**Divergence:** A new infrastructure helper can import an application controller while all named architecture tests stay green, despite the table and AD-17. The stated ban is review-only at precisely the ring where composition work now lives.

**Disposition: defer as an explicit open enforcement gap, or autofix the gate in an authorized later phase.** Phase 2's locked spec excludes new tests/gates (`02-SPEC.md:325-327`), so this plan should not silently add one. Record the unmechanized rule honestly in the spine or Deferred section until a gate is allowed.

### M5 — D-16's placement decision is only a closing footnote, not an operating rule

**Evidence:** D-16 (`02-CONTEXT.md:76`) accepts best-effort startup/cached placement and compositor placement on Wayland to keep the hotkey path I/O-free. The shipped setup applies size and position while the window is hidden (`main.dart:674-687`). The spine's AD-8 covers only visibility (`:202-239`), the operational envelope omits placement (`:646-653`), and `:688` merely refers to “D-16's placement waiver” without stating it.

**Divergence:** A panel/window implementor reading the spine could query the pointer or set position on each hotkey press to meet the original desired placement, while a controller implementor obeys AD-8's I/O-free path. Conversely, a Wayland UI author could claim exact pointer-display placement that the owner waived. The source has a concrete answer, but the architecture document does not carry it.

**Disposition: autofix in the authorized generator.** Put D-16's best-effort startup/cached geometry and compositor-owned Wayland placement beside AD-8 or in the operational envelope, with the no-runtime-observation limit.

### M6 — CAP-11's capability map points to the wrong behavioral rule

**Evidence:** The CAP-11 row (`:668`) cites only AD-6, which governs register order and persistence (`:164-168`). Explicit copy, selection not copying, and staying open after copy are in AD-18 (`:403`), while the SPEC's CAP-11 and CAP-14 (`SPEC.md:60-62,73-75`) require those behaviors.

**Divergence:** A contributor using the map to implement the copy action can miss the rule that separates selection from transfer. The prose rule exists; the index that routes work to it is stale.

**Disposition: autofix in the authorized generator.** Add AD-18 to CAP-11's governing rules; retain AD-6 only if the copy action intentionally uses register ordering.

## Low / evidence limits

- **L1 — Operational wording:** `:648` says “One Linux desktop binary,” while `:430,579-580,649-652` require a versioned Python sidecar asset and external interpreter/CLI. The intended meaning may be one Flutter app binary, but the phrase can misdirect packaging. **Disposition: autofix wording** to name one daemon executable plus bundled sidecar asset and host dependencies; packaging format remains Deferred (`:679`).
- **L2 — Stack currency wording:** `:453` calls the CI-pinned Flutter toolchain “Flutter (stable).” The repository pin is a deployment choice; [Flutter's official release notes](https://docs.flutter.dev/release/release-notes) list a later stable release. `tray_manager` 0.5.3 remains a real [published package version](https://pub.dev/documentation/tray_manager/latest/tray_manager/), while [the current package page](https://pub.dev/packages/tray_manager) shows a newer API. **Disposition: autofix wording** to “stable-channel CI pin”; no package upgrade is implied by this review.
- **L3 — Deterministic lint false positive:** `uv run .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06` reports one low placeholder at spine `:338` for `a{sv}`. That is the literal D-Bus signature, not an unfilled token. **Disposition: ignore.**

## Checklist conclusion

The draft keeps AD-1–AD-19, the core event and history shapes, D-17's user-authored key preservation exception (`:367,688`), D-18's preferred/effective distinction (`:327`), and D-19's owner-ratified defensive copy (`:251-254,317`). The current file map is a brownfield snapshot (`:479-582`), and the operational envelope now names the tray host and its source-inspected silent-absence limit (`:649-650`). These are positive checks, not live X11, Wayland, tray, keyring, or endpoint observations. H1–H3 and M1–M6 remain the review's actionable contract findings; none requires a new AD identifier.
