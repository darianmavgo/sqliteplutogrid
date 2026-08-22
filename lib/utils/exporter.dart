import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class DataExporter {
  /// Converts rows to CSV format
  static String toCsv(List<Map<String, Object?>> rows, {bool includeHeader = true}) {
    if (rows.isEmpty) return '';

    final headers = rows.first.keys.toList();
    final buffer = StringBuffer();

    if (includeHeader) {
      buffer.writeln(headers.map(_escapeCsvField).join(','));
    }

    for (final row in rows) {
      final values = headers.map((h) => _escapeCsvField(row[h]?.toString() ?? '')).join(',');
      buffer.writeln(values);
    }

    return buffer.toString();
  }

  /// Converts rows to pretty JSON string
  static String toJson(List<Map<String, Object?>> rows) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(rows);
  }

  /// Converts rows to SQL INSERT statements
  static String toInsertSql(String tableName, List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return '';

    final headers = rows.first.keys.toList();
    final quotedCols = headers.map((h) => '"$h"').join(', ');
    final buffer = StringBuffer();

    for (final row in rows) {
      final values = headers.map((h) {
        final val = row[h];
        if (val == null) return 'NULL';
        if (val is num) return val.toString();
        final escaped = val.toString().replaceAll("'", "''");
        return "'$escaped'";
      }).join(', ');

      buffer.writeln('INSERT INTO "$tableName" ($quotedCols) VALUES ($values);');
    }

    return buffer.toString();
  }

  static String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n') || field.contains('\r')) {
      final escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return field;
  }

  /// Save text to a chosen file destination
  static Future<String?> saveToFile({
    required String defaultFileName,
    required String content,
    required String dialogTitle,
  }) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: defaultFileName,
    );

    if (result != null) {
      final file = File(result);
      await file.writeAsString(content);
      return result;
    }
    return null;
  }

  /// Copy text to system clipboard
  static Future<void> copyToClipboard(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
  }
}
