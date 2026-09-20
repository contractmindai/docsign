import 'package:flutter/material.dart';

enum PdfToolKind {
  merge,
  extract,
  rotate,
  watermark,
  duplicate,
  qrCode,
  jpg,
  fillForm,   // → PdfFormFillerScreen   (pick existing PDF, fill it)
  makeForm,   // → PdfFormCreatorScreen  (build a new PDF from scratch)
  deletePages,
  reorderPages,
  movePage,
  compress,
  optimizeImages,
  stamp,
  convertPdfA,
}

class ToolItem {
  final PdfToolKind kind;
  final String name;
  final IconData icon;
  final String description;

  const ToolItem({
    required this.kind,
    required this.name,
    required this.icon,
    required this.description,
  });
}

const List<ToolItem> kAllTools = [
  // ── Form tools — fully independent of each other ───────────────────────────
  ToolItem(
    kind: PdfToolKind.makeForm,
    name: 'Create Form',
    icon: Icons.dynamic_form_rounded,
    description: 'Build a new fillable PDF from scratch',
  ),
  ToolItem(
    kind: PdfToolKind.fillForm,
    name: 'Fill Form',
    icon: Icons.edit_document,
    description: 'Open & fill any AcroForm PDF',
  ),

  // ── Other tools (unchanged) ────────────────────────────────────────────────
  ToolItem(kind: PdfToolKind.merge,          name: 'Merge',           icon: Icons.merge_rounded,              description: 'Combine multiple PDFs into one'),
  ToolItem(kind: PdfToolKind.extract,        name: 'Extract',         icon: Icons.content_cut_rounded,        description: 'Extract selected pages to a new PDF'),
  ToolItem(kind: PdfToolKind.rotate,         name: 'Rotate',          icon: Icons.rotate_right_rounded,       description: 'Rotate selected pages'),
  ToolItem(kind: PdfToolKind.duplicate,      name: 'Duplicate',       icon: Icons.copy_rounded,               description: 'Duplicate selected pages'),
  ToolItem(kind: PdfToolKind.watermark,      name: 'Watermark',       icon: Icons.branding_watermark_rounded, description: 'Add a text watermark'),
  ToolItem(kind: PdfToolKind.qrCode,         name: 'QR Code',         icon: Icons.qr_code_rounded,            description: 'Add a QR code to every page'),
  ToolItem(kind: PdfToolKind.jpg,            name: 'Export to JPG',   icon: Icons.image_rounded,              description: 'Export pages as JPG images'),
  ToolItem(kind: PdfToolKind.deletePages,    name: 'Delete Pages',    icon: Icons.delete_outline_rounded,     description: 'Remove selected pages'),
  ToolItem(kind: PdfToolKind.reorderPages,   name: 'Reorder Pages',   icon: Icons.swap_vert_rounded,          description: 'Rearrange page order'),
  ToolItem(kind: PdfToolKind.movePage,       name: 'Move Page',       icon: Icons.call_made_rounded,          description: 'Move a page to a new position'),
  ToolItem(kind: PdfToolKind.compress,       name: 'Compress',        icon: Icons.compress_rounded,           description: 'Reduce file size'),
  ToolItem(kind: PdfToolKind.optimizeImages, name: 'Optimize Images', icon: Icons.image_rounded,              description: 'Recompress images (advanced)'),
];
