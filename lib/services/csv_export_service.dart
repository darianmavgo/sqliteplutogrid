import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:trina_grid/trina_grid.dart';

class CsvExportService {
  /// Exports the given grid rows to a CSV file in the Downloads directory.
  /// Returns the path of the created file.
  static Future<String> exportRows({
    required List<TrinaRow> rows,
    required List<TrinaColumn> columns,
    required String tableName,
  }) async {
    final csvBuffer = StringBuffer();

    // Header row
    csvBuffer.writeln(columns.map((col) => _escapeCsvValue(col.title)).join(','));

    // Data rows
    for (final row in rows) {
      final values = columns.map((col) {
        // Access cell by column field/name
        // TrinaRow cells are map<String, TrinaCell> keyed by column name/field
        final cell = row.cells[col.field]; 
        return _escapeCsvValue(cell?.value?.toString() ?? '');
      }).toList();
      csvBuffer.writeln(values.join(','));
    }

    final csvString = csvBuffer.toString();

    // Get Downloads directory
    final downloadsPath = await _getDownloadsPath();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = '${tableName}_$timestamp.csv';
    final filePath = p.join(downloadsPath, fileName);

    // Write to file
    final file = File(filePath);
    await file.writeAsString(csvString);

    return filePath;
  }

  /// Escape CSV value (quote if contains comma, quote, or newline)
  static String _escapeCsvValue(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
  
  static Future<String> _getDownloadsPath() async {
    // Basic implementation for mac/linux
    // Could use path_provider but trying to keep dependencies minimal if not needed
    final home = Platform.environment['HOME'];
    if (home != null) {
      return p.join(home, 'Downloads');
    }
    return Directory.current.path; // Fallback
  }
}
