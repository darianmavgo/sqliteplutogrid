class Formatters {
  /// Format Unix permissions to human readable string (e.g. rw-r--r--)
  static String formatPermissions(dynamic value) {
    if (value == null) return '';
    if (value is! int) return value.toString();
    
    final mode = value;
    final isDir = (mode & 0x4000) != 0;
    
    var res = isDir ? 'd' : '-';
    
    // User
    res += (mode & 0x0100 != 0) ? 'r' : '-';
    res += (mode & 0x0080 != 0) ? 'w' : '-';
    res += (mode & 0x0040 != 0) ? 'x' : '-';
    
    // Group
    res += (mode & 0x0020 != 0) ? 'r' : '-';
    res += (mode & 0x0010 != 0) ? 'w' : '-';
    res += (mode & 0x0008 != 0) ? 'x' : '-';
    
    // Others
    res += (mode & 0x0004 != 0) ? 'r' : '-';
    res += (mode & 0x0002 != 0) ? 'w' : '-';
    res += (mode & 0x0001 != 0) ? 'x' : '-';
    
    return res;
  }

  /// Format date to yyyy-mm-dd
  static String formatDate(dynamic value) {
    if (value == null) return '';
    try {
      DateTime dt;
      if (value is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is String) {
        dt = DateTime.parse(value);
      } else {
        return value.toString();
      }
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    } catch (e) {
      return value.toString();
    }
  }

  /// Format time to hh:mm:ss
  static String formatTime(dynamic value) {
    if (value == null) return '';
    try {
      DateTime dt;
      if (value is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is String) {
        dt = DateTime.parse(value);
      } else {
        return value.toString();
      }
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
    } catch (e) {
      return value.toString();
    }
  }

  /// Get fruit emoji based on user_version (converter id)
  static String getConverterEmoji(int userVersion) {
    switch (userVersion) {
      case 1: return '🍎'; // CSV
      case 2: return '🍊'; // JSON
      case 3: return '🍋'; // Excel
      case 4: return '🍌'; // Parquet/Other
      case 5: return '🍇'; // XML
      case 6: return '🍓'; // MD
      default: return '🍒'; // Generic
    }
  }
}
