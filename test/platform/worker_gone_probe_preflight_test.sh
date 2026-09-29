#!/usr/bin/env bash
# Exercise the current probe file against disposable X servers and clean repos.
set -uo pipefail

fail() {
  printf '%s: FAIL — %s\n' "$CASE_NAME" "$1" >&2
  exit 1
}

require_tools() {
  local tool
  for tool in Xvfb xvfb-run openbox xclip timeout git xdpyinfo xprop \
    xdotool xwininfo import compare dbus-run-session python3 flutter \
    pgrep pkill readlink cmp paste wc mktemp chmod head; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing $tool"
  done
}

wait_for_window_manager() {
  local attempt
  openbox --sm-disable >"$CASE_ROOT/openbox.log" 2>&1 &
  OPENBOX_PID=$!
  for attempt in {1..40}; do
    if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id'; then
      return 0
    fi
    sleep 0.1
  done
  fail "openbox did not register with $DISPLAY"
}

make_clean_repository() {
  CASE_ROOT=$(mktemp -d -t "worker-gone-preflight-${CASE_NAME}.XXXXXXXX") \
    || fail "could not create case directory"
  git -C "$CASE_ROOT" init -q || fail "could not initialize case repository"
  cd "$CASE_ROOT" || fail "could not enter case repository"
  [ "$(git rev-parse --show-toplevel)" = "$CASE_ROOT" ] \
    || fail "probe would not run from the case repository"
  [ -z "$(git status --porcelain -uno -- lib/ test/ tool/)" ] \
    || fail "case repository has tracked source edits"
}

read_targets() {
  "$REAL_XCLIP" -selection clipboard -o -t TARGETS -d "$DISPLAY" 2>/dev/null
}

run_probe() {
  local result
  result=$(timeout 20 bash "$PROBE_PATH" --at invalid-preflight-revision 2>&1)
  PROBE_RC=$?
  PROBE_OUTPUT=$result
  printf '%s: probe_rc=%s halt=%s\n' "$CASE_NAME" "$PROBE_RC" \
    "$(printf '%s\n' "$result" | grep '^HALT (preflight):' | head -1)"
  if printf '%s\n' "$result" | grep -Eq '^(RUN|WORKTREE|BUILD)( |$)'; then
    fail "probe reached the build/run path"
  fi
  if printf '%s\n' "$result" | grep -q 'tracked files under lib/, test/ or tool/ are modified'; then
    fail "probe hit its dirty-tree gate instead of the clipboard gate"
  fi
}

assert_owner_refusal() {
  [ "$PROBE_RC" -eq 2 ] || fail "expected preflight exit 2"
  printf '%s\n' "$PROBE_OUTPUT" | grep -Eq \
    '^HALT \(preflight\): .*clipboard.*owner' \
    || fail "expected a named clipboard-owner refusal"
  if printf '%s\n' "$PROBE_OUTPUT" | grep -q 'not a commit'; then
    fail "probe reached invalid-revision refusal"
  fi
}

newline_only_case() {
  printf '\n\n\n' | "$REAL_XCLIP" -selection clipboard -i -d "$DISPLAY" \
    2>"$CASE_ROOT/owner.log" \
    || fail "could not seed newline selection"
  local before after before_targets after_targets
  before_targets=$(read_targets) || fail "newline selection has no owner"
  before=$("$REAL_XCLIP" -selection clipboard -o -d "$DISPLAY" | wc -c)
  [ "$before" -eq 3 ] || fail "expected exactly three newline bytes before probe; got $before"

  run_probe

  after_targets=$(read_targets) || after_targets=""
  after=$("$REAL_XCLIP" -selection clipboard -o -d "$DISPLAY" | wc -c)
  printf '%s: bytes_before=%s bytes_after=%s targets_before=%s targets_after=%s\n' \
    "$CASE_NAME" "$before" "$after" \
    "$(printf '%s\n' "$before_targets" | paste -sd, -)" \
    "$(printf '%s\n' "$after_targets" | paste -sd, -)"
  [ -n "$after_targets" ] || fail "newline selection lost its owner"
  [ "$after" -eq 3 ] || fail "newline selection byte count changed"
  cmp -s <(printf '\n\n\n') \
    <("$REAL_XCLIP" -selection clipboard -o -d "$DISPLAY") \
    || fail "newline selection bytes changed"
  assert_owner_refusal
}

