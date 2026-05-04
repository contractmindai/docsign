import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DS — Premium Design System
// Inspired by Linear, Vercel, Notion dark themes
// ─────────────────────────────────────────────────────────────────────────────

class DS {
  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color bg          = Color(0xFF080808); // true near-black
  static const Color bgCard      = Color(0xFF111113); // elevated surface
  static const Color bgCard2     = Color(0xFF18181B); // deeper card
  static const Color bgHover     = Color(0xFF1F1F22); // hover state
  static const Color separator   = Color(0xFF27272A); // borders
  static const Color separatorLight = Color(0xFF3F3F46);

  // ── Brand ────────────────────────────────────────────────────────────────
  static const Color indigo      = Color(0xFF6366F1); // primary
  static const Color indigoLight = Color(0xFF818CF8);
  static const Color purple      = Color(0xFF8B5CF6);
  static const Color green       = Color(0xFF10B981);
  static const Color orange      = Color(0xFFF59E0B);
  static const Color red         = Color(0xFFEF4444);
  static const Color cyan        = Color(0xFF06B6D4);
  static const Color pink        = Color(0xFFEC4899);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color textTertiary  = Color(0xFF52525B);
  static const Color textMuted     = Color(0xFF3F3F46);

  // ── Typography ────────────────────────────────────────────────────────────
  static TextStyle display({double size = 48}) => GoogleFonts.inter(
    color: textPrimary, fontSize: size, fontWeight: FontWeight.w800,
    letterSpacing: -2.0, height: 1.05);

  static TextStyle heading({double size = 28}) => GoogleFonts.inter(
    color: textPrimary, fontSize: size, fontWeight: FontWeight.w700,
    letterSpacing: -0.8, height: 1.15);

  static TextStyle title({double size = 17}) => GoogleFonts.inter(
    color: textPrimary, fontSize: size, fontWeight: FontWeight.w600,
    letterSpacing: -0.3);

  static TextStyle body({double size = 14, Color? color}) => GoogleFonts.inter(
    color: color ?? textSecondary, fontSize: size, fontWeight: FontWeight.w400,
    height: 1.6);

  static TextStyle label({double size = 12, Color? color}) => GoogleFonts.inter(
    color: color ?? textSecondary, fontSize: size, fontWeight: FontWeight.w500,
    letterSpacing: 0.2);

  static TextStyle caption() => GoogleFonts.inter(
    color: textSecondary, fontSize: 12, fontWeight: FontWeight.w400);

  static TextStyle mono({double size = 12}) => GoogleFonts.sourceCodePro(
    color: textSecondary, fontSize: size);

  // ── Status bar ─────────────────────────────────────────────────────────
  static void setStatusBar() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  // ── Premium button decorations ────────────────────────────────────────────
  static BoxDecoration primaryBtn = BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      begin: Alignment.topLeft, end: Alignment.bottomRight),
    borderRadius: BorderRadius.circular(10),
    boxShadow: [
      BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.35),
          blurRadius: 16, offset: const Offset(0, 4)),
    ]);

  static BoxDecoration ghostBtn = BoxDecoration(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: separatorLight, width: 1));

  static BoxDecoration card = BoxDecoration(
    color: bgCard, borderRadius: BorderRadius.circular(14),
    border: Border.all(color: separator, width: 0.5));

  static BoxDecoration cardHover = BoxDecoration(
    color: bgHover, borderRadius: BorderRadius.circular(14),
    border: Border.all(color: separatorLight, width: 0.5));
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Gradient-filled primary CTA button with spring press animation.
/// Optionally provide a solid [color] to override the default gradient.
class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final double height;
  final double? width;
  final Color? color; // NEW: optional solid color (replaces gradient)

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.loading = false,
    this.height = 48,
    this.width,
    this.color,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _s = Tween(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) _c.forward();
      },
      onTapUp: (_) {
        _c.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _c.reverse(),
      child: ScaleTransition(
        scale: _s,
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: _buttonDecoration(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              else ...[
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _buttonDecoration() {
    if (widget.color != null) {
      // Solid color button with matching shadow
      return BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: widget.color!.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      );
    }
    // Default gradient
    return DS.primaryBtn;
  }
}

/// Ghost / outlined button
class GhostButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  const GhostButton({super.key, required this.label, this.icon, this.onTap, this.color});
  @override State<GhostButton> createState() => _GhostButtonState();
}
class _GhostButtonState extends State<GhostButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;
  bool _hover = false;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _s = Tween(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? DS.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) { _c.reverse(); widget.onTap?.call(); },
        onTapCancel: () => _c.reverse(),
        child: ScaleTransition(scale: _s,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _hover ? DS.bgHover : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _hover ? DS.separatorLight : DS.separator)),
            child: Row(mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: c, size: 14),
                const SizedBox(width: 7),
              ],
              Text(widget.label, style: TextStyle(
                  color: c, fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          )),
      ),
    );
  }
}

