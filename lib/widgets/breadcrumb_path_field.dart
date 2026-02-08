import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'dart:io';
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
    } catch (e) {
      print('[BreadcrumbPathField] Error parsing path: $e');
      // Fallback to simple split
      setState(() {
        _cachedSegments = path.split('/').where((s) => s.isNotEmpty).map((text) =>
          _PathSegment(text: text, path: '', exists: false, type: 'unknown')
        ).toList();
        _lastParsedPath = path;
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
        },
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF3D3D3D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Leading indicator (simplified to just / or ~)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Text(
                        widget.controller.text.startsWith('~') ? '~' : '/',
                        style: TextStyle(
                          fontSize: 13,
                          color: _cachedSegments.isNotEmpty && _cachedSegments.first.exists
                              ? MacosColors.systemGreenColor.withOpacity(0.8)
                              : MacosColors.systemRedColor.withOpacity(0.8),
                        ),
                      ),
                    ),
                    
                    // Breadcrumb segments
                    for (int i = 0; i < _cachedSegments.length; i++) ...[
                      GestureDetector(
                        onDoubleTap: () {
                          final segment = _cachedSegments[i];
                          if (segment.path.isNotEmpty) {
                            widget.onNavigate(segment.path);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Builder(
                              builder: (context) {
                                final segment = _cachedSegments[i];
                                final exists = segment.exists;
                                return Text(
                                  segment.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: exists 
                                        ? (i == _cachedSegments.length - 1 ? Colors.white : Colors.white.withOpacity(0.7))
                                        : MacosColors.systemRedColor,
                                    fontWeight: i == _cachedSegments.length - 1
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                    decoration: exists ? null : TextDecoration.lineThrough,
                                    decorationColor: MacosColors.systemRedColor,
                                  ),
                                );
                              }
                            ),
                          ),
                        ),
                      ),
                      
                      // Separator
                      if (i < _cachedSegments.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            '/',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            
            if (widget.suffix != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
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
