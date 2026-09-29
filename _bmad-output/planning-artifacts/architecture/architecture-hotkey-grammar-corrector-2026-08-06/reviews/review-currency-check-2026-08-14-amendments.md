# Currency / reality-check review — the 2026-08-14 Update pass amendments

**Target:** `_bmad-output/planning-artifacts/architecture/architecture-hotkey-grammar-corrector-2026-08-06/ARCHITECTURE-SPINE.md`
**Lens:** currency / reality-check — was every committed decision web-researched or reality-checked rather than asserted; are named versions and technologies still current; is anything out of date that was not confirmed against the web, the existing project, or the current starter.
**Scope:** the three amended regions (AD-12's Rule, the `libkeybinder-3.0-0` clause, the `## Stack` heading note) and their immediate neighbours; lighter sweep elsewhere.
**Date:** 2026-08-14

Everything below is backed by a command output or a file citation taken in this session. Where I could not substantiate a claim I say so rather than asserting it.

---

## Verdict

The three amendments are **substantially better evidenced than the text they replaced**, and two of the three hold up under independent re-measurement. But the AD-12 widening over-reaches in two directions at once — it mandates an outcome the shipped code deliberately does not produce, and its enumerated set omits most of what the two adapters actually refuse, including the one portal failure AD-11 exists to prevent. The `libkeybinder` clause's *conclusion* is correct and I confirmed it empirically (more strongly than the spine claims), but its stated *mechanism* is a non-sequitur. The Stack note's row-by-row verification holds for every row, with one uncorrected gap in its "one known exception" framing and one pin that the note's own scope silently excluded from re-verification — and that pin is stale.

---

## Region 1 — AD-12's widened Rule

The amended Rule reads:

> **any** backend's refusal to hold the hotkey resolves to AD-9's `HotkeyUnavailable`, never an exception — `bind()` never throws and never rejects. The refusals are: a portal `CreateSession` or `BindShortcuts` that fails; a key `HotkeyKeyCatalogue` finds unrepresentable *before* the backend is touched; an X11 grab the backend refuses; and a session that identifies no display server, where AD-9's X11 fallback may have guessed wrong.

### F1 — HIGH — the widened Rule contradicts the shipped code on the catalogue arm

The Rule says a catalogue-caught refusal "resolves to AD-9's `HotkeyUnavailable`". In the shipped code it does so **only when nothing was previously in effect**. When a previous binding is held, `X11GlobalHotkey._refusedBeforeBackend` returns a `HotkeyBound` naming the *previous* combination:

`/workspace/lib/src/infrastructure/hotkey/x11_global_hotkey.dart:239-260`

```dart
  HotkeyBindOutcome _refusedBeforeBackend({
    required String key,
    required String message,
  }) {
    final stillInEffect = _effective;
    if (stillInEffect == null) {
      return HotkeyUnavailable(message: message);
    }
    _log(...);
    return HotkeyBound(
      HotkeyRegistration(
        effective: stillInEffect,
        authority: BindingAuthority.application,
      ),
    );
  }
```

This is not an oversight — the doc comment above it (`:216-238`) argues at length *why* `HotkeyUnavailable` would be the wrong answer there ("Answering `HotkeyUnavailable` regardless would say 'the hotkey is inactive' while the old combination was still grabbed and still opening the panel"). The refused-release path does the same thing for the same reason (`_releaseBeforeRebinding`, `:286-314`).

So the widened Rule, read literally, makes deliberate shipped behaviour non-conformant. The pre-amendment Rule was portal-scoped and did not have this problem; widening it to "any backend's refusal" imported an absolute that the X11 adapter's abandoned-rebind design contradicts. The fix is to say what the code says: a refusal resolves to a *value* on `HotkeyBindOutcome` — `HotkeyUnavailable` when nothing is held, and `HotkeyBound` naming what is genuinely still in effect when a previous binding survives (which is AD-10's own vocabulary).

### F2 — HIGH — the enumerated set is materially incomplete, and it excludes the portal failure AD-11 exists to prevent

Both adapters carry their own enumeration of what they refuse, and both are longer than AD-12's.

**Portal adapter** — `/workspace/lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart:51-56`:

> Everything the portal can refuse is a value (AD-12): an unparsable bus address, an absent session bus, an absent portal, a compositor with no GlobalShortcuts backend (every wlroots one), a dismissed dialog, a malformed reply, a discarded bind and a disposed adapter all resolve to [HotkeyUnavailable].

