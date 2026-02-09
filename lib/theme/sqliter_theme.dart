import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:trina_grid/trina_grid.dart';

class SqliterTheme {
  /// Returns a TrinaGrid configuration that perfectly matches the current MacosTheme
  static TrinaGridConfiguration getGridConfig(BuildContext context) {
    // 1. READ the single source of truth
    final theme = MacosTheme.of(context);
    final typography = theme.typography;
    final isDark = theme.brightness == Brightness.dark;

    // Define colors based on theme brightness
    final Color backgroundColor = theme.canvasColor;
    final Color gridBorderColor = theme.dividerColor;
    final Color rowColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color activatedColor = theme.primaryColor.withValues(alpha: 0.15);
    final Color activatedBorderColor = theme.primaryColor;

    // 2. MAP MacosTheme tokens to TrinaGrid tokens
    // We explicitly set every color to ensure no "white default" leaks through
    return TrinaGridConfiguration(
      style: TrinaGridStyleConfig(
        // Backgrounds
        gridBackgroundColor: backgroundColor,
        rowColor: rowColor,
        
        // Borders (using divider color from theme)
        gridBorderColor: gridBorderColor,
        borderColor: gridBorderColor,
        
        // Headers
        columnTextStyle: typography.headline.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: theme.typography.headline.color,
        ),
        
        // Cells
        cellTextStyle: typography.body.copyWith(
          fontSize: 13,
          color: theme.typography.body.color,
        ),
        
        // Selection / Activity
        activatedColor: activatedColor,
        activatedBorderColor: activatedBorderColor,
        
        // Icon colors
        iconColor: theme.iconTheme.color ?? (isDark ? Colors.white70 : Colors.black54),
      ),
      columnFilter: const TrinaGridColumnFilterConfig(
        filters: [], // No filters by default to avoid clutter
      ),
    );
  }
}
