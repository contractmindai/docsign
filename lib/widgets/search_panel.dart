import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/text_search_service.dart';
// import removed';

// ─────────────────────────────────────────────────────────────────────────────
// SearchPanel
//
// Slides down from the app bar. Debounced search across PDF text.
// Shows results as a scrollable list — tap to jump to page.
// ─────────────────────────────────────────────────────────────────────────────

class SearchPanel extends StatefulWidget {
  final String pdfPath;
  final int pageCount;
  final ValueChanged<int> onNavigate; // 1-based page
  final VoidCallback onClose;

  const SearchPanel({
    super.key,
    required this.pdfPath,
    required this.pageCount,
    required this.onNavigate,
    required this.onClose,
  });

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel>
    with SingleTickerProviderStateMixin {
  final _ctrl   = TextEditingController();
  final _focus  = FocusNode();
  late final AnimationController _animCtrl;
  late final Animation<double>   _anim;

  Map<int, List<SearchMatch>> _results = {};
  List<_FlatResult> _flat = [];
  int _current = 0;
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _results = {}; _flat = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    // TextSearchService.search returns List<SearchMatch>
    final matches = await TextSearchService.search(
        pdfPath: widget.pdfPath, query: query);
    if (!mounted) return;
    final flat = <_FlatResult>[];
    for (final m in matches) {
      flat.add(_FlatResult(pageIndex: m.pageIndex, match: m));
    }
    flat.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    // Convert to map for _results display
    final res = <int, List<SearchMatch>>{};
    for (final f in flat) {
      res.putIfAbsent(f.pageIndex, () => []).add(f.match);
    }
    setState(() { _results = res; _flat = flat; _searching = false; _current = 0; });
    if (flat.isNotEmpty) widget.onNavigate(flat.first.pageIndex + 1);
  }

  void _prev() {
    if (_flat.isEmpty) return;
    setState(() => _current = (_current - 1 + _flat.length) % _flat.length);
    widget.onNavigate(_flat[_current].pageIndex + 1);
  }

  void _next() {
    if (_flat.isEmpty) return;
    setState(() => _current = (_current + 1) % _flat.length);
    widget.onNavigate(_flat[_current].pageIndex + 1);
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _anim,
      axisAlignment: -1,
      child: Container(
        color: const Color(0xFF14142B),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Search row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 10),
                    const Icon(Icons.search_rounded,
                        size: 18, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode:  _focus,
                        onChanged:  _onChanged,
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search in document…',
                          hintStyle: GoogleFonts.inter(
                              color: Colors.white30, fontSize: 14),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFF6366F1))),
                      )
                    else if (_ctrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _ctrl.clear();
                          setState(() { _results = {}; _flat = []; });
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: Colors.white38),
                        ),
                      ),
                  ]),
                ),
              ),

              // Prev / Next
              if (_flat.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '${_current + 1}/${_flat.length}',
                  style: GoogleFonts.inter(
                      color: Colors.white38, fontSize: 11),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  onPressed: _prev,
                  iconSize: 20, color: Colors.white54,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: _next,
                  iconSize: 20, color: Colors.white54,
                  visualDensity: VisualDensity.compact,
                ),
              ],

              // Close
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onClose,
                iconSize: 18, color: Colors.white38,
                visualDensity: VisualDensity.compact,
              ),
            ]),
          ),

          // ── Results list ─────────────────────────────────────────────────
          if (_flat.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: _flat.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.white10),
                itemBuilder: (_, i) {
                  final r       = _flat[i];
                  final isActive = i == _current;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _current = i);
                      widget.onNavigate(r.pageIndex + 1);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      color: isActive
                          ? const Color(0xFF6366F1).withOpacity(0.15)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(children: [
                        Container(
                          width: 28,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF6366F1)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'p.${r.pageIndex + 1}',
                            style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : Colors.white38,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HighlightedText(
                            text: r.match.context,
                            query: _ctrl.text,
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            )
          else if (_ctrl.text.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text('No results for "${_ctrl.text}"',
                  style: GoogleFonts.inter(
                      color: Colors.white30, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _FlatResult {
  final int pageIndex;
  final SearchMatch match;
  const _FlatResult({required this.pageIndex, required this.match});
}

/// Renders text with the query substring highlighted in yellow.
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
          overflow: TextOverflow.ellipsis, maxLines: 2);
    }
    final spans  = <TextSpan>[];
    final lower  = text.toLowerCase();
    final qLower = query.toLowerCase();
    int pos = 0;
    while (true) {
      final idx = lower.indexOf(qLower, pos);
      if (idx == -1) {
        spans.add(TextSpan(
            text: text.substring(pos),
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)));
        break;
      }
      if (idx > pos) {
        spans.add(TextSpan(
            text: text.substring(pos, idx),
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: GoogleFonts.inter(
            color: Colors.black.withOpacity(0.87),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            background: Paint()..color = const Color(0xFFFFD600)),
      ));
      pos = idx + query.length;
    }
    return Text.rich(TextSpan(children: spans),
        overflow: TextOverflow.ellipsis, maxLines: 2);
  }
}
