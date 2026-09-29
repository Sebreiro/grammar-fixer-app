#!/usr/bin/env bash
# Live probe (phase 01, gap G-01-15 == 01-REVIEW.md CR-02). Kills the X11 key-grab
# worker isolate for real, mid-rebind, against a real release bundle built at a
# revision the caller names, and reads what the settings screen then says.
#
# Usage: tool/uat/worker_gone_probe.sh --at <rev> [--label <name>]
#        one case: rebind-worker-gone
#
# EXACTLY ONE THING IN THE RUN IS CONTRIVED, AND IT IS NAMED EVERYWHERE.
# Nothing outside this process can kill this daemon's worker isolate on demand:
# `_X11Worker.handle` carries no `on Object` guard and `Isolate.spawn` defaults to
# `errorsAreFatal: true`, so a Dart throw on the grab path really is fatal to the
# worker — but every throw the worker can actually take today is already guarded
# into a modelled refusal (`_openBindings` catches the whole `_X11Bindings`
# construction; `_openDisplay` reads a null pointer as a value). That is a finding
# in its own right: the `workerGone` arm is reachable in production and unreachable
# from outside the process. So the worker death is INJECTED — a throw at the top of
# `_X11Worker._grab`, keyed on the marker key F9 — and everything downstream of the
# injection is the shipped chain: the `onError` port, `_failPending`, `_refusalFor`,
# the adapter's cause-decides arm, `_recordStatus`, and the rendered sentence.
# What the injection changes is WHY the worker died, not WHAT the code did about it.
#
# The injection is applied ONLY inside a detached `git worktree` created under a
# `mktemp -d -t worker-gone-probe.XXXXXXXX` root, which the exit trap removes on
# every path including halts (T-01-80). Nothing here uses `git checkout --` or
# `git stash`: those destroy an uncommitted patch rather than restoring one.
#
# Not `set -e`: a run that fails must still be reported and must still clean up.
set -uo pipefail

readonly APP_CLASS='com.divertedriver.HotkeyGrammarCorrector'
readonly BUNDLE_REL='build/linux/x64/release/bundle/hotkey_grammar_corrector'
# The AOT snapshot, not the launcher: the launcher carries no Dart code and its
# mtime is a known-stale freshness signal (panel-toggle-observation.md, T-01-65).
readonly SNAPSHOT_REL='build/linux/x64/release/bundle/lib/libapp.so'
# The bracket keeps the pattern from matching the shell that runs the pkill.
readonly DAEMON_PAT='bundle/hotkey_grammar_correcto[r]'
readonly FLUTTER_BIN_DEFAULT='/home/vscode/flutter/bin'

# The combination the daemon starts bound to, and the one the rebind asks for.
# `F9` is in `HotkeyKeyCatalogue`'s F1-F12 run, so the startup bind of `g` succeeds
# and `_effective` is genuinely set, and the rebind is the one press that kills the
# worker. Two modifiers, so D-13's at-least-one-modifier rule is satisfied and the
# capture field accepts it.
readonly BOUND='Ctrl+Shift+G'
readonly REQUESTED='Ctrl+Shift+F9'
readonly MARKER_KEY='F9'

export DISPLAY="${DISPLAY:-:99}"

REPO_ROOT=""
REV_ARG=""
REV_SHA=""
REV_SHORT=""
LABEL="run"
TMP_ROOT=""
WORKTREE=""
XDG_ROOT=""
OUT_DIR=""
DAEMON_SID=""
DAEMON_PID=""
DAEMON_LOG=""
DAEMON_STARTED=0
CLIPBOARD_OWNER_PID=""
TOPLEVEL=""
DIFF_FILE=""
SCREEN=""
SOURCE_TREES_WERE_CLEAN=0

# --- halting -----------------------------------------------------------------
# A halt is never a verdict. Every one names its step and exits non-zero.
die() {   # preflight
  printf 'HALT (preflight): %s\n' "$1" >&2
  exit 2
}

