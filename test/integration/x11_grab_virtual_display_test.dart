import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_grab.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_registrar.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/x11_key_grab_registrar.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/panel/x11_keyboard_focus_witness.dart';
import 'package:test/test.dart';

void main() {
  late _VirtualDisplay display;

  setUpAll(() async => display = await _VirtualDisplay.start());
  tearDownAll(() async => display.dispose());

  test(
    'CAP-1: an X11 grab receives a real key press and releases it once',
    () async {
      final owner = X11KeyGrabRegistrar();
      final challenger = X11KeyGrabRegistrar();
      addTearDown(owner.dispose);
      addTearDown(challenger.dispose);

      await owner.grab(_grab(0x0007000a));
      await expectLater(
        challenger.grab(_grab(0x0007000a)),
        throwsA(_refusal(HotkeyRefusalCode.keyRefused)),
      );

      final press = owner.presses.first.timeout(const Duration(seconds: 3));
      await display.press('g');
      await press;

      await owner.grab(_grab(0x0007000a));
      await owner.release();
      await challenger.grab(_grab(0x0007000a));
      final newPress = challenger.presses.first.timeout(
        const Duration(seconds: 3),
      );
      await display.press('g');
      await newPress;
    },
  );

  test('AD-10: a refused X11 rebind keeps the old shortcut held', () async {
    final owner = X11KeyGrabRegistrar();
    final challenger = X11KeyGrabRegistrar();
    addTearDown(owner.dispose);
    addTearDown(challenger.dispose);

    await owner.grab(_grab(0x0007000a));
    await challenger.grab(_grab(0x0007000b));
    await expectLater(
      owner.grab(_grab(0x0007000b)),
      throwsA(_refusal(HotkeyRefusalCode.keyRefused)),
    );

    final press = owner.presses.first.timeout(const Duration(seconds: 3));
    await display.press('g');
    await press;

    await challenger.release();
    await owner.grab(_grab(0x0007000b));
    await challenger.grab(_grab(0x0007000a));
    final reboundPress = owner.presses.first.timeout(
      const Duration(seconds: 3),
    );
    await display.press('h');
    await reboundPress;
  });

  test('CAP-1: modifier variants bind and fire through the X server', () async {
    for (final modifiers in [
      <HotkeyModifier>{HotkeyModifier.alt},
      <HotkeyModifier>{HotkeyModifier.meta},
    ]) {
      final registrar = X11KeyGrabRegistrar();
      final grab = HotkeyGrab(modifiers: modifiers, usbHidUsage: 0x0007000a);
      await registrar.grab(grab);
      final press = registrar.presses.first.timeout(const Duration(seconds: 3));
      final chord = modifiers.single == HotkeyModifier.alt
          ? 'alt+g'
          : 'super+g';
      final result = await Process.run(
        'xdotool',
        ['key', '--clearmodifiers', chord],
        environment: {'DISPLAY': display.display},
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      await press;
      await registrar.dispose();
    }
  });

  test('CAP-13: an unknown key is refused before opening a worker', () async {
    final registrar = X11KeyGrabRegistrar();
    addTearDown(registrar.dispose);

    await expectLater(
      registrar.grab(_grab(0xffffffff)),
      throwsA(_refusal(HotkeyRefusalCode.keyRefused)),
    );
    await registrar.release();
    await registrar.dispose();
    await registrar.dispose();
    await expectLater(registrar.release(), throwsStateError);
    await expectLater(registrar.grab(_grab(0x0007000a)), throwsStateError);
  });

  test(
    'CAP-14: the X11 witness distinguishes steady focus from focus loss',
    () async {
      final connection = _FocusConnection.open();
      final witness = X11KeyboardFocusWitness();
      addTearDown(connection.dispose);
      addTearDown(witness.dispose);

      expect(witness.focusUnmoved, isFalse);
      connection.focusRoot();
      witness.recordFocusGained();
      expect(witness.focusUnmoved, isTrue);

      connection.clearFocus();
      expect(witness.focusUnmoved, isFalse);
      witness.recordFocusGained();
      expect(witness.focusUnmoved, isFalse);

      await witness.dispose();
      expect(witness.focusUnmoved, isFalse);
    },
  );

  test('CAP-14: an unavailable X display leaves no comparable focus', () async {
    final restore = _setDisplay(':not-a-running-display');
    addTearDown(restore);
    final witness = X11KeyboardFocusWitness();
    addTearDown(witness.dispose);

    witness.recordFocusGained();
    expect(witness.focusUnmoved, isFalse);
    witness.recordFocusGained();
    expect(witness.focusUnmoved, isFalse);
    await witness.dispose();
    await witness.dispose();
  });
}

HotkeyGrab _grab(int usage) => HotkeyGrab(
  modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
  usbHidUsage: usage,
);

Matcher _refusal(HotkeyRefusalCode code) => isA<HotkeyRegistrarRefusal>()
    .having((refusal) => refusal.code, 'code', code);

final class _VirtualDisplay {
  _VirtualDisplay(this._process, this.display, this._restoreDisplay);

  final Process _process;
  final String display;
  final void Function() _restoreDisplay;

  static Future<_VirtualDisplay> start() async {
    // Xvfb writes its allocated display number only when the X server is ready.
    final process = await Process.start('Xvfb', [
      '-displayfd',
      '1',
      '-screen',
      '0',
      '800x600x24',
      '-nolisten',
      'tcp',
    ]);
    process.stderr.listen((_) {});
    try {
      final number = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      final display = ':$number';
      return _VirtualDisplay(process, display, _setDisplay(display));
    } on Object {
      process.kill();
      rethrow;
    }
  }

  Future<void> press(String key) async {
    final result = await Process.run(
      'xdotool',
      ['key', '--clearmodifiers', 'ctrl+shift+$key'],
      environment: {'DISPLAY': display},
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
  }

  Future<void> dispose() async {
    _restoreDisplay();
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 5));
  }
}

