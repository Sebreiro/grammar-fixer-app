import 'dart:io';

import 'package:test/test.dart';

/// Enforces AD-1 for the domain ring: `lib/src/domain/**` references only
/// `dart:` libraries. Relative URIs are allowed only while they stay inside
/// `lib/src/domain/`. Scanned directives: `import`, `export`, `part`, and
/// `part of` — including every alternative URI of a conditional import
/// (`if (dart.library.x) '...'`). Commented-out directives are ignored.
///
/// Three rings are checked here, one import rule each: `domain` reaches nothing
/// but `dart:`, `application` never reaches infrastructure or Flutter widgets,
/// and `ui` never reaches infrastructure — no adapter, no plugin, no vendor SDK.
///
/// The ui ring gets a **fourth**, symbol-level rule as well, and the reason is
/// worth stating: its import rule cannot see the thing it most wants to forbid.
/// `package:flutter/services.dart` is a legitimate ui import (the panel needs
/// `LogicalKeyboardKey`), and it is also where `MethodChannel`,
/// `SystemChannels` and `Clipboard` live — so a widget can reach the platform
/// and the system clipboard directly with every import rule green. AGENTS.md §3
/// forbids exactly that ("no clipboard access inside a `build()` method or a
/// widget class"), as do AD-4 and AD-8 for a widget that reaches the visibility
/// seam, and neither is an import the scans can name.
///
/// The Dart 3.12 analyzer offers no analysis_options-native way to ban
/// imports by directory, so this test is the mechanical enforcement that
/// AD-1 requires; it runs under `dart test` (merge gate per AGENTS.md §6).
/// Each rule's checker carries its own positive and negative self-tests: a
/// scan that silently stopped matching anything would otherwise pass forever.
void main() {
  test('AD-1: lib/src/domain/** imports only dart: libraries', () {
    final domainDirectory = Directory('lib/src/domain');
    expect(
      domainDirectory.existsSync(),
      isTrue,
      reason: 'lib/src/domain/ must exist for AD-1 to be enforceable',
    );

    final violations = <String>[];
    final domainFiles = domainDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in domainFiles) {
      for (final uri in _violations(file.readAsStringSync(), file.path)) {
        violations.add('${file.path}: $uri');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'AD-1 violated — domain files may reference only dart: libraries '
          'or relative paths inside lib/src/domain/:\n${violations.join('\n')}',
    );
  });

  test('AD-1: lib/src/application/** never imports infrastructure', () {
    final applicationDirectory = Directory('lib/src/application');
    expect(
      applicationDirectory.existsSync(),
      isTrue,
      reason: 'lib/src/application/ must exist for AD-1 to be enforceable',
    );

    final violations = <String>[];
    final applicationFiles = applicationDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in applicationFiles) {
      for (final uri in _applicationViolations(
        file.readAsStringSync(),
        file.path,
      )) {
        violations.add('${file.path}: $uri');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'AD-1 violated — application files may reference only dart: '
          'libraries, Riverpod (AD-17), and paths inside lib/src/application/ '
          'or lib/src/domain/:\n${violations.join('\n')}',
    );
  });

  test('AD-1: lib/src/ui/** never imports infrastructure', () {
    final uiDirectory = Directory('lib/src/ui');
    expect(
      uiDirectory.existsSync(),
      isTrue,
      reason: 'lib/src/ui/ must exist for AD-1 to be enforceable',
    );

    final violations = <String>[];
    final uiFiles = uiDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in uiFiles) {
      for (final uri in _uiViolations(file.readAsStringSync(), file.path)) {
        violations.add('${file.path}: $uri');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'AD-1 violated — ui files may reference only dart: libraries, '
          'Flutter, Riverpod (AD-17), and paths inside lib/src/ui/, '
          'lib/src/application/ or lib/src/domain/:\n${violations.join('\n')}',
    );
  });

  test('AGENTS.md §3, AD-4, AD-8: no file under lib/src/ui/ names a platform '
      'channel, the clipboard service or the visibility seam', () {
    final uiDirectory = Directory('lib/src/ui');
    final violations = <String>[];
    final uiFiles = uiDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in uiFiles) {
      for (final symbol in _bannedUiSymbols(file.readAsStringSync())) {
        violations.add('${file.path}: $symbol');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'a widget reaches the platform and the clipboard through the '
          'controller and its ports, never directly — and it never shows or '
          'hides the window (AD-4, AD-8):\n${violations.join('\n')}',
    );
  });

  test('AD-1: every port seam is either banned in the ui ring or named as one '
      'a widget may read', () {
    final source = File(
      'lib/src/application/composition/port_providers.dart',
    ).readAsStringSync();
    final declared = _declaredTopLevelFinals(source);

    expect(
      declared,
      hasLength(greaterThanOrEqualTo(_knownPortSeamCount)),
      reason:
          'the seams must be findable for this gate to mean anything, and '
          'discovery that silently narrows is how a seam goes unclassified: '
          'found ${declared.length}, expected at least $_knownPortSeamCount '
          '(${declared.join(', ')})',
    );

    final unclassified = declared
        .where(
          (provider) =>
              !_uiBannedSymbols.contains(provider) &&
              !_uiSanctionedProviders.contains(provider),
        )
        .toList();

    expect(
      unclassified,
      isEmpty,
      reason:
          'a denylist that has to be remembered is not a gate: add each seam '
          'to _uiBannedSymbols, or to _uiSanctionedProviders with the reason a '
          'widget may read it:\n${unclassified.join('\n')}',
    );
  });

  group('AD-1 ui symbol checker self-tests', () {
    test('the symbol checker flags every symbol it bans', () {
      for (final symbol in _uiBannedSymbols) {
        expect(
          _bannedUiSymbols('final x = $symbol;'),
          equals([symbol]),
          reason: '$symbol must be reported, or banning it means nothing',
        );
      }
    });

    test('the symbol checker flags a clipboard write hidden in a widget', () {
      expect(
        _bannedUiSymbols(
          'void _copy(String text) {\n'
          '  Clipboard.setData(ClipboardData(text: text));\n'
          '}',
        ),
        equals(['Clipboard.']),
      );
    });

    test('the symbol checker flags a raw channel call that no import rule can '
        'see', () {
      expect(
        _bannedUiSymbols(
          "SystemChannels.platform.invokeMethod<void>('Clipboard.setData');",
        ),
        equals(['SystemChannels', 'Clipboard.']),
      );
    });

    test('the symbol checker flags the channel family, not just the three '
        'classes someone thought of', () {
      // Each of these reached the system clipboard from a widget with every
      // row of this gate green, one door down from the one before it.
      expect(
        _bannedUiSymbols(
          "const BasicMessageChannel<Object?>('flutter/platform', "
          'JSONMessageCodec()).send(payload);',
        ),
        contains('MessageChannel'),
      );
      expect(
        _bannedUiSymbols(
          "ServicesBinding.instance.defaultBinaryMessenger.send('x', null);",
        ),
        containsAll(<String>['BinaryMessenger', 'ServicesBinding']),
      );
      expect(
        _bannedUiSymbols(
          "WidgetsBinding.instance.defaultBinaryMessenger.send('x', null);",
        ),
        contains('BinaryMessenger'),
      );
    });

    test('the symbol checker sees a call sharing a line with a URL', () {
      // The comment stripper used to delete everything after `//`, wherever it
      // appeared — including inside a string literal — so this call was
      // invisible while the identical call on its own line was not.
      expect(
        _bannedUiSymbols(
          "final u = 'https://example.invalid';"
          ' Clipboard.setData(ClipboardData(text: u));',
        ),
        contains('Clipboard.'),
      );
    });

    test('the symbol checker allows the seams a widget legitimately reads', () {
      expect(
        _bannedUiSymbols(
          'final controller = ref.read(correctionControllerProvider);\n'
          'final logger = ref.read(loggerProvider);\n'
          "const hint = Text('copied to the clipboard');\n"
          "// MethodChannel('window_manager') — named in prose, not called\n",
        ),
        isEmpty,
      );
    });
  });

  group('AD-1 port-seam discovery self-tests', () {
    test('a seam is discovered however it is declared', () {
      expect(
        _declaredTopLevelFinals(
          'final loggerProvider = Provider<Logger>((ref) => throw x);\n'
          'final Provider<Clock> typedSeamProvider = Provider<Clock>(y);\n'
          'final unsuffixedSeam = Provider<Clock>(z);\n',
        ),
        equals(<String>[
          'loggerProvider',
          'typedSeamProvider',
          'unsuffixedSeam',
        ]),
        reason:
            'a seam discovered by nothing is classified by nothing, and the '
            'classification row passes with an empty unclassified list',
      );
    });

    test('a commented-out seam is not discovered', () {
      expect(
        _declaredTopLevelFinals('// final ghostProvider = Provider<Clock>(x);'),
        isEmpty,
      );
    });
  });

  group('AD-1 ui checker self-tests', () {
    const uiFile = 'lib/src/ui/panel/example_panel.dart';

    test('AD-1 checker flags an infrastructure import', () {
      expect(
        _uiViolations(
          "import '../../infrastructure/clipboard/system_clipboard.dart';",
          uiFile,
        ),
        equals(['../../infrastructure/clipboard/system_clipboard.dart']),
      );
    });

    test('AD-1 checker flags a plugin import', () {
      expect(
        _uiViolations(
          "import 'package:window_manager/window_manager.dart';",
          uiFile,
        ),
        equals(['package:window_manager/window_manager.dart']),
      );
    });

    test('AD-1 checker flags the dart: libraries that reach the machine', () {
      // The hole the ui rule shipped with: a widget that shells out to a
      // clipboard tool bypasses the port, the guard and the notice, and no
      // import rule and no banned symbol could see it.
      for (final library in _uiForbiddenDartLibraries) {
        expect(
          _uiViolations("import '$library';", uiFile),
          equals([library]),
          reason: '$library must be reported for the ui ring',
        );
      }
    });

    test('AD-1 checker allows Flutter, Riverpod, application, domain and '
        'in-ring URIs', () {
      expect(
        _uiViolations(
          "import 'dart:async';\n"
          "import 'package:flutter/material.dart';\n"
          "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
          "import '../../application/correction_state.dart';\n"
          "import '../../domain/correction/suggestion_register.dart';\n"
          "import 'suggestion_card.dart';",
          uiFile,
        ),
        isEmpty,
      );
    });

    test('AD-1 checker flags a self-package import of infrastructure', () {
      expect(
        _uiViolations(
          'import '
          "'package:hotkey_grammar_corrector/src/infrastructure/panel/"
          "window_manager_panel_visibility.dart';",
          uiFile,
        ),
        equals([
          'package:hotkey_grammar_corrector/src/infrastructure/panel/'
              'window_manager_panel_visibility.dart',
        ]),
      );
    });
  });

  group('AD-1 application checker self-tests', () {
    const applicationFile = 'lib/src/application/example_controller.dart';

    test('AD-1 checker flags an infrastructure import', () {
      expect(
        _applicationViolations(
          "import '../infrastructure/config/json_config_store.dart';",
          applicationFile,
        ),
        equals(['../infrastructure/config/json_config_store.dart']),
      );
    });

    test('AD-1 checker flags a Flutter widget import', () {
      expect(
        _applicationViolations(
          "import 'package:flutter/widgets.dart';",
          applicationFile,
        ),
        equals(['package:flutter/widgets.dart']),
      );
    });

    test('AD-1 checker allows domain, Riverpod, and in-ring URIs', () {
      expect(
        _applicationViolations(
          "import 'dart:async';\n"
          "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
          "import 'package:hotkey_grammar_corrector/src/domain/clock.dart';\n"
          "import '../domain/panel/panel_visibility.dart';\n"
          "import 'correction_state.dart';",
          applicationFile,
        ),
        isEmpty,
      );
    });

    test('AD-1 checker flags a self-package import of infrastructure', () {
      expect(
        _applicationViolations(
          'import '
          "'package:hotkey_grammar_corrector/src/infrastructure/x.dart';",
          applicationFile,
        ),
        equals(['package:hotkey_grammar_corrector/src/infrastructure/x.dart']),
      );
    });
  });

  group('AD-1 checker self-tests', () {
    const domainFile = 'lib/src/domain/correction/example.dart';

    test('AD-1 checker flags a plain package: import', () {
      expect(
        _violations("import 'package:flutter/widgets.dart';", domainFile),
        equals(['package:flutter/widgets.dart']),
      );
    });

    test('AD-1 checker flags the alternative URI of a conditional import', () {
      expect(
        _violations(
          "import 'suggestion.dart'\n"
          "    if (dart.library.io) 'package:flutter/widgets.dart';",
          domainFile,
        ),
        equals(['package:flutter/widgets.dart']),
      );
    });

    test('AD-1 checker flags an export escaping domain/', () {
      expect(
        _violations(
          "export '../../application/correction_controller.dart';",
          domainFile,
        ),
        equals(['../../application/correction_controller.dart']),
      );
    });

    test('AD-1 checker flags a part directive outside domain/', () {
      expect(
        _violations("part '../../generated/example.g.dart';", domainFile),
        equals(['../../generated/example.g.dart']),
      );
      expect(
        _violations("part of '../../application/library.dart';", domainFile),
        equals(['../../application/library.dart']),
      );
    });

    test('AD-1 checker ignores commented-out directives', () {
      expect(
        _violations(
          "// import 'package:flutter/widgets.dart';\n"
          "/* export 'package:drift/drift.dart'; */\n"
          "import 'suggestion.dart';",
          domainFile,
        ),
        isEmpty,
      );
    });

    test('AD-1 checker allows dart: and in-domain relative URIs', () {
      expect(
        _violations(
          "import 'dart:async';\n"
          "import 'suggestion.dart';\n"
          "export '../hotkey/hotkey_binding.dart';",
          domainFile,
        ),
        isEmpty,
      );
    });
  });
}

