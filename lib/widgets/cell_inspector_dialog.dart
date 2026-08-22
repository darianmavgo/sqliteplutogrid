import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

class CellInspectorDialog extends StatefulWidget {
  final String columnName;
  final String? cellValue;
  final String? columnType;

  const CellInspectorDialog({
    super.key,
    required this.columnName,
    required this.cellValue,
    this.columnType,
  });

  static Future<void> show(
    BuildContext context, {
    required String columnName,
    required String? cellValue,
    String? columnType,
  }) {
    return showMacosSheet(
      context: context,
      builder: (_) => CellInspectorDialog(
        columnName: columnName,
        cellValue: cellValue,
        columnType: columnType,
      ),
    );
  }

  @override
  State<CellInspectorDialog> createState() => _CellInspectorDialogState();
}

class _CellInspectorDialogState extends State<CellInspectorDialog> {
  bool _isJsonFormatted = false;
  bool _copied = false;
  String _displayText = '';
  bool _canFormatAsJson = false;

  @override
  void initState() {
    super.initState();
    _displayText = widget.cellValue ?? 'NULL';
    _checkJson();
  }

  void _checkJson() {
    final raw = widget.cellValue?.trim();
    if (raw != null && ((raw.startsWith('{') && raw.endsWith('}')) || (raw.startsWith('[') && raw.endsWith(']')))) {
      try {
        final decoded = jsonDecode(raw);
        const encoder = JsonEncoder.withIndent('  ');
        final formatted = encoder.convert(decoded);
        _canFormatAsJson = true;
        if (_isJsonFormatted) {
          _displayText = formatted;
        }
      } catch (_) {
        _canFormatAsJson = false;
      }
    }
  }

  void _toggleJsonFormat() {
    setState(() {
      _isJsonFormatted = !_isJsonFormatted;
      if (_isJsonFormatted) {
        try {
          final decoded = jsonDecode(widget.cellValue!);
          const encoder = JsonEncoder.withIndent('  ');
          _displayText = encoder.convert(decoded);
        } catch (_) {
          _displayText = widget.cellValue ?? '';
        }
      } else {
        _displayText = widget.cellValue ?? 'NULL';
      }
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _displayText));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MacosSheet(
      child: Container(
        width: 580,
        height: 440,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(CupertinoIcons.textbox, size: 18, color: MacosColors.systemOrangeColor),
                const SizedBox(width: 8),
                Text(
                  widget.columnName,
                  style: theme.typography.title2.copyWith(fontWeight: FontWeight.bold),
                ),
                if (widget.columnType != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: MacosColors.systemBlueColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.columnType!,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: MacosColors.systemBlueColor),
                    ),
                  ),
                ],
                const Spacer(),
                if (_canFormatAsJson) ...[
                  PushButton(
                    controlSize: ControlSize.small,
                    secondary: true,
                    onPressed: _toggleJsonFormat,
                    child: Text(_isJsonFormatted ? 'Raw Text' : 'Format JSON'),
                  ),
                  const SizedBox(width: 8),
                ],
                PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: _copyToClipboard,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? CupertinoIcons.check_mark : CupertinoIcons.doc_on_clipboard,
                        size: 12,
                        color: _copied ? MacosColors.systemGreenColor : null,
                      ),
                      const SizedBox(width: 4),
                      Text(_copied ? 'Copied!' : 'Copy'),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Content Viewer
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161616) : const Color(0xFFF6F6F6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.7)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _displayText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Close button
            Align(
              alignment: Alignment.centerRight,
              child: PushButton(
                controlSize: ControlSize.regular,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
