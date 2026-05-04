import 'dart:convert';
import 'dart:typed_data';

// ── Signer profile ────────────────────────────────────────────────────────────

class SignerProfile {
  final String fullName;
  final String title;
  final String company;
  final String email;

  const SignerProfile({
    required this.fullName,
    this.title = '',
    this.company = '',
    this.email = '',
  });

  bool get isEmpty => fullName.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'title': title,
        'company': company,
        'email': email,
      };

  factory SignerProfile.fromJson(Map<String, dynamic> j) => SignerProfile(
        fullName: j['fullName'] ?? '',
        title: j['title'] ?? '',
        company: j['company'] ?? '',
        email: j['email'] ?? '',
      );

  /// One-line summary for the audit trail.
  String get displayLine {
    final parts = [fullName, if (title.isNotEmpty) title, if (company.isNotEmpty) company];
    return parts.join(' · ');
  }
}

// ── Saved signature ───────────────────────────────────────────────────────────

class SavedSignature {
  final String id;
  final String label;         // "Full signature", "Initials", etc.
  final Uint8List pngBytes;
  final DateTime createdAt;

  const SavedSignature({
    required this.id,
    required this.label,
    required this.pngBytes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'pngBytes': base64Encode(pngBytes),
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedSignature.fromJson(Map<String, dynamic> j) => SavedSignature(
        id: j['id'],
        label: j['label'],
        pngBytes: base64Decode(j['pngBytes']),
        createdAt: DateTime.parse(j['createdAt']),
      );
}