/// Every referenced URI in [source] that AD-1 forbids the application ring,
/// in source order, as if the source lived at [filePath].
List<String> _applicationViolations(String source, String filePath) {
  return _directiveUris(
    source,
  ).where((uri) => _violatesApplicationRule(uri, filePath)).toList();
}

/// Symbols the ui ring may not name, in the order [_uiBannedSymbols] lists
/// them. Comments are stripped first, so naming one in prose is fine and
/// calling it is not.
///
/// A plain substring scan, deliberately: it is the same mechanical shape as the
/// import scans, and every symbol here is distinctive enough that a match is a
/// call. String literals are *not* stripped — a user-facing sentence containing
/// one of these would trip the rule, and that is a conversation worth having
/// rather than a hole worth leaving.
List<String> _bannedUiSymbols(String source) {
  final stripped = _stripComments(source);
  return [
    for (final symbol in _uiBannedSymbols)
      if (stripped.contains(symbol)) symbol,
  ];
}

/// What a widget must not reach for, and why each one is here.
const List<String> _uiBannedSymbols = [
  // The platform, directly. `package:flutter/services.dart` is a legitimate ui
  // import for `LogicalKeyboardKey`, and it carries these along with it.
  'MethodChannel',
  'EventChannel',
  'SystemChannels',
  // The same platform, two doors down. Banning the three above left the channel
  // family's other members open: `BasicMessageChannel('flutter/platform', …)`
  // addresses exactly the channel `Clipboard.setData` uses, and
  // `defaultBinaryMessenger.send('flutter/platform', …)` skips the channel
  // classes altogether. Both reached the system clipboard from a widget with
  // every row of this gate green. Substrings, so `BasicMessageChannel`,
  // `OptionalMethodChannel` and `defaultBinaryMessenger` are all covered.
  'MessageChannel',
  'BinaryMessenger',
  // The binding that hands out the messenger. `WidgetsBinding` stays allowed —
  // `addPostFrameCallback` is ordinary widget work — and the messenger it
  // inherits is caught by the entry above.
  'ServicesBinding',
  // Flutter's own clipboard service. AGENTS.md §3: no clipboard access inside a
  // widget class — CAP-11's write goes through the controller and the port.
  'Clipboard.',
  // The clipboard seam is the controller's, for the same reason.
  'clipboardProvider',
  // AD-4 and AD-8: no widget path shows, hides or cancels. The toggle owns
  // visibility and the window moves underneath a tree that is always built.
  'panelVisibilityProvider',
  // Every other port seam, for the reason AD-1 exists: a widget that reads one
  // has reached past the controller that owns the surface's state, and the
  // import graph cannot see it because the seam lives in the application ring
  // the ui ring is allowed to import. Enumerated here and pinned by
  // `_uiSanctionedProviders`'s row below, so a seam added by a later story
  // fails this gate until someone decides which side of it the seam is on.
  'clockProvider',
  'configStoreProvider',
  'globalHotkeyProvider',
  'trayProvider',
  'correctionRepositoryProvider',
  'activeCorrectionProviderProvider',
  'activePresetProvider',
  // Not a port but a seam all the same, and banned for exactly the reason the
  // ports are: the registrable key vocabulary is what the settings surface
  // validates a captured combination against, and DW-71 ratified it as
  // *supplied by* `SettingsController`. A widget that read the seam itself
  // would have reached past the controller that owns the surface's state, and
  // no import rule can see it — the seam lives in the application ring, which
  // the ui ring may import.
  'registrableKeysProvider',
];

