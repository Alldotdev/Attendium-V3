import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../core/constants/app_constants.dart';
import 'database_schema.dart';

/// Central SQLite Database Service managing connections, WAL pragma setup, and transactions.
class AppDatabase {
  final Database _db;

  AppDatabase(this._db);

  Database get rawDb => _db;

  /// Creates and opens an in-memory database for testing and fast local execution.
  factory AppDatabase.inMemory() {
    final db = sqlite3.openInMemory();
    _initializeDatabase(db);
    return AppDatabase(db);
  }

  /// Opens the authoritative persistent SQLite database in the application documents directory.
  static Future<AppDatabase> openPersistent([String? customPath]) async {
    String dbPath;
    if (customPath != null) {
      dbPath = customPath;
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      final appDir = Directory(p.join(docDir.path, 'Attendium'));
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      dbPath = p.join(appDir.path, AppConstants.databaseFileName);
    }

    final db = sqlite3.open(dbPath);
    _initializeDatabase(db);
    return AppDatabase(db);
  }

  static void _initializeDatabase(Database db) {
    // 1. Apply mandatory pragmas
    for (final pragma in DatabaseSchema.mandatoryPragmas) {
      db.execute(pragma);
    }

    // 2. Create 14 relational tables
    for (final createTable in DatabaseSchema.createTableStatements) {
      db.execute(createTable);
    }

    // 3. Create indexes
    for (final createIndex in DatabaseSchema.createIndexStatements) {
      db.execute(createIndex);
    }
  }

  /// Executes an operation within a database transaction.
  T transaction<T>(T Function() action) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final result = action();
      _db.execute('COMMIT;');
      return result;
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void close() {
    _db.dispose();
  }
}
