import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    // If on macOS, prefer the local path directly and ensure it exists
    if (Platform.isMacOS) {
       try {
          final libraryDir = await getLibraryDirectory();
          final dataDir = Directory(p.join(libraryDir.path, 'Application Support', 'Flight3'));
          if (!dataDir.existsSync()) {
             dataDir.createSync(recursive: true);
          }
          final localPath = p.join(dataDir.path, 'home.sqlite');
          
          // Always ensure schema is valid locally
          await _ensureLocalHomeSchema(localPath);
          
          debugPrint("[FlightService] Using local home.sqlite: $localPath");
          return localPath;
       } catch (e) {
         debugPrint("[FlightService] Failed to check/create local path: $e");
         // Fallback to server if local fails (unlikely)
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

  Future<void> _ensureLocalHomeSchema(String path) async {
      try {
        final db = await databaseFactory.openDatabase(path);
        
        // Enable WAL
        await db.execute('PRAGMA journal_mode=WAL;');
        
        // Create Tables
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "0_quick_links" (
            label TEXT, 
            target TEXT, 
            icon TEXT, 
            action TEXT, 
            description TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "1_recent_files" (
            filename TEXT, 
            path TEXT, 
            last_opened DATETIME,
            size_mb REAL,
            PRIMARY KEY (path)
          );
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "2_banquet_links" (
            name TEXT, 
            original_url TEXT, 
            description TEXT,
            PRIMARY KEY (original_url)
          );
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "3_query_styles" (
            name TEXT,
            sql TEXT,
            description TEXT,
            is_dangerous BOOLEAN,
            PRIMARY KEY (name)
          );
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "9_system_messages" (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, 
            level TEXT, 
            message TEXT
          );
        ''');
        
        // Check if Quick Links are empty, if so populate
        final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM "0_quick_links"'));
        if (count == 0) {
           await db.transaction((txn) async {
              await txn.rawInsert(
                'INSERT INTO "0_quick_links" (label, target, icon, action, description) VALUES (?, ?, ?, ?, ?)',
                ['📂 Open Local File', '', 'folder_open', 'open_file', 'Pick a SQLite database from your computer']
              );
              await txn.rawInsert(
                'INSERT INTO "0_quick_links" (label, target, icon, action, description) VALUES (?, ?, ?, ?, ?)',
                ['☁️ Connect to Remote', '', 'cloud', 'connect_remote', 'Enter a Flight URL or S3 bucket']
              );
              await txn.rawInsert(
                'INSERT INTO "0_quick_links" (label, target, icon, action, description) VALUES (?, ?, ?, ?, ?)',
                ['📝 New Query', '', 'edit', 'new_query', 'Start a scratchpad query']
              );
           });
        }
        
        await db.close();
      } catch (e) {
         debugPrint("[FlightService] Failed to ensure local home schema: $e");
         // Don't rethrow, just let it fail later or try server 
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
