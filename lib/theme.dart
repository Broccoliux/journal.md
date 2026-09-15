import 'package:flutter/material.dart';

/// Design system for journal.md.
///
/// Direction: *a physical journal from the future*. Warm paper and real ink in
/// light mode, a quiet instrument panel at night. Depth comes from hairline
/// rules and tonal surfaces rather than shadows, and the type hierarchy does
/// the heavy lifting.
class Tokens {
  const Tokens._();

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s7 = 48;
  static const double s8 = 64;

  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 18;
  static const double rXl = 26;

  /// Content column widths.
  static const double readingWidth = 720;
  static const double appMaxWidth = 1500;

  /// Shell breakpoints.
  static const double mobile = 760;
  static const double desktop = 1180;
}

/// Typographic voices. `serif` carries the literary tone in titles and prose
/// headings; `sans` keeps the interface crisp; `mono` is for technical work.
///
/// Only system families are used so the app never needs the network.
class AppFonts {
  const AppFonts._();

  static const String serif =
      '"Iowan Old Style", "Palatino Linotype", Palatino, "Book Antiqua", '
      'Georgia, "Times New Roman", serif';
  static const String sans =
      'Inter, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, '
      'sans-serif';
  static const String mono =
      '"JetBrains Mono", "SF Mono", "Cascadia Mono", "Roboto Mono", Consolas, '
      '"Liberation Mono", Menlo, monospace';
}

/// Custom colours Material 3 does not model.
@immutable
class Ink extends ThemeExtension<Ink> {
  const Ink({
    required this.canvas,
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceRaised,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.textSoft,
    required this.textFaint,
    required this.accent,
    required this.accentInk,
    required this.accentWash,
    required this.brass,
    required this.codeBg,
    required this.codeLine,
    required this.danger,
    required this.shadow,
  });

  /// Page background.
  final Color canvas;

  /// Cards, sheets, panels.
  final Color surface;

  /// Inset areas: search fields, rails.
  final Color surfaceSunken;

  /// Hovered / raised surfaces.
  final Color surfaceRaised;

  /// Hairline rules — the main depth device.
  final Color line;
  final Color lineStrong;

  final Color text;
  final Color textSoft;
  final Color textFaint;

  final Color accent;
  final Color accentInk;
  final Color accentWash;
  final Color brass;

  final Color codeBg;
  final Color codeLine;

  final Color danger;
  final Color shadow;

  /// Paper: warm, tactile, daylight.
  static const Ink paper = Ink(
    canvas: Color(0xFFF4F1EB),
    surface: Color(0xFFFCFBF8),
    surfaceSunken: Color(0xFFEDE9E1),
    surfaceRaised: Color(0xFFFFFFFF),
    line: Color(0xFFE0DACE),
    lineStrong: Color(0xFFC9C2B4),
    text: Color(0xFF181A1C),
    textSoft: Color(0xFF5A5E66),
    textFaint: Color(0xFF8D9099),
    accent: Color(0xFF0E6A5F),
    accentInk: Color(0xFFF7FBF9),
    accentWash: Color(0x140E6A5F),
    brass: Color(0xFF9C7538),
    codeBg: Color(0xFF1B1E22),
    codeLine: Color(0xFF2C3138),
    danger: Color(0xFFB3261E),
    shadow: Color(0x1A000000),
  );

  /// Midnight: low light, phosphor accents, still paper-like in feel.
  static const Ink midnight = Ink(
    canvas: Color(0xFF0A0B0D),
    surface: Color(0xFF121417),
    surfaceSunken: Color(0xFF0E1013),
    surfaceRaised: Color(0xFF1A1D21),
    line: Color(0xFF24282E),
    lineStrong: Color(0xFF343A42),
    text: Color(0xFFE9E7E1),
    textSoft: Color(0xFF9AA0A8),
    textFaint: Color(0xFF6D737C),
    accent: Color(0xFF6FDDC6),
    accentInk: Color(0xFF06201C),
    accentWash: Color(0x246FDDC6),
    brass: Color(0xFFD9B063),
    codeBg: Color(0xFF14161A),
    codeLine: Color(0xFF23272E),
    danger: Color(0xFFF2B8B5),
    shadow: Color(0x66000000),
  );

  Ink _withBase(Ink base) => base;

