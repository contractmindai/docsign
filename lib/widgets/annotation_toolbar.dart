import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/annotation.dart';

class AnnotationToolbar extends StatelessWidget {
  final AnnotationTool currentTool;
  final Color currentColor;
  final bool isSaving;
  final bool hasPendingSig;
  final bool darkMode;
  final bool showThumbs;
  final ValueChanged<AnnotationTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onUndo;
  final VoidCallback onSave;
  final VoidCallback? onShare;
  final VoidCallback? onPrint;
  final VoidCallback onDarkModeToggle;
  final VoidCallback onThumbsToggle;
  final VoidCallback onSearchToggle;
  final VoidCallback onProfile;
  final VoidCallback onSlots;
  final VoidCallback onClauses;
  final VoidCallback onSummary;
  final VoidCallback onCompare;

  const AnnotationToolbar({
    super.key,
    required this.currentTool,
    required this.currentColor,
    required this.isSaving,
    required this.hasPendingSig,
    required this.darkMode,
    required this.showThumbs,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onUndo,
    required this.onSave,
    this.onShare,
    this.onPrint,
    required this.onDarkModeToggle,
    required this.onThumbsToggle,
    required this.onSearchToggle,
    required this.onProfile,
    required this.onSlots,
    required this.onClauses,
    required this.onSummary,
    required this.onCompare,
  });

