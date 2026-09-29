// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class Corrections extends Table with TableInfo<Corrections, Correction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Corrections(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _inputTextMeta = const VerificationMeta(
    'inputText',
  );
  late final GeneratedColumn<String> inputText = GeneratedColumn<String>(
    'input_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _presetIdMeta = const VerificationMeta(
    'presetId',
  );
  late final GeneratedColumn<String> presetId = GeneratedColumn<String>(
    'preset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _latencyMsMeta = const VerificationMeta(
    'latencyMs',
  );
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
    'latency_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _failureKindMeta = const VerificationMeta(
    'failureKind',
  );
  late final GeneratedColumn<String> failureKind = GeneratedColumn<String>(
    'failure_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    inputText,
    presetId,
    providerId,
    model,
    latencyMs,
    outcome,
    failureKind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'corrections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Correction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('input_text')) {
      context.handle(
        _inputTextMeta,
        inputText.isAcceptableOrUnknown(data['input_text']!, _inputTextMeta),
      );
    } else if (isInserting) {
      context.missing(_inputTextMeta);
    }
    if (data.containsKey('preset_id')) {
      context.handle(
        _presetIdMeta,
        presetId.isAcceptableOrUnknown(data['preset_id']!, _presetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_presetIdMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('latency_ms')) {
      context.handle(
        _latencyMsMeta,
        latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta),
      );
    } else if (isInserting) {
      context.missing(_latencyMsMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('failure_kind')) {
      context.handle(
        _failureKindMeta,
        failureKind.isAcceptableOrUnknown(
          data['failure_kind']!,
          _failureKindMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Correction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Correction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      inputText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_text'],
      )!,
      presetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset_id'],
      )!,
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      latencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_ms'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      failureKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_kind'],
      ),
    );
  }

  @override
  Corrections createAlias(String alias) {
    return Corrections(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Correction extends DataClass implements Insertable<Correction> {
  final int id;
  final int createdAt;

  /// unix millis, UTC
  final String inputText;

  /// the edited text actually sent (CAP-3)
  final String presetId;
  final String providerId;
  final String model;
  final int latencyMs;
  final String outcome;

  /// 'completed' | 'failed'
  final String? failureKind;
  const Correction({
    required this.id,
    required this.createdAt,
    required this.inputText,
    required this.presetId,
    required this.providerId,
    required this.model,
    required this.latencyMs,
    required this.outcome,
    this.failureKind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['created_at'] = Variable<int>(createdAt);
    map['input_text'] = Variable<String>(inputText);
    map['preset_id'] = Variable<String>(presetId);
    map['provider_id'] = Variable<String>(providerId);
    map['model'] = Variable<String>(model);
    map['latency_ms'] = Variable<int>(latencyMs);
    map['outcome'] = Variable<String>(outcome);
    if (!nullToAbsent || failureKind != null) {
      map['failure_kind'] = Variable<String>(failureKind);
    }
    return map;
  }

  CorrectionsCompanion toCompanion(bool nullToAbsent) {
    return CorrectionsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      inputText: Value(inputText),
      presetId: Value(presetId),
      providerId: Value(providerId),
      model: Value(model),
      latencyMs: Value(latencyMs),
      outcome: Value(outcome),
      failureKind: failureKind == null && nullToAbsent
          ? const Value.absent()
          : Value(failureKind),
    );
  }

  factory Correction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Correction(
      id: serializer.fromJson<int>(json['id']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      inputText: serializer.fromJson<String>(json['input_text']),
      presetId: serializer.fromJson<String>(json['preset_id']),
      providerId: serializer.fromJson<String>(json['provider_id']),
      model: serializer.fromJson<String>(json['model']),
      latencyMs: serializer.fromJson<int>(json['latency_ms']),
      outcome: serializer.fromJson<String>(json['outcome']),
      failureKind: serializer.fromJson<String?>(json['failure_kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'created_at': serializer.toJson<int>(createdAt),
      'input_text': serializer.toJson<String>(inputText),
      'preset_id': serializer.toJson<String>(presetId),
      'provider_id': serializer.toJson<String>(providerId),
      'model': serializer.toJson<String>(model),
      'latency_ms': serializer.toJson<int>(latencyMs),
      'outcome': serializer.toJson<String>(outcome),
      'failure_kind': serializer.toJson<String?>(failureKind),
    };
  }

  Correction copyWith({
    int? id,
    int? createdAt,
    String? inputText,
    String? presetId,
    String? providerId,
    String? model,
    int? latencyMs,
    String? outcome,
    Value<String?> failureKind = const Value.absent(),
  }) => Correction(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    inputText: inputText ?? this.inputText,
    presetId: presetId ?? this.presetId,
    providerId: providerId ?? this.providerId,
    model: model ?? this.model,
    latencyMs: latencyMs ?? this.latencyMs,
    outcome: outcome ?? this.outcome,
    failureKind: failureKind.present ? failureKind.value : this.failureKind,
  );
  Correction copyWithCompanion(CorrectionsCompanion data) {
    return Correction(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      inputText: data.inputText.present ? data.inputText.value : this.inputText,
      presetId: data.presetId.present ? data.presetId.value : this.presetId,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      model: data.model.present ? data.model.value : this.model,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      failureKind: data.failureKind.present
          ? data.failureKind.value
          : this.failureKind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Correction(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('inputText: $inputText, ')
          ..write('presetId: $presetId, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('outcome: $outcome, ')
          ..write('failureKind: $failureKind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    inputText,
    presetId,
    providerId,
    model,
    latencyMs,
    outcome,
    failureKind,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Correction &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.inputText == this.inputText &&
          other.presetId == this.presetId &&
          other.providerId == this.providerId &&
          other.model == this.model &&
          other.latencyMs == this.latencyMs &&
          other.outcome == this.outcome &&
          other.failureKind == this.failureKind);
}

class CorrectionsCompanion extends UpdateCompanion<Correction> {
  final Value<int> id;
  final Value<int> createdAt;
  final Value<String> inputText;
  final Value<String> presetId;
  final Value<String> providerId;
  final Value<String> model;
  final Value<int> latencyMs;
  final Value<String> outcome;
  final Value<String?> failureKind;
  const CorrectionsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.inputText = const Value.absent(),
    this.presetId = const Value.absent(),
    this.providerId = const Value.absent(),
    this.model = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.outcome = const Value.absent(),
    this.failureKind = const Value.absent(),
  });
  CorrectionsCompanion.insert({
    this.id = const Value.absent(),
    required int createdAt,
    required String inputText,
    required String presetId,
    required String providerId,
    required String model,
    required int latencyMs,
    required String outcome,
    this.failureKind = const Value.absent(),
  }) : createdAt = Value(createdAt),
       inputText = Value(inputText),
       presetId = Value(presetId),
       providerId = Value(providerId),
       model = Value(model),
       latencyMs = Value(latencyMs),
       outcome = Value(outcome);
  static Insertable<Correction> custom({
    Expression<int>? id,
    Expression<int>? createdAt,
    Expression<String>? inputText,
    Expression<String>? presetId,
    Expression<String>? providerId,
    Expression<String>? model,
    Expression<int>? latencyMs,
    Expression<String>? outcome,
    Expression<String>? failureKind,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (inputText != null) 'input_text': inputText,
      if (presetId != null) 'preset_id': presetId,
      if (providerId != null) 'provider_id': providerId,
      if (model != null) 'model': model,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (outcome != null) 'outcome': outcome,
      if (failureKind != null) 'failure_kind': failureKind,
    });
  }

  CorrectionsCompanion copyWith({
    Value<int>? id,
    Value<int>? createdAt,
    Value<String>? inputText,
    Value<String>? presetId,
    Value<String>? providerId,
    Value<String>? model,
    Value<int>? latencyMs,
    Value<String>? outcome,
    Value<String?>? failureKind,
  }) {
    return CorrectionsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      inputText: inputText ?? this.inputText,
      presetId: presetId ?? this.presetId,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      latencyMs: latencyMs ?? this.latencyMs,
      outcome: outcome ?? this.outcome,
      failureKind: failureKind ?? this.failureKind,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (inputText.present) {
      map['input_text'] = Variable<String>(inputText.value);
    }
    if (presetId.present) {
      map['preset_id'] = Variable<String>(presetId.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (failureKind.present) {
      map['failure_kind'] = Variable<String>(failureKind.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CorrectionsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('inputText: $inputText, ')
          ..write('presetId: $presetId, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('outcome: $outcome, ')
          ..write('failureKind: $failureKind')
          ..write(')'))
        .toString();
  }
}

class Suggestions extends Table with TableInfo<Suggestions, Suggestion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Suggestions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _correctionIdMeta = const VerificationMeta(
    'correctionId',
  );
  late final GeneratedColumn<int> correctionId = GeneratedColumn<int>(
    'correction_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES corrections(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _registerMeta = const VerificationMeta(
    'register',
  );
  late final GeneratedColumn<String> register = GeneratedColumn<String>(
    'register',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _suggestionTextMeta = const VerificationMeta(
    'suggestionText',
  );
  late final GeneratedColumn<String> suggestionText = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    correctionId,
    register,
    suggestionText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'suggestions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Suggestion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('correction_id')) {
      context.handle(
        _correctionIdMeta,
        correctionId.isAcceptableOrUnknown(
          data['correction_id']!,
          _correctionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_correctionIdMeta);
    }
    if (data.containsKey('register')) {
      context.handle(
        _registerMeta,
        register.isAcceptableOrUnknown(data['register']!, _registerMeta),
      );
    } else if (isInserting) {
      context.missing(_registerMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _suggestionTextMeta,
        suggestionText.isAcceptableOrUnknown(
          data['text']!,
          _suggestionTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_suggestionTextMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {correctionId, register};
  @override
  Suggestion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Suggestion(
      correctionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}correction_id'],
      )!,
      register: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}register'],
      )!,
      suggestionText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
    );
  }

  @override
  Suggestions createAlias(String alias) {
    return Suggestions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(correction_id, register)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Suggestion extends DataClass implements Insertable<Suggestion> {
  final int correctionId;
  final String register;

  /// SuggestionRegister.name
  final String suggestionText;
  const Suggestion({
    required this.correctionId,
    required this.register,
    required this.suggestionText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['correction_id'] = Variable<int>(correctionId);
    map['register'] = Variable<String>(register);
    map['text'] = Variable<String>(suggestionText);
    return map;
  }

  SuggestionsCompanion toCompanion(bool nullToAbsent) {
    return SuggestionsCompanion(
      correctionId: Value(correctionId),
      register: Value(register),
      suggestionText: Value(suggestionText),
    );
  }

  factory Suggestion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Suggestion(
      correctionId: serializer.fromJson<int>(json['correction_id']),
      register: serializer.fromJson<String>(json['register']),
      suggestionText: serializer.fromJson<String>(json['text']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'correction_id': serializer.toJson<int>(correctionId),
      'register': serializer.toJson<String>(register),
      'text': serializer.toJson<String>(suggestionText),
    };
  }

  Suggestion copyWith({
    int? correctionId,
    String? register,
    String? suggestionText,
  }) => Suggestion(
    correctionId: correctionId ?? this.correctionId,
    register: register ?? this.register,
    suggestionText: suggestionText ?? this.suggestionText,
  );
  Suggestion copyWithCompanion(SuggestionsCompanion data) {
    return Suggestion(
      correctionId: data.correctionId.present
          ? data.correctionId.value
          : this.correctionId,
      register: data.register.present ? data.register.value : this.register,
      suggestionText: data.suggestionText.present
          ? data.suggestionText.value
          : this.suggestionText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Suggestion(')
          ..write('correctionId: $correctionId, ')
          ..write('register: $register, ')
          ..write('suggestionText: $suggestionText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(correctionId, register, suggestionText);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Suggestion &&
          other.correctionId == this.correctionId &&
          other.register == this.register &&
          other.suggestionText == this.suggestionText);
}

class SuggestionsCompanion extends UpdateCompanion<Suggestion> {
  final Value<int> correctionId;
  final Value<String> register;
  final Value<String> suggestionText;
  final Value<int> rowid;
  const SuggestionsCompanion({
    this.correctionId = const Value.absent(),
    this.register = const Value.absent(),
    this.suggestionText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SuggestionsCompanion.insert({
    required int correctionId,
    required String register,
    required String suggestionText,
    this.rowid = const Value.absent(),
  }) : correctionId = Value(correctionId),
       register = Value(register),
       suggestionText = Value(suggestionText);
  static Insertable<Suggestion> custom({
    Expression<int>? correctionId,
    Expression<String>? register,
    Expression<String>? suggestionText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (correctionId != null) 'correction_id': correctionId,
      if (register != null) 'register': register,
      if (suggestionText != null) 'text': suggestionText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SuggestionsCompanion copyWith({
    Value<int>? correctionId,
    Value<String>? register,
    Value<String>? suggestionText,
    Value<int>? rowid,
  }) {
    return SuggestionsCompanion(
      correctionId: correctionId ?? this.correctionId,
      register: register ?? this.register,
      suggestionText: suggestionText ?? this.suggestionText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (correctionId.present) {
      map['correction_id'] = Variable<int>(correctionId.value);
    }
    if (register.present) {
      map['register'] = Variable<String>(register.value);
    }
    if (suggestionText.present) {
      map['text'] = Variable<String>(suggestionText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SuggestionsCompanion(')
          ..write('correctionId: $correctionId, ')
          ..write('register: $register, ')
          ..write('suggestionText: $suggestionText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final Corrections corrections = Corrections(this);
  late final Suggestions suggestions = Suggestions(this);
  late final Index correctionsCreatedAtIdx = Index(
    'corrections_created_at_idx',
    'CREATE INDEX corrections_created_at_idx ON corrections (created_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    corrections,
    suggestions,
    correctionsCreatedAtIdx,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'corrections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('suggestions', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $CorrectionsCreateCompanionBuilder =
    CorrectionsCompanion Function({
      Value<int> id,
      required int createdAt,
      required String inputText,
      required String presetId,
      required String providerId,
      required String model,
      required int latencyMs,
      required String outcome,
      Value<String?> failureKind,
    });
typedef $CorrectionsUpdateCompanionBuilder =
    CorrectionsCompanion Function({
      Value<int> id,
      Value<int> createdAt,
      Value<String> inputText,
      Value<String> presetId,
      Value<String> providerId,
      Value<String> model,
      Value<int> latencyMs,
      Value<String> outcome,
      Value<String?> failureKind,
    });

final class $CorrectionsReferences
    extends BaseReferences<_$AppDatabase, Corrections, Correction> {
  $CorrectionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<Suggestions, List<Suggestion>>
  _suggestionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.suggestions,
    aliasName: 'corrections__id__suggestions__correction_id',
  );

  $SuggestionsProcessedTableManager get suggestionsRefs {
    final manager = $SuggestionsTableManager(
      $_db,
      $_db.suggestions,
    ).filter((f) => f.correctionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_suggestionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $CorrectionsFilterComposer extends Composer<_$AppDatabase, Corrections> {
  $CorrectionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputText => $composableBuilder(
    column: $table.inputText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureKind => $composableBuilder(
    column: $table.failureKind,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> suggestionsRefs(
    Expression<bool> Function($SuggestionsFilterComposer f) f,
  ) {
    final $SuggestionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.suggestions,
      getReferencedColumn: (t) => t.correctionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SuggestionsFilterComposer(
            $db: $db,
            $table: $db.suggestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $CorrectionsOrderingComposer
    extends Composer<_$AppDatabase, Corrections> {
  $CorrectionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputText => $composableBuilder(
    column: $table.inputText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureKind => $composableBuilder(
    column: $table.failureKind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $CorrectionsAnnotationComposer
    extends Composer<_$AppDatabase, Corrections> {
  $CorrectionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get inputText =>
      $composableBuilder(column: $table.inputText, builder: (column) => column);

  GeneratedColumn<String> get presetId =>
      $composableBuilder(column: $table.presetId, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get failureKind => $composableBuilder(
    column: $table.failureKind,
    builder: (column) => column,
  );

  Expression<T> suggestionsRefs<T extends Object>(
    Expression<T> Function($SuggestionsAnnotationComposer a) f,
  ) {
    final $SuggestionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.suggestions,
      getReferencedColumn: (t) => t.correctionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SuggestionsAnnotationComposer(
            $db: $db,
            $table: $db.suggestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $CorrectionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Corrections,
          Correction,
          $CorrectionsFilterComposer,
          $CorrectionsOrderingComposer,
          $CorrectionsAnnotationComposer,
          $CorrectionsCreateCompanionBuilder,
          $CorrectionsUpdateCompanionBuilder,
          (Correction, $CorrectionsReferences),
          Correction,
          PrefetchHooks Function({bool suggestionsRefs})
        > {
  $CorrectionsTableManager(_$AppDatabase db, Corrections table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $CorrectionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $CorrectionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $CorrectionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> inputText = const Value.absent(),
                Value<String> presetId = const Value.absent(),
                Value<String> providerId = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> latencyMs = const Value.absent(),
                Value<String> outcome = const Value.absent(),
                Value<String?> failureKind = const Value.absent(),
              }) => CorrectionsCompanion(
                id: id,
                createdAt: createdAt,
                inputText: inputText,
                presetId: presetId,
                providerId: providerId,
                model: model,
                latencyMs: latencyMs,
                outcome: outcome,
                failureKind: failureKind,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int createdAt,
                required String inputText,
                required String presetId,
                required String providerId,
                required String model,
                required int latencyMs,
                required String outcome,
                Value<String?> failureKind = const Value.absent(),
              }) => CorrectionsCompanion.insert(
                id: id,
                createdAt: createdAt,
                inputText: inputText,
                presetId: presetId,
                providerId: providerId,
                model: model,
                latencyMs: latencyMs,
                outcome: outcome,
                failureKind: failureKind,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $CorrectionsReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({suggestionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (suggestionsRefs) db.suggestions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (suggestionsRefs)
                    await $_getPrefetchedData<
                      Correction,
                      Corrections,
                      Suggestion
                    >(
                      currentTable: table,
                      referencedTable: $CorrectionsReferences
                          ._suggestionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $CorrectionsReferences(db, table, p0).suggestionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.correctionId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $CorrectionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Corrections,
      Correction,
      $CorrectionsFilterComposer,
      $CorrectionsOrderingComposer,
      $CorrectionsAnnotationComposer,
      $CorrectionsCreateCompanionBuilder,
      $CorrectionsUpdateCompanionBuilder,
      (Correction, $CorrectionsReferences),
      Correction,
      PrefetchHooks Function({bool suggestionsRefs})
    >;
typedef $SuggestionsCreateCompanionBuilder =
    SuggestionsCompanion Function({
      required int correctionId,
      required String register,
      required String suggestionText,
      Value<int> rowid,
    });
typedef $SuggestionsUpdateCompanionBuilder =
    SuggestionsCompanion Function({
      Value<int> correctionId,
      Value<String> register,
      Value<String> suggestionText,
      Value<int> rowid,
    });

final class $SuggestionsReferences
    extends BaseReferences<_$AppDatabase, Suggestions, Suggestion> {
  $SuggestionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Corrections _correctionIdTable(_$AppDatabase db) =>
      db.corrections.createAlias('suggestions__correction_id__corrections__id');

  $CorrectionsProcessedTableManager get correctionId {
    final $_column = $_itemColumn<int>('correction_id')!;

    final manager = $CorrectionsTableManager(
      $_db,
      $_db.corrections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_correctionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $SuggestionsFilterComposer extends Composer<_$AppDatabase, Suggestions> {
  $SuggestionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get register => $composableBuilder(
    column: $table.register,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestionText => $composableBuilder(
    column: $table.suggestionText,
    builder: (column) => ColumnFilters(column),
  );

  $CorrectionsFilterComposer get correctionId {
    final $CorrectionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.correctionId,
      referencedTable: $db.corrections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CorrectionsFilterComposer(
            $db: $db,
            $table: $db.corrections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SuggestionsOrderingComposer
    extends Composer<_$AppDatabase, Suggestions> {
  $SuggestionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get register => $composableBuilder(
    column: $table.register,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestionText => $composableBuilder(
    column: $table.suggestionText,
    builder: (column) => ColumnOrderings(column),
  );

  $CorrectionsOrderingComposer get correctionId {
    final $CorrectionsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.correctionId,
      referencedTable: $db.corrections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CorrectionsOrderingComposer(
            $db: $db,
            $table: $db.corrections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SuggestionsAnnotationComposer
    extends Composer<_$AppDatabase, Suggestions> {
  $SuggestionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get register =>
      $composableBuilder(column: $table.register, builder: (column) => column);

  GeneratedColumn<String> get suggestionText => $composableBuilder(
    column: $table.suggestionText,
    builder: (column) => column,
  );

  $CorrectionsAnnotationComposer get correctionId {
    final $CorrectionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.correctionId,
      referencedTable: $db.corrections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $CorrectionsAnnotationComposer(
            $db: $db,
            $table: $db.corrections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SuggestionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Suggestions,
          Suggestion,
          $SuggestionsFilterComposer,
          $SuggestionsOrderingComposer,
          $SuggestionsAnnotationComposer,
          $SuggestionsCreateCompanionBuilder,
          $SuggestionsUpdateCompanionBuilder,
          (Suggestion, $SuggestionsReferences),
          Suggestion,
          PrefetchHooks Function({bool correctionId})
        > {
  $SuggestionsTableManager(_$AppDatabase db, Suggestions table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SuggestionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SuggestionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SuggestionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> correctionId = const Value.absent(),
                Value<String> register = const Value.absent(),
                Value<String> suggestionText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuggestionsCompanion(
                correctionId: correctionId,
                register: register,
                suggestionText: suggestionText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int correctionId,
                required String register,
                required String suggestionText,
                Value<int> rowid = const Value.absent(),
              }) => SuggestionsCompanion.insert(
                correctionId: correctionId,
                register: register,
                suggestionText: suggestionText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $SuggestionsReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({correctionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (correctionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.correctionId,
                                referencedTable: $SuggestionsReferences
                                    ._correctionIdTable(db),
                                referencedColumn: $SuggestionsReferences
                                    ._correctionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $SuggestionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Suggestions,
      Suggestion,
      $SuggestionsFilterComposer,
      $SuggestionsOrderingComposer,
      $SuggestionsAnnotationComposer,
      $SuggestionsCreateCompanionBuilder,
      $SuggestionsUpdateCompanionBuilder,
      (Suggestion, $SuggestionsReferences),
      Suggestion,
      PrefetchHooks Function({bool correctionId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $CorrectionsTableManager get corrections =>
      $CorrectionsTableManager(_db, _db.corrections);
  $SuggestionsTableManager get suggestions =>
      $SuggestionsTableManager(_db, _db.suggestions);
}
