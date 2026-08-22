import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqliter/db_service.dart';
import 'package:sqliter/utils/exporter.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Heavy SQLite (>1.2 MB / 7.5 MB) Performance & Reliability Tests', () {
    late DatabaseService dbService;
    const dbPath = '/Users/darianhickman/Documents/sqliteplutogrid/test_databases/heavy_5mb.sqlite';

    setUp(() async {
      dbService = DatabaseService();
      expect(File(dbPath).existsSync(), isTrue, reason: 'Database file $dbPath must exist');
      final sizeMb = File(dbPath).lengthSync() / (1024 * 1024);
      expect(sizeMb, greaterThan(1.2), reason: 'File size must be over 1.2 MB (actual: ${sizeMb.toStringAsFixed(2)} MB)');
      await dbService.connect(dbPath);
    });

    tearDown(() async {
      await dbService.close();
    });

    test('1. Connects and summarizes tables in 7.5MB database with 10,000 rows', () async {
      final tables = await dbService.getTableSummaries();
      expect(tables.isNotEmpty, isTrue);
      final txTable = tables.firstWhere((t) => t.name == '1_transactions');
      expect(txTable.rowCount, equals(10000));
      expect(txTable.type, equals('table'));
    });

    test('2. Inspects schema and indexes for 1_transactions', () async {
      final schema = await dbService.getTableSchema('1_transactions');
      expect(schema.length, equals(10));
      expect(schema.any((c) => c.name == 'tx_hash' && c.notNull), isTrue);

      final indexes = await dbService.getTableIndexes('1_transactions');
      expect(indexes.any((idx) => idx.name == 'idx_tx_sender'), isTrue);
      expect(indexes.any((idx) => idx.name == 'idx_tx_status'), isTrue);
    });

    test('3. Fetches paginated rows with large JSON text payloads smoothly', () async {
      final stopwatch = Stopwatch()..start();
      final rows = await dbService.fetchRows('1_transactions', limit: 200, offset: 0);
      stopwatch.stop();

      expect(rows.length, equals(200));
      expect(rows.first.containsKey('metadata'), isTrue);
      expect(rows.first['metadata'].toString(), contains('block_height'));
      expect(stopwatch.elapsedMilliseconds, lessThan(100), reason: '200 rows pagination must take <100ms');
    });

    test('4. Performs fast SQL-level filtering across 10,000 rows', () async {
      final stopwatch = Stopwatch()..start();
      final count = await dbService.countRows('1_transactions', filterColumn: 'status', filterText: 'pending');
      stopwatch.stop();

      expect(count, greaterThan(0));
      expect(stopwatch.elapsedMilliseconds, lessThan(200), reason: 'Filtered count across 10k rows must be fast');
    });

    test('5. Performs SQL-level sorting across 10,000 rows', () async {
      final rows = await dbService.fetchRows(
        '1_transactions',
        limit: 10,
        sortColumn: 'amount',
        sortAscending: false,
      );

      expect(rows.length, equals(10));
      final firstAmount = rows.first['amount'] as double;
      final secondAmount = rows[1]['amount'] as double;
      expect(firstAmount, greaterThanOrEqualTo(secondAmount));
    });

    test('6. Executes aggregate query in SQL Query runner', () async {
      final stopwatch = Stopwatch()..start();
      final results = await dbService.executeQuery(
        'SELECT status, COUNT(*) as count, AVG(amount) as avg_amount FROM "1_transactions" GROUP BY status;'
      );
      stopwatch.stop();

      expect(results.length, greaterThanOrEqualTo(2));
      expect(results.any((r) => r['status'] == 'confirmed'), isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(150));
    });

    test('7. Exports large dataset chunk to CSV and JSON without memory corruption', () async {
      final rows = await dbService.fetchRows('1_transactions', limit: 1000);
      expect(rows.length, equals(1000));

      final csv = DataExporter.toCsv(rows);
      expect(csv.isNotEmpty, isTrue);
      expect(csv.split('\n').length, greaterThanOrEqualTo(1000));

      final jsonStr = DataExporter.toJson(rows.take(50).toList());
      expect(jsonStr.isNotEmpty, isTrue);
      expect(jsonStr, contains('tx_hash'));
    });
  });
}
