#!/usr/bin/env bash
# UAT harness (phase 01, gap G-01-13). Classifies one stimulus at the real daemon's
# toplevel from a timestamped X event stream, because xwininfo's Map State cannot see
# the measured 8-16 ms unmap/remap flicker (01-UAT.md test 13).
# Usage: tool/uat/panel_toggle_probe.sh <route> [<route> ...] | all
#        routes: show hide alternate focus-steal desktop-click
#                steal-after-presses press-then-click foreign-grab
# Not `set -e`: a route that fails must still be reported and the daemon still stopped.
set -uo pipefail

readonly APP_CLASS='com.divertedriver.HotkeyGrammarCorrector'
readonly BUNDLE='build/linux/x64/release/bundle/hotkey_grammar_corrector'
# The bracket keeps the pattern from matching the shell that runs the pkill.
readonly DAEMON_PAT='bundle/hotkey_grammar_correcto[r]'
readonly SETTLE_MS=1000   # 60x the measured 8-16 ms flicker: a margin, not a threshold.
readonly ATTACH_MS=500
# Let the transition a route just event-confirmed quiesce before the next mark is
# taken, so no tail of the previous step can land inside the measured slice.
readonly QUIESCE_MS=500

export DISPLAY="${DISPLAY:-:99}"

RUN_ROOT=""
DAEMON_SID=""
DAEMON_PID=""
DAEMON_LOG=""
TOPLEVEL=""
HALT_REASON=""
ROUTE_SEQ=0

# Measurement result, populated by do_measure and read by emit_route.
M_UNMAP=0; M_MAP=0; M_FIRST=none; M_FB='-'; M_FA='-'; M_VERDICT=NOTHING; M_LOG=""
# One extra field, emitted immediately before WINDOW= by a route that has an
# invariant to make visible. Empty for every route that has none.
M_EXTRA=""

# --- halting -----------------------------------------------------------------
# A named reason on stderr, never a route verdict.
fail() { HALT_REASON="$1"; return 1; }

die() {
  printf 'HALT (preflight): %s\n' "$1" >&2
  exit 2
}

# --- teardown ----------------------------------------------------------------
HELPER_PIDS=()

# focus-steal's xmessage and foreign-grab's ctypes grabber die on every path,
# including a halt (T-01-56): a leaked grabber holds a passive grab on the shared
# display and would silently break every later run.
stop_helpers() {
  local p
  for p in "${HELPER_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -TERM "$p" >/dev/null 2>&1
  done
  HELPER_PIDS=()
}

stop_daemon() {
  if [ -n "$DAEMON_SID" ]; then
    kill -TERM -- "-${DAEMON_SID}" >/dev/null 2>&1
  fi
  pkill -f "$DAEMON_PAT" >/dev/null 2>&1
  local i=0
  while pgrep -f "$DAEMON_PAT" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 150 ] && break
    sleep 0.1
  done
  # A reaped process still has windows until X tears its connection down. Waiting
  # here keeps a dead route's toplevel out of the next route's candidate list.
  i=0
  while [ -n "$(xdotool search --class "$APP_CLASS" 2>/dev/null)" ]; do
    i=$((i + 1))
    [ "$i" -gt 100 ] && break
    sleep 0.1
  done
  DAEMON_SID=""; DAEMON_PID=""; DAEMON_LOG=""; TOPLEVEL=""
}

cleanup() {
  xev_stop
  stop_helpers
  stop_daemon
  [ -n "$RUN_ROOT" ] && rm -rf "$RUN_ROOT"
}
trap cleanup EXIT

