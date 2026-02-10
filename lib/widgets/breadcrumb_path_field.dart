import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import '../flight_service.dart';

/// Interactive breadcrumb-style path field where each segment is double-clickable
class BreadcrumbPathField extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;
  final Function(String path) onNavigate;
  final Widget? suffix;
  final FlightService flightService;
  
  const BreadcrumbPathField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onNavigate,
    required this.flightService,
    this.suffix,
  });
  
  @override
  State<BreadcrumbPathField> createState() => _BreadcrumbPathFieldState();
}

class _BreadcrumbPathFieldState extends State<BreadcrumbPathField> {
  bool _isEditMode = false;
  final FocusNode _focusNode = FocusNode();
  List<_PathSegment> _cachedSegments = [];
  String _lastParsedPath = '';
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditMode) {
        setState(() {
          _isEditMode = false;
        });
      }
    });
  }
  
  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  // Parse path segments using server API
  Future<void> _parsePathSegments(String path) async {
    if (path.isEmpty || path == _lastParsedPath) return;
    
    try {
      final response = await widget.flightService.get(
        '/api/parse-path',
        queryParams: {'url': path},
      );
      
      final segments = (response['segments'] as List? ?? [])
          .map((json) => _PathSegment.fromJson(json))
          .toList();
      
      setState(() {
        _cachedSegments = segments;
        _lastParsedPath = path;
      });

      // Auto-scroll to end
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      // Fallback to simple split for local paths
      final parts = path.split('/').where((s) => s.isNotEmpty).toList();
      final segments = <_PathSegment>[];
      
      String buffer = path.startsWith('/') ? '/' : '';
      
      for (int i = 0; i < parts.length; i++) {
        if (i > 0 || (buffer != '/' && buffer.isNotEmpty)) {
          buffer += '/';
        }
        buffer += parts[i];
        
        segments.add(_PathSegment(
          text: parts[i],
          path: buffer,
          exists: true, // Assume valid for local paths
          type: 'unknown',
        ));
      }

      setState(() {
        _cachedSegments = segments;
        _lastParsedPath = path;
      });

      // Auto-scroll to end
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Ensure controller is attached before jumping
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isEditMode || widget.controller.text.isEmpty) {
      // Regular edit mode
      return MacosTextField(
        controller: widget.controller,
        placeholder: widget.placeholder,
        focusNode: _focusNode,
        autofocus: true,
        onSubmitted: (value) {
          setState(() {
            _isEditMode = false;
          });
          widget.onNavigate(value);
        },
        padding: EdgeInsets.zero,
        suffix: widget.suffix,
      );
    }
    
    // Trigger parsing if path changed (fire and forget)
    final currentPath = widget.controller.text;
    if (currentPath != _lastParsedPath) {
      _parsePathSegments(currentPath);
    }
    
    // Breadcrumb display mode
    return GestureDetector(
      onTap: () {
        // Single tap enters edit mode
        setState(() {
          _isEditMode = true;
        });
        _focusNode.requestFocus();
      },
      child: Container(
        height: 30,
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: const Color(0xFF3D3D3D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            // Leading indicator
            Padding(
              padding: EdgeInsets.zero,
              child: Text(
                widget.controller.text.startsWith('~') ? '' : '/',
                style: MacosTheme.of(context).typography.body.copyWith(
                  fontSize: 13,
                  color: MacosColors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            
            // Scrollable Breadcrumbs
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: _cachedSegments.length,
                separatorBuilder: (context, index) => Padding(
                  padding: EdgeInsets.zero,
                  child: Center(
                    child: Text(
                      '/',
                      style: MacosTheme.of(context).typography.body.copyWith(
                        fontSize: 13,
                        color: MacosColors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                itemBuilder: (context, index) {
                  return Center(
                    child: _BreadcrumbSegment(
                      segment: _cachedSegments[index],
                      isLast: index == _cachedSegments.length - 1,
                      onTap: () {
                         if (_cachedSegments[index].path.isNotEmpty) {
                           widget.onNavigate(_cachedSegments[index].path);
                         }
                      },
                    ),
                  );
                },
              ),
            ),
            
            if (widget.suffix != null)
              Padding(
                padding: EdgeInsets.zero,
                child: widget.suffix!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Represents a parsed path segment from the server
class _PathSegment {
  final String text;
  final String path;
  final bool exists;
  final String type; // "directory", "file", "banquet_table", "unknown"
  
  _PathSegment({
    required this.text,
    required this.path,
    required this.exists,
    required this.type,
  });
  
  factory _PathSegment.fromJson(Map<String, dynamic> json) {
    return _PathSegment(
      text: json['text'] ?? '',
      path: json['path'] ?? '',
      exists: json['exists'] ?? false,
      type: json['type'] ?? 'unknown',
    );
  }
}

class _BreadcrumbSegment extends StatefulWidget {
  final _PathSegment segment;
  final bool isLast;
  final VoidCallback onTap;

  const _BreadcrumbSegment({
    required this.segment,
    required this.isLast,
    required this.onTap,
  });

  @override
  State<_BreadcrumbSegment> createState() => _BreadcrumbSegmentState();
}

class _BreadcrumbSegmentState extends State<_BreadcrumbSegment> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final exists = widget.segment.exists;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.segment.text,
            style: MacosTheme.of(context).typography.body.copyWith(
              fontSize: 13, // Keep specific size for breadcrumb density
              color: exists 
                  ? (widget.isLast ? MacosColors.white : MacosColors.white.withValues(alpha: 0.7))
                  : MacosColors.systemRedColor,
              fontWeight: widget.isLast ? FontWeight.w500 : FontWeight.normal,
              decoration: exists ? null : TextDecoration.lineThrough,
              decorationColor: MacosColors.systemRedColor,
              backgroundColor: _isHovered ? MacosColors.white.withValues(alpha: 0.05) : null,
            ),
          ),
        ),
      ),
    );
  }
}
