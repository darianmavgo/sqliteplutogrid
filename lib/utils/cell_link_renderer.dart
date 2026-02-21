import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'dart:io';

/// Detects whether [value] is a URL, a local sqlite/db file path, or plain text.
enum CellLinkType { url, sqliteFile, none }

CellLinkType detectCellLinkType(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return CellLinkType.url;
  }
  if (trimmed.endsWith('.sqlite') ||
      trimmed.endsWith('.sqlite3') ||
      trimmed.endsWith('.db')) {
    return CellLinkType.sqliteFile;
  }
  return CellLinkType.none;
}

/// Renders a cell value as plain text or as a clickable link.
class CellLinkWidget extends StatefulWidget {
  final String value;
  final Function(String)? onNavigate; // For sqlite paths → open in banquet bar
  final Function(String)? onOpenUrl;  // For http URLs → open in browser

  const CellLinkWidget({
    super.key,
    required this.value,
    this.onNavigate,
    this.onOpenUrl,
  });

  @override
  State<CellLinkWidget> createState() => _CellLinkWidgetState();
}

class _CellLinkWidgetState extends State<CellLinkWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final linkType = detectCellLinkType(widget.value);

    if (linkType == CellLinkType.none) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          widget.value,
          style: MacosTheme.of(context).typography.body.copyWith(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final isUrl = linkType == CellLinkType.url;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          if (isUrl) {
            widget.onOpenUrl?.call(widget.value.trim());
          } else {
            widget.onNavigate?.call(widget.value.trim());
          }
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.value,
            style: MacosTheme.of(context).typography.body.copyWith(
              fontSize: 13,
              color: isUrl
                  ? const Color(0xFF60A5FA)   // blue for URLs
                  : const Color(0xFF34D399),  // green for sqlite paths
              decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
              decorationColor: isUrl
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFF34D399),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Opens a URL using macOS `open` command.
Future<void> openUrl(String url) async {
  await Process.run('open', [url]);
}
