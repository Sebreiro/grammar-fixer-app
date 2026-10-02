import 'dart:io';

import 'package:hotkey_grammar_corrector/src/application/hotkey_capture.dart';
import 'package:hotkey_grammar_corrector/src/domain/hotkey/hotkey_binding.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/hotkey_key_catalogue.dart';
import 'package:hotkey_grammar_corrector/src/infrastructure/hotkey/xdg_shortcut_trigger.dart';
import 'package:test/test.dart';

/// AD-1 for the hotkey slice, and the gate that keeps `dart test` runnable.
///
/// Two backends sit behind AD-9's one port, and this file confines both. The
/// X11 arm reaches `libX11.so.6` through `dart:ffi` from a single seam file;
/// `package:dbus` is confined to the Wayland and Secret Service adapters.
/// Neither backend's vocabulary may rise
/// above `lib/src/infrastructure/hotkey/`: no keysym, keycode, X modifier mask,
/// `Pointer` or `SendPort`, and equally no `DBusValue`, XDG object path, portal
/// interface name, D-Bus error name or `CTRL+SHIFT+g` trigger string.
///
/// The first two rows are the ordinary confinement claim, and both now assert
/// *absence*. `hotkey_manager` — a Flutter plugin behind a method channel and an
/// event channel, dealing in `HotKey`, `HotKeyModifier`, `PhysicalKeyboardKey`,
/// a GDK keyval and a `<Shift><Control>g` accelerator — was removed outright in
/// phase 1, because its Linux half discarded `keybinder_bind`'s result (so a
/// refused grab was indistinguishable from a taken one) and because it put
/// `libkeybinder-3.0.so.0` in the runner's link set, where the dynamic loader
/// resolved it before `main()` even on Wayland-only hosts. `uni_platform` and
/// `hotkey_manager_platform_interface` stay named because they are the packages
/// a Dart-side keyval computation would reach for, and neither is a declared
/// dependency: importing one would be an undeclared dependency as well as a
/// vendor package crossing the seam.
///
/// The Flutter row is the sharper one, and it protects a *command* rather than a
/// design rule. `test/infrastructure/system/daemon_startup_test.dart` imports
/// **both** `x11_global_hotkey.dart` and `wayland_portal_global_hotkey.dart`, and
/// runs under `dart test`, which cannot resolve `dart:ui`. A Flutter import
/// reaching either file does not fail one test: it stops the whole binding-free
/// suite from resolving.
///
/// That row covers exactly one directory — `lib/src/infrastructure/hotkey/` —
/// and **now with no exempt files at all**: it used to exempt the
/// `hotkey_manager` seam, because naming a Flutter plugin required a binding,
/// and the seam that replaced it needs none. It is not a check of the whole
/// import graph, and does not need to
/// be: the only other rings `x11_global_hotkey.dart` and
/// `wayland_portal_global_hotkey.dart` reach are `domain/` and each other's
/// directory, and `ad1_import_rule_test.dart` already holds `domain/` to `dart:`
/// libraries and intra-domain paths alone. Between the two rows the graph is
/// covered; either one alone would leave half of it open.
///
/// A source scan is the same idiom `tray_confinement_test.dart` and
/// `ad19_path_home_test.dart` use for claims that live in a file's text.
void main() {
  test('AD-1: no file under lib/ names package:hotkey_manager at all', () {
    expect(
      // The bare prefix, deliberately. This row used to scan
      // `package:hotkey_manager/` with a trailing slash so that it stayed
      // independent of the next row, which covers the platform interface.
      // With the package gone from the dependency graph there is nothing left
      // to keep the two rows apart, and the bare prefix is strictly stronger —
      // it also catches `hotkey_manager_linux`,
      // `hotkey_manager_platform_interface` and every other member of the
      // family in a single assertion.
      _filesReferencing('package:hotkey_manager'),
      isEmpty,
      reason:
          'this row read "confined to exactly one seam file" while the plugin '
          'shipped. It now reads "not present at all": the plugin was removed '
          "because its Linux half discarded keybinder_bind's result and so "
          'could not report a refused grab, and because it put '
          "libkeybinder-3.0.so.0 in the runner's link set. A file naming it "
          'again would be re-introducing both defects, not loosening a '
          'confinement',
    );
  });

  test('AD-1: no file under lib/ names uni_platform or the hotkey_manager '
      'platform interface', () {
    expect(
      [
        ..._filesReferencing('package:uni_platform'),
        ..._filesReferencing('package:hotkey_manager_platform_interface'),
      ],
      isEmpty,
      reason:
          'neither is a declared dependency, so naming one is an undeclared '
          'dependency. There is no longer a vendor package at the seam for it '
          'to sit on top of either: the seam talks to libX11.so.6 through '
          'dart:ffi, so a uni_platform reference now has no plausible reason '
          'to appear at all',
    );
  });

  test('AD-1: no file under lib/src/infrastructure/hotkey/ imports Flutter, '
      'with no exemptions left', () {
    // Every import that needs a Flutter binding, not just `package:flutter/`.
    // `dart:ui` is the one this row's own reason names as what `dart test`
    // cannot resolve, and it is reachable without going through
    // `package:flutter/` at all — so scanning for the wrapper alone would let
    // the exact import this row exists to stop walk straight past it.
    // `package:flutter_test/` is here for the same reason and
    // `package:flutter_riverpod/` because `ad1_import_rule_test.dart`
    // explicitly exempts it, which is right for the rings it polices and wrong
    // for this directory.
    for (final reference in const [
      'package:flutter/',
      'package:flutter_test/',
      'package:flutter_riverpod/',
      'dart:ui',
    ]) {
      expect(
        _filesReferencing(
          reference,
        ).where((path) => path.startsWith(_hotkeyDirectory)),
        isEmpty,
        reason:
            'x11_global_hotkey.dart and wayland_portal_global_hotkey.dart are '
            'both imported by suites that run under dart test, which cannot '
            'resolve dart:ui — a $reference import in this directory stops the '
            'binding-free suite resolving at all, rather than failing a test '
            'someone would read. **The exemption list is now empty and this '
            'whole directory is binding-free.** It previously exempted exactly '
            'one file, the hotkey_manager seam, because naming that package '
            'required a Flutter binding; the seam that replaced it reaches '
            'libX11.so.6 through dart:ffi, and dart:ffi, dart:isolate and '
            'package:ffi are all binding-free. This is a strengthening, so do '
            'not "restore" the exemption to make a new import fit — package:dbus '
            'is pure dart:io and the Wayland adapter has never needed one '
            'either. The other half of the import graph, lib/src/domain/, is '
            'held by ad1_import_rule_test.dart',
      );
    }
  });

  test(
    'AD-9, PROVIDER-02: only infrastructure adapters import package:dbus',
    () {
      expect(
        _filesReferencing('package:dbus/'),
        unorderedEquals([_secretServiceAdapterFile, _waylandAdapterFile]),
        reason:
            'portal and keyring calls must stay inside their own infrastructure '
            'adapters; neither domain nor UI may import a D-Bus type',
      );
    },
  );

  test('AD-9: portal names stay in the Wayland adapter and generic D-Bus '
      'types stay inside infrastructure adapters', () {
    for (final reference in const [
      '/org/freedesktop/portal/desktop',
      '/org/freedesktop/host/portal/registry',
    ]) {
      expect(
        _filesReferencing(reference),
        [_waylandAdapterFile],
        reason:
            'the portal vocabulary is the Wayland analogue of the X11 keyval '
            'and accelerator: nothing above the adapter may see $reference, or '
            "AD-9's one-port-two-adapters becomes one port with portal "
            'semantics baked into its callers',
      );
    }
    for (final reference in const ['org.freedesktop', 'DBus']) {
      expect(
        _filesReferencing(reference),
        unorderedEquals([_secretServiceAdapterFile, _waylandAdapterFile]),
        reason: '$reference must stay in its infrastructure adapter',
      );
    }
  });

  test(
    'AD-11: the portal request tokens come from a cryptographic generator',
    () {
      // Not pinnable by an outcome, and this is the closest honest gate. The
      // Request object path is built from `handle_token`, and the adapter's own
      // reasoning makes the token's unguessability defence in depth behind the
      // sender filter. A25 keeps the tokens *distinct* — which a plain counter
      // satisfies — so swapping `Random.secure()` for a seeded `Random()` leaves
      // the whole suite green while restoring exactly the guessable path a peer
      // on the session bus needs to forge a `Response`.
      final source = File(_waylandAdapterFile).readAsStringSync();
      expect(source, contains('Random.secure()'));
      expect(
        RegExp(r'\bRandom\((?!\))').hasMatch(_stripComments(source)),
        isFalse,
        reason: 'a seeded generator would make the Request path predictable',
      );
    },
  );

  test('AD-9: the XDG trigger vocabulary stays inside the hotkey directory', () {
    // The other half of AD-9's serialization, and the half that does not name
    // package:dbus at all: `CTRL+SHIFT+g` is portal syntax, and a settings screen
    // or a config store that spelled a combination that way would be encoding
    // one display server's assumptions into a shared surface.
    //
    // The vocabulary is **derived from `XdgShortcutTrigger` itself**, so the gate
    // cannot fall behind the serializer: a fifth `HotkeyModifier` brings its own
    // keyword along, and a changed keysym name changes what is scanned for.
    for (final reference in _triggerVocabulary) {
      expect(
        _filesReferencing(
          _patternFor(reference),
        ).where((path) => !path.startsWith(_hotkeyDirectory)),
        isEmpty,
        reason:
            '$reference is infrastructure vocabulary, not domain vocabulary — '
            'a config store or a settings widget spelling a combination that '
            'way would encode one display server into a shared surface',
      );
    }
  });

  test('the trigger scan does not fire on an ordinary word that contains a '
      'modifier keyword', () {
    // `ALT` is a substring of `ALTER`, and CAP-7's history lives in a drift
    // database whose first hand-written migration will say `ALTER TABLE`. A
    // bare-substring scan would fail the row above with a reason accusing a
    // schema migration of encoding a display server, sending the next reader
    // hunting for a hotkey leak in the persistence ring. The keysym half
    // already avoids this by scanning `CTRL+<keysym>`; the keywords need a word
    // boundary, which is what this row is here to keep.
    for (final line in const [
      "customStatement('ALTER TABLE corrections ADD COLUMN note TEXT')",
      'const salt = SALTED;',
      'NUMBER_OF_RETRIES',
    ]) {
      for (final keyword in _modifierKeywords) {
        expect(
          line.contains(_patternFor(keyword)),
          isFalse,
          reason: '$keyword must not match inside "$line"',
        );
      }
    }
    // And the control, or the row above proves only that the pattern matches
    // nothing at all.
    expect('preferred_trigger: CTRL+g'.contains(_patternFor('CTRL')), isTrue);
    expect('LOGO'.contains(_patternFor('LOGO')), isTrue);
  });

  test('AD-1: nothing under lib/src/ui/settings/ names a key label this build '
      'cannot register', () {
    // Re-pointed, not retired. This row used to scan the settings directory's
    // string literals for `HotkeyKeyCatalogue.labelsThatBindTheWrongKey` —
    // seven labels the removed vendor chain bound to a keypad, ISO or 3270
    // variant. That set is gone (see the catalogue's doc for the measurement),
    // and a loop over an empty set would have passed this row while asserting
    // nothing at all.
    //
    // The live subject is the other direction, and it is the one the capture
    // control makes checkable: the screen no longer *offers* key labels — the
    // user presses the combination — so any key label still spelled in a
    // literal there is prose, and prose that names a key this build cannot
    // register is the same defect in a new place (a user told to press
    // `PrintScreen` gets `HotkeyUnavailable`). The check lives here rather than
    // in the widget's own suite for the reason the rest of this file exists:
    // the vocabulary is `HotkeyKeyCatalogue`'s and AD-1 puts it out of the ui
    // ring's reach, so a widget test could only restate a hard-coded copy.
    final unregistrable = <String>[];
    for (final file
        in Directory(_settingsDirectory)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      for (final literal in _stringLiterals(file.readAsStringSync())) {
        for (final word in RegExp(
          r'[A-Za-z][A-Za-z0-9]*',
        ).allMatches(literal)) {
          final candidate = word.group(0)!;
          if (!_keyLabelShapedWords.contains(candidate)) {
            continue;
          }
          if (HotkeyKeyCatalogue.usbHidUsageFor(candidate) == null) {
            unregistrable.add('${file.path}: $candidate');
          }
        }
      }
    }

    expect(
      unregistrable,
      isEmpty,
      reason:
          'a settings screen must not name a key this build cannot register '
          'as a shortcut:\n${unregistrable.join('\n')}',
    );
  });

  test('AD-1, HOTKEY-04: the vocabulary the settings screen validates against '
      'is this build\'s, and refuses everything outside it', () {
    // **This row replaces a retired one, and the retirement is the point.** It
    // used to read `offeredKeyExamples` out of `hotkey_preference_field.dart`
    // and resolve each entry against the catalogue, because the free-text key
    // field *suggested* labels and a suggestion outside the catalogue came back
    // `HotkeyUnavailable` — the user following the screen's own advice and
    // being told no. D-14 removed the field and the suggestions with it: the
    // user presses the combination, so there is nothing left to offer and no
    // declaration to read.
    //
    // What now guarantees the user cannot choose an unregistrable key is not a
    // curated list of offers but a validator, and this row is where that claim
    // is checked from outside the ui ring. `main.dart` builds
    // `HotkeyKeyCatalogue.registrableKeys()` and injects it; the capture
    // control refuses any physical key the vocabulary does not carry. So the
    // subject is the vocabulary plus the refusal, and it is strictly stronger
    // than the row it replaces — that one could only check the three labels
    // somebody remembered to put in a list.
    final vocabulary = HotkeyKeyCatalogue.registrableKeys();
    final validator = HotkeyCaptureValidator(vocabulary);

    expect(
      vocabulary.all,
      isNotEmpty,
      reason: 'an empty vocabulary would pass every assertion below for free',
    );
    for (final key in vocabulary.all) {
      expect(
        HotkeyKeyCatalogue.usbHidUsageFor(key.label),
        key.usbHidUsage,
        reason:
            'the vocabulary must carry exactly what this build can register — '
            'a key in it the adapter refuses is the defect this row inherited',
      );
      expect(
        validator.verdictFor(
          HotkeyCapture(
            modifiers: const {HotkeyModifier.control, HotkeyModifier.shift},
            usbHidUsage: key.usbHidUsage,
            keyIsModifier: false,
            usesLevelThreeModifier: false,
          ),
        ),
        isA<HotkeyCaptureAccepted>(),
        reason: 'every key in the vocabulary must be capturable',
      );
    }

    // And the refusal, for a physical key that is real and outside the
    // catalogue: `PrintScreen` (0x00070046). The old row could not state this
    // at all — a scan for absent labels cannot prove a refusal happens.
    final refused = validator.verdictFor(
      const HotkeyCapture(
        modifiers: {HotkeyModifier.control},
        usbHidUsage: 0x00070046,
        keyIsModifier: false,
        usesLevelThreeModifier: false,
      ),
    );
    expect(refused, isA<HotkeyCaptureRefused>());
    expect(
      (refused as HotkeyCaptureRefused).refusal,
      HotkeyCaptureRefusal.keyNotRegistrable,
      reason:
          'the user must be told which of the four things went wrong, not '
          'merely that something did (D-15)',
    );
  });

  test('the offered-key scan reads literals and would catch a real one', () {
    // Positive and negative controls, because a scan that silently stopped
    // matching would pass this file's row forever. Comments are stripped first,
    // so the widget may *explain* which labels are refused; only an offer counts.
    // The positive control for the scanner's *subject*, re-pointed: it used to
    // assert that the dissolved label set contained `Space`, which fails the
    // moment that set is gone. `_keyLabelShapedWords` is the live subject the
    // scan above iterates, and `Space` is still in it — the point of the row is
    // that the scanner is matching something rather than nothing.
    expect(_keyLabelShapedWords, contains('Space'));
    expect(
      HotkeyKeyCatalogue.usbHidUsageFor('Space'),
      isNotNull,
      reason: 'and it is a label this build registers, so it is not a hit',
    );
    expect(
      _stringLiterals("const hint = 'for example G, Space or F12';"),
      contains('for example G, Space or F12'),
    );
    expect(
      _stringLiterals("// Space is refused\nfinal x = 'G';"),
      equals(<String>['G']),
    );
    expect(
      _stringLiterals("/* Space is refused */ final x = 'G';"),
      equals(<String>['G']),
    );
    // An escaped quote inside a literal must not end it. Without the `\.`
    // alternative the first match stopped at `don\`, the leftover quote
    // desynchronised the rest of the file, and `Space` went unscanned — the
    // scan passing precisely because it had stopped looking.
    expect(
      _stringLiterals(r"final hint = 'don\'t use Space';"),
      contains(r"don\'t use Space"),
    );
    // A comment marker *inside* a literal is not a comment. Stripping comments
    // in a separate first pass deleted from the `//` to the end of the line, so
    // the offer that followed it on that line went unscanned — the same silent
    // stop as the escaped quote, from the other direction.
    expect(
      _stringLiterals("final hint = 'see https://x for labels, e.g. Space';"),
      contains('see https://x for labels, e.g. Space'),
    );
    expect(
      _stringLiterals("final hint = 'a /* b */ Space';"),
      contains('a /* b */ Space'),
    );
    // An interpolation may carry quotes of its own, and they do not end the
    // literal that holds them.
    expect(
      _stringLiterals("final hint = 'for example \${list.join(', ')} here';"),
      contains("for example \${list.join(', ')} here"),
    );
    expect(
      Directory(_settingsDirectory).listSync().whereType<File>(),
      isNotEmpty,
      reason: 'the settings directory must exist for the row above to scan it',
    );
  });

  test('the scan actually finds something, or it proves nothing', () {
    // Re-pointed, not removed. This row exists so the scan cannot pass by
    // scanning for nothing, so every entry has to name something that is
    // genuinely present. `package:hotkey_manager` was the original positive
    // subject and it is gone; `XGrabKey` replaces it because the new seam
    // really does contain it and nothing else under lib/ does.
    expect(_filesReferencing('XGrabKey'), isNotEmpty);
    expect(_filesReferencing('package:dbus'), isNotEmpty);
    expect(_filesReferencing('org.freedesktop'), isNotEmpty);
    expect(_filesReferencing('CTRL'), isNotEmpty);
    expect(_filesReferencing('preferred_trigger'), isNotEmpty);
    // The one signal the sandbox predicate is allowed to key on, pinned as a
    // positive subject rather than as a confinement rule. Nothing above
    // infrastructure names it, but that is not what this row is for: the whole
    // sandboxed branch of AD-11's step 1 hangs off this literal, and a rewrite
    // that keyed the predicate on `/.dockerenv` or a cgroup path instead —
    // both true in this project's own container, which is why the adapter
    // refused to detect a sandbox at all before — would delete it and leave
    // every row here green.
    expect(_filesReferencing('/.flatpak-info'), isNotEmpty);
    expect(
      _triggerVocabulary,
      hasLength(79),
      reason:
          '4 modifier keywords + 74 composed triggers + preferred_trigger; a '
          'derivation that quietly produced an empty set would make the row '
          'above pass by scanning for nothing',
    );
    expect(File(_seamFile).existsSync(), isTrue);
    expect(File(_waylandAdapterFile).existsSync(), isTrue);
    expect(
      Directory(_hotkeyDirectory).listSync().whereType<File>(),
      isNotEmpty,
      reason: 'the hotkey directory must exist for the rows to mean anything',
    );
  });
}

