// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $NodesTable extends Nodes with TableInfo<$NodesTable, Node> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<int> nodeId = GeneratedColumn<int>(
      'node_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _longNameMeta =
      const VerificationMeta('longName');
  @override
  late final GeneratedColumn<String> longName = GeneratedColumn<String>(
      'long_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _shortNameMeta =
      const VerificationMeta('shortName');
  @override
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
      'short_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _userLabelMeta =
      const VerificationMeta('userLabel');
  @override
  late final GeneratedColumn<String> userLabel = GeneratedColumn<String>(
      'user_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hwModelMeta =
      const VerificationMeta('hwModel');
  @override
  late final GeneratedColumn<String> hwModel = GeneratedColumn<String>(
      'hw_model', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _firstSeenAtMeta =
      const VerificationMeta('firstSeenAt');
  @override
  late final GeneratedColumn<DateTime> firstSeenAt = GeneratedColumn<DateTime>(
      'first_seen_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastHeardAtMeta =
      const VerificationMeta('lastHeardAt');
  @override
  late final GeneratedColumn<DateTime> lastHeardAt = GeneratedColumn<DateTime>(
      'last_heard_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastLatMeta =
      const VerificationMeta('lastLat');
  @override
  late final GeneratedColumn<double> lastLat = GeneratedColumn<double>(
      'last_lat', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _lastLonMeta =
      const VerificationMeta('lastLon');
  @override
  late final GeneratedColumn<double> lastLon = GeneratedColumn<double>(
      'last_lon', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        nodeId,
        longName,
        shortName,
        userLabel,
        hwModel,
        firstSeenAt,
        lastHeardAt,
        lastLat,
        lastLon
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nodes';
  @override
  VerificationContext validateIntegrity(Insertable<Node> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('node_id')) {
      context.handle(_nodeIdMeta,
          nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta));
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('long_name')) {
      context.handle(_longNameMeta,
          longName.isAcceptableOrUnknown(data['long_name']!, _longNameMeta));
    }
    if (data.containsKey('short_name')) {
      context.handle(_shortNameMeta,
          shortName.isAcceptableOrUnknown(data['short_name']!, _shortNameMeta));
    }
    if (data.containsKey('user_label')) {
      context.handle(_userLabelMeta,
          userLabel.isAcceptableOrUnknown(data['user_label']!, _userLabelMeta));
    }
    if (data.containsKey('hw_model')) {
      context.handle(_hwModelMeta,
          hwModel.isAcceptableOrUnknown(data['hw_model']!, _hwModelMeta));
    }
    if (data.containsKey('first_seen_at')) {
      context.handle(
          _firstSeenAtMeta,
          firstSeenAt.isAcceptableOrUnknown(
              data['first_seen_at']!, _firstSeenAtMeta));
    } else if (isInserting) {
      context.missing(_firstSeenAtMeta);
    }
    if (data.containsKey('last_heard_at')) {
      context.handle(
          _lastHeardAtMeta,
          lastHeardAt.isAcceptableOrUnknown(
              data['last_heard_at']!, _lastHeardAtMeta));
    } else if (isInserting) {
      context.missing(_lastHeardAtMeta);
    }
    if (data.containsKey('last_lat')) {
      context.handle(_lastLatMeta,
          lastLat.isAcceptableOrUnknown(data['last_lat']!, _lastLatMeta));
    }
    if (data.containsKey('last_lon')) {
      context.handle(_lastLonMeta,
          lastLon.isAcceptableOrUnknown(data['last_lon']!, _lastLonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Node map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Node(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      nodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}node_id'])!,
      longName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}long_name'])!,
      shortName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}short_name'])!,
      userLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_label']),
      hwModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hw_model'])!,
      firstSeenAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}first_seen_at'])!,
      lastHeardAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_heard_at'])!,
      lastLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}last_lat']),
      lastLon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}last_lon']),
    );
  }

  @override
  $NodesTable createAlias(String alias) {
    return $NodesTable(attachedDatabase, alias);
  }
}

class Node extends DataClass implements Insertable<Node> {
  final int id;
  final int nodeId;
  final String longName;
  final String shortName;
  final String? userLabel;
  final String hwModel;
  final DateTime firstSeenAt;
  final DateTime lastHeardAt;
  final double? lastLat;
  final double? lastLon;
  const Node(
      {required this.id,
      required this.nodeId,
      required this.longName,
      required this.shortName,
      this.userLabel,
      required this.hwModel,
      required this.firstSeenAt,
      required this.lastHeardAt,
      this.lastLat,
      this.lastLon});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['node_id'] = Variable<int>(nodeId);
    map['long_name'] = Variable<String>(longName);
    map['short_name'] = Variable<String>(shortName);
    if (!nullToAbsent || userLabel != null) {
      map['user_label'] = Variable<String>(userLabel);
    }
    map['hw_model'] = Variable<String>(hwModel);
    map['first_seen_at'] = Variable<DateTime>(firstSeenAt);
    map['last_heard_at'] = Variable<DateTime>(lastHeardAt);
    if (!nullToAbsent || lastLat != null) {
      map['last_lat'] = Variable<double>(lastLat);
    }
    if (!nullToAbsent || lastLon != null) {
      map['last_lon'] = Variable<double>(lastLon);
    }
    return map;
  }

  NodesCompanion toCompanion(bool nullToAbsent) {
    return NodesCompanion(
      id: Value(id),
      nodeId: Value(nodeId),
      longName: Value(longName),
      shortName: Value(shortName),
      userLabel: userLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(userLabel),
      hwModel: Value(hwModel),
      firstSeenAt: Value(firstSeenAt),
      lastHeardAt: Value(lastHeardAt),
      lastLat: lastLat == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLat),
      lastLon: lastLon == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLon),
    );
  }

  factory Node.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Node(
      id: serializer.fromJson<int>(json['id']),
      nodeId: serializer.fromJson<int>(json['nodeId']),
      longName: serializer.fromJson<String>(json['longName']),
      shortName: serializer.fromJson<String>(json['shortName']),
      userLabel: serializer.fromJson<String?>(json['userLabel']),
      hwModel: serializer.fromJson<String>(json['hwModel']),
      firstSeenAt: serializer.fromJson<DateTime>(json['firstSeenAt']),
      lastHeardAt: serializer.fromJson<DateTime>(json['lastHeardAt']),
      lastLat: serializer.fromJson<double?>(json['lastLat']),
      lastLon: serializer.fromJson<double?>(json['lastLon']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'nodeId': serializer.toJson<int>(nodeId),
      'longName': serializer.toJson<String>(longName),
      'shortName': serializer.toJson<String>(shortName),
      'userLabel': serializer.toJson<String?>(userLabel),
      'hwModel': serializer.toJson<String>(hwModel),
      'firstSeenAt': serializer.toJson<DateTime>(firstSeenAt),
      'lastHeardAt': serializer.toJson<DateTime>(lastHeardAt),
      'lastLat': serializer.toJson<double?>(lastLat),
      'lastLon': serializer.toJson<double?>(lastLon),
    };
  }

  Node copyWith(
          {int? id,
          int? nodeId,
          String? longName,
          String? shortName,
          Value<String?> userLabel = const Value.absent(),
          String? hwModel,
          DateTime? firstSeenAt,
          DateTime? lastHeardAt,
          Value<double?> lastLat = const Value.absent(),
          Value<double?> lastLon = const Value.absent()}) =>
      Node(
        id: id ?? this.id,
        nodeId: nodeId ?? this.nodeId,
        longName: longName ?? this.longName,
        shortName: shortName ?? this.shortName,
        userLabel: userLabel.present ? userLabel.value : this.userLabel,
        hwModel: hwModel ?? this.hwModel,
        firstSeenAt: firstSeenAt ?? this.firstSeenAt,
        lastHeardAt: lastHeardAt ?? this.lastHeardAt,
        lastLat: lastLat.present ? lastLat.value : this.lastLat,
        lastLon: lastLon.present ? lastLon.value : this.lastLon,
      );
  Node copyWithCompanion(NodesCompanion data) {
    return Node(
      id: data.id.present ? data.id.value : this.id,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      longName: data.longName.present ? data.longName.value : this.longName,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      userLabel: data.userLabel.present ? data.userLabel.value : this.userLabel,
      hwModel: data.hwModel.present ? data.hwModel.value : this.hwModel,
      firstSeenAt:
          data.firstSeenAt.present ? data.firstSeenAt.value : this.firstSeenAt,
      lastHeardAt:
          data.lastHeardAt.present ? data.lastHeardAt.value : this.lastHeardAt,
      lastLat: data.lastLat.present ? data.lastLat.value : this.lastLat,
      lastLon: data.lastLon.present ? data.lastLon.value : this.lastLon,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Node(')
          ..write('id: $id, ')
          ..write('nodeId: $nodeId, ')
          ..write('longName: $longName, ')
          ..write('shortName: $shortName, ')
          ..write('userLabel: $userLabel, ')
          ..write('hwModel: $hwModel, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastHeardAt: $lastHeardAt, ')
          ..write('lastLat: $lastLat, ')
          ..write('lastLon: $lastLon')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, nodeId, longName, shortName, userLabel,
      hwModel, firstSeenAt, lastHeardAt, lastLat, lastLon);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Node &&
          other.id == this.id &&
          other.nodeId == this.nodeId &&
          other.longName == this.longName &&
          other.shortName == this.shortName &&
          other.userLabel == this.userLabel &&
          other.hwModel == this.hwModel &&
          other.firstSeenAt == this.firstSeenAt &&
          other.lastHeardAt == this.lastHeardAt &&
          other.lastLat == this.lastLat &&
          other.lastLon == this.lastLon);
}