# --- preflight ---------------------------------------------------------------
preflight() {
  xdpyinfo >/dev/null 2>&1 || die "DISPLAY=$DISPLAY does not answer (start: Xvfb :99 -screen 0 1440x900x24 -nolisten tcp)"
  local t
  for t in xev xdotool xwininfo xprop python3 dbus-run-session stdbuf; do
    command -v "$t" >/dev/null 2>&1 || die "required tool not on PATH: $t"
  done
  [ -x "$BUNDLE" ] || die "release bundle missing or not executable: $BUNDLE"
  # A surviving daemon holds the passive grab, so the next bind is refused and every
  # route would observe nothing while looking healthy.
  if pgrep -f "$DAEMON_PAT" >/dev/null 2>&1; then
    die "a daemon is already running and holds the grab — stop it first (pkill -f '$DAEMON_PAT')"
  fi
  RUN_ROOT=$(mktemp -d /tmp/hgc-p.XXXXXX) || die "could not create a run directory"
}

# --- daemon lifecycle --------------------------------------------------------
# DAEMON_PAT matches dbus-run-session's own command line too (the bundle path is one
# of its arguments), so the app process is identified by the executable it is running
# rather than by the pattern alone. _NET_WM_PID names this pid, not the launcher's.
daemon_pids() {
  local p exe
  for p in $(pgrep -f "$DAEMON_PAT" 2>/dev/null); do
    exe=$(readlink -f "/proc/$p/exe" 2>/dev/null)
    case "$exe" in
      */bundle/hotkey_grammar_corrector) printf '%s\n' "$p" ;;
    esac
  done
}

# Per-run XDG tree (T-01-55): never the developer's real config or history database.
start_daemon() {
  ROUTE_SEQ=$((ROUTE_SEQ + 1))
  local base="$RUN_ROOT/r$ROUTE_SEQ"
  local rt="$base/rt"
  mkdir -p "$base/config" "$base/data" "$rt" || { fail "could not create the XDG tree under $base"; return 1; }
  chmod 700 "$rt"

  DISPLAY="$DISPLAY" XDG_SESSION_TYPE=x11 \
    XDG_CONFIG_HOME="$base/config" XDG_DATA_HOME="$base/data" XDG_RUNTIME_DIR="$rt" \
    setsid nohup dbus-run-session -- "./$BUNDLE" > "$base/daemon.log" 2>&1 < /dev/null &
  DAEMON_SID=$!

  # Wait for the app process to exist rather than sleeping a fixed time. The window
  # wait belongs to resolve_toplevel, which keys on THIS pid: a bare class search
  # also matches the previous route's windows for the moment between the process
  # being reaped and X tearing its connection down, and that raced (measured).
  DAEMON_LOG="$base/daemon.log"
  local i=0 pids
  while [ "$i" -lt 300 ]; do
    pids=$(daemon_pids)
    if [ "$(printf '%s\n' "$pids" | grep -c .)" -eq 1 ]; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  fail "no daemon process appeared within 30 s — see $base/daemon.log"
  return 1
}

# Keep only ids whose _NET_WM_PID is the daemon's and which xwininfo can report on.
# Require exactly one survivor; the window XGetInputFocus names is a CHILD of it, so
# the two are not required to be equal.
resolve_toplevel() {
  local i=0 pids pid_count candidates survivors id wmpid last_candidates=""
  while [ "$i" -lt 300 ]; do
    pids=$(daemon_pids)
    pid_count=$(printf '%s\n' "$pids" | grep -c . )
    if [ "$pid_count" -ne 1 ]; then
      fail "expected exactly one daemon process, found $pid_count: $(printf '%s' "$pids" | tr '\n' ' ')"
      return 1
    fi
    DAEMON_PID=$(printf '%s' "$pids" | tr -d '[:space:]')

    survivors=()
    candidates=$(xdotool search --class "$APP_CLASS" 2>/dev/null)
    last_candidates=$(printf '%s' "$candidates" | tr '\n' ' ')
    for id in $candidates; do
      wmpid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | grep -oE '[0-9]+$')
      [ "$wmpid" = "$DAEMON_PID" ] || continue
      xwininfo -id "$id" 2>/dev/null | grep -q 'Map State' || continue
      # Measured 2026-09-10: the class also matches GTK's 10x10 hidden group-leader
      # window, which carries _NET_WM_PID and reports a Map State but has no window
      # type. The real toplevel is the one the WM is told to manage as NORMAL.
      xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q '_NET_WM_WINDOW_TYPE_NORMAL' || continue
      survivors+=("$id")
    done
    if [ "${#survivors[@]}" -eq 1 ]; then
      TOPLEVEL="${survivors[0]}"
      printf 'TOPLEVEL window=%s _NET_WM_PID=%s class=%s\n' "$TOPLEVEL" "$DAEMON_PID" "$APP_CLASS"
      return 0
    fi
    if [ "${#survivors[@]}" -gt 1 ]; then
      fail "expected exactly one toplevel for pid $DAEMON_PID, found ${#survivors[@]} — candidates: $last_candidates"
      return 1
    fi
    i=$((i + 1))
    sleep 0.1
  done
  fail "no NORMAL toplevel for pid $DAEMON_PID appeared within 30 s — candidates: ${last_candidates:-none} — see ${DAEMON_LOG:-the daemon log}"
  return 1
}

