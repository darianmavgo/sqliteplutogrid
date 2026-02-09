import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../models/view_mode.dart';
import 'breadcrumb_path_field.dart';
import '../flight_service.dart';

ToolBar buildAppToolbar({
  required BuildContext context,
  required ViewMode currentMode,
  required bool isFlightConnected,
  required bool isLoading,
  required TextEditingController pathController,
  required VoidCallback onHomeTap,
  required Function(String) onNavigate,
  required VoidCallback onConnectFlight,
  required VoidCallback onPower2,
  required VoidCallback onExportCsv,
  required VoidCallback onJumpToRow,
  required List<String> tables,
  required String? selectedTable,
  required Function(String) onTableChanged,
  required int? totalRows,
  required String? converterEmoji,
  required FlightService flightService,
}) {
  return ToolBar(
    titleWidth: 2000, // Make title area take up most of the space
    title: Row(
      children: [
        // Flame emoji as home button
        GestureDetector(
          onTap: onHomeTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              '🔥',
              style: TextStyle(
                fontSize: 24,
                // Add subtle glow when on home
                shadows: currentMode == ViewMode.home ? [
                  Shadow(
                    color: MacosColors.systemOrangeColor.withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ] : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Flight button
        MacosIconButton(
          icon: Icon(
            CupertinoIcons.cloud,
            color: isFlightConnected ? MacosColors.systemGreenColor : Colors.white.withOpacity(0.5),
            size: 20,
          ),
          onPressed: onConnectFlight,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: BreadcrumbPathField(
            controller: pathController,
            placeholder: currentMode == ViewMode.flight ? 'Banquet URL (e.g. data.db;table)' : 'Path',
            onNavigate: onNavigate,
            flightService: flightService, // Pass service for API calls
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentMode == ViewMode.database && tables.isNotEmpty)
                  MacosPopupButton<String>(
                    value: selectedTable,
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        onTableChanged(newValue);
                      }
                    },
                    items: tables.map<MacosPopupMenuItem<String>>((String value) {
                      return MacosPopupMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                if (totalRows != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text("${converterEmoji ?? '📊'} Rows: $totalRows", style: MacosTheme.of(context).typography.caption1),
                  ),
                const SizedBox(width: 8),
                if (currentMode == ViewMode.database) ...[
                   MacosIconButton(
                      icon: const Icon(CupertinoIcons.arrow_up_down_square), // Jump icon
                       onPressed: onJumpToRow,
                   ),
                   MacosIconButton(
                      icon: const Icon(CupertinoIcons.bolt, size: 16),
                      onPressed: onPower2,
                   ),
                   const SizedBox(width: 8),
                   MacosIconButton(
                      icon: const Icon(CupertinoIcons.square_arrow_up, size: 16),
                      onPressed: onExportCsv,
                   ),
                ]
              ],
            ),
          ),
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: ProgressCircle(radius: 10),
          ),
      ],
    ),
  );
}
