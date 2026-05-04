import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/signer_profile.dart';

class SignerProfileService {
  static const _kProfile = 'signer_profile_v1';
  static const _kSigs    = 'saved_signatures_v1';

  // ── Profile ───────────────────────────────────────────────────────────────

  static Future<SignerProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProfile);
    if (raw == null) return null;
    try {
      return SignerProfile.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProfile(SignerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfile, jsonEncode(profile.toJson()));
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfile);
  }

  // ── Saved signatures ──────────────────────────────────────────────────────

  static Future<List<SavedSignature>> loadSavedSignatures() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSigs);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => SavedSignature.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeSigs(List<SavedSignature> sigs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSigs, jsonEncode(sigs.map((s) => s.toJson()).toList()));
  }

  static Future<void> addSignature(SavedSignature sig) async {
    final sigs = await loadSavedSignatures();
    // Keep max 5 saved signatures
    if (sigs.length >= 5) sigs.removeAt(0);
    sigs.add(sig);
    await _writeSigs(sigs);
  }

  static Future<void> deleteSignature(String id) async {
    final sigs = await loadSavedSignatures();
    sigs.removeWhere((s) => s.id == id);
    await _writeSigs(sigs);
  }
}
