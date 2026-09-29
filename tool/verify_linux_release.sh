#!/usr/bin/env bash
set -euo pipefail

version='' output_dir=''
while (($#)); do
  case "$1" in
    --version) version="${2-}"; shift 2 ;;
    --output-dir) output_dir="${2-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[a-z0-9]+(-[a-z0-9]+)*\.[1-9][0-9]*)?$ && -d "$output_dir" ]] || { echo 'invalid version or output directory' >&2; exit 2; }
for command_name in tar dpkg-deb flatpak ldd; do
  command -v "$command_name" >/dev/null || { echo "missing verifier tool: $command_name" >&2; exit 1; }
done
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
app_id=com.divertedriver.HotkeyGrammarCorrector
base="hotkey_grammar_corrector-${version}"
extensions=(linux-x86_64.tar.gz linux-amd64.deb linux-x86_64.AppImage linux-x86_64.flatpak)
for extension in "${extensions[@]}"; do
  file="$output_dir/$base-$extension"
  [[ -s "$file" ]] || { echo "missing or empty package: $file" >&2; exit 1; }
done
[[ "$(find "$output_dir" -maxdepth 1 -type f | wc -l)" -eq 4 ]] || { echo 'expected exactly four package files' >&2; exit 1; }

check_bundle() {
  local root="$1" native_dependencies
  [[ -x "$root/hotkey_grammar_corrector" && -d "$root/lib" && -d "$root/data/flutter_assets" ]] || { echo "incomplete bundle: $root" >&2; exit 1; }
  [[ -f "$root/data/flutter_assets/assets/sidecar/claude_agent_sdk_sidecar.py" ]] || { echo 'sidecar asset missing' >&2; exit 1; }
  [[ -x "$root/sidecar-python" && -x "$root/sidecar-packages/claude_agent_sdk/_bundled/claude" ]] || { echo 'packaged sidecar runtime missing' >&2; exit 1; }
  "$root/sidecar-python" -c 'import claude_agent_sdk; import importlib.metadata as m; import os; import subprocess; assert m.version("claude-agent-sdk") == "0.2.132"; subprocess.run([os.environ["CLAUDE_CODE_CLI_PATH"], "--version"], check=True, capture_output=True)'
  native_dependencies="$(find "$root" -type f \( -name 'hotkey_grammar_corrector' -o -name '*.so' -o -name '*.so.*' \) -exec ldd '{}' + 2>/dev/null)"
  if grep -q 'not found' <<< "$native_dependencies"; then
    echo 'unresolved native dependency' >&2
    exit 1
  fi
}

tar -C "$work_dir" -xzf "$output_dir/$base-linux-x86_64.tar.gz"
check_bundle "$work_dir/bundle"
[[ -x "$work_dir/tool/install_desktop_entries.sh" && -f "$work_dir/linux/packaging/${app_id}.desktop" && -f "$work_dir/linux/packaging/autostart/${app_id}.desktop" && -s "$work_dir/assets/tray/hotkey-grammar-corrector.png" ]] || { echo 'tarball desktop installer incomplete' >&2; exit 1; }
XDG_DATA_HOME="$work_dir/tar-data" XDG_CONFIG_HOME="$work_dir/tar-config" \
  "$work_dir/tool/install_desktop_entries.sh" --exec "$work_dir/bundle/hotkey_grammar_corrector"
grep -Fq "$work_dir/bundle/hotkey_grammar_corrector" "$work_dir/tar-data/applications/${app_id}.desktop" || { echo 'tarball desktop entry points elsewhere' >&2; exit 1; }
dpkg-deb --info "$output_dir/$base-linux-amd64.deb" >/dev/null
dpkg-deb --contents "$output_dir/$base-linux-amd64.deb" >/dev/null
dpkg-deb -x "$output_dir/$base-linux-amd64.deb" "$work_dir/deb"
check_bundle "$work_dir/deb/opt/hotkey_grammar_corrector"
expected_deb_version="${version/-/\~}"
[[ "$(dpkg-deb -f "$output_dir/$base-linux-amd64.deb" Version)" == "$expected_deb_version" ]] || { echo 'Debian version mismatch' >&2; exit 1; }
[[ "$(dpkg-deb -f "$output_dir/$base-linux-amd64.deb" Depends)" == *'libayatana-appindicator3-1'* ]] || { echo 'Debian tray dependency missing' >&2; exit 1; }
[[ -x "$work_dir/deb/usr/bin/hotkey_grammar_corrector" && -f "$work_dir/deb/usr/share/applications/${app_id}.desktop" && -s "$work_dir/deb/usr/share/icons/hicolor/32x32/apps/${app_id}.png" && -f "$work_dir/deb/etc/xdg/autostart/${app_id}.desktop" ]] || { echo 'Debian integration files missing' >&2; exit 1; }

