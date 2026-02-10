import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqliter/flight_service.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Home SQLite Generation and Population', () async {
    // 1. Setup Persistent Test Output Directory
    final projectRoot = Directory.current.path;
    final outputDir = Directory(p.join(projectRoot, 'test_output', 'home_persistence'));
    if (outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true); // "Soft delete" by clearing previous run, but keeping this run's artifacts
    }
    outputDir.createSync(recursive: true);
    
    // addTearDown(() => outputDir.deleteSync(recursive: true)); // Disabled as requested
    
    print('Testing with output dir: ${outputDir.path}');

    // 2. Initialize Service with override
    // Note: We need to ensure we run this test in a way that respects Platform.isMacOS 
    // "flutter test" runs on the host machine, so it should be fine on macOS.
    final service = FlightService(storageDirOverride: outputDir);

    // 3. Trigger Home Creation
    final homePath = await service.getHomeDatabasePath();
    
    expect(homePath, equals(p.join(outputDir.path, 'home.sqlite')));
    expect(File(homePath).existsSync(), isTrue, reason: 'home.sqlite file should be created');

    // 4. Verify Schema and Data
    final db = await databaseFactory.openDatabase(homePath);
    try {
       // Check Tables
       final tables = await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']);
       final tableNames = tables.map((row) => row['name'] as String).toList();
       
       expect(tableNames, contains('0_quick_links'));
       expect(tableNames, contains('1_recent_files'));
       expect(tableNames, contains('2_banquet_links'));
       expect(tableNames, contains('3_query_styles'));
       expect(tableNames, contains('9_system_messages'));

       // Check Quick Links Data
       final quickLinks = await db.query('"0_quick_links"');
       expect(quickLinks.length, equals(3));
       expect(quickLinks[0]['label'], contains('Open Local File'));
       expect(quickLinks[1]['label'], contains('Connect to Remote'));
       expect(quickLinks[2]['label'], contains('New Query'));

    } finally {
      await db.close();
    }
  });
}
