---
status: complete
quick_id: 260927-l2c
date: 2026-09-27
commits:
  - 4e7c7e2
  - 6425619
  - b39dd57
  - 9759922
---

# Integration tests and coverage gate

Added a daemon widget integration journey through hotkey activation, clipboard seeding, edited submission, streamed suggestions, history persistence, and explicit copy. Added loopback HTTP integration cases for the OpenAI-compatible provider's structured streaming, stateless repeated calls, status errors, malformed responses, validation, and deadline. Added LCOV gate tests.

CI runs the complete headless Flutter suite with line and branch coverage on pushes to `master` and pull requests targeting `master` or `Dev`. The initial gate was 80%; the follow-up below raised it to 90%.

## Initial verification

- `dart analyze --fatal-infos`: clean.
- `flutter test --coverage --branch-coverage --exclude-tags=live test`: 1,157 passed, 9 existing desktop-session skips.
- `dart run tool/check_coverage.dart coverage/lcov.info`: 3,651/4,160 lines (87.76%) and 1,504/1,875 branches (80.21%).
- A synthetic low-coverage report made the CLI exit 1.
- The workflow YAML parsed with the requested branch filters and coverage commands.

## Limits

Coverage is for source files instrumented by Flutter's headless test run; the desktop `lib/main.dart` entrypoint is absent from the LCOV report. Generated `.g.dart` code is excluded. Real desktop-session checks remain skipped in this environment. The GitHub Actions workflow has not yet run on GitHub.

## Follow-up: 90% coverage gate

Raised the line and branch gate to 90%. Added Xvfb-backed X11 grab and focus tests, private D-Bus Secret Service and portal read-back tests, and config, provider, controller, and widget integration cases. CI installs `xvfb` and `xdotool` before the suite; the `master` push and `master`/`Dev` PR triggers remain in place.

- `dart analyze --fatal-infos`: clean.
- Full headless Flutter suite: 1,214 passed, 9 existing desktop-session skips.
- LCOV: 3,985/4,166 lines (95.66%) and 1,692/1,878 branches (90.10%).
- The updated threshold unit test passes. GitHub runner execution remains unobserved.
