import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  Database? _db;

  Future<void> connect(String path) async {
    if (!File(path).existsSync()) {
      throw Exception("Database file not found at $path");
    }
    // Initialize FFI if not already done (safe to call multiple times? usually done in main)
    // construct path/db
    _db = await openDatabase(path);
  }

  Future<List<String>> getTables() async {
    if (_db == null) throw Exception("Database not connected");
    final result = await _db!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
    );
    return result.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> getTableHeaders(String tableName) async {
    if (_db == null) throw Exception("Database not connected");
    // Query a single row or use PRAGMA table_info
    // Using limit 1 is safer to just get keys from result map
    final result = await _db!.rawQuery('SELECT * FROM "$tableName" LIMIT 1');
    if (result.isEmpty) return [];
    return result.first.keys.toList();
  }

  // Placeholder for future streaming
  Future<List<Map<String, Object?>>> fetchRows(String tableName, {int limit = 100, int offset = 0}) async {
    if (_db == null) throw Exception("Database not connected");
    return _db!.rawQuery('SELECT * FROM "$tableName" LIMIT $limit OFFSET $offset');
  }

  Future<List<Map<String, Object?>>> executeQuery(String sql) async {
    if (_db == null) throw Exception("Database not connected");
    return _db!.rawQuery(sql);
  }

  Stream<List<Map<String, Object?>>> streamRows(String tableName, {int chunkSize = 100}) async* {
    if (_db == null) throw Exception("Database not connected");
    int offset = 0;
    while (true) {
      final batch = await _db!.rawQuery('SELECT * FROM "$tableName" LIMIT $chunkSize OFFSET $offset');
      if (batch.isEmpty) break;
      yield batch;
      offset += chunkSize;
      // Yield to event loop to allow UI updates
      await Future.delayed(Duration.zero);
    }
  }

  Future<int> countRows(String tableName) async {
    if (_db == null) throw Exception("Database not connected");
    final result = await _db!.rawQuery('SELECT COUNT(*) as count FROM "$tableName"');
    if (result.isEmpty) return 0;
    final value = result.first.values.first;
    return (value as num?)?.toInt() ?? 0;
  }

  Future<int> getUserVersion() async {
    if (_db == null) throw Exception("Database not connected");
    final result = await _db!.rawQuery('PRAGMA user_version;');
    if (result.isEmpty) return 0;
    final value = result.first.values.first;
    return (value as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, Object?>>> fetchPower2Samples(String tableName) async {
    if (_db == null) throw Exception("Database not connected");
    final indices = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512];
    final results = <Map<String, Object?>>[];
    for (final i in indices) {
      final res = await _db!.rawQuery('SELECT * FROM "$tableName" LIMIT 1 OFFSET ${i-1}');
      if (res.isNotEmpty) {
        results.add(res.first);
      }
    }
    return results;
  }
  
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
