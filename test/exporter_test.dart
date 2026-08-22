import 'package:flutter_test/flutter_test.dart';
import 'package:sqliter/utils/exporter.dart';

void main() {
  group('DataExporter Tests', () {
    final sampleRows = [
      {'id': 1, 'name': 'Alice, Smith', 'score': 100, 'notes': 'Note "1"'},
      {'id': 2, 'name': 'Bob', 'score': 200, 'notes': null},
    ];

    test('toCsv generates valid escaped CSV with header', () {
      final csv = DataExporter.toCsv(sampleRows);
      expect(csv, contains('id,name,score,notes'));
      expect(csv, contains('1,"Alice, Smith",100,"Note ""1"""'));
      expect(csv, contains('2,Bob,200,'));
    });

    test('toJson generates indented JSON', () {
      final jsonStr = DataExporter.toJson(sampleRows);
      expect(jsonStr, contains('"id": 1'));
      expect(jsonStr, contains('"name": "Alice, Smith"'));
    });

    test('toInsertSql generates valid SQL statements', () {
      final sql = DataExporter.toInsertSql('users', sampleRows);
      expect(sql, contains('INSERT INTO "users" ("id", "name", "score", "notes") VALUES (1, \'Alice, Smith\', 100, \'Note "1"\');'));
      expect(sql, contains('INSERT INTO "users" ("id", "name", "score", "notes") VALUES (2, \'Bob\', 200, NULL);'));
    });
  });
}
