import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../models/recent_file.dart';
import '../services/recent_files_service.dart';
import '../cache_service.dart';

/// Home Dashboard widget - shows recent files, quick actions, and Flight3 status
class HomeDashboard extends StatefulWidget {
  final RecentFilesService recentFilesService;
  final CacheService cacheService;
  final bool isFlightConnected;
  final VoidCallback onBrowseLocal;
  final VoidCallback onConnectFlight;
  final Function(String path) onOpenFile;
  final Function(RecentFile file) onRemoveRecentFile;
  
  const HomeDashboard({
    super.key,
    required this.recentFilesService,
    required this.cacheService,
    required this.isFlightConnected,
    required this.onBrowseLocal,
    required this.onConnectFlight,
    required this.onOpenFile,
    required this.onRemoveRecentFile,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  Map<String, dynamic>? _cacheStats;
  
  @override
  void initState() {
    super.initState();
    _loadCacheStats();
  }
  
  Future<void> _loadCacheStats() async {
    final stats = await widget.cacheService.getCacheStats();
    if (mounted) {
      setState(() {
        _cacheStats = stats;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final recentFiles = widget.recentFilesService.recentFiles;
    final hasRecentFiles = recentFiles.isNotEmpty;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Header
              _buildWelcomeHeader(),
              const SizedBox(height: 32),
              
              // Quick Actions
              _buildQuickActions(),
              const SizedBox(height: 32),
              
              // Recent Files or Empty State
              if (hasRecentFiles) ...[
                _buildRecentFiles(recentFiles),
                const SizedBox(height: 32),
              ] else ...[
                _buildEmptyState(),
                const SizedBox(height: 32),
              ],
              
              // Flight3 Connection Status
              _buildFlightStatus(),
              const SizedBox(height: 32),
              
              // Cache Stats
              if (_cacheStats != null) ...[
                _buildCacheStats(),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildWelcomeHeader() {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good Morning';
    } else if (hour < 18) {
      greeting = 'Good Afternoon';
    } else {
      greeting = 'Good Evening';
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: MacosTheme.of(context).typography.largeTitle.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome to SQLiter',
          style: MacosTheme.of(context).typography.title2.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
  
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: MacosTheme.of(context).typography.title3.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                icon: CupertinoIcons.folder,
                title: 'Browse Local',
                description: 'Open files from your computer',
                color: MacosColors.systemBlueColor,
                onTap: widget.onBrowseLocal,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                icon: CupertinoIcons.cloud,
                title: 'Flight Server',
                description: 'Connect to remote datasets',
                color: widget.isFlightConnected 
                    ? MacosColors.systemGreenColor 
                    : MacosColors.systemOrangeColor,
                onTap: widget.onConnectFlight,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: MacosTheme.of(context).typography.headline.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: MacosTheme.of(context).typography.caption1.copyWith(
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRecentFiles(List<RecentFile> files) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Files',
              style: MacosTheme.of(context).typography.title3.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            MacosIconButton(
              icon: const Icon(CupertinoIcons.clear, size: 16),
              onPressed: () async {
                final confirmed = await showMacosAlertDialog(
                  context: context,
                  builder: (context) => MacosAlertDialog(
                    appIcon: const Icon(CupertinoIcons.trash, size: 64),
                    title: const Text('Clear Recent Files'),
                    message: const Text('Are you sure you want to clear all recent files?'),
                    primaryButton: PushButton(
                      controlSize: ControlSize.large,
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Clear'),
                    ),
                    secondaryButton: PushButton(
                      controlSize: ControlSize.large,
                      secondary: true,
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                );
                
                if (confirmed == true) {
                  await widget.recentFilesService.clearAllRecentFiles();
                  setState(() {});
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...files.take(10).map((file) => _buildRecentFileItem(file)),
      ],
    );
  }
  
  Widget _buildRecentFileItem(RecentFile file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onOpenFile(file.path),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  file.wasConverted 
                      ? CupertinoIcons.arrow_2_squarepath 
                      : CupertinoIcons.doc_text,
                  color: file.wasConverted 
                      ? MacosColors.systemOrangeColor 
                      : MacosColors.systemBlueColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.recentFilesService.getDirectory(file)} • ${file.getRelativeTime()}',
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                if (file.wasConverted) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: MacosColors.systemOrangeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: MacosColors.systemOrangeColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      file.getFileType(),
                      style: const TextStyle(fontSize: 11, color: MacosColors.systemOrangeColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                MacosIconButton(
                  icon: const Icon(CupertinoIcons.xmark_circle, size: 16),
                  onPressed: () {
                    widget.onRemoveRecentFile(file);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(CupertinoIcons.tray, size: 64, color: Colors.white30),
            const SizedBox(height: 16),
            Text(
              'No Recent Files',
              style: MacosTheme.of(context).typography.title3.copyWith(
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Get started by opening a file or connecting to Flight3',
              style: MacosTheme.of(context).typography.body.copyWith(
                color: Colors.white.withOpacity(0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFlightStatus() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isFlightConnected 
              ? MacosColors.systemGreenColor.withOpacity(0.3)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.cloud,
            size: 32,
            color: widget.isFlightConnected 
                ? MacosColors.systemGreenColor 
                : Colors.white30,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flight3 Server',
                  style: MacosTheme.of(context).typography.headline.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isFlightConnected 
                      ? 'Connected • Ready for file conversion'
                      : 'Not connected • Connect to enable automatic conversion',
                  style: MacosTheme.of(context).typography.caption1.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isFlightConnected 
                  ? MacosColors.systemGreenColor 
                  : MacosColors.systemRedColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCacheStats() {
    final fileCount = _cacheStats?['fileCount'] ?? 0;
    final totalSizeMB = _cacheStats?['totalSizeMB'] ?? '0.00';
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.folder_fill, size: 32, color: Colors.white60),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conversion Cache',
                  style: MacosTheme.of(context).typography.headline.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$fileCount ${fileCount == 1 ? 'file' : 'files'} cached • $totalSizeMB MB',
                  style: MacosTheme.of(context).typography.caption1.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          if (fileCount > 0)
            MacosIconButton(
              icon: const Icon(CupertinoIcons.trash, size: 16),
              onPressed: () async {
                final confirmed = await showMacosAlertDialog(
                  context: context,
                  builder: (context) => MacosAlertDialog(
                    appIcon: const Icon(CupertinoIcons.trash, size: 64),
                    title: const Text('Clear Cache'),
                    message: Text('Clear $fileCount cached ${fileCount == 1 ? 'file' : 'files'} ($totalSizeMB MB)?'),
                    primaryButton: PushButton(
                      controlSize: ControlSize.large,
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Clear'),
                    ),
                    secondaryButton: PushButton(
                      controlSize: ControlSize.large,
                      secondary: true,
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                );
                
                if (confirmed == true) {
                  await widget.cacheService.clearCache();
                  await _loadCacheStats();
                }
              },
            ),
        ],
      ),
    );
  }
}