# --- stimuli -----------------------------------------------------------------
STEAL_WIN=""

fire_stimulus() {
  case "$1" in
    press)        xdotool key --clearmodifiers ctrl+shift+g >/dev/null 2>&1 ;;
    foreignkey)   xdotool key --clearmodifiers ctrl+shift+h >/dev/null 2>&1 ;;
    activatesteal)
      [ -n "$STEAL_WIN" ] || { fail "no steal window to activate"; return 1; }
      xdotool windowactivate "$STEAL_WIN" >/dev/null 2>&1 ;;
    desktopclick) xdotool mousemove 1400 870 click 1 >/dev/null 2>&1 ;;
    *)            fail "unknown stimulus: $1"; return 1 ;;
  esac
  return 0
}

focus_now() {
  local f
  f=$(xdotool getwindowfocus -f 2>/dev/null | tr -d '[:space:]')
  printf '%s' "${f:--}"
}

# --- measurement -------------------------------------------------------------
# One stimulus, measured from the toplevel's own event stream. stdbuf forces xev to
# line-buffer: block-buffered output is lost when xev is stopped.
do_measure() {
  local stimulus="$1"
  local log="$RUN_ROOT/r$ROUTE_SEQ-$(printf '%s' "$stimulus")-$(date +%s%N).log"
  M_LOG="$log"

  stdbuf -oL xev -id "$TOPLEVEL" -event structure -event focus 2>/dev/null \
    | python3 -u -c 'import sys,time
[sys.stdout.write("%.3f %s" % (time.time(), l)) for l in sys.stdin]' > "$log" 2>/dev/null &
  local xev_pgid=$!
  sleep "$(awk "BEGIN{print $ATTACH_MS/1000}")"

  M_FB=$(focus_now)
  fire_stimulus "$stimulus" || { kill "$xev_pgid" >/dev/null 2>&1; return 1; }
  sleep "$(awk "BEGIN{print $SETTLE_MS/1000}")"
  M_FA=$(focus_now)

  pkill -P "$xev_pgid" -x xev >/dev/null 2>&1
  pkill -f "xev -id $TOPLEVEL" >/dev/null 2>&1
  wait "$xev_pgid" 2>/dev/null

  if [ ! -s "$log" ]; then
    fail "xev produced no output for stimulus '$stimulus' on window $TOPLEVEL"
    return 1
  fi

  M_UNMAP=$(grep -c ' UnmapNotify' "$log")
  M_MAP=$(grep -c ' MapNotify' "$log")
  local first_line
  first_line=$(grep -m1 -E ' (Unmap|Map)Notify' "$log")
  case "$first_line" in
    *' UnmapNotify'*) M_FIRST=Unmap ;;
    *' MapNotify'*)   M_FIRST=Map ;;
    *)                M_FIRST=none ;;
  esac
  M_VERDICT=$(classify "$M_UNMAP" "$M_MAP" "$M_FIRST")
  return 0
}

