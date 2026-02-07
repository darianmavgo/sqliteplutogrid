import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:pocketbase/pocketbase.dart'; 
import 'db_service.dart';
import 'flight_service.dart';

void main() {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SQLite PlutoGrid Viewer',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple, 
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DBViewerPage(dbPath: ''),
    );
  }
}


enum ViewMode { database, fileBrowser, flight }

class DBViewerPage extends StatefulWidget {
  final String dbPath;

  const DBViewerPage({super.key, required this.dbPath});

  @override
  State<DBViewerPage> createState() => _DBViewerPageState();
}

class _DBViewerPageState extends State<DBViewerPage> {
  // Common State
  late TextEditingController _pathController;
  ViewMode _currentMode = ViewMode.flight; // Default to Flight
  bool _isLoading = true;
  String? _errorMessage;
  Key _gridKey = UniqueKey(); // Force rebuild on every load

  // DB View State
  final DatabaseService _dbService = DatabaseService();
  List<String> _tables = [];
  String? _selectedTable;
  List<PlutoColumn> _dbColumns = [];
  // _loadedRows is not strictly used with infinity scroll, but kept for legacy
  int? _totalRows;
  PlutoGridStateManager? _dbStateManager;

  // File Browser State
  List<PlutoColumn> _fileColumns = [];
  List<PlutoRow> _fileRows = [];

