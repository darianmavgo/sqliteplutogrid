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
}) {
  return ToolBar(
    automaticallyImplyLeading: false,
    leading: const SizedBox(width: 1),
    alignment: Alignment.centerLeft,
    titleWidth: 5000,
    title: Row(
      children: [
        Expanded(
          child: BreadcrumbPathField(
            controller: pathController,
            placeholder: 'Banquet URL (e.g. data.db;table)',
            onNavigate: onNavigate,
            flightService: flightService, 
          ),
        ),
        // Add trailing drag area just in case (optional, but good for UX if path is short)
        const DragToMoveArea(
             child: SizedBox(width: 16, height: 40),
        ),
      ],
    ),
  );
}
