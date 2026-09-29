import 'dart:io';

import 'package:hotkey_grammar_corrector/src/infrastructure/config/app_paths.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/system/single_instance_lock.dart';

/// Child entry point for the AD-14 tests that need a second Dart VM.
///
/// A second lock in the test's own isolate cannot stand in for either case
/// this serves: the singleton guards a real second *launch* of the daemon,
/// and a process-wide descriptor limit can only be lowered for a process the
/// test spawns. The runtime directory comes from the environment the parent
/// hands over, so both processes derive the same abstract address without
/// sharing any Dart state.
///
/// Pass [_exhaustDescriptorsMode] to burn every remaining file descriptor
/// before acquiring — under a lowered `ulimit -n` that is what makes the bind
/// *and* the fallback connect fail together.
///
/// Output contract: the status name on stdout, the warning (if any) on
/// stderr.
Future<void> main(List<String> arguments) async {
  final heldDescriptors = arguments.contains(_exhaustDescriptorsMode)
      ? _burnDescriptors()
      : const <RandomAccessFile>[];

  final lock = SingleInstanceLock(
    paths: AppPaths.fromEnvironment(Platform.environment),
  );

  final acquisition = await lock.acquire();
  final warning = acquisition.warning;
  if (warning != null) {
    stderr.writeln(warning);
  }
  stdout.writeln(acquisition.status.name);

  await lock.dispose();
  _release(heldDescriptors);
  exit(0);
}

const String _exhaustDescriptorsMode = 'exhaust-descriptors';

/// Opens descriptors until the kernel refuses, so the next socket call cannot
/// get one either. Bounded well above any sane `ulimit -n` the caller would
/// set, so a machine with no limit at all fails the test rather than hanging.
List<RandomAccessFile> _burnDescriptors() {
  final held = <RandomAccessFile>[];
  for (var attempt = 0; attempt < 4096; attempt += 1) {
    try {
      held.add(File('/dev/null').openSync());
    } on FileSystemException {
      return held;
    }
  }
  return held;
}

void _release(List<RandomAccessFile> descriptors) {
  for (final descriptor in descriptors) {
    try {
      descriptor.closeSync();
    } on FileSystemException {
      // Already reclaimed while the VM was shutting down; nothing to undo.
    }
  }
}
