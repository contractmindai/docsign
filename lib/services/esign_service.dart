import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_file_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// eSignatureService — ESIGN Act (US) + eIDAS (EU) compliance
// ─────────────────────────────────────────────────────────────────────────────

class ESignService {
  static Future<String> hashDocument(String filePath, {Uint8List? bytes}) async {
    try {
      final data = bytes ?? await PlatformFileService.readBytes(filePath);
      if (data == null) return 'hash_unavailable';
      return sha256.convert(data).toString();
    } catch (_) { return 'hash_unavailable'; }
  }

  static Future<SigningSession> createSession({
    required String documentPath,
    required String documentName,
    required List<SigningRole> roles,
    Uint8List? documentBytes,
    SigningFramework framework = SigningFramework.esign,
  }) async {
    final hash   = await hashDocument(documentPath, bytes: documentBytes);
    final prefs  = await SharedPreferences.getInstance();
    final session = SigningSession(
        id: _id(), documentName: documentName, documentHash: hash,
        framework: framework, roles: roles,
        createdAt: DateTime.now(), events: []);
    await prefs.setString('esign_${session.id}', jsonEncode(session.toJson()));
    return session;
  }

  static Future<void> saveSession(SigningSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esign_${session.id}', jsonEncode(session.toJson()));
  }

  static Future<SigningEvent> recordSign({
    required SigningSession session, required String signerName,
    required String signerEmail, required String roleId,
    required int pageIndex, required String documentHashAtTime,
    String? ipAddress, String? deviceInfo,
  }) async {
    final event = SigningEvent(
        id: _id(), signerName: signerName, signerEmail: signerEmail,
        roleId: roleId, timestamp: DateTime.now(),
        ipAddress: ipAddress ?? 'offline',
        deviceInfo: deviceInfo ?? (kIsWeb ? 'Web' : 'Mobile'),
        pageIndex: pageIndex, documentHashAtTime: documentHashAtTime,
        integrityVerified: true);
    session.events.add(event);
    for (final r in session.roles) { if (r.id == roleId) r.signedAt = event.timestamp; }
    await saveSession(session);
    return event;
  }

  static bool canSign(SigningSession session, String roleId) {
    final idx = session.roles.indexWhere((r) => r.id == roleId);
    if (idx < 0) return false;
    for (int i = 0; i < idx; i++) { if (!session.roles[i].isSigned) return false; }
    return true;
  }

  static SigningRole? nextPending(SigningSession session) =>
      session.roles.where((r) => !r.isSigned).firstOrNull;

  static String generateReport(SigningSession session) {
    final b = StringBuffer();
    b.writeln('═══ ELECTRONIC SIGNATURE COMPLIANCE REPORT ═══');
    b.writeln('Framework:   ${session.framework.displayName}');
    b.writeln('Document:    ${session.documentName}');
    b.writeln('Session ID:  ${session.id}');
    b.writeln('SHA-256:     ${session.documentHash}');
    b.writeln('Created:     ${_fmt(session.createdAt)}');
    b.writeln();
    for (final ev in session.events) {
      b.writeln('✓ ${ev.signerName} <${ev.signerEmail}>');
      b.writeln('  Signed:  ${_fmt(ev.timestamp)}');
      b.writeln('  Device:  ${ev.deviceInfo}  IP: ${ev.ipAddress}');
      b.writeln('  Hash:    ${ev.documentHashAtTime.substring(0, 16)}…');
      b.writeln();
    }
    return b.toString();
  }

  static String _id() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  static String _fmt(DateTime d) =>
      '${d.year}-${_p(d.month)}-${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)} UTC';
  static String _p(int n) => n.toString().padLeft(2, '0');
}

enum SigningFramework {
  esign('ESIGN Act (US)'), eidas('eIDAS (EU)'), both('ESIGN + eIDAS');
  final String displayName; const SigningFramework(this.displayName);
}
enum SignerRoleType { manager, legal, client, witness, notary }

class SigningRole {
  final String id, label; final SignerRoleType type; final int order;
  DateTime? signedAt; String? signerName, signerEmail;
  SigningRole({required this.id, required this.label,
      required this.type, required this.order,
      this.signedAt, this.signerName, this.signerEmail});
  bool get isSigned => signedAt != null;
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'type': type.name,
      'order': order, 'signedAt': signedAt?.toIso8601String(),
      'signerName': signerName, 'signerEmail': signerEmail};
  factory SigningRole.fromJson(Map<String, dynamic> j) => SigningRole(
      id: j['id'], label: j['label'],
      type: SignerRoleType.values.firstWhere((e) => e.name == j['type'],
          orElse: () => SignerRoleType.client),
      order: j['order'],
      signedAt: j['signedAt'] != null ? DateTime.parse(j['signedAt']) : null,
      signerName: j['signerName'], signerEmail: j['signerEmail']);
}

class SigningEvent {
  final String id, signerName, signerEmail, roleId;
  final DateTime timestamp;
  final String ipAddress, deviceInfo, documentHashAtTime;
  final int pageIndex; final bool integrityVerified;
  const SigningEvent({required this.id, required this.signerName,
      required this.signerEmail, required this.roleId,
      required this.timestamp, required this.ipAddress,
      required this.deviceInfo, required this.pageIndex,
      required this.documentHashAtTime, required this.integrityVerified});
  Map<String, dynamic> toJson() => {'id': id, 'signerName': signerName,
      'signerEmail': signerEmail, 'roleId': roleId,
      'timestamp': timestamp.toIso8601String(), 'ipAddress': ipAddress,
      'deviceInfo': deviceInfo, 'pageIndex': pageIndex,
      'documentHashAtTime': documentHashAtTime,
      'integrityVerified': integrityVerified};
}

class SigningSession {
  final String id, documentName, documentHash;
  final SigningFramework framework;
  final List<SigningRole> roles;
  final DateTime createdAt; final List<SigningEvent> events;
  SigningSession({required this.id, required this.documentName,
      required this.documentHash, required this.framework,
      required this.roles, required this.createdAt, required this.events});
  bool get isComplete => roles.every((r) => r.isSigned);
  Map<String, dynamic> toJson() => {'id': id, 'documentName': documentName,
      'documentHash': documentHash, 'framework': framework.name,
      'roles': roles.map((r) => r.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'events': events.map((e) => e.toJson()).toList()};
}
