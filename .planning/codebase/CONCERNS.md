<!-- refreshed: 2026-08-30 -->
# Codebase Concerns

**Analysis Date:** 2026-08-30

## Test Coverage Gaps

### Unobserved Integration Tests

**Desktop entries and instalation (DW-9, DW-26):**
- What's not tested: End-to-end desktop entry installation and desktop recognition
- Files: `test/platform/desktop_entries_live_test.dart` (intentionally skipped, no body)
- Risk: Desktop entries may not be installed correctly or may not be read by the compositor
- Priority: High
- Reason skipped: No compositor, no XDG_RUNTIME_DIR, no xdg-desktop-portal in container
- Owed on: Real GNOME/KDE desktop sessions

**Tray indicator appearance and interaction (DW-9, DW-26):**
- What's not tested: Icon rendering in tray, menu functionality, state visibility on real tray
- Files: `test/platform/tray_live_test.dart` (intentionally skipped, no body)
- Risk: Icon may not appear, menu may not open, degraded state not visible
- Priority: High
- Reason skipped: No StatusNotifier/AppIndicator host, no display (:10 auth required, no Xvfb/xvfb-run)
- Current substitute: `test/platform/tray_manager_tray_test.dart` tests menu wiring against a fake; `test/platform/tray_manager_tray_icon_test.dart` tests channel translation against mock

**Panel visibility on real desktop (DW-9, DW-26):**
- What's not tested: Panel focused/visible state, focus-loss dismissal, real clipboard interaction, window fitting
- Files: `test/platform/correction_panel_live_test.dart` (intentionally skipped, no body)
- Risk: Panel may not focus, may flicker on hide, clipboard writes may fail silently
- Priority: High
- Reason skipped: No compositor, no reachable X display
- Current substitute: Widget tests prove editor focus inside tree, not toplevel keyboard focus; FakeClipboardPort proves copy flow

**X11/Wayland hotkey binding (real session):**
- What's not tested: Actual hotkey grab on X11 (no automated suite — the FFI seam needs a live X server; exercised by hand against Xvfb in phase 1), Wayland portal registration and triggering
- Files: `test/platform/x11_hotkey_live_test.dart`, `test/platform/wayland_hotkey_live_test.dart` (both intentionally skipped)
- Risk: Hotkeys may not register with session, may not trigger when pressed, may interfere with other applications
- Priority: High
- Current substitute: `test/infrastructure/hotkey/*_test.dart` test adapter internals against a fake seam. The headless channel-wiring suite was removed in phase 1 with the plugin it drove, and has no replacement: `X11KeyGrabRegistrar` cannot be driven by a mocked channel

**Settings screen interaction (real desktop):**
- What's not tested: Settings UI visible and responsive, hotkey field accepts input, dropdown navigation
- Files: `test/platform/settings_screen_live_test.dart` (intentionally skipped, no body)
- Risk: Settings may be inaccessible or unresponsive
- Priority: Medium
- Reason skipped: No display, no portal, no session bus
- Current substitute: `test/ui/settings/settings_screen_config_test.dart` tests widget tree layout

### Sidecar Streaming (Live Test)

**Claude Agent SDK correction streaming (live):**
- Files: `test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart`
- What could be missing: Parser state recovery, timeout edge cases during slow networks, multi-chunk deltas

## Fragile Areas

### Panel Visibility Reconciliation (1292 lines)

**File:** `lib/src/infrastructure/panel/window_manager_panel_visibility.dart`

**Why fragile:** This module implements four interdependent mechanisms that hold together only under specific conditions:

1. **Mirror leads before first await**: State is updated before awaiting platform calls, creating a race condition window where the mirror can diverge from reality if a late-landing abandoned call arrives
2. **Request serialization via queue**: Prevents reordering but creates a chain: if one call hangs, all subsequent presses fail until restart
3. **Superseded requests are abandoned, not cancelled**: Dart has no cancellation, so a late-arriving call from a superseded request can resurrect the panel or put it away unexpectedly
4. **Timeout as trade-off**: Each call runs under `_requestTimeout` (not specified in constants). An abandoned call still in flight can collide with the next request, creating race conditions

