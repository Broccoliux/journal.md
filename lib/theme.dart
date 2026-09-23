/// journal.md theme — a quiet, editorial "digital notebook".
///
/// Paper-cream light mode, warm near-black dark mode, a single ink-blue
/// accent, Lora for display type, Inter for UI, Roboto Mono for code.
library;

import 'package:flutter/material.dart';

const _paper = Color(0xFFFBFAF8);
const _paperSurface = Color(0xFFFFFFFF);
const _paperLow = Color(0xFFF3F1EC);
const _ink = Color(0xFF211F1B);
const _inkVariant = Color(0xFF6F6A62);
const _line = Color(0xFFDBD6CD);
const _lineSoft = Color(0xFFE9E5DD);
const _inkBlue = Color(0xFF2E5A6B);
const _inkBlueDeep = Color(0xFF234956);

const _night = Color(0xFF161514);
const _nightSurface = Color(0xFF1C1B19);
const _nightLow = Color(0xFF232220);
const _nightInk = Color(0xFFE9E5DE);
const _nightInkVariant = Color(0xFFA8A29A);
const _nightLine = Color(0xFF35322E);
const _nightLineSoft = Color(0xFF292724);
const _nightBlue = Color(0xFF9CC0CB);

TextTheme _textTheme(ColorScheme scheme) {
  final base = Typography.material2021().black;
  return base
      .apply(
        fontFamily: 'Inter',
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displaySmall: TextStyle(
          fontFamily: 'Lora',
          fontWeight: FontWeight.w600,
          fontSize: 30,
          height: 1.25,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Lora',
          fontWeight: FontWeight.w600,
          fontSize: 22,
          height: 1.3,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Lora',
          fontWeight: FontWeight.w600,
          fontSize: 18,
          height: 1.35,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 15,
          height: 1.4,
          color: scheme.onSurface,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          height: 1.4,
          letterSpacing: 0.1,
          color: scheme.onSurfaceVariant,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 15.5,
          height: 1.7,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 14,
          height: 1.6,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
          fontSize: 12.5,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          fontSize: 11.5,
          height: 1.4,
          letterSpacing: 0.3,
          color: scheme.onSurfaceVariant,
        ),
      );
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.light
      ? ColorScheme.light(
          primary: _inkBlueDeep,
          onPrimary: Colors.white,
          secondary: _inkBlue,
          onSecondary: Colors.white,
          surface: _paperSurface,
          onSurface: _ink,
          surfaceContainerLow: _paperLow,
          surfaceContainerLowest: _paper,
          onSurfaceVariant: _inkVariant,
          outline: _line,
          outlineVariant: _lineSoft,
          error: const Color(0xFF9A3B2E),
          onError: Colors.white,
        )
      : ColorScheme.dark(
          primary: _nightBlue,
          onPrimary: const Color(0xFF0E1417),
          secondary: _nightBlue,
          onSecondary: const Color(0xFF0E1417),
          surface: _nightSurface,
          onSurface: _nightInk,
          surfaceContainerLow: _nightLow,
          surfaceContainerLowest: _night,
          onSurfaceVariant: _nightInkVariant,
          outline: _nightLine,
          outlineVariant: _nightLineSoft,
          error: const Color(0xFFD98A79),
          onError: const Color(0xFF1A0E0B),
        );

  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light ? _paper : _night,
    textTheme: _textTheme(scheme),
    splashFactory: NoSplash.splashFactory,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      iconColor: scheme.onSurfaceVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline, width: 1.2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.secondary,
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13.5),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13.5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Lora',
        fontWeight: FontWeight.w600,
        fontSize: 17,
        color: scheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: brightness == Brightness.light ? _ink : _nightInk,
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13.5,
        color: brightness == Brightness.light ? _paper : _night,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: TextStyle(
        fontSize: 11.5,
        fontFamily: 'Inter',
        color: brightness == Brightness.light ? _paper : _night,
      ),
      decoration: BoxDecoration(
        color: brightness == Brightness.light ? _ink : _nightInk,
        borderRadius: BorderRadius.circular(6),
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
      backgroundColor: Colors.transparent,
      selectedColor: scheme.surfaceContainerLow,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent),
      side: BorderSide(color: scheme.outline, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
  );

  return theme;
}
