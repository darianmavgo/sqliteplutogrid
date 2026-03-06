import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'breadcrumb_path_field.dart';
import 'package:window_manager/window_manager.dart';
import '../flight_service.dart';

ToolBar buildBanquetBar({
  required BuildContext context,
  required TextEditingController pathController,
  required Function(String) onNavigate,
  required FlightService flightService,
  required VoidCallback onHomeTap,
  bool tileMode = false,
  VoidCallback? onToggleTile,
}) {
  return ToolBar(
    automaticallyImplyLeading: false,
    padding: EdgeInsets.zero,
    leading: Padding(
      padding: const EdgeInsets.only(left: 8),
      child: MacosIconButton(
        padding: EdgeInsets.zero,
        icon: const Text('🍊', style: TextStyle(fontSize: 20)),
        onPressed: onHomeTap,
      ),
    ),
    alignment: Alignment.centerLeft,
    titleWidth: 5000,
    title: Row(
      children: [
        Expanded(
          child: BreadcrumbPathField(
            controller: pathController,
            placeholder: 'Banquet URL — append #tile for thumbnail view',
            onNavigate: onNavigate,
            flightService: flightService,
          ),
        ),
        // Tile / Grid toggle button — only shown when data is loaded
        if (onToggleTile != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: Tooltip(
              message: tileMode ? 'Switch to table grid' : 'Switch to tile view (#tile)',
              child: MacosIconButton(
                padding: const EdgeInsets.all(4),
                icon: Icon(
                  tileMode ? CupertinoIcons.table : CupertinoIcons.square_grid_2x2,
                  size: 16,
                  color: tileMode
                      ? MacosColors.systemOrangeColor
                      : MacosColors.white.withValues(alpha: 0.6),
                ),
                onPressed: onToggleTile,
              ),
            ),
          ),
        const DragToMoveArea(
          child: SizedBox(width: 4, height: 40),
        ),
      ],
    ),
  );
}
