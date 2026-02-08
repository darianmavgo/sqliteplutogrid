import 'dart:convert';

/// Model representing a recently opened file
class RecentFile {
  final String path;
  final String name;
  final DateTime lastOpened;
  final bool wasConverted;
  final String? originalFormat; // CSV, XLSX, etc. (null if SQLite)
  
  RecentFile({
    required this.path,
    required this.name,
    required this.lastOpened,
    this.wasConverted = false,
    this.originalFormat,
  });
  
  /// Create from JSON
  factory RecentFile.fromJson(Map<String, dynamic> json) {
    return RecentFile(
      path: json['path'] as String,
      name: json['name'] as String,
      lastOpened: DateTime.parse(json['lastOpened'] as String),
      wasConverted: json['wasConverted'] as bool? ?? false,
      originalFormat: json['originalFormat'] as String?,
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'lastOpened': lastOpened.toIso8601String(),
      'wasConverted': wasConverted,
      'originalFormat': originalFormat,
    };
  }
  
  /// Get relative time string (e.g., "2 hours ago", "Yesterday")
  String getRelativeTime() {
    final now = DateTime.now();
    final difference = now.difference(lastOpened);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
  }
  
  /// Get file type display string
  String getFileType() {
    if (wasConverted && originalFormat != null) {
      return '$originalFormat → DB';
    } else if (originalFormat != null) {
      return originalFormat!; // Use non-null assertion since we checked above
    } else {
      return 'SQLite';
    }
  }
  
  @override
  String toString() {
    return 'RecentFile(path: $path, name: $name, lastOpened: $lastOpened, wasConverted: $wasConverted)';
  }
}
