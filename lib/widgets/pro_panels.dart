import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ClausePanel — shows all clause bookmarks, tap to navigate
// ─────────────────────────────────────────────────────────────────────────────

class ClausePanel extends StatelessWidget {
  final Map<int, List<ClauseBookmark>> bookmarks;
  final void Function(int pageIndex) onNavigate;
  final void Function(String bookmarkId) onDelete;

  const ClausePanel({
    super.key,
    required this.bookmarks,
    required this.onNavigate,
    required this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    required Map<int, List<ClauseBookmark>> bookmarks,
    required void Function(int) onNavigate,
    required void Function(String) onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ClausePanel(
        bookmarks: bookmarks, onNavigate: onNavigate, onDelete: onDelete),
    );
  }

  List<ClauseBookmark> get _flat {
    final all = <ClauseBookmark>[];
    for (final list in bookmarks.values) all.addAll(list);
    all.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final flat = _flat;
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(children: [
            const Icon(Icons.bookmark_rounded, color: Color(0xFF6366F1), size: 18),
            const SizedBox(width: 8),
            Text('Clause Bookmarks (${flat.length})',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),
        if (flat.isEmpty)
          Expanded(child: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border_rounded, size: 40, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 8),
              Text('No clause bookmarks yet', style: GoogleFonts.inter(
                  color: Colors.white30, fontSize: 13)),
              const SizedBox(height: 4),
              Text('Use the Bookmark tool to tag contract clauses',
                  style: GoogleFonts.inter(color: Colors.white24, fontSize: 11)),
            ],
          )))
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: flat.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (_, i) {
                final b = flat[i];
                return ListTile(
                  onTap: () { onNavigate(b.pageIndex); Navigator.pop(context); },
                  leading: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: b.color, shape: BoxShape.circle),
                  ),
                  title: Text(b.label, style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.87), fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('Page ${b.pageIndex + 1}',
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white30),
                    onPressed: () => onDelete(b.id),
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SignatureSlotsPanel — define multi-party roles, set active signer
// ─────────────────────────────────────────────────────────────────────────────

class SignatureSlotsPanel extends StatefulWidget {
  final List<SignatureSlot> slots;
  final String? activeSlotId;
  final void Function(List<SignatureSlot> updated, String? activeId) onChanged;

  const SignatureSlotsPanel({
    super.key,
    required this.slots,
    required this.activeSlotId,
    required this.onChanged,
  });

  static Future<void> show({
    required BuildContext context,
    required List<SignatureSlot> slots,
    required String? activeSlotId,
    required void Function(List<SignatureSlot>, String?) onChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SignatureSlotsPanel(
          slots: slots, activeSlotId: activeSlotId, onChanged: onChanged),
    );
  }

  @override
  State<SignatureSlotsPanel> createState() => _SignatureSlotsPanelState();
}

class _SignatureSlotsPanelState extends State<SignatureSlotsPanel> {
  late List<SignatureSlot> _slots;
  String? _activeId;
  final _uuid = const Uuid();

  static const _presetRoles  = ['Client', 'Witness', 'Notary', 'Guarantor', 'Counterparty'];
  static const _presetColors = [
    Color(0xFF6366F1), Color(0xFF10B981), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFF3B82F6),
  ];

  @override
  void initState() {
    super.initState();
    _slots    = List.from(widget.slots);
    _activeId = widget.activeSlotId;
  }

  void _addSlot(String role, Color color) {
    setState(() => _slots.add(SignatureSlot(
        id: _uuid.v4(), role: role, color: color)));
    _notify();
  }

  void _removeSlot(String id) {
    setState(() {
      _slots.removeWhere((s) => s.id == id);
      if (_activeId == id) _activeId = null;
    });
    _notify();
  }

  void _setActive(String id) {
    setState(() => _activeId = _activeId == id ? null : id);
    _notify();
  }

  void _notify() => widget.onChanged(List.from(_slots), _activeId);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF14142B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(children: [
            const Icon(Icons.people_rounded, color: Color(0xFF6366F1), size: 18),
            const SizedBox(width: 8),
            Text('Multi-Party Signers', style: GoogleFonts.inter(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Define signing roles. Tap a role to set it as the active signer — signatures placed while active are attributed to that role in the audit trail.',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(color: Colors.white10, height: 1),

        // Slot list
        if (_slots.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _slots.length,
            itemBuilder: (_, i) {
              final slot = _slots[i];
              final isActive = slot.id == _activeId;
              return ListTile(
                onTap: () => _setActive(slot.id),
                leading: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: slot.color.withOpacity(isActive ? 1.0 : 0.3),
                    shape: BoxShape.circle,
                    border: isActive
                        ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                  child: slot.isSigned
                      ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                      : null,
                ),
                title: Text(slot.role, style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.87), fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  isActive ? 'ACTIVE — next signature uses this role'
                      : slot.isSigned ? 'Signed ✓' : 'Pending',
                  style: GoogleFonts.inter(
                    color: isActive ? const Color(0xFF6366F1) : Colors.white38,
                    fontSize: 11),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white30),
                  onPressed: () => _removeSlot(slot.id),
                ),
              );
            },
          ),

        // Add role presets
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('ADD ROLE', style: GoogleFonts.inter(
              color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: List.generate(_presetRoles.length, (i) {
              final already = _slots.any((s) => s.role == _presetRoles[i]);
              return GestureDetector(
                onTap: already ? null : () => _addSlot(_presetRoles[i], _presetColors[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: already ? Colors.white.withOpacity(0.04)
                        : _presetColors[i].withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: already ? Colors.white12 : _presetColors[i].withOpacity(0.5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!already) Icon(Icons.add_rounded, size: 14, color: _presetColors[i]),
                    if (!already) const SizedBox(width: 4),
                    Text(_presetRoles[i], style: TextStyle(
                        color: already ? Colors.white24 : Colors.white70,
                        fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }
}
