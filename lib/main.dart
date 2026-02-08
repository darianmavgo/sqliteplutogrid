import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:pocketbase/pocketbase.dart'; 
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'db_service.dart';
import 'flight_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window manager
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    
    // Log initial state
    Size size = await windowManager.getSize();
    bool isFull = await windowManager.isFullScreen();
    print("[WINDOW] Initial Size: ${size.width}x${size.height}, FullScreen: $isFull");

    // Attempt Full Screen (Native Mode)
    print("[WINDOW] Attempting to set Full Screen...");
    await windowManager.setFullScreen(true);
    
    // Diagnostic verification after a short delay
    await Future.delayed(const Duration(milliseconds: 500));
    Size finalSize = await windowManager.getSize();
    bool finalFull = await windowManager.isFullScreen();
    print("[WINDOW] Final Size: ${finalSize.width}x${finalSize.height}, FullScreen: $finalFull");

    // Write to a status file for Mage to verify
    try {
      final statusPath = const String.fromEnvironment('STATUS_FILE_PATH');
      if (statusPath.isNotEmpty) {
        final logFile = File(statusPath);
        await logFile.writeAsString("READY: ${finalSize.width}x${finalSize.height}, FULLSCREEN: $finalFull");
        print("[WINDOW] status written to $statusPath");
      }
    } catch (e) {
      print("[WINDOW] Failed to write status file: $e");
    }
  });

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: '🔥 Sqliter',
      theme: MacosThemeData.dark(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
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
  List<TrinaColumn> _dbColumns = [];
  // _loadedRows is not strictly used with infinity scroll, but kept for legacy
  int? _totalRows;
  TrinaGridStateManager? _dbStateManager;

  // File Browser State
  List<TrinaColumn> _fileColumns = [];
  List<TrinaRow> _fileRows = [];

  // Flight Service State
  final FlightService _flightService = FlightService();
  bool _isFlightConnected = false;
  bool _isViewingLinksList = false;
  List<TrinaRow> _linksRows = [];

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
                 _errorMessage = "Could not auto-connect to Flight3 (${_flightService.baseUrl}). Ensure server is running.";
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
                      // Load links list immediately
                      _loadPath(); 
                   }
                 } catch (e) {
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
        _dbColumns = columns.map((e) => TrinaColumn(title: e, field: e, type: TrinaColumnType.text())).toList();
        _totalRows = totalCount;
        _isViewingLinksList = false;
        _isLoading = false;
        _errorMessage = null; 
        _dbStateManager = null; // Reset state manager for new infinite scroll
      });

    } catch(e) {
      print("[ERROR] Flight fetch failed for path '$banquetPath': $e");
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to load data from:\n$banquetPath\n\nError: $e";
      });
    }
  }

  Future<void> _loadBanquetLinksList() async {
    print("[LOG] Loading Banquet Links List");
    try {
      final links = await _flightService.getBanquetLinks();
      
      final columns = [
          TrinaColumn(
            title: 'Banquet Path', 
            field: 'display_path', 
            type: TrinaColumnType.text(),
            renderer: (rendererContext) {
              return Text(
                rendererContext.cell.value?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              );
            },
          ),
          TrinaColumn(
            title: 'Created', 
            field: 'created', 
            type: TrinaColumnType.text(),
            width: 180,
            renderer: (rendererContext) {
              final dateStr = rendererContext.cell.value?.toString() ?? '';
              // Format the date more nicely if needed
              final displayDate = dateStr.length > 19 ? dateStr.substring(0, 19).replaceAll('T', ' ') : dateStr;
              return Text(
                displayDate,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              );
            },
          ),
          TrinaColumn(title: 'Full URL', field: 'original_url', type: TrinaColumnType.text(), hide: true),
          TrinaColumn(title: 'ID', field: 'id', type: TrinaColumnType.text(), hide: true),
      ];
      
      final rows = links.map((r) {
         final originalUrl = r.data['original_url'] ?? '';
         // Extract a cleaner display path (filename or last part of URL)
         String displayPath = originalUrl;
         if (originalUrl.contains('/')) {
           final parts = originalUrl.split('/');
           // Find the meaningful part - usually after 'mksqltp' or just take last 3-4 parts
           if (parts.length > 3) {
             displayPath = parts.sublist(parts.length - 3).join('/');
           }
         }
         // If it's still too long, just show last 60 chars
         if (displayPath.length > 80) {
           displayPath = '...' + displayPath.substring(displayPath.length - 77);
         }
         
         return TrinaRow(cells: {
             'display_path': TrinaCell(value: displayPath),
             'created': TrinaCell(value: r.created),
             'original_url': TrinaCell(value: originalUrl),
             'id': TrinaCell(value: r.id),
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

        // Determine save path
        final safeName = "flight_download_${DateTime.now().millisecondsSinceEpoch}.sqlite";
        final tempDir = Directory.systemTemp;
        final savePath = p.join(tempDir.path, safeName);
        
        await _flightService.downloadFile(downloadUrl, savePath);
         
        if (mounted) {
          setState(() => _isLoading = false);
          _pathController.text = savePath;
          _loadPath();
        }
        await _loadPath();

    } catch (e) {
        print("[ERROR] Offline access failed: $e");
        setState(() {
            _isLoading = false;
            _errorMessage = "Offline Access Failed: $e";
        });
    }
  }

  void _onFlightRowDoubleTap(TrinaGridOnRowDoubleTapEvent event) {
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
        return TrinaColumn(
          title: key,
          field: key,
          type: TrinaColumnType.text(),
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
        TrinaColumn(title: 'Name', field: 'name', type: TrinaColumnType.text(), enableRowChecked: false),
        TrinaColumn(title: 'Type', field: 'type', type: TrinaColumnType.text(), width: 100),
        TrinaColumn(title: 'Size', field: 'size', type: TrinaColumnType.text(), width: 100),
      ];

      _fileRows = entities.map((e) {
        String type = e is Directory ? 'Folder' : p.extension(e.path);
        String size = e is File ? '${(e.lengthSync() / 1024).toStringAsFixed(1)} KB' : '';
        
        return TrinaRow(
          cells: {
             'name': TrinaCell(value: p.basename(e.path)),
             'type': TrinaCell(value: type),
             'size': TrinaCell(value: size),
             'path': TrinaCell(value: e.path), // Hidden metadata
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

  void _onFileBrowserRowDoubleTap(TrinaGridOnRowDoubleTapEvent event) {
    final path = event.row.cells['path']?.value.toString();
    if (path != null) {
      _pathController.text = path;
      _loadPath();
    }
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      toolBar: ToolBar(
        titleWidth: 2000,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0, right: 8.0),
              child: SvgPicture.asset(
                'assets/fire.svg',
                width: 24,
                height: 24,
              ),
            ),
            Expanded(
              child: MacosTextField(
                controller: _pathController,
                placeholder: _currentMode == ViewMode.flight ? 'Banquet URL (e.g. data.db;table)' : 'Path',
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_currentMode == ViewMode.database && _tables.isNotEmpty)
                      MacosPopupButton<String>(
                        value: _selectedTable,
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedTable = newValue;
                            });
                            _loadTableData(newValue);
                          }
                        },
                        items: _tables.map<MacosPopupMenuItem<String>>((String value) {
                          return MacosPopupMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                    if (_totalRows != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text("Rows: $_totalRows", style: MacosTheme.of(context).typography.caption1),
                      ),
                    MacosIconButton(
                      icon: Icon(
                        CupertinoIcons.cloud_upload,
                        color: _isFlightConnected ? MacosColors.systemGreenColor : MacosColors.systemGrayColor,
                      ),
                      onPressed: _connectToFlight,
                    ),
                    if (_currentMode == ViewMode.flight && _pathController.text.isNotEmpty)
                      MacosIconButton(
                        icon: const Icon(CupertinoIcons.cloud_download),
                        onPressed: () => _handleOfflineAccess(_pathController.text),
                      ),
                  ],
                ),
                onSubmitted: (_) => _loadPath(),
              ),
            ),
          ],
        ),
      ),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return _buildBody();
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
     if (_errorMessage != null) {
       return Center(
         child: Container(
           constraints: const BoxConstraints(maxWidth: 600),
           padding: const EdgeInsets.all(32.0),
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               const Icon(CupertinoIcons.exclamationmark_triangle, size: 64, color: MacosColors.systemRedColor),
               const SizedBox(height: 24),
               Text(
                 'Error Loading Data',
                 style: MacosTheme.of(context).typography.title1.copyWith(color: MacosColors.systemRedColor),
               ),
               const SizedBox(height: 16),
               Container(
                 padding: const EdgeInsets.all(16),
                 decoration: BoxDecoration(
                   color: const Color(0xFF2D2D2D),
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: MacosColors.systemRedColor.withOpacity(0.3)),
                 ),
                 child: SelectableText(
                   _errorMessage!,
                   style: MacosTheme.of(context).typography.body.copyWith(
                     fontFamily: 'monospace',
                     color: Colors.white70,
                   ),
                 ),
               ),
               const SizedBox(height: 24),
               Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   MacosIconButton(
                     icon: const Icon(CupertinoIcons.refresh, color: MacosColors.systemBlueColor),
                     onPressed: () {
                       setState(() {
                         _errorMessage = null;
                         _isLoading = true;
                       });
                       _loadPath();
                     },
                   ),
                   const SizedBox(width: 16),
                   MacosIconButton(
                     icon: const Icon(CupertinoIcons.clear, color: MacosColors.systemGrayColor),
                     onPressed: () {
                       setState(() {
                         _errorMessage = null;
                         _pathController.clear();
                       });
                     },
                   ),
                 ],
               ),
             ],
           ),
         ),
       );
     }
     
     if (_isLoading) {
       return const Center(child: ProgressCircle());
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

     return TrinaGrid(
        key: _gridKey,
        columns: _dbColumns,
        rows: [], 
        onLoaded: (TrinaGridOnLoadedEvent event) {
          _dbStateManager = event.stateManager;
          event.stateManager.setShowColumnFilter(true);
        },
        createFooter: (stateManager) {
          return TrinaInfinityScrollRows(
            fetch: (request) async {
               if (_selectedTable == null) return TrinaInfinityScrollRowsResponse(isLast: true, rows: []);
               final offset = stateManager.refRows.length;
               final rowsData = await _dbService.fetchRows(_selectedTable!, limit: 100, offset: offset);
               final newRows = rowsData.map((row) {
                  final cells = <String, TrinaCell>{};
                  row.forEach((key, value) {
                    cells[key] = TrinaCell(value: value?.toString() ?? '');
                  });
                  return TrinaRow(cells: cells);
               }).toList();
               return TrinaInfinityScrollRowsResponse(
                 isLast: newRows.isEmpty,
                 rows: newRows,
               );
            },
            stateManager: stateManager,
          );
        },
        configuration: _getGridConfiguration(context),
      );
  }
  
  Widget _buildFlightGrid() {
     // If in links list mode, use static, else use infinite
     if (_isViewingLinksList) {
         if (_dbColumns.isEmpty && _linksRows.isEmpty) {
             return const Center(child: Text("No Links Found."));
         }
         return TrinaGrid(
             key: _gridKey,
             columns: _dbColumns,
             rows: _linksRows,
             onRowDoubleTap: _onFlightRowDoubleTap, // Handle navigation
              configuration: _getGridConfiguration(context),
         );
     }
  
     // Data View Mode
     if (_dbColumns.isEmpty) {
        return const Center(child: Text("Enter a Banquet URL to view data from Flight Server"));
     }

     return TrinaGrid(
        key: _gridKey,
        columns: _dbColumns,
        rows: [], 
        onLoaded: (TrinaGridOnLoadedEvent event) {
          // _dbStateManager = event.stateManager; // Reuse or separate? Reuse is fine for simple view.
          event.stateManager.setShowColumnFilter(true);
        },
        createFooter: (stateManager) {
          return TrinaInfinityScrollRows(
            fetch: (request) async {
               final path = _pathController.text.trim();
               if (path.isEmpty) return TrinaInfinityScrollRowsResponse(isLast: true, rows: []);
               
               final offset = stateManager.refRows.length;
               
               try {
                   final data = await _flightService.fetchBanquetData(path, offset: offset, limit: 100);
                   final rowsList = (data['rows'] as List).cast<Map<String, dynamic>>();
                   
                   final newRows = rowsList.map((row) {
                      final cells = <String, TrinaCell>{};
                       // Ensure all columns in _dbColumns are present
                      for (var col in _dbColumns) {
                         var val = row[col.field];
                         cells[col.field] = TrinaCell(value: val?.toString() ?? '');
                      }
                      return TrinaRow(cells: cells);
                   }).toList();
                   
                   return TrinaInfinityScrollRowsResponse(
                     isLast: newRows.isEmpty,
                     rows: newRows,
                   );
               } catch (e) {
                 print("Error fetching flight rows: $e");
                 // Return empty to stop confusion
                 return TrinaInfinityScrollRowsResponse(isLast: true, rows: []);
               }
            },
            stateManager: stateManager,
          );
        },
        configuration: _getGridConfiguration(context),
      );
  }

  Widget _buildFileBrowserGrid() {
    return TrinaGrid(
      key: _gridKey,
      columns: _fileColumns,
      rows: _fileRows,
      onRowDoubleTap: _onFileBrowserRowDoubleTap, 
      configuration: _getGridConfiguration(context),
    );
  }
  TrinaGridConfiguration _getGridConfiguration(BuildContext context) {
    return TrinaGridConfiguration.dark(
      style: TrinaGridStyleConfig(
        rowHeight: 30,
        columnHeight: 32,
        columnTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        cellTextStyle: const TextStyle(fontSize: 12, color: Colors.white),
        gridBackgroundColor: const Color(0xFF1E1E1E),
        rowColor: const Color(0xFF2D2D2D),
        activatedColor: const Color(0xFF4A4A4A),
        cellColorInEditState: const Color(0xFF3A3A3A),
        cellColorInReadOnlyState: const Color(0xFF2D2D2D),
        gridBorderColor: const Color(0xFF4A4A4A),
        borderColor: const Color(0xFF3A3A3A),
        activatedBorderColor: MacosColors.systemBlueColor,
        inactivatedBorderColor: const Color(0xFF4A4A4A),
        iconColor: Colors.white70,
        disabledIconColor: Colors.white30,
      ),
      columnSize: const TrinaGridColumnSizeConfig(
        autoSizeMode: TrinaAutoSizeMode.none,
      ),
    );
  }
}