halt() {  # mid-run; $1 is the step name, $2 the reason
  printf 'HALT (%s): %s\n' "$1" "$2" >&2
  if [ -n "$TOPLEVEL" ]; then
    printf 'HALT window=%s\n' "$TOPLEVEL" >&2
    local shot
    shot="${OUT_DIR:-/tmp}/halt-$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-').png"
    if shot_window "$shot"; then
      printf 'HALT screenshot=%s\n' "$shot" >&2
    fi
  fi
  exit 3
}

# --- teardown ----------------------------------------------------------------
# Only ever this run's own daemon, and only ever the daemon this run launched.
# The exit trap is armed before the preflight, so teardown fires on the very path
# that refused to run BECAUSE a daemon is already up — a signal sent from here
# would kill the process the halt message just told the operator to stop by hand,
# discarding whatever that daemon held in its panel. The process match names the
# bundle inside the throwaway worktree this run built, so a release bundle a
# developer is running out of the main repository is outside the pattern.
stop_daemon() {
  [ "$DAEMON_STARTED" = 1 ] || return 0
  if [ -n "$DAEMON_SID" ]; then
    kill -TERM -- "-${DAEMON_SID}" >/dev/null 2>&1
  fi
  pkill -f "${WORKTREE}/${BUNDLE_REL}" >/dev/null 2>&1
  local i=0
  while pgrep -f "${WORKTREE}/${BUNDLE_REL}" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 150 ] && break
    sleep 0.1
  done
  DAEMON_SID=""; DAEMON_PID=""; TOPLEVEL=""
}

# Runs on EVERY path, including halts. A probe that leaks a patched worktree is
# worse than a probe that does not run.
cleanup() {
  stop_daemon
  # Only the selection owner this run started, on the same discipline as
  # stop_daemon: a run that halted before the clipboard gate signals nothing.
  [ -n "$CLIPBOARD_OWNER_PID" ] && kill "$CLIPBOARD_OWNER_PID" >/dev/null 2>&1
  # From the repository root, never from inside the worktree being removed.
  if [ -n "$WORKTREE" ] && [ -n "$REPO_ROOT" ] && cd "$REPO_ROOT"; then
    git worktree remove --force "$WORKTREE" >/dev/null 2>&1
    git worktree prune >/dev/null 2>&1
  fi
  [ -n "$TMP_ROOT" ] && rm -rf "$TMP_ROOT"
  # Only when nothing was written into it — a halt before the first screenshot
  # should not leave an empty directory behind, and a run that produced evidence
  # must keep it.
  [ -n "$OUT_DIR" ] && rmdir "$OUT_DIR" >/dev/null 2>&1
  assert_no_trace
}

# The exit assertion, in the SAME scope the preflight gate used.
assert_no_trace() {
  [ -n "$REPO_ROOT" ] || return 0
  local dirty leaked=0
  dirty=$(git -C "$REPO_ROOT" status --porcelain -uno -- lib/ test/ tool/ 2>/dev/null)
  # Only meaningful once the preflight gate proved the trees were clean to begin
  # with: a run refused BECAUSE the trees were dirty would otherwise report the
  # developer's own work in progress as the probe's leak, which is the one thing
  # this assertion exists to tell apart.
  if [ "$SOURCE_TREES_WERE_CLEAN" != 1 ]; then
    dirty=""
  fi
  if [ -n "$dirty" ]; then
    printf '!!! PROBE LEFT A TRACE: tracked files under lib/, test/ or tool/ are modified:\n%s\n' \
      "$dirty" >&2
    leaked=1
  fi
  # The probe's OWN temp root, never a global worktree count: a count of one is
  # true in this tree today and false the moment phase execution is itself
  # worktree-isolated, and a gate that fails for a reason unrelated to the probe
  # teaches its reader to ignore it.
  local stale
  stale=$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | grep 'worker-gone-probe\.')
  if [ -n "$stale" ]; then
    printf '!!! PROBE LEFT A TRACE: a git worktree under its own temp root survives:\n%s\n' \
      "$stale" >&2
    leaked=1
  fi
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    printf '!!! PROBE LEFT A TRACE: its temp root still exists: %s\n' "$TMP_ROOT" >&2
    leaked=1
  fi
  [ "$leaked" -eq 0 ] && return 0
  printf '!!! Remove the above by hand before running anything else.\n' >&2
  return 1
}
trap cleanup EXIT

