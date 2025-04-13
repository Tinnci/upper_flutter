// database.dart
// 需要在文件顶部指定 part 指令，指向生成的代码文件

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart'; // 用于桌面和移动端的 NativeDatabase
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart'; // 用于移动端
import 'package:sqlite3/sqlite3.dart'; // 用于桌面端

part 'database.g.dart'; // Drift 会生成这个文件
// --- 1. 定义数据表 ---
// 使用 Table 类来定义表结构和列
@DataClassName('SensorReading') // 指定生成的 Dart 类名
class SensorReadings extends Table {
  IntColumn get id => integer().autoIncrement()(); // 主键自增
  IntColumn get timestamp => integer()(); // 存储毫秒时间戳
  RealColumn get temperature => real()();
  RealColumn get humidity => real()();
  RealColumn get noise => real()();
  RealColumn get light => real()();
}

// --- 2. 定义数据库类 ---
// 使用 @DriftDatabase 注解，并指定包含的表
@DriftDatabase(tables: [SensorReadings])
class AppDatabase extends _$AppDatabase { // 继承由 drift_dev 生成的 _$AppDatabase
  AppDatabase() : super(_openConnection()); // 调用父类构造，传入连接

  AppDatabase.connect(DatabaseConnection super.connection);

  @override
  int get schemaVersion => 1; // 数据库版本号

  // --- 3. 定义数据访问方法 (DAO - Data Access Object) ---

  /// 插入一条传感器数据
  Future<int> insertSensorData(SensorReadingsCompanion data) {
    // SensorReadingsCompanion 是 Drift 生成的用于插入/更新的对象
    // 我们需要确保传入的时间戳是有效的
    final dataWithTimestamp = data.copyWith(
      timestamp: Value(DateTime.now().millisecondsSinceEpoch), // 使用当前时间戳
    );
    return into(sensorReadings).insert(dataWithTimestamp);
  }

  /// 根据时间范围查询数据 (时间戳为毫秒)
  Future<List<SensorReading>> getSensorDataInRange(DateTime startTime, DateTime endTime) {
    final startMillis = startTime.millisecondsSinceEpoch;
    final endMillis = endTime.millisecondsSinceEpoch;

    print("Drift Querying data between $startTime ($startMillis) and $endTime ($endMillis)");

    // 使用 select 语句进行查询
    return (select(sensorReadings)
          ..where((tbl) => tbl.timestamp.isBetweenValues(startMillis, endMillis))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.timestamp)])) // 按时间升序
        .get(); // 获取结果列表
  }

  /// 删除所有传感器数据
  Future<int> deleteAllSensorData() {
    print("Drift Deleting all data...");
    return delete(sensorReadings).go(); // 执行删除操作
  }
}

// --- 4. 配置数据库连接 ---
// 这个函数负责根据不同平台创建合适的数据库连接
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // 获取存储数据库文件的合适目录
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite')); // 数据库文件名

    // 在移动端 (Android/iOS)，我们需要确保 sqlite3 库可用
    if (Platform.isAndroid || Platform.isIOS) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions(); // 处理旧版Android兼容性
       // 告知 Drift 使用 `sqlite3_flutter_libs` 提供的库
       final cachebase = (await getTemporaryDirectory()).path;
       sqlite3.tempDirectory = cachebase;
    }

    // 创建 NativeDatabase 连接
    return NativeDatabase.createInBackground(file);
  });
}

// --- Helper for SensorData Provider ---
// 可以提供一个将 SensorData 转换为 Drift Companion 对象的方法
// (假设 SensorData 类定义在 sensor_data_provider.dart)
// import '../sensor_data_provider.dart'; // 导入 SensorData 定义
// SensorReadingsCompanion sensorDataToCompanion(SensorData data) {
//   return SensorReadingsCompanion(
//     // id 和 timestamp 会自动或在 insertSensorData 中处理
//     temperature: Value(data.temperature),
//     humidity: Value(data.humidity),
//     noise: Value(data.noise),
//     light: Value(data.light),
//     // timestamp 在 insert 时设置
//   );
// }