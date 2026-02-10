import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sqliter/main.dart';
import 'package:sqliter/flight_service.dart';
import 'package:sqliter/db_service.dart';

// --- Manual Mocks ---
class MockFlightService extends FlightService {
  MockFlightService() : super(baseUrl: 'http://mock');

  @override
  Future<List<RecordModel>> getBanquetLinks() async {
     return [
       RecordModel({'id': '1', 'original_url': 'banquet://test', 'description': 'Test Link'}),
     ];
  }

  @override
  Future<Map<String, dynamic>> fetchBanquetData(String banquetPath, {int? offset, int? limit}) async {
    return {
      'rows': [],
      'columns': ['col1', 'col2'],
      'total': 0,
    };
  }
  
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    return {'rows': []};
  }

  @override
  void initPb() {
    pb = PocketBase(baseUrl);
  }
  
  @override
  void updateUrl(String url) {}
  
  @override
  Future<void> authenticate(String email, String password) async {}

  @override
  Future<List<RecordModel>> getQueryStyles() async => [];

  @override
  Future<String> getHomeDatabasePath() async => '/tmp/home.sqlite';
}

class MockDatabaseService implements DatabaseService {
  @override
  Future<void> close() async {}

  @override
  Future<void> connect(String path) async {}

  @override
  Future<int> countRows(String tableName) async => 0;

  @override
  Future<List<Map<String, Object?>>> fetchRows(String tableName, {int limit = 100, int offset = 0}) async => [];

  @override
  Future<List<String>> getTableHeaders(String tableName) async => ['id', 'name'];

  @override
  Future<List<String>> getTables() async => ['Banquet Links', 'posts'];

  @override
  Stream<List<Map<String, Object?>>> streamRows(String tableName, {int chunkSize = 100}) async* {
    yield [];
  }

  @override
  Future<int> getUserVersion() async => 0;

  @override
  Future<List<Map<String, Object?>>> fetchPower2Samples(String tableName) async => [];

  @override
  Future<List<Map<String, Object?>>> executeQuery(String sql) async => [];
}



void main() {
  setUpAll(() {
    // Mock shared preferences if needed
  });

  group('UI Launch Tests', () {
    testWidgets('App Launches with correct services', (WidgetTester tester) async {
      await tester.pumpWidget(MacosApp(
        home: DBViewerPage(
          flightService: MockFlightService(),
          dbService: MockDatabaseService(),
        ),
      ));
      
      await tester.pumpAndSettle();
      
      // Verify basic structure
      expect(find.byType(MacosScaffold), findsOneWidget);
    });
  });
  
  group('Client Side Actions', () {
     testWidgets('Toolbar navigation input update', (WidgetTester tester) async {
      await tester.pumpWidget(MacosApp(
        home: DBViewerPage(
            flightService: MockFlightService(),
            dbService: MockDatabaseService(),
        ),
      ));
      
      await tester.pumpAndSettle();
      
      expect(find.text('🍊'), findsOneWidget);
    });

    testWidgets('Home Button loads Banquet Links', (WidgetTester tester) async {
       tester.view.physicalSize = const Size(1200, 800);
       tester.view.devicePixelRatio = 1.0;
       addTearDown(tester.view.resetPhysicalSize);

       await tester.pumpWidget(MacosApp(
        home: DBViewerPage(
            flightService: MockFlightService(),
            dbService: MockDatabaseService(),
        ),
      ));
      
      await tester.pumpAndSettle();
      
      // Find Flame icon
      final homeIcon = find.text('🍊');
      expect(homeIcon, findsOneWidget);
      
      await tester.tap(homeIcon);
      await tester.pumpAndSettle();
      
      // Verify "Banquet Links" header appears (as table name in grid)
      // "Banquet Links" is the table name, but DatabaseGridView doesn't display it explicitly as text
      // Instead we verify that the grid is loaded by checking for column headers
      expect(find.text('id'), findsOneWidget);
    });
  });
}
