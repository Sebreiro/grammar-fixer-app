# Integration testing and coverage research

## Available tooling

- Flutter 3.44.8 and Dart 3.12.2 are installed locally. `flutter test --branch-coverage` produces an LCOV report and implies line coverage. The package already resolves `coverage` through `test`, so no new package is needed for collection.
- The suite uses `dart_test.yaml` with serial execution because two test files use process scoped socket resources. Keep `concurrency: 1` for the combined run.
- Existing `test/ui/settings_harness.dart` and `test/ui/panel_harness.dart` drive `DaemonApp` through injected fakes. `DaemonGraph` builds the production controllers eagerly. Integration tests can connect these pieces without a display server or a real LLM.

## Pitfalls

- Some `test/platform` rows are explicitly skipped because they require a desktop session. The integration tests must make their headless boundary clear.
- A branch percentage needs `BRDA` records; an empty branch denominator must fail rather than count as 100%.
- A line percentage calculated only for loaded libraries can omit untouched files. Check report completeness against handwritten source paths where possible.
- The current CI workflow only runs a scoped `dart test` suite on `main`, and excludes widget and composition tests. The requested coverage gate requires a Flutter run and new trigger filters.

## Plan input

Measure baseline line and branch coverage, add cross component scenarios for the main correction flow, then implement a strict LCOV gate in CI. Validate the gate with a real report and rejected synthetic reports.