non_text_owner_case() {
  printf '' | "$REAL_XCLIP" -selection clipboard -i -t image/png -d "$DISPLAY" \
    2>"$CASE_ROOT/owner.log" \
    || fail "could not seed image/png owner"
  local before after empty_bytes
  before=$(read_targets) || fail "image/png selection has no owner"
  printf '%s\n' "$before" | grep -q 'image/png' \
    || fail "initial TARGETS omits image/png"
  empty_bytes=$({ "$REAL_XCLIP" -selection clipboard -o -d "$DISPLAY" 2>/dev/null || true; } | wc -c)
  [ "$empty_bytes" -eq 0 ] || fail "expected empty default payload; got $empty_bytes bytes"

  run_probe

  after=$(read_targets) || after=""
  printf '%s: default_bytes_before=%s targets_before=%s targets_after=%s\n' \
    "$CASE_NAME" "$empty_bytes" \
    "$(printf '%s\n' "$before" | paste -sd, -)" \
    "$(printf '%s\n' "$after" | paste -sd, -)"
  [ -n "$after" ] || fail "image/png selection lost its owner"
  printf '%s\n' "$after" | grep -q 'image/png' \
    || fail "image/png target disappeared"
  assert_owner_refusal
}

assert_write_is_last_preflight_action() {
  python3 - "$PROBE_PATH" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
preflight = source.split('preflight() {', 1)[1].split('\n}', 1)[0]
writes = [preflight.find("printf '' | xclip -selection clipboard -d")]
if writes[0] < 0 or preflight.count("printf '' | xclip -selection clipboard -d") != 1:
    raise SystemExit('preflight must contain exactly one empty-selection write')
if 'die ' in preflight[writes[0]:]:
    raise SystemExit('a preflight refusal follows the empty-selection write')
PY
}

late_refusal_case() {
  if read_targets >/dev/null; then
    fail "expected an unowned CLIPBOARD before probe"
  fi
  local wrapper_dir
  wrapper_dir="$CASE_ROOT/wrapper"
  mkdir -p "$wrapper_dir" || fail "could not create xclip wrapper"
  XCLIP_LOG="$CASE_ROOT/xclip-writes.log"
  export XCLIP_LOG REAL_XCLIP
  cat >"$wrapper_dir/xclip" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in -o|-out) exec "$REAL_XCLIP" "$@" ;; esac
done
printf 'WRITE\n' >> "$XCLIP_LOG"
exec "$REAL_XCLIP" "$@"
SH
  chmod +x "$wrapper_dir/xclip" || fail "could not activate xclip wrapper"
  export PATH="$wrapper_dir:$PATH"

  run_probe

  [ "$PROBE_RC" -eq 2 ] || fail "expected later preflight exit 2"
  printf '%s\n' "$PROBE_OUTPUT" | grep -q 'not a commit' \
    || fail "expected invalid-revision refusal after clipboard gate"
  printf '%s: xclip_writes=%s\n' "$CASE_NAME" \
    "$([ -f "$XCLIP_LOG" ] && wc -l < "$XCLIP_LOG" || printf 0)"
  [ ! -s "$XCLIP_LOG" ] || fail "probe attempted to write CLIPBOARD before late refusal"
  assert_write_is_last_preflight_action || fail "ownership write precedes a refusal"
  if read_targets >/dev/null; then
    fail "late refusal left a CLIPBOARD owner"
  fi
  printf '%s: xclip_writes=0 clipboard_after=unowned\n' "$CASE_NAME"
}

run_case() {
  CASE_NAME=$1
  PROBE_PATH=$2
  REAL_XCLIP=$(command -v xclip) || fail "xclip not found"
  OPENBOX_PID=""
  CASE_ROOT=""
  trap 'if [ -n "$OPENBOX_PID" ]; then kill "$OPENBOX_PID" 2>/dev/null || true; fi; if [ -n "$CASE_ROOT" ]; then rm -rf "$CASE_ROOT"; fi' EXIT
  make_clean_repository
  wait_for_window_manager
  case "$CASE_NAME" in
    newline-only) newline_only_case ;;
    non-text-owner) non_text_owner_case ;;
    late-refusal) late_refusal_case ;;
    *) fail "unknown case" ;;
  esac
  printf '%s: PASS\n' "$CASE_NAME"
}

main() {
  CASE_NAME=preflight
  require_tools
  if [ "${1:-}" = --case ]; then
    run_case "$2" "$3"
    return
  fi

  local script_path probe_path case_name passed=0
  script_path=$(readlink -f "$0") || fail "cannot resolve harness path"
  probe_path=$(readlink -f "$(dirname "$script_path")/../../tool/uat/worker_gone_probe.sh") \
    || fail "cannot resolve current probe path"
  [ -f "$probe_path" ] || fail "probe file does not exist"
  for case_name in newline-only non-text-owner late-refusal; do
    if xvfb-run -a -s '-screen 0 1440x900x24 -nolisten tcp' \
      bash "$script_path" --case "$case_name" "$probe_path"; then
      passed=$((passed + 1))
    fi
  done
  [ "$passed" -eq 3 ] || fail "$passed/3 cases passed"
  printf '3 passed\n'
}

main "$@"
