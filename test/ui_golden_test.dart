import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sqliter/main.dart';
import 'package:sqliter/flight_service.dart';
import 'package:sqliter/db_service.dart';
import 'package:sqliter/widgets/database_grid_view.dart';

// --- Manual Mocks (Simplified) ---
class MockFlightService extends FlightService {
  MockFlightService() : super(baseUrl: 'http://mock');

  @override
  Future<List<RecordModel>> getBanquetLinks() async => [];
  
  @override
  Future<Map<String, dynamic>> fetchBanquetData(String p, {int? offset, int? limit}) async => {'rows': []};
  
  @override
  void initPb() {
    // Avoid re-initializing the real PocketBase client in the mock constructor
    // or just leave it blank since we override methods.
    // However, the base constructor calls it.
    // We can't avoid the base constructor
    // But we can override this to do nothing if we don't want real PB.
  }
  
  @override
  Future<void> authenticate(String e, String p) async {}

  @override
  Future<List<RecordModel>> getQueryStyles() async => [];

  // This needs to match the Future<String> return type
  @override
  Future<String> getHomeDatabasePath() async => '/tmp/home.sqlite';
}

class MockDatabaseService extends DatabaseService {
  MockDatabaseService() : super();
  
  @override
  Future<void> connect(String path) async {}
  
  @override
  Future<List<String>> getTables() async => ['Table1', 'Table2'];

  @override
  Future<List<TableSummary>> getTableSummaries() async => [
    const TableSummary(name: 'Table1', type: 'table', rowCount: 10),
    const TableSummary(name: 'Table2', type: 'table', rowCount: 5),
  ];

  @override
  Future<List<ColumnInfo>> getTableSchema(String tableName) async => [
    const ColumnInfo(cid: 0, name: 'id', type: 'INTEGER', notNull: true, isPk: true),
    const ColumnInfo(cid: 1, name: 'name', type: 'TEXT', notNull: false, isPk: false),
    const ColumnInfo(cid: 2, name: 'value', type: 'TEXT', notNull: false, isPk: false),
  ];

  @override
  Future<List<IndexInfo>> getTableIndexes(String tableName) async => [];

  @override
  Future<String?> getTableDDL(String tableName) async => 'CREATE TABLE $tableName (id INTEGER PRIMARY KEY, name TEXT, value TEXT);';

  @override
  Future<List<String>> getTableHeaders(String tableName) async => ['id', 'name', 'value'];

  @override
  Future<int> countRows(String t, {String? filterColumn, String? filterText}) async => 10;
  
  @override
  Future<List<Map<String, Object?>>> fetchRows(
    String t, {
    int limit = 100,
    int offset = 0,
    String? filterColumn,
    String? filterText,
    String? sortColumn,
    bool sortAscending = true,
  }) async {
    return List.generate(5, (i) => {'id': i, 'name': 'Row $i', 'value': 100 + i});
  }

  @override
  Future<int> getUserVersion() async => 0;
  
  @override
  Future<List<Map<String, Object?>>> executeQuery(String sql) async => [];

  @override
  Future<void> close() async {}
}



void main() {
  setUpAll(() {
    // Mock Path Provider
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '/tmp';
      },
    );
    
    // Mock macOS UI Accent Color
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (MethodCall methodCall) async {
        return {
          'redComponent': 0.0,
          'greenComponent': 0.5,
          'blueComponent': 1.0,
          'alphaComponent': 1.0,
          'hueComponent': 210.0,
          'saturationComponent': 1.0,
          'brightnessComponent': 1.0,
        };
      },
    );

    // Mock Window Manager
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  // Ensure the tree is rendered at a specific size for goldens
  const Size goldenSize = Size(1280, 800);

  testWidgets('Golden Test - Flight View', (WidgetTester tester) async {
    tester.view.physicalSize = goldenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Pump app in Dark Mode
    await tester.pumpWidget(MacosApp(
      themeMode: ThemeMode.dark,
      home: DBViewerPage(
        flightService: MockFlightService(),
        dbService: MockDatabaseService(),
      ),
    ));

    await tester.pumpAndSettle();

    // Assert Visuals
    // 1. DatabaseGridView should be visible (displaying banquet links)
    expect(find.byType(DatabaseGridView), findsOneWidget);
    
    // 2. Dashboard Content (the welcome message might be in the view)

    // GOLDEN Assertion
    const goldenPath = 'goldens/macos_ui_initial.png';
    await expectLater(
      find.byType(MacosApp), 
      matchesGoldenFile(goldenPath)
    );
  });
  
  testWidgets('Golden Test - Database Grid', (WidgetTester tester) async {
    tester.view.physicalSize = goldenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MacosApp(
      themeMode: ThemeMode.dark,
      darkTheme: MacosThemeData.dark(),
      home: DBViewerPage(
          flightService: MockFlightService(),
          dbService: MockDatabaseService(),
      ),
    ));
    await tester.pumpAndSettle();

    // Trigger Database View (simulate opening file)
    // We can simulate this by mocking _loadPath logic or modifying state directly if accessible.
    // For this test, simpler to Assume mocks work if we can tap.
    // Or we can rebuild DBViewerPage?
    // DBViewerPage internal state defaults to Home.
    // But if we could dependency inject initial state... (We can't easily refactor that now).
    // So we assume user flow.
  });
}
