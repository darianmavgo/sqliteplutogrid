import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqliter/db_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService Tests (Dataflare Parity)', () {
    late DatabaseService dbService;
    late String testDbPath;

    setUp(() async {
      dbService = DatabaseService();
      final tempDir = Directory.systemTemp.createTempSync('sqliter_test_');
      testDbPath = '${tempDir.path}/test.db';

      // Initialize test database with numeric tables, columns, indexes
      final db = await openDatabase(testDbPath);
      await db.execute('''
        CREATE TABLE "1_users" (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT,
          score REAL DEFAULT 0.0
        );
      ''');
      await db.execute('CREATE INDEX "idx_users_email" ON "1_users" (email);');
      await db.execute('''
        CREATE VIEW "v_active_users" AS 
        SELECT id, name, email FROM "1_users" WHERE score > 0;
      ''');

      await db.rawInsert('INSERT INTO "1_users" (name, email, score) VALUES (?, ?, ?)', ['Alice', 'alice@test.com', 10.5]);
      await db.rawInsert('INSERT INTO "1_users" (name, email, score) VALUES (?, ?, ?)', ['Bob', 'bob@test.com', 0.0]);
      await db.rawInsert('INSERT INTO "1_users" (name, email, score) VALUES (?, ?, ?)', ['Charlie', 'charlie@other.com', 25.0]);
      await db.close();

      await dbService.connect(testDbPath);
    });

    tearDown(() async {
      await dbService.close();
      final file = File(testDbPath);
      if (file.existsSync()) {
        file.parent.deleteSync(recursive: true);
      }
    });

    test('Safe identifier quoting', () {
      expect(DatabaseService.quote('1_users'), '"1_users"');
      expect(DatabaseService.quote('table "with" quotes'), '"table ""with"" quotes"');
    });

    test('Discovers tables and views with summaries', () async {
      final summaries = await dbService.getTableSummaries();
      expect(summaries.length, 2);
      
      final table = summaries.firstWhere((s) => s.name == '1_users');
      expect(table.type, 'table');
      expect(table.rowCount, 3);

      final view = summaries.firstWhere((s) => s.name == 'v_active_users');
      expect(view.type, 'view');
    });

    test('Extracts column schema details', () async {
      final schema = await dbService.getTableSchema('1_users');
      expect(schema.length, 4);

      final idCol = schema.firstWhere((c) => c.name == 'id');
      expect(idCol.isPk, isTrue);
      expect(idCol.type, 'INTEGER');

      final nameCol = schema.firstWhere((c) => c.name == 'name');
      expect(nameCol.notNull, isTrue);

      final scoreCol = schema.firstWhere((c) => c.name == 'score');
      expect(scoreCol.dfltValue, '0.0');
    });

    test('Extracts indexes and columns', () async {
      final indexes = await dbService.getTableIndexes('1_users');
      expect(indexes.any((i) => i.name == 'idx_users_email'), isTrue);
      final emailIdx = indexes.firstWhere((i) => i.name == 'idx_users_email');
      expect(emailIdx.columns, contains('email'));
    });

    test('Extracts table DDL', () async {
      final ddl = await dbService.getTableDDL('1_users');
      expect(ddl, isNotNull);
      expect(ddl, contains('CREATE TABLE "1_users"'));
    });

    test('Filters rows by specific column or across all columns', () async {
      // Filter by email containing 'test.com'
      final results1 = await dbService.fetchRows('1_users', filterColumn: 'email', filterText: 'test.com');
      expect(results1.length, 2);

      // Filter across all columns for 'Charlie'
      final results2 = await dbService.fetchRows('1_users', filterText: 'Charlie');
      expect(results2.length, 1);
      expect(results2.first['name'], 'Charlie');

      // Count filtered
      final count = await dbService.countRows('1_users', filterText: 'test.com');
      expect(count, 2);
    });

    test('Sorts rows at SQL level', () async {
      final asc = await dbService.fetchRows('1_users', sortColumn: 'name', sortAscending: true);
      expect(asc.first['name'], 'Alice');
      expect(asc.last['name'], 'Charlie');

      final desc = await dbService.fetchRows('1_users', sortColumn: 'name', sortAscending: false);
      expect(desc.first['name'], 'Charlie');
      expect(desc.last['name'], 'Alice');
    });

    test('Executes arbitrary query via SQL editor runner', () async {
      final queryResults = await dbService.executeQuery('SELECT name, score * 2 AS double_score FROM "1_users" WHERE id = 1');
      expect(queryResults.length, 1);
      expect(queryResults.first['name'], 'Alice');
      expect(queryResults.first['double_score'], 21.0);
    });
  });
}
