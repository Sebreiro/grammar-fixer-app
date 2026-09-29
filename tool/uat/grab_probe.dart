// Temporary UAT harness (phase 01, /gsd-verify-work). Drives the real
// X11KeyGrabRegistrar against a live X server and counts delivered presses.
// Usage: dart run tool/uat/grab_probe.dart <LABEL> [<LABEL> ...]
import 'dart:async';
import 'dart:io';

import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_grab.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/x11_key_grab_registrar.dart';

Future<void> main(List<String> args) async {
  final labels = args.isEmpty ? <String>['G'] : args;
  final registrar = X11KeyGrabRegistrar();
  var presses = 0;
  final sub = registrar.presses.listen((_) {
    presses += 1;
    stdout.writeln('PRESS #$presses');
  });

  for (final label in labels) {
    final usage = HotkeyKeyCatalogue.usbHidUsageFor(label);
    if (usage == null) {
      stdout.writeln('RESULT $label catalogue=UNRESOLVED');
      continue;
    }
    presses = 0;
    try {
      await registrar.grab(
        HotkeyGrab(
          modifiers: <HotkeyModifier>{HotkeyModifier.control, HotkeyModifier.shift},
          usbHidUsage: usage,
        ),
      );
    } on Object catch (error) {
      stdout.writeln('RESULT $label grab=REFUSED(${error.runtimeType}) detail=$error');
      continue;
    }
    stdout.writeln('GRABBED $label');
    // Synthesise three presses through XTEST and count what the grab delivers.
    for (var i = 0; i < 3; i += 1) {
      final r = await Process.run('xdotool', <String>[
        'key', '--clearmodifiers', 'ctrl+shift+${_xdotoolName(label)}',
      ], environment: <String, String>{'DISPLAY': Platform.environment['DISPLAY'] ?? ':99'});
      if (r.exitCode != 0) {
        stdout.writeln('  xdotool failed: ${r.stderr}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    stdout.writeln('RESULT $label sent=3 delivered=$presses');
    await registrar.release();
  }

  await sub.cancel();
  await registrar.dispose();
  exit(0);
}

String _xdotoolName(String label) => switch (label) {
  'Space' => 'space',
  'Tab' => 'Tab',
  'Enter' => 'Return',
  _ => label,
};
