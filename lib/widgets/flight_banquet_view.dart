import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:macos_ui/macos_ui.dart';

class FlightBanquetView extends StatelessWidget {
  final List<TrinaRow> rows;
  final Function(TrinaRow) onRowDoubleTap;

  const FlightBanquetView({
    super.key,
    required this.rows,
    required this.onRowDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
        return const Center(child: Text("No accessible Banquet links found on server."));
    }

    return Column(
      children: [
        // Header / Instructions
        Container(
          padding: const EdgeInsets.all(16.0),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Banquet Links",
                style: MacosTheme.of(context).typography.title2,
              ),
              const SizedBox(height: 4),
              Text(
                "Common datasets shared on Flight3. Double-click an item to explore.",
                style: MacosTheme.of(context).typography.body.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        // Grid
        Expanded(
          child: Material(
            type: MaterialType.transparency,
            child: TrinaGrid(
              columns: [
                  TrinaColumn(field: 'path', title: 'Banquet Path (Click to Explore)', width: 500, frozen: TrinaColumnFrozen.start, type: TrinaColumnType.text()),
                  TrinaColumn(field: 'desc', title: 'Details', width: 300, type: TrinaColumnType.text()),
                  TrinaColumn(field: 'original_url', title: 'Source', width: 400, type: TrinaColumnType.text()),
              ],
              rows: rows,
              onRowDoubleTap: (event) => onRowDoubleTap(event.row),
              onLoaded: (TrinaGridOnLoadedEvent event) {
                event.stateManager.setShowColumnFilter(true);
              },
              configuration: const TrinaGridConfiguration(),
            ),
          ),
        ),
      ],
    );
  }
}
