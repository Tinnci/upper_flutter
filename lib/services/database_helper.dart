import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/sensor_data.dart'; // 导入数据模型

class DatabaseHelper {
  static const _databaseName = "sensor_data.db";
  static const _databaseVersion = 1;

  static const table = 'sensor_readings';

  static const columnId = 'id';
  static const columnTimestamp = 'timestamp';
  static const columnNoiseDb = 'noise_db';
  static const columnTemperature = 'temperature';
  static const columnHumidity = 'humidity';
  static const columnLightIntensity = 'light_intensity';

  // 单例模式
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  // 数据库实例
  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // 初始化数据库
  _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    print("数据库路径: $path"); // 打印数据库路径以便调试
    return await openDatabase(path,
        version: _databaseVersion,
        onCreate: _onCreate);
  }

  // 创建表
  Future _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE $table (
            $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
            $columnTimestamp TEXT NOT NULL,
            $columnNoiseDb REAL,
            $columnTemperature REAL,
            $columnHumidity REAL,
            $columnLightIntensity REAL
          )
          ''');
    print("数据库表 '$table' 已创建");
  }

  // --- CRUD 操作 ---

  // 插入数据
  Future<int> insertReading(SensorData data) async {
    final db = await instance.database;
    // 移除 id，让数据库自动生成
    final map = data.toMap();
    map.remove(columnId);
    return await db.insert(table, map);
  }

  // 获取最新的 N 条数据
  Future<List<SensorData>> getLatestReadings({int limit = 100}) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      table,
      orderBy: '$columnId DESC',
      limit: limit,
    );
    if (maps.isEmpty) {
      return [];
    }
    // 将 Map 列表转换为 SensorData 列表
    return List.generate(maps.length, (i) {
      return SensorData.fromMap(maps[i]);
    });
  }

  // 获取所有数据
  Future<List<SensorData>> getAllReadings() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      table,
      orderBy: '$columnId DESC',
    );
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) {
      return SensorData.fromMap(maps[i]);
    });
  }

  // 按日期范围搜索数据
  Future<List<SensorData>> searchReadings({String? startDate, String? endDate, int limit = 1000}) async {
    final db = await instance.database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (startDate != null && endDate != null) {
      whereClause = '$columnTimestamp BETWEEN ? AND ?';
      whereArgs = [startDate, endDate];
    } else if (startDate != null) {
      whereClause = '$columnTimestamp >= ?';
      whereArgs = [startDate];
    } else if (endDate != null) {
      whereClause = '$columnTimestamp <= ?';
      whereArgs = [endDate];
    }

    final List<Map<String, dynamic>> maps = await db.query(
      table,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '$columnId DESC',
      limit: limit,
    );

    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) {
      return SensorData.fromMap(maps[i]);
    });
  }

  // 清空所有数据
  Future<int> clearAllData() async {
    final db = await instance.database;
    return await db.delete(table);
  }

  // 删除指定天数前的数据
  Future<int> deleteDataBefore(int days) async {
    final db = await instance.database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    // 使用 ISO8601 格式进行比较
    final cutoffDateString = DateFormat("yyyy-MM-dd HH:mm:ss").format(cutoffDate);
    return await db.delete(
      table,
      where: '$columnTimestamp < ?',
      whereArgs: [cutoffDateString],
    );
  }
}