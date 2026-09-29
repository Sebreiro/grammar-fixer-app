#!/usr/bin/env bash
#
# Builds the pinned Python environment the AD-19 sidecar runs in.
#
# The daemon's default provider is a three-process chain — daemon → Python
# sidecar → `claude` CLI — and the middle link is the one a checkout cannot
# supply itself. This script creates .venv-sidecar (untracked, per machine),
# installs assets/sidecar/requirements.txt into it, and then *verifies* that the
# module imports and that the version it resolves is the pinned one, so a
# silently-upgraded or half-installed environment is a failure here rather than a
# surprise at correction time.
#
# It is idempotent and offline on the happy path: an environment that already
# satisfies the pin is reported and left untouched, so a second run neither
# reinstalls nor reaches the network.
#
# Usage: tool/provision_sidecar.sh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root

readonly requirements="${repo_root}/assets/sidecar/requirements.txt"
readonly venv_dir="${repo_root}/.venv-sidecar"
readonly venv_python="${venv_dir}/bin/python3"
readonly distribution='claude-agent-sdk'
readonly module='claude_agent_sdk'

# The pinned version, read out of requirements.txt rather than repeated here.
# A third copy of the pin is exactly what test/architecture/sidecar_pin_drift_test.dart
# exists to prevent.
#
# The extraction matches that test's Dart rule deliberately: stop at the first
# whitespace or `#`. A naive `${line#*==}` keeps a trailing comment, so
# `claude-agent-sdk==0.2.132  # keep in sync` would install correctly and then
# fail this script's own verification — blaming the environment for a parsing
# bug here. Two pinning lines are refused outright rather than silently
# resolved to the first: which one ships is not this script's guess to make.
read_pin() {
  local matches
  matches="$(grep -cE "^${distribution}==" "$requirements" || true)"
  if [ "$matches" -eq 0 ]; then
    printf 'error: %s pins no %s== version\n' "$requirements" "$distribution" >&2
    exit 1
  fi
  if [ "$matches" -gt 1 ]; then
    printf 'error: %s pins %s on %s lines; exactly one must\n' \
      "$requirements" "$distribution" "$matches" >&2
    exit 1
  fi
  local pin
  pin="$(
    grep -E "^${distribution}==" "$requirements" \
      | head -n 1 \
      | sed -nE "s/^${distribution}==([^[:space:]#]+).*/\1/p"
  )"
  # -n plus /p, not a bare substitution: a bare `s///` prints the line whether
  # or not it matched, so `claude-agent-sdk==` with no version at all made the
  # pin the whole requirement line and the failure arrived twenty lines later as
  # `pins claude-agent-sdk==claude-agent-sdk== but the environment resolved …` —
  # the parsing bug blaming the environment that this function exists to avoid.
  if [ -z "$pin" ]; then
    printf 'error: %s has a %s== line with no version after it\n' \
      "$requirements" "$distribution" >&2
    exit 1
  fi
  printf '%s' "$pin"
}

# The version an interpreter actually resolves, or empty when it cannot import
# the package at all. Never fails the script: "not installed yet" is the normal
# state on a fresh checkout.
#
# The module is imported, not just looked up in the metadata. `version()` reads
# the `dist-info` directory, which outlives the code it describes: a partially
# removed package, a wheel installed for a different Python ABI, or a broken
# native dependency all keep reporting the pin while `import claude_agent_sdk`
# fails. This script would then report a provisioned host, the fake-CLI rows
# would skip on their own import probe, and `dart test` would be green having
# run none of them — the silent-skip condition the whole story exists to retire.
installed_version() {
  local interpreter="$1"
  "$interpreter" -c \
    "import ${module}; import importlib.metadata as m; print(m.version('${distribution}'))" \
    2> /dev/null || true
}

