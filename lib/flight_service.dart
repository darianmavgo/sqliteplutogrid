import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class FlightService {
  String baseUrl;
  late PocketBase pb;
  late final http.Client _httpClient;

  FlightService({String? baseUrl}) 
      : baseUrl = (baseUrl != null && baseUrl.isNotEmpty) 
          ? baseUrl 
          : const String.fromEnvironment('FLIGHT_URL', defaultValue: 'http://127.0.0.1:8090') {
            
    // Extra safety for empty string or "null" string
    if (this.baseUrl.isEmpty || this.baseUrl == "null") {
       this.baseUrl = 'http://127.0.0.1:8090';
    }
    
    debugPrint("[FlightService] Initialized with Base URL: ${this.baseUrl}");
    initPb();
    _httpClient = http.Client();
  }

  void initPb() {
    pb = PocketBase(baseUrl);
  }

  void updateUrl(String url) {
    baseUrl = url;
    initPb();
  }

  bool get isAuthenticated => pb.authStore.isValid;

  Future<void> authenticate(String email, String password) async {
    try {
      // Try as admin first
      await pb.collection('_superusers').authWithPassword(email, password);
    } catch (e) {
      // Fallback to regular user
      await pb.collection('users').authWithPassword(email, password);
    }
  }

  Future<Map<String, dynamic>> fetchBanquetData(String banquetPath, {int? offset, int? limit}) async {
    // Construct URL: /sqliter/rows?path=...
    final queryParams = {
      'path': banquetPath,
    };
    
    if (offset != null && limit != null) {
      queryParams['start'] = offset.toString();
      queryParams['end'] = (offset + limit).toString();
    }
    
    final uri = Uri.parse('$baseUrl/sqliter/rows').replace(queryParameters: queryParams);
    debugPrint('[FlightService] Fetching: $uri');

    try {
      final response = await _httpClient.get(uri);
      
      debugPrint('[FlightService] Response status: ${response.statusCode}');
      debugPrint('[FlightService] Response body (first 200 chars): ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      
      if (response.statusCode == 200) {
        try {
          return jsonDecode(response.body);
        } catch (e) {
          throw Exception('Failed to parse JSON response from $uri: $e\nResponse: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');
        }
      } else {
        throw Exception('HTTP ${response.statusCode} from $uri: ${response.body}');
      }
    } catch (e) {
      debugPrint('[FlightService] ERROR: $e');
      rethrow;
    }
  }
  
  Future<List<RecordModel>> getBanquetLinks() async {
    try {
      // Use getList to be safer
      final result = await pb.collection('banquet_links').getList(page: 1, perPage: 100);
      return result.items;
    } catch (e) {
      debugPrint("[FlightService] Error fetching links: $e");
      if (e is ClientException) {
         debugPrint("Response: ${e.response}");
      }
      return [];
    }
  }

  Future<List<RecordModel>> getQueryStyles() async {
    try {
      final result = await pb.collection('query_style').getList(page: 1, perPage: 100);
      return result.items;
    } catch (e) {
      debugPrint("[FlightService] Error fetching styles: $e");
      return [];
    }
  }
  
  Future<RecordModel> saveBanquetLink(String path) async {
      return await pb.collection('banquet_links').create(body: {
          'original_url': path,
      });
  }

  /// Syncs the dataset with Flight3 and returns metadata including server path and download URL.
  Future<Map<String, String>> syncBanquet(String banquetPath) async {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uriStr = '$cleanBase/sqliter/sync/$banquetPath';
    final uri = Uri.parse(uriStr);

    final response = await _httpClient.get(uri);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Map<String, String>.from(data);
    } else {
      throw Exception('Failed to sync: ${response.statusCode} ${response.body}');
    }
  }

  Future<String> getHomeDatabasePath() async {
    // If on macOS, prefer the local path directly
    if (Platform.isMacOS) {
       try {
          final libraryDir = await getLibraryDirectory();
          final localPath = p.join(libraryDir.path, 'Application Support', 'Flight3', 'home.sqlite');
          if (File(localPath).existsSync()) {
             debugPrint("[FlightService] Found local home.sqlite: $localPath");
             return localPath;
          }
       } catch (e) {
         debugPrint("[FlightService] Failed to check local path: $e");
       }
    }

    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse('$cleanBase/sqliter/home');
    
    try {
      final response = await _httpClient.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['path'];
      } else {
        throw Exception('Failed to get home path: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("[FlightService] Error fetching home path: $e");
      rethrow;
    }
  }

  /// Downloads the file from Flight3 to a local path.
  Future<void> downloadFile(String downloadUrlPath, String savePath) async {
      final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      // downloadUrlPath should start with /
      final uri = Uri.parse('$cleanBase$downloadUrlPath');
      
      final response = await _httpClient.get(uri);
       if (response.statusCode == 200) {
          final file = File(savePath);
          await file.create(recursive: true);
          await file.writeAsBytes(response.bodyBytes);
       } else {
           throw Exception('Failed to download: ${response.statusCode}');
       }
  }

  /// Generic GET request with query parameters
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
    final response = await _httpClient.get(uri);
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('HTTP ${response.statusCode} from $uri: ${response.body}');
    }
  }

  /// Generic POST request
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body != null ? jsonEncode(body) : null,
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('HTTP ${response.statusCode} from $uri: ${response.body}');
    }
  }

  /// Generic DELETE request
  Future<void> delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _httpClient.delete(uri);
    
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('HTTP ${response.statusCode} from $uri: ${response.body}');
    }
  }

  String? get userId => pb.authStore.record?.id;
}