# --- arguments ---------------------------------------------------------------
parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --at)    REV_ARG="${2:-}"; shift 2 || die "--at needs a revision" ;;
      --label) LABEL="${2:-}"; shift 2 || die "--label needs a name" ;;
      *)       die "unknown argument: $1 (usage: $0 --at <rev> [--label <name>])" ;;
    esac
  done
  [ -n "$REV_ARG" ] || die "no revision given (usage: $0 --at <rev> [--label <name>])"
  [ -n "$LABEL" ] || die "--label was given an empty name"
}

# --- preflight ---------------------------------------------------------------
require_unowned_clipboard() {
  # TARGETS answers only while a client owns the selection. Payload reads can
  # appear empty for newline-only text or an empty non-text target.
  if xclip -selection clipboard -o -t TARGETS -d "$DISPLAY" >/dev/null 2>&1; then
    die "another clipboard owner is active on $DISPLAY — use a dedicated display or clear the selection yourself"
  fi
}

preflight() {
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
    || die "not inside a git repository"
  cd "$REPO_ROOT" || die "cannot enter the repository root $REPO_ROOT"

  if ! command -v flutter >/dev/null 2>&1 && [ -x "$FLUTTER_BIN_DEFAULT/flutter" ]; then
    export PATH="$PATH:$FLUTTER_BIN_DEFAULT:$FLUTTER_BIN_DEFAULT/cache/dart-sdk/bin"
  fi

  xdpyinfo >/dev/null 2>&1 \
    || die "DISPLAY=$DISPLAY does not answer (start: Xvfb :99 -screen 0 1440x900x24 -nolisten tcp)"
  xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id' \
    || die "no window manager is running on $DISPLAY (start: openbox)"

  local t
  for t in xdotool xwininfo xprop import compare dbus-run-session python3 git flutter xclip; do
    command -v "$t" >/dev/null 2>&1 || die "required tool not on PATH: $t"
  done

  # This probe photographs the panel, which seeds its editor from CLIPBOARD.
  # Refuse a foreign owner before any later preflight failure can alter it.
  require_unowned_clipboard

  # Scoped to TRACKED files under the three source trees, and deliberately not
  # widened to a bare `git status --porcelain`: measured in this repository the
  # bare form returns 87 lines (two tracked `.planning/` modifications and 85
  # untracked files under `.claude/`), none of which a detached-worktree build
  # can reach, so the bare form never opens and this gate would refuse on every
  # invocation. The injection is an edit to a TRACKED file under `lib/`, so a
  # tracked modification in the source trees is exactly the signal worth
  # refusing on. Untracked files are excluded for a second reason too: this
  # script is itself untracked the first time it runs, and a gate that refused
  # on that would refuse on its own existence.
  local dirty
  dirty=$(git status --porcelain -uno -- lib/ test/ tool/)
  if [ -n "$dirty" ]; then
    printf '%s\n' "$dirty" >&2
    die "tracked files under lib/, test/ or tool/ are modified — the worktree this probe builds would be unreproducible, and the run's own exit assertion could not tell the probe's leak from work in progress"
  fi

  SOURCE_TREES_WERE_CLEAN=1

  REV_SHA=$(git rev-parse --verify --quiet "${REV_ARG}^{commit}") \
    || die "not a commit in this repository: $REV_ARG"
  REV_SHORT=$(git rev-parse --short "$REV_SHA")

  if pgrep -f "$DAEMON_PAT" >/dev/null 2>&1; then
    die "a daemon is already running and holds the grab — stop it first (pkill -f '$DAEMON_PAT')"
  fi

  TMP_ROOT=$(mktemp -d -t worker-gone-probe.XXXXXXXX) \
    || die "could not create the probe's temp root"
  WORKTREE="$TMP_ROOT/tree"
  XDG_ROOT="$TMP_ROOT/xdg"
  # Outside the temp root on purpose: the trap removes the temp root, and the
  # screenshot, the daemon log and the injection diff are what the record cites.
  OUT_DIR="${PROBE_OUT_DIR:-/tmp}/worker-gone-probe-out/${LABEL}-${REV_SHORT}-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$OUT_DIR" || die "could not create the output directory $OUT_DIR"
  # 0700 for the reason $XDG_ROOT/rt already is: captures of a clipboard-seeded panel, under a world-traversable /tmp.
  chmod 700 "$OUT_DIR" || die "could not restrict $OUT_DIR"
  DIFF_FILE="$OUT_DIR/injection.diff"

  # The display can change during preflight, so repeat the ownership check at
  # the last point before this run establishes its own empty selection.
  require_unowned_clipboard
  local owners owner
  owners=" $(pgrep -f "xclip -selection clipboard -d $DISPLAY" 2>/dev/null | tr '\n' ' ') "
  printf '' | xclip -selection clipboard -d "$DISPLAY" >/dev/null 2>&1 &
  sleep 0.5
  # xclip forks to serve the selection, so `$!` is not the surviving owner; the
  # pid this run is entitled to signal is the one that was not there before it.
  for owner in $(pgrep -f "xclip -selection clipboard -d $DISPLAY" 2>/dev/null); do
    case "$owners" in *" $owner "*) ;; *) CLIPBOARD_OWNER_PID="$owner" ;; esac
  done
}

