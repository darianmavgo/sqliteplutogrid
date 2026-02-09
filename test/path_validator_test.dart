import 'package:flutter_test/flutter_test.dart';
import 'package:sqliter/utils/path_validator.dart';
import 'package:sqliter/flight_service.dart';

void main() {
  group('PathValidator Tests', () {
    late FlightService flight;

    setUp(() {
      // Initialize with test server URL
      flight = FlightService(baseUrl: 'http://127.0.0.1:8095');
    });

    test('validatePathBackwards returns correct structure', () async {
      // This test requires Flight3 server to be running
      // It will test against a known non-existent path
      final missingPath = '/tmp/this/does/not/exist/test_${DateTime.now().millisecondsSinceEpoch}.db';
      final result = await PathValidator.validatePathBackwards(flight, missingPath);
      
      expect(result, isA<Map<String, dynamic>>());
      expect(result.containsKey('valid'), true);
      expect(result.containsKey('expanded_path'), true);
    });

    test('generateSmartErrorMessage returns non-empty string', () async {
      final missingPath = '/nonexistent_path_${DateTime.now().millisecondsSinceEpoch}/data.db';
      final error = await PathValidator.generateSmartErrorMessage(flight, missingPath);
      
      expect(error, isNotEmpty);
      expect(error, anyOf(contains('Path not found'), contains('Failed to validate path')));
    });
  });
}
