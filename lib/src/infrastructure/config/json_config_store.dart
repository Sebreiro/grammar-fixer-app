import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../domain/config/app_config.dart';
import '../../domain/config/close_behavior.dart';
import '../../domain/config/config_load_result.dart';
import '../../domain/config/config_store.dart';
import '../../domain/config/config_write_conflict.dart';
import '../../domain/config/provider_config.dart';
import '../../domain/correction/preset.dart';
import '../../domain/hotkey/hotkey_binding.dart';
import 'app_paths.dart';

/// AD-13's single owner of the config file: the only code in `lib/` that
/// opens it, parses it, validates it, or writes it.
///
/// A missing, unreadable, unparseable, or internally inconsistent file yields
/// the injected defaults plus a warning on [ConfigLoadResult] — [load] never
/// throws, because a resident daemon that refuses to start over a bad file
/// leaves the user no surface on which to fix it.
final class JsonConfigStore implements ConfigStore {
  JsonConfigStore({required AppPaths paths, required this._defaults})
    : _file = File(paths.configFile);

  /// Human-editable output, because CAP-8's other half is a person opening
  /// this file in an editor.
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  /// Makes each temp file unique. Process-wide rather than per-instance
  /// because two stores over one path (tests, a future re-read) must not
  /// pick the same scratch name.
  static int _tempSequence = 0;

