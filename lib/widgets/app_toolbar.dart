import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'breadcrumb_path_field.dart';
import '../flight_service.dart';

ToolBar buildBanquetBar({
  required BuildContext context,
  required TextEditingController pathController,
  required Function(String) onNavigate,
  required FlightService flightService,
  required VoidCallback onHomeTap,
}) {
  return ToolBar(
    title: Row(
      children: [
        // Flame emoji as home button
        GestureDetector(
          onTap: onHomeTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: const Text(
              '🔥',
              style: TextStyle(
                fontSize: 24,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: BreadcrumbPathField(
            controller: pathController,
            placeholder: 'Banquet URL (e.g. data.db;table)',
            onNavigate: onNavigate,
            flightService: flightService, 
          ),
        ),
      ],
    ),
  );
}
