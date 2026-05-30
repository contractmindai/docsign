import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ds.dart'; // your DS colours

class AppleDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? child;
  final List<Widget> actions;
  final VoidCallback? onDismiss;
  final bool showCloseButton;

  const AppleDialog({
    super.key,
    required this.title,
    this.content,
    this.child,
    required this.actions,
    this.onDismiss,
    this.showCloseButton = true,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? child,
    required List<Widget> actions,
    VoidCallback? onDismiss,
    bool showCloseButton = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.3),
      useSafeArea: true,
      builder: (ctx) => AppleDialog(
        title: title,
        content: content,
        child: child,
        actions: actions,
        onDismiss: onDismiss,
        showCloseButton: showCloseButton,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedScale(
        scale: 1.0, // handled by dialog transition
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: DS.bgCard.withOpacity(0.88),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.12),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: DS.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            if (showCloseButton)
                              GestureDetector(
                                onTap: () {
                                  if (onDismiss != null) onDismiss!();
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (content != null || child != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: content != null
                              ? Text(
                                  content!,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: DS.textSecondary,
                                    height: 1.45,
                                    letterSpacing: -0.2,
                                  ),
                                )
                              : child,
                        ),
                      const SizedBox(height: 24),
                      Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Apple‑style button – clean, no background, large tap area
class AppleDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isDestructive;

  const AppleDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: isDestructive ? DS.red : DS.indigo,
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}