/// Every token the XDG serializer can emit, derived from it rather than listed.
///
/// Two shapes, because a bare keysym name is not scannable as a substring: the
/// serializer emits `g`, `Up`, `End`, `Tab`, `Insert`, `Home` and `Next` among
/// others, and measured against this tree those appear inside ordinary
/// identifiers everywhere — `Up` in generated drift code, `Down` inside
/// `shutdown`, `Home` inside `HOME`, `End` inside `appendEnd`, `space` inside
/// `whitespace`. So:
///
///  * the **modifier keywords** are scanned bare but on a word boundary — see
///    [_patternFor]; `ALT` inside `ALTER TABLE` is not a display server
///    escaping into the persistence ring. This is where a fifth
///    [HotkeyModifier] would show up automatically; and
///  * the **keysym names** are scanned in the only form in which one could
///    legitimately appear above infrastructure — as part of a serialized trigger,
///    `CTRL+<keysym>` — which is unambiguous for every one of the sixty-three.
///
/// Plus `preferred_trigger`, the vardict key the whole string exists to fill.
Iterable<String> get _triggerVocabulary => <String>{
  ..._modifierKeywords,
  for (final label in XdgShortcutTrigger.labels)
    XdgShortcutTrigger.forBinding(
      HotkeyBinding(modifiers: const {HotkeyModifier.control}, key: label),
    )!,
  'preferred_trigger',
};

