# grammar-fixer-app
desktop extension app to instantly fix grammar

## Developing

Linux only. The Flutter toolchain is expected on `PATH`.

### 1. Provision the sidecar environment

The default correction provider runs the Claude Agent SDK out of process, so the
chain is daemon → Python sidecar → `claude` CLI. The middle link is per-machine
and untracked:

```sh
tool/provision_sidecar.sh
```

It creates `.venv-sidecar`, installs the version pinned in
`assets/sidecar/requirements.txt`, and then verifies that the module actually
imports and that the version it resolves is the pinned one — metadata alone is
not accepted, because a half-installed environment keeps reporting the pin long
after the code stops importing. Rerunning it on an environment that already satisfies the pin is a
no-op and needs no network. On an interpreter with no `ensurepip` it prints the
`get-pip.py` bootstrap rather than failing somewhere inside `venv`.

**This step makes checkout defaults work.** A packaged build instead installs
`sidecar-python` beside the app binary and vendors the pinned SDK and its
bundled CLI. A fresh packaged config chooses that wrapper first. A custom
interpreter setting is never overwritten. The derivation runs only when the
config file is first written, so an older config keeps its selected path until
you edit it or seed a new config. Checkout runs without the provisioned
environment fall back to bare `python3`, which cannot import the SDK.

### 2. Install the desktop entries

```sh
tool/install_desktop_entries.sh --exec /path/to/hotkey_grammar_corrector
```

This writes three files. Two are the entries themselves, in two different XDG
destinations:

* `${XDG_DATA_HOME:-~/.local/share}/applications/com.divertedriver.HotkeyGrammarCorrector.desktop`
  — a **hard requirement of the Wayland hotkey**, not packaging polish. GNOME
  discards the global-shortcut binding when the app id the daemon registers has
  no installed entry of the same basename.
* `${XDG_CONFIG_HOME:-~/.config}/autostart/com.divertedriver.HotkeyGrammarCorrector.desktop`
  — starts the resident daemon at login.

The third is the tray artwork, installed as the entries' icon at
`${XDG_DATA_HOME:-~/.local/share}/icons/hicolor/32x32/apps/com.divertedriver.HotkeyGrammarCorrector.png`.

Both entries run the identical command, so login starts the same binary a manual
launch does. Without `--exec` they keep a bare `Exec=hotkey_grammar_corrector`,
which works only if the binary is on the session's `PATH`. A value that would
install a broken entry is refused rather than written: empty, relative (pass the
absolute path, not `build/linux/.../bundle/...`), or carrying a backslash, a
double quote, a control character, `%`, `$` or a backtick. A relative
`XDG_DATA_HOME`/`XDG_CONFIG_HOME` is ignored in favour of the specification
default, as the XDG base-directory spec requires. Rerunning is idempotent, and
each entry is staged and renamed rather than truncated in place.

### Window behavior

The open panel and Settings window appear in the desktop taskbar/dock. The app
starts with its window hidden and remains available from the tray.

Settings → **When closing the window** chooses **Close to tray** (the default)
or **Quit app**. Quit waits for pending history writes and releases daemon
resources before exiting. Hotkey dismissal and focus loss continue to hide the
panel regardless of this preference.

The same preference is stored as `"closeBehavior": "closeToTray"` or
`"closeBehavior": "quit"` in `config.json`. Existing files without the field
use the tray default; external edits take effect without restarting.

### Correction prompts

On first run the app creates a populated config at
`${XDG_CONFIG_HOME:-~/.config}/hotkey-grammar-corrector/config.json` and writes
its default correction prompt to `prompt-default-formal-casual-shorter.txt`
beside it. Each preset references its own plain UTF-8 text file:

```json
{
  "id": "default-formal-casual-shorter",
  "providerId": "claude-agent-sdk",
  "model": "claude-sonnet-5",
  "systemPromptFile": "prompt-default-formal-casual-shorter.txt"
}
```

Open that `.txt` file to read or edit the multiline prompt directly. File names
are relative to the config directory and must name a `.txt` file beside
`config.json`. Each preset needs its own file. You can choose a different name
by changing `systemPromptFile`; create the file before updating the reference.

You can also edit the active preset under **Settings → Correction prompt** and
choose **Save prompt**. Settings saves to the same text file. Both surfaces stay
in sync; saved edits apply to the next correction without restarting. The prompt
stays paired with its preset's model and provider. Both shipped providers append
the required `FORMAL:`, `CASUAL:`, `SHORTER:` and final `END` response format to
each request, so your prompt can focus on grammar instructions. This does not
rewrite your saved prompt file. A model response that ignores the format or ends
early still appears as an inline error with **Retry**.

For OpenRouter endpoints the app disables optional thinking and excludes
reasoning from the response, so the correction stream contains the requested
suggestions. These request options are specific to `openrouter.ai`.

Existing inline `systemPrompt` strings migrate to text files when the config is
loaded, preserving the exact prompt, model and provider. New files never replace
unrelated existing text files. A preset must use either `systemPrompt` or
`systemPromptFile`; remove the inline field when adding a file reference. Missing,
unreadable or blank prompt files produce a config warning; they are not replaced
with default text. Default files are seeded only when absent, so recreating a
missing config also preserves an existing default prompt file.

