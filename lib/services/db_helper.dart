import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;

  factory DBHelper() => _instance;
  DBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final String path =
        join(await getDatabasesPath(), 'homework_support.db');
    return await openDatabase(
      path,
      version: 2, // bumped from 1 → 2 for new columns
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ------------------------------------------------------------------
  // Schema creation (fresh install)
  // ------------------------------------------------------------------
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE student_performance (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        topic               TEXT    NOT NULL,
        score               REAL    NOT NULL,
        total_questions     INTEGER NOT NULL,
        date_taken          TEXT    NOT NULL,
        grade               TEXT    DEFAULT '',
        recommendation      TEXT    DEFAULT '',
        wrong_questions     TEXT    DEFAULT '[]',
        is_teacher_reviewed INTEGER DEFAULT 0,
        teacher_comment     TEXT    DEFAULT '',
        is_synced           INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE homework_cache (
        id       TEXT PRIMARY KEY,
        title    TEXT,
        due_date TEXT,
        content  TEXT
      )
    ''');
  }

  // ------------------------------------------------------------------
  // Schema migration (existing users upgrading from v1)
  // ------------------------------------------------------------------
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add the new columns introduced in version 2
      await db.execute(
          "ALTER TABLE student_performance ADD COLUMN grade TEXT DEFAULT ''");
      await db.execute(
          "ALTER TABLE student_performance ADD COLUMN recommendation TEXT DEFAULT ''");
      await db.execute(
          "ALTER TABLE student_performance ADD COLUMN wrong_questions TEXT DEFAULT '[]'");
      await db.execute(
          "ALTER TABLE student_performance ADD COLUMN is_teacher_reviewed INTEGER DEFAULT 0");
      await db.execute(
          "ALTER TABLE student_performance ADD COLUMN teacher_comment TEXT DEFAULT ''");
    }
  }

  // ------------------------------------------------------------------
  // CRUD: student_performance
  // ------------------------------------------------------------------

  /// Insert a new performance record.  [data] should be a map matching
  /// the column names (use [Performance.toMap()]).
  Future<int> savePerformance(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('student_performance', data);
  }

  /// Fetch all performance records, newest first.
  Future<List<Map<String, dynamic>>> getPerformance() async {
    final db = await database;
    return await db.query('student_performance',
        orderBy: 'date_taken DESC');
  }

  /// Fetch performance records for a specific topic.
  Future<List<Map<String, dynamic>>> getPerformanceByTopic(
      String topic) async {
    final db = await database;
    return await db.query(
      'student_performance',
      where: 'topic = ?',
      whereArgs: [topic],
      orderBy: 'date_taken DESC',
    );
  }

  /// Update an existing record (e.g. teacher override).
  Future<int> updatePerformance(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update(
      'student_performance',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------------------
  // CRUD: homework_cache
  // ------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getHomework() async {
    final db = await database;
    return await db.query('homework_cache');
  }

  // ------------------------------------------------------------------
  // Adaptive / Rule-Based helpers
  // ------------------------------------------------------------------

  /// Returns true if the student has scored ≥ 80 % on [topicName]
  /// at least once (mastery threshold).
  Future<bool> isTopicMastered(String topicName) async {
    final db = await database;
    final results = await db.query(
      'student_performance',
      where: 'topic = ?',
      whereArgs: [topicName],
    );
    if (results.isEmpty) return false;
    for (final row in results) {
      final double score = (row['score'] as num).toDouble();
      final int total = row['total_questions'] as int;
      if (total > 0 && (score / total) * 100 >= 80) return true;
    }
    return false;
  }

  /// Returns how many times a student has attempted [topic].
  Future<int> attemptCount(String topic) async {
    final db = await database;
    final rows = await db.query(
      'student_performance',
      where: 'topic = ?',
      whereArgs: [topic],
    );
    return rows.length;
  }
}
