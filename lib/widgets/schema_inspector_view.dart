import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import '../db_service.dart';

class SchemaInspectorView extends StatefulWidget {
  final DatabaseService dbService;
  final String tableName;

  const SchemaInspectorView({
    super.key,
    required this.dbService,
    required this.tableName,
  });

  @override
  State<SchemaInspectorView> createState() => _SchemaInspectorViewState();
}

class _SchemaInspectorViewState extends State<SchemaInspectorView> {
  bool _isLoading = true;
  String? _error;
  List<ColumnInfo> _columns = [];
  List<IndexInfo> _indexes = [];
  String? _ddl;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  @override
  void didUpdateWidget(SchemaInspectorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableName != widget.tableName) {
      _loadSchema();
    }
  }

  Future<void> _loadSchema() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cols = await widget.dbService.getTableSchema(widget.tableName);
      final idxs = await widget.dbService.getTableIndexes(widget.tableName);
      final ddl = await widget.dbService.getTableDDL(widget.tableName);

      if (mounted) {
        setState(() {
          _columns = cols;
          _indexes = idxs;
          _ddl = ddl;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _copyDDL() {
    if (_ddl != null) {
      Clipboard.setData(ClipboardData(text: _ddl!));
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    if (_isLoading) {
      return const Center(child: ProgressCircle());
    }

    if (_error != null) {
      return Center(
        child: Text('Error loading schema: $_error', style: theme.typography.body),
      );
    }

    return Container(
      color: theme.canvasColor,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Row(
            children: [
              const Icon(CupertinoIcons.square_stack_3d_up_fill, size: 20, color: MacosColors.systemOrangeColor),
              const SizedBox(width: 8),
              Text(
                'Schema: ${widget.tableName}',
                style: theme.typography.title2.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_ddl != null)
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: _copyDDL,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? CupertinoIcons.check_mark : CupertinoIcons.doc_on_clipboard,
                        size: 14,
                        color: _copied ? MacosColors.systemGreenColor : null,
                      ),
                      const SizedBox(width: 6),
                      Text(_copied ? 'Copied DDL!' : 'Copy DDL'),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),

          // Columns Section
          _buildSectionCard(
            title: 'COLUMNS (${_columns.length})',
            theme: theme,
            child: _buildColumnsTable(theme),
          ),

          const SizedBox(height: 18),

          // Indexes Section
          _buildSectionCard(
            title: 'INDEXES (${_indexes.length})',
            theme: theme,
            child: _buildIndexesTable(theme),
          ),

          const SizedBox(height: 18),

          // DDL Preview
          if (_ddl != null && _ddl!.isNotEmpty)
            _buildSectionCard(
              title: 'CREATE STATEMENT (DDL)',
              theme: theme,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? const Color(0xFF141414)
                      : const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  _ddl!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required MacosThemeData theme, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: theme.typography.caption2.color?.withValues(alpha: 0.7),
              ),
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildColumnsTable(MacosThemeData theme) {
    if (_columns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No columns found.'),
      );
    }

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(40),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FixedColumnWidth(80),
        4: FixedColumnWidth(60),
        5: FlexColumnWidth(2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
          children: const [
            _TableHeader('#'),
            _TableHeader('Column Name'),
            _TableHeader('Type'),
            _TableHeader('Not Null'),
            _TableHeader('PK'),
            _TableHeader('Default'),
          ],
        ),
        ..._columns.map((col) => TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3), width: 0.5)),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text('${col.cid}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (col.isPk) ...[
                    const Icon(CupertinoIcons.star_fill, size: 12, color: MacosColors.systemYellowColor),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    col.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: col.isPk ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: MacosColors.systemBlueColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  col.type.isNotEmpty ? col.type : 'ANY',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MacosColors.systemBlueColor),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                col.notNull ? 'YES' : 'NO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: col.notNull ? MacosColors.systemRedColor : Colors.grey,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: col.isPk
                  ? const Icon(CupertinoIcons.check_mark, size: 14, color: MacosColors.systemYellowColor)
                  : const Text('-', style: TextStyle(color: Colors.grey)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                col.dfltValue ?? 'NULL',
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: col.dfltValue != null ? 'monospace' : null,
                  color: col.dfltValue != null ? null : Colors.grey,
                ),
              ),
            ),
          ],
        )),
      ],
    );
  }

  Widget _buildIndexesTable(MacosThemeData theme) {
    if (_indexes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No indexes found on this table.'),
      );
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FixedColumnWidth(80),
        2: FlexColumnWidth(4),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
          children: const [
            _TableHeader('Index Name'),
            _TableHeader('Unique'),
            _TableHeader('Indexed Columns'),
          ],
        ),
        ..._indexes.map((idx) => TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3), width: 0.5)),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(idx.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                idx.unique ? 'YES' : 'NO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: idx.unique ? MacosColors.systemGreenColor : Colors.grey,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                idx.columns.join(', '),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        )),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: theme.typography.headline.color,
        ),
      ),
    );
  }
}