# Counts and order only, over the slice WINDOW names. No tolerance, no retry,
# no "if it looks like it hid, call it hidden".
classify() {
  local u="$1" m="$2" first="$3"
  if   [ "$u" -eq 0 ] && [ "$m" -eq 1 ]; then printf 'SHOW'
  elif [ "$u" -eq 1 ] && [ "$m" -eq 0 ]; then printf 'HIDE'
  elif [ "$u" -ge 1 ] && [ "$m" -ge 1 ] && [ "$first" = Unmap ]; then printf 'FLICKER'
  elif [ "$u" -eq 0 ] && [ "$m" -eq 0 ]; then printf 'NOTHING'
  else printf 'UNCLASSIFIED'
  fi
}

# --- windowed measurement ----------------------------------------------------
# Plan 01-13's two routes cannot be measured by do_measure, because what each
# classifies is a SLICE of the stream rather than one whole press: both have to
# fire several event-confirmed presses to reach the state they mean to test, and
# then count only what followed their final stimulus. So xev is attached ONCE for
# the whole route and the classification is scoped by timestamp. The timestamper
# in front of xev is what makes that slice available — this is the same
# measurement mechanism as do_measure's, scoped, not a second one.
#
# These routes therefore never call do_measure or warm_up: each attaches and then
# pkills an xev on this window, which would tear the long-lived stream down.
# Grab ownership is still established the way warm_up establishes it — the first
# press of each route is REQUIRED to map the panel, and the route halts by name
# if it does not.
XEV_PID=""
XEV_LOG=""
# The panel's mapping state as the event stream last reported it. Never read from
# xwininfo: Map State is the oracle 01-UAT.md test 13 disqualified.
PANEL=unknown

now_ts() { date +%s.%N; }

xev_start() {
  local tag="$1"
  XEV_LOG="$RUN_ROOT/r$ROUTE_SEQ-$tag-$(date +%s%N).log"
  stdbuf -oL xev -id "$TOPLEVEL" -event structure -event focus 2>/dev/null \
    | python3 -u -c 'import sys,time
[sys.stdout.write("%.3f %s" % (time.time(), l)) for l in sys.stdin]' > "$XEV_LOG" 2>/dev/null &
  XEV_PID=$!
  PANEL=unknown
  sleep "$(awk "BEGIN{print $ATTACH_MS/1000}")"
  return 0
}

xev_stop() {
  [ -n "$XEV_PID" ] || return 0
  pkill -P "$XEV_PID" -x xev >/dev/null 2>&1
  pkill -f "xev -id $TOPLEVEL" >/dev/null 2>&1
  wait "$XEV_PID" 2>/dev/null
  XEV_PID=""
}

# The slice: lines whose timestamper epoch is at or after MARK. Everything below
# reads $XEV_LOG, so a route can only ever classify its own stream.
slice_count() {
  awk -v m="$1" -v pat="$2" 'index($0,pat)>0 && $1+0>=m {n++} END{print n+0}' "$XEV_LOG"
}

slice_first() {
  awk -v m="$1" '$1+0>=m && /(Unmap|Map)Notify/ {
    print (index($0," UnmapNotify")>0 ? "Unmap" : "Map"); exit }' "$XEV_LOG"
}

slice_last() {
  awk -v m="$1" '$1+0>=m && /(Unmap|Map)Notify/ {
    k = (index($0," UnmapNotify")>0 ? "Unmap" : "Map") }
    END { print (k=="" ? "none" : k) }' "$XEV_LOG"
}

# Where the panel ended up after the next transition following MARK; non-zero if
# nothing moved within 3 s. The extra settle then the LAST transition, not the
# first: a flicker must never be read as a clean edge, which is the whole reason
# this file exists.
await_transition() {
  local mark="$1" i=0
  while [ "$i" -lt 30 ]; do
    sleep 0.1
    if [ "$(slice_count "$mark" ' UnmapNotify')" -ge 1 ] \
      || [ "$(slice_count "$mark" ' MapNotify')" -ge 1 ]; then
      sleep 0.5
      slice_last "$mark"
      return 0
    fi
    i=$((i + 1))
  done
  printf 'none'
  return 1
}

set_panel_from() {
  case "$1" in
    Map)   PANEL=mapped ;;
    Unmap) PANEL=unmapped ;;
    *)     PANEL=unknown ;;
  esac
}