# --- the throwaway worktree, and the injection -------------------------------
make_worktree() {
  printf 'WORKTREE creating a detached worktree at %s from %s (%s)\n' \
    "$WORKTREE" "$REV_SHORT" "$REV_SHA"
  git worktree add --detach "$WORKTREE" "$REV_SHA" >/dev/null 2>&1 \
    || halt worktree "git worktree add --detach failed for $REV_SHA"
  touch "$TMP_ROOT/.created" \
    || halt worktree "could not write the creation marker in $TMP_ROOT"
}

inject_fault() {
  local target="$WORKTREE/lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart"
  [ -f "$target" ] || halt inject "the registrar source is missing at $REV_SHORT: $target"
  if ! PROBE_MARKER_KEY="$MARKER_KEY" python3 - "$target" <<'PY'
import os, sys

path = sys.argv[1]
key = os.environ['PROBE_MARKER_KEY']
anchor = '  void _grab(int id, String keysymName, int modifierMask) {\n'
source = open(path, encoding='utf-8').read()
if source.count(anchor) != 1:
    sys.stderr.write('anchor %r found %d times\n' % (anchor, source.count(anchor)))
    sys.exit(1)
patch = (
    "    // PROBE INJECTION - tool/uat/worker_gone_probe.sh, gap G-01-15.\n"
    "    // The one contrived link: nothing outside this process can kill the worker\n"
    "    // isolate on demand. `handle` has no `on Object` guard and `Isolate.spawn`\n"
    "    // defaults to errorsAreFatal, so this throw is fatal to the worker at exactly\n"
    "    // the moment a reply is pending. Everything after the death is the shipped chain.\n"
    "    if (keysymName == '%s') {\n"
    "      throw StateError(\n"
    "        'worker_gone_probe.sh injected worker death for keysymName=$keysymName',\n"
    "      );\n"
    "    }\n" % key
)
open(path, 'w', encoding='utf-8').write(source.replace(anchor, anchor + patch))
PY
  then
    halt inject "could not insert the injection into $target"
  fi

  git -C "$WORKTREE" diff > "$DIFF_FILE" 2>/dev/null
  local files hunks
  files=$(git -C "$WORKTREE" diff --numstat | grep -c .)
  hunks=$(grep -c '^@@' "$DIFF_FILE")
  [ "$files" -eq 1 ] || halt inject "the injection touched $files files, expected exactly 1"
  [ "$hunks" -eq 1 ] || halt inject "the injection produced $hunks hunks, expected exactly 1"
  grep -q 'keysymName' "$DIFF_FILE" || halt inject "the injection diff does not name keysymName"
}