/// Every top-level `final` declared in [source], whatever its name and whether
/// or not it carries an explicit type.
///
/// `port_providers.dart`'s own library doc says it holds "one typed seam per
/// port, and nothing else", so every top-level `final` in it *is* a seam and the
/// classification row can insist on all of them. The previous pattern —
/// `^final (\w+Provider) =` — encoded two accidents of formatting instead: a
/// seam declared `final Provider<Clock> sneakyClockProvider = …`, or named
/// `sneakySeam`, was discovered by nothing, classified by nothing, and reachable
/// from a widget with the row green. `[^=\n]*` cannot cross a line or an `=`, so
/// the captured identifier is always the one being declared.
List<String> _declaredTopLevelFinals(String source) {
  return RegExp(
    r'^final\s+(?:[^=\n]*\s)?(\w+)\s*=',
    multiLine: true,
  ).allMatches(_stripComments(source)).map((match) => match.group(1)!).toList();
}

/// How many seams `port_providers.dart` holds today.
///
/// Pinned so that a discovery pattern which stops seeing one fails loudly
/// instead of reporting an empty `unclassified` list. A story that adds a seam
/// raises this and classifies it; a story that removes one lowers it.
///
/// Eleven since HOTKEY-04: `registrableKeysProvider` carries the key
/// vocabulary the settings surface validates against, declared over a domain
/// type because a `Provider<HotkeyKeyCatalogue>` would fail the application
/// ring's own import rule on its declaration alone.
const int _knownPortSeamCount = 11;