Eight classes. AD-12's portal arm covers at most two of them ("a portal `CreateSession` or `BindShortcuts` that fails"). Confirmed distinct code paths for the others:

- unparsable `DBUS_SESSION_BUS_ADDRESS` → `_unusableBusAddress`, decided in the factory (`:76-100`) and answered at `:269` before any portal call is made;
- dead connection → `_deadConnection`, answered at `:247` and `:263`;
- disposed adapter → `_shutDownDuringBind()` (`:1058-1065`), answered at `:243-245` and `:258`.

The most consequential omission is the **discarded bind**. The class doc is explicit that this is *not* a failure of `BindShortcuts` (`:21-29`):

> The `shortcuts` list the `BindShortcuts` response carries back is documented as "a subset of the shortcuts which were passed in … (this includes the set of all shortcuts and the empty set)", so a portal that discards the request answers *successfully* with our shortcut missing. That is how GNOME reports a bind it dropped because the application id has no installed `.desktop` entry.

AD-11's whole stated purpose is preventing exactly that ("GNOME discards the bind for an app id with no matching desktop entry"). AD-12's enumeration, phrased as *failures* of the two calls, excludes it. The code comment at `:273-274` also leans on AD-12's portal enumeration being narrow — "AD-12 names only CreateSession and BindShortcuts as the steps whose failure means no hotkey" — so this is a load-bearing citation, not incidental prose.

**X11 adapter** — `/workspace/lib/src/infrastructure/hotkey/x11_global_hotkey.dart:21-24`:

> an unrepresentable key, a refused grab, a refused release, a channel that is gone and a disposed adapter all resolve to [HotkeyUnavailable] or to the binding that is genuinely still in effect.

Five classes; AD-12 covers two. A refused release (`:286-314`) and a disposed adapter (`_shutDownDuringBind`, `:262-270`) are absent from AD-12's list.

Two further gaps:

- **"unrepresentable" undercounts the catalogue's two arms.** `HotkeyKeyCatalogue.usbHidUsageFor` returning null is genuine unrepresentability; `HotkeyKeyCatalogue.bindsTheWrongKey` (`hotkey_key_catalogue.dart:146`) covers seven keys that *are* representable and *would* be accepted by the backend, and are refused because the plugin would grab a keypad/ISO/3270 variant nobody can press (`x11_global_hotkey.dart:126-145`). AD-12's single word excludes the second, sharper class.
- **The compositor-originated drop is not in the list at all.** `_onShortcutsChanged` pushes a `HotkeyUnavailable` on `bindingChanges` when the compositor reports the session no longer holds the shortcut (`wayland_portal_global_hotkey.dart:846-869`), and AD-10 depends on that path reaching the UI. AD-12 enumerates only what `bind()` returns.

### F3 — MEDIUM — AD-12 adds a phantom refusal no code path can produce

"a session that identifies no display server" has no corresponding state. `DisplayServer.fromEnvironment` is total over its two cases:

`/workspace/lib/src/infrastructure/hotkey/display_server.dart:19-36` — `XDG_SESSION_TYPE == 'wayland'` → wayland; `== 'x11'` → x11; non-empty trimmed `WAYLAND_DISPLAY` → wayland; **otherwise x11**. There is no third value and no `HotkeyUnavailable` keyed to "no display server".

A wrong guess therefore surfaces as one of the *other* enumerated refusals (a refused X11 grab, or a portal failure once the Wayland adapter is chosen wrongly). It is a *cause* of a refusal, not a refusal class — and listing it as a peer of the other three implies a code path a reader will look for and not find. The display_server.dart doc gets this right (`:16-18`: "AD-12 makes a wrong guess a visible `HotkeyUnavailable`, not a crash" — a consequence, not a category).

### F8 — LOW — the Conventions "Errors" row was not brought along

The row still reads:

> Expected failures are modelled values (`CorrectionEvent`, `HotkeyRegistration`, `HotkeyUnavailable`). Exceptions signal programmer error only, and never cross a port boundary as a vendor type.

Two frictions with the widened AD-12:

1. It never names `HotkeyBindOutcome` / `HotkeyBound`, which is the sealed type `bind()` actually returns and — per F1 — is itself one of the refusal outcomes. Under the widened Rule this is now the central modelled-failure type in the hotkey slice.
2. "Exceptions signal programmer error only" sits awkwardly beside AD-12's new absolute "never an exception". `HotkeyRegistrar` deliberately **rejects** on a refused or unrepresentable grab and throws `StateError` on a disposal race — `hotkey_manager_registrar.dart:89` (`'the hotkey registrar was disposed during this grab'`), `:126`, `:193`, `:199`; contract stated at `hotkey_registrar.dart:46-49`. That is legitimate because the registrar is declared an infrastructure-private seam rather than a port, and `X11GlobalHotkey` converts one layer up. But AD-12's unqualified "never an exception" no longer signals that the prohibition is scoped to the port boundary. "never escapes the port as an exception" would keep the invariant and stop contradicting the seam that implements it.

---

## Region 2 — the `libkeybinder-3.0-0` clause

I re-measured every claim rather than reading the spine's numbers.

### What the amendment gets right (measured)

| Claim | Verified how | Result |
|---|---|---|
| `libkeybinder-3.0.so.0` is a `DT_NEEDED` entry of the plugin library | `readelf -d build/linux/x64/release/bundle/lib/libhotkey_manager_linux_plugin.so` | **Confirmed** — `0x…01 (NEEDED) Shared library: [libkeybinder-3.0.so.0]`, second entry |
| the executable does not carry it | `readelf -d build/linux/x64/release/bundle/hotkey_grammar_corrector` | **Confirmed** — 22 NEEDED entries, no libkeybinder; it NEEDs `libhotkey_manager_linux_plugin.so` and has `RUNPATH [$ORIGIN/lib]` |
| the plugin is `hotkey_manager_linux 0.2.0` | `pubspec.lock` | **Confirmed** — `hotkey_manager_linux 0.2.0` (transitive, under `hotkey_manager 0.2.3`) |
| the chain is runner → plugin `.so` → `libkeybinder-3.0.so.0` | the two readelf outputs above | **Confirmed** |
| the plugin is registered unconditionally | `linux/flutter/generated_plugin_registrant.cc` | **Confirmed** — `hotkey_manager_linux_plugin_register_with_registrar(...)` is called with no guard |

One supporting measurement the spine does **not** state, and which is what actually makes "runtime dependencies the app cannot supply itself" true: `build/linux/x64/release/bundle/lib/` contains `libapp.so`, `libflutter_linux_gtk.so`, `libhotkey_manager_linux_plugin.so`, `libscreen_retriever_linux_plugin.so`, `libsqlite3.so`, `libtray_manager_plugin.so`, `libwindow_manager_plugin.so` — **no libkeybinder**. The bundle cannot satisfy its own DT_NEEDED; the host must.

### The conclusion holds, and I measured it directly rather than inferring it

The spine infers pre-`main()` failure from `readelf` alone. I tested it. Placing a broken stand-in ahead of the loader cache:

```
$ LD_LIBRARY_PATH=<scratch> build/linux/x64/release/bundle/hotkey_grammar_corrector
build/linux/x64/release/bundle/hotkey_grammar_corrector: error while loading shared libraries:
  <scratch>/libkeybinder-3.0.so.0: file too short
exit=127
```

No `Gtk-WARNING`, no app output of any kind — whereas the control run with the real library reaches GTK (`Gtk-WARNING **: cannot open display: :14`, exit 0). The failure demonstrably precedes any app code.

And the display-server-independence claim, measured rather than argued:

```
$ env -u DISPLAY XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-0 \
    LD_LIBRARY_PATH=<scratch> build/.../hotkey_grammar_corrector
… error while loading shared libraries: … libkeybinder-3.0.so.0: file too short
exit=127
# control, real library, same Wayland-shaped env:
… Gtk-WARNING **: cannot open display:
exit=0
```

A Wayland-shaped session with no `DISPLAY` fails at load and never reaches `DisplayServer.fromEnvironment`. The clause's conclusion — "the hardness **precedes the adapter choice** and so is display-server-independent" — is **correct and now empirically measured**, not merely inferred.

### F4 — MEDIUM — the stated mechanism is asserted, and it is the wrong mechanism

The clause reasons:

> `linux/flutter/generated_plugin_registrant.cc` registers the plugin unconditionally, so the whole `DT_NEEDED` chain (runner → plugin `.so` → `libkeybinder-3.0.so.0`) is resolved by the loader *before* `main()`

