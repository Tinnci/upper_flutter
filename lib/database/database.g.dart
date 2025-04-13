// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SensorReadingsTable extends SensorReadings
    with TableInfo<$SensorReadingsTable, SensorReading> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SensorReadingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<double> temperature = GeneratedColumn<double>(
    'temperature',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _humidityMeta = const VerificationMeta(
    'humidity',
  );
  @override
  late final GeneratedColumn<double> humidity = GeneratedColumn<double>(
    'humidity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noiseMeta = const VerificationMeta('noise');
  @override
  late final GeneratedColumn<double> noise = GeneratedColumn<double>(
    'noise',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lightMeta = const VerificationMeta('light');
  @override
  late final GeneratedColumn<double> light = GeneratedColumn<double>(
    'light',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    timestamp,
    temperature,
    humidity,
    noise,
    light,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sensor_readings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SensorReading> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_temperatureMeta);
    }
    if (data.containsKey('humidity')) {
      context.handle(
        _humidityMeta,
        humidity.isAcceptableOrUnknown(data['humidity']!, _humidityMeta),
      );
    } else if (isInserting) {
      context.missing(_humidityMeta);
    }
    if (data.containsKey('noise')) {
      context.handle(
        _noiseMeta,
        noise.isAcceptableOrUnknown(data['noise']!, _noiseMeta),
      );
    } else if (isInserting) {
      context.missing(_noiseMeta);
    }
    if (data.containsKey('light')) {
      context.handle(
        _lightMeta,
        light.isAcceptableOrUnknown(data['light']!, _lightMeta),
      );
    } else if (isInserting) {
      context.missing(_lightMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SensorReading map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SensorReading(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      timestamp:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}timestamp'],
          )!,
      temperature:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}temperature'],
          )!,
      humidity:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}humidity'],
          )!,
      noise:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}noise'],
          )!,
      light:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}light'],
          )!,
    );
  }

  @override
  $SensorReadingsTable createAlias(String alias) {
    return $SensorReadingsTable(attachedDatabase, alias);
  }
}