/// The port seams a widget may read, and why each one is here.
///
/// One entry, deliberately: `CorrectionPanel` reports a state stream that errors
/// or ends, and the only alternative is a third public member on
/// `CorrectionController` — which this story's boundaries forbid. AGENTS.md §3
/// bars network calls, database writes, clipboard access and prompt building
/// from a widget class; a log line is none of those.
const Set<String> _uiSanctionedProviders = {'loggerProvider'};

/// Every referenced URI in [source] that AD-1 forbids the ui ring, in source
/// order, as if the source lived at [filePath].
List<String> _uiViolations(String source, String filePath) {
  return _directiveUris(
    source,
  ).where((uri) => _violatesUiRule(uri, filePath)).toList();
}

/// Every referenced URI in [source] that violates AD-1, in source order,
/// as if the source lived at [filePath].
List<String> _violations(String source, String filePath) {
  return _directiveUris(
    source,
  ).where((uri) => _violatesAd1(uri, filePath)).toList();
}

/// Every quoted URI of every `import`/`export`/`part`/`part of` directive,
/// including the alternative URIs of conditional imports. Comments are
/// stripped first so commented-out directives never match.
List<String> _directiveUris(String source) {
  final directivePattern = RegExp(
    r'^\s*(?:import|export|part)\b[^;]*;',
    multiLine: true,
  );
  final uriPattern = RegExp('''['"]([^'"]+)['"]''');
  return [
    for (final directive in directivePattern.allMatches(_stripComments(source)))
      for (final uri in uriPattern.allMatches(directive.group(0)!))
        uri.group(1)!,
  ];
}