**Known defects:**
- **DW-30** (resolved): Focus-loss hide could resurrect panel via abandoned `focus()` call that maps hidden toplevel. Mitigation: `_visible` gate added to `restore` arm.
- **DW-31** (resolved): Minimize echo was swallowed when it should be believed. Mitigation: `minimize` moved outside `_outstanding` guard.
- **DW-12** (resolved): Close event filtering necessary because plugin emits `close` *before* reading prevent-close flag, arriving with toplevel still mapped.

**Safe modification:** Changes to reconciliation logic must account for all three axes (echo-capable, mirror claim, visibility state). The `_outstanding` guard is load-bearing. Test changes against `test/architecture/panel_event_forwarding_test.dart`.

### Wayland Portal Global Hotkey (1307 lines)

**File:** `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`

**Why fragile:**
- **Portal behavior is opaque**: Portal returns only `description` and `trigger_description`, not machine-readable binding. Reconstructing a binding would fail silently (AGENTS.md §1), so `effective` is always null.
- **Race condition in shortcut registration**: A caller subscribing only after registration can miss the initial state. Buffering mechanism with `_ensureSubscription()` exists to close this window.
- **Compositor-side changes are async**: Portal emits `ShortcutsChanged` asynchronously. A change in the compositor is now visible on the settings surface via `_onShortcutsChanged` emit, but timing is nondeterministic.
- **DBusClient can throw at construction**: Constructor parses `DBUS_SESSION_BUS_ADDRESS` eagerly. Wrapped in factory to catch and report, not crash startup.

**Known limitations:**
- Portal must have installed `.desktop` file or bind silently fails with success response (empty shortcuts list)
- Backend-specific behavior: wlroots compositors have no GlobalShortcuts backend at all
- Older portals (pre-1.20) lack Registry interface entirely

**Safe modification:** Verify all four AD-11 steps in order. Changes to the signal subscription must maintain the buffering guarantee. Test against `test/infrastructure/hotkey/wayland_portal_global_hotkey_test.dart`.

### Correction Controller (840 lines)

**File:** `lib/src/application/correction_controller.dart`

**Why fragile:**
- **Session token and dismissal latch**: Two monotonic tokens carry lifecycle rules. The `_dismissalStands` latch is load-bearing for AD-18's three-way rule (only dismissal ends a session, not every departure).
- **Persistence happens on every terminal event**: AD-4 requires persistence even when hidden. A correction arriving after panel re-seeded is persisted then dropped from view—this asymmetry is fragile if correction timing changes.
- **Visibility subscription error-guarded but not rejecting**: An error on the visibility stream must not end the subscription. Errors are logged and ignored, which is correct per AD-15 but means a broken visibility adapter goes silent.
- **Stream backpressure**: The broadcast controller has no backpressure. If both panel and tray subscribe but one pauses, the other still receives events, which could cause state inconsistency.

**Safe modification:** Changes to session lifecycle must preserve the three-way rule. Test against `test/application/correction_controller_test.dart` and `test/composition/daemon_graph_test.dart`.

## Concurrency Issues

### Abandoned Platform Calls

