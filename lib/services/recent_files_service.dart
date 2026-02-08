import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recent_file.dart';

/// Service for managing recently opened files
class RecentFilesService {
  static const String _storageKey = 'recent_files';
  static const int maxRecentFiles = 15;
  
  List<RecentFile> _recentFiles = [];
  SharedPreferences? _prefs;
  
  /// Get the list of recent files
  List<RecentFile> get recentFiles => List.unmodifiable(_recentFiles);
  
  /// Initialize the service and load saved recent files
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadRecentFiles();
  }
  
  /// Load recent files from persistent storage
  Future<void> _loadRecentFiles() async {
    try {
      final String? jsonString = _prefs?.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _recentFiles = jsonList
            .map((json) => RecentFile.fromJson(json as Map<String, dynamic>))
            .toList();
        
        // Sort by last opened (most recent first)
        _recentFiles.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
        
        print('[RecentFilesService] Loaded ${_recentFiles.length} recent files');
      }
    } catch (e) {
      print('[RecentFilesService] Error loading recent files: $e');
      _recentFiles = [];
    }
  }
  
  /// Save recent files to persistent storage
  Future<void> _saveRecentFiles() async {
    try {
      final jsonList = _recentFiles.map((file) => file.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await _prefs?.setString(_storageKey, jsonString);
      print('[RecentFilesService] Saved ${_recentFiles.length} recent files');
    } catch (e) {
      print('[RecentFilesService] Error saving recent files: $e');
    }
  }
  
  /// Add or update a file in the recent files list
  Future<void> addRecentFile({
    required String path,
    bool wasConverted = false,
    String? originalFormat,
  }) async {
    try {
      // Extract file name
      final name = p.basename(path);
      
      // Check if file already exists in the list
      final existingIndex = _recentFiles.indexWhere((f) => f.path == path);
      
      if (existingIndex != -1) {
        // Update existing entry
        _recentFiles[existingIndex] = RecentFile(
          path: path,
          name: name,
          lastOpened: DateTime.now(),
          wasConverted: wasConverted,
          originalFormat: originalFormat,
        );
        print('[RecentFilesService] Updated recent file: $name');
      } else {
        // Add new entry
        _recentFiles.insert(0, RecentFile(
          path: path,
          name: name,
          lastOpened: DateTime.now(),
          wasConverted: wasConverted,
          originalFormat: originalFormat,
        ));
        print('[RecentFilesService] Added new recent file: $name');
      }
      
      // Sort by last opened
      _recentFiles.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
      
      // Trim to max size
      if (_recentFiles.length > maxRecentFiles) {
        _recentFiles = _recentFiles.sublist(0, maxRecentFiles);
      }
      
      // Save to storage
      await _saveRecentFiles();
    } catch (e) {
      print('[RecentFilesService] Error adding recent file: $e');
    }
  }
  
  /// Remove a file from the recent files list
  Future<void> removeRecentFile(String path) async {
    try {
      _recentFiles.removeWhere((f) => f.path == path);
      await _saveRecentFiles();
      print('[RecentFilesService] Removed recent file: $path');
    } catch (e) {
      print('[RecentFilesService] Error removing recent file: $e');
    }
  }
  
  /// Clear all recent files
  Future<void> clearAllRecentFiles() async {
    try {
      _recentFiles.clear();
      await _saveRecentFiles();
      print('[RecentFilesService] Cleared all recent files');
    } catch (e) {
      print('[RecentFilesService] Error clearing recent files: $e');
    }
  }
  
  /// Clean up recent files (remove non-existent files)
  Future<void> cleanupRecentFiles() async {
    try {
      final validFiles = <RecentFile>[];
      
      for (final recentFile in _recentFiles) {
        // Check if file still exists
        final file = File(recentFile.path);
        if (file.existsSync()) {
          validFiles.add(recentFile);
        } else {
          print('[RecentFilesService] Removing non-existent file: ${recentFile.path}');
        }
      }
      
      _recentFiles = validFiles;
      await _saveRecentFiles();
      
      print('[RecentFilesService] Cleanup complete. ${_recentFiles.length} files remain.');
    } catch (e) {
      print('[RecentFilesService] Error during cleanup: $e');
    }
  }
  
  /// Get directory of a recent file
  String getDirectory(RecentFile file) {
    return p.dirname(file.path);
  }
}
