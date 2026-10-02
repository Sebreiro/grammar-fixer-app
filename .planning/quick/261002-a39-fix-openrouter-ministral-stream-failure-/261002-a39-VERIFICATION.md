---
quick_id: 261002-a39
status: passed
date: 2026-10-02
source_fix_commit: 466be28
appimage_launcher_commit: 0ec708f
---

# Verification

| Must-have | Evidence | Result |
|---|---|---|
| Requested model streams and completes | Two real-adapter requests; 17 and 26 deltas; exactly one CorrectionCompleted each; all three variants nonempty; zero failure logs | Passed |
| Accounting frames preserve valid completion | Existing decoder unit tests and held-open HTTP integration regression pass | Passed |
| Invalid/truncated streams still fail | Malformed usage, duplicate stop, changed finish, late text, missing DONE, oversized input, and interrupted transport regressions pass | Passed |
| Linux bundle includes verified repair | Successful `flutter build linux --release` from current source containing `466be28` | Passed |
| Exact sentence works through packaged UI | Older release reproduced the exact stream error; new AppImage displays three variants on `What was your most memorable trip this year?` with no stream error | Passed |
| Packaged history persists corrections | After AppRun search-path repair, real AppImage stores a completed correction with three suggestions at 1283 ms; no history write failure | Passed |
| New AppImage replaces obsolete builds | Fresh artifact atomically installed at `build/releases/hotkey_grammar_corrector-1.0.0-linux-x86_64.AppImage`; only this AppImage remains under `build/`; checksum saved beside it | Passed |
| Package contains correct code and dependencies | Extracted AOT/SQLite library hashes match build; AppRun matches repaired source; SDK/CLI and native dependency checks pass | Passed |
| Credential stays out of saved artifacts | Hidden stdin; no saved key; probe logger emits no context; evidence inspected for credential prefixes | Passed |

Validation commands:

- `dart test test/infrastructure/correction/openai_compatible test/integration/openai_compatible_flow_test.dart --reporter expanded`: 37 passed.
- `dart analyze --fatal-infos`: no issues.
- `flutter build linux --release`: built successfully.
- `bash -n linux/packaging/appimage/AppRun`: passed.
- Isolated Xvfb/Openbox desktop live check with the supplied model, key in memory,
  and exact sentence: actual new AppImage completion and history persistence passed.
- Final-path `--install-desktop` smoke check with disposable XDG directories:
  application/autostart entries point to the replacement in `build/releases/`.
- SHA256 check from `build/releases/`: passed.

## Review and limits

The initial source-only investigation required no production change. The
subsequent real AppImage check exposed a launcher defect, repaired in `0ec708f`
and reviewed inline in REVIEW.md. Existing decoder behavior was inspected
against OpenRouter's primary documentation and regression tests. Another parser
rewrite or speculative compatibility relaxation was unnecessary.

This verifies the requested model and exact input in the delivered AppImage on
an isolated X11 desktop. It does not verify another model, every custom prompt,
or compositor-specific Wayland behavior. Fully quitting and relaunching the
rebuilt resident daemon remains an operational user step.
