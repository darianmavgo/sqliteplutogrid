import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import '../db_service.dart';
import '../theme/sqliter_theme.dart';
import '../utils/exporter.dart';

class SqlEditorView extends StatefulWidget {
  final DatabaseService dbService;
  final String? initialQuery;
  final String? currentTableName;

  const SqlEditorView({
    super.key,
    required this.dbService,
    this.initialQuery,
    this.currentTableName,
  });

  @override
  State<SqlEditorView> createState() => _SqlEditorViewState();
}

class _SqlEditorViewState extends State<SqlEditorView> {
  late final TextEditingController _sqlController;
  final FocusNode _focusNode = FocusNode();

  bool _isExecuting = false;
  String? _errorMessage;
  int? _executionTimeMs;
  int? _rowCount;
  String? _toastMessage;
  Timer? _toastTimer;

  List<TrinaColumn> _resultColumns = [];
  List<TrinaRow> _resultRows = [];
  List<Map<String, Object?>> _rawResults = [];

  @override
  void initState() {
    super.initState();
    _sqlController = TextEditingController(
      text: widget.initialQuery ?? 'SELECT * FROM sqlite_master LIMIT 50;',
    );
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _sqlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _applySnippet(String template) {
    final table = widget.currentTableName ?? 'table_name';
    final sql = template.replaceAll('{table}', DatabaseService.quote(table));
    _sqlController.text = sql;
    _sqlController.selection = TextSelection.fromPosition(TextPosition(offset: sql.length));
  }

  Future<void> executeQuery() => _executeQuery();

  Future<void> _executeQuery() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final results = await widget.dbService.executeQuery(sql);
      stopwatch.stop();
      _rawResults = results;

      if (results.isEmpty) {
        setState(() {
          _resultColumns = [
            TrinaColumn(
              field: 'status',
              title: 'Status',
              width: 300,
              type: TrinaColumnType.text(),
              enableFilterMenuItem: false,
              enableContextMenu: false,
            ),
          ];
          _resultRows = [
            TrinaRow(cells: {
              'status': TrinaCell(value: 'Query executed successfully. 0 rows returned.'),
            }),
          ];
          _rowCount = 0;
          _executionTimeMs = stopwatch.elapsedMilliseconds;
          _isExecuting = false;
        });
        return;
      }

      // Build columns from first row
      final firstRow = results.first;
      final columns = firstRow.keys.map((key) {
        return TrinaColumn(
          field: key,
          title: key,
          width: 140,
          type: TrinaColumnType.text(),
          enableSorting: true,
          enableFilterMenuItem: false,
          enableContextMenu: false,
        );
      }).toList();

      // Build rows
      final rows = results.map((r) {
        final cells = <String, TrinaCell>{};
        r.forEach((k, v) {
          cells[k] = TrinaCell(value: v?.toString() ?? 'NULL');
        });
        return TrinaRow(cells: cells);
      }).toList();

      setState(() {
        _resultColumns = columns;
        _resultRows = rows;
        _rawResults = results;
        _rowCount = results.length;
        _executionTimeMs = stopwatch.elapsedMilliseconds;
        _isExecuting = false;
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _executionTimeMs = stopwatch.elapsedMilliseconds;
        _isExecuting = false;
        _resultColumns = [];
        _resultRows = [];
        _rawResults = [];
        _rowCount = null;
      });
    }
  }

  Future<void> _exportResults(String format) async {
    if (_rawResults.isEmpty) return;

    if (format == 'copy_json') {
      final jsonStr = DataExporter.toJson(_rawResults);
      await DataExporter.copyToClipboard(jsonStr);
      _showToast('Copied JSON to clipboard!');
      return;
    } else if (format == 'copy_csv') {
      final csvStr = DataExporter.toCsv(_rawResults);
      await DataExporter.copyToClipboard(csvStr);
      _showToast('Copied CSV to clipboard!');
      return;
    }

    String content = '';
    String ext = '';
    if (format == 'csv') {
      content = DataExporter.toCsv(_rawResults);
      ext = 'csv';
    } else if (format == 'json') {
      content = DataExporter.toJson(_rawResults);
      ext = 'json';
    }

    final path = await DataExporter.saveToFile(
      defaultFileName: 'query_results.$ext',
      content: content,
      dialogTitle: 'Export Query Results',
    );

    if (path != null) {
      _showToast('Exported to ${ext.toUpperCase()}!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter, meta: true): _RunQueryIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _RunQueryIntent: CallbackAction<_RunQueryIntent>(
            onInvoke: (_) => _executeQuery(),
          ),
        },
        child: Container(
          color: theme.canvasColor,
          child: Column(
            children: [
              // Editor Toolbar
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.chevron_left_slash_chevron_right, size: 14, color: MacosColors.systemOrangeColor),
                    const SizedBox(width: 8),
                    Text(
                      'SQL Query Editor',
                      style: theme.typography.headline.copyWith(fontSize: 12.5),
                    ),
                    const Spacer(),
                    if (_rowCount != null) ...[
                      Text(
                        '$_rowCount rows',
                        style: theme.typography.caption1.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (_executionTimeMs != null) ...[
                      Text(
                        '${_executionTimeMs}ms',
                        style: theme.typography.caption1.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_toastMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: MacosColors.systemGreenColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _toastMessage!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MacosColors.systemGreenColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    PushButton(
                      controlSize: ControlSize.regular,
                      onPressed: _isExecuting ? null : _executeQuery,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isExecuting) ...[
                            const ProgressCircle(radius: 6),
                            const SizedBox(width: 6),
                          ] else ...[
                            const Icon(CupertinoIcons.play_arrow_solid, size: 12),
                            const SizedBox(width: 4),
                          ],
                          const Text('Run (⌘⏎)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Query Templates Bar
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B1B1B) : const Color(0xFFF7F7F7),
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5), width: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text('Templates:', style: theme.typography.caption2.copyWith(fontSize: 10.5, color: Colors.grey)),
                      const SizedBox(width: 6),
                      _buildSnippetChip('SELECT *', 'SELECT * FROM {table} LIMIT 100;', theme),
                      _buildSnippetChip('COUNT(*)', 'SELECT COUNT(*) as count FROM {table};', theme),
                      _buildSnippetChip('PRAGMA info', 'PRAGMA table_info({table});', theme),
                      _buildSnippetChip('TABLES', "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view');", theme),
                      _buildSnippetChip('VACUUM', 'VACUUM;', theme),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _sqlController.clear(),
                        child: Text('Clear', style: TextStyle(fontSize: 10.5, color: MacosColors.systemRedColor.withValues(alpha: 0.8))),
                      ),
                    ],
                  ),
                ),
              ),

              // Code input box
              Container(
                height: 125,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141414) : Colors.white,
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor, width: 1.0),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _sqlController,
                    focusNode: _focusNode,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Enter SQL query (e.g. SELECT * FROM table LIMIT 50;)...',
                      hintStyle: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),

              // Error display
              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: MacosColors.systemRedColor.withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_circle_fill, size: 16, color: MacosColors.systemRedColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          _errorMessage!,
                          style: const TextStyle(color: MacosColors.systemRedColor, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Results grid & export header
              Expanded(
                child: _resultColumns.isEmpty
                    ? Center(
                        child: Text(
                          _isExecuting
                              ? 'Executing query...'
                              : 'Run a query with ⌘⏎ to see results here',
                          style: theme.typography.body.copyWith(color: Colors.grey),
                        ),
                      )
                    : Column(
                        children: [
                          // Export action bar for results
                          Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFEEEEEE),
                              border: Border(
                                bottom: BorderSide(color: theme.dividerColor, width: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text('${_resultRows.length} query rows', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => _exportResults('copy_csv'),
                                  child: const Text('Copy CSV', style: TextStyle(fontSize: 11, color: MacosColors.systemBlueColor)),
                                ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: () => _exportResults('copy_json'),
                                  child: const Text('Copy JSON', style: TextStyle(fontSize: 11, color: MacosColors.systemBlueColor)),
                                ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: () => _exportResults('csv'),
                                  child: const Text('Save CSV...', style: TextStyle(fontSize: 11, color: MacosColors.systemBlueColor)),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: TrinaGrid(
                                key: ValueKey('sql_grid_${_resultColumns.length}_${_rowCount}_$_executionTimeMs'),
                                columns: _resultColumns,
                                // ignore: prefer_const_literals_to_create_immutables
                                rows: List<TrinaRow>.from(_resultRows),
                                configuration: SqliterTheme.getGridConfig(context),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSnippetChip(String label, String template, MacosThemeData theme) {
    return GestureDetector(
      onTap: () => _applySnippet(template),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.dividerColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontFamily: 'monospace',
            color: theme.typography.body.color?.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

class _RunQueryIntent extends Intent {
  const _RunQueryIntent();
}