# One press whose transition is REQUIRED to be WANT. A press that goes the other
# way is a finding, so it halts the route by name rather than being absorbed.
press_for() {
  local want="$1" what="$2" mark t
  mark=$(now_ts)
  fire_stimulus press || return 1
  if ! t=$(await_transition "$mark"); then
    fail "$what: the press produced no mapping transition within 3 s — on a route's first press that means the daemon does not own the grab, so nothing it observed can be trusted"
    return 1
  fi
  if [ "$t" != "$want" ]; then
    fail "$what: the press settled on ${t}Notify, not the expected ${want}Notify"
    return 1
  fi
  set_panel_from "$t"
  return 0
}

# One press with no expectation of direction. Post-fix every press toggles, so a
# route that fires a fixed count cannot know which way any single one goes — and
# asserting a direction here would be asserting the parity, not the behaviour.
press_either() {
  local what="$1" mark t
  mark=$(now_ts)
  fire_stimulus press || return 1
  if ! t=$(await_transition "$mark"); then
    fail "$what: the press produced no mapping transition within 3 s — on a route's first press that means the daemon does not own the grab, so nothing it observed can be trusted"
    return 1
  fi
  set_panel_from "$t"
  return 0
}

# A mapped panel is an INVARIANT the route establishes, never a consequence of how
# many presses it fired: post-fix the presses toggle, so parity would decide it
# otherwise, and a route that stole the keyboard from an already-hidden panel would
# read NOTHING and be indistinguishable from a defect.
ensure_mapped() {
  [ "$PANEL" = mapped ] && return 0
  press_for Map "establishing the mapped panel this route's stimulus needs"
}

# Fire STIMULUS and classify ONLY what followed it. The quiesce is what makes the
# slice honest: the transition the route just confirmed must be finished before the
# mark is taken, or its tail would be counted as the stimulus's own.
measure_after() {
  local stimulus="$1" mark
  sleep "$(awk "BEGIN{print $QUIESCE_MS/1000}")"
  mark=$(now_ts)
  M_FB=$(focus_now)
  fire_stimulus "$stimulus" || return 1
  sleep "$(awk "BEGIN{print $SETTLE_MS/1000}")"
  M_FA=$(focus_now)
  if [ ! -s "$XEV_LOG" ]; then
    fail "xev produced no output at all on window $TOPLEVEL"
    return 1
  fi
  M_UNMAP=$(slice_count "$mark" ' UnmapNotify')
  M_MAP=$(slice_count "$mark" ' MapNotify')
  M_FIRST=$(slice_first "$mark")
  M_FIRST="${M_FIRST:-none}"
  M_VERDICT=$(classify "$M_UNMAP" "$M_MAP" "$M_FIRST")
  M_LOG="$XEV_LOG"
  return 0
}

# Exactly one space between fields, in this order. Plan 01-13 adds routes that
# classify from a slice of the stream rather than the whole press, so WINDOW is
# emitted from the start by every route — a format that changed halfway through the
# set would silently invalidate this plan's baseline.
# The SUMMARY block, in route order. alternate contributes one comma-joined entry.
SUMMARY_KEYS=()
SUMMARY_VALS=()

record_verdict() {
  local key="$1" v="$2" i=0
  for i in "${!SUMMARY_KEYS[@]}"; do
    if [ "${SUMMARY_KEYS[$i]}" = "$key" ]; then
      SUMMARY_VALS[$i]="${SUMMARY_VALS[$i]},$v"
      return 0
    fi
  done
  SUMMARY_KEYS+=("$key")
  SUMMARY_VALS+=("$v")
}

print_summary() {
  local i
  for i in "${!SUMMARY_KEYS[@]}"; do
    printf 'SUMMARY %s=%s\n' "${SUMMARY_KEYS[$i]}" "${SUMMARY_VALS[$i]}"
  done
}