# --- the bundle --------------------------------------------------------------
build_bundle() {
  printf 'BUILD flutter build linux --release in the worktree — a cold build takes several minutes; this is expected, not a hang\n'
  local log="$TMP_ROOT/build.log"
  ( cd "$WORKTREE" && flutter build linux --release ) > "$log" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    tail -30 "$log" >&2
    halt build "flutter build linux --release failed (exit $rc) — tail above, full log $log"
  fi
  local bundle="$WORKTREE/$BUNDLE_REL" snapshot="$WORKTREE/$SNAPSHOT_REL"
  [ -x "$bundle" ] || halt build "no release bundle was produced at $bundle"
  [ -f "$snapshot" ] || halt build "no Dart AOT snapshot was produced at $snapshot"
  # A stale artefact cannot be mistaken for a fresh one: the snapshot must be
  # newer than the worktree itself. The launcher's mtime is NOT the signal —
  # it holds no Dart code (panel-toggle-observation.md, T-01-65).
  [ -n "$(find "$snapshot" -newer "$TMP_ROOT/.created" 2>/dev/null)" ] \
    || halt build "the Dart snapshot is not newer than the worktree — a stale artefact was measured"
  printf 'BUILD bundle=%s snapshot=%s (%s)\n' "$bundle" "$snapshot" \
    "$(date -u -r "$snapshot" +%Y-%m-%dT%H:%M:%SZ)"
}

# --- daemon lifecycle --------------------------------------------------------
# DAEMON_PAT matches dbus-run-session's own command line too (the bundle path is
# one of its arguments), so the app process is identified by the executable it is
# running. _NET_WM_PID names this pid, not the launcher's.
daemon_pids() {
  local p exe
  for p in $(pgrep -f "$DAEMON_PAT" 2>/dev/null); do
    exe=$(readlink -f "/proc/$p/exe" 2>/dev/null)
    case "$exe" in
      */bundle/hotkey_grammar_corrector) printf '%s\n' "$p" ;;
    esac
  done
}

# Per-run XDG tree (T-01-81): never the developer's real config or history
# database. No correction is ever submitted by this probe, so AD-19's Python
# sidecar is never spawned.
start_daemon() {
  mkdir -p "$XDG_ROOT/config" "$XDG_ROOT/data" "$XDG_ROOT/rt" \
    || halt start "could not create the XDG tree under $XDG_ROOT"
  chmod 700 "$XDG_ROOT/rt"
  # In the output directory rather than the XDG tree: the exit trap removes the
  # temp root, and on a halt the daemon's own log is the first thing a reader
  # needs. A halt that destroys its own evidence is a halt nobody can act on.
  DAEMON_LOG="$OUT_DIR/daemon.log"

  DISPLAY="$DISPLAY" XDG_SESSION_TYPE=x11 \
    XDG_CONFIG_HOME="$XDG_ROOT/config" XDG_DATA_HOME="$XDG_ROOT/data" \
    XDG_RUNTIME_DIR="$XDG_ROOT/rt" \
    setsid nohup dbus-run-session -- "$WORKTREE/$BUNDLE_REL" \
    > "$DAEMON_LOG" 2>&1 < /dev/null &
  DAEMON_SID=$!
  # Immediately, not after the readiness loop below: a daemon that launched but
  # never resolved to a pid is still this run's to stop.
  DAEMON_STARTED=1

  local i=0 pids
  while [ "$i" -lt 300 ]; do
    pids=$(daemon_pids)
    if [ "$(printf '%s\n' "$pids" | grep -c .)" -eq 1 ]; then
      DAEMON_PID=$(printf '%s' "$pids" | tr -d '[:space:]')
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  halt start "no daemon process appeared within 30 s — see $DAEMON_LOG"
}