  // Flight Service State
  final FlightService _flightService = FlightService();
  bool _isFlightConnected = false;
  bool _isViewingLinksList = false;
  List<PlutoRow> _linksRows = [];


  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.dbPath);
    // Initial load: Auto-connect to Flight
    _autoConnectAndLoad();
  }

  Future<void> _autoConnectAndLoad() async {
     print("[LOG] Auto-connecting to Flight...");
     try {
       // Try default credentials
       await _flightService.authenticate("admin@example.com", "password123");
       if (mounted) {
         setState(() {
           _isFlightConnected = true;
         });
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connected to Flight Server!")));
         // Trigger load (empty path -> load links list)
         _loadPath(); 
       }
     } catch (e) {
       print("[WARN] Auto-connect failed: $e");
       // If auto-connect fails, maybe show connect dialog or just error?
       // For now, let's just fall through, _loadPath will fail or show empty.
       if (widget.dbPath.isNotEmpty) {
          // If a path was provided, maybe we should try local?
           setState(() {
              _currentMode = ViewMode.database; // Or determine from path
           });
           _loadPath();
       } else {
           if (mounted) {
              setState(() {
                 _isLoading = false;
                 _errorMessage = "Could not auto-connect to Flight3 (127.0.0.1:8090). Ensure server is running.";
              });
           }
       }
     }
  }

  @override
  void dispose() {
    _dbService.close();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadPath() async {
    final path = _pathController.text.trim(); // Trim whitespace
    print("[LOG] _loadPath called with: $path");
    
    // Close existing DB connection if any, to avoid locks/leaks
    await _dbService.close();

    // Clear state/UI immediately
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _tables = [];
      _dbColumns = [];
      _fileRows = [];
      _linksRows = [];
      _gridKey = UniqueKey(); // Generate new key to force Grid rebuild
    });

    try {
      if (_currentMode == ViewMode.flight) {
         await _loadFlightData(path);
         return;
      }

      // Local Mode Logic
      // Use statSync to follow links or verify existence robustly
      final type = FileSystemEntity.typeSync(path);
      print("[LOG] Path type detected: $type");
      
      if (type == FileSystemEntityType.notFound) {
         // If not found locally, maybe user intended Flight mode? 
         // For now, throw.
         throw Exception("Path not found: $path");
      }

      if (type == FileSystemEntityType.directory) {
        print("[LOG] Switching to File Browser Mode");
        setState(() {
            _currentMode = ViewMode.fileBrowser;
        });
        await _loadFileBrowser(path);
      } else {
        print("[LOG] Switching to Database Mode");
        setState(() {
            _currentMode = ViewMode.database;
        });
         await _initDBLogic(path);
      }
    } catch (e) {
      print("[ERROR] _loadPath failed: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // --- Flight Logic ---
  
  Future<void> _connectToFlight() async {
     // Dialog to get URL and Creds
     final urlController = TextEditingController(text: _flightService.baseUrl);
     final emailController = TextEditingController(text: "admin@example.com");
     final passwordController = TextEditingController(text: "password123");

     await showDialog(
       context: context, 
       builder: (context) {
         return AlertDialog(
           title: const Text("Connect to Flight Server"),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               TextField(controller: urlController, decoration: const InputDecoration(labelText: "Server URL")),
               TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email")),
               TextField(controller: passwordController, decoration: const InputDecoration(labelText: "Password"), obscureText: true,),
             ],
           ),
           actions: [
             TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
             ElevatedButton(
               onPressed: () async {
                 try {
                   // Update URL first
                   _flightService.updateUrl(urlController.text);
                   
                   // Authenticate
                   await _flightService.authenticate(emailController.text, passwordController.text);
                   
                   if (mounted) {
                      setState(() {
                        _isFlightConnected = true;
                        _currentMode = ViewMode.flight;
                        _pathController.text = ""; // Clear path for user input
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connected to Flight!")));
                      // Load links list immediately
                      _loadPath(); 
                   }
                 } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                 }
               }, 
               child: const Text("Connect")
              ),
           ],
         );
       }
     );
  }

  Future<void> _loadFlightData(String banquetPath) async {
    print("[LOG] Loading Flight Data: $banquetPath");
    if (banquetPath.isEmpty) {
       await _loadBanquetLinksList();
       return;
    }

    try {
      // Fetch schema only first? Or just fetch first page.
      // fetchBanquetData returns rows and columns.
      final data = await _flightService.fetchBanquetData(banquetPath, offset: 0, limit: 100);
      
      final columns = (data['columns'] as List).cast<String>();
      // final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
      final totalCount = data['totalCount'] as int?;

      setState(() {
        _dbColumns = columns.map((e) => PlutoColumn(title: e, field: e, type: PlutoColumnType.text())).toList();
        _totalRows = totalCount;
        _isViewingLinksList = false;
        _isLoading = false;
        _errorMessage = null; 
        _dbStateManager = null; // Reset state manager for new infinite scroll
      });

    } catch(e) {
      print("[ERROR] Flight fetch failed: $e");
      setState(() {
        _isLoading = false;
        _errorMessage = "Flight Error: $e";
      });
    }
  }

  Future<void> _loadBanquetLinksList() async {
    print("[LOG] Loading Banquet Links List");
    try {
      final links = await _flightService.getBanquetLinks();
      
      final columns = [
          PlutoColumn(title: 'Original URL', field: 'original_url', type: PlutoColumnType.text(), width: 400),
          PlutoColumn(title: 'Created', field: 'created', type: PlutoColumnType.text(), width: 200),
          PlutoColumn(title: 'ID', field: 'id', type: PlutoColumnType.text(), hide: true, width: 0),
      ];
      
      final rows = links.map((r) {
         return PlutoRow(cells: {
             'original_url': PlutoCell(value: r.data['original_url'] ?? ''),
             'created': PlutoCell(value: r.created),
             'id': PlutoCell(value: r.id),
         });
      }).toList();

      setState(() {
          _dbColumns = columns;
          _linksRows = rows;
          _isViewingLinksList = true;
          _isLoading = false;
          _errorMessage = null;
          _totalRows = null;
      });
    } catch (e) {
      print("[ERROR] _loadBanquetLinksList failed: $e");
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to load links: $e";
      });
    }
  }

  Future<void> _handleOfflineAccess(String banquetPath) async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
        // 1. Sync to get metadata
        final meta = await _flightService.syncBanquet(banquetPath);
        final serverPath = meta['server_path'];
        final downloadUrl = meta['download_url'];
        
        if (serverPath == null || downloadUrl == null) {
            throw Exception("Invalid metadata from server");
        }

        // 2. Check Same Server Mode
        final serverFile = File(serverPath);
        if (await serverFile.exists()) {
            // Same Server!
            print("[LOG] Same Server Mode detected: $serverPath");
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opening directly from Server Cache (Same Server Mode)")));
            }
            
            setState(() {
                _currentMode = ViewMode.database;
                _pathController.text = serverPath;
            });
            await _loadPath(); // Will trigger database load
            return;
        }
        
        // 3. Download Mode
        print("[LOG] Remote Server detected. Downloading...");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Downloading file from Flight Server...")));
        }
        
        // Determine save path
        final safeName = "flight_download_${DateTime.now().millisecondsSinceEpoch}.sqlite";
        final tempDir = Directory.systemTemp;
        final savePath = p.join(tempDir.path, safeName);
        
        await _flightService.downloadFile(downloadUrl, savePath);
         
        print("[LOG] Downloaded to: $savePath");
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download complete. Opening...")));
        }

        setState(() {
            _currentMode = ViewMode.database;
            _pathController.text = savePath;
        });
        await _loadPath();

    } catch (e) {
        print("[ERROR] Offline access failed: $e");
        setState(() {
            _isLoading = false;
            _errorMessage = "Offline Access Failed: $e";
        });
    }
  }

  void _onFlightRowDoubleTap(PlutoGridOnRowDoubleTapEvent event) {
      if (_isViewingLinksList) {
          final url = event.row.cells['original_url']?.value.toString();
          if (url != null && url.isNotEmpty) {
              _pathController.text = url;
              _loadPath();
          }
      }
  }


  // --- Database Logic ---

  Future<void> _initDBLogic(String path) async {
    print("[LOG] _initDBLogic started for: $path");
    try {
      await _dbService.connect(path);
      final tables = await _dbService.getTables();
      print("[LOG] Database connected. Found ${tables.length} tables.");

      setState(() {
        _tables = tables;
        if (_tables.isNotEmpty) {
           _selectedTable = _tables.first;
           _loadTableData(_selectedTable!);
        } else {
          print("[WARN] No tables found.");
          _isLoading = false;
          _errorMessage = "No tables found in database.";
        }
      });
    } catch (e) {
      print("[ERROR] _initDBLogic failed: $e");
      // If valid file but not valid SQLite
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadTableData(String tableName) async {
    print("[LOG] Loading data for table: $tableName");
    setState(() {
      _isLoading = true;
      _dbColumns = [];
      _totalRows = null;
      _errorMessage = null;
      _dbStateManager = null; 
    });

    try {
      final headers = await _dbService.getTableHeaders(tableName);
      
      if (headers.isEmpty) {
         print("[WARN] Table $tableName is empty or has no columns.");
         setState(() {
          _isLoading = false;
          _errorMessage = "Table is empty or has no columns";
        });
        return;
      }

      print("[LOG] Columns loaded: ${headers.length}");
      _dbColumns = headers.map((key) {
        return PlutoColumn(
          title: key,
          field: key,
          type: PlutoColumnType.text(),
        );
      }).toList();

      setState(() {
        _isLoading = false;
      });
      print("[LOG] Grid initialized for table. Fetching total count...");

      _fetchTotalCount(tableName);
    } catch (e) {
       print("[ERROR] _loadTableData failed: $e");
       setState(() {
        _isLoading = false;
        _errorMessage = "Error loading table $tableName: $e";
      });
    }
  }

  Future<void> _fetchTotalCount(String tableName) async {
    try {
      final count = await _dbService.countRows(tableName);
      if (_selectedTable == tableName && mounted) {
        setState(() {
          _totalRows = count;
        });
      }
    } catch (e) {
      print("Error fetching count: $e");
    }
  }

  // --- File Browser Logic ---

  Future<void> _loadFileBrowser(String path) async {
    print("[LOG] _loadFileBrowser started for: $path");
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
         throw Exception("Directory does not exist: $path");
      }
      
      final List<FileSystemEntity> entities = dir.listSync();
      print("[LOG] Found ${entities.length} entities in directory.");

      // Sort Logic
      entities.sort((a, b) {
        final aIsDB = _isDatabaseFile(a.path);
        final bIsDB = _isDatabaseFile(b.path);
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;

        if (aIsDB && !bIsDB) return -1;
        if (!aIsDB && bIsDB) return 1;
        
        if (aIsDir && !bIsDir && !bIsDB) return -1; // Dir comes before "Other"
        if (!aIsDir && bIsDir && !aIsDB) return 1;

        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      _fileColumns = [
        PlutoColumn(title: 'Name', field: 'name', type: PlutoColumnType.text(), enableRowChecked: false),
        PlutoColumn(title: 'Type', field: 'type', type: PlutoColumnType.text(), width: 100),
        PlutoColumn(title: 'Size', field: 'size', type: PlutoColumnType.text(), width: 100),
      ];

      _fileRows = entities.map((e) {
        String type = e is Directory ? 'Folder' : p.extension(e.path);
        String size = e is File ? '${(e.lengthSync() / 1024).toStringAsFixed(1)} KB' : '';
        
        return PlutoRow(
          cells: {
             'name': PlutoCell(value: p.basename(e.path)),
             'type': PlutoCell(value: type),
             'size': PlutoCell(value: size),
             'path': PlutoCell(value: e.path), // Hidden metadata
          },
        );
      }).toList();

      print("[LOG] File browser rows prepared. Updating UI.");
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print("[ERROR] _loadFileBrowser failed: $e");
      setState(() {
        _isLoading = false;
        _errorMessage = "Error parsing directory: $e";
      });
    }
  }

  bool _isDatabaseFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.sqlite' || ext == '.db';
  }

  void _onFileBrowserRowDoubleTap(PlutoGridOnRowDoubleTapEvent event) {
    final path = event.row.cells['path']?.value.toString();
    if (path != null) {
      _pathController.text = path;
      _loadPath();
    }
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _pathController,
          decoration: InputDecoration(
            hintText: _currentMode == ViewMode.flight ? 'Enter Banquet URL (e.g. data/db.sqlite;table)' : 'Enter Database Path or Folder',
            border: InputBorder.none,
            isDense: true,
            prefixIcon: _currentMode == ViewMode.flight ? const Icon(Icons.cloud, color: Colors.blue) : const Icon(Icons.folder),
            prefixText: _currentMode == ViewMode.flight ? '${_flightService.baseUrl}/' : null,
            prefixStyle: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          onSubmitted: (_) => _loadPath(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.cloud_upload, color: _isFlightConnected ? Colors.green : Colors.grey),
            tooltip: "Connect to Flight3 Server",
            onPressed: _connectToFlight,
          ),
          if (_currentMode == ViewMode.flight && _pathController.text.isNotEmpty)
             IconButton(
               icon: const Icon(Icons.download),
               tooltip: "Download or Open Local (Same Server)",
               onPressed: () => _handleOfflineAccess(_pathController.text),
             ),
          if (_currentMode == ViewMode.database || _currentMode == ViewMode.flight) ...[
             if (_totalRows != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(child: Text("Total Rows: $_totalRows")),
                ),
          ],
          if (_currentMode == ViewMode.database && _tables.isNotEmpty)
                DropdownButton<String>(
                  value: _selectedTable,
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                       setState(() {
                         _selectedTable = newValue;
                       });
                       _loadTableData(newValue);
                    }
                  },
                  items: _tables.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
          const SizedBox(width: 20),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
     if (_errorMessage != null) {
       return Center(child: Text('Error: $_errorMessage', style: const TextStyle(color: Colors.red)));
     }
     
     if (_isLoading) {
       return const Center(child: CircularProgressIndicator());
     }

     if (_currentMode == ViewMode.database) {
        return _buildDatabaseGrid();
     } else if (_currentMode == ViewMode.flight) {
        return _buildFlightGrid();
     } else {
        return _buildFileBrowserGrid();
     }
  }

  Widget _buildDatabaseGrid() {
     if (_dbColumns.isEmpty) {
        return const Center(child: Text("Select a table to view data"));
     }

     return PlutoGrid(
        key: _gridKey,
        columns: _dbColumns,
        rows: [], 
        onLoaded: (PlutoGridOnLoadedEvent event) {
          _dbStateManager = event.stateManager;
          event.stateManager.setShowColumnFilter(true);
        },
        createFooter: (stateManager) {
          return PlutoInfinityScrollRows(
            fetch: (request) async {
               if (_selectedTable == null) return PlutoInfinityScrollRowsResponse(isLast: true, rows: []);
               final offset = stateManager.refRows.length;
               final rowsData = await _dbService.fetchRows(_selectedTable!, limit: 100, offset: offset);
               final newRows = rowsData.map((row) {
                  final cells = <String, PlutoCell>{};
                  row.forEach((key, value) {
                    cells[key] = PlutoCell(value: value?.toString() ?? '');
                  });
                  return PlutoRow(cells: cells);
               }).toList();
               return PlutoInfinityScrollRowsResponse(
                 isLast: newRows.isEmpty,
                 rows: newRows,
               );
            },
            stateManager: stateManager,
          );
        },
        configuration: PlutoGridConfiguration.dark(
           columnSize: const PlutoGridColumnSizeConfig(
            autoSizeMode: PlutoAutoSizeMode.scale,
          ),
        ),
      );
  }
  
  Widget _buildFlightGrid() {
     // If in links list mode, use static, else use infinite
     if (_isViewingLinksList) {
         if (_dbColumns.isEmpty && _linksRows.isEmpty) {
             return const Center(child: Text("No Links Found."));
         }
         return PlutoGrid(
             key: _gridKey,
             columns: _dbColumns,
             rows: _linksRows,
             onRowDoubleTap: _onFlightRowDoubleTap, // Handle navigation
             configuration: PlutoGridConfiguration.dark(
               columnSize: const PlutoGridColumnSizeConfig(
                autoSizeMode: PlutoAutoSizeMode.scale,
              ),
            ),
         );
     }
  
     // Data View Mode
     if (_dbColumns.isEmpty) {
        return const Center(child: Text("Enter a Banquet URL to view data from Flight Server"));
     }

     return PlutoGrid(
        key: _gridKey,
        columns: _dbColumns,
        rows: [], 
        onLoaded: (PlutoGridOnLoadedEvent event) {
          // _dbStateManager = event.stateManager; // Reuse or separate? Reuse is fine for simple view.
          event.stateManager.setShowColumnFilter(true);
        },
        createFooter: (stateManager) {
          return PlutoInfinityScrollRows(
            fetch: (request) async {
               final path = _pathController.text.trim();
               if (path.isEmpty) return PlutoInfinityScrollRowsResponse(isLast: true, rows: []);
               
               final offset = stateManager.refRows.length;
               
               try {
                   final data = await _flightService.fetchBanquetData(path, offset: offset, limit: 100);
                   final rowsList = (data['rows'] as List).cast<Map<String, dynamic>>();
                   
                   final newRows = rowsList.map((row) {
                      final cells = <String, PlutoCell>{};
                       // Ensure all columns in _dbColumns are present
                      for (var col in _dbColumns) {
                         var val = row[col.field];
                         cells[col.field] = PlutoCell(value: val?.toString() ?? '');
                      }
                      return PlutoRow(cells: cells);
                   }).toList();
                   
                   return PlutoInfinityScrollRowsResponse(
                     isLast: newRows.isEmpty,
                     rows: newRows,
                   );
               } catch (e) {
                 print("Error fetching flight rows: $e");
                 // Return empty to stop confusion
                 return PlutoInfinityScrollRowsResponse(isLast: true, rows: []);
               }
            },
            stateManager: stateManager,
          );
        },
        configuration: PlutoGridConfiguration.dark(
           columnSize: const PlutoGridColumnSizeConfig(
            autoSizeMode: PlutoAutoSizeMode.scale,
          ),
        ),
      );
  }

  Widget _buildFileBrowserGrid() {
    return PlutoGrid(
      key: _gridKey,
      columns: _fileColumns,
      rows: _fileRows,
      onRowDoubleTap: _onFileBrowserRowDoubleTap, 
      configuration: PlutoGridConfiguration.dark(
         columnSize: const PlutoGridColumnSizeConfig(
          autoSizeMode: PlutoAutoSizeMode.scale,
        ),
      ),
    );
  }
}