The registrant cannot be the reason. `fl_register_plugins` is called from **inside** the running process (the Flutter Linux runner calls it on the GTK activate path, after `main()` has started) — the experiment above proves the process dies before any of that. DT_NEEDED resolution happens at load time regardless of whether registration is ever reached; the hardness would hold even if registration were conditional, which is precisely why the registrant is the wrong evidence for it.

The artifact that *does* carry the claim is `linux/flutter/generated_plugins.cmake`, which I read:

```cmake
list(APPEND FLUTTER_PLUGIN_LIST
  hotkey_manager_linux
  …
)
foreach(plugin ${FLUTTER_PLUGIN_LIST})
  …
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)
```

That unconditional `target_link_libraries` against the runner is what creates the `DT_NEEDED` entry the clause reasons from. Citing the registrant instead is a non-sequitur that weakens a claim the readelf evidence already carries on its own — and it invites a reader to conclude, wrongly, that making registration conditional would soften the dependency.

Secondary: the clause says "measured with `readelf -d` against this tree's release build on 2026-08-14". The bundle's mtime is **2026-08-13 06:54** (`ls -la --time-style=long-iso build/linux/x64/release/bundle/`). Defensible as a measurement date, but the sentence reads as if the build is from the 14th, and a stale-`build/` reading is a known hazard in this tree. Naming the build date alongside the measurement date would close it.

### F5 — MEDIUM — the neighbours were left contradicting the amended region

The amendment argues, over four sentences, against a reading that two neighbours still assert unamended:

- The same bullet still annotates the dependency `libkeybinder-3.0-0` **(X11 hotkey)** (line 580).
- The Stack section still says: "`hotkey_manager` was last published 2024-05-18 and implements Linux through `keybinder-3.0`, an X11-only library. **It is bound here for the X11 adapter only**; AD-9 makes replacing it a one-file change."

Both are true about *binding* and both are misleading about *packaging*, which is the distinction the amendment exists to draw. The amendment acknowledges the tension from its own side ("despite the `(X11 hotkey)` annotation above and AD-9 binding `hotkey_manager` for the X11 adapter only") but leaves no pointer at either neighbour, so a reader who arrives via the Stack table or scans the dependency list gets the pre-amendment picture and no signal that it was corrected 80 lines away. This is the failure mode the prior gate flagged for this pass. Cheapest fix: `(X11 hotkey — packaging is not X11-scoped, see the operational envelope)` on the annotation, and one clause on the Stack note.

Also outside the re-verification's stated scope: **"`hotkey_manager` was last published 2024-05-18"** is a web claim from 2026-08-06 that now sits 27 months stale, inside a section whose heading note claims a 2026-08-14 re-verification. The note's scope is `pubspec.yaml`/`pubspec.lock`, which cannot confirm a publication date, so this prose was not re-checked and the note does not say it wasn't. Flagging as unverified rather than wrong — I did not confirm it either way.

---

## Region 3 — the `## Stack` heading note

The note claims: re-verified 2026-08-14 against `pubspec.yaml` / `pubspec.lock`; every row matches the shipped dependency graph; both citations resolve to exactly one pin each; one known exception, `drift_flutter 0.3.1`, carried under DW-94.

### Row-by-row verification (all rows, measured)

Versions read from `pubspec.lock` via a parse of every package block; constraints from `pubspec.yaml`.