create_venv() {
  local host_python
  host_python="$(command -v python3 || true)"
  if [ -z "$host_python" ]; then
    printf 'error: no python3 on PATH; the sidecar needs Python 3.11+\n' >&2
    exit 1
  fi

  # Some distributions (and this devcontainer) ship a python3 with no
  # ensurepip. `python3 -m venv` then fails deep inside ensurepip with a
  # message about a missing module, which reads like a broken script rather
  # than a missing OS package — so probe for it and say what is actually
  # needed.
  if "$host_python" -c 'import ensurepip' > /dev/null 2>&1; then
    "$host_python" -m venv "$venv_dir"
    return
  fi

  printf 'note: %s has no ensurepip, so the environment is created without pip\n' \
    "$host_python"
  "$host_python" -m venv --without-pip "$venv_dir"
}

# Everything a user needs to type when this host cannot install the pin itself.
# Both commands need the network; neither is run for them.
print_pip_bootstrap() {
  printf '\n'
  printf 'The environment at %s has no pip, so the pin cannot be installed.\n' "$venv_dir"
  printf 'Bootstrap it (both steps need network access), then rerun this script:\n\n'
  printf '  curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py\n'
  printf '  %s /tmp/get-pip.py\n\n' "$venv_python"
  printf 'Or, if you have uv: uv pip install --python %s -r %s\n' \
    "$venv_python" "$requirements"
}

install_requirements() {
  if ! "$venv_python" -m pip --version > /dev/null 2>&1; then
    print_pip_bootstrap
    exit 1
  fi
  "$venv_python" -m pip install --upgrade --requirement "$requirements"
}

report_ready() {
  local version="$1"
  printf '\nsidecar interpreter: %s\n' "$venv_python"
  printf 'resolved %s %s (pinned in %s)\n' "$module" "$version" "$requirements"
  printf '\nThis is the interpreter a fresh config points at: the shipped\n'
  printf 'default is derived, preferring this environment and falling back to\n'
  printf 'a bare `python3` when it is absent — which cannot import %s.\n' \
    "$module"
  printf 'The derivation runs once, when config.json is first written, so a\n'
  printf 'config seeded before this script ran keeps the fallback until its\n'
  printf '`interpreter` setting is edited or the file is deleted.\n'
  printf '\nNext:\n'
  printf '  dart test --exclude-tags=live test/application test/architecture \\\n'
  printf '    test/domain test/infrastructure test/fakes_smoke_test.dart\n'
  printf '  dart test --tags=live --run-skipped \\\n'
  printf '    test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart\n'
}

main() {
  if [ ! -f "$requirements" ]; then
    printf 'error: required source file not found: %s\n' "$requirements" >&2
    exit 1
  fi
  local pin
  pin="$(read_pin)"

  # Already satisfied: report and stop. This is what makes a second run cheap,
  # offline, and non-destructive of an environment provisioned by other means
  # (uv, a distro package, a hand-built venv).
  if [ -x "$venv_python" ] && [ "$(installed_version "$venv_python")" = "$pin" ]; then
    printf 'already provisioned: %s pins %s and the environment resolves it\n' \
      "$requirements" "$pin"
    report_ready "$pin"
    return
  fi

  if [ ! -x "$venv_python" ]; then
    create_venv
  fi
  install_requirements

  local resolved
  resolved="$(installed_version "$venv_python")"
  if [ -z "$resolved" ]; then
    # Distinct from a version mismatch, because the remedy is different: the
    # install reported success and the module still will not import, so the
    # interpreter's own error is the only useful thing to print.
    printf 'error: %s cannot import %s after installing %s\n' \
      "$venv_python" "$module" "$requirements" >&2
    "$venv_python" -c "import ${module}" >&2 || true
    exit 1
  fi
  if [ "$resolved" != "$pin" ]; then
    printf 'error: %s pins %s==%s but the environment resolved "%s"\n' \
      "$requirements" "$distribution" "$pin" "$resolved" >&2
    exit 1
  fi
  report_ready "$resolved"
}

main "$@"