### Logs

Logs are appended as JSON lines to
`${XDG_CONFIG_HOME:-~/.config}/hotkey-grammar-corrector/logs/grammmar-corrector.log`,
beside `config.json`. The daemon also writes diagnostics to stderr. The single
log file defaults to a 1 MiB limit. Set `"logMaxBytes": 1048576`
in `config.json` or choose **Log file size limit** in Settings; changes apply
without restarting. Values must be integers of at least 1024 bytes. Before an
entry would exceed the limit, the same file is cleared and logging starts from
the beginning. Entries always remain complete JSON lines; an entry larger than
the limit is reduced to a marked summary. Logs below the limit are retained
across restarts and flushed on Quit, stop signals, and startup abort.
If the file cannot be written, an error is reported on stderr and the daemon
continues running.

Failed corrections are logged. HTTP provider errors include the status, response
body, and available request-id and Retry-After headers, including OpenRouter's
429 details and errors received during streaming. Response capture is limited to
64 KiB and marks truncation; credentials and echoed correction text are redacted.

### 3. Run the tests

The binding-free suite, which is also what CI runs:

```sh
dart test --exclude-tags=live \
  test/application test/architecture test/domain test/infrastructure \
  test/fakes_smoke_test.dart
```

Everything, including the widget and platform rows:

```sh
flutter test
```

The fake-`claude`-CLI rows live in
`test/infrastructure/correction/claude_agent_sdk/sidecar_fake_cli_test.dart` and
run inside the scoped command above once step 1 has been done. They stub the CLI
that the SDK spawns, so they exercise the sidecar's failure branches with no
network and no model. Without `.venv-sidecar` they skip, and the skip reason
names the rows and repeats the provisioning command.

### 4. Run the live smoke deliberately

One end-to-end check against the real sidecar, the real SDK, and the real
`claude` CLI. It is tagged `live` and skipped by default because it spawns a
nested `claude` process:

```sh
dart test --tags=live --run-skipped \
  test/infrastructure/correction/claude_agent_sdk/claude_agent_sdk_sidecar_live_test.dart
```

Run it after changing the shipped system prompt: it is the only check that a
real model honours the prompt's `END` sentinel.

## Linux releases

The **Linux release** GitHub Actions workflow is manual. Dispatch it from
`main` with `bump=major`, `minor`, or `patch` for a stable release. Dispatch
from another branch for a branch-labeled, numbered prerelease. A stable run
commits the selected three-component version to `pubspec.yaml`, then atomically
pushes that commit and its annotated tag. A branch run pushes only its tag;
its temporary `pubspec.yaml` change stays in the runner. The workflow builds
and checks a tarball, `.deb`, AppImage, and Flatpak before it pushes anything.

If a tag was pushed but release creation or upload failed, dispatch the same
branch again with `retry_tag=vX.Y.Z` or `retry_tag=vX.Y.Z-branch.N`. The bump
input is ignored. Recovery verifies tag provenance, downloads the original
verified packages from the first run's retained Actions artifact, checks their
recorded hashes and package contents, and resumes a matching draft without
overwriting an existing asset. That artifact is retained for 90 days. A missing
artifact, mismatched asset, or published release needs operator review.

The workflow requires a `main` branch, a token with `contents: write` and
`actions: read`, and branch rules that permit the version commit and atomic push from the Actions
identity. A rejected push stops the run without force or rebase. The existing
merge-gate CI targets `master`; configure the release branch and repository
rules before dispatching this workflow from `main`.

On a Linux host with Flutter 3.44.8, Python 3.11+, pip or uv, `dpkg-deb`,
`linuxdeploy`, Flatpak, Flatpak Builder, and the GNOME 50 runtime and SDK:

```sh
tool/package_linux_release.sh --version 1.0.1 --output-dir /tmp/hgc-release-1.0.1
tool/verify_linux_release.sh --version 1.0.1 --output-dir /tmp/hgc-release-1.0.1
```

The tarball keeps the complete Flutter `bundle/` and includes the desktop
installer. Extract it, then run its exact-ID installer from the extracted root:

```sh
./tool/install_desktop_entries.sh --exec "$(realpath ./bundle/hotkey_grammar_corrector)"
```

Launch the binary in that bundle after installation.
The `.deb` installs a `/usr/bin` launcher, desktop entry, autostart entry, and
icon. Make the AppImage executable, keep it at its installed path, and run
`./hotkey_grammar_corrector-*.AppImage --install-desktop` to install its
Wayland desktop identity and autostart entry. Moving the AppImage later requires
rerunning that command and updating any saved sidecar interpreter path. Import
the Flatpak bundle with `flatpak install --user ./hotkey_grammar_corrector-*.flatpak`.
The tarball, `.deb`, and AppImage need host Python 3.11+; the Flatpak uses its runtime Python
and bundles compatible SDK wheels. A real Wayland hotkey/tray check still needs
a desktop compositor; headless package checks do not exercise it.
