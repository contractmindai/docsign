import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/signer_profile.dart';
import '../services/signer_profile_service.dart';
import 'signature_dialog.dart';

class SignerProfileDialog extends StatefulWidget {
  const SignerProfileDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const SignerProfileDialog(),
      );

  @override
  State<SignerProfileDialog> createState() => _SignerProfileDialogState();
}

class _SignerProfileDialogState extends State<SignerProfileDialog> {
  final _nameCtrl    = TextEditingController();
  final _titleCtrl   = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _emailCtrl   = TextEditingController();

  List<SavedSignature> _savedSigs = [];
  bool _loading = true;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await SignerProfileService.loadProfile();
    final sigs    = await SignerProfileService.loadSavedSignatures();
    if (!mounted) return;
    setState(() {
      if (profile != null) {
        _nameCtrl.text    = profile.fullName;
        _titleCtrl.text   = profile.title;
        _companyCtrl.text = profile.company;
        _emailCtrl.text   = profile.email;
      }
      _savedSigs = sigs;
      _loading   = false;
    });
  }

  Future<void> _save() async {
    final profile = SignerProfile(
      fullName: _nameCtrl.text.trim(),
      title:    _titleCtrl.text.trim(),
      company:  _companyCtrl.text.trim(),
      email:    _emailCtrl.text.trim(),
    );
    await SignerProfileService.saveProfile(profile);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved'),
            backgroundColor: Color(0xFF10B981)));
      Navigator.of(context).pop();
    }
  }

  Future<void> _addSignature() async {
    final bytes = await SignatureDialog.show(context);
    if (bytes == null || !mounted) return;
    final label = await _labelDialog();
    if (!mounted) return;
    final sig = SavedSignature(
      id: _uuid.v4(), label: label ?? 'Signature',
      pngBytes: bytes, createdAt: DateTime.now(),
    );
    await SignerProfileService.addSignature(sig);
    setState(() => _savedSigs = [..._savedSigs, sig]);
  }

  Future<String?> _labelDialog() async {
    final ctrl = TextEditingController(text: 'Full Signature');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Label this signature', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Full Signature / Initials',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? 'Signature' : ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSig(String id) async {
    await SignerProfileService.deleteSignature(id);
    setState(() => _savedSigs.removeWhere((s) => s.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF6366F1), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Signer Profile', style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white38),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
                const SizedBox(height: 20),

                // Form fields
                _field('Full Name *', _nameCtrl, hint: 'John Smith'),
                const SizedBox(height: 12),
                _field('Title', _titleCtrl, hint: 'Senior Partner'),
                const SizedBox(height: 12),
                _field('Company', _companyCtrl, hint: 'Acme Legal LLC'),
                const SizedBox(height: 12),
                _field('Email', _emailCtrl, hint: 'john@acmelegal.com', keyboard: TextInputType.emailAddress),
                const SizedBox(height: 24),

                // Saved signatures
                Row(children: [
                  Text('SAVED SIGNATURES', style: GoogleFonts.inter(
                      color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addSignature,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF6366F1)),
                  ),
                ]),
                const SizedBox(height: 8),

                if (_savedSigs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12, style: BorderStyle.solid),
                    ),
                    child: Column(children: [
                      Icon(Icons.draw_rounded, size: 28, color: Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 6),
                      Text('No saved signatures yet', style: GoogleFonts.inter(
                          color: Colors.white30, fontSize: 12)),
                    ]),
                  )
                else
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _savedSigs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => _savedSigCard(_savedSigs[i]),
                    ),
                  ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _nameCtrl.text.trim().isEmpty ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text('Save Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String hint = '', TextInputType keyboard = TextInputType.text}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14),
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white12)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF6366F1))),
        ),
      ),
    ]);
  }

  Widget _savedSigCard(SavedSignature sig) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              child: Image.memory(sig.pngBytes, fit: BoxFit.contain),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF14142B),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Text(sig.label, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
      Positioned(
        top: -8, right: -8,
        child: GestureDetector(
          onTap: () => _deleteSig(sig.id),
          child: Container(
            width: 20, height: 20,
            decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
          ),
        ),
      ),
    ]);
  }
}
