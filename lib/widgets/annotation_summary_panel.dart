import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/annotation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnnotationSummaryPanel
//
// Shows a categorised list of all annotations in the document.
// Tapping any row navigates to that page.
// ─────────────────────────────────────────────────────────────────────────────

class AnnotationSummaryPanel extends StatefulWidget {
  final Map<int, List<RectAnnotation>>  rects;
  final Map<int, InkAnnotation?>        ink;
  final Map<int, List<StickyNote>>      notes;
  final Map<int, List<SignatureOverlay>> sigs;
  final Map<int, List<TextStamp>>       stamps;
  final Map<int, List<RedactionRect>>   redactions;
  final Map<int, List<ClauseBookmark>>  bookmarks;
  final ValueChanged<int> onNavigate; // 0-based pageIndex

  const AnnotationSummaryPanel({
    super.key,
    required this.rects,
    required this.ink,
    required this.notes,
    required this.sigs,
    required this.stamps,
    required this.redactions,
    required this.bookmarks,
    required this.onNavigate,
  });

  static Future<void> show({
    required BuildContext context,
    required Map<int, List<RectAnnotation>> rects,
    required Map<int, InkAnnotation?> ink,
    required Map<int, List<StickyNote>> notes,
    required Map<int, List<SignatureOverlay>> sigs,
    required Map<int, List<TextStamp>> stamps,
    required Map<int, List<RedactionRect>> redactions,
    required Map<int, List<ClauseBookmark>> bookmarks,
    required ValueChanged<int> onNavigate,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, ctrl) => AnnotationSummaryPanel(
          rects: rects, ink: ink, notes: notes, sigs: sigs,
          stamps: stamps, redactions: redactions, bookmarks: bookmarks,
          onNavigate: onNavigate,
        ),
      ),
    );
  }

  @override
  State<AnnotationSummaryPanel> createState() => _AnnotationSummaryPanelState();
}