class SensorReading extends DataClass implements Insertable<SensorReading> {
  final int id;
  final int timestamp;
  final double temperature;
  final double humidity;
  final double noise;
  final double light;
  const SensorReading({
    required this.id,
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.noise,
    required this.light,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['timestamp'] = Variable<int>(timestamp);
    map['temperature'] = Variable<double>(temperature);
    map['humidity'] = Variable<double>(humidity);
    map['noise'] = Variable<double>(noise);
    map['light'] = Variable<double>(light);
    return map;
  }

  SensorReadingsCompanion toCompanion(bool nullToAbsent) {
    return SensorReadingsCompanion(
      id: Value(id),
      timestamp: Value(timestamp),
      temperature: Value(temperature),
      humidity: Value(humidity),
      noise: Value(noise),
      light: Value(light),
    );
  }

  factory SensorReading.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SensorReading(
      id: serializer.fromJson<int>(json['id']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      temperature: serializer.fromJson<double>(json['temperature']),
      humidity: serializer.fromJson<double>(json['humidity']),
      noise: serializer.fromJson<double>(json['noise']),
      light: serializer.fromJson<double>(json['light']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'timestamp': serializer.toJson<int>(timestamp),
      'temperature': serializer.toJson<double>(temperature),
      'humidity': serializer.toJson<double>(humidity),
      'noise': serializer.toJson<double>(noise),
      'light': serializer.toJson<double>(light),
    };
  }

  SensorReading copyWith({
    int? id,
    int? timestamp,
    double? temperature,
    double? humidity,
    double? noise,
    double? light,
  }) => SensorReading(
    id: id ?? this.id,
    timestamp: timestamp ?? this.timestamp,
    temperature: temperature ?? this.temperature,
    humidity: humidity ?? this.humidity,
    noise: noise ?? this.noise,
    light: light ?? this.light,
  );
  SensorReading copyWithCompanion(SensorReadingsCompanion data) {
    return SensorReading(
      id: data.id.present ? data.id.value : this.id,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      temperature:
          data.temperature.present ? data.temperature.value : this.temperature,
      humidity: data.humidity.present ? data.humidity.value : this.humidity,
      noise: data.noise.present ? data.noise.value : this.noise,
      light: data.light.present ? data.light.value : this.light,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SensorReading(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('temperature: $temperature, ')
          ..write('humidity: $humidity, ')
          ..write('noise: $noise, ')
          ..write('light: $light')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, timestamp, temperature, humidity, noise, light);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SensorReading &&
          other.id == this.id &&
          other.timestamp == this.timestamp &&
          other.temperature == this.temperature &&
          other.humidity == this.humidity &&
          other.noise == this.noise &&
          other.light == this.light);
}

class SensorReadingsCompanion extends UpdateCompanion<SensorReading> {
  final Value<int> id;
  final Value<int> timestamp;
  final Value<double> temperature;
  final Value<double> humidity;
  final Value<double> noise;
  final Value<double> light;
  const SensorReadingsCompanion({
    this.id = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.temperature = const Value.absent(),
    this.humidity = const Value.absent(),
    this.noise = const Value.absent(),
    this.light = const Value.absent(),
  });
  SensorReadingsCompanion.insert({
    this.id = const Value.absent(),
    required int timestamp,
    required double temperature,
    required double humidity,
    required double noise,
    required double light,
  }) : timestamp = Value(timestamp),
       temperature = Value(temperature),
       humidity = Value(humidity),
       noise = Value(noise),
       light = Value(light);
  static Insertable<SensorReading> custom({
    Expression<int>? id,
    Expression<int>? timestamp,
    Expression<double>? temperature,
    Expression<double>? humidity,
    Expression<double>? noise,
    Expression<double>? light,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timestamp != null) 'timestamp': timestamp,
      if (temperature != null) 'temperature': temperature,
      if (humidity != null) 'humidity': humidity,
      if (noise != null) 'noise': noise,
      if (light != null) 'light': light,
    });
  }

  SensorReadingsCompanion copyWith({
    Value<int>? id,
    Value<int>? timestamp,
    Value<double>? temperature,
    Value<double>? humidity,
    Value<double>? noise,
    Value<double>? light,
  }) {
    return SensorReadingsCompanion(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      noise: noise ?? this.noise,
      light: light ?? this.light,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<double>(temperature.value);
    }
    if (humidity.present) {
      map['humidity'] = Variable<double>(humidity.value);
    }
    if (noise.present) {
      map['noise'] = Variable<double>(noise.value);
    }
    if (light.present) {
      map['light'] = Variable<double>(light.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SensorReadingsCompanion(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('temperature: $temperature, ')
          ..write('humidity: $humidity, ')
          ..write('noise: $noise, ')
          ..write('light: $light')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SensorReadingsTable sensorReadings = $SensorReadingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [sensorReadings];
}

typedef $$SensorReadingsTableCreateCompanionBuilder =
    SensorReadingsCompanion Function({
      Value<int> id,
      required int timestamp,
      required double temperature,
      required double humidity,
      required double noise,
      required double light,
    });
typedef $$SensorReadingsTableUpdateCompanionBuilder =
    SensorReadingsCompanion Function({
      Value<int> id,
      Value<int> timestamp,
      Value<double> temperature,
      Value<double> humidity,
      Value<double> noise,
      Value<double> light,
    });

class $$SensorReadingsTableFilterComposer
    extends Composer<_$AppDatabase, $SensorReadingsTable> {
  $$SensorReadingsTableFilterComposer({
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

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get humidity => $composableBuilder(
    column: $table.humidity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get noise => $composableBuilder(
    column: $table.noise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get light => $composableBuilder(
    column: $table.light,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SensorReadingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SensorReadingsTable> {
  $$SensorReadingsTableOrderingComposer({
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

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get humidity => $composableBuilder(
    column: $table.humidity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get noise => $composableBuilder(
    column: $table.noise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get light => $composableBuilder(
    column: $table.light,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SensorReadingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SensorReadingsTable> {
  $$SensorReadingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumn<double> get humidity =>
      $composableBuilder(column: $table.humidity, builder: (column) => column);

  GeneratedColumn<double> get noise =>
      $composableBuilder(column: $table.noise, builder: (column) => column);

  GeneratedColumn<double> get light =>
      $composableBuilder(column: $table.light, builder: (column) => column);
}

class $$SensorReadingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SensorReadingsTable,
          SensorReading,
          $$SensorReadingsTableFilterComposer,
          $$SensorReadingsTableOrderingComposer,
          $$SensorReadingsTableAnnotationComposer,
          $$SensorReadingsTableCreateCompanionBuilder,
          $$SensorReadingsTableUpdateCompanionBuilder,
          (
            SensorReading,
            BaseReferences<_$AppDatabase, $SensorReadingsTable, SensorReading>,
          ),
          SensorReading,
          PrefetchHooks Function()
        > {
  $$SensorReadingsTableTableManager(
    _$AppDatabase db,
    $SensorReadingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SensorReadingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$SensorReadingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$SensorReadingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<double> temperature = const Value.absent(),
                Value<double> humidity = const Value.absent(),
                Value<double> noise = const Value.absent(),
                Value<double> light = const Value.absent(),
              }) => SensorReadingsCompanion(
                id: id,
                timestamp: timestamp,
                temperature: temperature,
                humidity: humidity,
                noise: noise,
                light: light,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int timestamp,
                required double temperature,
                required double humidity,
                required double noise,
                required double light,
              }) => SensorReadingsCompanion.insert(
                id: id,
                timestamp: timestamp,
                temperature: temperature,
                humidity: humidity,
                noise: noise,
                light: light,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SensorReadingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SensorReadingsTable,
      SensorReading,
      $$SensorReadingsTableFilterComposer,
      $$SensorReadingsTableOrderingComposer,
      $$SensorReadingsTableAnnotationComposer,
      $$SensorReadingsTableCreateCompanionBuilder,
      $$SensorReadingsTableUpdateCompanionBuilder,
      (
        SensorReading,
        BaseReferences<_$AppDatabase, $SensorReadingsTable, SensorReading>,
      ),
      SensorReading,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SensorReadingsTableTableManager get sensorReadings =>
      $$SensorReadingsTableTableManager(_db, _db.sensorReadings);
}
