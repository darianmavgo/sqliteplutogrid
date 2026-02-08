import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:macos_ui/macos_ui.dart';

class FileBrowserView extends StatelessWidget {
  final List<TrinaRow> rows;
  final Function(TrinaRow) onRowDoubleTap;

  const FileBrowserView({
    super.key,
    required this.rows,
    required this.onRowDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.folder_open, size: 48, color: MacosColors.systemGrayColor),
              SizedBox(height: 16),
              Text("Empty directory", style: TextStyle(color: MacosColors.systemGrayColor)),
            ],
          )
        );
    }
    
    // Calculate stats
    int folderCount = 0;
    int fileCount = 0;
    // Iterate to count. Rows cells 'icon' value contains emoji 📁 vs 📄/🗄️
    // Or just count total.
    for (var row in rows) {
       final icon = row.cells['icon']?.value;
       if (icon == '📁') folderCount++;
       else fileCount++;
    }

    return Column(
      children: [
        // Stats Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D), // Dark header background
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Row(
            children: [
              const Icon(CupertinoIcons.folder, size: 16, color: Colors.white60),
              const SizedBox(width: 8),
              Text(
                'Browsing',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(width: 16),
              Text(
                '•',
                style: TextStyle(color: Colors.white.withOpacity(0.3)),
              ),
              const SizedBox(width: 16),
              Text(
                '$folderCount folders, $fileCount files',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7)),
              ),
              const Spacer(),
            ],
          ),
        ),
        
        // Grid
        Expanded(
          child: TrinaGrid(
              columns: [
                  TrinaColumn(field: 'id', title: '', width: 0, type: TrinaColumnType.text(), hide: true),
                  TrinaColumn(
                    field: 'icon', 
                    title: '', 
                    width: 50, // Slightly wider for icon
                    frozen: TrinaColumnFrozen.start, 
                    type: TrinaColumnType.text(),
                    enableSorting: false,
                    enableRowChecked: false,
                  ),
                  TrinaColumn(field: 'name', title: 'Name', width: 400, type: TrinaColumnType.text()),
                  TrinaColumn(field: 'size', title: 'Size', width: 100, type: TrinaColumnType.text()),
                  TrinaColumn(field: 'modified', title: 'Date Modified', width: 200, type: TrinaColumnType.text()),
                  TrinaColumn(field: 'perm', title: 'Permissions', width: 120, type: TrinaColumnType.text()), // Wider for rwxr-xr-x
              ],
              rows: rows,
              onRowDoubleTap: (event) => onRowDoubleTap(event.row),
              configuration: const TrinaGridConfiguration(
                columnSize: TrinaGridColumnSizeConfig(
                  autoSizeMode: TrinaAutoSizeMode.scale, // Ensure columns fill width
                ),
                style: TrinaGridStyleConfig(
                  gridBackgroundColor: Colors.transparent, // Let theme handle it
                  rowColor: Colors.transparent,
                  gridBorderColor: Colors.transparent,
                  // Dark theme colors will apply automatically usually, but specifying safe defaults
                ),
              ),
            ),
        ),
      ],
    );
  }
}
