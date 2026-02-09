import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

class FlightService {
  String baseUrl;
  late PocketBase pb;
  late final http.Client _httpClient;
  bool _isAdmin = false;

  FlightService({String? baseUrl}) 
      : baseUrl = baseUrl ?? const String.fromEnvironment('FLIGHT_URL', defaultValue: 'http://127.0.0.1:8090') {
    print("[FlightService] Initialized with Base URL: $baseUrl");
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
      await pb.admins.authWithPassword(email, password);
      _isAdmin = true;
    } catch (e) {
      // Fallback to regular user
      await pb.collection('users').authWithPassword(email, password);
      _isAdmin = false;
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
    print('[FlightService] Fetching: $uri');

    try {
      final response = await _httpClient.get(uri);
      
      print('[FlightService] Response status: ${response.statusCode}');
      print('[FlightService] Response body (first 200 chars): ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      
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
      print('[FlightService] ERROR: $e');
      rethrow;
    }
  }
  
  Future<List<RecordModel>> getBanquetLinks() async {
    try {
      // Use getList to be safer
      final result = await pb.collection('banquet_links').getList(page: 1, perPage: 100);
      return result.items;
    } catch (e) {
      print("[FlightService] Error fetching links: $e");
      if (e is ClientException) {
         print("Response: ${e.response}");
      }
      return [];
    }
  }

  Future<List<RecordModel>> getQueryStyles() async {
    try {
      final result = await pb.collection('query_style').getList(page: 1, perPage: 100);
      return result.items;
    } catch (e) {
      print("[FlightService] Error fetching styles: $e");
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

  String? get userId => pb.authStore.model?.id;
}
