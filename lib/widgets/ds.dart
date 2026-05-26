import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DS — Premium Design System
// Human-crafted spacing, optical tuning, warm imperfections.
// ─────────────────────────────────────────────────────────────────────────────

class DS {
  // ── Organic spacing (irregular rhythm) ──────────────────────────────────
  static const double spaceXXL = 28;
  static const double spaceXL  = 24;
  static const double spaceL   = 18;
  static const double spaceM   = 14;
  static const double spaceS   = 10;
  static const double spaceXS  = 7;
  static const double spaceXXS = 4;

  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color bg          = Color(0xFF080808);
  static const Color bgCard      = Color(0xFF111113);
  static const Color bgCard2     = Color(0xFF18181B);
  static const Color bgHover     = Color(0xFF1F1F22);
  static const Color separator   = Color(0xFF27272A);
  static const Color separatorLight = Color(0xFF3F3F46);

  static const Color indigo      = Color(0xFF5B61F6);
  static const Color indigoLight = Color(0xFF7C5CFA);
  static const Color purple      = Color(0xFF8B5CF6);
  static const Color green       = Color(0xFF10B981);
  static const Color orange      = Color(0xFFF59E0B);
  static const Color red         = Color(0xFFEF4444);
  static const Color cyan        = Color(0xFF06B6D4);
  static const Color pink        = Color(0xFFEC4899);
  static const Color warm        = Color(0xFFCBA56C); // soft gold
  static const Color mist        = Color(0xFF94A3B8);

  static const Color textPrimary   = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color textTertiary  = Color(0xFF52525B);
  static const Color textMuted     = Color(0xFF3F3F46);

  // ── Typography ──────────────────────────────────────────────────────────
  static TextStyle display({double size = 48}) => GoogleFonts.inter(
    color: textPrimary, fontSize: size, fontWeight: FontWeight.w800,
    letterSpacing: -0.8, height: 1.05);

  static TextStyle heading({double size = 28}) => GoogleFonts.plusJakartaSans(
    color: textPrimary, fontSize: size, fontWeight: FontWeight.w700,
    letterSpacing: -0.6, height: 1.15);

  static TextStyle title({double size = 17}) => GoogleFonts.plusJakartaSans(
    color: textPrimary, fontSize: size, fontWeight: FontWeight.w600,
    letterSpacing: -0.3);

  static TextStyle body({double size = 14, Color? color}) => GoogleFonts.inter(
    color: color ?? mist, fontSize: size, fontWeight: FontWeight.w400,
    height: 1.6);

  static TextStyle label({double size = 12, Color? color}) => GoogleFonts.inter(
    color: color ?? textSecondary, fontSize: size, fontWeight: FontWeight.w500,
    letterSpacing: 0.2);

  static TextStyle caption() => GoogleFonts.inter(
    color: mist, fontSize: 12, fontWeight: FontWeight.w400);

  static TextStyle mono({double size = 12}) => GoogleFonts.sourceCodePro(
    color: textSecondary, fontSize: size);

  // ── Motion rhythm ───────────────────────────────────────────────────────
  static const Duration tapDuration    = Duration(milliseconds: 90);
  static const Duration hoverDuration  = Duration(milliseconds: 140);
  static const Duration dialogDuration = Duration(milliseconds: 240);
  static const Duration sheetDuration  = Duration(milliseconds: 320);

  // ── Status bar ─────────────────────────────────────────────────────────
  static void setStatusBar() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  // ── Cards: varied radii, layered shadows ───────────────────────────────
  static final BoxDecoration card = BoxDecoration(
    color: bgCard,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.white.withOpacity(0.04)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.28),
        blurRadius: 32,
        offset: const Offset(0, 16),
      ),
      BoxShadow(
        color: Colors.black.withOpacity(0.12),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ],
  );

  static final BoxDecoration cardHover = BoxDecoration(
    color: bgHover,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.white.withOpacity(0.08)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.32),
        blurRadius: 40,
        offset: const Offset(0, 20),
      ),
      BoxShadow(
        color: Colors.black.withOpacity(0.15),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ],
  );

  // ── Buttons: asymmetric internal spacing ───────────────────────────────
  static final BoxDecoration primaryBtn = BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF5B61F6), Color(0xFF8B5CF6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF5B61F6).withOpacity(0.35),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ],
  );

  static final BoxDecoration ghostBtn = BoxDecoration(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: separatorLight, width: 0.8),
  );

  // ── Surface noise ──────────────────────────────────────────────────────
  static final BoxDecoration surfaceNoise = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withOpacity(0.03),
        Colors.transparent,
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Widgets (with irregular spacing and asymmetric padding)
// ─────────────────────────────────────────────────────────────────────────────

/// Primary CTA button – taller, softer, asymmetrically weighted.
class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final double height;
  final double? width;
  final Color? color;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.loading = false,
    this.height = 52,
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
    _c = AnimationController(vsync: this, duration: DS.tapDuration);
    _s = Tween(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onTap() {
    if (widget.onTap == null) return;
    HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) _c.forward();
      },
      onTapUp: (_) {
        _c.reverse();
        _onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: ScaleTransition(
        scale: _s,
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: _buttonDecoration(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: DS.spaceXXS),
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 18),
                const SizedBox(width: DS.spaceS),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: DS.spaceXS),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _buttonDecoration() {
    if (widget.color != null) {
      return BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: widget.color!.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );
    }
    return DS.primaryBtn;
  }
}

