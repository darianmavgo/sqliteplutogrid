import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: depend_on_referenced_packages
// import 'package:pocketbase/pocketbase.dart'; 
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:banquet/banquet.dart';

import 'db_service.dart';
import 'flight_service.dart';
import 'utils/formatters.dart';
import 'utils/cell_link_renderer.dart';

import 'widgets/banquet_bar.dart';
import 'widgets/database_grid_view.dart';
import 'widgets/tile_view.dart';

/// Custom column title renderer that replaces the default sort icons
/// with "+" (ascending) and "-" (descending).
Widget _buildColumnTitle(TrinaColumnTitleRendererContext ctx) {
  final col = ctx.column;
  String sortIcon = '';
  if (col.sort.isAscending) sortIcon = ' +';
  if (col.sort.isDescending) sortIcon = ' -';

  return GestureDetector(
    onTap: () {
      // Cycle: none → ascending → descending → none
      if (col.sort.isNone || col.sort.isDescending) {
        ctx.stateManager.sortAscending(col);
      } else {
        ctx.stateManager.sortDescending(col);
      }
    },
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${col.title}$sortIcon',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        if (ctx.showContextIcon) ctx.contextMenuIcon,
      ],
    ),
  );
}

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
    await windowManager.maximize();
  });

  // Initialize FFI for SQLite
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MyApp());
  
  // Write status file if requested (for integration tests)
  const statusFilePath = String.fromEnvironment('STATUS_FILE_PATH');
  if (statusFilePath.isNotEmpty) {
     try {
       await File(statusFilePath).writeAsString('Window Initialized at ${DateTime.now()}');
     } catch (e) {
       // Ignore errors writing to tmp
       debugPrint('Failed to write status file: $e');
     }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: '🍊',
      themeMode: ThemeMode.dark,
      darkTheme: MacosThemeData.dark(),
      theme: MacosThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          // Use a builder to get the correct context for MediaQuery
          final data = MediaQuery.of(context);
          return MediaQuery(
            // Cap the scaling to prevent layout breakage on very large text settings
            data: data.copyWith(
              textScaler: data.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.5),
            ),
            child: const DBViewerPage(),
          );
        },
      ),
    );
  }
}

class DBViewerPage extends StatefulWidget {
  final FlightService? flightService;
  final DatabaseService? dbService;

  const DBViewerPage({
    super.key,
    this.flightService,
    this.dbService,
  });

  @override
  State<DBViewerPage> createState() => _DBViewerPageState();
}

class _DBViewerPageState extends State<DBViewerPage> {
  static const _fileOpenChannel = MethodChannel('com.darianmavgo.sqliter/file_open');

  // Services
  late final DatabaseService _dbService;
  late final FlightService _flightService;

  // State
  bool _isLoading = false;
  String? _errorMessage;
  
  // Controller
  final TextEditingController _pathController = TextEditingController();

  // Data
  final GlobalKey _gridKey = GlobalKey(); // To trigger grid reloads
  
  // Unified Grid Data State
  List<TrinaColumn> _gridColumns = [];
  String? _gridTitle;
  int? _totalRows;
  String? _homePath; // Cache home path
  
  // We need to keep track of what we are viewing to fetch correct rows
  // 0 = Banquet Links (Default home)
  // 1 = Database Table
  // 2 = Query Result (In-Memory)
  int _viewType = 0; 
  String? _currentTableName; // For DB view
  List<TrinaRow> _cachedBanquetRows = []; // For Query view
  bool _tileMode = false; // When true, show TileView instead of Grid

