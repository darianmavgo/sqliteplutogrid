import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

class TableFilterBar extends StatefulWidget {
  final List<String> columns;
  final String? selectedColumn;
  final String currentFilter;
  final int totalRows;
  final int loadedRows;
  final ValueChanged<({String? column, String text})> onFilterChanged;
  final VoidCallback onRefresh;
  final VoidCallback onAutoFit;

  const TableFilterBar({
    super.key,
    required this.columns,
    this.selectedColumn,
    required this.currentFilter,
    required this.totalRows,
    required this.loadedRows,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onAutoFit,
  });

  @override
  State<TableFilterBar> createState() => _TableFilterBarState();
}

class _TableFilterBarState extends State<TableFilterBar> {
  late final TextEditingController _filterController;
  Timer? _debounceTimer;
  String? _activeColumn;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController(text: widget.currentFilter);
    _activeColumn = widget.selectedColumn;
  }

  @override
  void didUpdateWidget(TableFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentFilter != widget.currentFilter && _filterController.text != widget.currentFilter) {
      _filterController.text = widget.currentFilter;
    }
    if (oldWidget.selectedColumn != widget.selectedColumn) {
      _activeColumn = widget.selectedColumn;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  void _onTextChange(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      widget.onFilterChanged((column: _activeColumn, text: value));
    });
  }

  void _clearFilter() {
    _filterController.clear();
    _debounceTimer?.cancel();
    widget.onFilterChanged((column: _activeColumn, text: ''));
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final hasActiveFilter = _filterController.text.isNotEmpty;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Filter Icon indicator
          Icon(
            CupertinoIcons.line_horizontal_3_decrease,
            size: 14,
            color: hasActiveFilter ? MacosColors.systemOrangeColor : theme.typography.caption1.color,
          ),
          const SizedBox(width: 6),

          // Column selector popup
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.dividerColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: MacosPopupButton<String>(
              value: _activeColumn ?? '__all__',
              popupColor: theme.canvasColor,
              onChanged: (String? val) {
                setState(() {
                  _activeColumn = (val == '__all__') ? null : val;
                });
                widget.onFilterChanged((column: _activeColumn, text: _filterController.text));
              },
              items: [
                const MacosPopupMenuItem<String>(
                  value: '__all__',
                  child: Text('All Columns', style: TextStyle(fontSize: 12)),
                ),
                ...widget.columns.map((col) => MacosPopupMenuItem<String>(
                  value: col,
                  child: Text(col, style: const TextStyle(fontSize: 12)),
                )),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Filter Text Field
          Expanded(
            child: SizedBox(
              height: 26,
              child: MacosTextField(
                controller: _filterController,
                placeholder: _activeColumn != null ? 'Filter in $_activeColumn...' : 'Filter table data...',
                style: const TextStyle(fontSize: 12),
                prefix: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(CupertinoIcons.search, size: 12),
                ),
                suffix: hasActiveFilter
                    ? GestureDetector(
                        onTap: _clearFilter,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(CupertinoIcons.clear_circled_solid, size: 14, color: Colors.grey),
                        ),
                      )
                    : null,
                onChanged: _onTextChange,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Auto-fit button
          Tooltip(
            message: 'Auto-fit all column widths',
            child: MacosIconButton(
              padding: const EdgeInsets.all(4),
              icon: const Icon(CupertinoIcons.arrow_left_right, size: 14),
              onPressed: widget.onAutoFit,
            ),
          ),

          // Refresh button
          Tooltip(
            message: 'Refresh data',
            child: MacosIconButton(
              padding: const EdgeInsets.all(4),
              icon: const Icon(CupertinoIcons.arrow_clockwise, size: 14),
              onPressed: widget.onRefresh,
            ),
          ),
        ],
      ),
    );
  }
}
