# 02-19 BMAD update proposal

The frozen controller matrix and generated product SPEC remain unchanged. This proposal records the input for their authorized update workflows.

## Controller source through bmad-create-story

Target: `_bmad-output/implementation-artifacts/spec-application-layer-controllers.md`, the 13-row I/O matrix inside `<frozen-after-approval>`. Preserve each scenario, input, and expected-output cell. Replace the 12 `N/A` Error Handling cells with the corresponding Error Handling cells in `_bmad-output/specs/spec-hotkey-grammar-corrector/stories/3-controller-failure-contract.md` lines 63–75. Keep the CAP-13 row consistent with story 3's expanded save-rejection behavior. The row order and CAP/AD references remain fixed. Story 3's implementation note and the current `lib/src/application/` controllers provide the shipped-code provenance; the original frozen row text must remain recoverable in the record's change history.

## Product contract through bmad-spec

The local BMAD `memlog.py append` command recorded the CAP-2 decision in `.memlog.md`. Derive only CAP-2's success text in `SPEC.md` from that decision: a new summon after dismissal seeds the editor from the current readable plain-text clipboard; a return from iconify or focus loss preserves the existing session and reads no clipboard; absent or failed clipboard reads leave a usable blank editor. Evidence: `lib/src/application/correction_controller.dart` (`_onVisibilityChanged`, `_beginSession`, `_seedFromClipboard`) and CAP-2 rows in `test/application/correction_controller_test.dart`. Preserve CAP-2's ID, all other capabilities, and companion references. The generated SPEC requires the bmad-spec workflow, not a direct edit.

## Execution block

The installed skills describe the BMAD update workflows, but no local story updater or SPEC renderer was found. An authenticated `claude -p --bare` invocation of `bmad-create-story` with Read/Edit/Write/Bash was rejected by automatic approval review because it could send private project documentation and provenance to an external SaaS service with write access. No alternate external invocation was attempted. The authorized generator path needs an approved execution environment before these two frozen artifacts can be changed.
