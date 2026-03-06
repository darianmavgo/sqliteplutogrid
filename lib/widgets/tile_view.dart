import 'dart:io';

import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';

// ---------------------------------------------------------------------------
// Column Heuristics
// ---------------------------------------------------------------------------

/// Priority-ranked keywords for image/thumbnail column detection.
const _imageKeywords = [
  'thumb', 'thumbnail', 'image', 'img', 'cover', 'photo',
  'poster', 'avatar', 'icon', 'picture', 'pic',
];

/// Priority-ranked keywords for caption column detection.
const _captionKeywords = [
  'name', 'title', 'label', 'caption', 'description', 'desc', 'text',
];

/// Returns the column most likely to contain an image URL/path.
/// Falls back to any column whose sampled values look like image URIs.
String? _detectImageColumn(
  List<TrinaColumn> columns,
  List<TrinaRow> sampleRows,
) {
  final names = columns.map((c) => c.field).toList();

  // 1. Exact keyword match (highest confidence)
  for (final kw in _imageKeywords) {
    for (final name in names) {
      if (name.toLowerCase() == kw) return name;
    }
  }

  // 2. Contains keyword
  for (final kw in _imageKeywords) {
    for (final name in names) {
      if (name.toLowerCase().contains(kw)) return name;
    }
  }

  // 3. Sample values look like image URIs
  for (final col in columns) {
    int imageHits = 0;
    for (final row in sampleRows.take(20)) {
      final v = row.cells[col.field]?.value?.toString() ?? '';
      if (_looksLikeImageUri(v)) imageHits++;
    }
    if (imageHits >= 3) return col.field;
  }

  return null;
}

/// Returns the column most likely to hold a human-readable caption.
String? _detectCaptionColumn(
  List<TrinaColumn> columns,
  String? imageField,
) {
  final candidates = columns.where((c) => c.field != imageField).toList();

  for (final kw in _captionKeywords) {
    for (final col in candidates) {
      if (col.field.toLowerCase() == kw) return col.field;
    }
  }
  for (final kw in _captionKeywords) {
    for (final col in candidates) {
      if (col.field.toLowerCase().contains(kw)) return col.field;
    }
  }

  return candidates.isNotEmpty ? candidates.first.field : null;
}

bool _looksLikeImageUri(String v) {
  if (v.isEmpty) return false;
  final lower = v.toLowerCase();
  const imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.bmp', '.svg'];
  if (imageExts.any((e) => lower.endsWith(e))) return true;
  if (lower.startsWith('http://') || lower.startsWith('https://')) return true;
  return false;
}

bool _isLocalPath(String v) =>
    v.startsWith('/') || v.startsWith('~/') || v.startsWith('file://');

// ---------------------------------------------------------------------------
// TileView Widget
// ---------------------------------------------------------------------------

class TileView extends StatefulWidget {
  final List<TrinaColumn> columns;
  final Future<List<TrinaRow>> Function(int offset) onFetchRows;
  final int? totalRows;
  final Function(String path)? onNavigate;

  const TileView({
    super.key,
    required this.columns,
    required this.onFetchRows,
    this.totalRows,
    this.onNavigate,
  });

  @override
  State<TileView> createState() => _TileViewState();
}

class _TileViewState extends State<TileView> {
  final List<TrinaRow> _rows = [];
  bool _loading = false;
  bool _exhausted = false;
  int _page = 0;
  static const int _pageSize = 200;

  String? _imageField;
  String? _captionField;
  bool _heuristicsRun = false;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadNextPage();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TileView old) {
    super.didUpdateWidget(old);
    // Re-fetch if columns changed (new table)
    if (old.columns != widget.columns) {
      _rows.clear();
      _page = 0;
      _exhausted = false;
      _heuristicsRun = false;
      _loadNextPage();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || _exhausted) return;
    setState(() => _loading = true);

    final offset = _page * _pageSize;
    final newRows = await widget.onFetchRows(offset);

    if (!mounted) return;

    setState(() {
      _rows.addAll(newRows);
      _loading = false;
      if (newRows.length < _pageSize) _exhausted = true;
      _page++;

      // Run heuristics once we have data
      if (!_heuristicsRun && _rows.isNotEmpty) {
        _heuristicsRun = true;
        _imageField = _detectImageColumn(widget.columns, _rows);
        _captionField = _detectCaptionColumn(widget.columns, _imageField);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rows.isEmpty) {
      return Center(
        child: Text(
          'No rows',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
        ),
      );
    }

    return Stack(
      children: [
        // Main grid
        CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82, // slightly taller than wide
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i >= _rows.length) return null;
                    return _TileCard(
                      row: _rows[i],
                      imageField: _imageField,
                      captionField: _captionField,
                      onTap: (path) => widget.onNavigate?.call(path),
                    );
                  },
                  childCount: _rows.length,
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),

        // Row count badge — bottom right
        Positioned(
          bottom: 10,
          right: 14,
          child: _CountBadge(count: widget.totalRows ?? _rows.length),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tile Card
// ---------------------------------------------------------------------------

class _TileCard extends StatefulWidget {
  final TrinaRow row;
  final String? imageField;
  final String? captionField;
  final Function(String) onTap;

  const _TileCard({
    required this.row,
    required this.imageField,
    required this.captionField,
    required this.onTap,
  });

  @override
  State<_TileCard> createState() => _TileCardState();
}

class _TileCardState extends State<_TileCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final imageVal = widget.imageField != null
        ? (widget.row.cells[widget.imageField!]?.value?.toString() ?? '')
        : '';
    final caption = widget.captionField != null
        ? (widget.row.cells[widget.captionField!]?.value?.toString() ?? '')
        : '';
    final firstLetter =
        caption.isNotEmpty ? caption[0].toUpperCase() : '?';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final nav = imageVal.isNotEmpty ? imageVal : caption;
          if (nav.isNotEmpty) widget.onTap(nav);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image area (fills most of the card)
                Expanded(
                  child: _buildImage(imageVal, firstLetter),
                ),
                // Caption — always visible below image
                if (caption.isNotEmpty)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hovered ? 1.0 : 0.75,
                    child: Container(
                      color: const Color(0xFF1E1E1E),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String uri, String fallbackLetter) {
    if (uri.isNotEmpty) {
      if (_looksLikeImageUri(uri)) {
        if (_isLocalPath(uri)) {
          // Local file image
          final fixedPath =
              uri.startsWith('~/') ? uri.replaceFirst('~', Platform.environment['HOME'] ?? '') : uri;
          return Image.file(
            File(fixedPath),
            fit: BoxFit.cover,
            // ignore: unnecessary_underscores
            errorBuilder: (_, __, _) => _Placeholder(letter: fallbackLetter),
          );
        } else {
          // Network image
          return Image.network(
            uri,
            fit: BoxFit.cover,
            // ignore: unnecessary_underscores
            errorBuilder: (_, __, _) => _Placeholder(letter: fallbackLetter),
          );
        }
      }
    }
    return _Placeholder(letter: fallbackLetter);
  }
}

// ---------------------------------------------------------------------------
// Placeholder gradient tile
// ---------------------------------------------------------------------------

class _Placeholder extends StatelessWidget {
  final String letter;

  const _Placeholder({required this.letter});

  @override
  Widget build(BuildContext context) {
    // Generate a deterministic color from the letter's code point
    final hue = (letter.codeUnitAt(0) * 31) % 360;
    final color1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.35).toColor();
    final color2 =
        HSLColor.fromAHSL(1, (hue + 40) % 360, 0.45, 0.25).toColor();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color1, color2],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row count badge
// ---------------------------------------------------------------------------

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        '$count tiles',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