# Keep only ids whose _NET_WM_PID is the daemon's, that xwininfo can report on,
# and that the WM was told to manage as NORMAL (the class also matches GTK's
# 10x10 hidden group-leader window). Require exactly one survivor.
resolve_toplevel() {
  local i=0 candidates survivors id wmpid last=""
  while [ "$i" -lt 300 ]; do
    survivors=()
    candidates=$(xdotool search --class "$APP_CLASS" 2>/dev/null)
    last=$(printf '%s' "$candidates" | tr '\n' ' ')
    for id in $candidates; do
      wmpid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | grep -oE '[0-9]+$')
      [ "$wmpid" = "$DAEMON_PID" ] || continue
      xwininfo -id "$id" 2>/dev/null | grep -q 'Map State' || continue
      xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null \
        | grep -q '_NET_WM_WINDOW_TYPE_NORMAL' || continue
      survivors+=("$id")
    done
    if [ "${#survivors[@]}" -eq 1 ]; then
      TOPLEVEL="${survivors[0]}"
      printf 'TOPLEVEL window=%s _NET_WM_PID=%s class=%s\n' "$TOPLEVEL" "$DAEMON_PID" "$APP_CLASS"
      return 0
    fi
    if [ "${#survivors[@]}" -gt 1 ]; then
      halt toplevel "expected exactly one toplevel for pid $DAEMON_PID, found ${#survivors[@]} — candidates: $last"
    fi
    i=$((i + 1))
    sleep 0.1
  done
  halt toplevel "no NORMAL toplevel for pid $DAEMON_PID appeared within 30 s — candidates: ${last:-none} — see $DAEMON_LOG"
}

# The config the daemon wrote for itself, asserted rather than hand-seeded: the
# shipped defaults derive two provider settings from the running host, so a
# hand-built file would either duplicate that derivation or change what the
# daemon does at startup. What this run needs from the config is one fact, and
# it is checked rather than assumed.
confirm_bound_combination() {
  local config="$XDG_ROOT/config/hotkey-grammar-corrector/config.json"
  local i=0
  while [ "$i" -lt 100 ] && [ ! -f "$config" ]; do
    i=$((i + 1))
    sleep 0.1
  done
  [ -f "$config" ] || halt config "the daemon wrote no config file at $config"
  local combination
  combination=$(python3 - "$config" <<'PY'
import json, sys
binding = json.load(open(sys.argv[1], encoding='utf-8'))['hotkeyBinding']
order = {'control': 0, 'alt': 1, 'shift': 2, 'meta': 3}
names = {'control': 'Ctrl', 'alt': 'Alt', 'shift': 'Shift', 'meta': 'Super'}
mods = sorted(binding['modifiers'], key=lambda m: order.get(m, 9))
print('+'.join([names.get(m, m) for m in mods] + [binding['key']]))
PY
)
  [ "$combination" = "$BOUND" ] \
    || halt config "the daemon started bound to '$combination', not '$BOUND' — this run needs a genuinely held grab to lose"
  printf 'CONFIG %s hotkeyBinding=%s\n' "$config" "$combination"
}

# --- X surfaces --------------------------------------------------------------
map_state() { xwininfo -id "$TOPLEVEL" 2>/dev/null | awk '/Map State/ {print $NF}'; }

win_geometry() {  # X Y W H, absolute
  xwininfo -id "$TOPLEVEL" 2>/dev/null | awk '
    /Absolute upper-left X/ {x=$NF}
    /Absolute upper-left Y/ {y=$NF}
    /^  Width:/  {w=$NF}
    /^  Height:/ {h=$NF}
    END {print x, y, w, h}'
}

shot_window() { import -window "$TOPLEVEL" "$1" >/dev/null 2>&1; }

# Differing pixels between two captures of the same window. The confirmation a
# GUI step actually landed: this container has no OCR and no accessibility
# bridge, so what a step changed on screen is the signal available, and a step
# that changed nothing is a step that did not happen.
pixels_changed() {
  compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1+0; exit}'
}

# One click, REQUIRED to change the window. Never a blind sleep followed by an
# assumption: a click that changes nothing halts by step name.
click_confirmed() {  # x y minimum-pixels step-name
  local x="$1" y="$2" minimum="$3" step="$4"
  local before="$OUT_DIR/step-$step-before.png" after="$OUT_DIR/step-$step-after.png"
  shot_window "$before" || halt "$step" "could not capture the window before the click"
  xdotool mousemove "$x" "$y" click 1 >/dev/null 2>&1 \
    || halt "$step" "xdotool could not click at $x,$y"
  sleep 1.5
  shot_window "$after" || halt "$step" "could not capture the window after the click"
  local changed
  changed=$(pixels_changed "$before" "$after")
  [ "${changed:-0}" -ge "$minimum" ] \
    || halt "$step" "the click at $x,$y changed $changed pixels, fewer than the $minimum this step must change — the control was not where it was clicked"
  printf 'STEP %s click=%s,%s changed=%s px\n' "$step" "$x" "$y" "$changed"
}

