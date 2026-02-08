import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'cache_service.dart';

/// Exception thrown when file conversion fails
class ConversionException implements Exception {
  final String message;
  final String? code;
  final String? detail;
  
  ConversionException(this.message, {this.code, this.detail});
  
  @override
  String toString() {
    if (detail != null) {
      return 'ConversionException: $message\nDetail: $detail';
    }
    return 'ConversionException: $message';
  }
}

/// Service for converting non-SQLite files to SQLite using Flight3
class ConversionService {
  final String? flight3Url;
  final CacheService cacheService;
  late final http.Client _httpClient;
  
  ConversionService({
    this.flight3Url,
    CacheService? cacheService,
  }) : cacheService = cacheService ?? CacheService() {
    _httpClient = http.Client();
    print('[ConversionService] Initialized with Flight3 URL: $flight3Url');
  }
  
  /// Supported file extensions for conversion
  static const supportedExtensions = [
    '.csv',
    '.xlsx',
    '.xls',
    '.json',
    '.html',
    '.htm',
    '.md',
    '.markdown',
    '.txt',
    '.zip',
  ];
  
  /// SQLite file extensions (no conversion needed)
  static const sqliteExtensions = [
    '.db',
    '.sqlite',
    '.sqlite3',
  ];
  
  /// Check if a file is already a SQLite database
  bool isSqliteFile(File file) {
    final ext = p.extension(file.path).toLowerCase();
    return sqliteExtensions.contains(ext);
  }
  
  /// Check if a file is supported for conversion
  bool isConvertibleFile(File file) {
    final ext = p.extension(file.path).toLowerCase();
    return supportedExtensions.contains(ext);
  }
  
  /// Ensures the file is a SQLite database.
  /// If already SQLite, returns the file as-is.
  /// If convertible and Flight3 is available, converts it.
  /// Otherwise, throws a ConversionException.
  Future<File> ensureSqlite(File file) async {
    print('[ConversionService] Ensuring SQLite for: ${file.path}');
    
    // If already SQLite, return as-is
    if (isSqliteFile(file)) {
      print('[ConversionService] File is already SQLite');
      return file;
    }
    
    // Check if file is convertible
    if (!isConvertibleFile(file)) {
      final ext = p.extension(file.path);
      throw ConversionException(
        'Unsupported file type: $ext',
        code: 'unsupported_format',
        detail: 'Supported formats: ${supportedExtensions.join(", ")}',
      );
    }
    
    // Check local cache first
    print('[ConversionService] Checking cache...');
    final cached = await cacheService.getCachedConversion(file);
    if (cached != null && cached.existsSync()) {
      print('[ConversionService] Found in cache: ${cached.path}');
      return cached;
    }
    
    // Try Flight3 conversion if available
    if (flight3Url != null && flight3Url!.isNotEmpty) {
      try {
        print('[ConversionService] Converting via Flight3...');
        final converted = await convertViaFlight3(file);
        
        // Cache the result
        await cacheService.cacheConversion(file, converted);
        
        return converted;
      } catch (e) {
        print('[ConversionService] Flight3 conversion failed: $e');
        // Don't rethrow yet - show helpful error below
      }
    }
    
    // Fallback: show error with helpful message
    final ext = p.extension(file.path);
    throw ConversionException(
      'Cannot open $ext files directly.\n\n'
      'To view this file:\n'
      '• Start Flight3 server for automatic conversion\n'
      '• Or manually convert to SQLite first',
      code: 'conversion_unavailable',
    );
  }
  
  /// Convert a file to SQLite using Flight3 API
  Future<File> convertViaFlight3(File file) async {
    if (flight3Url == null || flight3Url!.isEmpty) {
      throw ConversionException('Flight3 URL not configured');
    }
    
    final uri = Uri.parse('$flight3Url/api/convert');
    print('[ConversionService] Uploading to: $uri');
    
    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: p.basename(file.path),
      ));
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('[ConversionService] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        // Success - save to temp file
        final tempFile = await cacheService.createTempFile(file);
        await tempFile.writeAsBytes(response.bodyBytes);
        
        print('[ConversionService] Conversion successful: ${tempFile.path}');
        return tempFile;
      } else {
        // Error - try to parse JSON error response
        String errorMessage = 'Conversion failed';
        String? errorCode;
        String? errorDetail;
        
        try {
          final errorData = http.Response(response.body, response.statusCode);
          // Try to parse as JSON
          if (response.headers['content-type']?.contains('json') ?? false) {
            // Note: Would need dart:convert imported
            // For now, just use the body as error message
            errorMessage = response.body;
          }
        } catch (e) {
          errorMessage = response.body;
        }
        
        throw ConversionException(
          errorMessage,
          code: errorCode ?? 'conversion_failed',
          detail: errorDetail,
        );
      }
    } catch (e) {
      if (e is ConversionException) {
        rethrow;
      }
      
      // Network or other error
      throw ConversionException(
        'Failed to connect to Flight3 server',
        code: 'network_error',
        detail: e.toString(),
      );
    }
  }
  
  /// Dispose resources
  void dispose() {
    _httpClient.close();
  }
}
