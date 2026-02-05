import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'db_service.dart';

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
      home: const DBViewerPage(dbPath: '/Users/darianhickman/Documents/dbs/AllIndex5.sqlite'),
    );
  }
}


enum ViewMode { database, fileBrowser }

class DBViewerPage extends StatefulWidget {
  final String dbPath;

  const DBViewerPage({super.key, required this.dbPath});

  @override
  State<DBViewerPage> createState() => _DBViewerPageState();
}

class _DBViewerPageState extends State<DBViewerPage> {
  // Common State
  late TextEditingController _pathController;
  ViewMode _currentMode = ViewMode.database;
  bool _isLoading = true;
  String? _errorMessage;
  Key _gridKey = UniqueKey(); // Force rebuild on every load

  // DB View State
  final DatabaseService _dbService = DatabaseService();
  List<String> _tables = [];
  String? _selectedTable;
  List<PlutoColumn> _dbColumns = [];
  int _loadedRows = 0;
  int? _totalRows;
  PlutoGridStateManager? _dbStateManager;

  // File Browser State
  List<PlutoColumn> _fileColumns = [];
  List<PlutoRow> _fileRows = [];

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.dbPath);
    _loadPath();
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
      _gridKey = UniqueKey(); // Generate new key to force Grid rebuild
    });

    try {
      // Use statSync to follow links or verify existence robustly
      final type = FileSystemEntity.typeSync(path);
      print("[LOG] Path type detected: $type");
      
      if (type == FileSystemEntityType.notFound) {
         throw Exception("Path not found: $path");
      }

      // Check if it's a directory (or link to one?)
      // FileSystemEntity.typeSync returns 'directory' logic for links if followLinks is true (default is true?)
      // Actually default is true.
      
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
      _loadedRows = 0;
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

        return basename(a.path).toLowerCase().compareTo(basename(b.path).toLowerCase());
      });

      _fileColumns = [
        PlutoColumn(title: 'Name', field: 'name', type: PlutoColumnType.text(), enableRowChecked: false),
        PlutoColumn(title: 'Type', field: 'type', type: PlutoColumnType.text(), width: 100),
        PlutoColumn(title: 'Size', field: 'size', type: PlutoColumnType.text(), width: 100),
      ];

      _fileRows = entities.map((e) {
        String type = e is Directory ? 'Folder' : extension(e.path);
        String size = e is File ? '${(e.lengthSync() / 1024).toStringAsFixed(1)} KB' : '';
        
        return PlutoRow(
          cells: {
             'name': PlutoCell(value: basename(e.path)),
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
    final ext = extension(path).toLowerCase();
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
          decoration: const InputDecoration(
            hintText: 'Enter Database Path or Folder',
            border: InputBorder.none,
            isDense: true,
          ),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          onSubmitted: (_) => _loadPath(),
        ),
        actions: [
          if (_currentMode == ViewMode.database) ...[
             if (_totalRows != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(child: Text("Total Rows: $_totalRows")),
                ),
             if (_tables.isNotEmpty)
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
          ],
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