# --- the run -----------------------------------------------------------------
# Confirm the starting state before contriving anything: the daemon must
# actually hold the grab. A run that observes nothing must never be mistaken for
# a working daemon, and this is what makes BOUND= in the result line a
# measurement rather than a restatement of the config file.
confirm_grab_held() {
  local before after i=0
  before=$(map_state)
  [ "$before" = IsUnMapped ] \
    || halt warm-up "the panel is already $before before any press — the starting state is not the hidden panel this run needs"
  xdotool key --clearmodifiers ctrl+shift+g >/dev/null 2>&1 \
    || halt warm-up "xdotool could not send Ctrl+Shift+G"
  while [ "$i" -lt 100 ]; do
    after=$(map_state)
    [ "$after" = IsViewable ] && { printf 'GRAB %s mapped the panel (%s -> %s)\n' "$BOUND" "$before" "$after"; return 0; }
    i=$((i + 1))
    sleep 0.1
  done
  halt warm-up "$BOUND did not map the panel within 10 s (Map State is still $(map_state)) — the daemon does not own the grab, so nothing this run observed could be trusted"
}

# AD-14's second launch is the route to a raised panel where there is no tray
# host, and this container has none. Used only when the panel is not already up.
raise_panel() {
  [ "$(map_state)" = IsViewable ] && { printf 'PANEL already mapped\n'; return 0; }
  XDG_SESSION_TYPE=x11 XDG_CONFIG_HOME="$XDG_ROOT/config" \
    XDG_DATA_HOME="$XDG_ROOT/data" XDG_RUNTIME_DIR="$XDG_ROOT/rt" \
    "$WORKTREE/$BUNDLE_REL" > "$XDG_ROOT/second-launch.log" 2>&1
  local i=0
  while [ "$i" -lt 100 ]; do
    [ "$(map_state)" = IsViewable ] && { printf 'PANEL raised by AD-14 second launch\n'; return 0; }
    i=$((i + 1))
    sleep 0.1
  done
  halt raise-panel "the panel did not map after AD-14's second launch — see $XDG_ROOT/second-launch.log"
}

# Drive the rebind through the real settings screen: gear, capture field, the
# combination, Apply. Every step is confirmed or is a named halt.
drive_rebind() {
  local geo x y w h
  geo=$(win_geometry)
  x=$(printf '%s' "$geo" | cut -d' ' -f1)
  y=$(printf '%s' "$geo" | cut -d' ' -f2)
  w=$(printf '%s' "$geo" | cut -d' ' -f3)
  h=$(printf '%s' "$geo" | cut -d' ' -f4)
  printf 'WINDOW geometry=%sx%s at %s,%s\n' "$w" "$h" "$x" "$y"
  # The offsets below are measured from this app's own layout at 1280x720 and
  # are stable for any window big enough to hold the controls: the settings body
  # stacks from the top-left, and the status view is one line at this point in
  # the run. A window too small for them is a halt, not a guess.
  [ "$w" -ge 640 ] && [ "$h" -ge 400 ] \
    || halt geometry "the toplevel is ${w}x${h}; the settings controls this run drives need at least 640x400"

  # The gear, overlaid at the panel's top-right (daemon_home.dart:223).
  click_confirmed "$((x + w - 17))" "$((y + 16))" 5000 settings-gear

  # The capture surface. Arming it is what makes the next press a capture.
  click_confirmed "$((x + 142))" "$((y + 165))" 300 arm-capture-field

  # The one press that kills the worker — captured into the field, not grabbed.
  local before="$OUT_DIR/step-capture-before.png" after="$OUT_DIR/step-capture-after.png"
  shot_window "$before" || halt capture "could not capture the window before the press"
  xdotool key --clearmodifiers ctrl+shift+F9 >/dev/null 2>&1 \
    || halt capture "xdotool could not send Ctrl+Shift+F9"
  sleep 1.5
  shot_window "$after" || halt capture "could not capture the window after the press"
  local changed
  changed=$(pixels_changed "$before" "$after")
  [ "${changed:-0}" -ge 200 ] \
    || halt capture "pressing Ctrl+Shift+F9 changed $changed pixels — the field did not take the combination, so Apply would ask for the combination already in effect"
  printf 'STEP capture pressed=%s changed=%s px\n' "$REQUESTED" "$changed"

  # Apply. The confirmation is the daemon's own log line, which is the same
  # surface this run classifies from: a missed Apply produces no bind at all.
  LOG_LINES_BEFORE=$(grep -c . "$DAEMON_LOG")
  click_confirmed "$((x + 56))" "$((y + 284))" 100 apply
}

