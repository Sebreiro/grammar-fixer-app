import 'package:flutter/material.dart';

/// Neutral resident surfaces shared by the panel and Settings.
abstract final class DaemonTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);
  static Color successFor(Brightness brightness) =>
      Color(brightness == Brightness.dark ? 0xff97d6af : 0xff267349);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: Color(dark ? 0xffa9beff : 0xff3458c9),
      onPrimary: Color(dark ? 0xff182e68 : 0xffffffff),
      secondary: Color(dark ? 0xffabb4c4 : 0xff626b7a),
      onSecondary: Color(dark ? 0xff1e222a : 0xffffffff),
      error: Color(dark ? 0xffffb2b2 : 0xffad3439),
      onError: Color(dark ? 0xff37272d : 0xffffffff),
      errorContainer: Color(dark ? 0xff37272d : 0xfffff4f3),
      surface: Color(dark ? 0xff1e222a : 0xffffffff),
      onSurface: Color(dark ? 0xffedf0f6 : 0xff252a34),
      onSurfaceVariant: Color(dark ? 0xffabb4c4 : 0xff626b7a),
      surfaceContainerLow: Color(dark ? 0xff252a33 : 0xfff6f7f9),
      surfaceContainer: Color(dark ? 0xff222730 : 0xffffffff),
      primaryContainer: Color(dark ? 0xff2a3349 : 0xfff3f6ff),
      onPrimaryContainer: Color(dark ? 0xffedf0f6 : 0xff252a34),
      outline: Color(dark ? 0xff373e4a : 0xffe0e4eb),
      outlineVariant: Color(dark ? 0xff373e4a : 0xffe0e4eb),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 13,
          height: 1.45,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          height: 1.45,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 14),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 12),
      ),
      dividerColor: scheme.outline,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 48,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shape),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
    );
  }
}