emit_route() {
  local name="$1" window="$2" key="${3:-$1}"
  record_verdict "$key" "$M_VERDICT"
  printf 'ROUTE %s UNMAP=%s MAP=%s FIRST=%s FOCUS_BEFORE=%s FOCUS_AFTER=%s %sWINDOW=%s VERDICT=%s\n' \
    "$name" "$M_UNMAP" "$M_MAP" "$M_FIRST" "$M_FB" "$M_FA" "$M_EXTRA" "$window" "$M_VERDICT"
  if [ -n "$M_LOG" ] && [ -s "$M_LOG" ]; then
    sed 's/^/  /' "$M_LOG"
  fi
  if [ "$M_VERDICT" = UNCLASSIFIED ]; then
    printf '  (UNCLASSIFIED — raw stream above is the whole record)\n'
  fi
}

emit_halted() {
  record_verdict "$1" HALTED
  printf 'ROUTE %s UNMAP=0 MAP=0 FIRST=none FOCUS_BEFORE=- FOCUS_AFTER=- WINDOW=%s VERDICT=HALTED\n' \
    "$1" "${2:-all}"
}

# --- warm-up -----------------------------------------------------------------
# Confirms the daemon owns the grab, so a route that observes nothing is never
# mistaken for a working daemon: the first press must map the panel. Leaves the panel
# VISIBLE, which is the starting state every later route in this file wants. Its
# measurement is stashed so a route that wants the from-hidden press can report it
# instead of pressing twice.
WU_UNMAP=0; WU_MAP=0; WU_FIRST=none; WU_FB='-'; WU_FA='-'; WU_VERDICT=NOTHING; WU_LOG=""

warm_up() {
  do_measure press || return 1
  WU_UNMAP=$M_UNMAP; WU_MAP=$M_MAP; WU_FIRST=$M_FIRST
  WU_FB=$M_FB; WU_FA=$M_FA; WU_VERDICT=$M_VERDICT; WU_LOG=$M_LOG
  if [ "$M_MAP" -lt 1 ]; then
    fail "the first press did not map the panel (UNMAP=$M_UNMAP MAP=$M_MAP) — the daemon does not own the grab, so nothing this route observed can be trusted"
    return 1
  fi
  return 0
}

# Replay the warm-up's own measurement as a route result, so a route that wants the
# from-hidden press reports THAT press rather than pressing a second time.
emit_warm_up_as() {
  M_UNMAP=$WU_UNMAP; M_MAP=$WU_MAP; M_FIRST=$WU_FIRST
  M_FB=$WU_FB; M_FA=$WU_FA; M_VERDICT=$WU_VERDICT; M_LOG=$WU_LOG
  emit_route "$1" all "${2:-$1}"
}

# --- helper clients ----------------------------------------------------------
# A real second toplevel for focus-steal. Started BEFORE the warm-up: mapping a new
# window takes the focus at map time, and doing that inside the measurement window
# would dismiss the panel before xev was attached.
start_steal_window() {
  xmessage -geometry 300x150+600+400 STEAL >/dev/null 2>&1 &
  HELPER_PIDS+=($!)
  local i=0 ids
  while [ "$i" -lt 100 ]; do
    ids=$(xdotool search --class xmessage 2>/dev/null | tail -1)
    if [ -n "$ids" ]; then
      STEAL_WIN="$ids"
      sleep 0.5
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  fail "xmessage never mapped a window — focus-steal has nothing to hand the keyboard to"
  return 1
}

# A second X client passive-grabbing a combination the daemon does NOT own, so the
# daemon receives no activation at all and the self-inflicted dismissal is isolated
# from the toggle completely.
start_foreign_grabber() {
  local py="$RUN_ROOT/foreign_grabber.py"
  cat > "$py" <<'GRABBER'
import ctypes, sys, time
X = ctypes.CDLL("libX11.so.6")
X.XOpenDisplay.restype = ctypes.c_void_p
d = X.XOpenDisplay(None)
if not d:
    sys.stderr.write("grabber: cannot open display\n"); sys.exit(1)
X.XDefaultRootWindow.restype = ctypes.c_ulong
X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
root = X.XDefaultRootWindow(d)
X.XStringToKeysym.restype = ctypes.c_ulong
X.XStringToKeysym.argtypes = [ctypes.c_char_p]
ks = X.XStringToKeysym(b"h")
X.XKeysymToKeycode.restype = ctypes.c_ubyte
X.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
kc = X.XKeysymToKeycode(d, ks)
CONTROL_MASK = 1 << 2
SHIFT_MASK = 1 << 0
GRAB_MODE_ASYNC = 1
X.XGrabKey.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint,
                       ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_int]
