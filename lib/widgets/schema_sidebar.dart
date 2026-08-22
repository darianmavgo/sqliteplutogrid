import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import '../db_service.dart';
import 'package:path/path.dart' as p;

class SchemaSidebar extends StatefulWidget {
  final List<TableSummary> tables;
  final String? selectedTable;
  final String? dbPath;
  final bool isLoading;
  final ValueChanged<String> onSelectTable;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenNewDb;

  const SchemaSidebar({
    super.key,
    required this.tables,
    required this.selectedTable,
    required this.dbPath,
    required this.isLoading,
    required this.onSelectTable,
    required this.onRefresh,
    this.onOpenNewDb,
  });

  @override
  State<SchemaSidebar> createState() => _SchemaSidebarState();
}

class _SchemaSidebarState extends State<SchemaSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _filterQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dbName = widget.dbPath != null ? p.basename(widget.dbPath!) : 'No Database';

    final filteredTables = widget.tables.where((t) {
      if (_filterQuery.isEmpty) return true;
      return t.name.toLowerCase().contains(_filterQuery);
    }).toList();

    final tablesOnly = filteredTables.where((t) => t.type == 'table').toList();
    final viewsOnly = filteredTables.where((t) => t.type == 'view').toList();

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // DB Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.circle_grid_hex_fill, size: 16, color: MacosColors.systemOrangeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dbName,
                        style: theme.typography.headline.copyWith(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.tables.length} tables & views',
                        style: theme.typography.caption2.copyWith(color: theme.typography.caption2.color?.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                MacosIconButton(
                  icon: const Icon(CupertinoIcons.arrow_clockwise, size: 14),
                  padding: const EdgeInsets.all(4),
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: MacosSearchField(
              controller: _searchController,
              placeholder: 'Filter tables...',
            ),
          ),

          // Table list
          Expanded(
            child: widget.isLoading && widget.tables.isEmpty
                ? const Center(child: ProgressCircle())
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    children: [
                      if (tablesOnly.isNotEmpty) ...[
                        _buildSectionHeader('TABLES (${tablesOnly.length})', theme),
                        ...tablesOnly.map((t) => _buildTableItem(t, theme)),
                      ],
                      if (viewsOnly.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildSectionHeader('VIEWS (${viewsOnly.length})', theme),
                        ...viewsOnly.map((t) => _buildTableItem(t, theme)),
                      ],
                      if (filteredTables.isEmpty && widget.tables.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'No matching tables',
                              style: theme.typography.caption1.copyWith(color: Colors.grey),
                            ),
                          ),
                        ),
                      if (widget.tables.isEmpty && !widget.isLoading)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'No tables in database',
                              style: theme.typography.caption1.copyWith(color: Colors.grey),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, MacosThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: theme.typography.caption2.color?.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildTableItem(TableSummary table, MacosThemeData theme) {
    final isSelected = table.name == widget.selectedTable;
    final isView = table.type == 'view';

    return GestureDetector(
      onTap: () => widget.onSelectTable(table.name),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: isSelected
              ? Border.all(color: theme.primaryColor.withValues(alpha: 0.4), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              isView ? CupertinoIcons.eye : CupertinoIcons.table,
              size: 14,
              color: isSelected
                  ? MacosColors.systemOrangeColor
                  : (isView ? MacosColors.systemIndigoColor : MacosColors.systemBlueColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                table.name,
                style: theme.typography.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? theme.typography.headline.color : theme.typography.body.color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (table.rowCount != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${table.rowCount}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: theme.typography.caption2.color?.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