  @override
  Ink copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceSunken,
    Color? surfaceRaised,
    Color? line,
    Color? lineStrong,
    Color? text,
    Color? textSoft,
    Color? textFaint,
    Color? accent,
    Color? accentInk,
    Color? accentWash,
    Color? brass,
    Color? codeBg,
    Color? codeLine,
    Color? danger,
    Color? shadow,
  }) => _withBase(
    Ink(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      text: text ?? this.text,
      textSoft: textSoft ?? this.textSoft,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      accentWash: accentWash ?? this.accentWash,
      brass: brass ?? this.brass,
      codeBg: codeBg ?? this.codeBg,
      codeLine: codeLine ?? this.codeLine,
      danger: danger ?? this.danger,
      shadow: shadow ?? this.shadow,
    ),
  );

  @override
  Ink lerp(ThemeExtension<Ink>? other, double t) {
    if (other is! Ink) return this;
    return Ink(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSoft: Color.lerp(textSoft, other.textSoft, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      brass: Color.lerp(brass, other.brass, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeLine: Color.lerp(codeLine, other.codeLine, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Convenience accessors on [BuildContext].
extension InkContext on BuildContext {
  Ink get ink => Theme.of(this).extension<Ink>() ?? Ink.paper;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// True when the platform asks for reduced motion.
  bool get reducedMotion =>
      MediaQuery.maybeOf(this)?.disableAnimations ?? false;

  /// Collapses any duration to zero under reduced motion.
  Duration motion(Duration d) => reducedMotion ? Duration.zero : d;
}

/// Builds the two [ThemeData]s used by the app.
class JournalTheme {
  const JournalTheme._();

  static ThemeData light() => _build(Ink.paper, Brightness.light);

  static ThemeData dark() => _build(Ink.midnight, Brightness.dark);

  static ThemeData _build(Ink ink, Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: ink.accent,
      brightness: brightness,
    ).copyWith(
      surface: ink.surface,
      onSurface: ink.text,
      primary: ink.accent,
      onPrimary: ink.accentInk,
      outline: ink.lineStrong,
      outlineVariant: ink.line,
      error: ink.danger,
    );

    final TextTheme text = _textTheme(ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: ink.canvas,
      canvasColor: ink.canvas,
      textTheme: text,
      primaryTextTheme: text,
      fontFamily: AppFonts.sans,
      extensions: <ThemeExtension<dynamic>>[ink],
      // Motion: fade + a short vertical settle. Deliberately quiet.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: SettleTransition(),
          TargetPlatform.iOS: SettleTransition(),
          TargetPlatform.macOS: SettleTransition(),
          TargetPlatform.windows: SettleTransition(),
          TargetPlatform.linux: SettleTransition(),
          TargetPlatform.fuchsia: SettleTransition(),
        },
      ),
      dividerTheme: DividerThemeData(color: ink.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: ink.textSoft, size: 20),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 420),
        decoration: BoxDecoration(
          color: ink.text,
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
        textStyle: TextStyle(
          color: ink.canvas,
          fontSize: 12.5,
          fontFamily: AppFonts.sans,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(7),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll<Color>(ink.lineStrong),
        crossAxisMargin: 2,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ink.surfaceSunken,
        side: BorderSide(color: ink.line),
        labelStyle: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12,
          color: ink.textSoft,
          letterSpacing: 0.2,
        ),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink.text,
        contentTextStyle: TextStyle(
          color: ink.canvas,
          fontFamily: AppFonts.sans,
          fontSize: 14,
        ),
        actionTextColor: ink.brass,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
        ),
      ),
      inputDecorationTheme: _inputTheme(ink),
      dialogTheme: DialogThemeData(
        backgroundColor: ink.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rLg),
          side: BorderSide(color: ink.line),
        ),
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.serif,
          fontSize: 22,
          height: 1.25,
          color: ink.text,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14.5,
          height: 1.55,
          color: ink.textSoft,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> s) =>
                s.contains(WidgetState.disabled) ? ink.lineStrong : ink.accent,
          ),
          foregroundColor: WidgetStatePropertyAll<Color>(ink.accentInk),
          elevation: const WidgetStatePropertyAll<double>(0),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rMd),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(ink.accent),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rSm),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: ink.line)),
          foregroundColor: WidgetStatePropertyAll<Color>(ink.text),
          backgroundColor: WidgetStatePropertyAll<Color>(ink.surface),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rMd),
            ),
          ),
        ),
      ),
      );
  }

  static InputDecorationTheme _inputTheme(Ink ink) {
    OutlineInputBorder border(Color c, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
          borderSide: BorderSide(color: c, width: width),
        );

    return InputDecorationTheme(
      filled: true,
      fillColor: ink.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
      hintStyle: TextStyle(
        color: ink.textFaint,
        fontFamily: AppFonts.sans,
        fontSize: 14.5,
      ),
      labelStyle: TextStyle(
        color: ink.textSoft,
        fontFamily: AppFonts.sans,
        fontSize: 14,
      ),
      floatingLabelStyle: TextStyle(
        color: ink.accent,
        fontFamily: AppFonts.sans,
        fontSize: 14,
      ),
      border: border(ink.line),
      enabledBorder: border(ink.line),
      focusedBorder: border(ink.accent, 1.6),
      errorBorder: border(ink.danger),
      focusedErrorBorder: border(ink.danger, 1.6),
      errorStyle: TextStyle(color: ink.danger, fontSize: 12.5),
    );
  }
  static TextTheme _textTheme(Ink ink) {
    final Color strong = ink.text;
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 44,
        height: 1.08,
        letterSpacing: -0.9,
        fontWeight: FontWeight.w600,
        color: strong,
      ),
      displayMedium: TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 34,
        height: 1.12,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w600,
        color: strong,
      ),
      displaySmall: TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 27,
        height: 1.18,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w600,
        color: strong,
      ),
      headlineMedium: TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 23,
        height: 1.25,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w600,
        color: strong,
      ),
      headlineSmall: TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 20,
        height: 1.3,
        color: strong,
      ),
      titleLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 17,
        height: 1.35,
        letterSpacing: -0.1,
        fontWeight: FontWeight.w600,
        color: strong,
      ),
      titleMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: strong,
      ),
      titleSmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: ink.textSoft,
      ),
      bodyLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 15.5,
        height: 1.6,
        color: strong,
      ),
      bodyMedium: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 14,
        height: 1.6,
        color: ink.textSoft,
      ),
      bodySmall: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 12.5,
        height: 1.5,
        color: ink.textFaint,
      ),
      labelLarge: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: strong,
      ),
      labelMedium: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 11.5,
        letterSpacing: 0.6,
        color: ink.textSoft,
      ),
      labelSmall: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 10.5,
        letterSpacing: 0.9,
        color: ink.textFaint,
      ),
    );
  }
}

/// Quiet page transition: fade with a small vertical settle, so pushing a page
/// feels like turning a page rather than a carousel.
class SettleTransition extends PageTransitionsBuilder {
  const SettleTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context.reducedMotion) return child;
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
