import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for managing cached file conversions
class CacheService {
  static const String cacheDirectoryName = 'conversions';
  static const int defaultCacheDurationDays = 7;
  
  Directory? _cacheDir;
  
  CacheService();
  
  /// Get or create the cache directory
  Future<Directory> getCacheDirectory() async {
    if (_cacheDir != null) {
      return _cacheDir!;
    }
    
    try {
      // Try to get application support directory
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(appDir.path, cacheDirectoryName));
    } catch (e) {
      // Fallback to temp directory
      print('[CacheService] Could not get app support dir, using temp: $e');
      final tempDir = Directory.systemTemp;
      _cacheDir = Directory(p.join(tempDir.path, 'sqliter_cache', cacheDirectoryName));
    }
    
    // Create directory if it doesn't exist
    if (!_cacheDir!.existsSync()) {
      await _cacheDir!.create(recursive: true);
      print('[CacheService] Created cache directory: ${_cacheDir!.path}');
    }
    
    return _cacheDir!;
  }
  
  /// Generate a cache key from a file
  /// Uses file path and modification time to ensure uniqueness
  String getCacheKey(File file) {
    final stat = file.statSync();
    final modTime = stat.modified.millisecondsSinceEpoch;
    
    // Sanitize file path for use in filename
    String sanitizedPath = file.path
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(':', '_')
        .replaceAll(' ', '_');
    
    // Remove extension from sanitized path
    final ext = p.extension(sanitizedPath);
    if (ext.isNotEmpty) {
      sanitizedPath = sanitizedPath.substring(0, sanitizedPath.length - ext.length);
    }
    
    // Limit length to avoid filesystem issues
    if (sanitizedPath.length > 100) {
      sanitizedPath = sanitizedPath.substring(sanitizedPath.length - 100);
    }
    
    return '${sanitizedPath}_$modTime.db';
  }
  
  /// Get cached conversion file if it exists and is valid
  Future<File?> getCachedConversion(File sourceFile) async {
    try {
      final cacheDir = await getCacheDirectory();
      final cacheKey = getCacheKey(sourceFile);
      final cachedFile = File(p.join(cacheDir.path, cacheKey));
      
      if (!cachedFile.existsSync()) {
        return null;
      }
      
      // Check if cache is still valid
      final stat = cachedFile.statSync();
      final cacheAge = DateTime.now().difference(stat.modified);
      
      if (cacheAge.inDays > defaultCacheDurationDays) {
        print('[CacheService] Cache expired for ${sourceFile.path}');
        // Delete expired cache
        await cachedFile.delete();
        return null;
      }
      
      // Check if source file has been modified since cache was created
      final sourceStat = sourceFile.statSync();
      if (sourceStat.modified.isAfter(stat.modified)) {
        print('[CacheService] Source file modified, cache invalid');
        await cachedFile.delete();
        return null;
      }
      
      print('[CacheService] Cache hit: $cacheKey');
      return cachedFile;
      
    } catch (e) {
      print('[CacheService] Error checking cache: $e');
      return null;
    }
  }
  
  /// Cache a converted file
  Future<void> cacheConversion(File sourceFile, File convertedFile) async {
    try {
      final cacheDir = await getCacheDirectory();
      final cacheKey = getCacheKey(sourceFile);
      final cacheFile = File(p.join(cacheDir.path, cacheKey));
      
      // Copy converted file to cache
      await convertedFile.copy(cacheFile.path);
      
      print('[CacheService] Cached conversion: $cacheKey');
      
      // Clean up old cache entries
      _cleanupOldCache(cacheDir);
      
    } catch (e) {
      print('[CacheService] Error caching file: $e');
      // Don't throw - caching failure shouldn't break conversion
    }
  }
  
  /// Create a temporary file for conversion result
  Future<File> createTempFile(File sourceFile) async {
    final cacheDir = await getCacheDirectory();
    final baseName = p.basenameWithoutExtension(sourceFile.path);
    final tempPath = p.join(cacheDir.path, 'temp_${baseName}_${DateTime.now().millisecondsSinceEpoch}.db');
    
    return File(tempPath);
  }
  
  /// Clean up old cache entries (keep last 30 days)
  void _cleanupOldCache(Directory cacheDir) {
    try {
      final files = cacheDir.listSync();
      final now = DateTime.now();
      
      for (final file in files) {
        if (file is File) {
          final stat = file.statSync();
          final age = now.difference(stat.modified);
          
          if (age.inDays > 30) {
            print('[CacheService] Deleting old cache file: ${p.basename(file.path)}');
            file.deleteSync();
          }
        }
      }
    } catch (e) {
      print('[CacheService] Error cleaning up cache: $e');
    }
  }
  
  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final cacheDir = await getCacheDirectory();
      final files = cacheDir.listSync();
      
      int totalFiles = 0;
      int totalSize = 0;
      
      for (final file in files) {
        if (file is File) {
          totalFiles++;
          totalSize += file.statSync().size;
        }
      }
      
      return {
        'fileCount': totalFiles,
        'totalSizeBytes': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'cacheDirectory': cacheDir.path,
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }
  
  /// Clear all cached conversions
  Future<void> clearCache() async {
    try {
      final cacheDir = await getCacheDirectory();
      final files = cacheDir.listSync();
      
      int deletedCount = 0;
      for (final file in files) {
        if (file is File) {
          await file.delete();
          deletedCount++;
        }
      }
      
      print('[CacheService] Cleared $deletedCount cached files');
    } catch (e) {
      print('[CacheService] Error clearing cache: $e');
      rethrow;
    }
  }
}