X.XGrabKey(d, kc, CONTROL_MASK | SHIFT_MASK, root, 0, GRAB_MODE_ASYNC, GRAB_MODE_ASYNC)
X.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
X.XSync(d, 0)
# Reached only if XGrabKey raised no BadAccess: Xlib's default handler exits first.
sys.stdout.write("GRABBED ctrl+shift+h keycode=%d\n" % kc)
sys.stdout.flush()
while True:
    time.sleep(3600)
GRABBER
  local out="$RUN_ROOT/foreign_grabber.out"
  : > "$out"
  python3 -u "$py" > "$out" 2>&1 &
  local gpid=$!
  HELPER_PIDS+=("$gpid")
  local i=0
  while [ "$i" -lt 100 ]; do
    grep -q '^GRABBED ' "$out" 2>/dev/null && { printf 'GRABBER %s\n' "$(cat "$out")"; return 0; }
    kill -0 "$gpid" >/dev/null 2>&1 || { fail "the foreign grabber died before grabbing: $(cat "$out" 2>/dev/null)"; return 1; }
    i=$((i + 1))
    sleep 0.1
  done
  fail "the foreign grabber never confirmed its grab on ctrl+shift+h"
  return 1
}

# --- routes ------------------------------------------------------------------
# One press at a HIDDEN panel. Expected now and after the fix: SHOW. A hidden panel
# has no focus to lose, so no FocusOut(NotifyGrab) is generated and the first press
# has always worked.
route_show() {
  start_daemon && resolve_toplevel && warm_up || return 1
  emit_warm_up_as show
  return 0
}

# One press at a VISIBLE panel. Against the unfixed bundle this is G-01-13: the
# self-inflicted hide followed by the toggle's re-show, 8-16 ms apart.
route_hide() {
  start_daemon && resolve_toplevel && warm_up || return 1
  do_measure press || return 1
  emit_route hide all
  return 0
}

# Four presses from hidden, 1 s settle between each. Reproduces the reporter's
# "shows once, then never hides". Expected after the fix: SHOW, HIDE, SHOW, HIDE.
route_alternate() {
  start_daemon && resolve_toplevel && warm_up || return 1
  emit_warm_up_as alternate-1 alternate
  local n
  for n in 2 3 4; do
    sleep 1
    do_measure press || return 1
    emit_route "alternate-$n" all alternate
  done
  return 0
}

# CAP-14 working: a real second toplevel takes the keyboard and the panel hides.
# Expected now AND after the fix: HIDE. The fix must not change this.
route_focus_steal() {
  start_daemon && resolve_toplevel && start_steal_window && warm_up || return 1
  do_measure activatesteal || return 1
  emit_route focus-steal all
  return 0
}

# Second CAP-14 route, measured at +0.1 ms in the diagnosis. Expected now and after
# the fix: HIDE, with FOCUS_AFTER naming a window that is not the daemon's.
route_desktop_click() {
  start_daemon && resolve_toplevel && warm_up || return 1
  do_measure desktopclick || return 1
  emit_route desktop-click all
  return 0
}

# The control that isolates the self-inflicted dismissal from the toggle entirely:
# the daemon receives NO activation here, only FocusOut(NotifyGrab) from a foreign
# client's grab. Expected now: HIDE (condition 1 of the defect, on its own).
# Expected AFTER the fix: NOTHING — that is the fix working, not the harness failing.
route_foreign_grab() {
  start_daemon && resolve_toplevel && start_foreign_grabber && warm_up || return 1
  do_measure foreignkey || return 1
  emit_route foreign-grab all
  return 0
}

