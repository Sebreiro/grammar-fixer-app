---
quick_id: 261002-cgz
status: complete
verification: human_needed
execution: inline
completed: 2026-10-02
commits:
  - 767de5e
  - 80efc0c
---

# Preserve wording, then casual, then short

Implemented the user-confirmed behavior and labels:

1. Corrected — preserve wording, tone, and meaning; change only grammar and
   unnatural phrasing; return already-correct natural wording unchanged.
2. Casual — relaxed everyday English with the same meaning.
3. Short — concise English preserving meaning and key details.

Both shipped adapters append these requirements to each correction, so existing
presets receive the change without rewriting their saved prompt files. Fresh
defaults share the same instructions. FORMAL/CASUAL/SHORTER tags, enum names,
preset ID, prompt filenames, and history schema remain compatible.

## Commits

- `767de5e` — requested prompt semantics and both adapter regressions.
- `80efc0c` — panel labels, accessible copy controls, and documentation.

## Validation

- `dart analyze --fatal-infos`: no issues.
- Affected pure Dart provider, config, history, domain, and prompt-flow suites:
  288 tests passed.
- Panel and daemon workflow widget suites: 69 tests passed.
- Dart formatting and git whitespace checks passed.
- Full-mode plan check and code review completed inline; no findings.

The first suite run caught a capitalization-sensitive sentinel assertion.
The assertion now checks the required sentinel wording without depending on
capitalization; the complete affected Dart suite passed afterward.

## Remaining Verification

Automatic approval review rejected the live Claude smoke test because it may
use configured credentials and transmit synthetic test text to an external
service. No live model call ran. Real-model compliance with the requested tone
and minimal-edit behavior requires user approval or a manual correction.

## Scope Decisions

The explicit request replaces CAP-4's old formal-first behavior and authorizes
this narrow prompt-quality change. Generated SPEC.md and its companions were
not hand-edited. Concurrent window-stacking edits in this shared checkout were
left outside these commits. ROADMAP.md was not changed.

## Requested AppImage Rebuild

The follow-up rebuild succeeded from the current checkout. The verified local
release was replaced atomically at:

`build/releases/hotkey_grammar_corrector-1.0.0-linux-x86_64.AppImage`

SHA256: `a9fe8301bbb7b54118232fff84cfa235e9184a6bfd93376fbc51b6dab27cb1e2`.
Size: 111901176 bytes.

The package's native runner and AOT text/rodata sections match the fresh Linux
release bundle. Compiled AOT contains the new Corrected label and requested
variant instructions. Native dependencies resolve; bundled Claude SDK/CLI and
desktop integration checks passed. The actual AppImage passed isolated
Xvfb/openbox startup, focus, keep-above, taskbar, focus-loss hiding, and repeated
hotkey toggle checks using temporary config. No provider call was made.

Fully quit the existing tray daemon before launching the replacement.
