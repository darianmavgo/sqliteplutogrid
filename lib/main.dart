import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: depend_on_referenced_packages
import 'package:pocketbase/pocketbase.dart'; 
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';

import 'db_service.dart';
import 'flight_service.dart';
import 'models/view_mode.dart';
import 'utils/formatters.dart';

import 'widgets/app_toolbar.dart';
import 'widgets/database_grid_view.dart';
import 'widgets/flight_banquet_view.dart';

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
      home: const DBViewerPage(),
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
  // Services
  late final DatabaseService _dbService;
  late final FlightService _flightService;

  // State
  ViewMode _currentMode = ViewMode.flight;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isFlightConnected = false;
  
  // Controller
  final TextEditingController _pathController = TextEditingController();

  // Data
  final GlobalKey _gridKey = GlobalKey(); // To trigger grid reloads
  List<TrinaRow> _flightRows = [];
  List<String> _tables = [];
  String? _selectedTable;
  List<TrinaColumn> _dbColumns = [];
  int? _totalRows; // Total rows in current table
  String? _converterEmoji;
  List<RecordModel> _queryStyles = [];

  @override
  void initState() {
    super.initState();
    
    // Initialize services
    _flightService = widget.flightService ?? FlightService();
    _dbService = widget.dbService ?? DatabaseService();
    
    
    
    // Perform async initialization
    _initServices();
    
    // Initial checks
    _autoConnectFlight();
  }

  Future<void> _initServices() async {
    // Initialize services if needed
  }
  
  Future<void> _autoConnectFlight() async {
     try {
       // Simple health check or just assume connected if URL is set
       // For now, no-op or check status endpoint if available
       setState(() {
         _isFlightConnected = true; 
       });
     
     // Load query styles
     _queryStyles = await _flightService.getQueryStyles();
     
   } catch (e) {
       debugPrint("Flight auto-connect failed: $e");
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
    final path = pathOverride ?? _pathController.text.trim();
    if (path.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _tables.clear();
      _selectedTable = null;
      _dbColumns.clear();
      _totalRows = null;
      _converterEmoji = null;
    });

    try {
      // First try local if it's a known database extension
      if (path.endsWith('.db') || path.endsWith('.sqlite')) {
        final type = await FileSystemEntity.type(path);
        if (type != FileSystemEntityType.notFound) {
          await _openDatabaseFile(path);
          return;
        }
      }

      // Otherwise, use Banquet Sync (Flight3 server)
      // This handles directories, non-sqlite files (conversion), and remote banquet URLs
      await _handleOfflineAccess(path);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
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

  Future<void> _openDatabaseFile(String path) async {
    // Only open .db and .sqlite files
    if (!path.endsWith('.db') && !path.endsWith('.sqlite')) {
       throw Exception("Only .db and .sqlite files are supported for local opening. Use Flight for other formats.");
    }
    try {
      await _dbService.connect(path);
      
      final tables = await _dbService.getTables();
      final userVersion = await _dbService.getUserVersion();
      final emoji = Formatters.getConverterEmoji(userVersion);
      
      setState(() {
        _currentMode = ViewMode.database;
        _tables = tables;
        _isLoading = false;
        _converterEmoji = emoji;
        if (tables.isNotEmpty) {
           _selectedTable = tables.first;
        }
      });
      
      if (_selectedTable != null) {
        await _loadTableMetadata(_selectedTable!);
      }
    } catch (e) {
       throw Exception("Failed to open database: $e");
    }
  }

  Future<void> _loadTableMetadata(String tableName) async {
    setState(() {
       _isLoading = true;
       // Don't clear tables/etc, just reloading view
    });

    try {
      // Get columns
      final result = await _dbService.getTableHeaders(tableName);
      final columns = result.map((colName) => TrinaColumn(
        field: colName,
        title: colName,
        width: 100, // Default width
        type: TrinaColumnType.text(),
      )).toList();

      // Get count
      final count = await _dbService.countRows(tableName);

      // Apply query style defaults if any
      final style = _queryStyles.firstWhere(
        (s) => s.data['style_name'] == 'sqlite', 
        orElse: () => RecordModel()
      );
      
      if (style.id.isNotEmpty) {
        // Apply limit from style if needed, or stick to 200
        // For now just ensuring it doesn't crash
      }

      setState(() {
        _dbColumns = columns;
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

  Future<List<TrinaRow>> _fetchDatabaseRows(int offset) async {
    if (_selectedTable == null) return [];
    
    try {
      final rowsData = await _dbService.fetchRows(_selectedTable!, limit: 200, offset: offset);
      
      // If this is the initial load (offset 0), we can optimize columns
      if (offset == 0 && rowsData.isNotEmpty) {
        _optimizeColumns(_selectedTable!, rowsData);
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
          lengths.add(valStr.length * 8.5 + 32.0); 
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
        ));
      }
    }

    if (optimizedColumns.isNotEmpty) {
      setState(() {
        _dbColumns = optimizedColumns;
      });
    }
  }
  
  // ---------------------------------------------------------------------------
  // Remote / Flight Logic
  // ---------------------------------------------------------------------------
  
  Future<void> _connectToFlight() async {
     setState(() {
       _currentMode = ViewMode.flight;
       _isLoading = true;
       _errorMessage = null;
     });
     
     // Load banquet links
     try {
       final links = await _flightService.getBanquetLinks();
        setState(() {
           _flightRows = links.map((record) {
             final path = record.data['original_url'] ?? '';
             final desc = record.data['description'] ?? '';
             final isFolder = desc.toLowerCase().contains('folder') || !path.contains('.');
             final displayPath = isFolder ? '📁 $path' : '📄 $path';
             
             return TrinaRow(
                cells: {
                  'id': TrinaCell(value: record.id),
                  'path': TrinaCell(value: displayPath),
                  'raw_path': TrinaCell(value: path),
                  'desc': TrinaCell(value: record.data['description'] ?? ''),
                  'original_url': TrinaCell(value: record.data['original_url'] ?? ''),
                }
             );
           }).toList();
           _isLoading = false;
           _isFlightConnected = true;
        });
     } catch (e) {
       setState(() {
         _isLoading = false;
         _errorMessage = "Failed to connect to Flight: $e";
       });
     }
  }

  Future<void> _showPower2Analysis() async {
    if (_selectedTable == null) return;
    
    setState(() { _isLoading = true; });
    try {
      final samples = await _dbService.fetchPower2Samples(_selectedTable!);
      setState(() { _isLoading = false; });
      
      if (!mounted) return;
      
      final sampleText = samples.isEmpty 
          ? 'No rows found for sampling.'
          : samples.asMap().entries.map((e) {
              final row = e.value;
              final rowId = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512][e.key];
              // Pick first 3 keys to show
              final keys = row.keys.take(3).toList();
              final values = keys.map((k) => '$k: ${row[k]}').join(', ');
              return 'Row $rowId: $values';
            }).join('\n');

      showMacosAlertDialog(
        context: context,
        builder: (context) => MacosAlertDialog(
          appIcon: const Icon(CupertinoIcons.bolt_fill, size: 64, color: MacosColors.systemYellowColor),
          title: const Text('Power2 Analysis'),
          message: SingleChildScrollView(
            child: Text(
              'Sampling ${_selectedTable!} at powers of 2:\n\n$sampleText',
              style: MacosTheme.of(context).typography.caption1,
            ),
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Analysis failed: $e";
      });
    }
  }

  Future<void> _handleOfflineAccess(String banquetPath) async {
    setState(() { _isLoading = true; });
    try {
      final metadata = await _flightService.syncBanquet(banquetPath);
      final serverPath = metadata['server_path'];
      
      if (serverPath == null) throw Exception("Server returned no path");
      
      // If needed, download logic here. For now assume local path if simple.
      // Actually syncBanquet returns where it is on server.
      // Client needs to access it via /sqliter/file/ proxy or similar?
      // Or maybe _openDatabaseFile works if it's a local path relative to something?
      // Original logic implies downloading.
      
      // Simulating "Done" for now as we don't have download logic fully extracted
      _pathController.text = serverPath;
      await _openDatabaseFile(serverPath);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Sync failed: $e";
      });
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
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'Open...',
              shortcut: const CharacterActivator('o', meta: true),
              onSelected: _pickAndOpenFile,
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: 'Go Home',
              shortcut: const CharacterActivator('h', meta: true),
              onSelected: () {
                setState(() {
                  _currentMode = ViewMode.flight;
                  _pathController.clear();
                });
              },
            ),
            PlatformMenuItem(
              label: 'Flight Server',
              shortcut: const CharacterActivator('f', meta: true),
              onSelected: _connectToFlight,
            ),
          ],
        ),
      ],
      child: MacosWindow(
        child: MacosScaffold(
        toolBar: buildAppToolbar(
        context: context,
        currentMode: _currentMode,
        isFlightConnected: _isFlightConnected,
        isLoading: _isLoading,
        pathController: _pathController,
        flightService: _flightService,
        tables: _tables,
        selectedTable: _selectedTable,
        totalRows: _totalRows,
        converterEmoji: _converterEmoji,
        onPower2: _showPower2Analysis,
        onHomeTap: () {
          setState(() {
            _currentMode = ViewMode.flight;
            _isLoading = false;
            _errorMessage = null;
            _pathController.clear();
          });
        },
        onNavigate: (path) {
          _pathController.text = path;
          _loadPath();
        },
        onConnectFlight: _connectToFlight,
        onTableChanged: (val) {
           setState(() {
             _selectedTable = val;
           });
           _loadTableMetadata(val);
        },
        onExportCsv: () {
           // Handled inside GridView via callback if needed, but here we pass totalRows?
           // DatabaseGridView now handles export internally via button.
           // So this callback might be redundant if the button is inside the grid view only.
           // But AppToolbar might have an export button too?
           // The extraction put buttons in Toolbar AND Grid stats header.
           // If Toolbar button is pressed, we need a GlobalKey<DatabaseGridViewState> maybe?
        },
        onJumpToRow: () {
           // Same as export
        },
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
             
             switch (_currentMode) {
               case ViewMode.database:
                 return DatabaseGridView(
                   key: _gridKey,
                   columns: _dbColumns,
                   tableName: _selectedTable,
                   totalRows: _totalRows,
                   onFetchRows: _fetchDatabaseRows,
                 );
                 
               case ViewMode.flight:
                 return FlightBanquetView(
                   rows: _flightRows,
                   onRowDoubleTap: (row) {
                      final path = row.cells['path']?.value;
                      if (path != null) {
                         _pathController.text = path.toString();
                         _loadPath(); // Use centralized loadPath
                      }
                   },
                 );
             }
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
          const SizedBox(height: 24),
          Text(
            'Error',
             style: MacosTheme.of(context).typography.title1.copyWith(color: MacosColors.systemRedColor),
          ),
          const SizedBox(height: 16),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 16),
          PushButton(
             controlSize: ControlSize.large,
             onPressed: () {
               setState(() { _errorMessage = null; _currentMode = ViewMode.flight; });
             }, 
             child: const Text('Go Home')
          ),
        ],
      ),
    );
  }
}
