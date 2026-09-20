import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/platform_file_service.dart';
import '../utils/app_localizations.dart';
import '../widgets/ds.dart';
import 'pdf_tool_kind.dart';
import 'pdf_tools_screen.dart';
import 'pdf_form_filler_screen.dart';
import 'pdf_form_creator_screen.dart';

/// Two independent form tools:
///   "Fill Form"   → PdfFormFillerScreen   → pick a PDF, fill its fields
///   "Create Form" → PdfFormCreatorScreen  → choose Blank or Add-to-existing
///
/// "Create Form" handles its own internal mode choice (blank vs existing).
/// When the user picks "Add Fields to a PDF" inside that screen, it pops
/// back here with {'requestPickExisting': true} so this menu can use the
/// app's existing file picker, then re-opens the creator with that file —
/// this keeps PlatformFileService usage centralized in one place, same as
/// every other tool in this menu.
class PdfToolsMenuScreen extends StatelessWidget {
  final void Function(String displayName, Map<String, dynamic> result)? onToolComplete;

  const PdfToolsMenuScreen({super.key, this.onToolComplete});

  Future<void> _openFormCreator(BuildContext context, {String? path, dynamic bytes}) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfFormCreatorScreen(
          existingFilePath: path,
          existingFileBytes: bytes,
        ),
      ),
    );

    if (result == null || !context.mounted) return;

    // Creator screen wants a file picked (user chose "Add Fields to a PDF"
    // without one provided) — pick it here and relaunch the creator with it.
    if (result['requestPickExisting'] == true) {
      final picked = await PlatformFileService.pickPdf();
      if (picked == null || !context.mounted) return;
      await _openFormCreator(context, path: picked.virtualPath, bytes: picked.bytes);
      return;
    }

    onToolComplete?.call(
      result['path']?.toString().split('/').last ?? 'form.pdf',
      result,
    );
  }

  Future<void> _onToolTap(BuildContext context, ToolItem tool) async {
    if (tool.kind == PdfToolKind.makeForm) {
      await _openFormCreator(context);
      return;
    }

    try {
      final picked = await PlatformFileService.pickPdf();
      if (picked == null || !context.mounted) return;

      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(builder: (_) {
          if (tool.kind == PdfToolKind.fillForm) {
            return PdfFormFillerScreen(
              filePath: picked.virtualPath,
              fileBytes: picked.bytes,
            );
          }
          return PdfToolsScreen(
            filePath: picked.virtualPath,
            fileBytes: picked.bytes,
            initialTool: tool.kind,
          );
        }),
      );

      if (result != null && context.mounted) {
        onToolComplete?.call(picked.displayName, result);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: $e'), backgroundColor: DS.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(l10n.pdfTools,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose a tool', style: DS.heading(size: 24)),
            const SizedBox(height: 4),
            Text('Select a PDF after choosing a tool', style: DS.body(size: 14, color: DS.textSecondary)),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.2,
                ),
                itemCount: kAllTools.length,
                itemBuilder: (context, index) {
                  final tool = kAllTools[index];
                  return _ToolCard(tool: tool, onTap: () => _onToolTap(context, tool));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolItem tool;
  final VoidCallback onTap;
  const _ToolCard({required this.tool, required this.onTap});

  bool get _isFeatured => tool.kind == PdfToolKind.fillForm || tool.kind == PdfToolKind.makeForm;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isFeatured ? DS.indigo.withOpacity(0.12) : DS.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isFeatured ? DS.indigo.withOpacity(0.5) : DS.separator,
            width: _isFeatured ? 1.5 : 1.0,
          ),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tool.icon, size: 36, color: DS.indigo),
            const SizedBox(height: 8),
            Text(tool.name, style: const TextStyle(color: DS.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tool.description, style: TextStyle(color: DS.textSecondary, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