class NodesCompanion extends UpdateCompanion<Node> {
  final Value<int> id;
  final Value<int> nodeId;
  final Value<String> longName;
  final Value<String> shortName;
  final Value<String?> userLabel;
  final Value<String> hwModel;
  final Value<DateTime> firstSeenAt;
  final Value<DateTime> lastHeardAt;
  final Value<double?> lastLat;
  final Value<double?> lastLon;
  const NodesCompanion({
    this.id = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.longName = const Value.absent(),
    this.shortName = const Value.absent(),
    this.userLabel = const Value.absent(),
    this.hwModel = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.lastHeardAt = const Value.absent(),
    this.lastLat = const Value.absent(),
    this.lastLon = const Value.absent(),
  });
  NodesCompanion.insert({
    this.id = const Value.absent(),
    required int nodeId,
    this.longName = const Value.absent(),
    this.shortName = const Value.absent(),
    this.userLabel = const Value.absent(),
    this.hwModel = const Value.absent(),
    required DateTime firstSeenAt,
    required DateTime lastHeardAt,
    this.lastLat = const Value.absent(),
    this.lastLon = const Value.absent(),
  })  : nodeId = Value(nodeId),
        firstSeenAt = Value(firstSeenAt),
        lastHeardAt = Value(lastHeardAt);
  static Insertable<Node> custom({
    Expression<int>? id,
    Expression<int>? nodeId,
    Expression<String>? longName,
    Expression<String>? shortName,
    Expression<String>? userLabel,
    Expression<String>? hwModel,
    Expression<DateTime>? firstSeenAt,
    Expression<DateTime>? lastHeardAt,
    Expression<double>? lastLat,
    Expression<double>? lastLon,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nodeId != null) 'node_id': nodeId,
      if (longName != null) 'long_name': longName,
      if (shortName != null) 'short_name': shortName,
      if (userLabel != null) 'user_label': userLabel,
      if (hwModel != null) 'hw_model': hwModel,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (lastHeardAt != null) 'last_heard_at': lastHeardAt,
      if (lastLat != null) 'last_lat': lastLat,
      if (lastLon != null) 'last_lon': lastLon,
    });
  }

  NodesCompanion copyWith(
      {Value<int>? id,
      Value<int>? nodeId,
      Value<String>? longName,
      Value<String>? shortName,
      Value<String?>? userLabel,
      Value<String>? hwModel,
      Value<DateTime>? firstSeenAt,
      Value<DateTime>? lastHeardAt,
      Value<double?>? lastLat,
      Value<double?>? lastLon}) {
    return NodesCompanion(
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      longName: longName ?? this.longName,
      shortName: shortName ?? this.shortName,
      userLabel: userLabel ?? this.userLabel,
      hwModel: hwModel ?? this.hwModel,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastHeardAt: lastHeardAt ?? this.lastHeardAt,
      lastLat: lastLat ?? this.lastLat,
      lastLon: lastLon ?? this.lastLon,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<int>(nodeId.value);
    }
    if (longName.present) {
      map['long_name'] = Variable<String>(longName.value);
    }
    if (shortName.present) {
      map['short_name'] = Variable<String>(shortName.value);
    }
    if (userLabel.present) {
      map['user_label'] = Variable<String>(userLabel.value);
    }
    if (hwModel.present) {
      map['hw_model'] = Variable<String>(hwModel.value);
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<DateTime>(firstSeenAt.value);
    }
    if (lastHeardAt.present) {
      map['last_heard_at'] = Variable<DateTime>(lastHeardAt.value);
    }
    if (lastLat.present) {
      map['last_lat'] = Variable<double>(lastLat.value);
    }
    if (lastLon.present) {
      map['last_lon'] = Variable<double>(lastLon.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodesCompanion(')
          ..write('id: $id, ')
          ..write('nodeId: $nodeId, ')
          ..write('longName: $longName, ')
          ..write('shortName: $shortName, ')
          ..write('userLabel: $userLabel, ')
          ..write('hwModel: $hwModel, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('lastHeardAt: $lastHeardAt, ')
          ..write('lastLat: $lastLat, ')
          ..write('lastLon: $lastLon')
          ..write(')'))
        .toString();
  }
}

class $CoverageMapsTable extends CoverageMaps
    with TableInfo<$CoverageMapsTable, CoverageMap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoverageMapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baseNodeIdMeta =
      const VerificationMeta('baseNodeId');
  @override
  late final GeneratedColumn<int> baseNodeId = GeneratedColumn<int>(
      'base_node_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES nodes (id)'));
  static const VerificationMeta _baseLatMeta =
      const VerificationMeta('baseLat');
  @override
  late final GeneratedColumn<double> baseLat = GeneratedColumn<double>(
      'base_lat', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _baseLonMeta =
      const VerificationMeta('baseLon');
  @override
  late final GeneratedColumn<double> baseLon = GeneratedColumn<double>(
      'base_lon', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _colorMetricMeta =
      const VerificationMeta('colorMetric');
  @override
  late final GeneratedColumn<String> colorMetric = GeneratedColumn<String>(
      'color_metric', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('snr'));
  static const VerificationMeta _signalDirectionMeta =
      const VerificationMeta('signalDirection');
  @override
  late final GeneratedColumn<String> signalDirection = GeneratedColumn<String>(
      'signal_direction', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('rx'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        baseNodeId,
        baseLat,
        baseLon,
        createdAt,
        description,
        colorMetric,
        signalDirection
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'coverage_maps';
  @override
  VerificationContext validateIntegrity(Insertable<CoverageMap> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_node_id')) {
      context.handle(
          _baseNodeIdMeta,
          baseNodeId.isAcceptableOrUnknown(
              data['base_node_id']!, _baseNodeIdMeta));
    }
    if (data.containsKey('base_lat')) {
      context.handle(_baseLatMeta,
          baseLat.isAcceptableOrUnknown(data['base_lat']!, _baseLatMeta));
    }
    if (data.containsKey('base_lon')) {
      context.handle(_baseLonMeta,
          baseLon.isAcceptableOrUnknown(data['base_lon']!, _baseLonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('color_metric')) {
      context.handle(
          _colorMetricMeta,
          colorMetric.isAcceptableOrUnknown(
              data['color_metric']!, _colorMetricMeta));
    }
    if (data.containsKey('signal_direction')) {
      context.handle(
          _signalDirectionMeta,
          signalDirection.isAcceptableOrUnknown(
              data['signal_direction']!, _signalDirectionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoverageMap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoverageMap(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      baseNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_node_id']),
      baseLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}base_lat']),
      baseLon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}base_lon']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      colorMetric: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_metric'])!,
      signalDirection: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}signal_direction'])!,
    );
  }

  @override
  $CoverageMapsTable createAlias(String alias) {
    return $CoverageMapsTable(attachedDatabase, alias);
  }
}

class CoverageMap extends DataClass implements Insertable<CoverageMap> {
  final int id;
  final String name;

  /// Base radio of maps made before schema v8. A map is a place; the base
  /// radio belongs to each session (`Sessions.baseNodeId`), so new maps
  /// leave this null. Old sessions without their own base fall back to it.
  final int? baseNodeId;

  /// Where the base stands for this map (schema v8). Null until known.
  final double? baseLat;
  final double? baseLon;
  final DateTime createdAt;
  final String description;
  final String colorMetric;
  final String signalDirection;
  const CoverageMap(
      {required this.id,
      required this.name,
      this.baseNodeId,
      this.baseLat,
      this.baseLon,
      required this.createdAt,
      required this.description,
      required this.colorMetric,
      required this.signalDirection});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || baseNodeId != null) {
      map['base_node_id'] = Variable<int>(baseNodeId);
    }
    if (!nullToAbsent || baseLat != null) {
      map['base_lat'] = Variable<double>(baseLat);
    }
    if (!nullToAbsent || baseLon != null) {
      map['base_lon'] = Variable<double>(baseLon);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['description'] = Variable<String>(description);
    map['color_metric'] = Variable<String>(colorMetric);
    map['signal_direction'] = Variable<String>(signalDirection);
    return map;
  }

  CoverageMapsCompanion toCompanion(bool nullToAbsent) {
    return CoverageMapsCompanion(
      id: Value(id),
      name: Value(name),
      baseNodeId: baseNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(baseNodeId),
      baseLat: baseLat == null && nullToAbsent
          ? const Value.absent()
          : Value(baseLat),
      baseLon: baseLon == null && nullToAbsent
          ? const Value.absent()
          : Value(baseLon),
      createdAt: Value(createdAt),
      description: Value(description),
      colorMetric: Value(colorMetric),
      signalDirection: Value(signalDirection),
    );
  }

  factory CoverageMap.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoverageMap(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      baseNodeId: serializer.fromJson<int?>(json['baseNodeId']),
      baseLat: serializer.fromJson<double?>(json['baseLat']),
      baseLon: serializer.fromJson<double?>(json['baseLon']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      description: serializer.fromJson<String>(json['description']),
      colorMetric: serializer.fromJson<String>(json['colorMetric']),
      signalDirection: serializer.fromJson<String>(json['signalDirection']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'baseNodeId': serializer.toJson<int?>(baseNodeId),
      'baseLat': serializer.toJson<double?>(baseLat),
      'baseLon': serializer.toJson<double?>(baseLon),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'description': serializer.toJson<String>(description),
      'colorMetric': serializer.toJson<String>(colorMetric),
      'signalDirection': serializer.toJson<String>(signalDirection),
    };
  }

  CoverageMap copyWith(
          {int? id,
          String? name,
          Value<int?> baseNodeId = const Value.absent(),
          Value<double?> baseLat = const Value.absent(),
          Value<double?> baseLon = const Value.absent(),
          DateTime? createdAt,
          String? description,
          String? colorMetric,
          String? signalDirection}) =>
      CoverageMap(
        id: id ?? this.id,
        name: name ?? this.name,
        baseNodeId: baseNodeId.present ? baseNodeId.value : this.baseNodeId,
        baseLat: baseLat.present ? baseLat.value : this.baseLat,
        baseLon: baseLon.present ? baseLon.value : this.baseLon,
        createdAt: createdAt ?? this.createdAt,
        description: description ?? this.description,
        colorMetric: colorMetric ?? this.colorMetric,
        signalDirection: signalDirection ?? this.signalDirection,
      );
  CoverageMap copyWithCompanion(CoverageMapsCompanion data) {
    return CoverageMap(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      baseNodeId:
          data.baseNodeId.present ? data.baseNodeId.value : this.baseNodeId,
      baseLat: data.baseLat.present ? data.baseLat.value : this.baseLat,
      baseLon: data.baseLon.present ? data.baseLon.value : this.baseLon,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      description:
          data.description.present ? data.description.value : this.description,
      colorMetric:
          data.colorMetric.present ? data.colorMetric.value : this.colorMetric,
      signalDirection: data.signalDirection.present
          ? data.signalDirection.value
          : this.signalDirection,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoverageMap(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseNodeId: $baseNodeId, ')
          ..write('baseLat: $baseLat, ')
          ..write('baseLon: $baseLon, ')
          ..write('createdAt: $createdAt, ')
          ..write('description: $description, ')
          ..write('colorMetric: $colorMetric, ')
          ..write('signalDirection: $signalDirection')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, baseNodeId, baseLat, baseLon,
      createdAt, description, colorMetric, signalDirection);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoverageMap &&
          other.id == this.id &&
          other.name == this.name &&
          other.baseNodeId == this.baseNodeId &&
          other.baseLat == this.baseLat &&
          other.baseLon == this.baseLon &&
          other.createdAt == this.createdAt &&
          other.description == this.description &&
          other.colorMetric == this.colorMetric &&
          other.signalDirection == this.signalDirection);
}

class CoverageMapsCompanion extends UpdateCompanion<CoverageMap> {
  final Value<int> id;
  final Value<String> name;
  final Value<int?> baseNodeId;
  final Value<double?> baseLat;
  final Value<double?> baseLon;
  final Value<DateTime> createdAt;
  final Value<String> description;
  final Value<String> colorMetric;
  final Value<String> signalDirection;
  const CoverageMapsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.baseNodeId = const Value.absent(),
    this.baseLat = const Value.absent(),
    this.baseLon = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.description = const Value.absent(),
    this.colorMetric = const Value.absent(),
    this.signalDirection = const Value.absent(),
  });
  CoverageMapsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.baseNodeId = const Value.absent(),
    this.baseLat = const Value.absent(),
    this.baseLon = const Value.absent(),
    required DateTime createdAt,
    this.description = const Value.absent(),
    this.colorMetric = const Value.absent(),
    this.signalDirection = const Value.absent(),
  })  : name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<CoverageMap> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? baseNodeId,
    Expression<double>? baseLat,
    Expression<double>? baseLon,
    Expression<DateTime>? createdAt,
    Expression<String>? description,
    Expression<String>? colorMetric,
    Expression<String>? signalDirection,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (baseNodeId != null) 'base_node_id': baseNodeId,
      if (baseLat != null) 'base_lat': baseLat,
      if (baseLon != null) 'base_lon': baseLon,
      if (createdAt != null) 'created_at': createdAt,
      if (description != null) 'description': description,
      if (colorMetric != null) 'color_metric': colorMetric,
      if (signalDirection != null) 'signal_direction': signalDirection,
    });
  }

  CoverageMapsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<int?>? baseNodeId,
      Value<double?>? baseLat,
      Value<double?>? baseLon,
      Value<DateTime>? createdAt,
      Value<String>? description,
      Value<String>? colorMetric,
      Value<String>? signalDirection}) {
    return CoverageMapsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      baseNodeId: baseNodeId ?? this.baseNodeId,
      baseLat: baseLat ?? this.baseLat,
      baseLon: baseLon ?? this.baseLon,
      createdAt: createdAt ?? this.createdAt,
      description: description ?? this.description,
      colorMetric: colorMetric ?? this.colorMetric,
      signalDirection: signalDirection ?? this.signalDirection,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseNodeId.present) {
      map['base_node_id'] = Variable<int>(baseNodeId.value);
    }
    if (baseLat.present) {
      map['base_lat'] = Variable<double>(baseLat.value);
    }
    if (baseLon.present) {
      map['base_lon'] = Variable<double>(baseLon.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (colorMetric.present) {
      map['color_metric'] = Variable<String>(colorMetric.value);
    }
    if (signalDirection.present) {
      map['signal_direction'] = Variable<String>(signalDirection.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoverageMapsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseNodeId: $baseNodeId, ')
          ..write('baseLat: $baseLat, ')
          ..write('baseLon: $baseLon, ')
          ..write('createdAt: $createdAt, ')
          ..write('description: $description, ')
          ..write('colorMetric: $colorMetric, ')
          ..write('signalDirection: $signalDirection')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _coverageMapIdMeta =
      const VerificationMeta('coverageMapId');
  @override
  late final GeneratedColumn<int> coverageMapId = GeneratedColumn<int>(
      'coverage_map_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES coverage_maps (id)'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endedAtMeta =
      const VerificationMeta('endedAt');
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
      'ended_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _remoteNodeIdMeta =
      const VerificationMeta('remoteNodeId');
  @override
  late final GeneratedColumn<int> remoteNodeId = GeneratedColumn<int>(
      'remote_node_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES nodes (id)'));
  static const VerificationMeta _baseNodeIdMeta =
      const VerificationMeta('baseNodeId');
  @override
  late final GeneratedColumn<int> baseNodeId = GeneratedColumn<int>(
      'base_node_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES nodes (id)'));
  static const VerificationMeta _hwAntennaMeta =
      const VerificationMeta('hwAntenna');
  @override
  late final GeneratedColumn<String> hwAntenna = GeneratedColumn<String>(
      'hw_antenna', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _hwNodeModelMeta =
      const VerificationMeta('hwNodeModel');
  @override
  late final GeneratedColumn<String> hwNodeModel = GeneratedColumn<String>(
      'hw_node_model', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _hwNotesMeta =
      const VerificationMeta('hwNotes');
  @override
  late final GeneratedColumn<String> hwNotes = GeneratedColumn<String>(
      'hw_notes', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _loraPresetMeta =
      const VerificationMeta('loraPreset');
  @override
  late final GeneratedColumn<String> loraPreset = GeneratedColumn<String>(
      'lora_preset', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _protocolMeta =
      const VerificationMeta('protocol');
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
      'protocol', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('meshtastic'));
  static const VerificationMeta _pingIntervalSecMeta =
      const VerificationMeta('pingIntervalSec');
  @override
  late final GeneratedColumn<int> pingIntervalSec = GeneratedColumn<int>(
      'ping_interval_sec', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _packetAirtimeMsMeta =
      const VerificationMeta('packetAirtimeMs');
  @override
  late final GeneratedColumn<double> packetAirtimeMs = GeneratedColumn<double>(
      'packet_airtime_ms', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _mobileRigIdMeta =
      const VerificationMeta('mobileRigId');
  @override
  late final GeneratedColumn<int> mobileRigId = GeneratedColumn<int>(
      'mobile_rig_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _baseRigIdMeta =
      const VerificationMeta('baseRigId');
  @override
  late final GeneratedColumn<int> baseRigId = GeneratedColumn<int>(
      'base_rig_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _mobileRigJsonMeta =
      const VerificationMeta('mobileRigJson');
  @override
  late final GeneratedColumn<String> mobileRigJson = GeneratedColumn<String>(
      'mobile_rig_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _baseRigJsonMeta =
      const VerificationMeta('baseRigJson');
  @override
  late final GeneratedColumn<String> baseRigJson = GeneratedColumn<String>(
      'base_rig_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _radioAirUtilTxMeta =
      const VerificationMeta('radioAirUtilTx');
  @override
  late final GeneratedColumn<double> radioAirUtilTx = GeneratedColumn<double>(
      'radio_air_util_tx', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _radioChannelUtilMeta =
      const VerificationMeta('radioChannelUtil');
  @override
  late final GeneratedColumn<double> radioChannelUtil = GeneratedColumn<double>(
      'radio_channel_util', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _beaconKindMeta =
      const VerificationMeta('beaconKind');
  @override
  late final GeneratedColumn<String> beaconKind = GeneratedColumn<String>(
      'beacon_kind', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _beaconIntervalSecMeta =
      const VerificationMeta('beaconIntervalSec');
  @override
  late final GeneratedColumn<int> beaconIntervalSec = GeneratedColumn<int>(
      'beacon_interval_sec', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  @override
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
      'region', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _frequencySlotMeta =
      const VerificationMeta('frequencySlot');
  @override
  late final GeneratedColumn<int> frequencySlot = GeneratedColumn<int>(
      'frequency_slot', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _txPowerDbmMeta =
      const VerificationMeta('txPowerDbm');
  @override
  late final GeneratedColumn<int> txPowerDbm = GeneratedColumn<int>(
      'tx_power_dbm', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _hopLimitMeta =
      const VerificationMeta('hopLimit');
  @override
  late final GeneratedColumn<int> hopLimit = GeneratedColumn<int>(
      'hop_limit', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _frequencyMhzMeta =
      const VerificationMeta('frequencyMhz');
  @override
  late final GeneratedColumn<double> frequencyMhz = GeneratedColumn<double>(
      'frequency_mhz', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _testStepIdMeta =
      const VerificationMeta('testStepId');
  @override
  late final GeneratedColumn<int> testStepId = GeneratedColumn<int>(
      'test_step_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _rangeTestActiveMeta =
      const VerificationMeta('rangeTestActive');
  @override
  late final GeneratedColumn<bool> rangeTestActive = GeneratedColumn<bool>(
      'range_test_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("range_test_active" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _packetCountMeta =
      const VerificationMeta('packetCount');
  @override
  late final GeneratedColumn<int> packetCount = GeneratedColumn<int>(
      'packet_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        coverageMapId,
        name,
        startedAt,
        endedAt,
        isActive,
        remoteNodeId,
        baseNodeId,
        hwAntenna,
        hwNodeModel,
        hwNotes,
        loraPreset,
        protocol,
        pingIntervalSec,
        packetAirtimeMs,
        mobileRigId,
        baseRigId,
        mobileRigJson,
        baseRigJson,
        radioAirUtilTx,
        radioChannelUtil,
        beaconKind,
        beaconIntervalSec,
        region,
        frequencySlot,
        txPowerDbm,
        hopLimit,
        frequencyMhz,
        testStepId,
        rangeTestActive,
        packetCount
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(Insertable<Session> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('coverage_map_id')) {
      context.handle(
          _coverageMapIdMeta,
          coverageMapId.isAcceptableOrUnknown(
              data['coverage_map_id']!, _coverageMapIdMeta));
    } else if (isInserting) {
      context.missing(_coverageMapIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(_endedAtMeta,
          endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('remote_node_id')) {
      context.handle(
          _remoteNodeIdMeta,
          remoteNodeId.isAcceptableOrUnknown(
              data['remote_node_id']!, _remoteNodeIdMeta));
    }
    if (data.containsKey('base_node_id')) {
      context.handle(
          _baseNodeIdMeta,
          baseNodeId.isAcceptableOrUnknown(
              data['base_node_id']!, _baseNodeIdMeta));
    }
    if (data.containsKey('hw_antenna')) {
      context.handle(_hwAntennaMeta,
          hwAntenna.isAcceptableOrUnknown(data['hw_antenna']!, _hwAntennaMeta));
    }
    if (data.containsKey('hw_node_model')) {
      context.handle(
          _hwNodeModelMeta,
          hwNodeModel.isAcceptableOrUnknown(
              data['hw_node_model']!, _hwNodeModelMeta));
    }
    if (data.containsKey('hw_notes')) {
      context.handle(_hwNotesMeta,
          hwNotes.isAcceptableOrUnknown(data['hw_notes']!, _hwNotesMeta));
    }
    if (data.containsKey('lora_preset')) {
      context.handle(
          _loraPresetMeta,
          loraPreset.isAcceptableOrUnknown(
              data['lora_preset']!, _loraPresetMeta));
    }
    if (data.containsKey('protocol')) {
      context.handle(_protocolMeta,
          protocol.isAcceptableOrUnknown(data['protocol']!, _protocolMeta));
    }
    if (data.containsKey('ping_interval_sec')) {
      context.handle(
          _pingIntervalSecMeta,
          pingIntervalSec.isAcceptableOrUnknown(
              data['ping_interval_sec']!, _pingIntervalSecMeta));
    }
    if (data.containsKey('packet_airtime_ms')) {
      context.handle(
          _packetAirtimeMsMeta,
          packetAirtimeMs.isAcceptableOrUnknown(
              data['packet_airtime_ms']!, _packetAirtimeMsMeta));
    }
    if (data.containsKey('mobile_rig_id')) {
      context.handle(
          _mobileRigIdMeta,
          mobileRigId.isAcceptableOrUnknown(
              data['mobile_rig_id']!, _mobileRigIdMeta));
    }
    if (data.containsKey('base_rig_id')) {
      context.handle(
          _baseRigIdMeta,
          baseRigId.isAcceptableOrUnknown(
              data['base_rig_id']!, _baseRigIdMeta));
    }
    if (data.containsKey('mobile_rig_json')) {
      context.handle(
          _mobileRigJsonMeta,
          mobileRigJson.isAcceptableOrUnknown(
              data['mobile_rig_json']!, _mobileRigJsonMeta));
    }
    if (data.containsKey('base_rig_json')) {
      context.handle(
          _baseRigJsonMeta,
          baseRigJson.isAcceptableOrUnknown(
              data['base_rig_json']!, _baseRigJsonMeta));
    }
    if (data.containsKey('radio_air_util_tx')) {
      context.handle(
          _radioAirUtilTxMeta,
          radioAirUtilTx.isAcceptableOrUnknown(
              data['radio_air_util_tx']!, _radioAirUtilTxMeta));
    }
    if (data.containsKey('radio_channel_util')) {
      context.handle(
          _radioChannelUtilMeta,
          radioChannelUtil.isAcceptableOrUnknown(
              data['radio_channel_util']!, _radioChannelUtilMeta));
    }
    if (data.containsKey('beacon_kind')) {
      context.handle(
          _beaconKindMeta,
          beaconKind.isAcceptableOrUnknown(
              data['beacon_kind']!, _beaconKindMeta));
    }
    if (data.containsKey('beacon_interval_sec')) {
      context.handle(
          _beaconIntervalSecMeta,
          beaconIntervalSec.isAcceptableOrUnknown(
              data['beacon_interval_sec']!, _beaconIntervalSecMeta));
    }
    if (data.containsKey('region')) {
      context.handle(_regionMeta,
          region.isAcceptableOrUnknown(data['region']!, _regionMeta));
    }
    if (data.containsKey('frequency_slot')) {
      context.handle(
          _frequencySlotMeta,
          frequencySlot.isAcceptableOrUnknown(
              data['frequency_slot']!, _frequencySlotMeta));
    }
    if (data.containsKey('tx_power_dbm')) {
      context.handle(
          _txPowerDbmMeta,
          txPowerDbm.isAcceptableOrUnknown(
              data['tx_power_dbm']!, _txPowerDbmMeta));
    }
    if (data.containsKey('hop_limit')) {
      context.handle(_hopLimitMeta,
          hopLimit.isAcceptableOrUnknown(data['hop_limit']!, _hopLimitMeta));
    }
    if (data.containsKey('frequency_mhz')) {
      context.handle(
          _frequencyMhzMeta,
          frequencyMhz.isAcceptableOrUnknown(
              data['frequency_mhz']!, _frequencyMhzMeta));
    }
    if (data.containsKey('test_step_id')) {
      context.handle(
          _testStepIdMeta,
          testStepId.isAcceptableOrUnknown(
              data['test_step_id']!, _testStepIdMeta));
    }
    if (data.containsKey('range_test_active')) {
      context.handle(
          _rangeTestActiveMeta,
          rangeTestActive.isAcceptableOrUnknown(
              data['range_test_active']!, _rangeTestActiveMeta));
    }
    if (data.containsKey('packet_count')) {
      context.handle(
          _packetCountMeta,
          packetCount.isAcceptableOrUnknown(
              data['packet_count']!, _packetCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      coverageMapId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}coverage_map_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      endedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ended_at']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      remoteNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_node_id']),
      baseNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_node_id']),
      hwAntenna: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hw_antenna'])!,
      hwNodeModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hw_node_model'])!,
      hwNotes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hw_notes'])!,
      loraPreset: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}lora_preset'])!,
      protocol: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}protocol'])!,
      pingIntervalSec: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ping_interval_sec'])!,
      packetAirtimeMs: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}packet_airtime_ms'])!,
      mobileRigId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mobile_rig_id']),
      baseRigId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_rig_id']),
      mobileRigJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mobile_rig_json']),
      baseRigJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_rig_json']),
      radioAirUtilTx: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}radio_air_util_tx']),
      radioChannelUtil: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}radio_channel_util']),
      beaconKind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}beacon_kind'])!,
      beaconIntervalSec: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}beacon_interval_sec'])!,
      region: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}region']),
      frequencySlot: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}frequency_slot']),
      txPowerDbm: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tx_power_dbm']),
      hopLimit: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}hop_limit']),
      frequencyMhz: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}frequency_mhz']),
      testStepId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}test_step_id']),
      rangeTestActive: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}range_test_active'])!,
      packetCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}packet_count'])!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final int id;
  final int coverageMapId;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool isActive;
  final int? remoteNodeId;

  /// The base radio this session pinged and listened for (schema v8).
  /// Null on sessions from before v8 whose map had no base; readers fall
  /// back to `CoverageMaps.baseNodeId`.
  final int? baseNodeId;
  final String hwAntenna;
  final String hwNodeModel;
  final String hwNotes;

  /// LoRa modem preset in use, e.g. "LONG_FAST" (schema v2).
  final String loraPreset;

  /// Radio protocol the session was recorded with: "meshtastic" or
  /// "meshcore" (schema v5).
  final String protocol;
  final int pingIntervalSec;

  /// Estimated airtime of one ping in ms at session start (schema v3).
  final double packetAirtimeMs;

  /// Rig used on the mobile / base radio (schema v4). Ids may dangle if a
  /// profile is ever removed; the JSON snapshots are the source of truth.
  final int? mobileRigId;
  final int? baseRigId;

  /// Rig as it was when the session started (`RigSpec.toJson`).
  final String? mobileRigJson;
  final String? baseRigJson;

  /// Highest air_util_tx (% of the last hour our radio transmitted) and
  /// channel utilization the radio reported during the session (schema v6).
  /// Null when it never reported.
  final double? radioAirUtilTx;
  final double? radioChannelUtil;

  /// Base beacon the session ran with: 'rangeTest', 'telemetry', 'trace'
  /// (MeshCore pulled beacon: the mobile's trace pings) or 'none' (schema
  /// v7). Empty on older sessions.
  final String beaconKind;

  /// Beacon interval in seconds (schema v7); 0 when unknown or off.
  final int beaconIntervalSec;

  /// Radio settings beyond the preset at session start (schema v9), so a
  /// preset or antenna comparison isn't silently a frequency or power one.
  /// Null on older sessions and when the radio didn't say. Region code
  /// ("US"), effective 1-based frequency slot (null under a frequency
  /// override), transmit power, hop limit and centre frequency.
  final String? region;
  final int? frequencySlot;
  final int? txPowerDbm;
  final int? hopLimit;
  final double? frequencyMhz;

  /// The guided-test step (`test_steps.id`) that recorded this session
  /// (schema v11); null for ordinary sessions. No foreign key: the steps
  /// table points back at sessions.
  final int? testStepId;
  final bool rangeTestActive;
  final int packetCount;
  const Session(
      {required this.id,
      required this.coverageMapId,
      required this.name,
      required this.startedAt,
      this.endedAt,
      required this.isActive,
      this.remoteNodeId,
      this.baseNodeId,
      required this.hwAntenna,
      required this.hwNodeModel,
      required this.hwNotes,
      required this.loraPreset,
      required this.protocol,
      required this.pingIntervalSec,
      required this.packetAirtimeMs,
      this.mobileRigId,
      this.baseRigId,
      this.mobileRigJson,
      this.baseRigJson,
      this.radioAirUtilTx,
      this.radioChannelUtil,
      required this.beaconKind,
      required this.beaconIntervalSec,
      this.region,
      this.frequencySlot,
      this.txPowerDbm,
      this.hopLimit,
      this.frequencyMhz,
      this.testStepId,
      required this.rangeTestActive,
      required this.packetCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['coverage_map_id'] = Variable<int>(coverageMapId);
    map['name'] = Variable<String>(name);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['is_active'] = Variable<bool>(isActive);
    if (!nullToAbsent || remoteNodeId != null) {
      map['remote_node_id'] = Variable<int>(remoteNodeId);
    }
    if (!nullToAbsent || baseNodeId != null) {
      map['base_node_id'] = Variable<int>(baseNodeId);
    }
    map['hw_antenna'] = Variable<String>(hwAntenna);
    map['hw_node_model'] = Variable<String>(hwNodeModel);
    map['hw_notes'] = Variable<String>(hwNotes);
    map['lora_preset'] = Variable<String>(loraPreset);
    map['protocol'] = Variable<String>(protocol);
    map['ping_interval_sec'] = Variable<int>(pingIntervalSec);
    map['packet_airtime_ms'] = Variable<double>(packetAirtimeMs);
    if (!nullToAbsent || mobileRigId != null) {
      map['mobile_rig_id'] = Variable<int>(mobileRigId);
    }
    if (!nullToAbsent || baseRigId != null) {
      map['base_rig_id'] = Variable<int>(baseRigId);
    }
    if (!nullToAbsent || mobileRigJson != null) {
      map['mobile_rig_json'] = Variable<String>(mobileRigJson);
    }
    if (!nullToAbsent || baseRigJson != null) {
      map['base_rig_json'] = Variable<String>(baseRigJson);
    }
    if (!nullToAbsent || radioAirUtilTx != null) {
      map['radio_air_util_tx'] = Variable<double>(radioAirUtilTx);
    }
    if (!nullToAbsent || radioChannelUtil != null) {
      map['radio_channel_util'] = Variable<double>(radioChannelUtil);
    }
    map['beacon_kind'] = Variable<String>(beaconKind);
    map['beacon_interval_sec'] = Variable<int>(beaconIntervalSec);
    if (!nullToAbsent || region != null) {
      map['region'] = Variable<String>(region);
    }
    if (!nullToAbsent || frequencySlot != null) {
      map['frequency_slot'] = Variable<int>(frequencySlot);
    }
    if (!nullToAbsent || txPowerDbm != null) {
      map['tx_power_dbm'] = Variable<int>(txPowerDbm);
    }
    if (!nullToAbsent || hopLimit != null) {
      map['hop_limit'] = Variable<int>(hopLimit);
    }
    if (!nullToAbsent || frequencyMhz != null) {
      map['frequency_mhz'] = Variable<double>(frequencyMhz);
    }
    if (!nullToAbsent || testStepId != null) {
      map['test_step_id'] = Variable<int>(testStepId);
    }
    map['range_test_active'] = Variable<bool>(rangeTestActive);
    map['packet_count'] = Variable<int>(packetCount);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      coverageMapId: Value(coverageMapId),
      name: Value(name),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      isActive: Value(isActive),
      remoteNodeId: remoteNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteNodeId),
      baseNodeId: baseNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(baseNodeId),
      hwAntenna: Value(hwAntenna),
      hwNodeModel: Value(hwNodeModel),
      hwNotes: Value(hwNotes),
      loraPreset: Value(loraPreset),
      protocol: Value(protocol),
      pingIntervalSec: Value(pingIntervalSec),
      packetAirtimeMs: Value(packetAirtimeMs),
      mobileRigId: mobileRigId == null && nullToAbsent
          ? const Value.absent()
          : Value(mobileRigId),
      baseRigId: baseRigId == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRigId),
      mobileRigJson: mobileRigJson == null && nullToAbsent
          ? const Value.absent()
          : Value(mobileRigJson),
      baseRigJson: baseRigJson == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRigJson),
      radioAirUtilTx: radioAirUtilTx == null && nullToAbsent
          ? const Value.absent()
          : Value(radioAirUtilTx),
      radioChannelUtil: radioChannelUtil == null && nullToAbsent
          ? const Value.absent()
          : Value(radioChannelUtil),
      beaconKind: Value(beaconKind),
      beaconIntervalSec: Value(beaconIntervalSec),
      region:
          region == null && nullToAbsent ? const Value.absent() : Value(region),
      frequencySlot: frequencySlot == null && nullToAbsent
          ? const Value.absent()
          : Value(frequencySlot),
      txPowerDbm: txPowerDbm == null && nullToAbsent
          ? const Value.absent()
          : Value(txPowerDbm),
      hopLimit: hopLimit == null && nullToAbsent
          ? const Value.absent()
          : Value(hopLimit),
      frequencyMhz: frequencyMhz == null && nullToAbsent
          ? const Value.absent()
          : Value(frequencyMhz),
      testStepId: testStepId == null && nullToAbsent
          ? const Value.absent()
          : Value(testStepId),
      rangeTestActive: Value(rangeTestActive),
      packetCount: Value(packetCount),
    );
  }

  factory Session.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<int>(json['id']),
      coverageMapId: serializer.fromJson<int>(json['coverageMapId']),
      name: serializer.fromJson<String>(json['name']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      remoteNodeId: serializer.fromJson<int?>(json['remoteNodeId']),
      baseNodeId: serializer.fromJson<int?>(json['baseNodeId']),
      hwAntenna: serializer.fromJson<String>(json['hwAntenna']),
      hwNodeModel: serializer.fromJson<String>(json['hwNodeModel']),
      hwNotes: serializer.fromJson<String>(json['hwNotes']),
      loraPreset: serializer.fromJson<String>(json['loraPreset']),
      protocol: serializer.fromJson<String>(json['protocol']),
      pingIntervalSec: serializer.fromJson<int>(json['pingIntervalSec']),
      packetAirtimeMs: serializer.fromJson<double>(json['packetAirtimeMs']),
      mobileRigId: serializer.fromJson<int?>(json['mobileRigId']),
      baseRigId: serializer.fromJson<int?>(json['baseRigId']),
      mobileRigJson: serializer.fromJson<String?>(json['mobileRigJson']),
      baseRigJson: serializer.fromJson<String?>(json['baseRigJson']),
      radioAirUtilTx: serializer.fromJson<double?>(json['radioAirUtilTx']),
      radioChannelUtil: serializer.fromJson<double?>(json['radioChannelUtil']),
      beaconKind: serializer.fromJson<String>(json['beaconKind']),
      beaconIntervalSec: serializer.fromJson<int>(json['beaconIntervalSec']),
      region: serializer.fromJson<String?>(json['region']),
      frequencySlot: serializer.fromJson<int?>(json['frequencySlot']),
      txPowerDbm: serializer.fromJson<int?>(json['txPowerDbm']),
      hopLimit: serializer.fromJson<int?>(json['hopLimit']),
      frequencyMhz: serializer.fromJson<double?>(json['frequencyMhz']),
      testStepId: serializer.fromJson<int?>(json['testStepId']),
      rangeTestActive: serializer.fromJson<bool>(json['rangeTestActive']),
      packetCount: serializer.fromJson<int>(json['packetCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'coverageMapId': serializer.toJson<int>(coverageMapId),
      'name': serializer.toJson<String>(name),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'isActive': serializer.toJson<bool>(isActive),
      'remoteNodeId': serializer.toJson<int?>(remoteNodeId),
      'baseNodeId': serializer.toJson<int?>(baseNodeId),
      'hwAntenna': serializer.toJson<String>(hwAntenna),
      'hwNodeModel': serializer.toJson<String>(hwNodeModel),
      'hwNotes': serializer.toJson<String>(hwNotes),
      'loraPreset': serializer.toJson<String>(loraPreset),
      'protocol': serializer.toJson<String>(protocol),
      'pingIntervalSec': serializer.toJson<int>(pingIntervalSec),
      'packetAirtimeMs': serializer.toJson<double>(packetAirtimeMs),
      'mobileRigId': serializer.toJson<int?>(mobileRigId),
      'baseRigId': serializer.toJson<int?>(baseRigId),
      'mobileRigJson': serializer.toJson<String?>(mobileRigJson),
      'baseRigJson': serializer.toJson<String?>(baseRigJson),
      'radioAirUtilTx': serializer.toJson<double?>(radioAirUtilTx),
      'radioChannelUtil': serializer.toJson<double?>(radioChannelUtil),
      'beaconKind': serializer.toJson<String>(beaconKind),
      'beaconIntervalSec': serializer.toJson<int>(beaconIntervalSec),
      'region': serializer.toJson<String?>(region),
      'frequencySlot': serializer.toJson<int?>(frequencySlot),
      'txPowerDbm': serializer.toJson<int?>(txPowerDbm),
      'hopLimit': serializer.toJson<int?>(hopLimit),
      'frequencyMhz': serializer.toJson<double?>(frequencyMhz),
      'testStepId': serializer.toJson<int?>(testStepId),
      'rangeTestActive': serializer.toJson<bool>(rangeTestActive),
      'packetCount': serializer.toJson<int>(packetCount),
    };
  }

  Session copyWith(
          {int? id,
          int? coverageMapId,
          String? name,
          DateTime? startedAt,
          Value<DateTime?> endedAt = const Value.absent(),
          bool? isActive,
          Value<int?> remoteNodeId = const Value.absent(),
          Value<int?> baseNodeId = const Value.absent(),
          String? hwAntenna,
          String? hwNodeModel,
          String? hwNotes,
          String? loraPreset,
          String? protocol,
          int? pingIntervalSec,
          double? packetAirtimeMs,
          Value<int?> mobileRigId = const Value.absent(),
          Value<int?> baseRigId = const Value.absent(),
          Value<String?> mobileRigJson = const Value.absent(),
          Value<String?> baseRigJson = const Value.absent(),
          Value<double?> radioAirUtilTx = const Value.absent(),
          Value<double?> radioChannelUtil = const Value.absent(),
          String? beaconKind,
          int? beaconIntervalSec,
          Value<String?> region = const Value.absent(),
          Value<int?> frequencySlot = const Value.absent(),
          Value<int?> txPowerDbm = const Value.absent(),
          Value<int?> hopLimit = const Value.absent(),
          Value<double?> frequencyMhz = const Value.absent(),
          Value<int?> testStepId = const Value.absent(),
          bool? rangeTestActive,
          int? packetCount}) =>
      Session(
        id: id ?? this.id,
        coverageMapId: coverageMapId ?? this.coverageMapId,
        name: name ?? this.name,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt.present ? endedAt.value : this.endedAt,
        isActive: isActive ?? this.isActive,
        remoteNodeId:
            remoteNodeId.present ? remoteNodeId.value : this.remoteNodeId,
        baseNodeId: baseNodeId.present ? baseNodeId.value : this.baseNodeId,
        hwAntenna: hwAntenna ?? this.hwAntenna,
        hwNodeModel: hwNodeModel ?? this.hwNodeModel,
        hwNotes: hwNotes ?? this.hwNotes,
        loraPreset: loraPreset ?? this.loraPreset,
        protocol: protocol ?? this.protocol,
        pingIntervalSec: pingIntervalSec ?? this.pingIntervalSec,
        packetAirtimeMs: packetAirtimeMs ?? this.packetAirtimeMs,
        mobileRigId: mobileRigId.present ? mobileRigId.value : this.mobileRigId,
        baseRigId: baseRigId.present ? baseRigId.value : this.baseRigId,
        mobileRigJson:
            mobileRigJson.present ? mobileRigJson.value : this.mobileRigJson,
        baseRigJson: baseRigJson.present ? baseRigJson.value : this.baseRigJson,
        radioAirUtilTx:
            radioAirUtilTx.present ? radioAirUtilTx.value : this.radioAirUtilTx,
        radioChannelUtil: radioChannelUtil.present
            ? radioChannelUtil.value
            : this.radioChannelUtil,
        beaconKind: beaconKind ?? this.beaconKind,
        beaconIntervalSec: beaconIntervalSec ?? this.beaconIntervalSec,
        region: region.present ? region.value : this.region,
        frequencySlot:
            frequencySlot.present ? frequencySlot.value : this.frequencySlot,
        txPowerDbm: txPowerDbm.present ? txPowerDbm.value : this.txPowerDbm,
        hopLimit: hopLimit.present ? hopLimit.value : this.hopLimit,
        frequencyMhz:
            frequencyMhz.present ? frequencyMhz.value : this.frequencyMhz,
        testStepId: testStepId.present ? testStepId.value : this.testStepId,
        rangeTestActive: rangeTestActive ?? this.rangeTestActive,
        packetCount: packetCount ?? this.packetCount,
      );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      coverageMapId: data.coverageMapId.present
          ? data.coverageMapId.value
          : this.coverageMapId,
      name: data.name.present ? data.name.value : this.name,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      remoteNodeId: data.remoteNodeId.present
          ? data.remoteNodeId.value
          : this.remoteNodeId,
      baseNodeId:
          data.baseNodeId.present ? data.baseNodeId.value : this.baseNodeId,
      hwAntenna: data.hwAntenna.present ? data.hwAntenna.value : this.hwAntenna,
      hwNodeModel:
          data.hwNodeModel.present ? data.hwNodeModel.value : this.hwNodeModel,
      hwNotes: data.hwNotes.present ? data.hwNotes.value : this.hwNotes,
      loraPreset:
          data.loraPreset.present ? data.loraPreset.value : this.loraPreset,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      pingIntervalSec: data.pingIntervalSec.present
          ? data.pingIntervalSec.value
          : this.pingIntervalSec,
      packetAirtimeMs: data.packetAirtimeMs.present
          ? data.packetAirtimeMs.value
          : this.packetAirtimeMs,
      mobileRigId:
          data.mobileRigId.present ? data.mobileRigId.value : this.mobileRigId,
      baseRigId: data.baseRigId.present ? data.baseRigId.value : this.baseRigId,
      mobileRigJson: data.mobileRigJson.present
          ? data.mobileRigJson.value
          : this.mobileRigJson,
      baseRigJson:
          data.baseRigJson.present ? data.baseRigJson.value : this.baseRigJson,
      radioAirUtilTx: data.radioAirUtilTx.present
          ? data.radioAirUtilTx.value
          : this.radioAirUtilTx,
      radioChannelUtil: data.radioChannelUtil.present
          ? data.radioChannelUtil.value
          : this.radioChannelUtil,
      beaconKind:
          data.beaconKind.present ? data.beaconKind.value : this.beaconKind,
      beaconIntervalSec: data.beaconIntervalSec.present
          ? data.beaconIntervalSec.value
          : this.beaconIntervalSec,
      region: data.region.present ? data.region.value : this.region,
      frequencySlot: data.frequencySlot.present
          ? data.frequencySlot.value
          : this.frequencySlot,
      txPowerDbm:
          data.txPowerDbm.present ? data.txPowerDbm.value : this.txPowerDbm,
      hopLimit: data.hopLimit.present ? data.hopLimit.value : this.hopLimit,
      frequencyMhz: data.frequencyMhz.present
          ? data.frequencyMhz.value
          : this.frequencyMhz,
      testStepId:
          data.testStepId.present ? data.testStepId.value : this.testStepId,
      rangeTestActive: data.rangeTestActive.present
          ? data.rangeTestActive.value
          : this.rangeTestActive,
      packetCount:
          data.packetCount.present ? data.packetCount.value : this.packetCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('coverageMapId: $coverageMapId, ')
          ..write('name: $name, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('isActive: $isActive, ')
          ..write('remoteNodeId: $remoteNodeId, ')
          ..write('baseNodeId: $baseNodeId, ')
          ..write('hwAntenna: $hwAntenna, ')
          ..write('hwNodeModel: $hwNodeModel, ')
          ..write('hwNotes: $hwNotes, ')
          ..write('loraPreset: $loraPreset, ')
          ..write('protocol: $protocol, ')
          ..write('pingIntervalSec: $pingIntervalSec, ')
          ..write('packetAirtimeMs: $packetAirtimeMs, ')
          ..write('mobileRigId: $mobileRigId, ')
          ..write('baseRigId: $baseRigId, ')
          ..write('mobileRigJson: $mobileRigJson, ')
          ..write('baseRigJson: $baseRigJson, ')
          ..write('radioAirUtilTx: $radioAirUtilTx, ')
          ..write('radioChannelUtil: $radioChannelUtil, ')
          ..write('beaconKind: $beaconKind, ')
          ..write('beaconIntervalSec: $beaconIntervalSec, ')
          ..write('region: $region, ')
          ..write('frequencySlot: $frequencySlot, ')
          ..write('txPowerDbm: $txPowerDbm, ')
          ..write('hopLimit: $hopLimit, ')
          ..write('frequencyMhz: $frequencyMhz, ')
          ..write('testStepId: $testStepId, ')
          ..write('rangeTestActive: $rangeTestActive, ')
          ..write('packetCount: $packetCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        coverageMapId,
        name,
        startedAt,
        endedAt,
        isActive,
        remoteNodeId,
        baseNodeId,
        hwAntenna,
        hwNodeModel,
        hwNotes,
        loraPreset,
        protocol,
        pingIntervalSec,
        packetAirtimeMs,
        mobileRigId,
        baseRigId,
        mobileRigJson,
        baseRigJson,
        radioAirUtilTx,
        radioChannelUtil,
        beaconKind,
        beaconIntervalSec,
        region,
        frequencySlot,
        txPowerDbm,
        hopLimit,
        frequencyMhz,
        testStepId,
        rangeTestActive,
        packetCount
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.coverageMapId == this.coverageMapId &&
          other.name == this.name &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.isActive == this.isActive &&
          other.remoteNodeId == this.remoteNodeId &&
          other.baseNodeId == this.baseNodeId &&
          other.hwAntenna == this.hwAntenna &&
          other.hwNodeModel == this.hwNodeModel &&
          other.hwNotes == this.hwNotes &&
          other.loraPreset == this.loraPreset &&
          other.protocol == this.protocol &&
          other.pingIntervalSec == this.pingIntervalSec &&
          other.packetAirtimeMs == this.packetAirtimeMs &&
          other.mobileRigId == this.mobileRigId &&
          other.baseRigId == this.baseRigId &&
          other.mobileRigJson == this.mobileRigJson &&
          other.baseRigJson == this.baseRigJson &&
          other.radioAirUtilTx == this.radioAirUtilTx &&
          other.radioChannelUtil == this.radioChannelUtil &&
          other.beaconKind == this.beaconKind &&
          other.beaconIntervalSec == this.beaconIntervalSec &&
          other.region == this.region &&
          other.frequencySlot == this.frequencySlot &&
          other.txPowerDbm == this.txPowerDbm &&
          other.hopLimit == this.hopLimit &&
          other.frequencyMhz == this.frequencyMhz &&
          other.testStepId == this.testStepId &&
          other.rangeTestActive == this.rangeTestActive &&
          other.packetCount == this.packetCount);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<int> id;
  final Value<int> coverageMapId;
  final Value<String> name;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<bool> isActive;
  final Value<int?> remoteNodeId;
  final Value<int?> baseNodeId;
  final Value<String> hwAntenna;
  final Value<String> hwNodeModel;
  final Value<String> hwNotes;
  final Value<String> loraPreset;
  final Value<String> protocol;
  final Value<int> pingIntervalSec;
  final Value<double> packetAirtimeMs;
  final Value<int?> mobileRigId;
  final Value<int?> baseRigId;
  final Value<String?> mobileRigJson;
  final Value<String?> baseRigJson;
  final Value<double?> radioAirUtilTx;
  final Value<double?> radioChannelUtil;
  final Value<String> beaconKind;
  final Value<int> beaconIntervalSec;
  final Value<String?> region;
  final Value<int?> frequencySlot;
  final Value<int?> txPowerDbm;
  final Value<int?> hopLimit;
  final Value<double?> frequencyMhz;
  final Value<int?> testStepId;
  final Value<bool> rangeTestActive;
  final Value<int> packetCount;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.coverageMapId = const Value.absent(),
    this.name = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.remoteNodeId = const Value.absent(),
    this.baseNodeId = const Value.absent(),
    this.hwAntenna = const Value.absent(),
    this.hwNodeModel = const Value.absent(),
    this.hwNotes = const Value.absent(),
    this.loraPreset = const Value.absent(),
    this.protocol = const Value.absent(),
    this.pingIntervalSec = const Value.absent(),
    this.packetAirtimeMs = const Value.absent(),
    this.mobileRigId = const Value.absent(),
    this.baseRigId = const Value.absent(),
    this.mobileRigJson = const Value.absent(),
    this.baseRigJson = const Value.absent(),
    this.radioAirUtilTx = const Value.absent(),
    this.radioChannelUtil = const Value.absent(),
    this.beaconKind = const Value.absent(),
    this.beaconIntervalSec = const Value.absent(),
    this.region = const Value.absent(),
    this.frequencySlot = const Value.absent(),
    this.txPowerDbm = const Value.absent(),
    this.hopLimit = const Value.absent(),
    this.frequencyMhz = const Value.absent(),
    this.testStepId = const Value.absent(),
    this.rangeTestActive = const Value.absent(),
    this.packetCount = const Value.absent(),
  });
  SessionsCompanion.insert({
    this.id = const Value.absent(),
    required int coverageMapId,
    this.name = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.remoteNodeId = const Value.absent(),
    this.baseNodeId = const Value.absent(),
    this.hwAntenna = const Value.absent(),
    this.hwNodeModel = const Value.absent(),
    this.hwNotes = const Value.absent(),
    this.loraPreset = const Value.absent(),
    this.protocol = const Value.absent(),
    this.pingIntervalSec = const Value.absent(),
    this.packetAirtimeMs = const Value.absent(),
    this.mobileRigId = const Value.absent(),
    this.baseRigId = const Value.absent(),
    this.mobileRigJson = const Value.absent(),
    this.baseRigJson = const Value.absent(),
    this.radioAirUtilTx = const Value.absent(),
    this.radioChannelUtil = const Value.absent(),
    this.beaconKind = const Value.absent(),
    this.beaconIntervalSec = const Value.absent(),
    this.region = const Value.absent(),
    this.frequencySlot = const Value.absent(),
    this.txPowerDbm = const Value.absent(),
    this.hopLimit = const Value.absent(),
    this.frequencyMhz = const Value.absent(),
    this.testStepId = const Value.absent(),
    this.rangeTestActive = const Value.absent(),
    this.packetCount = const Value.absent(),
  })  : coverageMapId = Value(coverageMapId),
        startedAt = Value(startedAt);
  static Insertable<Session> custom({
    Expression<int>? id,
    Expression<int>? coverageMapId,
    Expression<String>? name,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<bool>? isActive,
    Expression<int>? remoteNodeId,
    Expression<int>? baseNodeId,
    Expression<String>? hwAntenna,
    Expression<String>? hwNodeModel,
    Expression<String>? hwNotes,
    Expression<String>? loraPreset,
    Expression<String>? protocol,
    Expression<int>? pingIntervalSec,
    Expression<double>? packetAirtimeMs,
    Expression<int>? mobileRigId,
    Expression<int>? baseRigId,
    Expression<String>? mobileRigJson,
    Expression<String>? baseRigJson,
    Expression<double>? radioAirUtilTx,
    Expression<double>? radioChannelUtil,
    Expression<String>? beaconKind,
    Expression<int>? beaconIntervalSec,
    Expression<String>? region,
    Expression<int>? frequencySlot,
    Expression<int>? txPowerDbm,
    Expression<int>? hopLimit,
    Expression<double>? frequencyMhz,
    Expression<int>? testStepId,
    Expression<bool>? rangeTestActive,
    Expression<int>? packetCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (coverageMapId != null) 'coverage_map_id': coverageMapId,
      if (name != null) 'name': name,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (isActive != null) 'is_active': isActive,
      if (remoteNodeId != null) 'remote_node_id': remoteNodeId,
      if (baseNodeId != null) 'base_node_id': baseNodeId,
      if (hwAntenna != null) 'hw_antenna': hwAntenna,
      if (hwNodeModel != null) 'hw_node_model': hwNodeModel,
      if (hwNotes != null) 'hw_notes': hwNotes,
      if (loraPreset != null) 'lora_preset': loraPreset,
      if (protocol != null) 'protocol': protocol,
      if (pingIntervalSec != null) 'ping_interval_sec': pingIntervalSec,
      if (packetAirtimeMs != null) 'packet_airtime_ms': packetAirtimeMs,
      if (mobileRigId != null) 'mobile_rig_id': mobileRigId,
      if (baseRigId != null) 'base_rig_id': baseRigId,
      if (mobileRigJson != null) 'mobile_rig_json': mobileRigJson,
      if (baseRigJson != null) 'base_rig_json': baseRigJson,
      if (radioAirUtilTx != null) 'radio_air_util_tx': radioAirUtilTx,
      if (radioChannelUtil != null) 'radio_channel_util': radioChannelUtil,
      if (beaconKind != null) 'beacon_kind': beaconKind,
      if (beaconIntervalSec != null) 'beacon_interval_sec': beaconIntervalSec,
      if (region != null) 'region': region,
      if (frequencySlot != null) 'frequency_slot': frequencySlot,
      if (txPowerDbm != null) 'tx_power_dbm': txPowerDbm,
      if (hopLimit != null) 'hop_limit': hopLimit,
      if (frequencyMhz != null) 'frequency_mhz': frequencyMhz,
      if (testStepId != null) 'test_step_id': testStepId,
      if (rangeTestActive != null) 'range_test_active': rangeTestActive,
      if (packetCount != null) 'packet_count': packetCount,
    });
  }

  SessionsCompanion copyWith(
      {Value<int>? id,
      Value<int>? coverageMapId,
      Value<String>? name,
      Value<DateTime>? startedAt,
      Value<DateTime?>? endedAt,
      Value<bool>? isActive,
      Value<int?>? remoteNodeId,
      Value<int?>? baseNodeId,
      Value<String>? hwAntenna,
      Value<String>? hwNodeModel,
      Value<String>? hwNotes,
      Value<String>? loraPreset,
      Value<String>? protocol,
      Value<int>? pingIntervalSec,
      Value<double>? packetAirtimeMs,
      Value<int?>? mobileRigId,
      Value<int?>? baseRigId,
      Value<String?>? mobileRigJson,
      Value<String?>? baseRigJson,
      Value<double?>? radioAirUtilTx,
      Value<double?>? radioChannelUtil,
      Value<String>? beaconKind,
      Value<int>? beaconIntervalSec,
      Value<String?>? region,
      Value<int?>? frequencySlot,
      Value<int?>? txPowerDbm,
      Value<int?>? hopLimit,
      Value<double?>? frequencyMhz,
      Value<int?>? testStepId,
      Value<bool>? rangeTestActive,
      Value<int>? packetCount}) {
    return SessionsCompanion(
      id: id ?? this.id,
      coverageMapId: coverageMapId ?? this.coverageMapId,
      name: name ?? this.name,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      isActive: isActive ?? this.isActive,
      remoteNodeId: remoteNodeId ?? this.remoteNodeId,
      baseNodeId: baseNodeId ?? this.baseNodeId,
      hwAntenna: hwAntenna ?? this.hwAntenna,
      hwNodeModel: hwNodeModel ?? this.hwNodeModel,
      hwNotes: hwNotes ?? this.hwNotes,
      loraPreset: loraPreset ?? this.loraPreset,
      protocol: protocol ?? this.protocol,
      pingIntervalSec: pingIntervalSec ?? this.pingIntervalSec,
      packetAirtimeMs: packetAirtimeMs ?? this.packetAirtimeMs,
      mobileRigId: mobileRigId ?? this.mobileRigId,
      baseRigId: baseRigId ?? this.baseRigId,
      mobileRigJson: mobileRigJson ?? this.mobileRigJson,
      baseRigJson: baseRigJson ?? this.baseRigJson,
      radioAirUtilTx: radioAirUtilTx ?? this.radioAirUtilTx,
      radioChannelUtil: radioChannelUtil ?? this.radioChannelUtil,
      beaconKind: beaconKind ?? this.beaconKind,
      beaconIntervalSec: beaconIntervalSec ?? this.beaconIntervalSec,
      region: region ?? this.region,
      frequencySlot: frequencySlot ?? this.frequencySlot,
      txPowerDbm: txPowerDbm ?? this.txPowerDbm,
      hopLimit: hopLimit ?? this.hopLimit,
      frequencyMhz: frequencyMhz ?? this.frequencyMhz,
      testStepId: testStepId ?? this.testStepId,
      rangeTestActive: rangeTestActive ?? this.rangeTestActive,
      packetCount: packetCount ?? this.packetCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (coverageMapId.present) {
      map['coverage_map_id'] = Variable<int>(coverageMapId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (remoteNodeId.present) {
      map['remote_node_id'] = Variable<int>(remoteNodeId.value);
    }
    if (baseNodeId.present) {
      map['base_node_id'] = Variable<int>(baseNodeId.value);
    }
    if (hwAntenna.present) {
      map['hw_antenna'] = Variable<String>(hwAntenna.value);
    }
    if (hwNodeModel.present) {
      map['hw_node_model'] = Variable<String>(hwNodeModel.value);
    }
    if (hwNotes.present) {
      map['hw_notes'] = Variable<String>(hwNotes.value);
    }
    if (loraPreset.present) {
      map['lora_preset'] = Variable<String>(loraPreset.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (pingIntervalSec.present) {
      map['ping_interval_sec'] = Variable<int>(pingIntervalSec.value);
    }
    if (packetAirtimeMs.present) {
      map['packet_airtime_ms'] = Variable<double>(packetAirtimeMs.value);
    }
    if (mobileRigId.present) {
      map['mobile_rig_id'] = Variable<int>(mobileRigId.value);
    }
    if (baseRigId.present) {
      map['base_rig_id'] = Variable<int>(baseRigId.value);
    }
    if (mobileRigJson.present) {
      map['mobile_rig_json'] = Variable<String>(mobileRigJson.value);
    }
    if (baseRigJson.present) {
      map['base_rig_json'] = Variable<String>(baseRigJson.value);
    }
    if (radioAirUtilTx.present) {
      map['radio_air_util_tx'] = Variable<double>(radioAirUtilTx.value);
    }
    if (radioChannelUtil.present) {
      map['radio_channel_util'] = Variable<double>(radioChannelUtil.value);
    }
    if (beaconKind.present) {
      map['beacon_kind'] = Variable<String>(beaconKind.value);
    }
    if (beaconIntervalSec.present) {
      map['beacon_interval_sec'] = Variable<int>(beaconIntervalSec.value);
    }
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (frequencySlot.present) {
      map['frequency_slot'] = Variable<int>(frequencySlot.value);
    }
    if (txPowerDbm.present) {
      map['tx_power_dbm'] = Variable<int>(txPowerDbm.value);
    }
    if (hopLimit.present) {
      map['hop_limit'] = Variable<int>(hopLimit.value);
    }
    if (frequencyMhz.present) {
      map['frequency_mhz'] = Variable<double>(frequencyMhz.value);
    }
    if (testStepId.present) {
      map['test_step_id'] = Variable<int>(testStepId.value);
    }
    if (rangeTestActive.present) {
      map['range_test_active'] = Variable<bool>(rangeTestActive.value);
    }
    if (packetCount.present) {
      map['packet_count'] = Variable<int>(packetCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('coverageMapId: $coverageMapId, ')
          ..write('name: $name, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('isActive: $isActive, ')
          ..write('remoteNodeId: $remoteNodeId, ')
          ..write('baseNodeId: $baseNodeId, ')
          ..write('hwAntenna: $hwAntenna, ')
          ..write('hwNodeModel: $hwNodeModel, ')
          ..write('hwNotes: $hwNotes, ')
          ..write('loraPreset: $loraPreset, ')
          ..write('protocol: $protocol, ')
          ..write('pingIntervalSec: $pingIntervalSec, ')
          ..write('packetAirtimeMs: $packetAirtimeMs, ')
          ..write('mobileRigId: $mobileRigId, ')
          ..write('baseRigId: $baseRigId, ')
          ..write('mobileRigJson: $mobileRigJson, ')
          ..write('baseRigJson: $baseRigJson, ')
          ..write('radioAirUtilTx: $radioAirUtilTx, ')
          ..write('radioChannelUtil: $radioChannelUtil, ')
          ..write('beaconKind: $beaconKind, ')
          ..write('beaconIntervalSec: $beaconIntervalSec, ')
          ..write('region: $region, ')
          ..write('frequencySlot: $frequencySlot, ')
          ..write('txPowerDbm: $txPowerDbm, ')
          ..write('hopLimit: $hopLimit, ')
          ..write('frequencyMhz: $frequencyMhz, ')
          ..write('testStepId: $testStepId, ')
          ..write('rangeTestActive: $rangeTestActive, ')
          ..write('packetCount: $packetCount')
          ..write(')'))
        .toString();
  }
}

class $PacketEventsTable extends PacketEvents
    with TableInfo<$PacketEventsTable, PacketEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PacketEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
      'session_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sessions (id)'));
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceNodeIdMeta =
      const VerificationMeta('sourceNodeId');
  @override
  late final GeneratedColumn<int> sourceNodeId = GeneratedColumn<int>(
      'source_node_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES nodes (id)'));
  static const VerificationMeta _rxSnrMeta = const VerificationMeta('rxSnr');
  @override
  late final GeneratedColumn<double> rxSnr = GeneratedColumn<double>(
      'rx_snr', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _rxRssiMeta = const VerificationMeta('rxRssi');
  @override
  late final GeneratedColumn<int> rxRssi = GeneratedColumn<int>(
      'rx_rssi', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _hopCountMeta =
      const VerificationMeta('hopCount');
  @override
  late final GeneratedColumn<int> hopCount = GeneratedColumn<int>(
      'hop_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _rxLatMeta = const VerificationMeta('rxLat');
  @override
  late final GeneratedColumn<double> rxLat = GeneratedColumn<double>(
      'rx_lat', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _rxLonMeta = const VerificationMeta('rxLon');
  @override
  late final GeneratedColumn<double> rxLon = GeneratedColumn<double>(
      'rx_lon', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _rxAltMeta = const VerificationMeta('rxAlt');
  @override
  late final GeneratedColumn<double> rxAlt = GeneratedColumn<double>(
      'rx_alt', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _gpsAccuracyMeta =
      const VerificationMeta('gpsAccuracy');
  @override
  late final GeneratedColumn<double> gpsAccuracy = GeneratedColumn<double>(
      'gps_accuracy', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _packetTypeMeta =
      const VerificationMeta('packetType');
  @override
  late final GeneratedColumn<String> packetType = GeneratedColumn<String>(
      'packet_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _meshPacketIdMeta =
      const VerificationMeta('meshPacketId');
  @override
  late final GeneratedColumn<int> meshPacketId = GeneratedColumn<int>(
      'mesh_packet_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _channelIndexMeta =
      const VerificationMeta('channelIndex');
  @override
  late final GeneratedColumn<int> channelIndex = GeneratedColumn<int>(
      'channel_index', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _viaMqttMeta =
      const VerificationMeta('viaMqtt');
  @override
  late final GeneratedColumn<bool> viaMqtt = GeneratedColumn<bool>(
      'via_mqtt', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("via_mqtt" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sourceKindMeta =
      const VerificationMeta('sourceKind');
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
      'source_kind', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('passive'));
  static const VerificationMeta _baseChannelUtilMeta =
      const VerificationMeta('baseChannelUtil');
  @override
  late final GeneratedColumn<double> baseChannelUtil = GeneratedColumn<double>(
      'base_channel_util', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _uplinkSnrMeta =
      const VerificationMeta('uplinkSnr');
  @override
  late final GeneratedColumn<double> uplinkSnr = GeneratedColumn<double>(
      'uplink_snr', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        sessionId,
        timestamp,
        direction,
        sourceNodeId,
        rxSnr,
        rxRssi,
        hopCount,
        rxLat,
        rxLon,
        rxAlt,
        gpsAccuracy,
        packetType,
        meshPacketId,
        channelIndex,
        viaMqtt,
        seq,
        sourceKind,
        baseChannelUtil,
        uplinkSnr
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'packet_events';
  @override
  VerificationContext validateIntegrity(Insertable<PacketEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('source_node_id')) {
      context.handle(
          _sourceNodeIdMeta,
          sourceNodeId.isAcceptableOrUnknown(
              data['source_node_id']!, _sourceNodeIdMeta));
    } else if (isInserting) {
      context.missing(_sourceNodeIdMeta);
    }
    if (data.containsKey('rx_snr')) {
      context.handle(
          _rxSnrMeta, rxSnr.isAcceptableOrUnknown(data['rx_snr']!, _rxSnrMeta));
    }
    if (data.containsKey('rx_rssi')) {
      context.handle(_rxRssiMeta,
          rxRssi.isAcceptableOrUnknown(data['rx_rssi']!, _rxRssiMeta));
    }
    if (data.containsKey('hop_count')) {
      context.handle(_hopCountMeta,
          hopCount.isAcceptableOrUnknown(data['hop_count']!, _hopCountMeta));
    }
    if (data.containsKey('rx_lat')) {
      context.handle(
          _rxLatMeta, rxLat.isAcceptableOrUnknown(data['rx_lat']!, _rxLatMeta));
    }
    if (data.containsKey('rx_lon')) {
      context.handle(
          _rxLonMeta, rxLon.isAcceptableOrUnknown(data['rx_lon']!, _rxLonMeta));
    }
    if (data.containsKey('rx_alt')) {
      context.handle(
          _rxAltMeta, rxAlt.isAcceptableOrUnknown(data['rx_alt']!, _rxAltMeta));
    }
    if (data.containsKey('gps_accuracy')) {
      context.handle(
          _gpsAccuracyMeta,
          gpsAccuracy.isAcceptableOrUnknown(
              data['gps_accuracy']!, _gpsAccuracyMeta));
    }
    if (data.containsKey('packet_type')) {
      context.handle(
          _packetTypeMeta,
          packetType.isAcceptableOrUnknown(
              data['packet_type']!, _packetTypeMeta));
    } else if (isInserting) {
      context.missing(_packetTypeMeta);
    }
    if (data.containsKey('mesh_packet_id')) {
      context.handle(
          _meshPacketIdMeta,
          meshPacketId.isAcceptableOrUnknown(
              data['mesh_packet_id']!, _meshPacketIdMeta));
    }
    if (data.containsKey('channel_index')) {
      context.handle(
          _channelIndexMeta,
          channelIndex.isAcceptableOrUnknown(
              data['channel_index']!, _channelIndexMeta));
    }
    if (data.containsKey('via_mqtt')) {
      context.handle(_viaMqttMeta,
          viaMqtt.isAcceptableOrUnknown(data['via_mqtt']!, _viaMqttMeta));
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    }
    if (data.containsKey('source_kind')) {
      context.handle(
          _sourceKindMeta,
          sourceKind.isAcceptableOrUnknown(
              data['source_kind']!, _sourceKindMeta));
    }
    if (data.containsKey('base_channel_util')) {
      context.handle(
          _baseChannelUtilMeta,
          baseChannelUtil.isAcceptableOrUnknown(
              data['base_channel_util']!, _baseChannelUtilMeta));
    }
    if (data.containsKey('uplink_snr')) {
      context.handle(_uplinkSnrMeta,
          uplinkSnr.isAcceptableOrUnknown(data['uplink_snr']!, _uplinkSnrMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PacketEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PacketEvent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}session_id'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      sourceNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}source_node_id'])!,
      rxSnr: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rx_snr']),
      rxRssi: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rx_rssi']),
      hopCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}hop_count'])!,
      rxLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rx_lat']),
      rxLon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rx_lon']),
      rxAlt: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rx_alt']),
      gpsAccuracy: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}gps_accuracy']),
      packetType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}packet_type'])!,
      meshPacketId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mesh_packet_id']),
      channelIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}channel_index'])!,
      viaMqtt: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}via_mqtt'])!,
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq']),
      sourceKind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_kind'])!,
      baseChannelUtil: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}base_channel_util']),
      uplinkSnr: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}uplink_snr']),
    );
  }

  @override
  $PacketEventsTable createAlias(String alias) {
    return $PacketEventsTable(attachedDatabase, alias);
  }
}

class PacketEvent extends DataClass implements Insertable<PacketEvent> {
  final int id;
  final int sessionId;
  final DateTime timestamp;
  final String direction;
  final int sourceNodeId;
  final double? rxSnr;
  final int? rxRssi;
  final int hopCount;
  final double? rxLat;
  final double? rxLon;
  final double? rxAlt;
  final double? gpsAccuracy;
  final String packetType;
  final int? meshPacketId;
  final int channelIndex;
  final bool viaMqtt;

  /// Beacon sequence number (Range Test `seq N`); null for anything else
  /// (schema v7).
  final int? seq;

  /// What produced the row (schema v7): `range_test | telemetry | position |
  /// ack | traceroute | passive | telemetry_miss | log_only`. Rows from
  /// before v7 and ordinary non-beacon packets are `passive`; `log_only`
  /// rows (schema v10) are packets whose over-the-air origin is unknown,
  /// kept for the log but never a coverage sample (`SourceKind.notSamples`).
  final String sourceKind;

  /// The sender's own channel utilisation (%) from a telemetry beacon:
  /// busy/noise context at the base end (schema v7).
  final double? baseChannelUtil;

  /// How well the base heard our ping (mobile → base, dB), on ping reply
  /// rows when the protocol reports it (MeshCore trace hop SNR). Null
  /// otherwise (schema v10).
  final double? uplinkSnr;
  const PacketEvent(
      {required this.id,
      required this.sessionId,
      required this.timestamp,
      required this.direction,
      required this.sourceNodeId,
      this.rxSnr,
      this.rxRssi,
      required this.hopCount,
      this.rxLat,
      this.rxLon,
      this.rxAlt,
      this.gpsAccuracy,
      required this.packetType,
      this.meshPacketId,
      required this.channelIndex,
      required this.viaMqtt,
      this.seq,
      required this.sourceKind,
      this.baseChannelUtil,
      this.uplinkSnr});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['direction'] = Variable<String>(direction);
    map['source_node_id'] = Variable<int>(sourceNodeId);
    if (!nullToAbsent || rxSnr != null) {
      map['rx_snr'] = Variable<double>(rxSnr);
    }
    if (!nullToAbsent || rxRssi != null) {
      map['rx_rssi'] = Variable<int>(rxRssi);
    }
    map['hop_count'] = Variable<int>(hopCount);
    if (!nullToAbsent || rxLat != null) {
      map['rx_lat'] = Variable<double>(rxLat);
    }
    if (!nullToAbsent || rxLon != null) {
      map['rx_lon'] = Variable<double>(rxLon);
    }
    if (!nullToAbsent || rxAlt != null) {
      map['rx_alt'] = Variable<double>(rxAlt);
    }
    if (!nullToAbsent || gpsAccuracy != null) {
      map['gps_accuracy'] = Variable<double>(gpsAccuracy);
    }
    map['packet_type'] = Variable<String>(packetType);
    if (!nullToAbsent || meshPacketId != null) {
      map['mesh_packet_id'] = Variable<int>(meshPacketId);
    }
    map['channel_index'] = Variable<int>(channelIndex);
    map['via_mqtt'] = Variable<bool>(viaMqtt);
    if (!nullToAbsent || seq != null) {
      map['seq'] = Variable<int>(seq);
    }
    map['source_kind'] = Variable<String>(sourceKind);
    if (!nullToAbsent || baseChannelUtil != null) {
      map['base_channel_util'] = Variable<double>(baseChannelUtil);
    }
    if (!nullToAbsent || uplinkSnr != null) {
      map['uplink_snr'] = Variable<double>(uplinkSnr);
    }
    return map;
  }

  PacketEventsCompanion toCompanion(bool nullToAbsent) {
    return PacketEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      timestamp: Value(timestamp),
      direction: Value(direction),
      sourceNodeId: Value(sourceNodeId),
      rxSnr:
          rxSnr == null && nullToAbsent ? const Value.absent() : Value(rxSnr),
      rxRssi:
          rxRssi == null && nullToAbsent ? const Value.absent() : Value(rxRssi),
      hopCount: Value(hopCount),
      rxLat:
          rxLat == null && nullToAbsent ? const Value.absent() : Value(rxLat),
      rxLon:
          rxLon == null && nullToAbsent ? const Value.absent() : Value(rxLon),
      rxAlt:
          rxAlt == null && nullToAbsent ? const Value.absent() : Value(rxAlt),
      gpsAccuracy: gpsAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(gpsAccuracy),
      packetType: Value(packetType),
      meshPacketId: meshPacketId == null && nullToAbsent
          ? const Value.absent()
          : Value(meshPacketId),
      channelIndex: Value(channelIndex),
      viaMqtt: Value(viaMqtt),
      seq: seq == null && nullToAbsent ? const Value.absent() : Value(seq),
      sourceKind: Value(sourceKind),
      baseChannelUtil: baseChannelUtil == null && nullToAbsent
          ? const Value.absent()
          : Value(baseChannelUtil),
      uplinkSnr: uplinkSnr == null && nullToAbsent
          ? const Value.absent()
          : Value(uplinkSnr),
    );
  }

  factory PacketEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PacketEvent(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      direction: serializer.fromJson<String>(json['direction']),
      sourceNodeId: serializer.fromJson<int>(json['sourceNodeId']),
      rxSnr: serializer.fromJson<double?>(json['rxSnr']),
      rxRssi: serializer.fromJson<int?>(json['rxRssi']),
      hopCount: serializer.fromJson<int>(json['hopCount']),
      rxLat: serializer.fromJson<double?>(json['rxLat']),
      rxLon: serializer.fromJson<double?>(json['rxLon']),
      rxAlt: serializer.fromJson<double?>(json['rxAlt']),
      gpsAccuracy: serializer.fromJson<double?>(json['gpsAccuracy']),
      packetType: serializer.fromJson<String>(json['packetType']),
      meshPacketId: serializer.fromJson<int?>(json['meshPacketId']),
      channelIndex: serializer.fromJson<int>(json['channelIndex']),
      viaMqtt: serializer.fromJson<bool>(json['viaMqtt']),
      seq: serializer.fromJson<int?>(json['seq']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      baseChannelUtil: serializer.fromJson<double?>(json['baseChannelUtil']),
      uplinkSnr: serializer.fromJson<double?>(json['uplinkSnr']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'direction': serializer.toJson<String>(direction),
      'sourceNodeId': serializer.toJson<int>(sourceNodeId),
      'rxSnr': serializer.toJson<double?>(rxSnr),
      'rxRssi': serializer.toJson<int?>(rxRssi),
      'hopCount': serializer.toJson<int>(hopCount),
      'rxLat': serializer.toJson<double?>(rxLat),
      'rxLon': serializer.toJson<double?>(rxLon),
      'rxAlt': serializer.toJson<double?>(rxAlt),
      'gpsAccuracy': serializer.toJson<double?>(gpsAccuracy),
      'packetType': serializer.toJson<String>(packetType),
      'meshPacketId': serializer.toJson<int?>(meshPacketId),
      'channelIndex': serializer.toJson<int>(channelIndex),
      'viaMqtt': serializer.toJson<bool>(viaMqtt),
      'seq': serializer.toJson<int?>(seq),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'baseChannelUtil': serializer.toJson<double?>(baseChannelUtil),
      'uplinkSnr': serializer.toJson<double?>(uplinkSnr),
    };
  }

  PacketEvent copyWith(
          {int? id,
          int? sessionId,
          DateTime? timestamp,
          String? direction,
          int? sourceNodeId,
          Value<double?> rxSnr = const Value.absent(),
          Value<int?> rxRssi = const Value.absent(),
          int? hopCount,
          Value<double?> rxLat = const Value.absent(),
          Value<double?> rxLon = const Value.absent(),
          Value<double?> rxAlt = const Value.absent(),
          Value<double?> gpsAccuracy = const Value.absent(),
          String? packetType,
          Value<int?> meshPacketId = const Value.absent(),
          int? channelIndex,
          bool? viaMqtt,
          Value<int?> seq = const Value.absent(),
          String? sourceKind,
          Value<double?> baseChannelUtil = const Value.absent(),
          Value<double?> uplinkSnr = const Value.absent()}) =>
      PacketEvent(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        timestamp: timestamp ?? this.timestamp,
        direction: direction ?? this.direction,
        sourceNodeId: sourceNodeId ?? this.sourceNodeId,
        rxSnr: rxSnr.present ? rxSnr.value : this.rxSnr,
        rxRssi: rxRssi.present ? rxRssi.value : this.rxRssi,
        hopCount: hopCount ?? this.hopCount,
        rxLat: rxLat.present ? rxLat.value : this.rxLat,
        rxLon: rxLon.present ? rxLon.value : this.rxLon,
        rxAlt: rxAlt.present ? rxAlt.value : this.rxAlt,
        gpsAccuracy: gpsAccuracy.present ? gpsAccuracy.value : this.gpsAccuracy,
        packetType: packetType ?? this.packetType,
        meshPacketId:
            meshPacketId.present ? meshPacketId.value : this.meshPacketId,
        channelIndex: channelIndex ?? this.channelIndex,
        viaMqtt: viaMqtt ?? this.viaMqtt,
        seq: seq.present ? seq.value : this.seq,
        sourceKind: sourceKind ?? this.sourceKind,
        baseChannelUtil: baseChannelUtil.present
            ? baseChannelUtil.value
            : this.baseChannelUtil,
        uplinkSnr: uplinkSnr.present ? uplinkSnr.value : this.uplinkSnr,
      );
  PacketEvent copyWithCompanion(PacketEventsCompanion data) {
    return PacketEvent(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      direction: data.direction.present ? data.direction.value : this.direction,
      sourceNodeId: data.sourceNodeId.present
          ? data.sourceNodeId.value
          : this.sourceNodeId,
      rxSnr: data.rxSnr.present ? data.rxSnr.value : this.rxSnr,
      rxRssi: data.rxRssi.present ? data.rxRssi.value : this.rxRssi,
      hopCount: data.hopCount.present ? data.hopCount.value : this.hopCount,
      rxLat: data.rxLat.present ? data.rxLat.value : this.rxLat,
      rxLon: data.rxLon.present ? data.rxLon.value : this.rxLon,
      rxAlt: data.rxAlt.present ? data.rxAlt.value : this.rxAlt,
      gpsAccuracy:
          data.gpsAccuracy.present ? data.gpsAccuracy.value : this.gpsAccuracy,
      packetType:
          data.packetType.present ? data.packetType.value : this.packetType,
      meshPacketId: data.meshPacketId.present
          ? data.meshPacketId.value
          : this.meshPacketId,
      channelIndex: data.channelIndex.present
          ? data.channelIndex.value
          : this.channelIndex,
      viaMqtt: data.viaMqtt.present ? data.viaMqtt.value : this.viaMqtt,
      seq: data.seq.present ? data.seq.value : this.seq,
      sourceKind:
          data.sourceKind.present ? data.sourceKind.value : this.sourceKind,
      baseChannelUtil: data.baseChannelUtil.present
          ? data.baseChannelUtil.value
          : this.baseChannelUtil,
      uplinkSnr: data.uplinkSnr.present ? data.uplinkSnr.value : this.uplinkSnr,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PacketEvent(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('timestamp: $timestamp, ')
          ..write('direction: $direction, ')
          ..write('sourceNodeId: $sourceNodeId, ')
          ..write('rxSnr: $rxSnr, ')
          ..write('rxRssi: $rxRssi, ')
          ..write('hopCount: $hopCount, ')
          ..write('rxLat: $rxLat, ')
          ..write('rxLon: $rxLon, ')
          ..write('rxAlt: $rxAlt, ')
          ..write('gpsAccuracy: $gpsAccuracy, ')
          ..write('packetType: $packetType, ')
          ..write('meshPacketId: $meshPacketId, ')
          ..write('channelIndex: $channelIndex, ')
          ..write('viaMqtt: $viaMqtt, ')
          ..write('seq: $seq, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('baseChannelUtil: $baseChannelUtil, ')
          ..write('uplinkSnr: $uplinkSnr')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      sessionId,
      timestamp,
      direction,
      sourceNodeId,
      rxSnr,
      rxRssi,
      hopCount,
      rxLat,
      rxLon,
      rxAlt,
      gpsAccuracy,
      packetType,
      meshPacketId,
      channelIndex,
      viaMqtt,
      seq,
      sourceKind,
      baseChannelUtil,
      uplinkSnr);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PacketEvent &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.timestamp == this.timestamp &&
          other.direction == this.direction &&
          other.sourceNodeId == this.sourceNodeId &&
          other.rxSnr == this.rxSnr &&
          other.rxRssi == this.rxRssi &&
          other.hopCount == this.hopCount &&
          other.rxLat == this.rxLat &&
          other.rxLon == this.rxLon &&
          other.rxAlt == this.rxAlt &&
          other.gpsAccuracy == this.gpsAccuracy &&
          other.packetType == this.packetType &&
          other.meshPacketId == this.meshPacketId &&
          other.channelIndex == this.channelIndex &&
          other.viaMqtt == this.viaMqtt &&
          other.seq == this.seq &&
          other.sourceKind == this.sourceKind &&
          other.baseChannelUtil == this.baseChannelUtil &&
          other.uplinkSnr == this.uplinkSnr);
}

class PacketEventsCompanion extends UpdateCompanion<PacketEvent> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<DateTime> timestamp;
  final Value<String> direction;
  final Value<int> sourceNodeId;
  final Value<double?> rxSnr;
  final Value<int?> rxRssi;
  final Value<int> hopCount;
  final Value<double?> rxLat;
  final Value<double?> rxLon;
  final Value<double?> rxAlt;
  final Value<double?> gpsAccuracy;
  final Value<String> packetType;
  final Value<int?> meshPacketId;
  final Value<int> channelIndex;
  final Value<bool> viaMqtt;
  final Value<int?> seq;
  final Value<String> sourceKind;
  final Value<double?> baseChannelUtil;
  final Value<double?> uplinkSnr;
  const PacketEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.direction = const Value.absent(),
    this.sourceNodeId = const Value.absent(),
    this.rxSnr = const Value.absent(),
    this.rxRssi = const Value.absent(),
    this.hopCount = const Value.absent(),
    this.rxLat = const Value.absent(),
    this.rxLon = const Value.absent(),
    this.rxAlt = const Value.absent(),
    this.gpsAccuracy = const Value.absent(),
    this.packetType = const Value.absent(),
    this.meshPacketId = const Value.absent(),
    this.channelIndex = const Value.absent(),
    this.viaMqtt = const Value.absent(),
    this.seq = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.baseChannelUtil = const Value.absent(),
    this.uplinkSnr = const Value.absent(),
  });
  PacketEventsCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required DateTime timestamp,
    required String direction,
    required int sourceNodeId,
    this.rxSnr = const Value.absent(),
    this.rxRssi = const Value.absent(),
    this.hopCount = const Value.absent(),
    this.rxLat = const Value.absent(),
    this.rxLon = const Value.absent(),
    this.rxAlt = const Value.absent(),
    this.gpsAccuracy = const Value.absent(),
    required String packetType,
    this.meshPacketId = const Value.absent(),
    this.channelIndex = const Value.absent(),
    this.viaMqtt = const Value.absent(),
    this.seq = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.baseChannelUtil = const Value.absent(),
    this.uplinkSnr = const Value.absent(),
  })  : sessionId = Value(sessionId),
        timestamp = Value(timestamp),
        direction = Value(direction),
        sourceNodeId = Value(sourceNodeId),
        packetType = Value(packetType);
  static Insertable<PacketEvent> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<DateTime>? timestamp,
    Expression<String>? direction,
    Expression<int>? sourceNodeId,
    Expression<double>? rxSnr,
    Expression<int>? rxRssi,
    Expression<int>? hopCount,
    Expression<double>? rxLat,
    Expression<double>? rxLon,
    Expression<double>? rxAlt,
    Expression<double>? gpsAccuracy,
    Expression<String>? packetType,
    Expression<int>? meshPacketId,
    Expression<int>? channelIndex,
    Expression<bool>? viaMqtt,
    Expression<int>? seq,
    Expression<String>? sourceKind,
    Expression<double>? baseChannelUtil,
    Expression<double>? uplinkSnr,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (timestamp != null) 'timestamp': timestamp,
      if (direction != null) 'direction': direction,
      if (sourceNodeId != null) 'source_node_id': sourceNodeId,
      if (rxSnr != null) 'rx_snr': rxSnr,
      if (rxRssi != null) 'rx_rssi': rxRssi,
      if (hopCount != null) 'hop_count': hopCount,
      if (rxLat != null) 'rx_lat': rxLat,
      if (rxLon != null) 'rx_lon': rxLon,
      if (rxAlt != null) 'rx_alt': rxAlt,
      if (gpsAccuracy != null) 'gps_accuracy': gpsAccuracy,
      if (packetType != null) 'packet_type': packetType,
      if (meshPacketId != null) 'mesh_packet_id': meshPacketId,
      if (channelIndex != null) 'channel_index': channelIndex,
      if (viaMqtt != null) 'via_mqtt': viaMqtt,
      if (seq != null) 'seq': seq,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (baseChannelUtil != null) 'base_channel_util': baseChannelUtil,
      if (uplinkSnr != null) 'uplink_snr': uplinkSnr,
    });
  }

  PacketEventsCompanion copyWith(
      {Value<int>? id,
      Value<int>? sessionId,
      Value<DateTime>? timestamp,
      Value<String>? direction,
      Value<int>? sourceNodeId,
      Value<double?>? rxSnr,
      Value<int?>? rxRssi,
      Value<int>? hopCount,
      Value<double?>? rxLat,
      Value<double?>? rxLon,
      Value<double?>? rxAlt,
      Value<double?>? gpsAccuracy,
      Value<String>? packetType,
      Value<int?>? meshPacketId,
      Value<int>? channelIndex,
      Value<bool>? viaMqtt,
      Value<int?>? seq,
      Value<String>? sourceKind,
      Value<double?>? baseChannelUtil,
      Value<double?>? uplinkSnr}) {
    return PacketEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      direction: direction ?? this.direction,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      rxSnr: rxSnr ?? this.rxSnr,
      rxRssi: rxRssi ?? this.rxRssi,
      hopCount: hopCount ?? this.hopCount,
      rxLat: rxLat ?? this.rxLat,
      rxLon: rxLon ?? this.rxLon,
      rxAlt: rxAlt ?? this.rxAlt,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      packetType: packetType ?? this.packetType,
      meshPacketId: meshPacketId ?? this.meshPacketId,
      channelIndex: channelIndex ?? this.channelIndex,
      viaMqtt: viaMqtt ?? this.viaMqtt,
      seq: seq ?? this.seq,
      sourceKind: sourceKind ?? this.sourceKind,
      baseChannelUtil: baseChannelUtil ?? this.baseChannelUtil,
      uplinkSnr: uplinkSnr ?? this.uplinkSnr,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (sourceNodeId.present) {
      map['source_node_id'] = Variable<int>(sourceNodeId.value);
    }
    if (rxSnr.present) {
      map['rx_snr'] = Variable<double>(rxSnr.value);
    }
    if (rxRssi.present) {
      map['rx_rssi'] = Variable<int>(rxRssi.value);
    }
    if (hopCount.present) {
      map['hop_count'] = Variable<int>(hopCount.value);
    }
    if (rxLat.present) {
      map['rx_lat'] = Variable<double>(rxLat.value);
    }
    if (rxLon.present) {
      map['rx_lon'] = Variable<double>(rxLon.value);
    }
    if (rxAlt.present) {
      map['rx_alt'] = Variable<double>(rxAlt.value);
    }
    if (gpsAccuracy.present) {
      map['gps_accuracy'] = Variable<double>(gpsAccuracy.value);
    }
    if (packetType.present) {
      map['packet_type'] = Variable<String>(packetType.value);
    }
    if (meshPacketId.present) {
      map['mesh_packet_id'] = Variable<int>(meshPacketId.value);
    }
    if (channelIndex.present) {
      map['channel_index'] = Variable<int>(channelIndex.value);
    }
    if (viaMqtt.present) {
      map['via_mqtt'] = Variable<bool>(viaMqtt.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (baseChannelUtil.present) {
      map['base_channel_util'] = Variable<double>(baseChannelUtil.value);
    }
    if (uplinkSnr.present) {
      map['uplink_snr'] = Variable<double>(uplinkSnr.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PacketEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('timestamp: $timestamp, ')
          ..write('direction: $direction, ')
          ..write('sourceNodeId: $sourceNodeId, ')
          ..write('rxSnr: $rxSnr, ')
          ..write('rxRssi: $rxRssi, ')
          ..write('hopCount: $hopCount, ')
          ..write('rxLat: $rxLat, ')
          ..write('rxLon: $rxLon, ')
          ..write('rxAlt: $rxAlt, ')
          ..write('gpsAccuracy: $gpsAccuracy, ')
          ..write('packetType: $packetType, ')
          ..write('meshPacketId: $meshPacketId, ')
          ..write('channelIndex: $channelIndex, ')
          ..write('viaMqtt: $viaMqtt, ')
          ..write('seq: $seq, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('baseChannelUtil: $baseChannelUtil, ')
          ..write('uplinkSnr: $uplinkSnr')
          ..write(')'))
        .toString();
  }
}

class $PingCorrelationsTable extends PingCorrelations
    with TableInfo<$PingCorrelationsTable, PingCorrelation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PingCorrelationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _txEventIdMeta =
      const VerificationMeta('txEventId');
  @override
  late final GeneratedColumn<int> txEventId = GeneratedColumn<int>(
      'tx_event_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES packet_events (id)'));
  static const VerificationMeta _ackEventIdMeta =
      const VerificationMeta('ackEventId');
  @override
  late final GeneratedColumn<int> ackEventId = GeneratedColumn<int>(
      'ack_event_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES packet_events (id)'));
  static const VerificationMeta _roundTripMsMeta =
      const VerificationMeta('roundTripMs');
  @override
  late final GeneratedColumn<int> roundTripMs = GeneratedColumn<int>(
      'round_trip_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _ackStatusMeta =
      const VerificationMeta('ackStatus');
  @override
  late final GeneratedColumn<String> ackStatus = GeneratedColumn<String>(
      'ack_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('timeout'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, txEventId, ackEventId, roundTripMs, ackStatus];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ping_correlations';
  @override
  VerificationContext validateIntegrity(Insertable<PingCorrelation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tx_event_id')) {
      context.handle(
          _txEventIdMeta,
          txEventId.isAcceptableOrUnknown(
              data['tx_event_id']!, _txEventIdMeta));
    } else if (isInserting) {
      context.missing(_txEventIdMeta);
    }
    if (data.containsKey('ack_event_id')) {
      context.handle(
          _ackEventIdMeta,
          ackEventId.isAcceptableOrUnknown(
              data['ack_event_id']!, _ackEventIdMeta));
    }
    if (data.containsKey('round_trip_ms')) {
      context.handle(
          _roundTripMsMeta,
          roundTripMs.isAcceptableOrUnknown(
              data['round_trip_ms']!, _roundTripMsMeta));
    }
    if (data.containsKey('ack_status')) {
      context.handle(_ackStatusMeta,
          ackStatus.isAcceptableOrUnknown(data['ack_status']!, _ackStatusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PingCorrelation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PingCorrelation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      txEventId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tx_event_id'])!,
      ackEventId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ack_event_id']),
      roundTripMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}round_trip_ms']),
      ackStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ack_status'])!,
    );
  }

  @override
  $PingCorrelationsTable createAlias(String alias) {
    return $PingCorrelationsTable(attachedDatabase, alias);
  }
}

class PingCorrelation extends DataClass implements Insertable<PingCorrelation> {
  final int id;
  final int txEventId;
  final int? ackEventId;
  final int? roundTripMs;
  final String ackStatus;
  const PingCorrelation(
      {required this.id,
      required this.txEventId,
      this.ackEventId,
      this.roundTripMs,
      required this.ackStatus});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tx_event_id'] = Variable<int>(txEventId);
    if (!nullToAbsent || ackEventId != null) {
      map['ack_event_id'] = Variable<int>(ackEventId);
    }
    if (!nullToAbsent || roundTripMs != null) {
      map['round_trip_ms'] = Variable<int>(roundTripMs);
    }
    map['ack_status'] = Variable<String>(ackStatus);
    return map;
  }

  PingCorrelationsCompanion toCompanion(bool nullToAbsent) {
    return PingCorrelationsCompanion(
      id: Value(id),
      txEventId: Value(txEventId),
      ackEventId: ackEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(ackEventId),
      roundTripMs: roundTripMs == null && nullToAbsent
          ? const Value.absent()
          : Value(roundTripMs),
      ackStatus: Value(ackStatus),
    );
  }

  factory PingCorrelation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PingCorrelation(
      id: serializer.fromJson<int>(json['id']),
      txEventId: serializer.fromJson<int>(json['txEventId']),
      ackEventId: serializer.fromJson<int?>(json['ackEventId']),
      roundTripMs: serializer.fromJson<int?>(json['roundTripMs']),
      ackStatus: serializer.fromJson<String>(json['ackStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'txEventId': serializer.toJson<int>(txEventId),
      'ackEventId': serializer.toJson<int?>(ackEventId),
      'roundTripMs': serializer.toJson<int?>(roundTripMs),
      'ackStatus': serializer.toJson<String>(ackStatus),
    };
  }

  PingCorrelation copyWith(
          {int? id,
          int? txEventId,
          Value<int?> ackEventId = const Value.absent(),
          Value<int?> roundTripMs = const Value.absent(),
          String? ackStatus}) =>
      PingCorrelation(
        id: id ?? this.id,
        txEventId: txEventId ?? this.txEventId,
        ackEventId: ackEventId.present ? ackEventId.value : this.ackEventId,
        roundTripMs: roundTripMs.present ? roundTripMs.value : this.roundTripMs,
        ackStatus: ackStatus ?? this.ackStatus,
      );
  PingCorrelation copyWithCompanion(PingCorrelationsCompanion data) {
    return PingCorrelation(
      id: data.id.present ? data.id.value : this.id,
      txEventId: data.txEventId.present ? data.txEventId.value : this.txEventId,
      ackEventId:
          data.ackEventId.present ? data.ackEventId.value : this.ackEventId,
      roundTripMs:
          data.roundTripMs.present ? data.roundTripMs.value : this.roundTripMs,
      ackStatus: data.ackStatus.present ? data.ackStatus.value : this.ackStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PingCorrelation(')
          ..write('id: $id, ')
          ..write('txEventId: $txEventId, ')
          ..write('ackEventId: $ackEventId, ')
          ..write('roundTripMs: $roundTripMs, ')
          ..write('ackStatus: $ackStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, txEventId, ackEventId, roundTripMs, ackStatus);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PingCorrelation &&
          other.id == this.id &&
          other.txEventId == this.txEventId &&
          other.ackEventId == this.ackEventId &&
          other.roundTripMs == this.roundTripMs &&
          other.ackStatus == this.ackStatus);
}

class PingCorrelationsCompanion extends UpdateCompanion<PingCorrelation> {
  final Value<int> id;
  final Value<int> txEventId;
  final Value<int?> ackEventId;
  final Value<int?> roundTripMs;
  final Value<String> ackStatus;
  const PingCorrelationsCompanion({
    this.id = const Value.absent(),
    this.txEventId = const Value.absent(),
    this.ackEventId = const Value.absent(),
    this.roundTripMs = const Value.absent(),
    this.ackStatus = const Value.absent(),
  });
  PingCorrelationsCompanion.insert({
    this.id = const Value.absent(),
    required int txEventId,
    this.ackEventId = const Value.absent(),
    this.roundTripMs = const Value.absent(),
    this.ackStatus = const Value.absent(),
  }) : txEventId = Value(txEventId);
  static Insertable<PingCorrelation> custom({
    Expression<int>? id,
    Expression<int>? txEventId,
    Expression<int>? ackEventId,
    Expression<int>? roundTripMs,
    Expression<String>? ackStatus,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (txEventId != null) 'tx_event_id': txEventId,
      if (ackEventId != null) 'ack_event_id': ackEventId,
      if (roundTripMs != null) 'round_trip_ms': roundTripMs,
      if (ackStatus != null) 'ack_status': ackStatus,
    });
  }

  PingCorrelationsCompanion copyWith(
      {Value<int>? id,
      Value<int>? txEventId,
      Value<int?>? ackEventId,
      Value<int?>? roundTripMs,
      Value<String>? ackStatus}) {
    return PingCorrelationsCompanion(
      id: id ?? this.id,
      txEventId: txEventId ?? this.txEventId,
      ackEventId: ackEventId ?? this.ackEventId,
      roundTripMs: roundTripMs ?? this.roundTripMs,
      ackStatus: ackStatus ?? this.ackStatus,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (txEventId.present) {
      map['tx_event_id'] = Variable<int>(txEventId.value);
    }
    if (ackEventId.present) {
      map['ack_event_id'] = Variable<int>(ackEventId.value);
    }
    if (roundTripMs.present) {
      map['round_trip_ms'] = Variable<int>(roundTripMs.value);
    }
    if (ackStatus.present) {
      map['ack_status'] = Variable<String>(ackStatus.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PingCorrelationsCompanion(')
          ..write('id: $id, ')
          ..write('txEventId: $txEventId, ')
          ..write('ackEventId: $ackEventId, ')
          ..write('roundTripMs: $roundTripMs, ')
          ..write('ackStatus: $ackStatus')
          ..write(')'))
        .toString();
  }
}

class $RigProfilesTable extends RigProfiles
    with TableInfo<$RigProfilesTable, RigProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RigProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('either'));
  static const VerificationMeta _radioModelMeta =
      const VerificationMeta('radioModel');
  @override
  late final GeneratedColumn<String> radioModel = GeneratedColumn<String>(
      'radio_model', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _antennaNameMeta =
      const VerificationMeta('antennaName');
  @override
  late final GeneratedColumn<String> antennaName = GeneratedColumn<String>(
      'antenna_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _antennaGainDbiMeta =
      const VerificationMeta('antennaGainDbi');
  @override
  late final GeneratedColumn<double> antennaGainDbi = GeneratedColumn<double>(
      'antenna_gain_dbi', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _cableTypeMeta =
      const VerificationMeta('cableType');
  @override
  late final GeneratedColumn<String> cableType = GeneratedColumn<String>(
      'cable_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('none'));
  static const VerificationMeta _cableLengthMMeta =
      const VerificationMeta('cableLengthM');
  @override
  late final GeneratedColumn<double> cableLengthM = GeneratedColumn<double>(
      'cable_length_m', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _connectorCountMeta =
      const VerificationMeta('connectorCount');
  @override
  late final GeneratedColumn<int> connectorCount = GeneratedColumn<int>(
      'connector_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _connectorLossDbMeta =
      const VerificationMeta('connectorLossDb');
  @override
  late final GeneratedColumn<double> connectorLossDb = GeneratedColumn<double>(
      'connector_loss_db', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.1));
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _archivedMeta =
      const VerificationMeta('archived');
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
      'archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        role,
        radioModel,
        antennaName,
        antennaGainDbi,
        cableType,
        cableLengthM,
        connectorCount,
        connectorLossDb,
        notes,
        createdAt,
        updatedAt,
        archived
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rig_profiles';
  @override
  VerificationContext validateIntegrity(Insertable<RigProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('radio_model')) {
      context.handle(
          _radioModelMeta,
          radioModel.isAcceptableOrUnknown(
              data['radio_model']!, _radioModelMeta));
    }
    if (data.containsKey('antenna_name')) {
      context.handle(
          _antennaNameMeta,
          antennaName.isAcceptableOrUnknown(
              data['antenna_name']!, _antennaNameMeta));
    }
    if (data.containsKey('antenna_gain_dbi')) {
      context.handle(
          _antennaGainDbiMeta,
          antennaGainDbi.isAcceptableOrUnknown(
              data['antenna_gain_dbi']!, _antennaGainDbiMeta));
    }
    if (data.containsKey('cable_type')) {
      context.handle(_cableTypeMeta,
          cableType.isAcceptableOrUnknown(data['cable_type']!, _cableTypeMeta));
    }
    if (data.containsKey('cable_length_m')) {
      context.handle(
          _cableLengthMMeta,
          cableLengthM.isAcceptableOrUnknown(
              data['cable_length_m']!, _cableLengthMMeta));
    }
    if (data.containsKey('connector_count')) {
      context.handle(
          _connectorCountMeta,
          connectorCount.isAcceptableOrUnknown(
              data['connector_count']!, _connectorCountMeta));
    }
    if (data.containsKey('connector_loss_db')) {
      context.handle(
          _connectorLossDbMeta,
          connectorLossDb.isAcceptableOrUnknown(
              data['connector_loss_db']!, _connectorLossDbMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('archived')) {
      context.handle(_archivedMeta,
          archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RigProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RigProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      radioModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}radio_model'])!,
      antennaName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}antenna_name'])!,
      antennaGainDbi: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}antenna_gain_dbi'])!,
      cableType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cable_type'])!,
      cableLengthM: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}cable_length_m'])!,
      connectorCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}connector_count'])!,
      connectorLossDb: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}connector_loss_db'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      archived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}archived'])!,
    );
  }

  @override
  $RigProfilesTable createAlias(String alias) {
    return $RigProfilesTable(attachedDatabase, alias);
  }
}

class RigProfile extends DataClass implements Insertable<RigProfile> {
  final int id;
  final String name;
  final String role;
  final String radioModel;
  final String antennaName;
  final double antennaGainDbi;
  final String cableType;
  final double cableLengthM;
  final int connectorCount;
  final double connectorLossDb;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;
  const RigProfile(
      {required this.id,
      required this.name,
      required this.role,
      required this.radioModel,
      required this.antennaName,
      required this.antennaGainDbi,
      required this.cableType,
      required this.cableLengthM,
      required this.connectorCount,
      required this.connectorLossDb,
      required this.notes,
      required this.createdAt,
      required this.updatedAt,
      required this.archived});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['role'] = Variable<String>(role);
    map['radio_model'] = Variable<String>(radioModel);
    map['antenna_name'] = Variable<String>(antennaName);
    map['antenna_gain_dbi'] = Variable<double>(antennaGainDbi);
    map['cable_type'] = Variable<String>(cableType);
    map['cable_length_m'] = Variable<double>(cableLengthM);
    map['connector_count'] = Variable<int>(connectorCount);
    map['connector_loss_db'] = Variable<double>(connectorLossDb);
    map['notes'] = Variable<String>(notes);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  RigProfilesCompanion toCompanion(bool nullToAbsent) {
    return RigProfilesCompanion(
      id: Value(id),
      name: Value(name),
      role: Value(role),
      radioModel: Value(radioModel),
      antennaName: Value(antennaName),
      antennaGainDbi: Value(antennaGainDbi),
      cableType: Value(cableType),
      cableLengthM: Value(cableLengthM),
      connectorCount: Value(connectorCount),
      connectorLossDb: Value(connectorLossDb),
      notes: Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archived: Value(archived),
    );
  }

  factory RigProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RigProfile(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String>(json['role']),
      radioModel: serializer.fromJson<String>(json['radioModel']),
      antennaName: serializer.fromJson<String>(json['antennaName']),
      antennaGainDbi: serializer.fromJson<double>(json['antennaGainDbi']),
      cableType: serializer.fromJson<String>(json['cableType']),
      cableLengthM: serializer.fromJson<double>(json['cableLengthM']),
      connectorCount: serializer.fromJson<int>(json['connectorCount']),
      connectorLossDb: serializer.fromJson<double>(json['connectorLossDb']),
      notes: serializer.fromJson<String>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String>(role),
      'radioModel': serializer.toJson<String>(radioModel),
      'antennaName': serializer.toJson<String>(antennaName),
      'antennaGainDbi': serializer.toJson<double>(antennaGainDbi),
      'cableType': serializer.toJson<String>(cableType),
      'cableLengthM': serializer.toJson<double>(cableLengthM),
      'connectorCount': serializer.toJson<int>(connectorCount),
      'connectorLossDb': serializer.toJson<double>(connectorLossDb),
      'notes': serializer.toJson<String>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  RigProfile copyWith(
          {int? id,
          String? name,
          String? role,
          String? radioModel,
          String? antennaName,
          double? antennaGainDbi,
          String? cableType,
          double? cableLengthM,
          int? connectorCount,
          double? connectorLossDb,
          String? notes,
          DateTime? createdAt,
          DateTime? updatedAt,
          bool? archived}) =>
      RigProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        role: role ?? this.role,
        radioModel: radioModel ?? this.radioModel,
        antennaName: antennaName ?? this.antennaName,
        antennaGainDbi: antennaGainDbi ?? this.antennaGainDbi,
        cableType: cableType ?? this.cableType,
        cableLengthM: cableLengthM ?? this.cableLengthM,
        connectorCount: connectorCount ?? this.connectorCount,
        connectorLossDb: connectorLossDb ?? this.connectorLossDb,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        archived: archived ?? this.archived,
      );
  RigProfile copyWithCompanion(RigProfilesCompanion data) {
    return RigProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      radioModel:
          data.radioModel.present ? data.radioModel.value : this.radioModel,
      antennaName:
          data.antennaName.present ? data.antennaName.value : this.antennaName,
      antennaGainDbi: data.antennaGainDbi.present
          ? data.antennaGainDbi.value
          : this.antennaGainDbi,
      cableType: data.cableType.present ? data.cableType.value : this.cableType,
      cableLengthM: data.cableLengthM.present
          ? data.cableLengthM.value
          : this.cableLengthM,
      connectorCount: data.connectorCount.present
          ? data.connectorCount.value
          : this.connectorCount,
      connectorLossDb: data.connectorLossDb.present
          ? data.connectorLossDb.value
          : this.connectorLossDb,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RigProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('radioModel: $radioModel, ')
          ..write('antennaName: $antennaName, ')
          ..write('antennaGainDbi: $antennaGainDbi, ')
          ..write('cableType: $cableType, ')
          ..write('cableLengthM: $cableLengthM, ')
          ..write('connectorCount: $connectorCount, ')
          ..write('connectorLossDb: $connectorLossDb, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      role,
      radioModel,
      antennaName,
      antennaGainDbi,
      cableType,
      cableLengthM,
      connectorCount,
      connectorLossDb,
      notes,
      createdAt,
      updatedAt,
      archived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RigProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.role == this.role &&
          other.radioModel == this.radioModel &&
          other.antennaName == this.antennaName &&
          other.antennaGainDbi == this.antennaGainDbi &&
          other.cableType == this.cableType &&
          other.cableLengthM == this.cableLengthM &&
          other.connectorCount == this.connectorCount &&
          other.connectorLossDb == this.connectorLossDb &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archived == this.archived);
}

class RigProfilesCompanion extends UpdateCompanion<RigProfile> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> role;
  final Value<String> radioModel;
  final Value<String> antennaName;
  final Value<double> antennaGainDbi;
  final Value<String> cableType;
  final Value<double> cableLengthM;
  final Value<int> connectorCount;
  final Value<double> connectorLossDb;
  final Value<String> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> archived;
  const RigProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.radioModel = const Value.absent(),
    this.antennaName = const Value.absent(),
    this.antennaGainDbi = const Value.absent(),
    this.cableType = const Value.absent(),
    this.cableLengthM = const Value.absent(),
    this.connectorCount = const Value.absent(),
    this.connectorLossDb = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archived = const Value.absent(),
  });
  RigProfilesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.role = const Value.absent(),
    this.radioModel = const Value.absent(),
    this.antennaName = const Value.absent(),
    this.antennaGainDbi = const Value.absent(),
    this.cableType = const Value.absent(),
    this.cableLengthM = const Value.absent(),
    this.connectorCount = const Value.absent(),
    this.connectorLossDb = const Value.absent(),
    this.notes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.archived = const Value.absent(),
  })  : name = Value(name),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<RigProfile> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? role,
    Expression<String>? radioModel,
    Expression<String>? antennaName,
    Expression<double>? antennaGainDbi,
    Expression<String>? cableType,
    Expression<double>? cableLengthM,
    Expression<int>? connectorCount,
    Expression<double>? connectorLossDb,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (radioModel != null) 'radio_model': radioModel,
      if (antennaName != null) 'antenna_name': antennaName,
      if (antennaGainDbi != null) 'antenna_gain_dbi': antennaGainDbi,
      if (cableType != null) 'cable_type': cableType,
      if (cableLengthM != null) 'cable_length_m': cableLengthM,
      if (connectorCount != null) 'connector_count': connectorCount,
      if (connectorLossDb != null) 'connector_loss_db': connectorLossDb,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archived != null) 'archived': archived,
    });
  }

  RigProfilesCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String>? role,
      Value<String>? radioModel,
      Value<String>? antennaName,
      Value<double>? antennaGainDbi,
      Value<String>? cableType,
      Value<double>? cableLengthM,
      Value<int>? connectorCount,
      Value<double>? connectorLossDb,
      Value<String>? notes,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<bool>? archived}) {
    return RigProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      radioModel: radioModel ?? this.radioModel,
      antennaName: antennaName ?? this.antennaName,
      antennaGainDbi: antennaGainDbi ?? this.antennaGainDbi,
      cableType: cableType ?? this.cableType,
      cableLengthM: cableLengthM ?? this.cableLengthM,
      connectorCount: connectorCount ?? this.connectorCount,
      connectorLossDb: connectorLossDb ?? this.connectorLossDb,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (radioModel.present) {
      map['radio_model'] = Variable<String>(radioModel.value);
    }
    if (antennaName.present) {
      map['antenna_name'] = Variable<String>(antennaName.value);
    }
    if (antennaGainDbi.present) {
      map['antenna_gain_dbi'] = Variable<double>(antennaGainDbi.value);
    }
    if (cableType.present) {
      map['cable_type'] = Variable<String>(cableType.value);
    }
    if (cableLengthM.present) {
      map['cable_length_m'] = Variable<double>(cableLengthM.value);
    }
    if (connectorCount.present) {
      map['connector_count'] = Variable<int>(connectorCount.value);
    }
    if (connectorLossDb.present) {
      map['connector_loss_db'] = Variable<double>(connectorLossDb.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RigProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('radioModel: $radioModel, ')
          ..write('antennaName: $antennaName, ')
          ..write('antennaGainDbi: $antennaGainDbi, ')
          ..write('cableType: $cableType, ')
          ..write('cableLengthM: $cableLengthM, ')
          ..write('connectorCount: $connectorCount, ')
          ..write('connectorLossDb: $connectorLossDb, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $TestPlansTable extends TestPlans
    with TableInfo<$TestPlansTable, TestPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TestPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _coverageMapIdMeta =
      const VerificationMeta('coverageMapId');
  @override
  late final GeneratedColumn<int> coverageMapId = GeneratedColumn<int>(
      'coverage_map_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES coverage_maps (id)'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _templateMeta =
      const VerificationMeta('template');
  @override
  late final GeneratedColumn<String> template = GeneratedColumn<String>(
      'template', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _intentJsonMeta =
      const VerificationMeta('intentJson');
  @override
  late final GeneratedColumn<String> intentJson = GeneratedColumn<String>(
      'intent_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('draft'));
  static const VerificationMeta _currentStepMeta =
      const VerificationMeta('currentStep');
  @override
  late final GeneratedColumn<int> currentStep = GeneratedColumn<int>(
      'current_step', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _remoteChangesMeta =
      const VerificationMeta('remoteChanges');
  @override
  late final GeneratedColumn<bool> remoteChanges = GeneratedColumn<bool>(
      'remote_changes', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("remote_changes" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _finishedAtMeta =
      const VerificationMeta('finishedAt');
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
      'finished_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _resultJsonMeta =
      const VerificationMeta('resultJson');
  @override
  late final GeneratedColumn<String> resultJson = GeneratedColumn<String>(
      'result_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _aiResultJsonMeta =
      const VerificationMeta('aiResultJson');
  @override
  late final GeneratedColumn<String> aiResultJson = GeneratedColumn<String>(
      'ai_result_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        coverageMapId,
        title,
        template,
        intentJson,
        status,
        currentStep,
        remoteChanges,
        createdAt,
        finishedAt,
        resultJson,
        aiResultJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'test_plans';
  @override
  VerificationContext validateIntegrity(Insertable<TestPlan> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('coverage_map_id')) {
      context.handle(
          _coverageMapIdMeta,
          coverageMapId.isAcceptableOrUnknown(
              data['coverage_map_id']!, _coverageMapIdMeta));
    } else if (isInserting) {
      context.missing(_coverageMapIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('template')) {
      context.handle(_templateMeta,
          template.isAcceptableOrUnknown(data['template']!, _templateMeta));
    } else if (isInserting) {
      context.missing(_templateMeta);
    }
    if (data.containsKey('intent_json')) {
      context.handle(
          _intentJsonMeta,
          intentJson.isAcceptableOrUnknown(
              data['intent_json']!, _intentJsonMeta));
    } else if (isInserting) {
      context.missing(_intentJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('current_step')) {
      context.handle(
          _currentStepMeta,
          currentStep.isAcceptableOrUnknown(
              data['current_step']!, _currentStepMeta));
    }
    if (data.containsKey('remote_changes')) {
      context.handle(
          _remoteChangesMeta,
          remoteChanges.isAcceptableOrUnknown(
              data['remote_changes']!, _remoteChangesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
          _finishedAtMeta,
          finishedAt.isAcceptableOrUnknown(
              data['finished_at']!, _finishedAtMeta));
    }
    if (data.containsKey('result_json')) {
      context.handle(
          _resultJsonMeta,
          resultJson.isAcceptableOrUnknown(
              data['result_json']!, _resultJsonMeta));
    }
    if (data.containsKey('ai_result_json')) {
      context.handle(
          _aiResultJsonMeta,
          aiResultJson.isAcceptableOrUnknown(
              data['ai_result_json']!, _aiResultJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TestPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TestPlan(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      coverageMapId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}coverage_map_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      template: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}template'])!,
      intentJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}intent_json'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      currentStep: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}current_step'])!,
      remoteChanges: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}remote_changes'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      finishedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}finished_at']),
      resultJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}result_json']),
      aiResultJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ai_result_json']),
    );
  }

  @override
  $TestPlansTable createAlias(String alias) {
    return $TestPlansTable(attachedDatabase, alias);
  }
}

class TestPlan extends DataClass implements Insertable<TestPlan> {
  final int id;
  final int coverageMapId;
  final String title;

  /// `PlanTemplate.name`.
  final String template;

  /// `PlanIntent.toJson()`.
  final String intentJson;

  /// `PlanStatus.name`: draft | running | paused | done | abandoned.
  final String status;

  /// Ordinal of the current step while running or paused.
  final int currentStep;

  /// The base is changed from a distance (Meshtastic remote admin) rather
  /// than by walking to it.
  final bool remoteChanges;
  final DateTime createdAt;
  final DateTime? finishedAt;

  /// `PlanAnalysisResult.toJson()` once analysed.
  final String? resultJson;

  /// Cached AI narrative, so reopening does not re-bill.
  final String? aiResultJson;
  const TestPlan(
      {required this.id,
      required this.coverageMapId,
      required this.title,
      required this.template,
      required this.intentJson,
      required this.status,
      required this.currentStep,
      required this.remoteChanges,
      required this.createdAt,
      this.finishedAt,
      this.resultJson,
      this.aiResultJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['coverage_map_id'] = Variable<int>(coverageMapId);
    map['title'] = Variable<String>(title);
    map['template'] = Variable<String>(template);
    map['intent_json'] = Variable<String>(intentJson);
    map['status'] = Variable<String>(status);
    map['current_step'] = Variable<int>(currentStep);
    map['remote_changes'] = Variable<bool>(remoteChanges);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    if (!nullToAbsent || resultJson != null) {
      map['result_json'] = Variable<String>(resultJson);
    }
    if (!nullToAbsent || aiResultJson != null) {
      map['ai_result_json'] = Variable<String>(aiResultJson);
    }
    return map;
  }

  TestPlansCompanion toCompanion(bool nullToAbsent) {
    return TestPlansCompanion(
      id: Value(id),
      coverageMapId: Value(coverageMapId),
      title: Value(title),
      template: Value(template),
      intentJson: Value(intentJson),
      status: Value(status),
      currentStep: Value(currentStep),
      remoteChanges: Value(remoteChanges),
      createdAt: Value(createdAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      resultJson: resultJson == null && nullToAbsent
          ? const Value.absent()
          : Value(resultJson),
      aiResultJson: aiResultJson == null && nullToAbsent
          ? const Value.absent()
          : Value(aiResultJson),
    );
  }

  factory TestPlan.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TestPlan(
      id: serializer.fromJson<int>(json['id']),
      coverageMapId: serializer.fromJson<int>(json['coverageMapId']),
      title: serializer.fromJson<String>(json['title']),
      template: serializer.fromJson<String>(json['template']),
      intentJson: serializer.fromJson<String>(json['intentJson']),
      status: serializer.fromJson<String>(json['status']),
      currentStep: serializer.fromJson<int>(json['currentStep']),
      remoteChanges: serializer.fromJson<bool>(json['remoteChanges']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      resultJson: serializer.fromJson<String?>(json['resultJson']),
      aiResultJson: serializer.fromJson<String?>(json['aiResultJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'coverageMapId': serializer.toJson<int>(coverageMapId),
      'title': serializer.toJson<String>(title),
      'template': serializer.toJson<String>(template),
      'intentJson': serializer.toJson<String>(intentJson),
      'status': serializer.toJson<String>(status),
      'currentStep': serializer.toJson<int>(currentStep),
      'remoteChanges': serializer.toJson<bool>(remoteChanges),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'resultJson': serializer.toJson<String?>(resultJson),
      'aiResultJson': serializer.toJson<String?>(aiResultJson),
    };
  }

  TestPlan copyWith(
          {int? id,
          int? coverageMapId,
          String? title,
          String? template,
          String? intentJson,
          String? status,
          int? currentStep,
          bool? remoteChanges,
          DateTime? createdAt,
          Value<DateTime?> finishedAt = const Value.absent(),
          Value<String?> resultJson = const Value.absent(),
          Value<String?> aiResultJson = const Value.absent()}) =>
      TestPlan(
        id: id ?? this.id,
        coverageMapId: coverageMapId ?? this.coverageMapId,
        title: title ?? this.title,
        template: template ?? this.template,
        intentJson: intentJson ?? this.intentJson,
        status: status ?? this.status,
        currentStep: currentStep ?? this.currentStep,
        remoteChanges: remoteChanges ?? this.remoteChanges,
        createdAt: createdAt ?? this.createdAt,
        finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
        resultJson: resultJson.present ? resultJson.value : this.resultJson,
        aiResultJson:
            aiResultJson.present ? aiResultJson.value : this.aiResultJson,
      );
  TestPlan copyWithCompanion(TestPlansCompanion data) {
    return TestPlan(
      id: data.id.present ? data.id.value : this.id,
      coverageMapId: data.coverageMapId.present
          ? data.coverageMapId.value
          : this.coverageMapId,
      title: data.title.present ? data.title.value : this.title,
      template: data.template.present ? data.template.value : this.template,
      intentJson:
          data.intentJson.present ? data.intentJson.value : this.intentJson,
      status: data.status.present ? data.status.value : this.status,
      currentStep:
          data.currentStep.present ? data.currentStep.value : this.currentStep,
      remoteChanges: data.remoteChanges.present
          ? data.remoteChanges.value
          : this.remoteChanges,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      finishedAt:
          data.finishedAt.present ? data.finishedAt.value : this.finishedAt,
      resultJson:
          data.resultJson.present ? data.resultJson.value : this.resultJson,
      aiResultJson: data.aiResultJson.present
          ? data.aiResultJson.value
          : this.aiResultJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TestPlan(')
          ..write('id: $id, ')
          ..write('coverageMapId: $coverageMapId, ')
          ..write('title: $title, ')
          ..write('template: $template, ')
          ..write('intentJson: $intentJson, ')
          ..write('status: $status, ')
          ..write('currentStep: $currentStep, ')
          ..write('remoteChanges: $remoteChanges, ')
          ..write('createdAt: $createdAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('resultJson: $resultJson, ')
          ..write('aiResultJson: $aiResultJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      coverageMapId,
      title,
      template,
      intentJson,
      status,
      currentStep,
      remoteChanges,
      createdAt,
      finishedAt,
      resultJson,
      aiResultJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TestPlan &&
          other.id == this.id &&
          other.coverageMapId == this.coverageMapId &&
          other.title == this.title &&
          other.template == this.template &&
          other.intentJson == this.intentJson &&
          other.status == this.status &&
          other.currentStep == this.currentStep &&
          other.remoteChanges == this.remoteChanges &&
          other.createdAt == this.createdAt &&
          other.finishedAt == this.finishedAt &&
          other.resultJson == this.resultJson &&
          other.aiResultJson == this.aiResultJson);
}

class TestPlansCompanion extends UpdateCompanion<TestPlan> {
  final Value<int> id;
  final Value<int> coverageMapId;
  final Value<String> title;
  final Value<String> template;
  final Value<String> intentJson;
  final Value<String> status;
  final Value<int> currentStep;
  final Value<bool> remoteChanges;
  final Value<DateTime> createdAt;
  final Value<DateTime?> finishedAt;
  final Value<String?> resultJson;
  final Value<String?> aiResultJson;
  const TestPlansCompanion({
    this.id = const Value.absent(),
    this.coverageMapId = const Value.absent(),
    this.title = const Value.absent(),
    this.template = const Value.absent(),
    this.intentJson = const Value.absent(),
    this.status = const Value.absent(),
    this.currentStep = const Value.absent(),
    this.remoteChanges = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.resultJson = const Value.absent(),
    this.aiResultJson = const Value.absent(),
  });
  TestPlansCompanion.insert({
    this.id = const Value.absent(),
    required int coverageMapId,
    required String title,
    required String template,
    required String intentJson,
    this.status = const Value.absent(),
    this.currentStep = const Value.absent(),
    this.remoteChanges = const Value.absent(),
    required DateTime createdAt,
    this.finishedAt = const Value.absent(),
    this.resultJson = const Value.absent(),
    this.aiResultJson = const Value.absent(),
  })  : coverageMapId = Value(coverageMapId),
        title = Value(title),
        template = Value(template),
        intentJson = Value(intentJson),
        createdAt = Value(createdAt);
  static Insertable<TestPlan> custom({
    Expression<int>? id,
    Expression<int>? coverageMapId,
    Expression<String>? title,
    Expression<String>? template,
    Expression<String>? intentJson,
    Expression<String>? status,
    Expression<int>? currentStep,
    Expression<bool>? remoteChanges,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? finishedAt,
    Expression<String>? resultJson,
    Expression<String>? aiResultJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (coverageMapId != null) 'coverage_map_id': coverageMapId,
      if (title != null) 'title': title,
      if (template != null) 'template': template,
      if (intentJson != null) 'intent_json': intentJson,
      if (status != null) 'status': status,
      if (currentStep != null) 'current_step': currentStep,
      if (remoteChanges != null) 'remote_changes': remoteChanges,
      if (createdAt != null) 'created_at': createdAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (resultJson != null) 'result_json': resultJson,
      if (aiResultJson != null) 'ai_result_json': aiResultJson,
    });
  }

  TestPlansCompanion copyWith(
      {Value<int>? id,
      Value<int>? coverageMapId,
      Value<String>? title,
      Value<String>? template,
      Value<String>? intentJson,
      Value<String>? status,
      Value<int>? currentStep,
      Value<bool>? remoteChanges,
      Value<DateTime>? createdAt,
      Value<DateTime?>? finishedAt,
      Value<String?>? resultJson,
      Value<String?>? aiResultJson}) {
    return TestPlansCompanion(
      id: id ?? this.id,
      coverageMapId: coverageMapId ?? this.coverageMapId,
      title: title ?? this.title,
      template: template ?? this.template,
      intentJson: intentJson ?? this.intentJson,
      status: status ?? this.status,
      currentStep: currentStep ?? this.currentStep,
      remoteChanges: remoteChanges ?? this.remoteChanges,
      createdAt: createdAt ?? this.createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      resultJson: resultJson ?? this.resultJson,
      aiResultJson: aiResultJson ?? this.aiResultJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (coverageMapId.present) {
      map['coverage_map_id'] = Variable<int>(coverageMapId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (template.present) {
      map['template'] = Variable<String>(template.value);
    }
    if (intentJson.present) {
      map['intent_json'] = Variable<String>(intentJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (currentStep.present) {
      map['current_step'] = Variable<int>(currentStep.value);
    }
    if (remoteChanges.present) {
      map['remote_changes'] = Variable<bool>(remoteChanges.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (resultJson.present) {
      map['result_json'] = Variable<String>(resultJson.value);
    }
    if (aiResultJson.present) {
      map['ai_result_json'] = Variable<String>(aiResultJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TestPlansCompanion(')
          ..write('id: $id, ')
          ..write('coverageMapId: $coverageMapId, ')
          ..write('title: $title, ')
          ..write('template: $template, ')
          ..write('intentJson: $intentJson, ')
          ..write('status: $status, ')
          ..write('currentStep: $currentStep, ')
          ..write('remoteChanges: $remoteChanges, ')
          ..write('createdAt: $createdAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('resultJson: $resultJson, ')
          ..write('aiResultJson: $aiResultJson')
          ..write(')'))
        .toString();
  }
}

class $TestStepsTable extends TestSteps
    with TableInfo<$TestStepsTable, TestStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TestStepsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<int> planId = GeneratedColumn<int>(
      'plan_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES test_plans (id)'));
  static const VerificationMeta _ordinalMeta =
      const VerificationMeta('ordinal');
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
      'ordinal', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _variantMeta =
      const VerificationMeta('variant');
  @override
  late final GeneratedColumn<int> variant = GeneratedColumn<int>(
      'variant', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _instructionMeta =
      const VerificationMeta('instruction');
  @override
  late final GeneratedColumn<String> instruction = GeneratedColumn<String>(
      'instruction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _summaryMeta =
      const VerificationMeta('summary');
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
      'summary', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _paramsJsonMeta =
      const VerificationMeta('paramsJson');
  @override
  late final GeneratedColumn<String> paramsJson = GeneratedColumn<String>(
      'params_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('todo'));
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
      'session_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sessions (id)'));
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _endedAtMeta =
      const VerificationMeta('endedAt');
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
      'ended_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        planId,
        ordinal,
        kind,
        variant,
        title,
        instruction,
        summary,
        paramsJson,
        status,
        sessionId,
        startedAt,
        endedAt,
        note
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'test_steps';
  @override
  VerificationContext validateIntegrity(Insertable<TestStep> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('plan_id')) {
      context.handle(_planIdMeta,
          planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta));
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(_ordinalMeta,
          ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta));
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('variant')) {
      context.handle(_variantMeta,
          variant.isAcceptableOrUnknown(data['variant']!, _variantMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('instruction')) {
      context.handle(
          _instructionMeta,
          instruction.isAcceptableOrUnknown(
              data['instruction']!, _instructionMeta));
    } else if (isInserting) {
      context.missing(_instructionMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(_summaryMeta,
          summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta));
    }
    if (data.containsKey('params_json')) {
      context.handle(
          _paramsJsonMeta,
          paramsJson.isAcceptableOrUnknown(
              data['params_json']!, _paramsJsonMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    }
    if (data.containsKey('ended_at')) {
      context.handle(_endedAtMeta,
          endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TestStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TestStep(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      planId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}plan_id'])!,
      ordinal: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ordinal'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      variant: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}variant']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      instruction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}instruction'])!,
      summary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary'])!,
      paramsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}params_json'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}session_id']),
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at']),
      endedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ended_at']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note'])!,
    );
  }

  @override
  $TestStepsTable createAlias(String alias) {
    return $TestStepsTable(attachedDatabase, alias);
  }
}

class TestStep extends DataClass implements Insertable<TestStep> {
  final int id;
  final int planId;
  final int ordinal;

  /// `StepKind.name`.
  final String kind;

  /// Index into the intent's variants; null for preflight/goTo/analyze.
  final int? variant;
  final String title;
  final String instruction;
  final String summary;
  final String paramsJson;

  /// `StepStatus.name`: todo | active | done | skipped.
  final String status;

  /// The session a `walk` step recorded.
  final int? sessionId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String note;
  const TestStep(
      {required this.id,
      required this.planId,
      required this.ordinal,
      required this.kind,
      this.variant,
      required this.title,
      required this.instruction,
      required this.summary,
      required this.paramsJson,
      required this.status,
      this.sessionId,
      this.startedAt,
      this.endedAt,
      required this.note});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['plan_id'] = Variable<int>(planId);
    map['ordinal'] = Variable<int>(ordinal);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || variant != null) {
      map['variant'] = Variable<int>(variant);
    }
    map['title'] = Variable<String>(title);
    map['instruction'] = Variable<String>(instruction);
    map['summary'] = Variable<String>(summary);
    map['params_json'] = Variable<String>(paramsJson);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<int>(sessionId);
    }
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['note'] = Variable<String>(note);
    return map;
  }

  TestStepsCompanion toCompanion(bool nullToAbsent) {
    return TestStepsCompanion(
      id: Value(id),
      planId: Value(planId),
      ordinal: Value(ordinal),
      kind: Value(kind),
      variant: variant == null && nullToAbsent
          ? const Value.absent()
          : Value(variant),
      title: Value(title),
      instruction: Value(instruction),
      summary: Value(summary),
      paramsJson: Value(paramsJson),
      status: Value(status),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      note: Value(note),
    );
  }

  factory TestStep.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TestStep(
      id: serializer.fromJson<int>(json['id']),
      planId: serializer.fromJson<int>(json['planId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      kind: serializer.fromJson<String>(json['kind']),
      variant: serializer.fromJson<int?>(json['variant']),
      title: serializer.fromJson<String>(json['title']),
      instruction: serializer.fromJson<String>(json['instruction']),
      summary: serializer.fromJson<String>(json['summary']),
      paramsJson: serializer.fromJson<String>(json['paramsJson']),
      status: serializer.fromJson<String>(json['status']),
      sessionId: serializer.fromJson<int?>(json['sessionId']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'planId': serializer.toJson<int>(planId),
      'ordinal': serializer.toJson<int>(ordinal),
      'kind': serializer.toJson<String>(kind),
      'variant': serializer.toJson<int?>(variant),
      'title': serializer.toJson<String>(title),
      'instruction': serializer.toJson<String>(instruction),
      'summary': serializer.toJson<String>(summary),
      'paramsJson': serializer.toJson<String>(paramsJson),
      'status': serializer.toJson<String>(status),
      'sessionId': serializer.toJson<int?>(sessionId),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'note': serializer.toJson<String>(note),
    };
  }

  TestStep copyWith(
          {int? id,
          int? planId,
          int? ordinal,
          String? kind,
          Value<int?> variant = const Value.absent(),
          String? title,
          String? instruction,
          String? summary,
          String? paramsJson,
          String? status,
          Value<int?> sessionId = const Value.absent(),
          Value<DateTime?> startedAt = const Value.absent(),
          Value<DateTime?> endedAt = const Value.absent(),
          String? note}) =>
      TestStep(
        id: id ?? this.id,
        planId: planId ?? this.planId,
        ordinal: ordinal ?? this.ordinal,
        kind: kind ?? this.kind,
        variant: variant.present ? variant.value : this.variant,
        title: title ?? this.title,
        instruction: instruction ?? this.instruction,
        summary: summary ?? this.summary,
        paramsJson: paramsJson ?? this.paramsJson,
        status: status ?? this.status,
        sessionId: sessionId.present ? sessionId.value : this.sessionId,
        startedAt: startedAt.present ? startedAt.value : this.startedAt,
        endedAt: endedAt.present ? endedAt.value : this.endedAt,
        note: note ?? this.note,
      );
  TestStep copyWithCompanion(TestStepsCompanion data) {
    return TestStep(
      id: data.id.present ? data.id.value : this.id,
      planId: data.planId.present ? data.planId.value : this.planId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      kind: data.kind.present ? data.kind.value : this.kind,
      variant: data.variant.present ? data.variant.value : this.variant,
      title: data.title.present ? data.title.value : this.title,
      instruction:
          data.instruction.present ? data.instruction.value : this.instruction,
      summary: data.summary.present ? data.summary.value : this.summary,
      paramsJson:
          data.paramsJson.present ? data.paramsJson.value : this.paramsJson,
      status: data.status.present ? data.status.value : this.status,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TestStep(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('ordinal: $ordinal, ')
          ..write('kind: $kind, ')
          ..write('variant: $variant, ')
          ..write('title: $title, ')
          ..write('instruction: $instruction, ')
          ..write('summary: $summary, ')
          ..write('paramsJson: $paramsJson, ')
          ..write('status: $status, ')
          ..write('sessionId: $sessionId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      planId,
      ordinal,
      kind,
      variant,
      title,
      instruction,
      summary,
      paramsJson,
      status,
      sessionId,
      startedAt,
      endedAt,
      note);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TestStep &&
          other.id == this.id &&
          other.planId == this.planId &&
          other.ordinal == this.ordinal &&
          other.kind == this.kind &&
          other.variant == this.variant &&
          other.title == this.title &&
          other.instruction == this.instruction &&
          other.summary == this.summary &&
          other.paramsJson == this.paramsJson &&
          other.status == this.status &&
          other.sessionId == this.sessionId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.note == this.note);
}

class TestStepsCompanion extends UpdateCompanion<TestStep> {
  final Value<int> id;
  final Value<int> planId;
  final Value<int> ordinal;
  final Value<String> kind;
  final Value<int?> variant;
  final Value<String> title;
  final Value<String> instruction;
  final Value<String> summary;
  final Value<String> paramsJson;
  final Value<String> status;
  final Value<int?> sessionId;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> endedAt;
  final Value<String> note;
  const TestStepsCompanion({
    this.id = const Value.absent(),
    this.planId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.kind = const Value.absent(),
    this.variant = const Value.absent(),
    this.title = const Value.absent(),
    this.instruction = const Value.absent(),
    this.summary = const Value.absent(),
    this.paramsJson = const Value.absent(),
    this.status = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.note = const Value.absent(),
  });
  TestStepsCompanion.insert({
    this.id = const Value.absent(),
    required int planId,
    required int ordinal,
    required String kind,
    this.variant = const Value.absent(),
    required String title,
    required String instruction,
    this.summary = const Value.absent(),
    this.paramsJson = const Value.absent(),
    this.status = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.note = const Value.absent(),
  })  : planId = Value(planId),
        ordinal = Value(ordinal),
        kind = Value(kind),
        title = Value(title),
        instruction = Value(instruction);
  static Insertable<TestStep> custom({
    Expression<int>? id,
    Expression<int>? planId,
    Expression<int>? ordinal,
    Expression<String>? kind,
    Expression<int>? variant,
    Expression<String>? title,
    Expression<String>? instruction,
    Expression<String>? summary,
    Expression<String>? paramsJson,
    Expression<String>? status,
    Expression<int>? sessionId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<String>? note,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (planId != null) 'plan_id': planId,
      if (ordinal != null) 'ordinal': ordinal,
      if (kind != null) 'kind': kind,
      if (variant != null) 'variant': variant,
      if (title != null) 'title': title,
      if (instruction != null) 'instruction': instruction,
      if (summary != null) 'summary': summary,
      if (paramsJson != null) 'params_json': paramsJson,
      if (status != null) 'status': status,
      if (sessionId != null) 'session_id': sessionId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (note != null) 'note': note,
    });
  }

  TestStepsCompanion copyWith(
      {Value<int>? id,
      Value<int>? planId,
      Value<int>? ordinal,
      Value<String>? kind,
      Value<int?>? variant,
      Value<String>? title,
      Value<String>? instruction,
      Value<String>? summary,
      Value<String>? paramsJson,
      Value<String>? status,
      Value<int?>? sessionId,
      Value<DateTime?>? startedAt,
      Value<DateTime?>? endedAt,
      Value<String>? note}) {
    return TestStepsCompanion(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      ordinal: ordinal ?? this.ordinal,
      kind: kind ?? this.kind,
      variant: variant ?? this.variant,
      title: title ?? this.title,
      instruction: instruction ?? this.instruction,
      summary: summary ?? this.summary,
      paramsJson: paramsJson ?? this.paramsJson,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      note: note ?? this.note,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<int>(planId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (variant.present) {
      map['variant'] = Variable<int>(variant.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (instruction.present) {
      map['instruction'] = Variable<String>(instruction.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (paramsJson.present) {
      map['params_json'] = Variable<String>(paramsJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TestStepsCompanion(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('ordinal: $ordinal, ')
          ..write('kind: $kind, ')
          ..write('variant: $variant, ')
          ..write('title: $title, ')
          ..write('instruction: $instruction, ')
          ..write('summary: $summary, ')
          ..write('paramsJson: $paramsJson, ')
          ..write('status: $status, ')
          ..write('sessionId: $sessionId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $NodesTable nodes = $NodesTable(this);
  late final $CoverageMapsTable coverageMaps = $CoverageMapsTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $PacketEventsTable packetEvents = $PacketEventsTable(this);
  late final $PingCorrelationsTable pingCorrelations =
      $PingCorrelationsTable(this);
  late final $RigProfilesTable rigProfiles = $RigProfilesTable(this);
  late final $TestPlansTable testPlans = $TestPlansTable(this);
  late final $TestStepsTable testSteps = $TestStepsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        nodes,
        coverageMaps,
        sessions,
        packetEvents,
        pingCorrelations,
        rigProfiles,
        testPlans,
        testSteps
      ];
}

typedef $$NodesTableCreateCompanionBuilder = NodesCompanion Function({
  Value<int> id,
  required int nodeId,
  Value<String> longName,
  Value<String> shortName,
  Value<String?> userLabel,
  Value<String> hwModel,
  required DateTime firstSeenAt,
  required DateTime lastHeardAt,
  Value<double?> lastLat,
  Value<double?> lastLon,
});
typedef $$NodesTableUpdateCompanionBuilder = NodesCompanion Function({
  Value<int> id,
  Value<int> nodeId,
  Value<String> longName,
  Value<String> shortName,
  Value<String?> userLabel,
  Value<String> hwModel,
  Value<DateTime> firstSeenAt,
  Value<DateTime> lastHeardAt,
  Value<double?> lastLat,
  Value<double?> lastLon,
});

final class $$NodesTableReferences
    extends BaseReferences<_$AppDatabase, $NodesTable, Node> {
  $$NodesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CoverageMapsTable, List<CoverageMap>>
      _coverageMapsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.coverageMaps,
          aliasName:
              $_aliasNameGenerator(db.nodes.id, db.coverageMaps.baseNodeId));

  $$CoverageMapsTableProcessedTableManager get coverageMapsRefs {
    final manager = $$CoverageMapsTableTableManager($_db, $_db.coverageMaps)
        .filter((f) => f.baseNodeId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_coverageMapsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$PacketEventsTable, List<PacketEvent>>
      _packetEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.packetEvents,
          aliasName:
              $_aliasNameGenerator(db.nodes.id, db.packetEvents.sourceNodeId));

  $$PacketEventsTableProcessedTableManager get packetEventsRefs {
    final manager = $$PacketEventsTableTableManager($_db, $_db.packetEvents)
        .filter((f) => f.sourceNodeId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_packetEventsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$NodesTableFilterComposer extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get nodeId => $composableBuilder(
      column: $table.nodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get longName => $composableBuilder(
      column: $table.longName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get shortName => $composableBuilder(
      column: $table.shortName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userLabel => $composableBuilder(
      column: $table.userLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hwModel => $composableBuilder(
      column: $table.hwModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get firstSeenAt => $composableBuilder(
      column: $table.firstSeenAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastHeardAt => $composableBuilder(
      column: $table.lastHeardAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lastLat => $composableBuilder(
      column: $table.lastLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lastLon => $composableBuilder(
      column: $table.lastLon, builder: (column) => ColumnFilters(column));

  Expression<bool> coverageMapsRefs(
      Expression<bool> Function($$CoverageMapsTableFilterComposer f) f) {
    final $$CoverageMapsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.baseNodeId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableFilterComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> packetEventsRefs(
      Expression<bool> Function($$PacketEventsTableFilterComposer f) f) {
    final $$PacketEventsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.sourceNodeId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableFilterComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$NodesTableOrderingComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get nodeId => $composableBuilder(
      column: $table.nodeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get longName => $composableBuilder(
      column: $table.longName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get shortName => $composableBuilder(
      column: $table.shortName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userLabel => $composableBuilder(
      column: $table.userLabel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hwModel => $composableBuilder(
      column: $table.hwModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get firstSeenAt => $composableBuilder(
      column: $table.firstSeenAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastHeardAt => $composableBuilder(
      column: $table.lastHeardAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lastLat => $composableBuilder(
      column: $table.lastLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lastLon => $composableBuilder(
      column: $table.lastLon, builder: (column) => ColumnOrderings(column));
}

class $$NodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get nodeId =>
      $composableBuilder(column: $table.nodeId, builder: (column) => column);

  GeneratedColumn<String> get longName =>
      $composableBuilder(column: $table.longName, builder: (column) => column);

  GeneratedColumn<String> get shortName =>
      $composableBuilder(column: $table.shortName, builder: (column) => column);

  GeneratedColumn<String> get userLabel =>
      $composableBuilder(column: $table.userLabel, builder: (column) => column);

  GeneratedColumn<String> get hwModel =>
      $composableBuilder(column: $table.hwModel, builder: (column) => column);

  GeneratedColumn<DateTime> get firstSeenAt => $composableBuilder(
      column: $table.firstSeenAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastHeardAt => $composableBuilder(
      column: $table.lastHeardAt, builder: (column) => column);

  GeneratedColumn<double> get lastLat =>
      $composableBuilder(column: $table.lastLat, builder: (column) => column);

  GeneratedColumn<double> get lastLon =>
      $composableBuilder(column: $table.lastLon, builder: (column) => column);

  Expression<T> coverageMapsRefs<T extends Object>(
      Expression<T> Function($$CoverageMapsTableAnnotationComposer a) f) {
    final $$CoverageMapsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.baseNodeId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableAnnotationComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> packetEventsRefs<T extends Object>(
      Expression<T> Function($$PacketEventsTableAnnotationComposer a) f) {
    final $$PacketEventsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.sourceNodeId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableAnnotationComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$NodesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $NodesTable,
    Node,
    $$NodesTableFilterComposer,
    $$NodesTableOrderingComposer,
    $$NodesTableAnnotationComposer,
    $$NodesTableCreateCompanionBuilder,
    $$NodesTableUpdateCompanionBuilder,
    (Node, $$NodesTableReferences),
    Node,
    PrefetchHooks Function({bool coverageMapsRefs, bool packetEventsRefs})> {
  $$NodesTableTableManager(_$AppDatabase db, $NodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> nodeId = const Value.absent(),
            Value<String> longName = const Value.absent(),
            Value<String> shortName = const Value.absent(),
            Value<String?> userLabel = const Value.absent(),
            Value<String> hwModel = const Value.absent(),
            Value<DateTime> firstSeenAt = const Value.absent(),
            Value<DateTime> lastHeardAt = const Value.absent(),
            Value<double?> lastLat = const Value.absent(),
            Value<double?> lastLon = const Value.absent(),
          }) =>
              NodesCompanion(
            id: id,
            nodeId: nodeId,
            longName: longName,
            shortName: shortName,
            userLabel: userLabel,
            hwModel: hwModel,
            firstSeenAt: firstSeenAt,
            lastHeardAt: lastHeardAt,
            lastLat: lastLat,
            lastLon: lastLon,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int nodeId,
            Value<String> longName = const Value.absent(),
            Value<String> shortName = const Value.absent(),
            Value<String?> userLabel = const Value.absent(),
            Value<String> hwModel = const Value.absent(),
            required DateTime firstSeenAt,
            required DateTime lastHeardAt,
            Value<double?> lastLat = const Value.absent(),
            Value<double?> lastLon = const Value.absent(),
          }) =>
              NodesCompanion.insert(
            id: id,
            nodeId: nodeId,
            longName: longName,
            shortName: shortName,
            userLabel: userLabel,
            hwModel: hwModel,
            firstSeenAt: firstSeenAt,
            lastHeardAt: lastHeardAt,
            lastLat: lastLat,
            lastLon: lastLon,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$NodesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {coverageMapsRefs = false, packetEventsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (coverageMapsRefs) db.coverageMaps,
                if (packetEventsRefs) db.packetEvents
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (coverageMapsRefs)
                    await $_getPrefetchedData<Node, $NodesTable, CoverageMap>(
                        currentTable: table,
                        referencedTable:
                            $$NodesTableReferences._coverageMapsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$NodesTableReferences(db, table, p0)
                                .coverageMapsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.baseNodeId == item.id),
                        typedResults: items),
                  if (packetEventsRefs)
                    await $_getPrefetchedData<Node, $NodesTable, PacketEvent>(
                        currentTable: table,
                        referencedTable:
                            $$NodesTableReferences._packetEventsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$NodesTableReferences(db, table, p0)
                                .packetEventsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sourceNodeId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$NodesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $NodesTable,
    Node,
    $$NodesTableFilterComposer,
    $$NodesTableOrderingComposer,
    $$NodesTableAnnotationComposer,
    $$NodesTableCreateCompanionBuilder,
    $$NodesTableUpdateCompanionBuilder,
    (Node, $$NodesTableReferences),
    Node,
    PrefetchHooks Function({bool coverageMapsRefs, bool packetEventsRefs})>;
typedef $$CoverageMapsTableCreateCompanionBuilder = CoverageMapsCompanion
    Function({
  Value<int> id,
  required String name,
  Value<int?> baseNodeId,
  Value<double?> baseLat,
  Value<double?> baseLon,
  required DateTime createdAt,
  Value<String> description,
  Value<String> colorMetric,
  Value<String> signalDirection,
});
typedef $$CoverageMapsTableUpdateCompanionBuilder = CoverageMapsCompanion
    Function({
  Value<int> id,
  Value<String> name,
  Value<int?> baseNodeId,
  Value<double?> baseLat,
  Value<double?> baseLon,
  Value<DateTime> createdAt,
  Value<String> description,
  Value<String> colorMetric,
  Value<String> signalDirection,
});

final class $$CoverageMapsTableReferences
    extends BaseReferences<_$AppDatabase, $CoverageMapsTable, CoverageMap> {
  $$CoverageMapsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NodesTable _baseNodeIdTable(_$AppDatabase db) => db.nodes.createAlias(
      $_aliasNameGenerator(db.coverageMaps.baseNodeId, db.nodes.id));

  $$NodesTableProcessedTableManager? get baseNodeId {
    final $_column = $_itemColumn<int>('base_node_id');
    if ($_column == null) return null;
    final manager = $$NodesTableTableManager($_db, $_db.nodes)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_baseNodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$SessionsTable, List<Session>> _sessionsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.sessions,
          aliasName: $_aliasNameGenerator(
              db.coverageMaps.id, db.sessions.coverageMapId));

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager($_db, $_db.sessions)
        .filter((f) => f.coverageMapId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$TestPlansTable, List<TestPlan>>
      _testPlansRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.testPlans,
              aliasName: $_aliasNameGenerator(
                  db.coverageMaps.id, db.testPlans.coverageMapId));

  $$TestPlansTableProcessedTableManager get testPlansRefs {
    final manager = $$TestPlansTableTableManager($_db, $_db.testPlans)
        .filter((f) => f.coverageMapId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_testPlansRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$CoverageMapsTableFilterComposer
    extends Composer<_$AppDatabase, $CoverageMapsTable> {
  $$CoverageMapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get baseLat => $composableBuilder(
      column: $table.baseLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get baseLon => $composableBuilder(
      column: $table.baseLon, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get colorMetric => $composableBuilder(
      column: $table.colorMetric, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get signalDirection => $composableBuilder(
      column: $table.signalDirection,
      builder: (column) => ColumnFilters(column));

  $$NodesTableFilterComposer get baseNodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.baseNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableFilterComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> sessionsRefs(
      Expression<bool> Function($$SessionsTableFilterComposer f) f) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.coverageMapId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableFilterComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> testPlansRefs(
      Expression<bool> Function($$TestPlansTableFilterComposer f) f) {
    final $$TestPlansTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.testPlans,
        getReferencedColumn: (t) => t.coverageMapId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestPlansTableFilterComposer(
              $db: $db,
              $table: $db.testPlans,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$CoverageMapsTableOrderingComposer
    extends Composer<_$AppDatabase, $CoverageMapsTable> {
  $$CoverageMapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get baseLat => $composableBuilder(
      column: $table.baseLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get baseLon => $composableBuilder(
      column: $table.baseLon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get colorMetric => $composableBuilder(
      column: $table.colorMetric, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get signalDirection => $composableBuilder(
      column: $table.signalDirection,
      builder: (column) => ColumnOrderings(column));

  $$NodesTableOrderingComposer get baseNodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.baseNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableOrderingComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$CoverageMapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoverageMapsTable> {
  $$CoverageMapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get baseLat =>
      $composableBuilder(column: $table.baseLat, builder: (column) => column);

  GeneratedColumn<double> get baseLon =>
      $composableBuilder(column: $table.baseLon, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get colorMetric => $composableBuilder(
      column: $table.colorMetric, builder: (column) => column);

  GeneratedColumn<String> get signalDirection => $composableBuilder(
      column: $table.signalDirection, builder: (column) => column);

  $$NodesTableAnnotationComposer get baseNodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.baseNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableAnnotationComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> sessionsRefs<T extends Object>(
      Expression<T> Function($$SessionsTableAnnotationComposer a) f) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.coverageMapId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> testPlansRefs<T extends Object>(
      Expression<T> Function($$TestPlansTableAnnotationComposer a) f) {
    final $$TestPlansTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.testPlans,
        getReferencedColumn: (t) => t.coverageMapId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestPlansTableAnnotationComposer(
              $db: $db,
              $table: $db.testPlans,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$CoverageMapsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CoverageMapsTable,
    CoverageMap,
    $$CoverageMapsTableFilterComposer,
    $$CoverageMapsTableOrderingComposer,
    $$CoverageMapsTableAnnotationComposer,
    $$CoverageMapsTableCreateCompanionBuilder,
    $$CoverageMapsTableUpdateCompanionBuilder,
    (CoverageMap, $$CoverageMapsTableReferences),
    CoverageMap,
    PrefetchHooks Function(
        {bool baseNodeId, bool sessionsRefs, bool testPlansRefs})> {
  $$CoverageMapsTableTableManager(_$AppDatabase db, $CoverageMapsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoverageMapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoverageMapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoverageMapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int?> baseNodeId = const Value.absent(),
            Value<double?> baseLat = const Value.absent(),
            Value<double?> baseLon = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> colorMetric = const Value.absent(),
            Value<String> signalDirection = const Value.absent(),
          }) =>
              CoverageMapsCompanion(
            id: id,
            name: name,
            baseNodeId: baseNodeId,
            baseLat: baseLat,
            baseLon: baseLon,
            createdAt: createdAt,
            description: description,
            colorMetric: colorMetric,
            signalDirection: signalDirection,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<int?> baseNodeId = const Value.absent(),
            Value<double?> baseLat = const Value.absent(),
            Value<double?> baseLon = const Value.absent(),
            required DateTime createdAt,
            Value<String> description = const Value.absent(),
            Value<String> colorMetric = const Value.absent(),
            Value<String> signalDirection = const Value.absent(),
          }) =>
              CoverageMapsCompanion.insert(
            id: id,
            name: name,
            baseNodeId: baseNodeId,
            baseLat: baseLat,
            baseLon: baseLon,
            createdAt: createdAt,
            description: description,
            colorMetric: colorMetric,
            signalDirection: signalDirection,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$CoverageMapsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {baseNodeId = false,
              sessionsRefs = false,
              testPlansRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (sessionsRefs) db.sessions,
                if (testPlansRefs) db.testPlans
              ],
              addJoins: <
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
                      dynamic>>(state) {
                if (baseNodeId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.baseNodeId,
                    referencedTable:
                        $$CoverageMapsTableReferences._baseNodeIdTable(db),
                    referencedColumn:
                        $$CoverageMapsTableReferences._baseNodeIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (sessionsRefs)
                    await $_getPrefetchedData<CoverageMap, $CoverageMapsTable,
                            Session>(
                        currentTable: table,
                        referencedTable: $$CoverageMapsTableReferences
                            ._sessionsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$CoverageMapsTableReferences(db, table, p0)
                                .sessionsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.coverageMapId == item.id),
                        typedResults: items),
                  if (testPlansRefs)
                    await $_getPrefetchedData<CoverageMap, $CoverageMapsTable,
                            TestPlan>(
                        currentTable: table,
                        referencedTable: $$CoverageMapsTableReferences
                            ._testPlansRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$CoverageMapsTableReferences(db, table, p0)
                                .testPlansRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.coverageMapId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$CoverageMapsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CoverageMapsTable,
    CoverageMap,
    $$CoverageMapsTableFilterComposer,
    $$CoverageMapsTableOrderingComposer,
    $$CoverageMapsTableAnnotationComposer,
    $$CoverageMapsTableCreateCompanionBuilder,
    $$CoverageMapsTableUpdateCompanionBuilder,
    (CoverageMap, $$CoverageMapsTableReferences),
    CoverageMap,
    PrefetchHooks Function(
        {bool baseNodeId, bool sessionsRefs, bool testPlansRefs})>;
typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  Value<int> id,
  required int coverageMapId,
  Value<String> name,
  required DateTime startedAt,
  Value<DateTime?> endedAt,
  Value<bool> isActive,
  Value<int?> remoteNodeId,
  Value<int?> baseNodeId,
  Value<String> hwAntenna,
  Value<String> hwNodeModel,
  Value<String> hwNotes,
  Value<String> loraPreset,
  Value<String> protocol,
  Value<int> pingIntervalSec,
  Value<double> packetAirtimeMs,
  Value<int?> mobileRigId,
  Value<int?> baseRigId,
  Value<String?> mobileRigJson,
  Value<String?> baseRigJson,
  Value<double?> radioAirUtilTx,
  Value<double?> radioChannelUtil,
  Value<String> beaconKind,
  Value<int> beaconIntervalSec,
  Value<String?> region,
  Value<int?> frequencySlot,
  Value<int?> txPowerDbm,
  Value<int?> hopLimit,
  Value<double?> frequencyMhz,
  Value<int?> testStepId,
  Value<bool> rangeTestActive,
  Value<int> packetCount,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<int> id,
  Value<int> coverageMapId,
  Value<String> name,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<bool> isActive,
  Value<int?> remoteNodeId,
  Value<int?> baseNodeId,
  Value<String> hwAntenna,
  Value<String> hwNodeModel,
  Value<String> hwNotes,
  Value<String> loraPreset,
  Value<String> protocol,
  Value<int> pingIntervalSec,
  Value<double> packetAirtimeMs,
  Value<int?> mobileRigId,
  Value<int?> baseRigId,
  Value<String?> mobileRigJson,
  Value<String?> baseRigJson,
  Value<double?> radioAirUtilTx,
  Value<double?> radioChannelUtil,
  Value<String> beaconKind,
  Value<int> beaconIntervalSec,
  Value<String?> region,
  Value<int?> frequencySlot,
  Value<int?> txPowerDbm,
  Value<int?> hopLimit,
  Value<double?> frequencyMhz,
  Value<int?> testStepId,
  Value<bool> rangeTestActive,
  Value<int> packetCount,
});

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CoverageMapsTable _coverageMapIdTable(_$AppDatabase db) =>
      db.coverageMaps.createAlias(
          $_aliasNameGenerator(db.sessions.coverageMapId, db.coverageMaps.id));

  $$CoverageMapsTableProcessedTableManager get coverageMapId {
    final $_column = $_itemColumn<int>('coverage_map_id')!;

    final manager = $$CoverageMapsTableTableManager($_db, $_db.coverageMaps)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_coverageMapIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $NodesTable _remoteNodeIdTable(_$AppDatabase db) => db.nodes
      .createAlias($_aliasNameGenerator(db.sessions.remoteNodeId, db.nodes.id));

  $$NodesTableProcessedTableManager? get remoteNodeId {
    final $_column = $_itemColumn<int>('remote_node_id');
    if ($_column == null) return null;
    final manager = $$NodesTableTableManager($_db, $_db.nodes)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_remoteNodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $NodesTable _baseNodeIdTable(_$AppDatabase db) => db.nodes
      .createAlias($_aliasNameGenerator(db.sessions.baseNodeId, db.nodes.id));

  $$NodesTableProcessedTableManager? get baseNodeId {
    final $_column = $_itemColumn<int>('base_node_id');
    if ($_column == null) return null;
    final manager = $$NodesTableTableManager($_db, $_db.nodes)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_baseNodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$PacketEventsTable, List<PacketEvent>>
      _packetEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.packetEvents,
          aliasName:
              $_aliasNameGenerator(db.sessions.id, db.packetEvents.sessionId));

  $$PacketEventsTableProcessedTableManager get packetEventsRefs {
    final manager = $$PacketEventsTableTableManager($_db, $_db.packetEvents)
        .filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_packetEventsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$TestStepsTable, List<TestStep>>
      _testStepsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.testSteps,
              aliasName:
                  $_aliasNameGenerator(db.sessions.id, db.testSteps.sessionId));

  $$TestStepsTableProcessedTableManager get testStepsRefs {
    final manager = $$TestStepsTableTableManager($_db, $_db.testSteps)
        .filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_testStepsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hwAntenna => $composableBuilder(
      column: $table.hwAntenna, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hwNodeModel => $composableBuilder(
      column: $table.hwNodeModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hwNotes => $composableBuilder(
      column: $table.hwNotes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get loraPreset => $composableBuilder(
      column: $table.loraPreset, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get protocol => $composableBuilder(
      column: $table.protocol, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pingIntervalSec => $composableBuilder(
      column: $table.pingIntervalSec,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get packetAirtimeMs => $composableBuilder(
      column: $table.packetAirtimeMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mobileRigId => $composableBuilder(
      column: $table.mobileRigId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get baseRigId => $composableBuilder(
      column: $table.baseRigId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mobileRigJson => $composableBuilder(
      column: $table.mobileRigJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseRigJson => $composableBuilder(
      column: $table.baseRigJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get radioAirUtilTx => $composableBuilder(
      column: $table.radioAirUtilTx,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get radioChannelUtil => $composableBuilder(
      column: $table.radioChannelUtil,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get beaconKind => $composableBuilder(
      column: $table.beaconKind, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get beaconIntervalSec => $composableBuilder(
      column: $table.beaconIntervalSec,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get region => $composableBuilder(
      column: $table.region, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get frequencySlot => $composableBuilder(
      column: $table.frequencySlot, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get txPowerDbm => $composableBuilder(
      column: $table.txPowerDbm, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get hopLimit => $composableBuilder(
      column: $table.hopLimit, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get frequencyMhz => $composableBuilder(
      column: $table.frequencyMhz, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get testStepId => $composableBuilder(
      column: $table.testStepId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get rangeTestActive => $composableBuilder(
      column: $table.rangeTestActive,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get packetCount => $composableBuilder(
      column: $table.packetCount, builder: (column) => ColumnFilters(column));

  $$CoverageMapsTableFilterComposer get coverageMapId {
    final $$CoverageMapsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.coverageMapId,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableFilterComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableFilterComposer get remoteNodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.remoteNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableFilterComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableFilterComposer get baseNodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.baseNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableFilterComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> packetEventsRefs(
      Expression<bool> Function($$PacketEventsTableFilterComposer f) f) {
    final $$PacketEventsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableFilterComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> testStepsRefs(
      Expression<bool> Function($$TestStepsTableFilterComposer f) f) {
    final $$TestStepsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.testSteps,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestStepsTableFilterComposer(
              $db: $db,
              $table: $db.testSteps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hwAntenna => $composableBuilder(
      column: $table.hwAntenna, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hwNodeModel => $composableBuilder(
      column: $table.hwNodeModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hwNotes => $composableBuilder(
      column: $table.hwNotes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get loraPreset => $composableBuilder(
      column: $table.loraPreset, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get protocol => $composableBuilder(
      column: $table.protocol, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pingIntervalSec => $composableBuilder(
      column: $table.pingIntervalSec,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get packetAirtimeMs => $composableBuilder(
      column: $table.packetAirtimeMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mobileRigId => $composableBuilder(
      column: $table.mobileRigId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get baseRigId => $composableBuilder(
      column: $table.baseRigId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mobileRigJson => $composableBuilder(
      column: $table.mobileRigJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseRigJson => $composableBuilder(
      column: $table.baseRigJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get radioAirUtilTx => $composableBuilder(
      column: $table.radioAirUtilTx,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get radioChannelUtil => $composableBuilder(
      column: $table.radioChannelUtil,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get beaconKind => $composableBuilder(
      column: $table.beaconKind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get beaconIntervalSec => $composableBuilder(
      column: $table.beaconIntervalSec,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get region => $composableBuilder(
      column: $table.region, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get frequencySlot => $composableBuilder(
      column: $table.frequencySlot,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get txPowerDbm => $composableBuilder(
      column: $table.txPowerDbm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get hopLimit => $composableBuilder(
      column: $table.hopLimit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get frequencyMhz => $composableBuilder(
      column: $table.frequencyMhz,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get testStepId => $composableBuilder(
      column: $table.testStepId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get rangeTestActive => $composableBuilder(
      column: $table.rangeTestActive,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get packetCount => $composableBuilder(
      column: $table.packetCount, builder: (column) => ColumnOrderings(column));

  $$CoverageMapsTableOrderingComposer get coverageMapId {
    final $$CoverageMapsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.coverageMapId,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableOrderingComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableOrderingComposer get remoteNodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.remoteNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableOrderingComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableOrderingComposer get baseNodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.baseNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableOrderingComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get hwAntenna =>
      $composableBuilder(column: $table.hwAntenna, builder: (column) => column);

  GeneratedColumn<String> get hwNodeModel => $composableBuilder(
      column: $table.hwNodeModel, builder: (column) => column);

  GeneratedColumn<String> get hwNotes =>
      $composableBuilder(column: $table.hwNotes, builder: (column) => column);

  GeneratedColumn<String> get loraPreset => $composableBuilder(
      column: $table.loraPreset, builder: (column) => column);

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<int> get pingIntervalSec => $composableBuilder(
      column: $table.pingIntervalSec, builder: (column) => column);

  GeneratedColumn<double> get packetAirtimeMs => $composableBuilder(
      column: $table.packetAirtimeMs, builder: (column) => column);

  GeneratedColumn<int> get mobileRigId => $composableBuilder(
      column: $table.mobileRigId, builder: (column) => column);

  GeneratedColumn<int> get baseRigId =>
      $composableBuilder(column: $table.baseRigId, builder: (column) => column);

  GeneratedColumn<String> get mobileRigJson => $composableBuilder(
      column: $table.mobileRigJson, builder: (column) => column);

  GeneratedColumn<String> get baseRigJson => $composableBuilder(
      column: $table.baseRigJson, builder: (column) => column);

  GeneratedColumn<double> get radioAirUtilTx => $composableBuilder(
      column: $table.radioAirUtilTx, builder: (column) => column);

  GeneratedColumn<double> get radioChannelUtil => $composableBuilder(
      column: $table.radioChannelUtil, builder: (column) => column);

  GeneratedColumn<String> get beaconKind => $composableBuilder(
      column: $table.beaconKind, builder: (column) => column);

  GeneratedColumn<int> get beaconIntervalSec => $composableBuilder(
      column: $table.beaconIntervalSec, builder: (column) => column);

  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<int> get frequencySlot => $composableBuilder(
      column: $table.frequencySlot, builder: (column) => column);

  GeneratedColumn<int> get txPowerDbm => $composableBuilder(
      column: $table.txPowerDbm, builder: (column) => column);

  GeneratedColumn<int> get hopLimit =>
      $composableBuilder(column: $table.hopLimit, builder: (column) => column);

  GeneratedColumn<double> get frequencyMhz => $composableBuilder(
      column: $table.frequencyMhz, builder: (column) => column);

  GeneratedColumn<int> get testStepId => $composableBuilder(
      column: $table.testStepId, builder: (column) => column);

  GeneratedColumn<bool> get rangeTestActive => $composableBuilder(
      column: $table.rangeTestActive, builder: (column) => column);

  GeneratedColumn<int> get packetCount => $composableBuilder(
      column: $table.packetCount, builder: (column) => column);

  $$CoverageMapsTableAnnotationComposer get coverageMapId {
    final $$CoverageMapsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.coverageMapId,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableAnnotationComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableAnnotationComposer get remoteNodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.remoteNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableAnnotationComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableAnnotationComposer get baseNodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.baseNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableAnnotationComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> packetEventsRefs<T extends Object>(
      Expression<T> Function($$PacketEventsTableAnnotationComposer a) f) {
    final $$PacketEventsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableAnnotationComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> testStepsRefs<T extends Object>(
      Expression<T> Function($$TestStepsTableAnnotationComposer a) f) {
    final $$TestStepsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.testSteps,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestStepsTableAnnotationComposer(
              $db: $db,
              $table: $db.testSteps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SessionsTable,
    Session,
    $$SessionsTableFilterComposer,
    $$SessionsTableOrderingComposer,
    $$SessionsTableAnnotationComposer,
    $$SessionsTableCreateCompanionBuilder,
    $$SessionsTableUpdateCompanionBuilder,
    (Session, $$SessionsTableReferences),
    Session,
    PrefetchHooks Function(
        {bool coverageMapId,
        bool remoteNodeId,
        bool baseNodeId,
        bool packetEventsRefs,
        bool testStepsRefs})> {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> coverageMapId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int?> remoteNodeId = const Value.absent(),
            Value<int?> baseNodeId = const Value.absent(),
            Value<String> hwAntenna = const Value.absent(),
            Value<String> hwNodeModel = const Value.absent(),
            Value<String> hwNotes = const Value.absent(),
            Value<String> loraPreset = const Value.absent(),
            Value<String> protocol = const Value.absent(),
            Value<int> pingIntervalSec = const Value.absent(),
            Value<double> packetAirtimeMs = const Value.absent(),
            Value<int?> mobileRigId = const Value.absent(),
            Value<int?> baseRigId = const Value.absent(),
            Value<String?> mobileRigJson = const Value.absent(),
            Value<String?> baseRigJson = const Value.absent(),
            Value<double?> radioAirUtilTx = const Value.absent(),
            Value<double?> radioChannelUtil = const Value.absent(),
            Value<String> beaconKind = const Value.absent(),
            Value<int> beaconIntervalSec = const Value.absent(),
            Value<String?> region = const Value.absent(),
            Value<int?> frequencySlot = const Value.absent(),
            Value<int?> txPowerDbm = const Value.absent(),
            Value<int?> hopLimit = const Value.absent(),
            Value<double?> frequencyMhz = const Value.absent(),
            Value<int?> testStepId = const Value.absent(),
            Value<bool> rangeTestActive = const Value.absent(),
            Value<int> packetCount = const Value.absent(),
          }) =>
              SessionsCompanion(
            id: id,
            coverageMapId: coverageMapId,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            isActive: isActive,
            remoteNodeId: remoteNodeId,
            baseNodeId: baseNodeId,
            hwAntenna: hwAntenna,
            hwNodeModel: hwNodeModel,
            hwNotes: hwNotes,
            loraPreset: loraPreset,
            protocol: protocol,
            pingIntervalSec: pingIntervalSec,
            packetAirtimeMs: packetAirtimeMs,
            mobileRigId: mobileRigId,
            baseRigId: baseRigId,
            mobileRigJson: mobileRigJson,
            baseRigJson: baseRigJson,
            radioAirUtilTx: radioAirUtilTx,
            radioChannelUtil: radioChannelUtil,
            beaconKind: beaconKind,
            beaconIntervalSec: beaconIntervalSec,
            region: region,
            frequencySlot: frequencySlot,
            txPowerDbm: txPowerDbm,
            hopLimit: hopLimit,
            frequencyMhz: frequencyMhz,
            testStepId: testStepId,
            rangeTestActive: rangeTestActive,
            packetCount: packetCount,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int coverageMapId,
            Value<String> name = const Value.absent(),
            required DateTime startedAt,
            Value<DateTime?> endedAt = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int?> remoteNodeId = const Value.absent(),
            Value<int?> baseNodeId = const Value.absent(),
            Value<String> hwAntenna = const Value.absent(),
            Value<String> hwNodeModel = const Value.absent(),
            Value<String> hwNotes = const Value.absent(),
            Value<String> loraPreset = const Value.absent(),
            Value<String> protocol = const Value.absent(),
            Value<int> pingIntervalSec = const Value.absent(),
            Value<double> packetAirtimeMs = const Value.absent(),
            Value<int?> mobileRigId = const Value.absent(),
            Value<int?> baseRigId = const Value.absent(),
            Value<String?> mobileRigJson = const Value.absent(),
            Value<String?> baseRigJson = const Value.absent(),
            Value<double?> radioAirUtilTx = const Value.absent(),
            Value<double?> radioChannelUtil = const Value.absent(),
            Value<String> beaconKind = const Value.absent(),
            Value<int> beaconIntervalSec = const Value.absent(),
            Value<String?> region = const Value.absent(),
            Value<int?> frequencySlot = const Value.absent(),
            Value<int?> txPowerDbm = const Value.absent(),
            Value<int?> hopLimit = const Value.absent(),
            Value<double?> frequencyMhz = const Value.absent(),
            Value<int?> testStepId = const Value.absent(),
            Value<bool> rangeTestActive = const Value.absent(),
            Value<int> packetCount = const Value.absent(),
          }) =>
              SessionsCompanion.insert(
            id: id,
            coverageMapId: coverageMapId,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            isActive: isActive,
            remoteNodeId: remoteNodeId,
            baseNodeId: baseNodeId,
            hwAntenna: hwAntenna,
            hwNodeModel: hwNodeModel,
            hwNotes: hwNotes,
            loraPreset: loraPreset,
            protocol: protocol,
            pingIntervalSec: pingIntervalSec,
            packetAirtimeMs: packetAirtimeMs,
            mobileRigId: mobileRigId,
            baseRigId: baseRigId,
            mobileRigJson: mobileRigJson,
            baseRigJson: baseRigJson,
            radioAirUtilTx: radioAirUtilTx,
            radioChannelUtil: radioChannelUtil,
            beaconKind: beaconKind,
            beaconIntervalSec: beaconIntervalSec,
            region: region,
            frequencySlot: frequencySlot,
            txPowerDbm: txPowerDbm,
            hopLimit: hopLimit,
            frequencyMhz: frequencyMhz,
            testStepId: testStepId,
            rangeTestActive: rangeTestActive,
            packetCount: packetCount,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SessionsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {coverageMapId = false,
              remoteNodeId = false,
              baseNodeId = false,
              packetEventsRefs = false,
              testStepsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (packetEventsRefs) db.packetEvents,
                if (testStepsRefs) db.testSteps
              ],
              addJoins: <
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
                      dynamic>>(state) {
                if (coverageMapId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.coverageMapId,
                    referencedTable:
                        $$SessionsTableReferences._coverageMapIdTable(db),
                    referencedColumn:
                        $$SessionsTableReferences._coverageMapIdTable(db).id,
                  ) as T;
                }
                if (remoteNodeId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.remoteNodeId,
                    referencedTable:
                        $$SessionsTableReferences._remoteNodeIdTable(db),
                    referencedColumn:
                        $$SessionsTableReferences._remoteNodeIdTable(db).id,
                  ) as T;
                }
                if (baseNodeId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.baseNodeId,
                    referencedTable:
                        $$SessionsTableReferences._baseNodeIdTable(db),
                    referencedColumn:
                        $$SessionsTableReferences._baseNodeIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (packetEventsRefs)
                    await $_getPrefetchedData<Session, $SessionsTable,
                            PacketEvent>(
                        currentTable: table,
                        referencedTable: $$SessionsTableReferences
                            ._packetEventsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SessionsTableReferences(db, table, p0)
                                .packetEventsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sessionId == item.id),
                        typedResults: items),
                  if (testStepsRefs)
                    await $_getPrefetchedData<Session, $SessionsTable,
                            TestStep>(
                        currentTable: table,
                        referencedTable:
                            $$SessionsTableReferences._testStepsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SessionsTableReferences(db, table, p0)
                                .testStepsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sessionId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SessionsTable,
    Session,
    $$SessionsTableFilterComposer,
    $$SessionsTableOrderingComposer,
    $$SessionsTableAnnotationComposer,
    $$SessionsTableCreateCompanionBuilder,
    $$SessionsTableUpdateCompanionBuilder,
    (Session, $$SessionsTableReferences),
    Session,
    PrefetchHooks Function(
        {bool coverageMapId,
        bool remoteNodeId,
        bool baseNodeId,
        bool packetEventsRefs,
        bool testStepsRefs})>;
typedef $$PacketEventsTableCreateCompanionBuilder = PacketEventsCompanion
    Function({
  Value<int> id,
  required int sessionId,
  required DateTime timestamp,
  required String direction,
  required int sourceNodeId,
  Value<double?> rxSnr,
  Value<int?> rxRssi,
  Value<int> hopCount,
  Value<double?> rxLat,
  Value<double?> rxLon,
  Value<double?> rxAlt,
  Value<double?> gpsAccuracy,
  required String packetType,
  Value<int?> meshPacketId,
  Value<int> channelIndex,
  Value<bool> viaMqtt,
  Value<int?> seq,
  Value<String> sourceKind,
  Value<double?> baseChannelUtil,
  Value<double?> uplinkSnr,
});
typedef $$PacketEventsTableUpdateCompanionBuilder = PacketEventsCompanion
    Function({
  Value<int> id,
  Value<int> sessionId,
  Value<DateTime> timestamp,
  Value<String> direction,
  Value<int> sourceNodeId,
  Value<double?> rxSnr,
  Value<int?> rxRssi,
  Value<int> hopCount,
  Value<double?> rxLat,
  Value<double?> rxLon,
  Value<double?> rxAlt,
  Value<double?> gpsAccuracy,
  Value<String> packetType,
  Value<int?> meshPacketId,
  Value<int> channelIndex,
  Value<bool> viaMqtt,
  Value<int?> seq,
  Value<String> sourceKind,
  Value<double?> baseChannelUtil,
  Value<double?> uplinkSnr,
});

final class $$PacketEventsTableReferences
    extends BaseReferences<_$AppDatabase, $PacketEventsTable, PacketEvent> {
  $$PacketEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
          $_aliasNameGenerator(db.packetEvents.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$SessionsTableTableManager($_db, $_db.sessions)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $NodesTable _sourceNodeIdTable(_$AppDatabase db) =>
      db.nodes.createAlias(
          $_aliasNameGenerator(db.packetEvents.sourceNodeId, db.nodes.id));

  $$NodesTableProcessedTableManager get sourceNodeId {
    final $_column = $_itemColumn<int>('source_node_id')!;

    final manager = $$NodesTableTableManager($_db, $_db.nodes)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceNodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$PingCorrelationsTable, List<PingCorrelation>>
      _pingCorrelationsTxTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.pingCorrelations,
              aliasName: $_aliasNameGenerator(
                  db.packetEvents.id, db.pingCorrelations.txEventId));

  $$PingCorrelationsTableProcessedTableManager get pingCorrelationsTx {
    final manager =
        $$PingCorrelationsTableTableManager($_db, $_db.pingCorrelations)
            .filter((f) => f.txEventId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_pingCorrelationsTxTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$PingCorrelationsTable, List<PingCorrelation>>
      _pingCorrelationsAckTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.pingCorrelations,
              aliasName: $_aliasNameGenerator(
                  db.packetEvents.id, db.pingCorrelations.ackEventId));

  $$PingCorrelationsTableProcessedTableManager get pingCorrelationsAck {
    final manager =
        $$PingCorrelationsTableTableManager($_db, $_db.pingCorrelations)
            .filter((f) => f.ackEventId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_pingCorrelationsAckTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$PacketEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PacketEventsTable> {
  $$PacketEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rxSnr => $composableBuilder(
      column: $table.rxSnr, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rxRssi => $composableBuilder(
      column: $table.rxRssi, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get hopCount => $composableBuilder(
      column: $table.hopCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rxLat => $composableBuilder(
      column: $table.rxLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rxLon => $composableBuilder(
      column: $table.rxLon, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rxAlt => $composableBuilder(
      column: $table.rxAlt, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get gpsAccuracy => $composableBuilder(
      column: $table.gpsAccuracy, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packetType => $composableBuilder(
      column: $table.packetType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get meshPacketId => $composableBuilder(
      column: $table.meshPacketId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get channelIndex => $composableBuilder(
      column: $table.channelIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get viaMqtt => $composableBuilder(
      column: $table.viaMqtt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get baseChannelUtil => $composableBuilder(
      column: $table.baseChannelUtil,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get uplinkSnr => $composableBuilder(
      column: $table.uplinkSnr, builder: (column) => ColumnFilters(column));

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableFilterComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableFilterComposer get sourceNodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sourceNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableFilterComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> pingCorrelationsTx(
      Expression<bool> Function($$PingCorrelationsTableFilterComposer f) f) {
    final $$PingCorrelationsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.pingCorrelations,
        getReferencedColumn: (t) => t.txEventId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PingCorrelationsTableFilterComposer(
              $db: $db,
              $table: $db.pingCorrelations,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> pingCorrelationsAck(
      Expression<bool> Function($$PingCorrelationsTableFilterComposer f) f) {
    final $$PingCorrelationsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.pingCorrelations,
        getReferencedColumn: (t) => t.ackEventId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PingCorrelationsTableFilterComposer(
              $db: $db,
              $table: $db.pingCorrelations,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$PacketEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PacketEventsTable> {
  $$PacketEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rxSnr => $composableBuilder(
      column: $table.rxSnr, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rxRssi => $composableBuilder(
      column: $table.rxRssi, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get hopCount => $composableBuilder(
      column: $table.hopCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rxLat => $composableBuilder(
      column: $table.rxLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rxLon => $composableBuilder(
      column: $table.rxLon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rxAlt => $composableBuilder(
      column: $table.rxAlt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get gpsAccuracy => $composableBuilder(
      column: $table.gpsAccuracy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packetType => $composableBuilder(
      column: $table.packetType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get meshPacketId => $composableBuilder(
      column: $table.meshPacketId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get channelIndex => $composableBuilder(
      column: $table.channelIndex,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get viaMqtt => $composableBuilder(
      column: $table.viaMqtt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get baseChannelUtil => $composableBuilder(
      column: $table.baseChannelUtil,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get uplinkSnr => $composableBuilder(
      column: $table.uplinkSnr, builder: (column) => ColumnOrderings(column));

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableOrderingComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableOrderingComposer get sourceNodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sourceNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableOrderingComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PacketEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PacketEventsTable> {
  $$PacketEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<double> get rxSnr =>
      $composableBuilder(column: $table.rxSnr, builder: (column) => column);

  GeneratedColumn<int> get rxRssi =>
      $composableBuilder(column: $table.rxRssi, builder: (column) => column);

  GeneratedColumn<int> get hopCount =>
      $composableBuilder(column: $table.hopCount, builder: (column) => column);

  GeneratedColumn<double> get rxLat =>
      $composableBuilder(column: $table.rxLat, builder: (column) => column);

  GeneratedColumn<double> get rxLon =>
      $composableBuilder(column: $table.rxLon, builder: (column) => column);

  GeneratedColumn<double> get rxAlt =>
      $composableBuilder(column: $table.rxAlt, builder: (column) => column);

  GeneratedColumn<double> get gpsAccuracy => $composableBuilder(
      column: $table.gpsAccuracy, builder: (column) => column);

  GeneratedColumn<String> get packetType => $composableBuilder(
      column: $table.packetType, builder: (column) => column);

  GeneratedColumn<int> get meshPacketId => $composableBuilder(
      column: $table.meshPacketId, builder: (column) => column);

  GeneratedColumn<int> get channelIndex => $composableBuilder(
      column: $table.channelIndex, builder: (column) => column);

  GeneratedColumn<bool> get viaMqtt =>
      $composableBuilder(column: $table.viaMqtt, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => column);

  GeneratedColumn<double> get baseChannelUtil => $composableBuilder(
      column: $table.baseChannelUtil, builder: (column) => column);

  GeneratedColumn<double> get uplinkSnr =>
      $composableBuilder(column: $table.uplinkSnr, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$NodesTableAnnotationComposer get sourceNodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sourceNodeId,
        referencedTable: $db.nodes,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$NodesTableAnnotationComposer(
              $db: $db,
              $table: $db.nodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> pingCorrelationsTx<T extends Object>(
      Expression<T> Function($$PingCorrelationsTableAnnotationComposer a) f) {
    final $$PingCorrelationsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.pingCorrelations,
        getReferencedColumn: (t) => t.txEventId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PingCorrelationsTableAnnotationComposer(
              $db: $db,
              $table: $db.pingCorrelations,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> pingCorrelationsAck<T extends Object>(
      Expression<T> Function($$PingCorrelationsTableAnnotationComposer a) f) {
    final $$PingCorrelationsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.pingCorrelations,
        getReferencedColumn: (t) => t.ackEventId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PingCorrelationsTableAnnotationComposer(
              $db: $db,
              $table: $db.pingCorrelations,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$PacketEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PacketEventsTable,
    PacketEvent,
    $$PacketEventsTableFilterComposer,
    $$PacketEventsTableOrderingComposer,
    $$PacketEventsTableAnnotationComposer,
    $$PacketEventsTableCreateCompanionBuilder,
    $$PacketEventsTableUpdateCompanionBuilder,
    (PacketEvent, $$PacketEventsTableReferences),
    PacketEvent,
    PrefetchHooks Function(
        {bool sessionId,
        bool sourceNodeId,
        bool pingCorrelationsTx,
        bool pingCorrelationsAck})> {
  $$PacketEventsTableTableManager(_$AppDatabase db, $PacketEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PacketEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PacketEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PacketEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> sessionId = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<int> sourceNodeId = const Value.absent(),
            Value<double?> rxSnr = const Value.absent(),
            Value<int?> rxRssi = const Value.absent(),
            Value<int> hopCount = const Value.absent(),
            Value<double?> rxLat = const Value.absent(),
            Value<double?> rxLon = const Value.absent(),
            Value<double?> rxAlt = const Value.absent(),
            Value<double?> gpsAccuracy = const Value.absent(),
            Value<String> packetType = const Value.absent(),
            Value<int?> meshPacketId = const Value.absent(),
            Value<int> channelIndex = const Value.absent(),
            Value<bool> viaMqtt = const Value.absent(),
            Value<int?> seq = const Value.absent(),
            Value<String> sourceKind = const Value.absent(),
            Value<double?> baseChannelUtil = const Value.absent(),
            Value<double?> uplinkSnr = const Value.absent(),
          }) =>
              PacketEventsCompanion(
            id: id,
            sessionId: sessionId,
            timestamp: timestamp,
            direction: direction,
            sourceNodeId: sourceNodeId,
            rxSnr: rxSnr,
            rxRssi: rxRssi,
            hopCount: hopCount,
            rxLat: rxLat,
            rxLon: rxLon,
            rxAlt: rxAlt,
            gpsAccuracy: gpsAccuracy,
            packetType: packetType,
            meshPacketId: meshPacketId,
            channelIndex: channelIndex,
            viaMqtt: viaMqtt,
            seq: seq,
            sourceKind: sourceKind,
            baseChannelUtil: baseChannelUtil,
            uplinkSnr: uplinkSnr,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int sessionId,
            required DateTime timestamp,
            required String direction,
            required int sourceNodeId,
            Value<double?> rxSnr = const Value.absent(),
            Value<int?> rxRssi = const Value.absent(),
            Value<int> hopCount = const Value.absent(),
            Value<double?> rxLat = const Value.absent(),
            Value<double?> rxLon = const Value.absent(),
            Value<double?> rxAlt = const Value.absent(),
            Value<double?> gpsAccuracy = const Value.absent(),
            required String packetType,
            Value<int?> meshPacketId = const Value.absent(),
            Value<int> channelIndex = const Value.absent(),
            Value<bool> viaMqtt = const Value.absent(),
            Value<int?> seq = const Value.absent(),
            Value<String> sourceKind = const Value.absent(),
            Value<double?> baseChannelUtil = const Value.absent(),
            Value<double?> uplinkSnr = const Value.absent(),
          }) =>
              PacketEventsCompanion.insert(
            id: id,
            sessionId: sessionId,
            timestamp: timestamp,
            direction: direction,
            sourceNodeId: sourceNodeId,
            rxSnr: rxSnr,
            rxRssi: rxRssi,
            hopCount: hopCount,
            rxLat: rxLat,
            rxLon: rxLon,
            rxAlt: rxAlt,
            gpsAccuracy: gpsAccuracy,
            packetType: packetType,
            meshPacketId: meshPacketId,
            channelIndex: channelIndex,
            viaMqtt: viaMqtt,
            seq: seq,
            sourceKind: sourceKind,
            baseChannelUtil: baseChannelUtil,
            uplinkSnr: uplinkSnr,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PacketEventsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {sessionId = false,
              sourceNodeId = false,
              pingCorrelationsTx = false,
              pingCorrelationsAck = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (pingCorrelationsTx) db.pingCorrelations,
                if (pingCorrelationsAck) db.pingCorrelations
              ],
              addJoins: <
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
                      dynamic>>(state) {
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$PacketEventsTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$PacketEventsTableReferences._sessionIdTable(db).id,
                  ) as T;
                }
                if (sourceNodeId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sourceNodeId,
                    referencedTable:
                        $$PacketEventsTableReferences._sourceNodeIdTable(db),
                    referencedColumn:
                        $$PacketEventsTableReferences._sourceNodeIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (pingCorrelationsTx)
                    await $_getPrefetchedData<PacketEvent, $PacketEventsTable,
                            PingCorrelation>(
                        currentTable: table,
                        referencedTable: $$PacketEventsTableReferences
                            ._pingCorrelationsTxTable(db),
                        managerFromTypedResult: (p0) =>
                            $$PacketEventsTableReferences(db, table, p0)
                                .pingCorrelationsTx,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.txEventId == item.id),
                        typedResults: items),
                  if (pingCorrelationsAck)
                    await $_getPrefetchedData<PacketEvent, $PacketEventsTable,
                            PingCorrelation>(
                        currentTable: table,
                        referencedTable: $$PacketEventsTableReferences
                            ._pingCorrelationsAckTable(db),
                        managerFromTypedResult: (p0) =>
                            $$PacketEventsTableReferences(db, table, p0)
                                .pingCorrelationsAck,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.ackEventId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$PacketEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PacketEventsTable,
    PacketEvent,
    $$PacketEventsTableFilterComposer,
    $$PacketEventsTableOrderingComposer,
    $$PacketEventsTableAnnotationComposer,
    $$PacketEventsTableCreateCompanionBuilder,
    $$PacketEventsTableUpdateCompanionBuilder,
    (PacketEvent, $$PacketEventsTableReferences),
    PacketEvent,
    PrefetchHooks Function(
        {bool sessionId,
        bool sourceNodeId,
        bool pingCorrelationsTx,
        bool pingCorrelationsAck})>;
typedef $$PingCorrelationsTableCreateCompanionBuilder
    = PingCorrelationsCompanion Function({
  Value<int> id,
  required int txEventId,
  Value<int?> ackEventId,
  Value<int?> roundTripMs,
  Value<String> ackStatus,
});
typedef $$PingCorrelationsTableUpdateCompanionBuilder
    = PingCorrelationsCompanion Function({
  Value<int> id,
  Value<int> txEventId,
  Value<int?> ackEventId,
  Value<int?> roundTripMs,
  Value<String> ackStatus,
});

final class $$PingCorrelationsTableReferences extends BaseReferences<
    _$AppDatabase, $PingCorrelationsTable, PingCorrelation> {
  $$PingCorrelationsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $PacketEventsTable _txEventIdTable(_$AppDatabase db) =>
      db.packetEvents.createAlias($_aliasNameGenerator(
          db.pingCorrelations.txEventId, db.packetEvents.id));

  $$PacketEventsTableProcessedTableManager get txEventId {
    final $_column = $_itemColumn<int>('tx_event_id')!;

    final manager = $$PacketEventsTableTableManager($_db, $_db.packetEvents)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_txEventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $PacketEventsTable _ackEventIdTable(_$AppDatabase db) =>
      db.packetEvents.createAlias($_aliasNameGenerator(
          db.pingCorrelations.ackEventId, db.packetEvents.id));

  $$PacketEventsTableProcessedTableManager? get ackEventId {
    final $_column = $_itemColumn<int>('ack_event_id');
    if ($_column == null) return null;
    final manager = $$PacketEventsTableTableManager($_db, $_db.packetEvents)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ackEventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$PingCorrelationsTableFilterComposer
    extends Composer<_$AppDatabase, $PingCorrelationsTable> {
  $$PingCorrelationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get roundTripMs => $composableBuilder(
      column: $table.roundTripMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ackStatus => $composableBuilder(
      column: $table.ackStatus, builder: (column) => ColumnFilters(column));

  $$PacketEventsTableFilterComposer get txEventId {
    final $$PacketEventsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.txEventId,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableFilterComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$PacketEventsTableFilterComposer get ackEventId {
    final $$PacketEventsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.ackEventId,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableFilterComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PingCorrelationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PingCorrelationsTable> {
  $$PingCorrelationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get roundTripMs => $composableBuilder(
      column: $table.roundTripMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ackStatus => $composableBuilder(
      column: $table.ackStatus, builder: (column) => ColumnOrderings(column));

  $$PacketEventsTableOrderingComposer get txEventId {
    final $$PacketEventsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.txEventId,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableOrderingComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$PacketEventsTableOrderingComposer get ackEventId {
    final $$PacketEventsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.ackEventId,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableOrderingComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PingCorrelationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PingCorrelationsTable> {
  $$PingCorrelationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get roundTripMs => $composableBuilder(
      column: $table.roundTripMs, builder: (column) => column);

  GeneratedColumn<String> get ackStatus =>
      $composableBuilder(column: $table.ackStatus, builder: (column) => column);

  $$PacketEventsTableAnnotationComposer get txEventId {
    final $$PacketEventsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.txEventId,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableAnnotationComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$PacketEventsTableAnnotationComposer get ackEventId {
    final $$PacketEventsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.ackEventId,
        referencedTable: $db.packetEvents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PacketEventsTableAnnotationComposer(
              $db: $db,
              $table: $db.packetEvents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PingCorrelationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PingCorrelationsTable,
    PingCorrelation,
    $$PingCorrelationsTableFilterComposer,
    $$PingCorrelationsTableOrderingComposer,
    $$PingCorrelationsTableAnnotationComposer,
    $$PingCorrelationsTableCreateCompanionBuilder,
    $$PingCorrelationsTableUpdateCompanionBuilder,
    (PingCorrelation, $$PingCorrelationsTableReferences),
    PingCorrelation,
    PrefetchHooks Function({bool txEventId, bool ackEventId})> {
  $$PingCorrelationsTableTableManager(
      _$AppDatabase db, $PingCorrelationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PingCorrelationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PingCorrelationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PingCorrelationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> txEventId = const Value.absent(),
            Value<int?> ackEventId = const Value.absent(),
            Value<int?> roundTripMs = const Value.absent(),
            Value<String> ackStatus = const Value.absent(),
          }) =>
              PingCorrelationsCompanion(
            id: id,
            txEventId: txEventId,
            ackEventId: ackEventId,
            roundTripMs: roundTripMs,
            ackStatus: ackStatus,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int txEventId,
            Value<int?> ackEventId = const Value.absent(),
            Value<int?> roundTripMs = const Value.absent(),
            Value<String> ackStatus = const Value.absent(),
          }) =>
              PingCorrelationsCompanion.insert(
            id: id,
            txEventId: txEventId,
            ackEventId: ackEventId,
            roundTripMs: roundTripMs,
            ackStatus: ackStatus,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$PingCorrelationsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({txEventId = false, ackEventId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                      dynamic>>(state) {
                if (txEventId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.txEventId,
                    referencedTable:
                        $$PingCorrelationsTableReferences._txEventIdTable(db),
                    referencedColumn: $$PingCorrelationsTableReferences
                        ._txEventIdTable(db)
                        .id,
                  ) as T;
                }
                if (ackEventId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.ackEventId,
                    referencedTable:
                        $$PingCorrelationsTableReferences._ackEventIdTable(db),
                    referencedColumn: $$PingCorrelationsTableReferences
                        ._ackEventIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$PingCorrelationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PingCorrelationsTable,
    PingCorrelation,
    $$PingCorrelationsTableFilterComposer,
    $$PingCorrelationsTableOrderingComposer,
    $$PingCorrelationsTableAnnotationComposer,
    $$PingCorrelationsTableCreateCompanionBuilder,
    $$PingCorrelationsTableUpdateCompanionBuilder,
    (PingCorrelation, $$PingCorrelationsTableReferences),
    PingCorrelation,
    PrefetchHooks Function({bool txEventId, bool ackEventId})>;
typedef $$RigProfilesTableCreateCompanionBuilder = RigProfilesCompanion
    Function({
  Value<int> id,
  required String name,
  Value<String> role,
  Value<String> radioModel,
  Value<String> antennaName,
  Value<double> antennaGainDbi,
  Value<String> cableType,
  Value<double> cableLengthM,
  Value<int> connectorCount,
  Value<double> connectorLossDb,
  Value<String> notes,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<bool> archived,
});
typedef $$RigProfilesTableUpdateCompanionBuilder = RigProfilesCompanion
    Function({
  Value<int> id,
  Value<String> name,
  Value<String> role,
  Value<String> radioModel,
  Value<String> antennaName,
  Value<double> antennaGainDbi,
  Value<String> cableType,
  Value<double> cableLengthM,
  Value<int> connectorCount,
  Value<double> connectorLossDb,
  Value<String> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> archived,
});

class $$RigProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $RigProfilesTable> {
  $$RigProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get radioModel => $composableBuilder(
      column: $table.radioModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get antennaName => $composableBuilder(
      column: $table.antennaName, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get antennaGainDbi => $composableBuilder(
      column: $table.antennaGainDbi,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cableType => $composableBuilder(
      column: $table.cableType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get cableLengthM => $composableBuilder(
      column: $table.cableLengthM, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get connectorCount => $composableBuilder(
      column: $table.connectorCount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get connectorLossDb => $composableBuilder(
      column: $table.connectorLossDb,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get archived => $composableBuilder(
      column: $table.archived, builder: (column) => ColumnFilters(column));
}

class $$RigProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $RigProfilesTable> {
  $$RigProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get radioModel => $composableBuilder(
      column: $table.radioModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get antennaName => $composableBuilder(
      column: $table.antennaName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get antennaGainDbi => $composableBuilder(
      column: $table.antennaGainDbi,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cableType => $composableBuilder(
      column: $table.cableType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get cableLengthM => $composableBuilder(
      column: $table.cableLengthM,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get connectorCount => $composableBuilder(
      column: $table.connectorCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get connectorLossDb => $composableBuilder(
      column: $table.connectorLossDb,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get archived => $composableBuilder(
      column: $table.archived, builder: (column) => ColumnOrderings(column));
}

class $$RigProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RigProfilesTable> {
  $$RigProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get radioModel => $composableBuilder(
      column: $table.radioModel, builder: (column) => column);

  GeneratedColumn<String> get antennaName => $composableBuilder(
      column: $table.antennaName, builder: (column) => column);

  GeneratedColumn<double> get antennaGainDbi => $composableBuilder(
      column: $table.antennaGainDbi, builder: (column) => column);

  GeneratedColumn<String> get cableType =>
      $composableBuilder(column: $table.cableType, builder: (column) => column);

  GeneratedColumn<double> get cableLengthM => $composableBuilder(
      column: $table.cableLengthM, builder: (column) => column);

  GeneratedColumn<int> get connectorCount => $composableBuilder(
      column: $table.connectorCount, builder: (column) => column);

  GeneratedColumn<double> get connectorLossDb => $composableBuilder(
      column: $table.connectorLossDb, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);
}

class $$RigProfilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RigProfilesTable,
    RigProfile,
    $$RigProfilesTableFilterComposer,
    $$RigProfilesTableOrderingComposer,
    $$RigProfilesTableAnnotationComposer,
    $$RigProfilesTableCreateCompanionBuilder,
    $$RigProfilesTableUpdateCompanionBuilder,
    (RigProfile, BaseReferences<_$AppDatabase, $RigProfilesTable, RigProfile>),
    RigProfile,
    PrefetchHooks Function()> {
  $$RigProfilesTableTableManager(_$AppDatabase db, $RigProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RigProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RigProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RigProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> radioModel = const Value.absent(),
            Value<String> antennaName = const Value.absent(),
            Value<double> antennaGainDbi = const Value.absent(),
            Value<String> cableType = const Value.absent(),
            Value<double> cableLengthM = const Value.absent(),
            Value<int> connectorCount = const Value.absent(),
            Value<double> connectorLossDb = const Value.absent(),
            Value<String> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> archived = const Value.absent(),
          }) =>
              RigProfilesCompanion(
            id: id,
            name: name,
            role: role,
            radioModel: radioModel,
            antennaName: antennaName,
            antennaGainDbi: antennaGainDbi,
            cableType: cableType,
            cableLengthM: cableLengthM,
            connectorCount: connectorCount,
            connectorLossDb: connectorLossDb,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archived: archived,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String> role = const Value.absent(),
            Value<String> radioModel = const Value.absent(),
            Value<String> antennaName = const Value.absent(),
            Value<double> antennaGainDbi = const Value.absent(),
            Value<String> cableType = const Value.absent(),
            Value<double> cableLengthM = const Value.absent(),
            Value<int> connectorCount = const Value.absent(),
            Value<double> connectorLossDb = const Value.absent(),
            Value<String> notes = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<bool> archived = const Value.absent(),
          }) =>
              RigProfilesCompanion.insert(
            id: id,
            name: name,
            role: role,
            radioModel: radioModel,
            antennaName: antennaName,
            antennaGainDbi: antennaGainDbi,
            cableType: cableType,
            cableLengthM: cableLengthM,
            connectorCount: connectorCount,
            connectorLossDb: connectorLossDb,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archived: archived,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RigProfilesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RigProfilesTable,
    RigProfile,
    $$RigProfilesTableFilterComposer,
    $$RigProfilesTableOrderingComposer,
    $$RigProfilesTableAnnotationComposer,
    $$RigProfilesTableCreateCompanionBuilder,
    $$RigProfilesTableUpdateCompanionBuilder,
    (RigProfile, BaseReferences<_$AppDatabase, $RigProfilesTable, RigProfile>),
    RigProfile,
    PrefetchHooks Function()>;
typedef $$TestPlansTableCreateCompanionBuilder = TestPlansCompanion Function({
  Value<int> id,
  required int coverageMapId,
  required String title,
  required String template,
  required String intentJson,
  Value<String> status,
  Value<int> currentStep,
  Value<bool> remoteChanges,
  required DateTime createdAt,
  Value<DateTime?> finishedAt,
  Value<String?> resultJson,
  Value<String?> aiResultJson,
});
typedef $$TestPlansTableUpdateCompanionBuilder = TestPlansCompanion Function({
  Value<int> id,
  Value<int> coverageMapId,
  Value<String> title,
  Value<String> template,
  Value<String> intentJson,
  Value<String> status,
  Value<int> currentStep,
  Value<bool> remoteChanges,
  Value<DateTime> createdAt,
  Value<DateTime?> finishedAt,
  Value<String?> resultJson,
  Value<String?> aiResultJson,
});

final class $$TestPlansTableReferences
    extends BaseReferences<_$AppDatabase, $TestPlansTable, TestPlan> {
  $$TestPlansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CoverageMapsTable _coverageMapIdTable(_$AppDatabase db) =>
      db.coverageMaps.createAlias(
          $_aliasNameGenerator(db.testPlans.coverageMapId, db.coverageMaps.id));

  $$CoverageMapsTableProcessedTableManager get coverageMapId {
    final $_column = $_itemColumn<int>('coverage_map_id')!;

    final manager = $$CoverageMapsTableTableManager($_db, $_db.coverageMaps)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_coverageMapIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$TestStepsTable, List<TestStep>>
      _testStepsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.testSteps,
              aliasName:
                  $_aliasNameGenerator(db.testPlans.id, db.testSteps.planId));

  $$TestStepsTableProcessedTableManager get testStepsRefs {
    final manager = $$TestStepsTableTableManager($_db, $_db.testSteps)
        .filter((f) => f.planId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_testStepsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$TestPlansTableFilterComposer
    extends Composer<_$AppDatabase, $TestPlansTable> {
  $$TestPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get template => $composableBuilder(
      column: $table.template, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get intentJson => $composableBuilder(
      column: $table.intentJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get currentStep => $composableBuilder(
      column: $table.currentStep, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get remoteChanges => $composableBuilder(
      column: $table.remoteChanges, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
      column: $table.finishedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resultJson => $composableBuilder(
      column: $table.resultJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get aiResultJson => $composableBuilder(
      column: $table.aiResultJson, builder: (column) => ColumnFilters(column));

  $$CoverageMapsTableFilterComposer get coverageMapId {
    final $$CoverageMapsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.coverageMapId,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableFilterComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> testStepsRefs(
      Expression<bool> Function($$TestStepsTableFilterComposer f) f) {
    final $$TestStepsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.testSteps,
        getReferencedColumn: (t) => t.planId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestStepsTableFilterComposer(
              $db: $db,
              $table: $db.testSteps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TestPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $TestPlansTable> {
  $$TestPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get template => $composableBuilder(
      column: $table.template, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get intentJson => $composableBuilder(
      column: $table.intentJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get currentStep => $composableBuilder(
      column: $table.currentStep, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get remoteChanges => $composableBuilder(
      column: $table.remoteChanges,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
      column: $table.finishedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resultJson => $composableBuilder(
      column: $table.resultJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get aiResultJson => $composableBuilder(
      column: $table.aiResultJson,
      builder: (column) => ColumnOrderings(column));

  $$CoverageMapsTableOrderingComposer get coverageMapId {
    final $$CoverageMapsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.coverageMapId,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableOrderingComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TestPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $TestPlansTable> {
  $$TestPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get template =>
      $composableBuilder(column: $table.template, builder: (column) => column);

  GeneratedColumn<String> get intentJson => $composableBuilder(
      column: $table.intentJson, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get currentStep => $composableBuilder(
      column: $table.currentStep, builder: (column) => column);

  GeneratedColumn<bool> get remoteChanges => $composableBuilder(
      column: $table.remoteChanges, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
      column: $table.finishedAt, builder: (column) => column);

  GeneratedColumn<String> get resultJson => $composableBuilder(
      column: $table.resultJson, builder: (column) => column);

  GeneratedColumn<String> get aiResultJson => $composableBuilder(
      column: $table.aiResultJson, builder: (column) => column);

  $$CoverageMapsTableAnnotationComposer get coverageMapId {
    final $$CoverageMapsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.coverageMapId,
        referencedTable: $db.coverageMaps,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CoverageMapsTableAnnotationComposer(
              $db: $db,
              $table: $db.coverageMaps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> testStepsRefs<T extends Object>(
      Expression<T> Function($$TestStepsTableAnnotationComposer a) f) {
    final $$TestStepsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.testSteps,
        getReferencedColumn: (t) => t.planId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestStepsTableAnnotationComposer(
              $db: $db,
              $table: $db.testSteps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TestPlansTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TestPlansTable,
    TestPlan,
    $$TestPlansTableFilterComposer,
    $$TestPlansTableOrderingComposer,
    $$TestPlansTableAnnotationComposer,
    $$TestPlansTableCreateCompanionBuilder,
    $$TestPlansTableUpdateCompanionBuilder,
    (TestPlan, $$TestPlansTableReferences),
    TestPlan,
    PrefetchHooks Function({bool coverageMapId, bool testStepsRefs})> {
  $$TestPlansTableTableManager(_$AppDatabase db, $TestPlansTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TestPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TestPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TestPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> coverageMapId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> template = const Value.absent(),
            Value<String> intentJson = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> currentStep = const Value.absent(),
            Value<bool> remoteChanges = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> finishedAt = const Value.absent(),
            Value<String?> resultJson = const Value.absent(),
            Value<String?> aiResultJson = const Value.absent(),
          }) =>
              TestPlansCompanion(
            id: id,
            coverageMapId: coverageMapId,
            title: title,
            template: template,
            intentJson: intentJson,
            status: status,
            currentStep: currentStep,
            remoteChanges: remoteChanges,
            createdAt: createdAt,
            finishedAt: finishedAt,
            resultJson: resultJson,
            aiResultJson: aiResultJson,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int coverageMapId,
            required String title,
            required String template,
            required String intentJson,
            Value<String> status = const Value.absent(),
            Value<int> currentStep = const Value.absent(),
            Value<bool> remoteChanges = const Value.absent(),
            required DateTime createdAt,
            Value<DateTime?> finishedAt = const Value.absent(),
            Value<String?> resultJson = const Value.absent(),
            Value<String?> aiResultJson = const Value.absent(),
          }) =>
              TestPlansCompanion.insert(
            id: id,
            coverageMapId: coverageMapId,
            title: title,
            template: template,
            intentJson: intentJson,
            status: status,
            currentStep: currentStep,
            remoteChanges: remoteChanges,
            createdAt: createdAt,
            finishedAt: finishedAt,
            resultJson: resultJson,
            aiResultJson: aiResultJson,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TestPlansTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {coverageMapId = false, testStepsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (testStepsRefs) db.testSteps],
              addJoins: <
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
                      dynamic>>(state) {
                if (coverageMapId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.coverageMapId,
                    referencedTable:
                        $$TestPlansTableReferences._coverageMapIdTable(db),
                    referencedColumn:
                        $$TestPlansTableReferences._coverageMapIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (testStepsRefs)
                    await $_getPrefetchedData<TestPlan, $TestPlansTable,
                            TestStep>(
                        currentTable: table,
                        referencedTable:
                            $$TestPlansTableReferences._testStepsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TestPlansTableReferences(db, table, p0)
                                .testStepsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.planId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$TestPlansTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TestPlansTable,
    TestPlan,
    $$TestPlansTableFilterComposer,
    $$TestPlansTableOrderingComposer,
    $$TestPlansTableAnnotationComposer,
    $$TestPlansTableCreateCompanionBuilder,
    $$TestPlansTableUpdateCompanionBuilder,
    (TestPlan, $$TestPlansTableReferences),
    TestPlan,
    PrefetchHooks Function({bool coverageMapId, bool testStepsRefs})>;
typedef $$TestStepsTableCreateCompanionBuilder = TestStepsCompanion Function({
  Value<int> id,
  required int planId,
  required int ordinal,
  required String kind,
  Value<int?> variant,
  required String title,
  required String instruction,
  Value<String> summary,
  Value<String> paramsJson,
  Value<String> status,
  Value<int?> sessionId,
  Value<DateTime?> startedAt,
  Value<DateTime?> endedAt,
  Value<String> note,
});
typedef $$TestStepsTableUpdateCompanionBuilder = TestStepsCompanion Function({
  Value<int> id,
  Value<int> planId,
  Value<int> ordinal,
  Value<String> kind,
  Value<int?> variant,
  Value<String> title,
  Value<String> instruction,
  Value<String> summary,
  Value<String> paramsJson,
  Value<String> status,
  Value<int?> sessionId,
  Value<DateTime?> startedAt,
  Value<DateTime?> endedAt,
  Value<String> note,
});

final class $$TestStepsTableReferences
    extends BaseReferences<_$AppDatabase, $TestStepsTable, TestStep> {
  $$TestStepsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TestPlansTable _planIdTable(_$AppDatabase db) => db.testPlans
      .createAlias($_aliasNameGenerator(db.testSteps.planId, db.testPlans.id));

  $$TestPlansTableProcessedTableManager get planId {
    final $_column = $_itemColumn<int>('plan_id')!;

    final manager = $$TestPlansTableTableManager($_db, $_db.testPlans)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
          $_aliasNameGenerator(db.testSteps.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager? get sessionId {
    final $_column = $_itemColumn<int>('session_id');
    if ($_column == null) return null;
    final manager = $$SessionsTableTableManager($_db, $_db.sessions)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TestStepsTableFilterComposer
    extends Composer<_$AppDatabase, $TestStepsTable> {
  $$TestStepsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ordinal => $composableBuilder(
      column: $table.ordinal, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get variant => $composableBuilder(
      column: $table.variant, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get instruction => $composableBuilder(
      column: $table.instruction, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paramsJson => $composableBuilder(
      column: $table.paramsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  $$TestPlansTableFilterComposer get planId {
    final $$TestPlansTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.planId,
        referencedTable: $db.testPlans,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestPlansTableFilterComposer(
              $db: $db,
              $table: $db.testPlans,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableFilterComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TestStepsTableOrderingComposer
    extends Composer<_$AppDatabase, $TestStepsTable> {
  $$TestStepsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ordinal => $composableBuilder(
      column: $table.ordinal, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get variant => $composableBuilder(
      column: $table.variant, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get instruction => $composableBuilder(
      column: $table.instruction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paramsJson => $composableBuilder(
      column: $table.paramsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  $$TestPlansTableOrderingComposer get planId {
    final $$TestPlansTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.planId,
        referencedTable: $db.testPlans,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestPlansTableOrderingComposer(
              $db: $db,
              $table: $db.testPlans,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableOrderingComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TestStepsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TestStepsTable> {
  $$TestStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get variant =>
      $composableBuilder(column: $table.variant, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get instruction => $composableBuilder(
      column: $table.instruction, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get paramsJson => $composableBuilder(
      column: $table.paramsJson, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  $$TestPlansTableAnnotationComposer get planId {
    final $$TestPlansTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.planId,
        referencedTable: $db.testPlans,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TestPlansTableAnnotationComposer(
              $db: $db,
              $table: $db.testPlans,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TestStepsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TestStepsTable,
    TestStep,
    $$TestStepsTableFilterComposer,
    $$TestStepsTableOrderingComposer,
    $$TestStepsTableAnnotationComposer,
    $$TestStepsTableCreateCompanionBuilder,
    $$TestStepsTableUpdateCompanionBuilder,
    (TestStep, $$TestStepsTableReferences),
    TestStep,
    PrefetchHooks Function({bool planId, bool sessionId})> {
  $$TestStepsTableTableManager(_$AppDatabase db, $TestStepsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TestStepsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TestStepsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TestStepsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> planId = const Value.absent(),
            Value<int> ordinal = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<int?> variant = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> instruction = const Value.absent(),
            Value<String> summary = const Value.absent(),
            Value<String> paramsJson = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int?> sessionId = const Value.absent(),
            Value<DateTime?> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<String> note = const Value.absent(),
          }) =>
              TestStepsCompanion(
            id: id,
            planId: planId,
            ordinal: ordinal,
            kind: kind,
            variant: variant,
            title: title,
            instruction: instruction,
            summary: summary,
            paramsJson: paramsJson,
            status: status,
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: endedAt,
            note: note,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int planId,
            required int ordinal,
            required String kind,
            Value<int?> variant = const Value.absent(),
            required String title,
            required String instruction,
            Value<String> summary = const Value.absent(),
            Value<String> paramsJson = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int?> sessionId = const Value.absent(),
            Value<DateTime?> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<String> note = const Value.absent(),
          }) =>
              TestStepsCompanion.insert(
            id: id,
            planId: planId,
            ordinal: ordinal,
            kind: kind,
            variant: variant,
            title: title,
            instruction: instruction,
            summary: summary,
            paramsJson: paramsJson,
            status: status,
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: endedAt,
            note: note,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TestStepsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({planId = false, sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                      dynamic>>(state) {
                if (planId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.planId,
                    referencedTable:
                        $$TestStepsTableReferences._planIdTable(db),
                    referencedColumn:
                        $$TestStepsTableReferences._planIdTable(db).id,
                  ) as T;
                }
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$TestStepsTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$TestStepsTableReferences._sessionIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TestStepsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TestStepsTable,
    TestStep,
    $$TestStepsTableFilterComposer,
    $$TestStepsTableOrderingComposer,
    $$TestStepsTableAnnotationComposer,
    $$TestStepsTableCreateCompanionBuilder,
    $$TestStepsTableUpdateCompanionBuilder,
    (TestStep, $$TestStepsTableReferences),
    TestStep,
    PrefetchHooks Function({bool planId, bool sessionId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$NodesTableTableManager get nodes =>
      $$NodesTableTableManager(_db, _db.nodes);
  $$CoverageMapsTableTableManager get coverageMaps =>
      $$CoverageMapsTableTableManager(_db, _db.coverageMaps);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$PacketEventsTableTableManager get packetEvents =>
      $$PacketEventsTableTableManager(_db, _db.packetEvents);
  $$PingCorrelationsTableTableManager get pingCorrelations =>
      $$PingCorrelationsTableTableManager(_db, _db.pingCorrelations);
  $$RigProfilesTableTableManager get rigProfiles =>
      $$RigProfilesTableTableManager(_db, _db.rigProfiles);
  $$TestPlansTableTableManager get testPlans =>
      $$TestPlansTableTableManager(_db, _db.testPlans);
  $$TestStepsTableTableManager get testSteps =>
      $$TestStepsTableTableManager(_db, _db.testSteps);
}