void Function() _setDisplay(String display) {
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
  final value = display.toNativeUtf8();
  try {
    final existing = getenv(name);
    final previous = existing == nullptr ? null : existing.toDartString();
    setenv(name, value, 1);
    return () {
      final restore = previous?.toNativeUtf8();
      try {
        if (restore == null) {
          unsetenv(name);
        } else {
          setenv(name, restore, 1);
        }
      } finally {
        if (restore != null) calloc.free(restore);
        calloc.free(name);
      }
    };
  } finally {
    calloc.free(value);
  }
}

final class _FocusConnection {
  _FocusConnection(
    this._display,
    this._root,
    this._setFocus,
    this._sync,
    this._close,
  );

  final Pointer<Void> _display;
  final int _root;
  final int Function(Pointer<Void>, int, int, int) _setFocus;
  final int Function(Pointer<Void>, int) _sync;
  final int Function(Pointer<Void>) _close;

  static _FocusConnection open() {
    final library = DynamicLibrary.open('libX11.so.6');
    final openDisplay = library
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>),
          Pointer<Void> Function(Pointer<Utf8>)
        >('XOpenDisplay');
    final rootWindow = library
        .lookupFunction<
          UnsignedLong Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('XDefaultRootWindow');
    final setFocus = library
        .lookupFunction<
          Int32 Function(Pointer<Void>, UnsignedLong, Int32, UnsignedLong),
          int Function(Pointer<Void>, int, int, int)
        >('XSetInputFocus');
    final sync = library
        .lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)
        >('XSync');
    final close = library
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('XCloseDisplay');
    final display = openDisplay(nullptr);
    if (display == nullptr) {
      throw StateError('Xvfb did not accept the focus client');
    }
    return _FocusConnection(
      display,
      rootWindow(display),
      setFocus,
      sync,
      close,
    );
  }

  void focusRoot() => _focus(_root);
  void clearFocus() => _focus(0);

  void _focus(int window) {
    _setFocus(_display, window, 1, 0);
    _sync(_display, 0);
  }

  void dispose() => _close(_display);
}
