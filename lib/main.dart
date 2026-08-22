import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'db_service.dart';
import 'flight_service.dart';
import 'utils/formatters.dart';
import 'utils/cell_link_renderer.dart';

import 'widgets/banquet_bar.dart';
import 'widgets/database_grid_view.dart';
import 'widgets/tile_view.dart';
import 'widgets/schema_sidebar.dart';
import 'widgets/table_filter_bar.dart';
import 'widgets/schema_inspector_view.dart';
import 'widgets/sql_editor_view.dart';
import 'widgets/table_status_footer.dart';
import 'widgets/cell_inspector_dialog.dart';

/// Global schema type cache for column header rendering
final Map<String, ColumnInfo> _globalColumnSchemas = {};

/// Custom column title renderer with sort indicator, column type pill, and PK badge
Widget _buildColumnTitle(TrinaColumnTitleRendererContext ctx) {
  final col = ctx.column;
  String sortIcon = '';
  if (col.sort.isAscending) sortIcon = ' ↑';
  if (col.sort.isDescending) sortIcon = ' ↓';

  return GestureDetector(
    onTap: () {
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
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ),
        if (ctx.showContextIcon) ctx.contextMenuIcon,
      ],
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MyApp());
  
  const statusFilePath = String.fromEnvironment('STATUS_FILE_PATH');
  if (statusFilePath.isNotEmpty) {
     try {
       await File(statusFilePath).writeAsString('Window Initialized at ${DateTime.now()}');
     } catch (e) {
       debugPrint('Failed to write status file: $e');
     }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: '🍊 Sqliter',
      themeMode: ThemeMode.dark,
      darkTheme: MacosThemeData.dark(),
      theme: MacosThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          final data = MediaQuery.of(context);
          return MediaQuery(
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

enum AppTab { data, schema, sqlEditor }

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

  late final DatabaseService _dbService;
  late final FlightService _flightService;

  bool _isLoading = false;
  String? _errorMessage;
  bool _showSidebar = true;
  AppTab _selectedTab = AppTab.data;
  int? _lastQueryDurationMs;
  
  String _activeFilterText = '';
  String? _activeFilterColumn;
  
  final TextEditingController _pathController = TextEditingController();
  final GlobalKey _gridKey = GlobalKey();
  TrinaGridStateManager? _gridStateManager;
  
  List<TableSummary> _tables = [];
  List<TrinaColumn> _gridColumns = [];
  String? _gridTitle;
  int? _totalRows;
  String? _homePath;
  String? _currentConnectedPath;
  
  int _viewType = 0; 
  String? _currentTableName;
  final List<TrinaRow> _cachedBanquetRows = [];
  bool _tileMode = false;

  @override
  void initState() {
    super.initState();
    
    _flightService = widget.flightService ?? FlightService();
    _dbService = widget.dbService ?? DatabaseService();
    
    _fileOpenChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened') {
        final String path = call.arguments;
        _loadPath(pathOverride: path);
      }
    });

    _startCommandFileWatcher();
    _checkPendingFile();
  }

  Timer? _commandWatcherTimer;
  String _lastProcessedCommand = '';

  void _startCommandFileWatcher() {
    _commandWatcherTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      try {
        final cmdFile = File('/tmp/sqliter_command.txt');
        if (cmdFile.existsSync()) {
          final content = cmdFile.readAsStringSync().trim();
          if (content.isNotEmpty && content != _lastProcessedCommand) {
            _lastProcessedCommand = content;
            debugPrint('[Sqliter Command Trigger] Executing: $content');
            await _loadPath(pathOverride: content);
          }
        }
      } catch (e) {
        debugPrint('[Sqliter Command Watcher Error] $e');
      }
    });
  }

  Future<void> _checkPendingFile() async {
    try {
      final String? pendingPath = await _fileOpenChannel.invokeMethod('getPendingFile');
      if (pendingPath != null && pendingPath.isNotEmpty) {
        await _loadPath(pathOverride: pendingPath);
        return;
      }
    } catch (e) {
      debugPrint('Failed to get pending file: $e');
    }

    if (widget.dbService == null) {
      const defaultHeavyDb = '/Users/darianhickman/Documents/sqliteplutogrid/test_databases/heavy_5mb.sqlite';
      if (File(defaultHeavyDb).existsSync()) {
        await _loadPath(pathOverride: defaultHeavyDb);
        return;
      }
    }

    await _loadHome();
  }
  
  Future<void> _loadHome() async {
     windowManager.setTitle('🍊 Sqliter');
     setState(() {
       _isLoading = true;
       _errorMessage = null;
       _viewType = 0;
       _tileMode = false;
       _selectedTab = AppTab.data;
       _activeFilterText = '';
       _activeFilterColumn = null;
       _pathController.clear();
     });
     
     try {
       final homePath = await _flightService.getHomeDatabasePath();
       _homePath = homePath;
       await _openDatabaseFile(homePath, isHome: true);
     } catch (e) {
       if (e.toString().contains("Home database was empty")) {
           debugPrint("Retrying home load after repair...");
           if (mounted) {
              Future.delayed(const Duration(milliseconds: 500), () => _loadHome());
           }
           return;
       }
       if (!mounted) return;
       setState(() {
         _isLoading = false;
         _errorMessage = "Failed to load home: $e";
       });
     }
  }

  @override
  void dispose() {
    _commandWatcherTimer?.cancel();
    if (widget.dbService == null) {
      _dbService.close();
    }
    _pathController.dispose();
    super.dispose();
  }

  Future<void> loadPathDirect(String path) => _loadPath(pathOverride: path);
  Future<void> selectTableDirect(String tableName) => _loadTableMetadata(tableName);

  Future<void> _loadPath({String? pathOverride}) async {
    final rawPath = pathOverride ?? _pathController.text.trim();
    if (rawPath.isEmpty) return;

    final hasTile = rawPath.contains('#tile');
    final path = rawPath.replaceAll('#tile', '').trim();

    final displayPath = hasTile ? '$path#tile' : path;
    if (pathOverride != null) {
      _pathController.text = displayPath;
    }

    setState(() {
      _tileMode = hasTile;
      _activeFilterText = '';
      _activeFilterColumn = null;
    });

    if (path.isEmpty) return;
    
    windowManager.setTitle('🍊 $path');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var cleanPath = Uri.decodeFull(path.trim());
      if ((cleanPath.startsWith('"') && cleanPath.endsWith('"')) || (cleanPath.startsWith("'") && cleanPath.endsWith("'"))) {
        cleanPath = cleanPath.substring(1, cleanPath.length - 1).trim();
      }
      debugPrint('[Sqliter Troubleshooting] Loading path: $cleanPath');

      final upperPath = cleanPath.trim().toUpperCase();
      if (upperPath.startsWith('SELECT') || 
          upperPath.startsWith('PRAGMA') || 
          upperPath.startsWith('WITH') ||
          upperPath.startsWith('EXPLAIN')) {
         setState(() {
           _selectedTab = AppTab.sqlEditor;
           _isLoading = false;
         });
         return;
      }

      String localDbPath = cleanPath;
      String? targetTable;
      if (cleanPath.contains(';')) {
        final parts = cleanPath.split(';');
        localDbPath = parts[0].trim();
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          targetTable = parts[1].trim();
        }
      }

      final lowerPath = localDbPath.toLowerCase();
      final isDbExt = lowerPath.endsWith('.db') || lowerPath.endsWith('.sqlite') || lowerPath.endsWith('.sqlite3');

      if (isDbExt) {
        String? resolvedPath;
        if (File(localDbPath).existsSync()) {
          resolvedPath = File(localDbPath).absolute.path;
        } else if (localDbPath.startsWith('~/')) {
          final home = Platform.environment['HOME'] ?? '';
          final expanded = p.join(home, localDbPath.substring(2));
          if (File(expanded).existsSync()) {
            resolvedPath = expanded;
          }
        } else if (File(p.join(Directory.current.path, localDbPath)).existsSync()) {
          resolvedPath = p.join(Directory.current.path, localDbPath);
        }

        if (resolvedPath != null) {
          debugPrint('[Sqliter Troubleshooting] Resolved database path: $resolvedPath');
          await _openDatabaseFile(resolvedPath, targetTable: targetTable);
          return;
        } else {
          debugPrint('[Sqliter Troubleshooting] File not found: $localDbPath');
          _showErrorDialog("Database file not found:\n$localDbPath\n\nTip: Use ⌘O to pick the file in Finder.");
          setState(() { _isLoading = false; });
          return;
        }
      }

      if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
        await _handleOfflineAccess(cleanPath);
        return;
      }

      await _handleOfflineAccess(cleanPath);
    } catch (e) {
      debugPrint('[Sqliter Troubleshooting] Exception in _loadPath: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Text('🍊', style: TextStyle(fontSize: 32)),
        title: const Text('Notice'),
        message: Text(message),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('OK'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _pickAndOpenFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite', 'sqlite3'],
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

  Future<void> _openDatabaseFile(String path, {bool isHome = false, String? logicalPath, String? targetTable}) async {
    final lowerPath = path.toLowerCase();
    if (!lowerPath.endsWith('.db') && !lowerPath.endsWith('.sqlite') && !lowerPath.endsWith('.sqlite3')) {
       throw Exception("Only .db, .sqlite, and .sqlite3 files are supported for local opening.");
    }
    try {
      await _dbService.connect(path);
      _currentConnectedPath = path;
      
      final tables = await _dbService.getTableSummaries();
      
      if (tables.isEmpty) {
        if (!mounted) return;
        setState(() {
          _viewType = isHome ? 0 : 1;
          _isLoading = false;
          _currentTableName = null;
          _tables = [];
          _gridTitle = p.basename(path);
          _gridColumns = [];
          _totalRows = 0;
          _errorMessage = "Database '${p.basename(path)}' opened, but contains no tables.";
        });
        if (!isHome) {
          _recordRecentFile(logicalPath ?? path, path);
        }
        return;
      }

      String? tableToSelect;
      final tableNames = tables.map((t) => t.name).toList();

      if (targetTable != null && tableNames.contains(targetTable)) {
        tableToSelect = targetTable;
      } else if (isHome) {
        if (tableNames.contains("0_quick_links")) {
          tableToSelect = "0_quick_links";
        } else if (tableNames.contains("2_banquet_links")) {
          tableToSelect = "2_banquet_links";
        } else if (tableNames.isNotEmpty) {
          tableToSelect = tableNames.first;
        }
      } else {
        tableToSelect = tableNames.first;
      }

      if (!mounted) return;
      setState(() {
        _viewType = isHome ? 0 : 1;
        _tables = tables;
        _currentTableName = tableToSelect;
        _selectedTab = AppTab.data;
        _errorMessage = null;
      });
      debugPrint('[Sqliter Troubleshooting] Successfully connected to $path. Found ${tables.length} tables: ${tableNames.join(", ")}. Selected table: $tableToSelect');
      
      if (tableToSelect != null) {
        await _loadTableMetadata(tableToSelect);
      }
      
      if (!isHome) {
         _recordRecentFile(logicalPath ?? path, path);
      }
    } catch (e) {
       debugPrint('[Sqliter Troubleshooting] Error opening database $path: $e');
       throw Exception("Failed to open database: $e");
    }
  }

  Future<void> _recordRecentFile(String displayPath, String actualFilePath) async {
     if (_homePath == null) return;
     try {
       final homeDb = await databaseFactory.openDatabase(_homePath!);
       await homeDb.execute('''
         CREATE TABLE IF NOT EXISTS "1_recent_files" (
           filename TEXT,
           path TEXT PRIMARY KEY,
           last_opened TEXT,
           size_mb REAL
         );
       ''');
       final fileSizeMb = File(actualFilePath).existsSync() ? (File(actualFilePath).lengthSync() / (1024 * 1024)) : 0.0;
       
       await homeDb.rawInsert(
         'INSERT OR REPLACE INTO "1_recent_files" (filename, path, last_opened, size_mb) VALUES (?, ?, ?, ?)',
         [p.basename(displayPath), displayPath, DateTime.now().toIso8601String(), fileSizeMb],
       );
       
       await homeDb.close();
     } catch (e) {
       debugPrint("Failed to record recent file: $e");
     }
  }

  Future<void> _loadTableMetadata(String tableName) async {
    setState(() {
       _isLoading = true;
       _gridTitle = tableName;
       _currentTableName = tableName;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final headers = await _dbService.getTableHeaders(tableName);
      final cleanHeaders = headers.map((h) => h.replaceAll('<', '').replaceAll('>', '')).toList();

      // Load column schemas to populate types and PKs
      try {
        final schemaCols = await _dbService.getTableSchema(tableName);
        _globalColumnSchemas.clear();
        for (final col in schemaCols) {
          _globalColumnSchemas[col.name] = col;
        }
      } catch (_) {}

      final columns = cleanHeaders.map((colName) => TrinaColumn(
        field: colName,
        title: colName,
        width: 120,
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

      final count = await _dbService.countRows(
        tableName,
        filterColumn: _activeFilterColumn,
        filterText: _activeFilterText,
      );

      stopwatch.stop();

      if (!mounted) return;
      setState(() {
        _gridColumns = columns;
        _totalRows = count;
        _lastQueryDurationMs = stopwatch.elapsedMilliseconds;
        _isLoading = false;
        _errorMessage = null;
      });
      debugPrint('[Sqliter Troubleshooting] Table $tableName loaded: ${columns.length} columns, $count rows in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      stopwatch.stop();
      debugPrint('[Sqliter Troubleshooting] Failed to load table $tableName: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to load table: $e";
      });
    }
  }

  Future<List<TrinaRow>> _fetchRows(int offset) async {
    if (_viewType == 2) {
       if (offset >= _cachedBanquetRows.length) return [];
       return _cachedBanquetRows.skip(offset).take(100).toList();
    }
    return _fetchDatabaseRows(offset);
  }

  Future<List<TrinaRow>> _fetchDatabaseRows(int offset) async {
    if (_currentTableName == null) return [];
    
    try {
      final rowsData = await _dbService.fetchRows(
        _currentTableName!,
        limit: 200,
        offset: offset,
        filterColumn: _activeFilterColumn,
        filterText: _activeFilterText,
      );
      
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
          
          final cleanKey = key.replaceAll('<', '').replaceAll('>', '');
          cells[cleanKey] = TrinaCell(value: displayValue);
        });
        return TrinaRow(cells: cells);
      }).toList();
    } catch (e) {
      debugPrint('[DatabaseService] ERROR: $e');
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
          lengths.add(valStr.length * 8.5 + 0.0); 
        }
      }

      if (!isAllNull) {
        lengths.sort();
        final index = (lengths.length * 0.98).floor();
        double maxWidth = index < lengths.length ? lengths[index] : (lengths.isNotEmpty ? lengths.last : 100.0);
        
        if (maxWidth < 100) maxWidth = 100;
        if (maxWidth > 600) maxWidth = 600;
        
        final cleanKey = key.replaceAll('<', '').replaceAll('>', '');

        optimizedColumns.add(TrinaColumn(
          field: cleanKey,
          title: cleanKey,
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
      debugPrint("Banquet sync fallback to picker: $e");
      
      try {
        String initialDir = banquetPath;
        if (initialDir.startsWith('~')) {
          String? home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
          if (home != null) {
            initialDir = initialDir.replaceFirst('~', home);
          }
        }

        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['db', 'sqlite', 'sqlite3'],
          initialDirectory: initialDir,
          dialogTitle: 'Select a Database',
        );

        if (result != null && result.files.single.path != null) {
          final pickedPath = result.files.single.path!;
          _pathController.text = pickedPath;
          windowManager.setTitle('🍊 $pickedPath');
          await _openDatabaseFile(pickedPath);
          return;
        } else {
          setState(() { _isLoading = false; });
        }
      } catch (pickerError) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Sync failed: $e\nFallback failed: $pickerError";
          });
      }
    }
  }

  void _onFilterChanged(({String? column, String text}) filter) async {
    setState(() {
      _activeFilterColumn = filter.column;
      _activeFilterText = filter.text;
    });
    if (_currentTableName != null) {
      await _loadTableMetadata(_currentTableName!);
    }
  }

  void _autoFitAllColumns() {
    final sm = _gridStateManager;
    if (sm != null && mounted) {
      for (final col in sm.columns) {
        sm.autoFitColumn(context, col);
      }
    }
  }

  void _inspectCell(TrinaRow row) {
    if (row.cells.isEmpty) return;
    final firstKey = row.cells.keys.first;
    final firstValue = row.cells[firstKey]?.value?.toString();
    final colInfo = _globalColumnSchemas[firstKey];

    CellInspectorDialog.show(
      context,
      columnName: firstKey,
      cellValue: firstValue,
      columnType: colInfo?.type,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

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
                      applicationName: '🍊 Sqliter',
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
              label: 'Open Database...',
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
              onSelected: _loadHome,
            ),
            PlatformMenuItem(
              label: 'Refresh',
              shortcut: const CharacterActivator('r', meta: true),
              onSelected: () {
                if (_currentTableName != null) {
                  _loadTableMetadata(_currentTableName!);
                }
              },
            ),
            PlatformMenuItem(
              label: 'Data Grid View',
              shortcut: const CharacterActivator('1', meta: true),
              onSelected: () => setState(() => _selectedTab = AppTab.data),
            ),
            PlatformMenuItem(
              label: 'Schema Inspector',
              shortcut: const CharacterActivator('2', meta: true),
              onSelected: () => setState(() => _selectedTab = AppTab.schema),
            ),
            PlatformMenuItem(
              label: 'SQL Editor',
              shortcut: const CharacterActivator('3', meta: true),
              onSelected: () => setState(() => _selectedTab = AppTab.sqlEditor),
            ),
            PlatformMenuItem(
              label: 'Toggle Sidebar',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
              onSelected: () {
                setState(() => _showSidebar = !_showSidebar);
              },
            ),
            PlatformMenuItem(
              label: 'Toggle Full Screen',
              shortcut: const CharacterActivator('f', meta: true, control: true),
              onSelected: () async {
                bool isFullScreen = await windowManager.isFullScreen();
                await windowManager.setFullScreen(!isFullScreen);
              },
            ),
            PlatformMenuItem(
              label: 'Maximize Window',
              shortcut: const CharacterActivator('m', meta: true, control: true),
              onSelected: () async => await windowManager.maximize(),
            ),
          ],
        ),
      ],
      child: MacosWindow(
        child: MacosScaffold(
          toolBar: buildBanquetBar(
            context: context,
            pathController: _pathController,
            flightService: _flightService,
            onHomeTap: _loadHome,
            onNavigate: (path) {
              _pathController.text = path;
              _loadPath();
            },
            tileMode: _tileMode,
            onToggleTile: (_gridColumns.isNotEmpty)
                ? () {
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

                return Row(
                  children: [
                    if (_showSidebar)
                      SchemaSidebar(
                        tables: _tables,
                        selectedTable: _currentTableName,
                        dbPath: _currentConnectedPath,
                        isLoading: _isLoading,
                        onSelectTable: (tableName) {
                          setState(() {
                            _selectedTab = AppTab.data;
                            _activeFilterText = '';
                            _activeFilterColumn = null;
                          });
                          _loadTableMetadata(tableName);
                        },
                        onRefresh: () async {
                          if (_currentConnectedPath != null) {
                            await _openDatabaseFile(_currentConnectedPath!, targetTable: _currentTableName);
                          }
                        },
                        onOpenNewDb: _pickAndOpenFile,
                      ),

                    Expanded(
                      child: Column(
                        children: [
                          _buildTopTabBar(theme),
                          Expanded(
                            child: _buildActiveTabContent(theme),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTabBar(MacosThemeData theme) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: _showSidebar ? 'Hide Sidebar (⌘⇧S)' : 'Show Sidebar (⌘⇧S)',
              child: MacosIconButton(
                padding: const EdgeInsets.all(4),
                icon: Icon(
                  CupertinoIcons.sidebar_left,
                  size: 16,
                  color: _showSidebar ? MacosColors.systemOrangeColor : null,
                ),
                onPressed: () {
                  setState(() => _showSidebar = !_showSidebar);
                },
              ),
            ),
            const SizedBox(width: 8),

            _buildTabButton(AppTab.data, 'Data Grid (⌘1)', CupertinoIcons.table, theme),
            const SizedBox(width: 4),
            _buildTabButton(AppTab.schema, 'Schema (⌘2)', CupertinoIcons.square_stack_3d_up, theme),
            const SizedBox(width: 4),
            _buildTabButton(AppTab.sqlEditor, 'SQL Editor (⌘3)', CupertinoIcons.chevron_left_slash_chevron_right, theme),

            const SizedBox(width: 16),

            if (_currentTableName != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.table, size: 12, color: MacosColors.systemOrangeColor),
                    const SizedBox(width: 6),
                    Text(
                      _currentTableName!,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(AppTab tab, String label, IconData icon, MacosThemeData theme) {
    final isSelected = _selectedTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: isSelected
              ? Border.all(color: theme.primaryColor.withValues(alpha: 0.3), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? MacosColors.systemOrangeColor : theme.typography.body.color?.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? theme.typography.headline.color : theme.typography.body.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(MacosThemeData theme) {
    if (_isLoading) {
      return const Center(child: ProgressCircle());
    }

    switch (_selectedTab) {
      case AppTab.schema:
        if (_currentTableName == null) {
          return const Center(child: Text('Select a table to view schema.'));
        }
        return SchemaInspectorView(
          dbService: _dbService,
          tableName: _currentTableName!,
        );

      case AppTab.sqlEditor:
        return SqlEditorView(
          dbService: _dbService,
          currentTableName: _currentTableName,
          initialQuery: _currentTableName != null
              ? 'SELECT * FROM "${_currentTableName!}" LIMIT 100;'
              : 'SELECT * FROM sqlite_master LIMIT 50;',
        );

      case AppTab.data:
        return Column(
          children: [
            if (_gridColumns.isNotEmpty)
              TableFilterBar(
                columns: _gridColumns.map((c) => c.title).toList(),
                selectedColumn: _activeFilterColumn,
                currentFilter: _activeFilterText,
                totalRows: _totalRows ?? 0,
                loadedRows: _gridColumns.length,
                onFilterChanged: _onFilterChanged,
                onRefresh: () {
                  if (_currentTableName != null) {
                    _loadTableMetadata(_currentTableName!);
                  }
                },
                onAutoFit: _autoFitAllColumns,
              ),

            Expanded(
              child: Material(
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
                        onStateManagerCreated: (sm) => _gridStateManager = sm,
                        onCellNavigate: (value) {
                          _loadPath(pathOverride: value);
                        },
                        onRowDoubleTap: (row) {
                          if (_viewType == 0) {
                            if (_currentTableName == "2_banquet_links") {
                              final path = row.cells['original_url']?.value?.toString();
                              if (path != null) _loadPath(pathOverride: path);
                            } else if (_currentTableName == "0_quick_links") {
                              final action = row.cells['action']?.value?.toString();
                              if (action == 'open_file') {
                                _pickAndOpenFile();
                              } else if (action == 'new_query') {
                                setState(() => _selectedTab = AppTab.sqlEditor);
                              }
                            } else if (_currentTableName == "1_recent_files") {
                              final path = row.cells['path']?.value?.toString();
                              if (path != null) _loadPath(pathOverride: path);
                            }
                          } else {
                            _inspectCell(row);
                          }
                        },
                      ),
              ),
            ),

            if (_gridColumns.isNotEmpty && _totalRows != null)
              TableStatusFooter(
                totalRows: _totalRows!,
                totalCols: _gridColumns.length,
                executionTimeMs: _lastQueryDurationMs,
                tableName: _currentTableName,
                onFetchAllRows: () async {
                  if (_currentTableName == null) return [];
                  return _dbService.fetchRows(_currentTableName!, limit: 10000);
                },
              ),
          ],
        );
    }
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle, size: 56, color: MacosColors.systemRedColor),
            const SizedBox(height: 16),
            Text(
              'Unable to Load Database',
              style: MacosTheme.of(context).typography.title1.copyWith(color: MacosColors.systemRedColor),
            ),
            const SizedBox(height: 12),
            SelectableText(
              _errorMessage ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: MacosTheme.of(context).typography.body,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PushButton(
                  controlSize: ControlSize.large,
                  secondary: true,
                  onPressed: _loadHome,
                  child: const Text('Go Home'),
                ),
                const SizedBox(width: 12),
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: _pickAndOpenFile,
                  child: const Text('Open with Finder (⌘O)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