/// [source] with its comments removed and its string literals left intact.
///
/// A scanner rather than a pair of regexes, because `//` and `/*` inside a
/// string literal do not start a comment. `RegExp(r'//[^\n]*')` believed they
/// did, so everything after a literal containing `//` — any URL — was deleted to
/// end of line, and a banned call sharing that line went with it:
/// `final u = 'https://x'; Clipboard.setData(…);` passed this whole gate while
/// the identical call on its own line failed it.
///
/// Literals are preserved rather than blanked, which is what [_bannedUiSymbols]
/// documents and wants: a banned symbol named inside a string is a conversation
/// worth having.
String _stripComments(String source) {
  final kept = StringBuffer();
  var index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      while (index < source.length && source[index] != '\n') {
        index++;
      }
      continue;
    }
    if (source.startsWith('/*', index)) {
      final end = source.indexOf('*/', index + 2);
      index = end < 0 ? source.length : end + 2;
      continue;
    }
    final literalEnd = _endOfStringLiteral(source, index);
    if (literalEnd != null) {
      kept.write(source.substring(index, literalEnd));
      index = literalEnd;
      continue;
    }
    kept.write(source[index]);
    index++;
  }
  return kept.toString();
}

/// The index just past the string literal starting at [start], or null if no
/// literal starts there. Handles the `r` prefix, single and triple quotes, and
/// backslash escapes — enough of Dart's grammar to know where a literal ends,
/// which is all [_stripComments] needs to not mistake its content for a comment.
int? _endOfStringLiteral(String source, int start) {
  var index = start;
  final raw = source[index] == 'r';
  if (raw) {
    index++;
  }
  if (index >= source.length) {
    return null;
  }
  final quote = source[index];
  if (quote != "'" && quote != '"') {
    return null;
  }
  final delimiter = source.startsWith(quote * 3, index) ? quote * 3 : quote;
  index += delimiter.length;
  while (index < source.length) {
    if (!raw && source[index] == r'\') {
      index += 2;
      continue;
    }
    if (source.startsWith(delimiter, index)) {
      return index + delimiter.length;
    }
    if (delimiter.length == 1 && source[index] == '\n') {
      // Unterminated: stop at the line end rather than swallowing the rest of
      // the file, so a syntax error cannot blind the scan that follows.
      return index;
    }
    index++;
  }
  return index;
}

