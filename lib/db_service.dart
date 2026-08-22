import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ColumnInfo {
  final int cid;
  final String name;
  final String type;
  final bool notNull;
  final String? dfltValue;
  final bool isPk;

  const ColumnInfo({
    required this.cid,
    required this.name,
    required this.type,
    required this.notNull,
    this.dfltValue,
    required this.isPk,
  });

  factory ColumnInfo.fromMap(Map<String, Object?> map) {
    return ColumnInfo(
      cid: (map['cid'] as num?)?.toInt() ?? 0,
      name: map['name']?.toString() ?? '',
      type: (map['type']?.toString() ?? 'TEXT').toUpperCase(),
      notNull: ((map['notnull'] as num?)?.toInt() ?? 0) == 1,
      dfltValue: map['dflt_value']?.toString(),
      isPk: ((map['pk'] as num?)?.toInt() ?? 0) >= 1,
    );
  }
}

class IndexInfo {
  final String name;
  final bool unique;
  final String origin;
  final bool partial;
  final List<String> columns;

  const IndexInfo({
    required this.name,
    required this.unique,
    required this.origin,
    required this.partial,
    this.columns = const [],
  });
}

class TableSummary {
  final String name;
  final String type; // 'table' or 'view'
  final int? rowCount;
  final int? columnCount;

  const TableSummary({
    required this.name,
    required this.type,
    this.rowCount,
    this.columnCount,
  });
}

class DatabaseService {
  Database? _db;
  String? _currentDbPath;

  String? get currentDbPath => _currentDbPath;
  bool get isConnected => _db != null;

  /// Safely quote SQLite identifiers (table names, column names)
  static String quote(String identifier) {
    final escaped = identifier.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> connect(String path) async {
    if (!File(path).existsSync()) {
      throw Exception("Database file not found at $path");
    }
    await close();
    _db = await openDatabase(path);
    _currentDbPath = path;
  }

  Future<List<String>> getTables() async {
    if (_db == null) throw Exception("Database not connected");
    final result = await _db!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name ASC;"
    );
    return result.map((e) => e['name'] as String).toList();
  }

  Future<List<TableSummary>> getTableSummaries() async {
    if (_db == null) throw Exception("Database not connected");
    final items = await _db!.rawQuery(
      "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY type ASC, name ASC;"
    );

    final summaries = <TableSummary>[];
    for (final item in items) {
      final name = item['name'] as String;
      final type = item['type'] as String;
      int? count;
      try {
        count = await countRows(name);
      } catch (_) {}
      summaries.add(TableSummary(
        name: name,
        type: type,
        rowCount: count,
      ));
    }
    return summaries;
  }

  Future<List<ColumnInfo>> getTableSchema(String tableName) async {
    if (_db == null) throw Exception("Database not connected");
    final quoted = quote(tableName);
    final info = await _db!.rawQuery('PRAGMA table_info($quoted)');
    return info.map((m) => ColumnInfo.fromMap(m)).toList();
  }

