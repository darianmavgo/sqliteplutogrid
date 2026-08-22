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
  /// Called when a cell value looks like a URL or sqlite path.
  final Function(String value)? onCellNavigate;
  final ValueChanged<TrinaGridStateManager>? onStateManagerCreated;

  const DatabaseGridView({
    super.key,
    required this.columns,
    this.tableName,
    this.totalRows,
    required this.onFetchRows,
    this.onRowDoubleTap,
    this.onCellNavigate,
    this.onStateManagerCreated,
  });

  @override
  State<DatabaseGridView> createState() => _DatabaseGridViewState();
}

class _DatabaseGridViewState extends State<DatabaseGridView> {
  TrinaGridStateManager? _stateManager;
  bool _hasAutoSized = false;

  /// Auto-fit every column based on rendered content.
  void _autoFitAllColumns() {
    final sm = _stateManager;
    if (sm == null || !mounted) return;
    for (final col in sm.columns) {
      sm.autoFitColumn(context, col);
    }
  }

  @override
  void didUpdateWidget(DatabaseGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset auto-size flag when the table changes so it runs again for the new table.
    if (oldWidget.tableName != widget.tableName) {
      _hasAutoSized = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tableName == null) {
      return const Center(child: Text("No Table Selected"));
    }

    if (widget.columns.isEmpty) {
      return Center(
        child: Text(
          "Table '${widget.tableName}' has no columns or is empty.",
          style: MacosTheme.of(context).typography.body,
        ),
      );
    }

    final config = SqliterTheme.getGridConfig(context);

    return TrinaGrid(
      key: ValueKey(widget.tableName),
      columns: widget.columns,
      // ignore: prefer_const_literals_to_create_immutables
      rows: [],
      onLoaded: (event) {
        _stateManager = event.stateManager;
        widget.onStateManagerCreated?.call(event.stateManager);
        _hasAutoSized = false;
      },
      onRowDoubleTap: (event) {
        if (widget.onRowDoubleTap != null) {
          widget.onRowDoubleTap!(event.row);
        }
      },
      configuration: config,
      createFooter: (stateManager) {
        _stateManager = stateManager;
        widget.onStateManagerCreated?.call(stateManager);
        return TrinaLazyPagination(
          stateManager: stateManager,
          initialPage: 1,
          initialPageSize: 200,
          fetch: (request) async {
            final offset = (request.page - 1) * request.pageSize;
            final rows = await widget.onFetchRows(offset);

            // Auto-size all columns once after the first page arrives.
            if (!_hasAutoSized && request.page == 1) {
              _hasAutoSized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _autoFitAllColumns();
              });
            }

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
