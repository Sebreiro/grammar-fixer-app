import 'dart:io';

import 'package:test/test.dart';

/// The entries of `pubspec.yaml`'s `flutter: assets:` list, and nothing else.
///
/// Scoped to the `flutter:` block rather than searched across the file, because
/// the failure this exists to catch is a *silent* one: an asset directory that
/// is commented out, or parked under `dependencies:`, satisfies a bare
/// substring check while leaving the files out of `flutter_assets` entirely.
/// Anything that reads its own assets out of the bundle then resolves a path to
/// nothing, with no build error and no runtime complaint until the feature is
/// used.
///
/// Shared by the tray icon rows and the sidecar path rows, which need the same
/// guard for the same reason.
List<String> declaredFlutterAssets() {
  final lines = File('pubspec.yaml').readAsLinesSync();

  final flutterKey = lines.indexWhere((line) => line == 'flutter:');
  expect(flutterKey, isNonNegative, reason: 'pubspec.yaml has no flutter: key');

  var end = lines.indexWhere(
    (line) => line.isNotEmpty && !line.startsWith(RegExp(r'\s|#')),
    flutterKey + 1,
  );
  if (end < 0) {
    end = lines.length;
  }

  final block = lines.sublist(flutterKey + 1, end);
  final assetsKey = block.indexWhere((line) => line.trim() == 'assets:');
  if (assetsKey < 0) {
    return const [];
  }

  final assets = <String>[];
  for (final line in block.sublist(assetsKey + 1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    if (!trimmed.startsWith('- ')) {
      break;
    }
    assets.add(trimmed.substring(2).trim());
  }
  return assets;
}