/// The application ring may reach dart:, Riverpod (AD-17 puts the state
/// approach here), and the two rings it is allowed to see — itself and
/// domain. Everything else, infrastructure and Flutter widgets included, is
/// a dependency pointing the wrong way.
bool _violatesApplicationRule(String uri, String referencingFilePath) =>
    _landsOutsideRings(uri, referencingFilePath, _ringRoots);

/// The ui ring may reach dart:, Flutter, Riverpod (AD-17 puts the state
/// approach in application *and* ui), and the two rings below it — application,
/// and domain for its read-only types. Infrastructure is what it may never see:
/// a widget that names an adapter, a plugin or a `MethodChannel` is the
/// dependency pointing the wrong way, and AD-1 says a violation fails the merge
/// gate rather than being noticed in review.
///
/// Flutter itself is the one allowance that distinguishes this rule from the
/// application ring's, where a Flutter import *is* the violation.
bool _violatesUiRule(String uri, String referencingFilePath) {
  if (_uiForbiddenDartLibraries.contains(uri)) {
    return true;
  }
  if (uri.startsWith('package:flutter/')) {
    return false;
  }
  return _landsOutsideRings(uri, referencingFilePath, _uiRingRoots);
}

/// The `dart:` libraries that reach the machine rather than the language.
///
/// [_landsOutsideRings] waves every `dart:` URI through, which is right for
/// `dart:async` and `dart:ui` and a hole for these two: a widget that imports
/// `dart:io` can shell out to `wl-copy`, read the config file or probe the
/// platform — bypassing the port, the controller's guard, the failure notice and
/// the type-only logging convention with every import rule and every symbol in
/// [_uiBannedSymbols] green.
const Set<String> _uiForbiddenDartLibraries = {'dart:io', 'dart:ffi'};

/// Whether [uri], referenced from [referencingFilePath], resolves outside
/// every ring in [roots] — the part the application and ui rules share.
bool _landsOutsideRings(
  String uri,
  String referencingFilePath,
  List<String> roots,
) {
  if (uri.startsWith('dart:') || uri.startsWith('package:flutter_riverpod/')) {
    return false;
  }
  // A self-package URI names a path in this project's own lib/, so it is
  // judged by which ring it lands in, exactly like a relative one.
  const selfPackage = 'package:hotkey_grammar_corrector/';
  if (uri.startsWith(selfPackage)) {
    final path = 'lib/${uri.substring(selfPackage.length)}';
    return !roots.any(File(path).absolute.uri.normalizePath().path.startsWith);
  }
  if (uri.contains(':')) {
    return true;
  }
  final referencingDirectory = File(referencingFilePath).absolute.parent.uri;
  final resolved = referencingDirectory.resolve(uri).normalizePath().path;
  return !roots.any(resolved.startsWith);
}

final List<String> _ringRoots = _rootsOf([
  'lib/src/application',
  'lib/src/domain',
]);

final List<String> _uiRingRoots = _rootsOf([
  'lib/src/ui',
  'lib/src/application',
  'lib/src/domain',
]);

List<String> _rootsOf(List<String> rings) => [
  for (final ring in rings) Directory(ring).absolute.uri.normalizePath().path,
];

bool _violatesAd1(String uri, String referencingFilePath) {
  if (uri.startsWith('dart:')) {
    return false;
  }
  if (uri.contains(':')) {
    // package:, or any other scheme — banned outright.
    return true;
  }
  // Relative URI: it must resolve to a path that stays inside domain/.
  final referencingDirectory = File(referencingFilePath).absolute.parent.uri;
  final resolved = referencingDirectory.resolve(uri).normalizePath().path;
  final domainRoot = Directory(
    'lib/src/domain',
  ).absolute.uri.normalizePath().path;
  return !resolved.startsWith(domainRoot);
}