  Future<List<IndexInfo>> getTableIndexes(String tableName) async {
    if (_db == null) throw Exception("Database not connected");
    final quoted = quote(tableName);
    final list = await _db!.rawQuery('PRAGMA index_list($quoted)');
    final indexes = <IndexInfo>[];

    for (final row in list) {
      final idxName = row['name']?.toString() ?? '';
      final unique = ((row['unique'] as num?)?.toInt() ?? 0) == 1;
      final origin = row['origin']?.toString() ?? 'c';
      final partial = ((row['partial'] as num?)?.toInt() ?? 0) == 1;

      List<String> cols = [];
      if (idxName.isNotEmpty) {
        try {
          final colsInfo = await _db!.rawQuery('PRAGMA index_info(${quote(idxName)})');
          cols = colsInfo
              .map((c) => c['name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        } catch (_) {}
      }

      indexes.add(IndexInfo(
        name: idxName,
        unique: unique,
        origin: origin,
        partial: partial,
        columns: cols,
      ));
    }

    return indexes;
  }

  Future<String?> getTableDDL(String tableName) async {
    if (_db == null) throw Exception("Database not connected");
    final result = await _db!.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = ? LIMIT 1;",
      [tableName],
    );
    if (result.isNotEmpty && result.first['sql'] != null) {
      return result.first['sql'] as String;
    }
    return null;
  }

  Future<List<String>> getTableHeaders(String tableName) async {
    if (_db == null) throw Exception("Database not connected");
    try {
      final schema = await getTableSchema(tableName);
      if (schema.isNotEmpty) {
        return schema.map((c) => c.name).toList();
      }
    } catch (_) {}

    // Fallback for views or virtual tables
    final quoted = quote(tableName);
    final result = await _db!.rawQuery('SELECT * FROM $quoted LIMIT 1');
    if (result.isEmpty) return [];
    return result.first.keys.toList();
  }

  Future<List<Map<String, Object?>>> fetchRows(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? filterColumn,
    String? filterText,
    String? sortColumn,
    bool sortAscending = true,
  }) async {
    if (_db == null) throw Exception("Database not connected");
    final quotedTable = quote(tableName);

    String query = 'SELECT * FROM $quotedTable';
    List<Object?> args = [];

    if (filterText != null && filterText.trim().isNotEmpty) {
      if (filterColumn != null && filterColumn.isNotEmpty && filterColumn != '__all__') {
        query += ' WHERE CAST(${quote(filterColumn)} AS TEXT) LIKE ?';
        args.add('%${filterText.trim()}%');
      } else {
        // Search across all columns
        final headers = await getTableHeaders(tableName);
        if (headers.isNotEmpty) {
          final whereClauses = headers.map((h) => 'CAST(${quote(h)} AS TEXT) LIKE ?').join(' OR ');
          query += ' WHERE ($whereClauses)';
          args = List.filled(headers.length, '%${filterText.trim()}%');
        }
      }
    }

    if (sortColumn != null && sortColumn.isNotEmpty) {
      final direction = sortAscending ? 'ASC' : 'DESC';
      query += ' ORDER BY ${quote(sortColumn)} $direction';
    }

    query += ' LIMIT $limit OFFSET $offset';
    return _db!.rawQuery(query, args);
  }

  Future<int> countRows(
    String tableName, {
    String? filterColumn,
    String? filterText,
  }) async {
    if (_db == null) throw Exception("Database not connected");
    final quotedTable = quote(tableName);

    String query = 'SELECT COUNT(*) as count FROM $quotedTable';
    List<Object?> args = [];

    if (filterText != null && filterText.trim().isNotEmpty) {
      if (filterColumn != null && filterColumn.isNotEmpty && filterColumn != '__all__') {
        query += ' WHERE CAST(${quote(filterColumn)} AS TEXT) LIKE ?';
        args.add('%${filterText.trim()}%');
      } else {
        final headers = await getTableHeaders(tableName);
        if (headers.isNotEmpty) {
          final whereClauses = headers.map((h) => 'CAST(${quote(h)} AS TEXT) LIKE ?').join(' OR ');
          query += ' WHERE ($whereClauses)';
          args = List.filled(headers.length, '%${filterText.trim()}%');
        }
      }
    }

    final result = await _db!.rawQuery(query, args);
    if (result.isEmpty) return 0;
    final value = result.first.values.first;
    return (value as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, Object?>>> executeQuery(String sql) async {
    if (_db == null) throw Exception("Database not connected");
    return _db!.rawQuery(sql);
  }

  Stream<List<Map<String, Object?>>> streamRows(String tableName, {int chunkSize = 100}) async* {
    if (_db == null) throw Exception("Database not connected");
    final quoted = quote(tableName);
    int offset = 0;
    while (true) {
      final batch = await _db!.rawQuery('SELECT * FROM $quoted LIMIT $chunkSize OFFSET $offset');
      if (batch.isEmpty) break;
      yield batch;
      offset += chunkSize;
      await Future.delayed(Duration.zero);
    }
  }

  Future<int> getUserVersion() async {
    if (_db == null) throw Exception("Database not connected");
    final result = await _db!.rawQuery('PRAGMA user_version;');
    if (result.isEmpty) return 0;
    final value = result.first.values.first;
    return (value as num?)?.toInt() ?? 0;
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _currentDbPath = null;
    }
  }
}