| Table row | Table value | Measured | Verdict |
|---|---|---|---|
| Flutter (stable) | cited → `.github/workflows/ci.yml` | `ci.yml:88` `flutter-version: 3.44.8`; **exactly one** version-shaped string in the whole file | ✅ resolves to one pin, no version restated |
| Dart SDK | 3.12.2 | `pubspec.yaml` `sdk: ^3.12.2`; lock `sdks: dart: ">=3.12.2 <4.0.0"`; installed `Dart SDK version: 3.12.2` | ✅ |
| flutter_riverpod | 3.4.2 | 3.4.2 (direct main) | ✅ |
| drift | 2.34.3 | 2.34.3 (direct main) | ✅ |
| drift_flutter | 0.3.1 | **absent from lock and pubspec** | ⚠️ known, labelled exception (DW-94) |
| drift_dev (dev) | 2.34.0 | 2.34.0 (direct dev) | ✅ |
| build_runner (dev) | 2.15.1 | 2.15.1 (direct dev) | ✅ |
| sqlite3 | 3.5.1 | 3.5.1 (direct main) | ✅ |
| dbus | 0.7.14 | 0.7.14 (direct main) | ✅ |
| window_manager | 0.5.2 | 0.5.2 (direct main) | ✅ |
| tray_manager | 0.5.3 | 0.5.3 (direct main) | ✅ |
| hotkey_manager | 0.2.3 | 0.2.3 (direct main); platform packages `hotkey_manager_linux/macos/windows/platform_interface` all 0.2.0 | ✅ |
| flutter_lints (dev) | 6.0.0 | 6.0.0 (direct dev) | ✅ |
| Python (sidecar) | 3.11+ | `tool/provision_sidecar.sh:93` — "the sidecar needs Python 3.11+" | ✅ |
| claude_agent_sdk | cited → `assets/sidecar/requirements.txt` | `claude-agent-sdk==0.2.132`; **exactly one** version-bearing line | ✅ resolves to one pin, no version restated |
| `claude` CLI | on `PATH` | not a version claim | n/a |
| Default model | `claude-sonnet-5` | `lib/src/infrastructure/config/default_app_config.dart:41` `shippedModel = 'claude-sonnet-5'`; verified against the current Claude model reference — Claude Sonnet 5 is a live model id (1M context), not a stale or invented string | ✅ |

Gate check: `test/architecture/sidecar_pin_drift_test.dart` exists (34 KB), so the note's claim that a test enforces both citations is not vapour. Neither cited cell has grown a version beside its citation.

The note's honesty about the further hand-maintained copies also checks out: `.devcontainer/Dockerfile:111-112` carries `ARG FLUTTER_VERSION=3.44.8` with its coupled `ARG FLUTTER_SHA256=672089e0…`, matching the CI pin, and no gate covers that pair.

### F6 — MEDIUM — "one known exception" is two; the second is documented in pubspec and unabsorbed by the spine

The note's headline is "Every row matches the shipped dependency graph … with **one known exception**". Reconciling the table against `pubspec.yaml` turns up a second labelled divergence, which the spine does not acknowledge anywhere:

`/workspace/pubspec.yaml`, dev_dependencies:

```yaml
  # Not in the spine Stack table, but already in the dependency graph at this
  # exact version (riverpod 3.4.2 depends on it). A direct dev dependency is
  # required for the spec's own verification command `dart test` to run the
  # pure-Dart domain tests without a Flutter binding (AGENTS.md §7).
  test: 1.31.0
```