/// The four specification keywords, which are the tokens scanned bare.
Set<String> get _modifierKeywords => {
  for (final modifier in HotkeyModifier.values)
    XdgShortcutTrigger.modifierKeywordFor(modifier),
};

/// A bare modifier keyword is matched on a word boundary; everything else is a
/// plain substring.
///
/// `CTRL+<keysym>` and `preferred_trigger` are already unambiguous as
/// substrings, and wrapping them in `\b` would be noise. A keyword is not: `ALT`
/// sits inside `ALTER` and `SALT`, `NUM` inside `NUMBER`, so scanning it bare
/// would fail this file's own row on an unrelated SQL migration.
Pattern _patternFor(String reference) => _modifierKeywords.contains(reference)
    ? RegExp('\\b${RegExp.escape(reference)}\\b')
    : reference;

/// Every single- or double-quoted string literal in [source], in source order.
///
/// Deliberately literals rather than the whole text: the settings widgets
/// *explain* which labels are refused, and prose naming one is the opposite of a
/// violation. Comments are stripped by the caller, so what is left is code, and a
/// literal is where an offer to the user lives.
///
/// Escapes are part of the literal body, and leaving them out was a hole rather
/// than a simplification: with no `\\.` alternative, `'don\\'t use Space'` ends
/// its first match at the escaped quote, and the unpaired quote left behind
/// desynchronises every literal after it — so the label this row exists to catch
/// would never be scanned and the row would pass reporting nothing.
/// Every string literal in [source], with comments skipped in the same pass.
///
/// **One pass, and that is the fix rather than a tidy-up.** Stripping comments
/// first and matching literals afterwards means a `//` or `/*` *inside* a
/// literal deletes to the end of the line: `'see https://example.com/keys'`
/// strips to `'see https:`, so a label offered on that line goes unscanned and
/// the row passes by having stopped looking. That is the same silent failure
/// mode the escaped quote caused, and only a scanner that knows which construct
/// it is inside can avoid it — which is why this reads the source rather than
/// pattern-matching it.
///
/// Interpolations are stepped over with brace depth, so a nested `'` inside
/// `${…}` cannot end the literal early; triple-quoted strings are consumed
/// whole. An unterminated quote is stepped past rather than allowed to
/// desynchronise everything after it.
List<String> _stringLiterals(String source) {
  final literals = <String>[];
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    if (char == '/' && i + 1 < source.length) {
      final next = source[i + 1];
      if (next == '/') {
        final end = source.indexOf('\n', i);
        i = end == -1 ? source.length : end + 1;
        continue;
      }
      if (next == '*') {
        final end = source.indexOf('*/', i + 2);
        i = end == -1 ? source.length : end + 2;
        continue;
      }
    }
    if (char != "'" && char != '"') {
      i++;
      continue;
    }
    final triple = source.startsWith(char * 3, i);
    final quote = triple ? char * 3 : char;
    final buffer = StringBuffer();
    var j = i + quote.length;
    var closed = false;
    while (j < source.length) {
      final c = source[j];
      if (c == r'\' && j + 1 < source.length) {
        buffer
          ..write(c)
          ..write(source[j + 1]);
        j += 2;
        continue;
      }
      if (source.startsWith(quote, j)) {
        closed = true;
        break;
      }
      if (c == r'$' && j + 1 < source.length && source[j + 1] == '{') {
        // Step over the interpolation with brace depth: the expression inside
        // may carry quotes of its own, and they are not this literal's end.
        var depth = 0;
        var k = j + 1;
        while (k < source.length) {
          if (source[k] == '{') depth++;
          if (source[k] == '}') {
            depth--;
            if (depth == 0) break;
          }
          k++;
        }
        buffer.write(source.substring(j, k == source.length ? k : k + 1));
        j = k == source.length ? k : k + 1;
        continue;
      }
      if (!triple && c == '\n') {
        break; // an unterminated single-line literal
      }
      buffer.write(c);
      j++;
    }
    if (closed) {
      literals.add(buffer.toString());
      i = j + quote.length;
      continue;
    }
    i++;
  }
  return literals;
}

