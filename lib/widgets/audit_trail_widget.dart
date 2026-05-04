import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/ds.dart';

// Visual audit trail timeline — shown as a bottom sheet
class AuditTrailSheet extends StatelessWidget {
  final String documentName;
  final List<AuditEvent> events;

  const AuditTrailSheet({
    super.key, required this.documentName, required this.events,
  });

  static Future<void> show({
    required BuildContext context,
    required String documentName,
    required List<AuditEvent> events,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => AuditTrailSheet(
          documentName: documentName, events: events),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DS.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle
        Center(child: Container(
          margin: const EdgeInsets.only(top: 10),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: DS.separator, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: DS.indigo.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.verified_rounded, color: DS.indigo, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Audit Trail', style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              Text(documentName, style: DS.caption(),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        const Divider(height: 1, color: DS.separator),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          itemCount: events.length,
          itemBuilder: (_, i) => _TimelineEvent(
            event: events[i],
            isFirst: i == 0,
            isLast: i == events.length - 1,
          ),
        )),
      ]),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  final AuditEvent event;
  final bool isFirst, isLast;
  const _TimelineEvent({required this.event,
      required this.isFirst, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Timeline line + dot
        SizedBox(width: 32, child: Column(
          crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (!isFirst)
            Container(width: 2, height: 12, color: DS.separator),
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: event.color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: event.color, width: 1.5)),
            child: Icon(event.icon, size: 13, color: event.color)),
          if (!isLast)
            Expanded(child: Container(width: 2, color: DS.separator)),
        ])),
        const SizedBox(width: 14),
        // Content
        Expanded(child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DS.bgCard2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DS.separator, width: 0.5)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(event.title, style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w600))),
              Text(event.timestamp, style: DS.caption().copyWith(fontSize: 10)),
            ]),
            if (event.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(event.subtitle!, style: DS.caption()),
            ],
            if (event.metadata != null) ...[
              const SizedBox(height: 8),
              ...event.metadata!.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Text('${e.key}: ', style: DS.caption().copyWith(
                      fontSize: 10, fontWeight: FontWeight.w600)),
                  Expanded(child: Text(e.value, style: DS.caption().copyWith(fontSize: 10),
                      overflow: TextOverflow.ellipsis)),
                ]),
              )),
            ],
          ]),
        )),
      ]),
    );
  }
}

class AuditEvent {
  final String title;
  final String? subtitle;
  final String timestamp;
  final IconData icon;
  final Color color;
  final Map<String, String>? metadata;

  const AuditEvent({
    required this.title,
    this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.color,
    this.metadata,
  });

  // Factory constructors for common events
  static AuditEvent created(String docName) => AuditEvent(
    title: 'Document Created',
    subtitle: docName,
    timestamp: _now(),
    icon: Icons.description_rounded,
    color: DS.indigo,
  );

  static AuditEvent opened() => AuditEvent(
    title: 'Document Opened',
    timestamp: _now(),
    icon: Icons.folder_open_rounded,
    color: DS.indigo,
  );

  static AuditEvent signed(String signerName, int page) => AuditEvent(
    title: 'Signed',
    subtitle: 'p.$page by $signerName',
    timestamp: _now(),
    icon: Icons.draw_rounded,
    color: DS.green,
    metadata: {'Signer': signerName, 'Page': '$page'},
  );

  static AuditEvent initialled(String signerName, int page) => AuditEvent(
    title: 'Initialled',
    subtitle: 'p.$page by $signerName',
    timestamp: _now(),
    icon: Icons.fingerprint_rounded,
    color: DS.green,
    metadata: {'Signer': signerName, 'Page': '$page'},
  );

  static AuditEvent annotated(String type, int page) => AuditEvent(
    title: 'Annotated',
    subtitle: '$type on p.$page',
    timestamp: _now(),
    icon: Icons.rate_review_rounded,
    color: DS.orange,
  );

  static AuditEvent redacted(int page) => AuditEvent(
    title: 'Redaction Applied',
    subtitle: 'Content permanently removed from p.$page',
    timestamp: _now(),
    icon: Icons.hide_source_rounded,
    color: DS.red,
    metadata: {'Status': 'Text data permanently removed'},
  );

  static AuditEvent saved(String path) => AuditEvent(
    title: 'Document Saved',
    subtitle: path.split('/').last,
    timestamp: _now(),
    icon: Icons.save_rounded,
    color: DS.indigo,
  );

  static String _now() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2,'0')}:'
        '${d.minute.toString().padLeft(2,'0')} '
        '${d.day}/${d.month}';
  }
}