  @override
  void initState() {
    super.initState();
    
    // Initialize services
    _flightService = widget.flightService ?? FlightService();
    _dbService = widget.dbService ?? DatabaseService();
    
    // Perform async initialization
    _initServices();
    
    // Listen for file open events
    _fileOpenChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened') {
        final String path = call.arguments;
        _loadPath(pathOverride: path);
      }
    });

    // Check for pending files
    _checkPendingFile();
    
    // Initial checks - Load Home DB
    _loadHome();
  }

  Future<void> _checkPendingFile() async {
    try {
      final String? pendingPath = await _fileOpenChannel.invokeMethod('getPendingFile');
      if (pendingPath != null && pendingPath.isNotEmpty) {
        _loadPath(pathOverride: pendingPath);
      }
    } catch (e) {
      debugPrint('Failed to get pending file: $e');
    }
  }

  Future<void> _initServices() async {
    // Initialize services if needed
  }
  
  Future<void> _loadHome() async {
     // Reset title
     windowManager.setTitle('🍊');
     setState(() {
       _isLoading = true;
       _errorMessage = null;
       _viewType = 0; // Home Mode
       _tileMode = false; // Always grid on home
       _pathController.clear();
     });
     
     try {
       // 1. Get path to home.sqlite from server
       final homePath = await _flightService.getHomeDatabasePath();
       _homePath = homePath;
       
       // 2. Open it as a database
       await _openDatabaseFile(homePath, isHome: true);
       
     } catch (e) {
       if (e.toString().contains("Home database was empty")) {
           debugPrint("Retrying home load after repair...");
           // ignore: use_build_context_synchronously
           if (context.mounted) {
              Future.delayed(const Duration(milliseconds: 500), () => _loadHome());
           }
           return;
       }
       setState(() {
         _isLoading = false;
         _errorMessage = "Failed to load home: $e";
       });
     }
  }

  @override
  void dispose() {
    _dbService.close();
    _pathController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation & Logic
  // ---------------------------------------------------------------------------

  Future<void> _loadPath({String? pathOverride}) async {
    final rawPath = pathOverride ?? _pathController.text.trim();
    if (rawPath.isEmpty) return;

    // Detect and strip #tile keyword
    final hasTile = rawPath.contains('#tile');
    final path = rawPath.replaceAll('#tile', '').trim();

    // Keep #tile in the URL bar so breadcrumb shows the chip
    final displayPath = hasTile ? '$path#tile' : path;
    if (pathOverride != null) {
      _pathController.text = displayPath;
    }

    setState(() {
      _tileMode = hasTile;
    });

    if (path.isEmpty) return;
    
    // Update controller if override used, to reflect current path in UI
    windowManager.setTitle('🍊 $path');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if input is a SQL command (basic heuristic)
      final upperPath = path.trim().toUpperCase();
      if (upperPath.startsWith('SELECT') || 
          upperPath.startsWith('PRAGMA') || 
          upperPath.startsWith('WITH') ||
          upperPath.startsWith('EXPLAIN')) {
         await _executeQuery(path);
         return;
      }

      // First try local if it's a known database extension
      if (path.endsWith('.db') || path.endsWith('.sqlite')) {
        final type = await FileSystemEntity.type(path);
        if (type != FileSystemEntityType.notFound) {
          await _openDatabaseFile(path);
          return;
        }
      }

      // Otherwise, use Banquet Sync (Flight3 server)
      await _handleOfflineAccess(path);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _executeQuery(String sql) async {
    // Determine target DB
    // If we are in "Home" mode, we might want to run against home.sqlite?
    // User requested "Command Palette backend", so maybe.
    // If in "Data" mode, run against current DB.
    
    // We already have a connected DB in _dbService (either Home or Data).
    // So just run it.
    
    setState(() {
       _isLoading = true;
       _gridTitle = "Query Result";
    });
    
    try {
       final results = await _dbService.executeQuery(sql);
       
       if (results.isEmpty) {
          setState(() {
             _gridColumns = [TrinaColumn(field: 'info', title: 'Info', width: 300, type: TrinaColumnType.text(), enableFilterMenuItem: false, enableContextMenu: false)];
             _totalRows = 0;
             _isLoading = false;
             _errorMessage = "Query returned no results.";
          });
       } else {
          _optimizeColumns("Query", results);
          
          // For ad-hoc queries, we serve from memory (results)
          // We need to override _fetchRows to serve this static list
          setState(() {
             _viewType = 2; // Query Mode
             _cachedBanquetRows = results.map((row) {
                 final cells = <String, TrinaCell>{};
                 row.forEach((key, value) {
                    cells[key] = TrinaCell(value: value?.toString() ?? '');
                 });
                 return TrinaRow(cells: cells);
             }).toList();
             _totalRows = results.length;
             _isLoading = false;
          });
       }
    } catch (e) {
       setState(() {
          _isLoading = false;
          _errorMessage = "Query failed: $e";
       });
    }
  }

  Future<void> _pickAndOpenFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite'],
      );

      if (result != null && result.files.single.path != null) {
        await _loadPath(pathOverride: result.files.single.path!);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to pick file: $e";
      });
    }
  }

  Future<void> _openDatabaseFile(String path, {bool isHome = false, String? logicalPath}) async {
    // Only open .db and .sqlite files
    if (!path.endsWith('.db') && !path.endsWith('.sqlite')) {
       throw Exception("Only .db and .sqlite files are supported for local opening.");
    }
    try {
      await _dbService.connect(path);
      
      final tables = await _dbService.getTables();
      
      if (tables.isEmpty && isHome) {
          debugPrint("Home database is empty.");
          // Do not delete. We will attempt to regenerate/fill it if needed, or just show empty.
      }


      setState(() {
        _viewType = isHome ? 0 : 1;
        _isLoading = false;
        // For Home, prefer "2_banquet_links" or "0_quick_links"
        if (isHome) {
            // Prioritize Quick Links (0) so users can see actions [Open, Connect]
            if (tables.contains("0_quick_links")) {
                _currentTableName = "0_quick_links";
            } else if (tables.contains("2_banquet_links")) {
                _currentTableName = "2_banquet_links";
            } else if (tables.isNotEmpty) {
                 _currentTableName = tables.first;
            }
        } else {
            if (tables.isNotEmpty) {
               _currentTableName = tables.first;
            }
        }
      });
      
      if (_currentTableName != null) {
        await _loadTableMetadata(_currentTableName!);
      }
      
      if (!isHome) {
         _recordRecentFile(logicalPath ?? path, path);
      }
    } catch (e) {
       throw Exception("Failed to open database: $e");
    }
  }

  Future<void> _recordRecentFile(String displayPath, String actualFilePath) async {
     if (_homePath == null) return;
     try {
       // Open home db temporarily
       // We use a separate connection to avoid messing with the main view
       final homeDb = await openDatabase(_homePath!);
       
       final fileSizeMb = File(actualFilePath).existsSync() ? (File(actualFilePath).lengthSync() / (1024 * 1024)) : 0.0;
       
       await homeDb.insert('1_recent_files', {
          'filename': p.basename(displayPath),
          'path': displayPath,
          'last_opened': DateTime.now().toIso8601String(),
          'size_mb': fileSizeMb
       }, conflictAlgorithm: ConflictAlgorithm.replace);
       
       await homeDb.close();
     } catch (e) {
       debugPrint("Failed to record recent file: $e");
     }
  }

  Future<void> _loadTableMetadata(String tableName) async {
    setState(() {
       _isLoading = true;
       _gridTitle = tableName;
    });

    try {
      // Get columns
      final result = await _dbService.getTableHeaders(tableName);
      final columns = result.map((colName) => TrinaColumn(
        field: colName,
        title: colName,
        width: 100,
        type: TrinaColumnType.text(),
        enableSorting: true,
        enableFilterMenuItem: false,
        enableContextMenu: false,
        titleRenderer: _buildColumnTitle,
        renderer: (rendererContext) {
           final displayValue = rendererContext.cell.value?.toString() ?? '';
           return CellLinkWidget(
              value: displayValue,
              onNavigate: (path) => _loadPath(pathOverride: path),
              onOpenUrl: (url) => openUrl(url),
           );
        },
      )).toList();

      // Get count
      final count = await _dbService.countRows(tableName);

      setState(() {
        _gridColumns = columns;
        _totalRows = count;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to load table: $e";
      });
    }
  }

  Future<List<TrinaRow>> _fetchRows(int offset) async {
    if (_viewType == 2) {
       // Query Mode (In-Memory)
       if (offset >= _cachedBanquetRows.length) return [];
       return _cachedBanquetRows.skip(offset).take(100).toList();
    }
    // Always fetch from DB now for Home (0) and Data (1)
    return _fetchDatabaseRows(offset);
  }

  Future<List<TrinaRow>> _fetchDatabaseRows(int offset) async {
    if (_currentTableName == null) return [];
    
    try {
      final rowsData = await _dbService.fetchRows(_currentTableName!, limit: 200, offset: offset);
      
      // If this is the initial load (offset 0), we can optimize columns
      if (offset == 0 && rowsData.isNotEmpty) {
        _optimizeColumns(_currentTableName!, rowsData);
      }

      return rowsData.map((row) {
        final cells = <String, TrinaCell>{};
        row.forEach((key, value) {
          String displayValue = value?.toString() ?? '';
          
          final lowerKey = key.toLowerCase();
          if (lowerKey.contains('permission') || lowerKey == 'mode') {
            displayValue = Formatters.formatPermissions(value);
          } else if (lowerKey.contains('date') || lowerKey.contains('created') || lowerKey.contains('updated')) {
            displayValue = Formatters.formatDate(value);
          } else if (lowerKey.contains('time') || lowerKey == 'timestamp') {
            displayValue = Formatters.formatTime(value);
          }
          
          cells[key] = TrinaCell(value: displayValue);
        });
        return TrinaRow(cells: cells);
      }).toList();
    } catch (e) {
      debugPrint('[FlightService] ERROR: $e');
      return [];
    }
  }

  void _optimizeColumns(String tableName, List<Map<String, Object?>> sampleData) {
    if (sampleData.isEmpty) return;

    final List<TrinaColumn> optimizedColumns = [];
    final keys = sampleData.first.keys.toList();

    for (final key in keys) {
      final lengths = <double>[];
      bool isAllNull = true;

      for (final row in sampleData) {
        final value = row[key];
        if (value != null && value.toString().isNotEmpty) {
          isAllNull = false;
          final valStr = value.toString();
          // Rough estimation of width (8.5px per char + padding)
          lengths.add(valStr.length * 8.5 + 0.0); 
        }
      }

      if (!isAllNull) {
        lengths.sort();
        // Use 98% percentile for "tight fit"
        final index = (lengths.length * 0.98).floor();
        double maxWidth = index < lengths.length ? lengths[index] : (lengths.isNotEmpty ? lengths.last : 100.0);
        
        // Ensure some minimums/maximums
        if (maxWidth < 100) maxWidth = 100;
        if (maxWidth > 600) maxWidth = 600;
        
        optimizedColumns.add(TrinaColumn(
          field: key,
          title: key,
          width: maxWidth,
          type: TrinaColumnType.text(),
          enableSorting: true,
          enableFilterMenuItem: false,
          enableContextMenu: false,
          titleRenderer: _buildColumnTitle,
          renderer: (rendererContext) {
             final displayValue = rendererContext.cell.value?.toString() ?? '';
             return CellLinkWidget(
                value: displayValue,
                onNavigate: (path) => _loadPath(pathOverride: path),
                onOpenUrl: (url) => openUrl(url),
             );
          },
        ));
      }
    }

    if (optimizedColumns.isNotEmpty) {
      setState(() {
        _gridColumns = optimizedColumns;
      });
    }
  }
  
  Future<void> _handleOfflineAccess(String banquetPath) async {
    setState(() { _isLoading = true; });
    try {
      final metadata = await _flightService.syncBanquet(banquetPath);
      final serverPath = metadata['server_path'];
      
      if (serverPath == null) throw Exception("Server returned no path");
      
      windowManager.setTitle('🍊 $banquetPath');
      await _openDatabaseFile(serverPath, logicalPath: banquetPath);
    } catch (e) {
      debugPrint("Flight3 sync failed: $e. Falling back to native picker.");
      
      try {
        // Fallback: If server fails, try to open as a local folder using native picker
        String initialDir = banquetPath;
        if (initialDir.startsWith('~')) {
          String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
          if (home != null) {
            initialDir = initialDir.replaceFirst('~', home);
          }
        }

        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['db', 'sqlite'],
          initialDirectory: initialDir,
          dialogTitle: 'Select a Database in $banquetPath',
        );

        if (result != null && result.files.single.path != null) {
          // User picked a file, open it
          final pickedPath = result.files.single.path!;
          _pathController.text = pickedPath; // Update URL bar
          windowManager.setTitle('🍊 $pickedPath');
          await _openDatabaseFile(pickedPath);
          return;
        } else {
          // User cancelled picker
          setState(() {
             _isLoading = false;
             // We don't show an error if they just cancelled the "folder view"
          });
        }
      } catch (pickerError) {
         // If picker also fails (e.g. invalid path for initialDirectory), show original error
          setState(() {
            _isLoading = false;
            _errorMessage = "Sync failed: $e\nFallback failed: $pickerError";
          });
      }
    }
  }

  PlatformMenu _buildPathMenu(String fullPath) {
    if (fullPath.isEmpty) return const PlatformMenu(label: '🍊', menus: []);

    try {
      final b = parseBanquet(fullPath);
      final List<String> paths = [];

      // Add segments based on banquet structure
      if (b.dataSetPath.isNotEmpty) {
        paths.add(b.dataSetPath);
      }
      if (b.table.isNotEmpty) {
        paths.add('${b.dataSetPath};${b.table}');
      }
      if (b.columnPath.isNotEmpty && b.table.isNotEmpty) {
        paths.add('${b.dataSetPath};${b.table};${b.columnPath}');
      } else if (b.columnPath.isNotEmpty) {
        // Flat dataset with column path
        paths.add('${b.dataSetPath};;${b.columnPath}');
      }

      // If no paths found (maybe it's just a raw path), fallback to simple split
      if (paths.isEmpty) {
        List<String> rawSegments = fullPath.split('/').where((s) => s.isNotEmpty).toList();
        String current = fullPath.startsWith('/') ? '/' : '';
        for (int i = 0; i < rawSegments.length; i++) {
          if (i > 0 || (current != '/' && current.isNotEmpty)) current += '/';
          current += rawSegments[i];
          paths.add(current);
        }
      }

      // Reverse (longest to shortest) and cap at 10
      List<String> sortedPaths = paths.reversed.take(10).toList();

      return PlatformMenu(
        label: fullPath,
        menus: sortedPaths.map((p) => PlatformMenuItem(
          label: p,
          onSelected: () {
            _pathController.text = p;
            _loadPath();
          },
        )).toList(),
      );
    } catch (e) {
      debugPrint("Error building path menu with banquet: $e");
      // Fallback to minimal menu
      return PlatformMenu(
        label: fullPath,
        menus: [
          PlatformMenuItem(
            label: fullPath,
            onSelected: () {},
          ),
        ],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: '🍊',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'About Sqliter',
                  onSelected: () {
                    showAboutDialog(
                      context: context,
                      applicationName: '🫐',
                      applicationVersion: '1.0.0',
                    );
                  },
                ),
              ],
            ),
            if (defaultTargetPlatform == TargetPlatform.macOS)
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
          ],
        ),
        PlatformMenu(
          label: '🍎',
          menus: [
            PlatformMenuItem(
              label: 'Open...',
              shortcut: const CharacterActivator('o', meta: true),
              onSelected: _pickAndOpenFile,
            ),
          ],
        ),
        PlatformMenu(
          label: '🍊',
          menus: [
            PlatformMenuItem(
              label: 'Go Home',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true),
              onSelected: () {
                _loadHome();
              },
            ),
            PlatformMenuItem(
              label: 'Toggle Full Screen',
              shortcut: const CharacterActivator('f', meta: true, control: true),
              onSelected: () async {
                bool isFullScreen = await windowManager.isFullScreen();
                if (isFullScreen) {
                  await windowManager.setFullScreen(false);
                } else {
                  await windowManager.setFullScreen(true);
                }
              },
            ),
            PlatformMenuItem(
              label: 'Maximize Window',
              shortcut: const CharacterActivator('m', meta: true, control: true),
              onSelected: () async {
                  await windowManager.maximize();
              },
            ),
          ],
        ),
        if (_pathController.text.isNotEmpty)
          _buildPathMenu(_pathController.text),
      ],
      child: MacosWindow(
        child: MacosScaffold(
        toolBar: buildBanquetBar(
          context: context,
          pathController: _pathController,
          flightService: _flightService,
          onHomeTap: () {
            _loadHome();
          },
          onNavigate: (path) {
            _pathController.text = path;
            _loadPath();
          },
          tileMode: _tileMode,
          onToggleTile: (_gridColumns.isNotEmpty)
              ? () {
                  // Toggle by appending/removing #tile from the current path
                  final cur = _pathController.text.replaceAll('#tile', '').trim();
                  final next = _tileMode ? cur : '$cur#tile';
                  _pathController.text = next;
                  setState(() => _tileMode = !_tileMode);
                }
              : null,
      ),
      children: [
        ContentArea(
          builder: (context, scrollController) {
             if (_errorMessage != null) {
                return _buildErrorView();
             }
             
             if (_isLoading) {
               return const Center(child: ProgressCircle());
             }
             
             // UNIFIED GRID VIEW
             return Material(
               color: Colors.transparent,
               child: _tileMode
                   ? TileView(
                       key: ValueKey('tile_$_gridTitle'),
                       columns: _gridColumns,
                       onFetchRows: _fetchRows,
                       totalRows: _totalRows,
                       onNavigate: (path) => _loadPath(pathOverride: path),
                     )
                   : DatabaseGridView(
                       key: _gridKey,
                       columns: _gridColumns,
                       tableName: _gridTitle,
                       totalRows: _totalRows,
                       onFetchRows: _fetchRows,
                       onCellNavigate: (value) {
                         _loadPath(pathOverride: value);
                       },
                       onRowDoubleTap: (row) {
                    // Interaction Logic
                    if (_viewType == 0) { // Home Mode
                        if (_currentTableName == "2_banquet_links") {
                            final path = row.cells['original_url']?.value?.toString();
                            if (path != null) {
                               _loadPath(pathOverride: path);
                            }
                        } else if (_currentTableName == "0_quick_links") {
                            final action = row.cells['action']?.value?.toString();
                            if (action == 'open_file') {
                                _pickAndOpenFile();
                            } else if (action == 'new_query') {
                                setState(() {
                                   _viewType = 2;
                                   _gridTitle = "New Query";
                                   _cachedBanquetRows = [];
                                   _totalRows = 0;
                                });
                            }
                        } else if (_currentTableName == "1_recent_files") {
                            final path = row.cells['path']?.value?.toString();
                            if (path != null) {
                               _loadPath(pathOverride: path);
                            }
                        } else if (_currentTableName == "3_query_styles") {
                            final sql = row.cells['sql']?.value?.toString();
                            if (sql != null) {
                               Clipboard.setData(ClipboardData(text: sql));
                               // Optional: Show a toast/snackbar? 
                               // For now, maybe just flash the title?
                               final oldTitle = _gridTitle;
                               setState(() => _gridTitle = "Copied to Clipboard!");
                               Future.delayed(const Duration(seconds: 1), () {
                                  if (mounted) setState(() => _gridTitle = oldTitle);
                               });
                            }
                        }
                    }
                 },
               ),
             );
          },
        ),
      ],
    ),
   ),
  );
 }
  
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle, size: 64, color: MacosColors.systemRedColor),
          const SizedBox(height: 0),
          Text(
            'Error',
             style: MacosTheme.of(context).typography.title1.copyWith(color: MacosColors.systemRedColor),
          ),
          const SizedBox(height: 0),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 0),
          PushButton(
             controlSize: ControlSize.large,
             onPressed: () {
               _loadHome();
             }, 
             child: const Text('Go Home')
          ),
        ],
      ),
    );
  }
}