mkdir "$work_dir/appimage"
(cd "$work_dir/appimage" && "$output_dir/$base-linux-x86_64.AppImage" --appimage-extract >/dev/null)
appdir="$work_dir/appimage/squashfs-root"
[[ -x "$appdir/AppRun" && -f "$appdir/${app_id}.desktop" && -s "$appdir/${app_id}.png" ]] || { echo 'AppImage desktop integration missing' >&2; exit 1; }
check_bundle "$appdir/usr/bin"
[[ -x "$appdir/tool/install_desktop_entries.sh" ]] || { echo 'AppImage desktop installer missing' >&2; exit 1; }
APPIMAGE="$output_dir/$base-linux-x86_64.AppImage" XDG_DATA_HOME="$work_dir/appimage-data" XDG_CONFIG_HOME="$work_dir/appimage-config" \
  "$appdir/AppRun" --install-desktop
grep -Fq "$output_dir/$base-linux-x86_64.AppImage" "$work_dir/appimage-data/applications/${app_id}.desktop" || { echo 'AppImage desktop entry points elsewhere' >&2; exit 1; }

flatpak_bundle="$output_dir/$base-linux-x86_64.flatpak"
XDG_DATA_HOME="$work_dir/xdg-data" XDG_CONFIG_HOME="$work_dir/xdg-config" flatpak --user install -y --bundle "$flatpak_bundle" >/dev/null
flatpak_env=(env XDG_DATA_HOME="$work_dir/xdg-data" XDG_CONFIG_HOME="$work_dir/xdg-config")
metadata="$("${flatpak_env[@]}" flatpak info --user --show-metadata "$app_id")"
normalize_grants() { tr ';' '\n' | sed '/^$/d' | sort | paste -sd, -; }
sockets="$(printf '%s\n' "$metadata" | sed -n 's/^sockets=//p' | normalize_grants)"
shared="$(printf '%s\n' "$metadata" | sed -n 's/^shared=//p' | normalize_grants)"
[[ "$sockets" == 'fallback-x11,wayland' && "$shared" == 'ipc,network' ]] || { echo 'Flatpak display/network permissions differ from approved set' >&2; exit 1; }
[[ "$metadata" == *'org.freedesktop.secrets=talk'* ]] || { echo 'Flatpak Secret Service permission missing' >&2; exit 1; }
[[ "$metadata" != *'filesystems='* && "$metadata" != *'org.freedesktop.Flatpak'* ]] || { echo 'Flatpak contains prohibited permission' >&2; exit 1; }
"${flatpak_env[@]}" flatpak run --user --command=/app/bin/sidecar-python "$app_id" -c 'import claude_agent_sdk; import os; import subprocess; assert os.path.isfile("/app/bin/data/flutter_assets/assets/sidecar/claude_agent_sdk_sidecar.py"); subprocess.run([os.environ["CLAUDE_CODE_CLI_PATH"], "--version"], check=True, capture_output=True)'
native_dependencies="$("${flatpak_env[@]}" flatpak run --user --command=sh "$app_id" -c \
  'find /app/bin -type f \( -name hotkey_grammar_corrector -o -name "*.so" -o -name "*.so.*" \) -exec ldd {} +')"
if grep -q 'not found' <<< "$native_dependencies"; then
  echo 'Flatpak native dependency unresolved' >&2
  exit 1
fi
echo "verified four Linux release packages for $version"