Lock confirms `test 1.31.0` as a **direct dev** dependency. So `pubspec.yaml` names two divergences from this table — `drift_flutter` (table has it, graph doesn't) and `test` (graph has it, table doesn't) — and the 2026-08-14 pass absorbed one. A reader who does the reconciliation the note invites finds a second labelled gap and a note that says there is only one. Either add the row (it is a pinned direct dev dependency with a stated architectural reason — AGENTS.md §7's binding-free `dart test`) or widen the exception sentence to name both.

Note the asymmetry is real, not pedantry: the note's "one known exception" framing is what tells a future reader they can stop reconciling. It currently tells them that one row early.

### F7 — LOW — the one pin outside pubspec is the one pin nothing re-checked, and it is stale

The note's verification scope is `pubspec.yaml` / `pubspec.lock`. That scope structurally cannot cover the `claude_agent_sdk` row, whose executable home is `assets/sidecar/requirements.txt`. Measured against PyPI:

- pinned: `claude-agent-sdk==0.2.132`
- current released version (PyPI JSON API, `https://pypi.org/pypi/claude-agent-sdk/json`, `info.version`): **0.2.138**

Six patch releases behind. The package exists and is the right one — the Python Claude Agent SDK is published as `claude-agent-sdk`, which also confirms AD-19's "ships only as `claude-agent-sdk` (Python) and `@anthropic-ai/claude-agent-sdk` (TypeScript)" is still accurate — so this is a staleness flag, not a "technology no longer exists" flag. Nor is it a table error: the cited row still resolves to exactly one pin, which is all the table claims.

The finding is about the *note*: a heading note that announces a re-verification date invites the reading that every row was checked on that date, and the one row whose pin lives outside pubspec was not. The pin-renegotiation paragraph likewise carries a user-ratification date but no PyPI check. One clause — naming the scope limit, or adding a second check date for the requirements pin — closes it.

---

## Light sweep elsewhere — nothing further

- **AD-9 / AD-10 / AD-11 vs the widened AD-12.** No direct contradiction found beyond F1/F2/F8. AD-9's `bindingChanges` contract ("An adapter whose backend cannot originate one … implements it as an empty stream that closes") matches `X11GlobalHotkey.bindingChanges => const Stream<HotkeyBindOutcome>.empty()` (`x11_global_hotkey.dart:92-94`). AD-10's "a returned `HotkeyUnavailable` is rendered as AD-12's degradation" is consistent. AD-11's four-step order is implemented in order, and the `Registry.Register` tolerance for `UnknownMethod` / `ServiceUnknown` is present (`wayland_portal_global_hotkey.dart:387-402`).
- **AD-19's technology claims.** Verified independently: the Claude Agent SDK is a real, currently-published package under the names the spine gives; the Dart → Python → `claude` CLI chain matches how the Python SDK is documented (it is the Claude Code harness packaged as a library, driving the CLI). `assets/sidecar/` contains `claude_agent_sdk_sidecar.py` and `requirements.txt` as the AD describes.
- **AD-16's wire format, AD-13/14/15/17/18.** No currency claims to check; nothing asserted about a version, library, or starter default.
- No stale or invented technology names found anywhere in the spine.

---

## Findings, ranked

| # | Sev | Region | Finding |
|---|---|---|---|
| F1 | HIGH | AD-12 | Widened Rule mandates `HotkeyUnavailable` for catalogue and release refusals; shipped code deliberately returns `HotkeyBound(previous)` when a binding is still held (`x11_global_hotkey.dart:239-260`, `:286-314`) |
| F2 | HIGH | AD-12 | Enumeration covers 2 of 8 portal refusals and 2 of 5 X11 refusals, and excludes the *successful*-but-discarded `BindShortcuts` — the exact failure AD-11 exists to prevent (`wayland_portal_global_hotkey.dart:21-29`, `:51-56`; `x11_global_hotkey.dart:21-24`) |
| F4 | MED | envelope | Conclusion measured and confirmed (empirically, beyond the spine's own evidence), but the stated mechanism is wrong — registration runs inside `main()`; the load-bearing artifact is `generated_plugins.cmake`, not `generated_plugin_registrant.cc`. Measurement date (08-14) also postdates the build (08-13) |
| F5 | MED | envelope ↔ Stack | `(X11 hotkey)` annotation and the Stack `hotkey_manager` note still assert the X11-scoped reading the amendment refutes, with no cross-pointer; Stack's "last published 2024-05-18" was outside the re-verification scope |
| F6 | MED | Stack note | "one known exception" is two — `pubspec.yaml` documents a second divergence (`test: 1.31.0`, "Not in the spine Stack table") that the pass did not absorb |
| F3 | MED | AD-12 | "a session that identifies no display server" is a phantom refusal — `DisplayServer.fromEnvironment` is total over {x11, wayland} (`display_server.dart:19-36`); it is a cause of a refusal, not a class of one |
| F7 | LOW | Stack note | `claude-agent-sdk==0.2.132` is six releases behind PyPI's 0.2.138; the note's pubspec-only scope structurally excluded the one pin that lives outside pubspec, without saying so |
| F8 | LOW | Conventions | "Errors" row never names `HotkeyBindOutcome`/`HotkeyBound`, now the central modelled failure type; and its "Exceptions signal programmer error only" sits awkwardly against AD-12's unqualified "never an exception" while `HotkeyRegistrar` deliberately rejects and throws `StateError` (`hotkey_manager_registrar.dart:89`, `:126`, `:193`, `:199`) |

## Commands and sources used

- `readelf -d` on `build/linux/x64/release/bundle/hotkey_grammar_corrector` and `…/lib/libhotkey_manager_linux_plugin.so`
- `ls -la --time-style=long-iso` on the bundle and `bundle/lib/`
- `ldconfig -p | grep keybinder` (host has `/lib/x86_64-linux-gnu/libkeybinder-3.0.so.0`, so the negative case required a stand-in)
- direct execution of the release runner with a broken `libkeybinder-3.0.so.0` ahead of the loader cache via `LD_LIBRARY_PATH`, with and without a Wayland-shaped environment, against a real-library control
- `linux/flutter/generated_plugin_registrant.cc`, `linux/flutter/generated_plugins.cmake`
- full parse of `pubspec.lock` (every package name/version/dependency-kind) plus `pubspec.yaml`, `pubspec.lock` `sdks:` block
- `dart --version`, `flutter --version`
- `.github/workflows/ci.yml`, `.devcontainer/Dockerfile`, `assets/sidecar/requirements.txt`, `tool/provision_sidecar.sh`
- `lib/src/domain/hotkey/global_hotkey.dart`, `hotkey_bind_outcome.dart`; `lib/src/infrastructure/hotkey/{x11_global_hotkey,display_server,hotkey_registrar,hotkey_key_catalogue,hotkey_manager_registrar,wayland_portal_global_hotkey}.dart`; `lib/src/infrastructure/system/daemon_startup.dart`; `lib/src/infrastructure/config/default_app_config.dart`
- PyPI JSON API for `claude-agent-sdk` (`info.version` = 0.2.138)
- current Claude model reference for `claude-sonnet-5` validity

Sources: [claude-agent-sdk on PyPI](https://pypi.org/project/claude-agent-sdk/)

---

## Disposition — 2026-09-26

The original review measured a different dependency graph and architecture revision. These are current repository/source dispositions only; the older loader experiment and upstream release check were not rerun.

| Finding | Status | Current evidence and limit |
| --- | --- | --- |
| F1 (catalogue refusal value) | Accepted; source-level closure | AD-12 now requires `HotkeyBound(previous)` when a previously granted shortcut survives. `X11GlobalHotkey._refusedBeforeBackend` returns that value through `_abandonedRebind`; it returns `HotkeyUnavailable(keyRefused, …)` only when nothing was held. |
| F2 (under-inclusive refusal list) | Accepted in the contract | AD-12 now says “include, and are not limited to” and explicitly names the successful-but-discarded `BindShortcuts` read-back and refused X11 release. `WaylandPortalGlobalHotkey` checks the returned shortcuts map for its ID before reporting a grant. The list is illustrative, not a new exhaustive proof of all adapter branches. |
| F3 (phantom no-display refusal) | Still open as wording | `DisplayServer.fromEnvironment` returns X11 when neither session type nor Wayland socket identifies Wayland (`lib/src/infrastructure/hotkey/display_server.dart`). AD-12 still lists “a session that identifies no display server” as a peer refusal; the actual refusal, if any, comes from the selected adapter after that total fallback. |
| F4 and F5 (keybinder loader and X11 annotation) | Superseded | The Stack and operational envelope now describe `X11KeyGrabRegistrar` over libX11 FFI. `pubspec.yaml` removed `hotkey_manager`, and `linux/flutter/generated_plugins.cmake` no longer lists it. The old release-bundle loader experiment is historical and does not establish the behavior of this build. |
| F6 (Stack exception count) | Accepted | The Stack includes the direct `test` dev dependency and omits removed `drift_flutter`; the current manifests agree on both. The section calls its check a dated manifest reconciliation, not an evergreen gate. |
| F7 (upstream SDK freshness) | Superseded as a dated observation | `assets/sidecar/requirements.txt` still pins `claude-agent-sdk==0.2.132`, while the Stack cites that file and says upstream latest was outside its 2026-09-26 check. No current PyPI result is asserted here; package freshness remains unverified. |
| F8 (Conventions error wording) | Still open as prose | AD-9 and AD-12 now define the complete `HotkeyBindOutcome` shape, but the Consistency Conventions “Errors” row still lists `HotkeyRegistration` and `HotkeyUnavailable` without `HotkeyBound`, and says exceptions signal programmer error only. The infrastructure-private `HotkeyRegistrar` may reject internally; its adapter reduces that to a port value. Clarifying the row would make the boundary explicit. |

No new review pass, test, gate, CI change, or runtime observation is implied by these statuses.

## Post-plan closure — 2026-09-26

**F3's phantom no-display-server refusal is closed in the generated spine.** Commit `68eb358` updated the BMAD memlog and regenerated AD-12 (`ARCHITECTURE-SPINE.md:348`) to state that absent session hints select X11, then a failed `XOpenDisplay` yields `noBackend`. This matches `DisplayServer.fromEnvironment`'s total fallback (`lib/src/infrastructure/hotkey/display_server.dart:27-44`). The owner reports three focused reviewers passed and existing fallback tests passed 10/10. The old F3 row remains accurate for the 02-22 commit point; this closure does not claim a native session was observed.