  static final DynamicLibrary _libc = DynamicLibrary.open('libc.so.6');
  static final int Function(Pointer<Utf8>, int, int) _openFile = _libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, Uint32),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  static final int Function(int) _closeFile = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final int Function(int, int) _fchmodFile = _libc
      .lookupFunction<Int32 Function(Int32, Uint32), int Function(int, int)>(
        'fchmod',
      );
  static final int Function(Pointer<Utf8>, int) _chmodFile = _libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)
      >('chmod');

  // Linux O_WRONLY | O_CREAT | O_EXCL and owner read/write (0600).
  static const int _exclusiveWriteCreate = 0x1 | 0x40 | 0x80;
  static const int _ownerReadWrite = 0x180;

  final File _file;
  final AppConfig _defaults;
  final StreamController<AppConfig> _changes =
      StreamController<AppConfig>.broadcast();

  /// Serializes every file operation. `SettingsController.changeHotkey`
  /// awaits a portal dialog that can sit for seconds, so a second mutation
  /// landing in that window is reachable in-process — and two overlapping
  /// writes would truncate each other's scratch file.
  Future<void> _fileOperations = Future<void>.value();
  StreamSubscription<FileSystemEvent>? _fileEvents;

  AppConfig? _loaded;
  Map<String, String> _promptFileNames = const {};

  @override
  AppConfig get current {
    final loaded = _loaded;
    if (loaded == null) {
      throw StateError('ConfigStore.current was read before load() completed');
    }
    return loaded;
  }

  @override
  Stream<AppConfig> get changes => _changes.stream;

  @override
  Future<ConfigLoadResult> load() => _serialized(() async {
    final result = await _loadAndMigratePrompts();
    final changed = _loaded != null && _loaded != result.config;
    _loaded = result.config;
    if (changed && result.warning == null && !_changes.isClosed) {
      _changes.add(result.config);
    }
    await _watchFile();
    return result;
  });

  Future<ConfigLoadResult> _loadAndMigratePrompts() async {
    final result = await _read();
    if (result.warning != null ||
        _promptFileNames.length == result.config.presets.length) {
      return result;
    }
    try {
      await _writeFile(result.config);
      return result;
    } on FileSystemException catch (error) {
      return ConfigLoadResult(
        config: result.config,
        warning:
            'could not move inline prompts to .txt files beside '
            '"${_file.path}"; continuing with the saved inline prompts',
        warningErrorType: error.runtimeType.toString(),
      );
    }
  }

  @override
  Future<void> write(AppConfig config) async {
    // Validated before queueing: a rejected write must not wait behind an
    // in-flight one to report a mistake the caller already made.
    final problem = validationProblem(config);
    if (problem != null) {
      throw ArgumentError.value(config, 'config', problem);
    }
    await _serialized(() async {
      if (_loaded != null) {
        final latest = await _read();
        if (latest.warning != null) {
          throw FileSystemException(
            'the config file cannot be read for writing',
          );
        }
        if (latest.config != _loaded) {
          _loaded = latest.config;
          if (!_changes.isClosed) {
            _changes.add(latest.config);
          }
          throw const ConfigWriteConflict();
        }
      }
      await _writeFile(config);
      _loaded = config;
      // A write can resolve after shutdown; adding then would be an
      // unhandled "add after close" in a daemon that is already going down.
      if (!_changes.isClosed) {
        _changes.add(config);
      }
    });
  }

  /// Runs [operation] after every file operation queued before it. A failure
  /// does not poison the queue: the next caller still gets its turn.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _fileOperations.then((_) => operation());
    _fileOperations = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// Releases the broadcast controller. Not part of the port: the
  /// composition root owns the store's lifetime and calls this at shutdown.
  Future<void> close() async {
    await _fileEvents?.cancel();
    if (!_changes.isClosed) {
      await _changes.close();
    }
  }

  /// Watch the directory because atomic replacement changes the file inode.
  Future<void> _watchFile() async {
    if (_fileEvents != null) {
      return;
    }
    try {
      if (!await _file.parent.exists()) {
        return;
      }
      _fileEvents = _file.parent.watch().listen(
        (event) {
          final name = event.path.split(Platform.pathSeparator).last;
          if (name != _file.uri.pathSegments.last &&
              !_promptFileNames.containsValue(name)) {
            return;
          }
          unawaited(_refreshFromDisk());
        },
        onError: (Object _) {
          // The next write still checks the file before replacing it.
        },
      );
    } on FileSystemException {
      // A read-only or unwatchable directory still gets a guarded next write.
    }
  }

  Future<void> _refreshFromDisk() => _serialized(() async {
    final result = await _read();
    if (result.warning != null || result.config == _loaded) {
      return;
    }
    _loaded = result.config;
    if (!_changes.isClosed) {
      _changes.add(result.config);
    }
  });

  /// A description of the first structural problem in [config], or null when
  /// it is internally consistent. Pure, and the single validation point the
  /// port documents — nothing downstream re-validates, so everything a
  /// consumer is entitled to assume has to be checked here: [load] turns a
  /// hit into a warning, [write] turns it into an [ArgumentError].
  ///
  /// An empty modifier set is deliberately allowed: a bare-key binding (an
  /// F-key, say) is legitimate, and ruling it out is the hotkey layer's
  /// call, not this store's.
  static String? validationProblem(AppConfig config) {
    if (config.logMaxBytes < AppConfig.minimumLogMaxBytes) {
      return 'logMaxBytes must be at least ${AppConfig.minimumLogMaxBytes}';
    }
    final seenPresetIds = <String>{};
    for (final preset in config.presets) {
      if (preset.systemPrompt.trim().isEmpty) {
        return 'preset "${preset.id}" systemPrompt must not be empty';
      }
      // Consumers resolve the active preset with a single-match lookup, so a
      // duplicate id is a crash waiting downstream of a config this method
      // would otherwise have certified.
      if (!seenPresetIds.add(preset.id)) {
        return 'preset id "${preset.id}" appears more than once; preset ids '
            'must be unique';
      }
      if (!config.providers.containsKey(preset.providerId)) {
        return 'preset "${preset.id}" names provider "${preset.providerId}", '
            'which is not described in providers';
      }
    }
    final activeExists = config.presets.any(
      (preset) => preset.id == config.activePresetId,
    );
    if (!activeExists) {
      return 'activePresetId "${config.activePresetId}" names no preset';
    }
    if (config.hotkeyBinding.key.isEmpty) {
      return 'hotkeyBinding.key is empty; a binding needs a key to bind';
    }
    return null;
  }

  Future<ConfigLoadResult> _read() async {
    final String contents;
    try {
      if (!await _file.exists()) {
        final (warning, errorType) = await _seed();
        if (warning != null) {
          return ConfigLoadResult(
            config: _defaults,
            warning: warning,
            warningErrorType: errorType,
          );
        }
      }
      contents = await _file.readAsString();
    } on IOException catch (error) {
      return _defaultsWithWarning(
        'could not be read',
        errorType: error.runtimeType.toString(),
      );
    }
    final ({AppConfig config, Map<String, String> promptFiles}) decoded;
    try {
      decoded = await _decode(contents);
    } on _ConfigFormatException catch (error) {
      return _defaultsWithWarning(
        'is invalid: ${error.message}',
        loggedProblem: 'has an invalid structure',
        errorType: error.runtimeType.toString(),
      );
    } on FormatException catch (error) {
      return _defaultsWithWarning(
        'is not valid JSON',
        errorType: error.runtimeType.toString(),
      );
    }
    final problem = validationProblem(decoded.config);
    if (problem != null) {
      return _defaultsWithWarning(
        'is inconsistent: $problem',
        loggedProblem: 'contains inconsistent settings',
      );
    }
    _promptFileNames = decoded.promptFiles;
    return ConfigLoadResult(config: decoded.config);
  }

  /// A first run writes the defaults out so CAP-8's "edit the config file"
  /// half has a file to edit. Returns a warning instead of throwing when the
  /// seed cannot be written — startup survives a read-only home.
  Future<(String?, String?)> _seed() async {
    try {
      final names = {
        for (final preset in _defaults.presets)
          preset.id: _defaultPromptFileName(preset.id),
      };
      final contents = <(File, String)>[];
      for (final preset in _defaults.presets) {
        final prompt = _promptFile(_requiredFileName(names, preset.id));
        // Reseeding a deleted config must not erase a user's existing prompt.
        if (!await prompt.exists()) contents.add((prompt, preset.systemPrompt));
      }
      contents.add((_file, _encode(_defaults, names)));
      await _writeFiles(contents);
      return (null, null);
    } on FileSystemException catch (error) {
      return (
        'could not create the default config file at "${_file.path}"; '
            'continuing with in-memory defaults',
        error.runtimeType.toString(),
      );
    }
  }

  ConfigLoadResult _defaultsWithWarning(
    String problem, {
    String? loggedProblem,
    String? errorType,
  }) => ConfigLoadResult(
    config: _defaults,
    warning: 'the config file "${_file.path}" $problem; using defaults',
    logWarning: loggedProblem == null
        ? null
        : 'the config file "${_file.path}" $loggedProblem; using defaults',
    warningErrorType: errorType,
  );

  /// Temp file plus rename, so a crash or a full disk can never leave a
  /// half-written config behind for the next startup to reject. The scratch
  /// name is unique per write: a fixed one lets two writers truncate each
  /// other and leaves the loser renaming a file that no longer exists.
  Future<void> _writeFile(AppConfig config) async {
    final names = await _fileNamesFor(config);
    await _writeFiles([
      for (final preset in config.presets)
        (_promptFile(_requiredFileName(names, preset.id)), preset.systemPrompt),
      (_file, _encode(config, names)),
    ]);
    _promptFileNames = names;
  }

  File _promptFile(String name) => File('${_file.parent.path}/$name');

  static String _defaultPromptFileName(String presetId) =>
      'prompt-${Uri.encodeComponent(presetId)}.txt';

  Future<Map<String, String>> _fileNamesFor(AppConfig config) async {
    final names = <String, String>{
      for (final preset in config.presets)
        preset.id: ?_promptFileNames[preset.id],
    };
    for (final preset in config.presets) {
      if (names.containsKey(preset.id)) continue;
      final base = _defaultPromptFileName(preset.id);
      var candidate = base;
      var suffix = 2;
      while (names.containsValue(candidate) ||
          await FileSystemEntity.type(_promptFile(candidate).path) !=
              FileSystemEntityType.notFound) {
        candidate = '${base.substring(0, base.length - 4)}-${suffix++}.txt';
      }
      names[preset.id] = candidate;
    }
    return names;
  }

  static String _requiredFileName(Map<String, String> names, String presetId) {
    final name = names[presetId];
    if (name == null) throw StateError('No prompt file for preset $presetId');
    return name;
  }

  /// Stage every file before replacing any: disk-full and permission failures
  /// must leave the saved preset and its prompt together.
  Future<void> _writeFiles(List<(File, String)> contents) async {
    final prepared = <_PreparedWrite>[];
    try {
      for (final (target, text) in contents) {
        final previous = await target.exists()
            ? await target.readAsString()
            : null;
        if (previous == text) continue;
        final temp = await _stageFile(target, text);
        prepared.add(_PreparedWrite(target, temp, previous));
      }
      await _installFiles(prepared);
    } finally {
      for (final write in prepared) {
        await _discard(write.temp);
      }
    }
  }

  Future<void> _installFiles(List<_PreparedWrite> prepared) async {
    final installed = <_PreparedWrite>[];
    try {
      for (final write in prepared) {
        await write.temp.rename(write.target.path);
        installed.add(write);
      }
    } on FileSystemException {
      for (final write in installed.reversed) {
        await _restoreFile(write);
      }
      rethrow;
    }
  }

  Future<void> _restoreFile(_PreparedWrite write) async {
    final previous = write.previous;
    if (previous == null) {
      await write.target.delete();
      return;
    }
    final temp = await _stageFile(write.target, previous);
    try {
      await temp.rename(write.target.path);
    } finally {
      await _discard(temp);
    }
  }

  Future<File> _stageFile(File target, String contents) async {
    await target.parent.create(recursive: true);
    _tempSequence += 1;
    final temp = File('${target.path}.$pid.$_tempSequence.tmp');
    try {
      final existing = await target.stat();
      final finalMode = existing.type == FileSystemEntityType.file
          ? existing.mode & _ownerReadWrite
          : _ownerReadWrite;
      if (Platform.isLinux) {
        _createOwnerOnly(temp.path);
      }
      await temp.writeAsString(contents, flush: true);
      if (Platform.isLinux && finalMode != _ownerReadWrite) {
        _setMode(temp.path, finalMode);
      }
      return temp;
    } on FileSystemException {
      await _discard(temp);
      rethrow;
    }
  }

  /// The scratch file must already be private when Dart writes config bytes.
  /// Exclusive creation refuses a scratch path already present at open time.
  static void _createOwnerOnly(String path) {
    final nativePath = path.toNativeUtf8();
    try {
      final descriptor = _openFile(
        nativePath,
        _exclusiveWriteCreate,
        _ownerReadWrite,
      );
      if (descriptor < 0) {
        throw FileSystemException(
          'could not create a private config file',
          path,
        );
      }
      final modeResult = _fchmodFile(descriptor, _ownerReadWrite);
      final closeResult = _closeFile(descriptor);
      if (modeResult != 0) {
        throw FileSystemException('could not protect the config file', path);
      }
      if (closeResult != 0) {
        throw FileSystemException(
          'could not close the private config file',
          path,
        );
      }
    } finally {
      calloc.free(nativePath);
    }
  }

  static void _setMode(String path, int mode) {
    final nativePath = path.toNativeUtf8();
    try {
      if (_chmodFile(nativePath, mode) != 0) {
        throw FileSystemException(
          'could not preserve config permissions',
          path,
        );
      }
    } finally {
      calloc.free(nativePath);
    }
  }

  /// Best-effort cleanup: a failed write must not litter the config
  /// directory, but the original failure is the one worth reporting.
  Future<void> _discard(File temp) async {
    try {
      if (temp.existsSync()) {
        await temp.delete();
      }
    } on FileSystemException {
      return;
    }
  }

  static String _encode(AppConfig config, Map<String, String> promptFiles) =>
      '${_encoder.convert(_toJson(config, promptFiles))}\n';

  static Map<String, Object?> _toJson(
    AppConfig config,
    Map<String, String> promptFiles,
  ) => {
    'providers': {
      for (final MapEntry(:key, :value) in config.providers.entries)
        key: {'settings': value.settings},
    },
    'presets': [
      for (final preset in config.presets)
        {
          'id': preset.id,
          'providerId': preset.providerId,
          'model': preset.model,
          'systemPromptFile': _requiredFileName(promptFiles, preset.id),
        },
    ],
    'activePresetId': config.activePresetId,
    'closeBehavior': config.closeBehavior.name,
    'logMaxBytes': config.logMaxBytes,
    'hotkeyBinding': {
      // Enums serialize by .name, never by index, so reordering the enum
      // cannot silently rewrite a stored binding (Consistency Conventions).
      'modifiers': [
        for (final modifier in config.hotkeyBinding.modifiers) modifier.name,
      ],
      'key': config.hotkeyBinding.key,
    },
  };

  /// A config file written by an older build still loads, because nothing here
  /// asks for the `sidecarPath` and `interpreterPath` keys any more: the AD-19
  /// paths have one home, in `providers.<id>.settings`, so the two top-level
  /// keys are simply never read. (Unknown keys were always ignored — this
  /// decoder only ever reads what it names — but that tolerance is what makes
  /// the leftovers *harmless*, not what makes the file load. Dropping a key
  /// `_decode` still required would fail it regardless.)
  Future<({AppConfig config, Map<String, String> promptFiles})> _decode(
    String contents,
  ) async {
    final root = _object(jsonDecode(contents), 'the config file');
    final entries = _presetEntries(root);
    final names = _promptReferences(entries);
    final prompts = <String, String>{};
    for (final name in names.values) {
      prompts[name] = await _readPrompt(name);
    }
    return (config: _configValue(root, entries, prompts), promptFiles: names);
  }

  static AppConfig _configValue(
    Map<String, Object?> root,
    List<Map<String, Object?>> entries,
    Map<String, String> prompts,
  ) => AppConfig(
    providers: _providers(root),
    presets: [for (final entry in entries) _preset(entry, prompts)],
    activePresetId: _string(root, 'activePresetId'),
    hotkeyBinding: _hotkeyBinding(root),
    closeBehavior: _closeBehavior(root),
    logMaxBytes: _logMaxBytes(root),
  );

  Future<String> _readPrompt(String name) async {
    try {
      return utf8.decode(await _promptFile(name).readAsBytes());
    } on IOException {
      throw _ConfigFormatException(
        'systemPromptFile "$name" could not be read',
      );
    } on FormatException {
      throw _ConfigFormatException(
        'systemPromptFile "$name" must contain UTF-8 text',
      );
    }
  }

  static Map<String, String> _promptReferences(
    List<Map<String, Object?>> entries,
  ) {
    final names = <String, String>{};
    for (final entry in entries) {
      if (!entry.containsKey('systemPromptFile')) continue;
      if (entry.containsKey('systemPrompt')) {
        throw _ConfigFormatException(
          'a preset must use either systemPrompt or systemPromptFile, not both',
        );
      }
      final name = _promptFileName(entry);
      if (names.containsValue(name)) {
        throw _ConfigFormatException(
          'preset "${_string(entry, 'id')}" needs its own systemPromptFile',
        );
      }
      names[_string(entry, 'id')] = name;
    }
    return names;
  }

  static String _promptFileName(Map<String, Object?> entry) {
    final name = _string(entry, 'systemPromptFile');
    if (!name.endsWith('.txt') ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\u0000')) {
      throw _ConfigFormatException(
        'systemPromptFile must name a .txt file beside config.json',
      );
    }
    return name;
  }

  static int _logMaxBytes(Map<String, Object?> root) {
    if (!root.containsKey('logMaxBytes')) return AppConfig.defaultLogMaxBytes;
    return switch (root['logMaxBytes']) {
      int value when value >= AppConfig.minimumLogMaxBytes => value,
      _ => throw _ConfigFormatException(
        '"logMaxBytes" must be an integer of at least ${AppConfig.minimumLogMaxBytes}',
      ),
    };
  }

  static CloseBehavior _closeBehavior(Map<String, Object?> root) {
    // Config files from older builds keep the resident daemon behavior.
    if (!root.containsKey('closeBehavior')) return CloseBehavior.closeToTray;
    return switch (root['closeBehavior']) {
      'closeToTray' => CloseBehavior.closeToTray,
      'quit' => CloseBehavior.quit,
      _ => throw _ConfigFormatException(
        '"closeBehavior" must be "closeToTray" or "quit"',
      ),
    };
  }

  static Map<String, ProviderConfig> _providers(Map<String, Object?> root) {
    final providers = _object(root['providers'], '"providers"');
    return {
      for (final MapEntry(:key, :value) in providers.entries)
        key: ProviderConfig(settings: _settings(key, value)),
    };
  }

  static Map<String, String> _settings(String providerId, Object? entry) {
    final provider = _object(entry, 'provider "$providerId"');
    final raw = _object(
      provider['settings'],
      'provider "$providerId" settings',
    );
    final settings = <String, String>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      final scalar = _scalar(value);
      if (scalar == null) {
        throw _ConfigFormatException(
          'provider "$providerId" setting "$key" must be a string, number, '
          'or boolean, found ${_describe(value)}',
        );
      }
      settings[key] = scalar;
    }
    return settings;
  }

  /// Settings are strings on the wire, but CAP-8 invites hand-editing and
  /// `"timeoutMillis": 60000` is the natural thing to type. Discarding the
  /// user's whole config — presets, hotkey and all — over a pair of missing
  /// quotes is a far worse outcome than taking the obvious intent. Objects,
  /// arrays and null still fail, because those have no obvious intent.
  static String? _scalar(Object? value) => switch (value) {
    String() => value,
    num() || bool() => '$value',
    _ => null,
  };

  static List<Map<String, Object?>> _presetEntries(Map<String, Object?> root) {
    final presets = root['presets'];
    if (presets is! List<Object?>) {
      throw _ConfigFormatException(
        '"presets" must be a list, found ${_describe(presets)}',
      );
    }
    return [for (final entry in presets) _object(entry, 'each preset')];
  }

  static Preset _preset(
    Map<String, Object?> entry,
    Map<String, String> prompts,
  ) => Preset(
    id: _string(entry, 'id'),
    providerId: _string(entry, 'providerId'),
    model: _string(entry, 'model'),
    systemPrompt: _systemPrompt(entry, prompts),
  );

  static String _systemPrompt(
    Map<String, Object?> entry,
    Map<String, String> prompts,
  ) {
    if (!entry.containsKey('systemPromptFile')) {
      return _string(entry, 'systemPrompt');
    }
    final prompt = prompts[_string(entry, 'systemPromptFile')];
    if (prompt == null) {
      throw _ConfigFormatException('systemPromptFile could not be resolved');
    }
    return prompt;
  }

  static HotkeyBinding _hotkeyBinding(Map<String, Object?> root) {
    final binding = _object(root['hotkeyBinding'], '"hotkeyBinding"');
    final rawModifiers = binding['modifiers'];
    if (rawModifiers is! List<Object?>) {
      throw _ConfigFormatException(
        '"hotkeyBinding.modifiers" must be a list, found '
        '${_describe(rawModifiers)}',
      );
    }
    final byName = HotkeyModifier.values.asNameMap();
    final modifiers = <HotkeyModifier>{};
    for (final raw in rawModifiers) {
      final modifier = raw is String ? byName[raw] : null;
      if (modifier == null) {
        throw _ConfigFormatException(
          '"hotkeyBinding.modifiers" contains ${_describe(raw)}, which is '
          'not one of ${byName.keys.join(', ')}',
        );
      }
      modifiers.add(modifier);
    }
    return HotkeyBinding(modifiers: modifiers, key: _string(binding, 'key'));
  }

  static Map<String, Object?> _object(Object? value, String field) {
    if (value is! Map<String, Object?>) {
      throw _ConfigFormatException(
        '$field must be a JSON object, found ${_describe(value)}',
      );
    }
    return value;
  }

  static String _string(Map<String, Object?> owner, String field) {
    final value = owner[field];
    if (value is! String) {
      throw _ConfigFormatException(
        '"$field" must be a string, found ${_describe(value)}',
      );
    }
    return value;
  }

  /// Describes an invalid value in the surfaced parser warning without
  /// dumping a nested structure into it. The logged version omits this value.
  static String _describe(Object? value) => switch (value) {
    null => 'nothing',
    String() => '"$value"',
    Map<Object?, Object?>() => 'an object',
    List<Object?>() => 'a list',
    _ => '$value',
  };
}

final class _PreparedWrite {
  const _PreparedWrite(this.target, this.temp, this.previous);

  final File target;
  final File temp;
  final String? previous;
}

/// A structural problem in the config file. Its message is authored solely by
/// this parser, so the surfaced warning can name the invalid field. The log
/// receives a separate generic sentence. This exception never escapes here.
final class _ConfigFormatException implements Exception {
  _ConfigFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
