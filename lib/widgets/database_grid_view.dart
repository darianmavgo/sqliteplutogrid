import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';
import '../theme/sqliter_theme.dart';

class DatabaseGridView extends StatefulWidget {
  final List<TrinaColumn> columns;
  final String? tableName;
  final int? totalRows;
  final Future<List<TrinaRow>> Function(int offset) onFetchRows;
  final Function(TrinaRow)? onRowDoubleTap;

  const DatabaseGridView({
    super.key,
    required this.columns,
    this.tableName,
    this.totalRows,
    required this.onFetchRows,
    this.onRowDoubleTap,
  });

  @override
  State<DatabaseGridView> createState() => _DatabaseGridViewState();
}

class _DatabaseGridViewState extends State<DatabaseGridView> {

  @override
  Widget build(BuildContext context) {
    if (widget.columns.isEmpty) {
       return const Center(child: Text("Select a table to view data"));
    }

    return Column(
      children: [
        // Grid
        // Grid
        Expanded(
          child: Material(
            type: MaterialType.transparency, // Keep it transparent as we handle background
            child: TrinaGrid(
              columns: widget.columns,
              // ignore: prefer_const_literals_to_create_immutables
              rows: [],
              onLoaded: (TrinaGridOnLoadedEvent event) {
                // event.stateManager.setShowColumnFilter(true);
              },
              onRowDoubleTap: widget.onRowDoubleTap != null ? (event) => widget.onRowDoubleTap!(event.row) : null,
              createFooter: (stateManager) {
                return TrinaInfinityScrollRows(
                  fetch: (request) async {
                     final offset = stateManager.refRows.length;
                     final newRows = await widget.onFetchRows(offset);
                     
                     // Update UI to show new loaded count
                     if (mounted && newRows.isNotEmpty) {
                       setState(() {}); // Refresh to update stats header if we were showing loaded count
                     }
                     
                     return TrinaInfinityScrollRowsResponse(
                       isLast: newRows.isEmpty,
                       rows: newRows,
                     );
                  },
                  stateManager: stateManager,
                );
              },
              configuration: SqliterTheme.getGridConfig(context),
            ),
          ),
        ),
      ],
    );
  }
}