class _AnnotationSummaryPanelState extends State<AnnotationSummaryPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Build flat lists ──────────────────────────────────────────────────────

  List<_SummaryItem> get _highlights {
    final out = <_SummaryItem>[];
    widget.rects.forEach((page, list) {
      for (final r in list) {
        if (r.type == AnnotationType.highlight) {
          out.add(_SummaryItem(pageIndex: page,
              icon: Icons.highlight_rounded, color: const Color(0xFFFFD600),
              label: 'Highlight', subtitle: 'p.${page + 1}'));
        } else if (r.type == AnnotationType.underline) {
          out.add(_SummaryItem(pageIndex: page,
              icon: Icons.format_underline_rounded, color: const Color(0xFF38BDF8),
              label: 'Underline', subtitle: 'p.${page + 1}'));
        } else if (r.type == AnnotationType.strikethrough) {
          out.add(_SummaryItem(pageIndex: page,
              icon: Icons.strikethrough_s_rounded, color: const Color(0xFFF87171),
              label: 'Strikethrough', subtitle: 'p.${page + 1}'));
        }
      }
    });
    return out..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  List<_SummaryItem> get _inkItems {
    final out = <_SummaryItem>[];
    widget.ink.forEach((page, ann) {
      if (ann != null && ann.strokes.isNotEmpty) {
        out.add(_SummaryItem(pageIndex: page,
            icon: Icons.brush_rounded, color: const Color(0xFFA78BFA),
            label: '${ann.strokes.length} ink stroke${ann.strokes.length == 1 ? '' : 's'}',
            subtitle: 'p.${page + 1}'));
      }
    });
    return out..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  List<_SummaryItem> get _noteItems {
    final out = <_SummaryItem>[];
    widget.notes.forEach((page, list) {
      for (final n in list) {
        out.add(_SummaryItem(pageIndex: page,
            icon: Icons.sticky_note_2_rounded, color: const Color(0xFFFB923C),
            label: n.text.length > 50 ? '${n.text.substring(0, 50)}…' : n.text,
            subtitle: 'p.${page + 1}'));
      }
    });
    return out..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  List<_SummaryItem> get _sigItems {
    final out = <_SummaryItem>[];
    widget.sigs.forEach((page, list) {
      for (final s in list) {
        out.add(_SummaryItem(pageIndex: page,
            icon: s.isInitials ? Icons.fingerprint_rounded : Icons.draw_rounded,
            color: const Color(0xFF818CF8),
            label: s.signerName != null && s.signerName!.isNotEmpty
                ? s.signerName!
                : s.isInitials ? 'Initials' : 'Signature',
            subtitle: 'p.${page + 1}${s.slotId != null ? ' · ${s.slotId}' : ''}'));
      }
    });
    return out..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  List<_SummaryItem> get _redactItems {
    final out = <_SummaryItem>[];
    widget.redactions.forEach((page, list) {
      for (final _ in list) {
        out.add(_SummaryItem(pageIndex: page,
            icon: Icons.hide_source_rounded, color: const Color(0xFFEF4444),
            label: 'Redacted region', subtitle: 'p.${page + 1}'));
      }
    });
    return out..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  List<_SummaryItem> get _clauseItems {
    final out = <_SummaryItem>[];
    widget.bookmarks.forEach((page, list) {
      for (final b in list) {
        out.add(_SummaryItem(pageIndex: page,
            icon: Icons.bookmark_rounded, color: b.color,
            label: b.label, subtitle: 'p.${page + 1}'));
      }
    });
    return out..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  }

  int get _total =>
      _highlights.length + _inkItems.length + _noteItems.length +
      _sigItems.length + _redactItems.length + _clauseItems.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF14142B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle
        Center(child: Container(
          margin: const EdgeInsets.only(top: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(children: [
            const Icon(Icons.list_alt_rounded,
                color: Color(0xFF6366F1), size: 18),
            const SizedBox(width: 8),
            Text('All Annotations',
                style: GoogleFonts.inter(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$_total',
                  style: const TextStyle(
                      color: Color(0xFF818CF8), fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ),

        // Tab bar
        TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF6366F1),
          labelColor: const Color(0xFF6366F1),
          unselectedLabelColor: Colors.white38,
          indicatorWeight: 2,
          labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
          tabs: [
            _countTab('Marks', _highlights.length),
            _countTab('Ink', _inkItems.length),
            _countTab('Notes', _noteItems.length),
            _countTab('Sigs', _sigItems.length),
            _countTab('Redact', _redactItems.length),
            _countTab('Clauses', _clauseItems.length),
          ],
        ),
        const Divider(height: 1, color: Colors.white10),

        // Tab views
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _list(_highlights),
              _list(_inkItems),
              _list(_noteItems),
              _list(_sigItems),
              _list(_redactItems),
              _list(_clauseItems),
            ],
          ),
        ),
      ]),
    );
  }

  Tab _countTab(String label, int count) => Tab(
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label),
      if (count > 0) ...[
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count',
              style: const TextStyle(fontSize: 9, color: Color(0xFF818CF8))),
        ),
      ],
    ]),
  );

  Widget _list(List<_SummaryItem> items) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline_rounded,
            size: 36, color: Colors.white.withOpacity(0.12)),
        const SizedBox(height: 8),
        Text('None yet', style: GoogleFonts.inter(
            color: Colors.white24, fontSize: 13)),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Colors.white10),
      itemBuilder: (ctx, i) {
        final item = items[i];
        return ListTile(
          dense: true,
          onTap: () {
            widget.onNavigate(item.pageIndex);
            Navigator.of(ctx).pop();
          },
          leading: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, size: 16, color: item.color),
          ),
          title: Text(item.label,
              style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.87), fontSize: 13,
                  fontWeight: FontWeight.w500),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(item.subtitle,
              style: GoogleFonts.inter(
                  color: Colors.white38, fontSize: 11)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded,
              size: 12, color: Colors.white24),
        );
      },
    );
  }
}

class _SummaryItem {
  final int pageIndex;
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  const _SummaryItem({
    required this.pageIndex, required this.icon, required this.color,
    required this.label, required this.subtitle,
  });
}
