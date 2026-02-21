import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:macos_ui/macos_ui.dart';
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
    if (widget.tableName == null) {
      return const Center(child: Text("No Table Selected"));
    }

    final config = SqliterTheme.getGridConfig(context);

    // Use a key based on tableName to force rebuild when table changes
    // This ensures fetching starts fro page 1 for new table
    return TrinaGrid(
      key: ValueKey(widget.tableName),
      columns: widget.columns,
      rows: [], // Initial empty rows, TrinaLazyPagination will fetch
      onRowDoubleTap: (event) {
        if (widget.onRowDoubleTap != null) {
          widget.onRowDoubleTap!(event.row);
        }
      },
      configuration: config,
      createFooter: (stateManager) {
        return TrinaLazyPagination(
          stateManager: stateManager,
          initialPage: 1,
          initialPageSize: 200, // Matches the limit in main.dart _fetchDatabaseRows
          fetch: (request) async {
             final offset = (request.page - 1) * request.pageSize;
             final rows = await widget.onFetchRows(offset);
             
             final totalRecords = widget.totalRows ?? 0;
             final totalPage = (totalRecords / request.pageSize).ceil();
             
             return TrinaLazyPaginationResponse(
               totalPage: totalPage > 0 ? totalPage : 1,
               rows: rows,
               totalRecords: totalRecords,
             );
          },
          showTotalRows: true,
          showPageSizeSelector: false,
        );
      },
    );
  }
}