# UAT test 14's third focus route, re-run as a REGRESSION GUARD over plan 01-12's
# change to the recorded keyboard state (`_focused` now survives a suppressed
# focus-out). Read the register carefully: this is NOT evidence that the fix works.
# It has no pre-fix baseline, because plan 01-11 did not carry it; per test 14's own
# HEAD evidence it would have read HIDE on the broken build too, so a HIDE here
# discriminates nothing; and the NotifyUngrab/`_focused` mechanism it targets has
# never reproduced in this container and was inferred rather than observed. What it
# buys is the absence of a symptom after an edit that could plausibly have
# introduced one. Expected: HIDE, from the steal alone.
route_steal_after_presses() {
  start_daemon && resolve_toplevel && start_steal_window || return 1
  xev_start steal-after-presses || return 1
  # Four mapped presses, the count test 14's evidence used. The panel starts hidden,
  # so press 1 maps it and 2-4 toggle from there.
  press_for Map 'press 1 of 4, at a hidden panel' || return 1
  local n
  for n in 2 3 4; do
    press_either "press $n of 4" || return 1
  done
  ensure_mapped || return 1
  M_EXTRA='PRESTEAL=mapped '
  measure_after activatesteal || return 1
  xev_stop
  emit_route steal-after-presses post-steal
  return 0
}

# UAT test 14's fourth focus route, three attempts, in the same regression-guard
# register as steal-after-presses and with the same three limits.
#
# The naive form of this route passes for the wrong reason, which is worse than
# failing. Post-fix the press at a mapped panel dismisses the panel itself, so the
# click lands on an already-unmapped window and contributes nothing — while the
# whole-press window still reads UNMAP=1 MAP=0 and a VERDICT=HIDE gate goes green
# over the toggle's own unmap. The route would assert that the click still dismisses
# while never testing the click. So a mapped panel is re-established BETWEEN the
# press and the click, and only what follows the click is classified.
route_press_then_click() {
  start_daemon && resolve_toplevel || return 1
  local attempt
  for attempt in 1 2 3; do
    xev_start "press-then-click-$attempt" || return 1
    ensure_mapped || return 1
    press_for Unmap "attempt $attempt: the press at a mapped panel" || return 1
    press_for Map "attempt $attempt: re-establishing the mapped panel before the click" || return 1
    measure_after desktopclick || return 1
    xev_stop
    emit_route "press-then-click-$attempt" post-click press-then-click
  done
  return 0
}

# --- runner ------------------------------------------------------------------
readonly ALL_ROUTES='show hide alternate focus-steal desktop-click steal-after-presses press-then-click foreign-grab'

run_route() {
  local name="$1"
  HALT_REASON=""
  M_EXTRA=""
  local fn="route_${name//-/_}"
  if ! declare -F "$fn" >/dev/null 2>&1; then
    printf 'HALT %s: unknown route\n' "$name" >&2
    emit_halted "$name"
    return 1
  fi
  "$fn"
  local rc=$?
  # Before stop_daemon, which clears TOPLEVEL that xev_stop needs to match on.
  xev_stop
  stop_helpers
  stop_daemon
  if [ "$rc" -ne 0 ]; then
    printf 'HALT %s: %s\n' "$name" "${HALT_REASON:-unspecified}" >&2
    emit_halted "$name"
    return 1
  fi
  return 0
}

main() {
  if [ "$#" -eq 0 ]; then
    printf 'Usage: %s <route> [<route> ...] | all\n       routes: %s\n' "$0" "$ALL_ROUTES" >&2
    exit 2
  fi
  preflight

  local requested=()
  local a
  for a in "$@"; do
    if [ "$a" = all ]; then
      for r in $ALL_ROUTES; do requested+=("$r"); done
    else
      requested+=("$a")
    fi
  done

  local rc=0 r
  for r in "${requested[@]}"; do
    run_route "$r" || rc=1
  done
  print_summary
  exit "$rc"
}

main "$@"
