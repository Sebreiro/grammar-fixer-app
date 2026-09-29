/// Spawning child VMs, with the two hazards this repo has actually hit taken
/// care of once instead of per suite.
///
/// **The child must be killed, not merely awaited.** Four
/// `flutter_tester run test/support/single_instance_child.dart` processes were
/// found alive after nearly five hours, still holding AD-14 abstract socket
/// addresses — which then made an unrelated `single_instance_lock_test.dart`
/// run fail, because a leaked holder is indistinguishable from a real one.
/// `Process.run` hands back no handle, so a child that wedges can only be
/// waited on forever; [runGuardedChild] starts the process, registers the kill
/// as a tear-down, and bounds the wait.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The Dart VM to spawn child processes with.
///
/// `Platform.resolvedExecutable` is only `dart` under `dart test`. Under
/// `flutter test` — which the verify gate also runs — it is the
/// `flutter_tester` engine binary, and `flutter_tester run <file>` never
/// returns: it is the engine, not the SDK, and it ignores the sub-command.
/// That is precisely how the leaked processes above were spawned, so resolving
/// this wrongly is not a hypothetical.
String get dartExecutable {
  final resolved = Platform.resolvedExecutable;
  if (_basename(resolved).startsWith('dart')) {
    return resolved;
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final sdkDart = '$flutterRoot/bin/cache/dart-sdk/bin/dart';
    if (File(sdkDart).existsSync()) {
      return sdkDart;
    }
  }
  return 'dart';
}

/// Runs [executable] to completion and guarantees the process is dead by the
/// end of the test, however the test ends.
///
/// A child that outlives its test is not a tidiness problem here: these
/// children bind the singleton address, so a survivor makes every later run of
/// the AD-14 suites see a daemon that does not exist. [timeout] bounds the
/// wait so a wedged child fails its own test instead of hanging the suite.
Future<ProcessResult> runGuardedChild(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
  );
  var exited = false;
  // Registered before the first await: a test that fails between here and the
  // wait below must still take the child with it.
  addTearDown(() {
    if (!exited) {
      process.kill(ProcessSignal.sigkill);
    }
  });

  // Drained concurrently with the wait. A child that fills a pipe buffer and
  // blocks on write would otherwise never reach its own exit.
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  try {
    final exitCode = await process.exitCode.timeout(timeout);
    exited = true;
    return ProcessResult(process.pid, exitCode, await out, await err);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    exited = true;
    fail(
      'the child process did not exit within $timeout and was killed: '
      '$executable ${arguments.join(' ')}',
    );
  }
}

String _basename(String path) => path.split(Platform.pathSeparator).last;