/// Ghost button – minimal, with haptics
class GhostButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  const GhostButton({super.key, required this.label, this.icon, this.onTap, this.color});
  @override State<GhostButton> createState() => _GhostButtonState();
}
class _GhostButtonState extends State<GhostButton> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;
  bool _hover = false;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: DS.tapDuration);
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
        onTapUp: (_) {
          _c.reverse();
          if (widget.onTap != null) {
            HapticFeedback.lightImpact();
            widget.onTap!();
          }
        },
        onTapCancel: () => _c.reverse(),
        child: ScaleTransition(scale: _s,
          child: AnimatedContainer(
            duration: DS.hoverDuration,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: _hover ? DS.bgHover : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hover ? DS.separatorLight : DS.separator, width: 0.8)),
            child: Row(mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: c, size: 15),
                const SizedBox(width: DS.spaceS),
              ],
              Text(widget.label, style: TextStyle(
                  color: c, fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          )),
      ),
    );
  }
}

/// Icon button with haptics and subtle hover
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
      child: GestureDetector(
        onTap: () {
          if (widget.onTap != null) {
            HapticFeedback.lightImpact();
            widget.onTap!();
          }
        },
        child: AnimatedContainer(
          duration: DS.hoverDuration,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _hover ? DS.bgCard2 : Colors.transparent,
            borderRadius: BorderRadius.circular(10)),
          child: Icon(widget.icon, size: widget.size,
              color: widget.color ?? DS.textSecondary))),
    ));
}

/// Badge – uses warm accent as default, irregular padding
class DSBadge extends StatelessWidget {
  final String text; final Color color; final IconData? icon;
  const DSBadge({super.key, required this.text, required this.color, this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 5)],
      Text(text, style: TextStyle(color: color, fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 0.2)),
    ]));
}

/// Section header – irregular bottom margin
class DSSectionHeader extends StatelessWidget {
  final String title; final String? subtitle; final Widget? action;
  const DSSectionHeader({super.key, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: DS.heading(size: 22)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: DS.body(size: 13, color: DS.mist)),
        ],
      ])),
      if (action != null) action!,
    ]));
}

/// Premium card with hover effect and layered shadows
class DSCard extends StatefulWidget {
  final Widget child; final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const DSCard({super.key, required this.child, this.onTap,
      this.padding = const EdgeInsets.all(20)});
  @override State<DSCard> createState() => _DSCardState();
}
class _DSCardState extends State<DSCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit:  (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: DS.hoverDuration,
        padding: widget.padding,
        decoration: _hover && widget.onTap != null ? DS.cardHover : DS.card,
        child: widget.child)));
}

/// Surface noise wrapper – use VERY sparingly (only onboarding, settings)
class SurfaceNoise extends StatelessWidget {
  final Widget child;
  const SurfaceNoise({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: DS.surfaceNoise,
      child: child,
    );
  }
}

/// Gradient text – use ONLY for onboarding hero or premium headers
class GradientText extends StatelessWidget {
  final String text; final TextStyle? style;
  final List<Color> colors;
  const GradientText(this.text, {super.key, this.style,
      this.colors = const [Color(0xFF5B61F6), Color(0xFF8B5CF6)]});
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (bounds) => LinearGradient(colors: colors).createShader(bounds),
    child: Text(text, style: (style ?? DS.heading()).copyWith(color: Colors.white)));
}

/// Tab bar – pill shape, varied internal spacing
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
          duration: DS.hoverDuration,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? DS.indigo : DS.bgCard2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? DS.indigo.withOpacity(0.5) : DS.separator, width: 0.5),
            boxShadow: active ? [
              BoxShadow(color: DS.indigo.withOpacity(0.25), blurRadius: 12)
            ] : null,
          ),
          child: Text(e.value, style: TextStyle(
              color: active ? Colors.white : DS.textSecondary,
              fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w500))),
      );
    }).toList()));
}

/// Keyboard hint – unchanged
class DSKeyHint extends StatelessWidget {
  final String key_;
  const DSKeyHint(this.key_, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: DS.bgCard2, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: DS.separator)),
    child: Text(key_, style: DS.mono(size: 10)));
}

// ─────────────────────────────────────────────────────────────────────────────
// ADDED: DSTopBar – used in HomeScreen for web/mobile templates
// ─────────────────────────────────────────────────────────────────────────────
class DSTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final List<Widget>? actions;
  final VoidCallback? onBackPressed;
  final Color? backgroundColor;

  const DSTopBar({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.actions,
    this.onBackPressed,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? DS.bgCard,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (showBackButton)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: DSIconBtn(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: 'Back',
                    onTap: onBackPressed ?? () => Navigator.pop(context),
                    color: DS.indigo,
                    size: 20,
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  style: DS.title(size: 18).copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}