**Problem:** `WindowManagerPanelVisibility` issues platform calls under `_requestTimeout`, but Dart has no cancellation. A timeout doesn't stop the call—it just stops waiting for it. A late-arriving response can:
- Map a dismissed panel via abandoned `focus()` (DW-30 mitigation: `_visible` gate)
- Unmap a shown panel via abandoned `hide()` → `dismissed` event → next press re-seeds (costs user's text)
- Show a panel after user hid it via abandoned `show()` → `shown` event → panel reappears

**Impact:** Race condition window between timeout and late arrival. Mirror goes out of sync. Only fixed by next window event.

**Files:** `lib/src/infrastructure/panel/window_manager_panel_visibility.dart`

### Process Group Termination

**Problem:** Sidecar spawned with `setsid` (process group leader). Termination uses SIGTERM with 2-second grace, then SIGKILL. If `_teardown()` is never awaited (e.g., stream cancelled during spawn), the process stays resident.

**Impact:** Orphaned processes accumulate if corrections are cancelled rapidly. Python SDK may hang on SIGTERM if network call is in flight.

**Files:** `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` lines 121-128, 184-190

**Mitigation:** `onCancel` callback calls `_teardown()` unconditionally, ensuring process is killed.

### Timer and Future Leaks

**Problem:** Multiple timers and futures are created throughout the daemon lifecycle. If the daemon is force-terminated without cleanup, these may not fire their cleanup arms.

**Impact:** File handles, sockets, DBus connections may not close cleanly on abnormal exit.

**Files:** 
- `lib/main.dart` (error handler setup, multiple `unawaited` calls)
- `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` (deadline timer)
- `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` (signal subscriptions, teardown budget)

## Performance Bottlenecks

### 60-Second Correction Timeout

**Issue:** `ClaudeAgentSdkCorrectionProvider.defaultTimeout = Duration(seconds: 60)`. Generous to bound stalled transport, but a slow model + slow network can legitimately exceed this. User sees timeout failure.

**Files:** `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` line 49

**Current mitigation:** Timeout is configurable via settings (`timeoutSettingsKey`), but default is generous not adaptive.

### Panel Visibility Queue Serialization

**Issue:** Each `show()`/`hide()` request is chained onto the previous one via queue. If a single platform call hangs, the entire queue parks. Next press waits for timeout before being served.

**Impact:** User presses hotkey, waits for `_requestTimeout` to expire, then gets response. Perceived lag on every press if window manager is slow.

**Files:** `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` lines 443-456

**Trade-off:** Accepted because it prevents reordering, which would cost one press. Being parked costs *every* press until restart—worse than reordering.

### Unbounded Parser Output Buffering (Pre-2026)

**Issue:** Stream parser (`register_tagged_stream_parser.dart`) has backpressure handling at the sidecar level but not internally. A slow consumer reading parsed events can cause buffer growth if parser runs ahead.

**Current mitigation:** Backpressure implementation at `_SidecarRun` level (line 97-104) pauses stdout lines when consumer pauses.

**Files:** `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart`, `lib/src/infrastructure/correction/claude_agent_sdk/register_tagged_stream_parser.dart`

## Scaling Limits

### Single Instance Lock

**File:** `lib/src/infrastructure/system/single_instance_lock.dart` (308 lines)

**Current capacity:** Binds to a Unix domain socket. Supports one daemon process per instance file. If instance file is on a slow filesystem or network mount, lock handshake can timeout.

**Limit:** Socket path length is OS-dependent (typically ~100-108 bytes). Long `~/.config/` paths could exceed this.

**Scaling path:** Move to abstract socket namespace or use lockfile instead of socket if portability needed.

### Correction History (Drift Database)

**File:** `lib/src/infrastructure/persistence/drift_correction_repository.dart` (248 lines)

**Current capacity:** SQLite database stored in `~/.config/`. No explicit pruning. History grows unbounded.

**Limit:** SQLite becomes slow on very large databases (millions of rows). No pagination or archival strategy.

**Scaling path:** Implement history retention policy (e.g., delete after N days or rows). Add indices for time-based queries.

## Dependencies at Risk

### DBus Connection Lifecycle

**Risk:** `WaylandPortalGlobalHotkey` holds a `DBusClient` created at construction. If the session bus dies (user logs out, session restarted), the client becomes stale. No reconnection logic.

**Impact:** Daemon continues running but hotkey binding fails silently after session restart.

**Files:** `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` lines 65-80

**Mitigation:** None. Daemon must be restarted to reconnect to new session bus.

### Flutter Window Manager Plugin

**Risk:** `window_manager` plugin behavior is platform-specific and version-dependent. A GTK update changes event timing or adds new event types → mirror desynchronization.

**Impact:** Panel visibility becomes incorrect on desktop update.

**Files:** `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` (entire module)

**Known fragility:** GTK `window-state-event` vs `configure-event` timing. Comments throughout document version-specific workarounds.

### Python Sidecar Availability

**Risk:** Daemon starts without verifying sidecar is executable. First correction fails with `providerUnavailable` if missing. No fallback.

**Impact:** User sees error on first use, must fix settings, restart daemon.

**Files:** `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` lines 157-161

**Mitigation:** Settings validation at startup (not yet implemented). Currently lazy-checked on first correction.

## Error Handling Patterns

### Intentional Error Swallowing

**Areas:** Multiple error swallows are documented as intentional. Changing these is a refactoring, not a bugfix:

- **Visibility stream errors**: `CorrectionController._onVisibilityChanged` ignores errors (AD-15 backstop)
- **Panel state stream errors**: `CorrectionPanel._onStateStreamError` keeps last state, doesn't clear (deliberate)
- **Abandoned platform calls**: Late-arriving responses are swallowed if request was superseded
- **Queue error handling in panel visibility**: Errors on queued futures are logged, queue advances

**Files:**
- `lib/src/application/correction_controller.dart` lines 57-62
- `lib/src/ui/panel/correction_panel.dart` lines 232-239
- `lib/src/infrastructure/panel/window_manager_panel_visibility.dart` lines 50-106 (entire documented mechanism)

**Validation:** These are architectural choices, not bugs. Verify against requirements before changing.

### Recover-by-Restart Pattern

**Pattern:** Several error conditions have no inline recovery:

1. DBus connection dies → daemon must restart to reconnect
2. Wayland portal vanishes → next bind silently fails
3. X server disconnects → application exits (clean by design)
4. Sidecar stdout closes before exit → treated as process death
5. Parser receives unparseable JSON → event dropped silently

**Impact:** Most errors require daemon restart. User experience: app becomes unresponsive, user must close and reopen.

**Files:** `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart`, `lib/src/infrastructure/hotkey/x11_global_hotkey.dart`, `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart`

## Platform-Specific Fragility

### X11 vs Wayland Divergence

**File:** `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart`

**Issue:** X11 implementation uses keybinder-3.0 library; Wayland uses xdg-desktop-portal. Behavior differs significantly:

- **X11 (dart:ffi to libX11.so.6)**: Direct passive grab, synchronous feedback — `XSetErrorHandler` + `XSync` reports a conflicting grab as `BadAccess` before `XSync` returns, so a refusal is readable rather than guessed.
- **Wayland portal**: Mediated by compositor, async signal, no effective binding readback.

**Tests cannot run both simultaneously:** Test file explicitly chooses one adapter at startup via environment check. No way to verify both work on same machine.

**Files:** 
- `lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart` (adapter selection)
- `test/platform/x11_hotkey_live_test.dart` (X11 coverage gap)
- `test/platform/wayland_hotkey_live_test.dart` (Wayland coverage gap)

### GTK Event Timing Assumptions

**File:** `lib/src/infrastructure/panel/window_manager_panel_visibility.dart`

**Issue:** Code assumes specific GTK event ordering:
- `show()` → `isMinimized()` hop → actual show → echo event
- `focus()` is `gtk_window_present` which maps hidden toplevel
- `configure-event` vs `window-state-event` ordering

**Risk:** GTK version update changes timing. Mirror desynchronizes silently.

**Current guard:** Timeout on each call (prevents forever hang) + mirror reconciliation on next event (eventual consistency).

## Missing Critical Features

### Hotkey Effective Binding Readback (Wayland)

**Problem:** Settings screen wants to display "the effective combination in effect" (AD-10). Wayland portal returns only human-readable `trigger_description`, not machine-readable binding.

**Impact:** Settings show "effective binding: Not available" instead of the actual key combo.

**Files:** `lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart` lines 31-42

**Status:** Documented and accepted. Portal API does not expose effective binding.

### Adaptive Correction Timeout

**Problem:** 60-second timeout is generous but could fail on slow networks. No adaptive backoff or user feedback.

**Impact:** User waits 60 seconds in silence, then sees timeout error with no way to increase timeout mid-correction.

**Files:** `lib/src/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_correction_provider.dart` line 49

**Owed:** UI feedback (e.g., progress indicator, cancel button), adaptive timeout based on model complexity.

### History Retention Policy

**Problem:** Correction history grows unbounded in SQLite database. No pruning, no archival.

**Impact:** Very old daemons accumulate megabytes of history, slowing queries.

**Files:** `lib/src/infrastructure/persistence/drift_correction_repository.dart`

**Owed:** Retention policy (e.g., delete after 90 days), export/archive feature.

### Composition Root Error Recovery

**File:** `lib/main.dart` (864 lines)

**Problem:** If any startup step throws (ports fail, graph cannot build, lifecycle setup fails), the daemon exits. No retry, no graceful degradation.

**Impact:** Desktop session has no daemon and no indication why (error is logged to stderr, not shown to user).

**Owed:** User-facing error UI, or retry logic with backoff.

---

*Concerns audit: 2026-08-30*
