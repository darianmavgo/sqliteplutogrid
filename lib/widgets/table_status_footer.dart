import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../utils/exporter.dart';

class TableStatusFooter extends StatefulWidget {
  final int totalRows;
  final int totalCols;
  final int? executionTimeMs;
  final String? tableName;
  final Future<List<Map<String, Object?>>> Function() onFetchAllRows;

  const TableStatusFooter({
    super.key,
    required this.totalRows,
    required this.totalCols,
    this.executionTimeMs,
    this.tableName,
    required this.onFetchAllRows,
  });

  @override
  State<TableStatusFooter> createState() => _TableStatusFooterState();
}

class _TableStatusFooterState extends State<TableStatusFooter> {
  bool _isExporting = false;
  String? _toastMessage;
  Timer? _toastTimer;

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _exportData(String format) async {
    final tableName = widget.tableName ?? 'export';
    setState(() => _isExporting = true);

    try {
      final rows = await widget.onFetchAllRows();
      if (rows.isEmpty) {
        _showToast('No data to export');
        setState(() => _isExporting = false);
        return;
      }

      String content = '';
      String ext = '';

      switch (format) {
        case 'csv':
          content = DataExporter.toCsv(rows);
          ext = 'csv';
          break;
        case 'json':
          content = DataExporter.toJson(rows);
          ext = 'json';
          break;
        case 'sql':
          content = DataExporter.toInsertSql(tableName, rows);
          ext = 'sql';
          break;
        case 'copy_csv':
          content = DataExporter.toCsv(rows);
          await DataExporter.copyToClipboard(content);
          _showToast('Copied CSV to clipboard!');
          setState(() => _isExporting = false);
          return;
        case 'copy_json':
          content = DataExporter.toJson(rows);
          await DataExporter.copyToClipboard(content);
          _showToast('Copied JSON to clipboard!');
          setState(() => _isExporting = false);
          return;
      }

      final savedPath = await DataExporter.saveToFile(
        defaultFileName: '$tableName.$ext',
        content: content,
        dialogTitle: 'Export $tableName as ${ext.toUpperCase()}',
      );

      if (savedPath != null) {
        _showToast('Exported to ${ext.toUpperCase()}!');
      }
    } catch (e) {
      _showToast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Row count
          _buildPill(
            icon: CupertinoIcons.list_bullet,
            text: '${widget.totalRows} rows',
            theme: theme,
          ),
          const SizedBox(width: 12),

          // Column count
          _buildPill(
            icon: CupertinoIcons.table,
            text: '${widget.totalCols} cols',
            theme: theme,
          ),

          if (widget.executionTimeMs != null) ...[
            const SizedBox(width: 12),
            _buildPill(
              icon: CupertinoIcons.timer,
              text: '${widget.executionTimeMs}ms',
              theme: theme,
            ),
          ],

          if (_toastMessage != null) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MacosColors.systemGreenColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _toastMessage!,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MacosColors.systemGreenColor),
              ),
            ),
          ],

          const Spacer(),

          // Export dropdown / menu
          if (_isExporting)
            const ProgressCircle(radius: 6)
          else
            MacosPopupButton<String>(
              value: 'export',
              popupColor: theme.canvasColor,
              onChanged: (String? format) {
                if (format != null && format != 'export') {
                  _exportData(format);
                }
              },
              items: const [
                MacosPopupMenuItem<String>(
                  value: 'export',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.share, size: 12),
                      SizedBox(width: 6),
                      Text('Export / Copy', style: TextStyle(fontSize: 11.5)),
                    ],
                  ),
                ),
                MacosPopupMenuItem<String>(
                  value: 'csv',
                  child: Text('Export to CSV file...', style: TextStyle(fontSize: 11.5)),
                ),
                MacosPopupMenuItem<String>(
                  value: 'json',
                  child: Text('Export to JSON file...', style: TextStyle(fontSize: 11.5)),
                ),
                MacosPopupMenuItem<String>(
                  value: 'sql',
                  child: Text('Export to INSERT SQL file...', style: TextStyle(fontSize: 11.5)),
                ),
                MacosPopupMenuItem<String>(
                  value: 'copy_csv',
                  child: Text('Copy all as CSV', style: TextStyle(fontSize: 11.5)),
                ),
                MacosPopupMenuItem<String>(
                  value: 'copy_json',
                  child: Text('Copy all as JSON', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPill({required IconData icon, required String text, required MacosThemeData theme}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.typography.caption2.color?.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: theme.typography.caption2.color?.withValues(alpha: 0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