const String _settingsDirectory = 'lib/src/ui/settings/';
const String _hotkeyDirectory = 'lib/src/infrastructure/hotkey/';

/// The one file that names `dart:ffi` and opens an X `Display`.
///
/// Named `_seamFile` still, but no longer a *Flutter-import exemption* — the
/// exemption list is empty now (see the import row above). What makes this file
/// the seam is that it is the only implementation of `HotkeyRegistrar` and the
/// only place the X11 vocabulary exists, which is what AD-9's "replacing this
/// backend is a one-file change" claim is about.
const String _seamFile =
    'lib/src/infrastructure/hotkey/x11_key_grab_registrar.dart';
const String _waylandAdapterFile =
    'lib/src/infrastructure/hotkey/wayland_portal_global_hotkey.dart';
const String _secretServiceAdapterFile =
    'lib/src/infrastructure/correction/secret_service_secret_store.dart';

/// Every file under `lib/` whose source names [reference], comments stripped so
/// a comment explaining the confinement never reads as a violation of it.
List<String> _filesReferencing(Pattern reference) {
  return [
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
      if (_stripComments(file.readAsStringSync()).contains(reference))
        file.path,
  ];
}

String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp('//[^\n]*'), '');

/// The words a settings-screen literal might use that are *meant* as key
/// labels, so the scan above can tell `Insert` the key from `insert` the verb.
///
/// A closed list rather than "every word the catalogue resolves", and the
/// difference matters in both directions. Single letters and digits are the
/// catalogue's largest run and are also ordinary English (`A`, `I`) and
/// ordinary numbers, so resolving every word against the catalogue would make
/// the row fire on any sentence; and the interesting failures are the
/// *unregistrable* ones, which by definition are not in the catalogue and so
/// have to be enumerated. Every entry that is registrable is here to keep the
/// list honest — a list of only bad labels would pass while the scan matched
/// nothing.
const Set<String> _keyLabelShapedWords = {
  // Registrable, and named so the scanner has live subjects to match.
  'Space',
  'Tab',
  'Enter',
  'Escape',
  'Backspace',
  'Insert',
  'Delete',
  'Home',
  'End',
  'PageUp',
  'PageDown',
  'F1',
  'F12',
  // Not registrable by this build, and the reason the row exists: each is a
  // real physical key a user could reasonably be told to press.
  'PrintScreen',
  'CapsLock',
  'NumLock',
  'ScrollLock',
  'Pause',
  'Menu',
  'F13',
  'Numpad0',
  'KP_Space',
  'ISO_Left_Tab',
};
