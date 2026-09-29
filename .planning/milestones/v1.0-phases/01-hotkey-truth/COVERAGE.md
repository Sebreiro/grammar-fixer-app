# API Coverage — `org.freedesktop.portal.GlobalShortcuts` (+ `org.freedesktop.host.portal.Registry`)

> Full coverage by default. Opt-outs are explicit, reasoned decisions.

**Why this file exists.** The deterministic detector returned `{"detected":false,"signals":[]}` — a
real negative, not a skip — when it ran over the ROADMAP section, which was the only scope available
before any PLAN.md existed. Re-checked against the plan bodies as written, the phase does newly
integrate one previously-uncalled method of an external D-Bus service (`ListShortcuts`, plan 01-06)
and makes another conditional (`Registry.Register`, plan 01-05). That is enough of an external-API
surface to be worth deciding explicitly rather than leaving to a seal-time re-probe. The matrix is
produced rather than skipped.

**Scope note.** This is not a new integration: the GlobalShortcuts handshake ships today in
`lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`. The matrix therefore records the
*whole* surface, marking what already ships, what this phase adds, and what is deliberately not used.

| capability | decision | reason |
|---|---|---|
| `Registry.Register` | INTEGRATE | Ships today. Plan 01-05 makes it conditional on a sandbox predicate: the spec says the interface will not work for portal-identified sandboxed apps, and D-18 puts Flatpak in the packaging set. |
| `GlobalShortcuts.CreateSession` | INTEGRATE | Ships today. AD-11 step 2. Plan 01-05 bounds it, since no portal dialog sits behind it. |
| `GlobalShortcuts.BindShortcuts` | INTEGRATE | Ships today. AD-11 step 3, with the read-back that tells a portal which took the bind from one which discarded it. Outside the short timeout budget (plan 01-05) — it is the step a human answers. |
| `GlobalShortcuts.ListShortcuts` | INTEGRATE | **Newly integrated by plan 01-06.** The on-demand re-read behind D-01's "show what is currently in effect" — the compositor's report, not our echo. Reuses the existing Request/Response machinery. |
| `GlobalShortcuts.Activated` (signal) | INTEGRATE | Ships today. CAP-1's entire press path. Sender-filtered — an unfiltered subscription would let any session-bus peer forge a summon of a panel that reads the clipboard. |
| `GlobalShortcuts.Deactivated` (signal) | OPT-OUT | Not needed — the panel is a press-toggle (AD-8), so there is no key-release behaviour to model. Subscribing would deliver events with no consumer. |
| `GlobalShortcuts.ShortcutsChanged` (signal) | INTEGRATE | Ships today. Carries D-01's silent update and D-08's revocation. Sender-filtered. Plan 01-06 makes it carry the description; plan 01-04 gives its revocation branch a machine-readable cause. |
| `Request.Response` (signal) | INTEGRATE | Ships today. Every portal call resolves through it, matched on the portal's resolved unique bus name with a `Random.secure()` handle token. |
| `Request.Close` | INTEGRATE | Ships today, on the teardown path only. Plan 01-05 explicitly forbids sending it on a timeout path — cancelling a dialog the user is answering is the failure Pitfall 4 names. |
| `Session.Close` | INTEGRATE | Ships today. The spec allows binding a session's shortcuts only once, so a rebind closes the old session first; two interleaved rebinds would otherwise leave a live untracked session. |
| `Session.Closed` (signal) | OPT-OUT | Not needed yet — the adapter tracks session lifecycle via `_queue`/`_session` and closes explicitly on teardown. A compositor-initiated close surfaces as a failed later call, already handled. |
| `GlobalShortcuts` version property | OPT-OUT | Not needed — the adapter tolerates older portals via documented exception arms on the Register path (`UnknownMethod`, `UnknownInterface`, `UnknownObject`): behaviour-based, not version-based. |

**Not an external API, recorded so the boundary is clear.** The X11 side of this phase
(`XGrabKey`, `XUngrabKey`, `XSetErrorHandler`, `XSync`, `XNextEvent`, `XKeysymToKeycode`,
`XStringToKeysym`, `XRefreshKeyboardMapping`, `XOpenDisplay`, `XCloseDisplay`) is a native library
called over `dart:ffi`, not a network or service API. Its surface is bounded by what a passive grab
needs, and deliberately narrow: no `XGrabKeyboard`, no `AnyKey`, no `AnyModifier` — a wider grab
would observe keystrokes the user never bound.
