import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import '../db_service.dart';
import '../theme/sqliter_theme.dart';

class SqlEditorView extends StatefulWidget {
  final DatabaseService dbService;
  final String? initialQuery;

  const SqlEditorView({
    super.key,
    required this.dbService,
    this.initialQuery,
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

  List<TrinaColumn> _resultColumns = [];
  List<TrinaRow> _resultRows = [];

  @override
  void initState() {
    super.initState();
    _sqlController = TextEditingController(
      text: widget.initialQuery ?? 'SELECT * FROM sqlite_master LIMIT 50;',
    );
  }

  @override
  void dispose() {
    _sqlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

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
        _rowCount = null;
      });
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

              // Code input box
              Container(
                height: 140,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181818) : Colors.white,
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor, width: 1.0),
                  ),
                ),
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
                    hintText: 'Enter SQL query (e.g. SELECT * FROM table LIMIT 100)...',
                    hintStyle: TextStyle(fontSize: 13, fontFamily: 'monospace', color: Colors.grey),
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

              // Results grid
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
                    : Material(
                        color: Colors.transparent,
                        child: TrinaGrid(
                          columns: _resultColumns,
                          rows: _resultRows,
                          configuration: SqliterTheme.getGridConfig(context),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunQueryIntent extends Intent {
  const _RunQueryIntent();
}
