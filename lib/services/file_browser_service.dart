import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:trina_grid/trina_grid.dart';
import 'package:flutter/material.dart'; // For formatting date/size? Or remove flutter dep?

class FileBrowserService {
  
  static List<TrinaRow> loadFiles(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw Exception("Directory not found: $path");
    }

    final entities = dir.listSync();
    
    // Sort: Directories first, then files
    entities.sort((a, b) {
      final typeA = FileSystemEntity.typeSync(a.path);
      final typeB = FileSystemEntity.typeSync(b.path);
      
      if (typeA == FileSystemEntityType.directory && typeB != FileSystemEntityType.directory) {
        return -1;
      }
      if (typeA != FileSystemEntityType.directory && typeB == FileSystemEntityType.directory) {
        return 1;
      }
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });

    return entities.map<TrinaRow>((e) {
      final stat = e.statSync();
      final isDir = e is Directory;
      final name = p.basename(e.path);
      final modTime = stat.modified;
      final size = isDir ? '' : _formatBytes(stat.size);
      
      return TrinaRow(
        cells: {
          'id': TrinaCell(value: e.path),
          'icon': TrinaCell(
            value: isDir ? '📁' : (_isDatabaseFile(e.path) ? '🗄️' : '📄'),
          ),
          'name': TrinaCell(value: name),
          'size': TrinaCell(value: size),
          'modified': TrinaCell(value: '${modTime.month}/${modTime.day}/${modTime.year} ${modTime.hour}:${modTime.minute}'),
          'perm': TrinaCell(value: _formatPermission(stat.mode)),
        }
      );
    }).toList();
  }

  static bool _isDatabaseFile(String path) {
    if (path.endsWith('.db') || path.endsWith('.sqlite') || path.endsWith('.sqlite3')) {
      return true;
    }
    return false;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  static String _formatPermission(int mode) {
    // Basic rwxr-xr-x formatting
    final type = (mode & 0xF000) == 0x4000 ? 'd' : '-';
    // User
    final u = mode >> 6 & 0x7;
    // Group
    final g = mode >> 3 & 0x7;
    // Other
    final o = mode & 0x7;
    
    String p(int v) {
      final r = (v & 4) != 0 ? 'r' : '-';
      final w = (v & 2) != 0 ? 'w' : '-';
      final x = (v & 1) != 0 ? 'x' : '-';
      return '$r$w$x';
    }
    
    return '$type${p(u)}${p(g)}${p(o)}';
  }
}
