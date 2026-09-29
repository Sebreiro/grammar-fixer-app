import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_grab.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_registrar.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/x11_key_grab_registrar.dart';
import 'package:test/test.dart';

/// The one claim about the shipped registrar that is observable with **no X
/// server at all**: a bind that could not open a display must still tear down.
///
/// Everything else about this seam needs a live X server and is owed to a real
/// session (`test/platform/x11_hotkey_live_test.dart` records that). This row
/// exists because the opposite of that argument was assumed for a whole phase:
/// "the seam cannot be tested without a display" was read as "the seam cannot
/// be tested", and the no-display path — the very one AD-12 calls a visible
/// `HotkeyUnavailable` rather than a crash — went unexercised while
/// `XCloseDisplay(nullptr)` killed the process on every exit path
/// (`main.dart`'s lifecycle teardown *and* its pre-lifecycle abort).
///
/// A native null dereference is a `SIGSEGV`, not a Dart exception: the worker's
/// `_guard` cannot catch it and no `expect` can observe it. What this row
/// asserts is therefore the only thing that can be asserted — that the process
/// is still alive to answer at all. A regression does not fail this test, it
/// takes the whole suite down with exit 134, which is louder.
///
/// Pure Dart: `dart:ffi` and `dart:isolate` are binding-free, so this stays in
/// the `dart test` set with the rest of the seam's decision-making rows
/// (AGENTS.md §7).
void main() {
  test('AD-12, HOTKEY-02: a grab that could not open an X display refuses as '
      'noBackend, and the teardown that follows it does not fault', () async {
    // The condition under test is "no reachable X display", and `DISPLAY` is
    // how Xlib decides: `XOpenDisplay(NULL)` reads it through the C library's
    // own `getenv`, so `Platform.environment` cannot express this and neither
    // can a fake. Removed for the length of this row and put back afterwards,
    // because the alternative — trusting whatever the host exports — makes the
    // row assert nothing on a developer machine and *hold a real global grab*
    // on one where the display opens.
    final restore = _unsetDisplay();
    addTearDown(restore);

    final registrar = X11KeyGrabRegistrar();
    Object? thrown;
    try {
      await registrar.grab(
        HotkeyGrab(
          modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
          usbHidUsage: 0x0007000a,
        ),
      );
    } on Object catch (error) {
      thrown = error;
    }

    expect(
      thrown,
      isA<HotkeyRegistrarRefusal>().having(
        (refusal) => refusal.code,
        'code',
        HotkeyRefusalCode.noBackend,
      ),
      reason:
          'no display could be opened, so no combination can ever work here '
          '— which is what noBackend means and what keyRefused would deny',
    );

    // The whole point of the row. Before the guard on `closeDisplay` this
    // call reached `XCloseDisplay(nullptr)` in the worker isolate and the
    // process died at `XCloseDisplay+0xb` with exit 134, so a daemon on such
    // a host crashed instead of degrading.
    await registrar.dispose();

    // Reached only if the worker survived its own teardown.
    expect(registrar.presses, isNotNull);
  });
}

/// Removes `DISPLAY` from the process environment as the C library sees it,
/// returning the call that puts it back.
///
/// `setenv`/`unsetenv` are looked up on the process rather than on a soname:
/// they are libc's and libc is already mapped into every Dart process, so there
/// is nothing to open. The value is captured first so the restore is exact —
/// suites share one process here (`dart_test.yaml`, `concurrency: 1`), and a
/// row that quietly stripped `DISPLAY` for everything after it would be a worse
/// bug than the one it pins.
void Function() _unsetDisplay() {
  final libc = DynamicLibrary.process();
  final getenv = libc
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('getenv');
  final setenv = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)
      >('setenv');
  final unsetenv = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('unsetenv');

  final name = 'DISPLAY'.toNativeUtf8();
  try {
    final existing = getenv(name);
    final previous = existing == nullptr ? null : existing.toDartString();
    unsetenv(name);
    return () {
      final restoreName = 'DISPLAY'.toNativeUtf8();
      try {
        if (previous == null) {
          unsetenv(restoreName);
          return;
        }
        final value = previous.toNativeUtf8();
        try {
          setenv(restoreName, value, 1);
        } finally {
          calloc.free(value);
        }
      } finally {
        calloc.free(restoreName);
      }
    };
  } finally {
    calloc.free(name);
  }
}
