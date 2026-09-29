#!/usr/bin/env bash
#
# Installs the two desktop entries the daemon needs on a real session.
#
#   applications/<app-id>.desktop   AD-11 — GNOME discards the global-shortcut
#                                   bind unless an installed entry has the same
#                                   basename as the registered app id.
#   autostart/<app-id>.desktop      AD-14 — starts the resident daemon at login.
#
# The two destinations are different XDG roots on purpose, so both are derived
# rather than hard-coded under $HOME. Rerunning is idempotent: every write is a
# whole-file copy to a fixed path.
#
# Usage:
#   tool/install_desktop_entries.sh [--exec /path/to/hotkey_grammar_corrector]
#
# Without --exec the entries keep their bare `Exec=hotkey_grammar_corrector`,
# which works only when the binary is on the session's PATH.

set -euo pipefail

readonly APP_ID='com.divertedriver.HotkeyGrammarCorrector'

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

readonly entry_source="${repo_root}/linux/packaging/${APP_ID}.desktop"
readonly autostart_source="${repo_root}/linux/packaging/autostart/${APP_ID}.desktop"
# The tray adapter's own 32x32 artwork, reused as the desktop-entry icon so the
# app-id file's Icon= key resolves instead of falling back to a blank tile.
readonly icon_source="${repo_root}/assets/tray/hotkey-grammar-corrector.png"

exec_path=''

usage() {
  printf 'usage: %s [--exec /path/to/hotkey_grammar_corrector]\n' "$0" >&2
}

# Rejects the --exec values that would otherwise install a broken entry and
# still exit 0 — the worst outcome available here, because the entry is what a
# compositor reads at login and nothing reads it back.
validate_exec() {
  local candidate="$1"
  if [ -z "$candidate" ]; then
    # The realistic source of an empty value is `--exec "$(command -v …)"`
    # where the lookup found nothing. Falling through to the bare name would
    # install an entry that works only by accident of PATH.
    printf 'error: --exec was given an empty path\n' >&2
    exit 2
  fi
  case "$candidate" in
    *\\*|*\"*)
      # The desktop entry spec gives both characters meaning inside Exec, and
      # neither survives this script's rewrite intact: a backslash is an escape
      # to the spec's own quoting rules, and a quote would terminate the one
      # this script adds.
      printf 'error: --exec may not contain a backslash or a double quote: %s\n' \
        "$candidate" >&2
      exit 2
      ;;
  esac
  # The whole control-character class, and a newline is why: the rewrite prints
  # the replacement as one line, so an embedded newline splits Exec in two and
  # turns the remainder into a second key — a duplicate `Name`, if the path was
  # crafted, and a syntax error otherwise. Either way the entry is broken and
  # the exit code was 0. Non-ASCII is *not* refused: a UTF-8 path is legitimate.
  case "$candidate" in
    *[[:cntrl:]]*)
      printf 'error: --exec may not contain a control character (a newline '\
'would split the entry in two)\n' >&2
      exit 2
      ;;
  esac
  # `%` is the spec's field-code introducer (`%f`, `%U`, `%%`), so an unescaped
  # one makes the compositor substitute rather than execute. Doubling it here
  # would be a silent rewrite of the caller's path; refusing says what happened.
  # `$` and a backtick are refused for the same reason the quote is: the value
  # lands inside a double-quoted Exec, where the spec reserves both.
  case "$candidate" in
    *%*|*'$'*|*'`'*)
      printf 'error: --exec may not contain %%, $ or a backtick: %s\n' \
        "$candidate" >&2
      exit 2
      ;;
  esac
  # A leading dash would be read as an option by whatever eventually runs the
  # entry, and `--exec --help` is the realistic way to produce one: the flag
  # takes the next word whatever it is.
  case "$candidate" in
    -*)
      printf 'error: --exec looks like a flag rather than a path: %s\n' \
        "$candidate" >&2
      exit 2
      ;;
  esac
  # A bare name is fine — that is the shipped default, resolved on the session's
  # PATH. A path is not: the spec requires an absolute one, and a relative value
  # is resolved against the compositor's working directory rather than the
  # caller's, so `--exec build/linux/x64/debug/bundle/hotkey_grammar_corrector`
  # (the value a developer has to hand) installs an entry that never launches.
  case "$candidate" in
    /*) ;;
    */*)
      printf 'error: --exec must be absolute or a bare command name: %s\n' \
        "$candidate" >&2
      exit 2
      ;;
  esac
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --exec)
        [ "$#" -ge 2 ] || { printf 'error: --exec needs a path\n' >&2; usage; exit 2; }
        validate_exec "$2"
        exec_path="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'error: unknown argument "%s"\n' "$1" >&2
        usage
        exit 2
        ;;
    esac
  done
}

