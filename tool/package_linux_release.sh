#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version='' output_dir=''
while (($#)); do
  case "$1" in
    --version) version="${2-}"; shift 2 ;;
    --output-dir) output_dir="${2-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[a-z0-9]+(-[a-z0-9]+)*\.[1-9][0-9]*)?$ ]] || { echo 'invalid release version' >&2; exit 2; }
[[ -n "$output_dir" && "$output_dir" = /* && "$output_dir" != / ]] || { echo 'output directory must be an absolute non-root path' >&2; exit 2; }
for command_name in flutter python3 dpkg-deb tar flatpak flatpak-builder linuxdeploy ldd ldconfig readlink file; do
  command -v "$command_name" >/dev/null || { echo "missing build tool: $command_name" >&2; exit 1; }
done
[[ "$(flutter --version | head -1)" == 'Flutter 3.44.8 '* ]] || { echo 'Flutter 3.44.8 is required' >&2; exit 1; }
source_date_epoch="${SOURCE_DATE_EPOCH:-$(git -C "$repo_root" log -1 --format=%ct)}"
[[ "$source_date_epoch" =~ ^[0-9]+$ ]] || { echo 'SOURCE_DATE_EPOCH must be numeric' >&2; exit 2; }
export SOURCE_DATE_EPOCH="$source_date_epoch"
[[ ! -e "$output_dir" || -d "$output_dir" ]] || { echo 'output path is not a directory' >&2; exit 2; }
mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
[[ -z "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] || { echo 'output directory must be empty' >&2; exit 2; }
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
cd "$repo_root"
flutter build linux --release
bundle="$repo_root/build/linux/x64/release/bundle"
[[ -x "$bundle/hotkey_grammar_corrector" && -d "$bundle/lib" && -d "$bundle/data/flutter_assets" ]] || { echo 'incomplete Flutter bundle' >&2; exit 1; }
cp -a -- "$bundle" "$work_dir/bundle"
install -m 755 linux/packaging/sidecar-python "$work_dir/bundle/sidecar-python"
if python3 -m pip --version >/dev/null 2>&1; then
  python3 -m pip install --disable-pip-version-check --no-compile --target "$work_dir/bundle/sidecar-packages" -r assets/sidecar/requirements.txt
else
  command -v uv >/dev/null || { echo 'Python pip or uv is required to vendor the pinned SDK' >&2; exit 1; }
  uv pip install --python "$(command -v python3)" --target "$work_dir/bundle/sidecar-packages" -r assets/sidecar/requirements.txt
fi
"$work_dir/bundle/sidecar-python" -c 'import claude_agent_sdk; import importlib.metadata as m; assert m.version("claude-agent-sdk") == "0.2.132"'
app_id=com.divertedriver.HotkeyGrammarCorrector
desktop="linux/packaging/${app_id}.desktop"
icon=assets/tray/hotkey-grammar-corrector.png
[[ -s "$icon" && -f "$desktop" ]] || { echo 'desktop entry or icon missing' >&2; exit 1; }
install -d "$work_dir/tool" "$work_dir/linux/packaging/autostart" "$work_dir/assets/tray"
install -m 755 tool/install_desktop_entries.sh "$work_dir/tool/"
install -m 644 "$desktop" "$work_dir/linux/packaging/"
install -m 644 "linux/packaging/autostart/${app_id}.desktop" "$work_dir/linux/packaging/autostart/"
install -m 644 "$icon" "$work_dir/assets/tray/hotkey-grammar-corrector.png"
find "$work_dir/bundle" "$work_dir/tool" "$work_dir/linux" "$work_dir/assets" -exec touch -h -d "@$source_date_epoch" {} +
tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
  -C "$work_dir" -cf - bundle tool linux assets \
  | gzip -n > "$output_dir/hotkey_grammar_corrector-${version}-linux-x86_64.tar.gz"
deb="$work_dir/deb"
install -d "$deb/DEBIAN" "$deb/opt/hotkey_grammar_corrector" "$deb/usr/bin" "$deb/usr/share/applications" "$deb/usr/share/icons/hicolor/32x32/apps" "$deb/etc/xdg/autostart"
cp -a "$work_dir/bundle/." "$deb/opt/hotkey_grammar_corrector/"
install -m 644 "$desktop" "$deb/usr/share/applications/"
install -m 644 "$icon" "$deb/usr/share/icons/hicolor/32x32/apps/${app_id}.png"
install -m 644 "linux/packaging/autostart/${app_id}.desktop" "$deb/etc/xdg/autostart/"
printf '#!/usr/bin/env bash\nexec /opt/hotkey_grammar_corrector/hotkey_grammar_corrector "$@"\n' > "$deb/usr/bin/hotkey_grammar_corrector"
chmod 755 "$deb/usr/bin/hotkey_grammar_corrector"
deb_version="${version/-/\~}"
printf 'Package: hotkey-grammar-corrector\nVersion: %s\nArchitecture: amd64\nMaintainer: Hotkey Grammar Corrector maintainers\nDepends: python3 (>= 3.11), libgtk-3-0, libayatana-appindicator3-1, libsecret-1-0\nDescription: Resident Linux grammar correction daemon\n' "$deb_version" > "$deb/DEBIAN/control"
find "$deb" -exec touch -h -d "@$source_date_epoch" {} +
dpkg-deb --build --root-owner-group "$deb" "$output_dir/hotkey_grammar_corrector-${version}-linux-amd64.deb"
appdir="$work_dir/AppDir"
install -d "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/32x32/apps"
cp -a "$work_dir/bundle/." "$appdir/usr/bin/"
install -m 644 "$desktop" "$appdir/usr/share/applications/"
install -m 644 "$icon" "$appdir/usr/share/icons/hicolor/32x32/apps/${app_id}.png"
cp "$desktop" "$appdir/${app_id}.desktop"
cp "$icon" "$appdir/${app_id}.png"
install -m 755 linux/packaging/appimage/AppRun "$appdir/AppRun"
install -d "$appdir/tool" "$appdir/linux/packaging/autostart" "$appdir/assets/tray"
install -m 755 tool/install_desktop_entries.sh "$appdir/tool/"
install -m 644 "$desktop" "$appdir/linux/packaging/"
install -m 644 "linux/packaging/autostart/${app_id}.desktop" "$appdir/linux/packaging/autostart/"
install -m 644 "$icon" "$appdir/assets/tray/hotkey-grammar-corrector.png"
find "$appdir" -exec touch -h -d "@$source_date_epoch" {} +
(
  cd "$work_dir"
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 VERSION="$version" linuxdeploy --appdir "$appdir" --custom-apprun "$repo_root/linux/packaging/appimage/AppRun" --output appimage
)
appimage="$(find "$work_dir" -maxdepth 1 -name '*.AppImage' -print -quit)"
[[ -n "$appimage" ]] || { echo 'linuxdeploy emitted no AppImage' >&2; exit 1; }
mv "$appimage" "$output_dir/hotkey_grammar_corrector-${version}-linux-x86_64.AppImage"
flatpak_stage="$work_dir/flatpak-stage"
install -d "$flatpak_stage/desktop" "$flatpak_stage/native-libs" "$flatpak_stage/native-notices"
cp -a "$work_dir/bundle" "$flatpak_stage/bundle"
for library_name in libayatana-appindicator3.so.1 libayatana-indicator3.so.7 libayatana-ido3-0.4.so.0 libdbusmenu-glib.so.4 libdbusmenu-gtk3.so.4; do
  library_path="$(ldconfig -p | awk -v name="$library_name" '$1 == name && /x86-64/ { print $NF; exit }')"
  [[ -f "$library_path" ]] || { echo "missing Flatpak tray library: $library_name" >&2; exit 1; }
  install -m 644 "$library_path" "$flatpak_stage/native-libs/$library_name"
done
for package_name in libayatana-appindicator3-1 libayatana-indicator3-7 libayatana-ido3-0.4-0 libdbusmenu-glib4 libdbusmenu-gtk3-4; do
  notice_path="/usr/share/doc/$package_name/copyright"
  [[ -f "$notice_path" ]] || { echo "missing Flatpak library notice: $package_name" >&2; exit 1; }
  install -m 644 "$notice_path" "$flatpak_stage/native-notices/$package_name.copyright"
done
runtime_dir="$(flatpak info --show-location org.gnome.Platform//50)"
python_target="$(readlink "$runtime_dir/files/bin/python3")"
[[ "$python_target" =~ ^python(3\.[0-9]+)$ ]] || { echo 'cannot identify Flatpak runtime Python' >&2; exit 1; }
runtime_python="${BASH_REMATCH[1]}"
command -v uv >/dev/null || { echo 'uv is required for Flatpak Python wheel selection' >&2; exit 1; }
rm -rf "$flatpak_stage/bundle/sidecar-packages"
uv pip install --target "$flatpak_stage/bundle/sidecar-packages" --python-version "$runtime_python" --python-platform x86_64-manylinux_2_17 -r assets/sidecar/requirements.txt
install -m 644 "$desktop" "$flatpak_stage/desktop/${app_id}.desktop"
install -m 644 "$icon" "$flatpak_stage/desktop/${app_id}.png"
cp linux/packaging/${app_id}.flatpak.yml "$flatpak_stage/manifest.yml"
flatpak-builder --force-clean --disable-rofiles-fuse --state-dir="$work_dir/flatpak-state" --repo="$work_dir/flatpak-repo" "$work_dir/flatpak-build" "$flatpak_stage/manifest.yml"
flatpak build-bundle "$work_dir/flatpak-repo" "$output_dir/hotkey_grammar_corrector-${version}-linux-x86_64.flatpak" "$app_id"
tool/verify_linux_release.sh --version "$version" --output-dir "$output_dir"