  void _pickColor(BuildContext ctx) {
    Color temp = currentColor;
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ink colour', style: GoogleFonts.inter(color: Colors.white, fontSize: 15)),
        content: ColorPicker(pickerColor: currentColor, onColorChanged: (c) => temp = c,
            enableAlpha: false, labelTypes: const [], pickerAreaHeightPercent: 0.65),
        actions: [TextButton(
          onPressed: () { onColorChanged(temp); Navigator.pop(ctx); },
          child: const Text('Done', style: TextStyle(color: Color(0xFF6366F1))),
        )],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14142B),
        border: const Border(top: BorderSide(color: Colors.white10)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4),
            blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Tool strip ────────────────────────────────────────────────────
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            children: [
              _T(icon: Icons.pan_tool_alt_rounded,    label: 'View',      tool: AnnotationTool.view,            ct: currentTool, onTap: onToolChanged, tint: Colors.white54),
              _T(icon: Icons.highlight_rounded,        label: 'Highlight', tool: AnnotationTool.highlight,       ct: currentTool, onTap: onToolChanged, tint: const Color(0xFFFFD600)),
              _T(icon: Icons.format_underline_rounded, label: 'Underline', tool: AnnotationTool.underline,       ct: currentTool, onTap: onToolChanged, tint: const Color(0xFF38BDF8)),
              _T(icon: Icons.strikethrough_s_rounded,  label: 'Strike',    tool: AnnotationTool.strikethrough,   ct: currentTool, onTap: onToolChanged, tint: const Color(0xFFF87171)),
              _T(icon: Icons.brush_rounded,            label: 'Draw',      tool: AnnotationTool.ink,             ct: currentTool, onTap: onToolChanged, tint: currentColor),
              _T(icon: Icons.sticky_note_2_rounded,    label: 'Note',      tool: AnnotationTool.stickyNote,      ct: currentTool, onTap: onToolChanged, tint: const Color(0xFFFB923C)),
              _div(),
              _T(icon: Icons.draw_rounded,             label: 'Sign',      tool: AnnotationTool.signature,       ct: currentTool, onTap: onToolChanged, tint: const Color(0xFF818CF8), badge: hasPendingSig ? '●' : null),
              _T(icon: Icons.fingerprint_rounded,      label: 'Initials',  tool: AnnotationTool.initials,        ct: currentTool, onTap: onToolChanged, tint: const Color(0xFFA78BFA)),
              _T(icon: Icons.text_fields_rounded,      label: 'Text',      tool: AnnotationTool.textStamp,       ct: currentTool, onTap: onToolChanged, tint: const Color(0xFF34D399)),
              _T(icon: Icons.hide_source_rounded,      label: 'Redact',    tool: AnnotationTool.redaction,       ct: currentTool, onTap: onToolChanged, tint: const Color(0xFFEF4444)),
              _T(icon: Icons.bookmark_add_rounded,     label: 'Clause',    tool: AnnotationTool.clauseBookmark,  ct: currentTool, onTap: onToolChanged, tint: const Color(0xFF10B981)),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),
        // ── Action row ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            // Colour dot
            GestureDetector(
              onTap: () => _pickColor(context),
              child: Tooltip(message: 'Ink colour', child: Container(
                width: 22, height: 22, margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(color: currentColor, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 1.5)),
              )),
            ),
            _A(icon: Icons.undo_rounded, tooltip: 'Undo', onTap: onUndo, color: Colors.white54),
            _div2(),
            // View toggles
            _A(icon: Icons.search_rounded, tooltip: 'Search', onTap: onSearchToggle, color: Colors.white38),
            _A(
              icon: showThumbs ? Icons.grid_on_rounded : Icons.grid_off_rounded,
              tooltip: showThumbs ? 'Hide thumbnails' : 'Show thumbnails',
              onTap: onThumbsToggle,
              color: showThumbs ? const Color(0xFF6366F1) : Colors.white38,
            ),
            _A(
              icon: darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              tooltip: darkMode ? 'Light mode' : 'Dark mode',
              onTap: onDarkModeToggle,
              color: darkMode ? Colors.amber : Colors.white38,
            ),
            _div2(),
            // Pro panels
            _A(icon: Icons.list_alt_rounded,   tooltip: 'Annotation summary', onTap: onSummary, color: Colors.white38),
            _A(icon: Icons.people_rounded,     tooltip: 'Multi-party slots',  onTap: onSlots,   color: Colors.white38),
            _A(icon: Icons.bookmarks_rounded,  tooltip: 'Clause bookmarks',   onTap: onClauses, color: Colors.white38),
            _A(icon: Icons.compare_rounded,    tooltip: 'Compare versions',   onTap: onCompare, color: Colors.white38),
            _A(icon: Icons.person_rounded,     tooltip: 'Signer profile',     onTap: onProfile, color: Colors.white38),
            _div2(),
            if (onPrint != null) _A(icon: Icons.print_rounded, tooltip: 'Print', onTap: onPrint!, color: Colors.white38),
            if (onShare != null) _A(icon: Icons.share_rounded, tooltip: 'Share', onTap: onShare!, color: Colors.white38),
            // Save
            isSaving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: Color(0xFF6366F1))))
                : _A(icon: Icons.save_rounded, tooltip: 'Save PDF', onTap: onSave,
                    color: const Color(0xFF6366F1)),
          ]),
        ),
      ])),
    );
  }

  Widget _div()  => Container(width: 1, height: 38, margin: const EdgeInsets.symmetric(horizontal: 4), color: Colors.white12);
  Widget _div2() => Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 2), color: Colors.white12);
}

class _T extends StatelessWidget {
  final IconData icon; final String label;
  final AnnotationTool tool, ct;
  final void Function(AnnotationTool) onTap;
  final Color tint; final String? badge;
  const _T({required this.icon, required this.label, required this.tool,
      required this.ct, required this.onTap, required this.tint, this.badge});
  @override
  Widget build(BuildContext context) {
    final sel = ct == tool;
    return GestureDetector(
      onTap: () => onTap(tool),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: sel ? tint.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: sel ? Border.all(color: tint.withOpacity(0.55)) : null,
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: sel ? tint : Colors.white30),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                color: sel ? tint : Colors.white24)),
          ]),
          if (badge != null) Positioned(top: -4, right: -4,
              child: Text(badge!, style: const TextStyle(color: Color(0xFF6366F1), fontSize: 9))),
        ]),
      ),
    );
  }
}

class _A extends StatelessWidget {
  final IconData icon; final String tooltip;
  final VoidCallback onTap; final Color color;
  const _A({required this.icon, required this.tooltip, required this.onTap, required this.color});
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, color: color, size: 19), tooltip: tooltip,
    onPressed: onTap, visualDensity: VisualDensity.compact,
  );
}
