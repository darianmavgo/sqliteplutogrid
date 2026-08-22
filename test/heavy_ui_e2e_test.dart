import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqliter/db_service.dart';
import 'package:sqliter/flight_service.dart';
import 'package:sqliter/main.dart';
import 'package:sqliter/widgets/cell_inspector_dialog.dart';
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp',
    );
  });

  group('Full E2E UI Journey: Opening 7.5MB SQLite & Interacting with 10,000 Rows', () {
    const dbPath = '/Users/darianhickman/Documents/sqliteplutogrid/test_databases/heavy_5mb.sqlite';
    late DatabaseService dbService;

    setUp(() async {
      dbService = DatabaseService();
      await dbService.connect(dbPath);
    });

    tearDown(() async {
      await dbService.close();
    });

    testWidgets('1. Opens 7.5MB SQLite file in DBViewerPage, discovers 10,000 rows table, and renders status footer', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final realFlightService = FlightService();

      await tester.pumpWidget(MacosApp(
        home: DBViewerPage(
          flightService: realFlightService,
          dbService: dbService,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(DBViewerPage), findsOneWidget);

      final pageState = tester.state(find.byType(DBViewerPage)) as dynamic;
      await tester.runAsync(() async {
        await pageState.loadPathDirect(dbPath);
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('1_transactions'), findsWidgets);
      expect(find.byType(TableStatusFooter), findsOneWidget);
      expect(find.textContaining('10000 rows'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('2. Displays CellInspectorDialog with JSON formatting & copy actions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MacosApp(
        home: Material(
          child: CellInspectorDialog(
            columnName: 'metadata',
            cellValue: '{"block_height": 840001, "gas_used": 21000}',
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CellInspectorDialog), findsOneWidget);
      expect(find.text('Format JSON'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('3. SchemaInspectorView loads all 10 columns and indexes for 1_transactions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MacosApp(
        home: Material(
          child: SchemaInspectorView(
            dbService: dbService,
            tableName: '1_transactions',
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SchemaInspectorView), findsOneWidget);
      expect(find.text('tx_hash'), findsWidgets);
      expect(find.text('idx_tx_sender'), findsOneWidget);
      expect(find.text('idx_tx_status'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('4. SqlEditorView runs aggregate query on 7.5MB table', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MacosApp(
        home: Material(
          child: SqlEditorView(
            dbService: dbService,
            initialQuery: 'SELECT status, COUNT(*) as cnt FROM "1_transactions" GROUP BY status;',
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      final sqlState = tester.state(find.byType(SqlEditorView)) as dynamic;
      await tester.runAsync(() async {
        await sqlState.executeQuery();
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('rows'), findsWidgets);
      expect(find.text('Copy CSV'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
    });
  });
}
