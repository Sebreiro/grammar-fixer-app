#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_binary="$(mktemp /tmp/hgc-panel-activation-test-XXXXXX)"
trap 'rm -f "$test_binary"' EXIT

c++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -pthread \
  -I"$project_dir/linux/runner" \
  "$project_dir/test/native/tray_activation_token_test.cc" \
  "$project_dir/linux/runner/tray_activation_token.cc" \
  $(pkg-config --cflags --libs gio-2.0) -o "$test_binary"
dbus-run-session -- "$test_binary"