# One XDG root: the environment's value when it is usable, the spec's default
# otherwise. The base-directory specification requires a relative value be
# *ignored* rather than resolved, and it means it: a relative root installs the
# entries under whatever directory the caller happened to be in, where no
# compositor looks, and exits 0.
xdg_root() {
  local value="$1" fallback="$2" name="$3"
  case "$value" in
    /*) printf '%s' "$value" ; return 0 ;;
  esac
  # Only now does the fallback have to exist. A caller with no HOME that gave an
  # absolute root returned above; one that gave nothing usable is the only case
  # that has to fail, and it fails naming both halves of what it needs.
  if [ -z "$fallback" ]; then
    printf 'error: %s is not set to an absolute path and HOME is unset, so '\
'there is no directory to install into. Set %s, or set HOME.\n' \
      "$name" "$name" >&2
    exit 1
  fi
  case "$value" in
    '') printf '%s' "$fallback" ;;
    *)
      printf 'warning: %s is relative ("%s"); the XDG base directory '\
'specification requires ignoring it, so %s is used instead\n' \
        "$name" "$value" "$fallback" >&2
      printf '%s' "$fallback"
      ;;
  esac
}

require_source() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf 'error: required source file not found: %s\n' "$path" >&2
    exit 1
  fi
}

# The file a write is currently staged through, or empty between writes.
staged=''

rm_staged() {
  [ -n "$staged" ] && rm -f -- "$staged"
  return 0
}

# The default under $HOME for one XDG root, or empty when there is no $HOME.
#
# Resolved lazily, because `set -u` makes "${HOME}/.local/share" an error rather
# than a value: a systemd unit, a minimal container or a scrubbed CI step can
# have no HOME at all, and passing both XDG roots as absolute paths is exactly
# how such a caller is supposed to work. Expanding HOME eagerly killed that
# caller with `HOME: unbound variable` before a single file was written.
home_default() {
  local suffix="$1" home="${HOME:-}"
  [ -n "$home" ] && printf '%s/%s' "$home" "$suffix"
  return 0
}

# The Exec= line for the requested path. A value carrying whitespace is quoted,
# because the spec parses an unquoted Exec as a command followed by arguments —
# so `/opt/my apps/hgc` would otherwise launch `/opt/my` with `apps/hgc`.
#
# A single quote is quoted for a different reason and is easy to miss, because
# it needs no whitespace to do damage: the spec reserves it, and GLib's
# `g_shell_parse_argv` — which is what GDesktopAppInfo launches through — reads
# an unquoted one as an opening quote and fails the whole line with
# "Text ended before matching quote was found". `/opt/nick's-tools/hgc` is an
# ordinary path, it passes every arm of validate_exec, and unquoted it installs
# an entry that cannot launch. Inside the double quotes it parses correctly.
exec_line() {
  case "$exec_path" in
    *[[:space:]]*|*\'*) printf 'Exec="%s"' "$exec_path" ;;
    *)                  printf 'Exec=%s' "$exec_path" ;;
  esac
}

# Copies one entry to its destination, rewriting Exec= when --exec was given.
# Written whole rather than edited in place, so a rerun cannot accumulate edits.
#
# Staged through a temporary file in the destination directory and renamed, so
# the path a compositor reads is either the old entry or the new one and never a
# half-written or truncated file. A plain `> "$destination"` truncates before awk
# writes a byte, which on a failure or a kill mid-write leaves a zero-length
# .desktop in the user's real applications directory — taking AD-11's binding
# with it, and reported as `wrote …` either way.
install_entry() {
  local source="$1" destination="$2"
  mkdir -p -- "$(dirname -- "$destination")"
  # Global rather than local, and cleared on success: the EXIT trap runs after
  # this frame is gone. `set -e` means any command below can end the script, and
  # the stage lives in the user's *real* applications directory — so without the
  # trap a failed awk leaves `…desktop.tmp.1234` beside the entry forever, and
  # every rerun that fails the same way leaves another.
  staged="${destination}.tmp.$$"
  trap 'rm_staged' EXIT
  if [ -n "$exec_path" ]; then
    # Through ENVIRON, not `awk -v`: -v applies escape-sequence processing to
    # its value, so a `\t` in a path would become a tab and a `\n` would split
    # the entry in two — leaving a file with no valid Exec and a zero exit.
    # (validate_exec rejects backslashes as well; this is the second lock.)
    #
    # Scoped to the [Desktop Entry] group, matching the reader in
    # test/architecture/desktop_entries_test.dart. `/^Exec=/` alone matches in
    # any group, so the day one of these entries grows a `[Desktop Action …]`
    # group — the standard way to give a tray app a right-click command — its
    # action's command would be silently overwritten with the main binary.
    REPLACEMENT="$(exec_line)" awk \
      '/^\[/ { group = $0 }
       /^Exec=/ && group == "[Desktop Entry]" { print ENVIRON["REPLACEMENT"]; next }
       { print }' \
      "$source" > "$staged"
  else
    cp -- "$source" "$staged"
  fi
  # The rewrite is a substitution, so it is a silent no-op on a source that has
  # no Exec= line in its [Desktop Entry] group — and an entry with no Exec is
  # exactly as dead as one with a wrong Exec, while `wrote …` says neither.
  #
  # Group-scoped, exactly like the rewrite above, and for the same reason: a
  # bare `grep -q '^Exec='` is satisfied by a `[Desktop Action …]` group's own
  # Exec, which is the one case this guard exists for. The rewrite would touch
  # nothing, the guard would pass on the action's line, and the installer would
  # print `wrote …` over an entry whose [Desktop Entry] group has no Exec at all.
  if ! awk '/^\[/ { group = $0 }
            /^Exec=/ && group == "[Desktop Entry]" { found = 1 }
            END { exit !found }' "$staged"; then
    printf 'error: no Exec= line was produced in the [Desktop Entry] group of '\
'%s (source: %s)\n' "$destination" "$source" >&2
    exit 1
  fi
  mv -- "$staged" "$destination"
  # Renamed, so there is nothing left to clean up and nothing the next call's
  # trap could delete out from under an installed entry.
  staged=''
  trap - EXIT
  printf 'wrote %s\n' "$destination"
}

main() {
  parse_arguments "$@"

  require_source "$entry_source"
  require_source "$autostart_source"
  require_source "$icon_source"

  local data_home config_home
  data_home="$(xdg_root "${XDG_DATA_HOME:-}" "$(home_default .local/share)" XDG_DATA_HOME)"
  config_home="$(xdg_root "${XDG_CONFIG_HOME:-}" "$(home_default .config)" XDG_CONFIG_HOME)"

  local applications_dir="${data_home}/applications"
  local autostart_dir="${config_home}/autostart"
  local icon_dir="${data_home}/icons/hicolor/32x32/apps"

  install_entry "$entry_source" "${applications_dir}/${APP_ID}.desktop"
  install_entry "$autostart_source" "${autostart_dir}/${APP_ID}.desktop"

  # Staged and renamed for the same reason the entries are: `cp` truncates its
  # destination before it writes a byte, so an interrupt or a full disk mid-copy
  # leaves a zero-length PNG that resolves as a permanently blank launcher icon
  # — and no rerun repairs it unless that rerun gets this far.
  mkdir -p -- "$icon_dir"
  staged="${icon_dir}/${APP_ID}.png.tmp.$$"
  trap 'rm_staged' EXIT
  cp -- "$icon_source" "$staged"
  mv -- "$staged" "${icon_dir}/${APP_ID}.png"
  staged=''
  trap - EXIT
  printf 'wrote %s\n' "${icon_dir}/${APP_ID}.png"

  # Optional: a session that has no desktop-file-utils installed still gets a
  # correct install, so a missing tool is not a failure.
  if ! command -v update-desktop-database > /dev/null 2>&1; then
    printf 'update-desktop-database not found; skipped the cache refresh\n'
  elif update-desktop-database "$applications_dir"; then
    printf 'refreshed the desktop database in %s\n' "$applications_dir"
  else
    # Not fatal — the entries are installed and correct either way — but never
    # reported as a refresh that happened. A stale cache is a real symptom and
    # a user chasing it deserves to know this step failed.
    printf 'warning: update-desktop-database failed in %s; the entries are '\
'installed but the cache was not refreshed\n' "$applications_dir" >&2
  fi

  printf '\nInstalled the %s entries. The app-id entry is what lets a Wayland\n' "$APP_ID"
  printf 'compositor keep the global shortcut binding (AD-11); the autostart\n'
  printf 'entry starts the daemon at your next login (AD-14).\n'
}

main "$@"
