# Quick Task 260927-l2c: Integration tests and coverage gate

**Gathered:** 2026-09-27
**Status:** Ready for planning

<domain>
## Task Boundary

Add project integration tests. Require at least 80% line and branch coverage. Run the tests on pushes to `master` and pull requests targeting `master` or `Dev`.
</domain>

<decisions>
## Implementation Decisions

### Coverage scope
- Measure instrumented handwritten Dart application code under `lib/`; omit generated `*.g.dart` code.
- Count covered and total instrumented lines and branches from the same Flutter test run. Fail the CI job if either percentage is below 80%.

### Integration scope
- Exercise real app composition, controller, and widget paths with fake platform and provider ports. A headless Linux runner cannot prove native desktop session behavior.

### CI triggers
- Preserve the existing analysis and sidecar setup checks. Use the exact branch spellings in the request: `master` and `Dev`.

### Agent discretion
- Choose the coverage parser and the test cases after measuring the current suite. Keep CI output concise and actionable.
- A headless coverage report does not include the desktop `main.dart` entrypoint; report that limit with the result.
</decisions>

<specifics>
## Specific Ideas

The existing `flutter test` command supports `--branch-coverage`; test fixtures expose fake hotkey, clipboard, provider, history, and config ports.
</specifics>

<canonical_refs>
## Canonical References

- `_bmad-output/specs/spec-hotkey-grammar-corrector/SPEC.md`
- `AGENTS.md`
- `.github/workflows/ci.yml`
</canonical_refs>