await_bind_outcome() {
  local i=0 new
  while [ "$i" -lt 150 ]; do
    new=$(tail -n +"$((LOG_LINES_BEFORE + 1))" "$DAEMON_LOG" | grep -c 'the X11 key grab was refused')
    [ "${new:-0}" -ge 1 ] && { sleep 1.5; return 0; }
    i=$((i + 1))
    sleep 0.1
  done
  halt apply "no bind outcome reached the daemon log within 15 s of Apply — either Apply was not pressed or the grab never resolved; the log since Apply is: $(tail -n +"$((LOG_LINES_BEFORE + 1))" "$DAEMON_LOG" | tr '\n' '|')"
}

# --- reading both surfaces ---------------------------------------------------
read_surfaces() {
  APPLY_LOG=$(tail -n +"$((LOG_LINES_BEFORE + 1))" "$DAEMON_LOG" | grep '"level"')
  REFUSAL_CODE=$(printf '%s\n' "$APPLY_LOG" \
    | grep -o '"refusal_code":"[^"]*"' | tail -1 | sed 's/.*:"//; s/"$//')
  REFUSAL_CODE="${REFUSAL_CODE:-none}"
  # Order matters: the abandoned sentence CONTAINS the plain refusal one, so the
  # abandonment clause is tested first. No smoothing, no "if it looks like it
  # refused, call it refused".
  if printf '%s\n' "$APPLY_LOG" | grep -q 'abandoned'; then
    LOG_CLASS=abandoned
  elif printf '%s\n' "$APPLY_LOG" | grep -q '"message":"the X11 key grab was refused"'; then
    LOG_CLASS=refused
  else
    LOG_CLASS=none
  fi
  SCREEN="$OUT_DIR/settings-after-rebind.png"
  shot_window "$SCREEN" || halt read-screen "could not capture the settings screen"
}

classify() {
  case "$LOG_CLASS" in
    abandoned) VERDICT=REPORTED_IN_EFFECT ;;
    refused)   VERDICT=REPORTED_UNAVAILABLE ;;
    *)         VERDICT=UNCLASSIFIED ;;
  esac
}

emit() {
  printf 'RESULT rebind-worker-gone REV=%s INJECTED=yes BOUND=%s REQUESTED=%s REFUSAL_CODE=%s LOG=%s SCREEN=%s VERDICT=%s\n' \
    "$REV_SHORT" "$BOUND" "$REQUESTED" "$REFUSAL_CODE" "$LOG_CLASS" "$SCREEN" "$VERDICT"
  printf '%s\n' "$APPLY_LOG" | sed 's/^/  /'
  sed 's/^/  /' "$DIFF_FILE"
  if [ "$VERDICT" = UNCLASSIFIED ]; then
    printf '  (UNCLASSIFIED — the whole log since Apply is above)\n'
  fi
}

main() {
  parse_args "$@"
  preflight
  printf 'RUN label=%s at=%s (%s) display=%s\n' "$LABEL" "$REV_SHORT" "$REV_SHA" "$DISPLAY"
  printf 'REVISION %s %s\n' "$REV_SHA" "$(git log -1 --format=%s "$REV_SHA")"
  make_worktree
  inject_fault
  build_bundle
  start_daemon
  resolve_toplevel
  confirm_bound_combination
  confirm_grab_held
  raise_panel
  drive_rebind
  await_bind_outcome
  read_surfaces
  classify
  emit
  [ "$VERDICT" = UNCLASSIFIED ] && exit 1
  exit 0
}

main "$@"
