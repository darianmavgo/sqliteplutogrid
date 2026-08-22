import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqliter/db_service.dart';
import 'package:sqliter/widgets/table_filter_bar.dart';
import 'package:sqliter/widgets/schema_inspector_view.dart';
import 'package:sqliter/widgets/sql_editor_view.dart';
import 'package:sqliter/widgets/table_status_footer.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (call) async => {
        'hueComponent': 0.5,
        'saturationComponent': 0.5,
        'brightnessComponent': 0.5,
        'alphaComponent': 1.0,
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => null,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.darianmavgo.sqliter/file_open'),
      (call) async => null,
    );
  });

  group('Dataflare Feature Suite Tests', () {
    late DatabaseService dbService;
    late String testDbPath;
    late Directory tempDir;

    setUp(() async {
      dbService = DatabaseService();
      tempDir = Directory.systemTemp.createTempSync('sqliter_suite_test_');
      testDbPath = '${tempDir.path}/test_app.db';

      // Create test SQLite DB with tables, indexes, views, and data
      final db = await openDatabase(testDbPath);
      await db.execute('''
        CREATE TABLE "1_customers" (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT,
          metadata TEXT,
          balance REAL DEFAULT 0.0
        );
      ''');
      await db.execute('CREATE INDEX "idx_cust_email" ON "1_customers" (email);');

      await db.execute('''
        CREATE TABLE "orders" (
          order_id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER,
          total REAL,
          status TEXT
        );
      ''');

      await db.execute('''
        CREATE VIEW "v_top_customers" AS
        SELECT id, name, email, balance FROM "1_customers" WHERE balance > 50.0;
      ''');

      for (int i = 1; i <= 25; i++) {
        await db.rawInsert(
          'INSERT INTO "1_customers" (name, email, metadata, balance) VALUES (?, ?, ?, ?)',
          [
            'Customer $i',
            'cust$i@example.com',
            '{"tier": "gold", "loyalty_points": ${i * 10}}',
            i * 10.5,
          ],
        );
      }
      await db.close();

      await dbService.connect(testDbPath);
    });

    tearDown(() async {
      await dbService.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('1. SchemaInspectorView loads columns, types, indexes, and DDL', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MacosApp(
        home: MacosScaffold(
          children: [
            ContentArea(
              builder: (context, _) => SchemaInspectorView(
                dbService: dbService,
                tableName: '1_customers',
              ),
            ),
          ],
        ),
      ));

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.byType(SchemaInspectorView), findsOneWidget);
      expect(find.textContaining('COLUMNS'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('email'), findsWidgets);
      expect(find.text('idx_cust_email'), findsOneWidget);
      expect(find.text('CREATE STATEMENT (DDL)'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('2. SqlEditorView runs queries and provides export tools', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MacosApp(
        home: Material(
          child: SqlEditorView(
            dbService: dbService,
            initialQuery: 'SELECT * FROM "1_customers" LIMIT 10;',
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SqlEditorView), findsOneWidget);

      final editorState = tester.state(find.byType(SqlEditorView)) as dynamic;
      await tester.runAsync(() async {
        await editorState.executeQuery();
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('10 rows'), findsOneWidget);
      expect(find.text('Copy CSV'), findsOneWidget);
      expect(find.text('Copy JSON'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('3. TableFilterBar captures column selection and debounced search', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? filteredCol;
      String filteredText = '';

      await tester.pumpWidget(MacosApp(
        home: MacosScaffold(
          children: [
            ContentArea(
              builder: (context, _) => TableFilterBar(
                columns: const ['id', 'name', 'email', 'balance'],
                currentFilter: '',
                totalRows: 25,
                loadedRows: 4,
                onFilterChanged: (filter) {
                  filteredCol = filter.column;
                  filteredText = filter.text;
                },
                onRefresh: () {},
                onAutoFit: () {},
              ),
            ),
          ],
        ),
      ));
      await tester.pump();

      expect(find.byType(TableFilterBar), findsOneWidget);
      expect(find.text('All Columns'), findsOneWidget);

      final filterInput = find.byType(MacosTextField);
      await tester.enterText(filterInput, 'Alice');
      await tester.pump(const Duration(milliseconds: 300));

      expect(filteredText, 'Alice');
      expect(filteredCol, isNull);

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('4. TableStatusFooter displays statistics and export trigger', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MacosApp(
        home: MacosScaffold(
          children: [
            ContentArea(
              builder: (context, _) => TableStatusFooter(
                totalRows: 1250,
                totalCols: 8,
                executionTimeMs: 4,
                tableName: '1_customers',
                onFetchAllRows: () async => dbService.fetchRows('1_customers', limit: 25),
              ),
            ),
          ],
        ),
      ));
      await tester.pump();

      expect(find.byType(TableStatusFooter), findsOneWidget);
      expect(find.text('1250 rows'), findsOneWidget);
      expect(find.text('8 cols'), findsOneWidget);
      expect(find.text('4ms'), findsOneWidget);
      expect(find.text('Export / Copy'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
    });
  });
}