/// Icon button with tooltip and hover state
class DSIconBtn extends StatefulWidget {
  final IconData icon; final String tooltip;
  final VoidCallback? onTap; final Color? color; final double size;
  const DSIconBtn({super.key, required this.icon, required this.tooltip,
      this.onTap, this.color, this.size = 20});
  @override State<DSIconBtn> createState() => _DSIconBtnState();
}
class _DSIconBtnState extends State<DSIconBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => Tooltip(message: widget.tooltip,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _hover ? DS.bgCard2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
          child: Icon(widget.icon, size: widget.size,
              color: widget.color ?? DS.textSecondary))),
    ));
}

/// Premium badge/tag
class DSBadge extends StatelessWidget {
  final String text; final Color color; final IconData? icon;
  const DSBadge({super.key, required this.text, required this.color, this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 10, color: color), const SizedBox(width: 5)],
      Text(text, style: TextStyle(color: color, fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 0.2)),
    ]));
}

/// Section header with optional action
class DSSectionHeader extends StatelessWidget {
  final String title; final String? subtitle; final Widget? action;
  const DSSectionHeader({super.key, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: DS.heading(size: 22)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: DS.body(size: 13)),
        ],
      ])),
      if (action != null) action!,
    ]));
}

/// Premium card with hover effect
class DSCard extends StatefulWidget {
  final Widget child; final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const DSCard({super.key, required this.child, this.onTap,
      this.padding = const EdgeInsets.all(16)});
  @override State<DSCard> createState() => _DSCardState();
}
class _DSCardState extends State<DSCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit:  (_) => setState(() => _hover = false),
    child: GestureDetector(onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: widget.padding,
        decoration: _hover && widget.onTap != null ? DS.cardHover : DS.card,
        child: widget.child)));
}

/// Gradient text
class GradientText extends StatelessWidget {
  final String text; final TextStyle? style;
  final List<Color> colors;
  const GradientText(this.text, {super.key, this.style,
      this.colors = const [Color(0xFF6366F1), Color(0xFF8B5CF6)]});
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (bounds) => LinearGradient(colors: colors).createShader(bounds),
    child: Text(text, style: (style ?? DS.heading()).copyWith(color: Colors.white)));
}

/// Animated tab selector
class DSTabBar extends StatelessWidget {
  final List<String> tabs; final int current;
  final ValueChanged<int> onTap;
  const DSTabBar({super.key, required this.tabs, required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: tabs.asMap().entries.map((e) {
      final active = e.key == current;
      return GestureDetector(
        onTap: () => onTap(e.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? DS.indigo : DS.bgCard2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? DS.indigo.withOpacity(0.6) : DS.separator)),
          child: Text(e.value, style: TextStyle(
              color: active ? Colors.white : DS.textSecondary,
              fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w500))),
      );
    }).toList()));
}

/// Keyboard shortcut hint
class DSKeyHint extends StatelessWidget {
  final String key_;
  const DSKeyHint(this.key_, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: DS.bgCard2, borderRadius: BorderRadius.circular(4),
      border: Border.all(color: DS.separator)),
    child: Text(key_, style: DS.mono(size: 10)));
}