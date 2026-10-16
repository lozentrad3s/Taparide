import 'package:flutter/material.dart';

/// Colour tokens taken from the Tap A Ride logo and the product mockup.
abstract final class AppColors {
  static const ink = Color(0xFF111814);
  static const inkSoft = Color(0xFF34423A);
  static const muted = Color(0xFF5B6B62);
  static const faint = Color(0xFF8A9890);
  static const line = Color(0xFFDDE6E0);
  static const lineStrong = Color(0xFFC6D3CA);
  static const ground = Color(0xFFF2F6F3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunk = Color(0xFFF7FAF8);

  /// Primary action and brand field colour (deep forest green).
  static const forest = Color(0xFF0B5A3A);
  static const forestHover = Color(0xFF0E6B45);
  static const forestDeep = Color(0xFF06331F);

  /// Bright pin green from the logo. Decorative or large use only on white.
  static const leaf = Color(0xFF4DB52A);
  static const leafText = Color(0xFF237A2E);
  static const mint = Color(0xFFE6F2EA);
  static const mintStrong = Color(0xFFCDE6D5);

  static const amber = Color(0xFF8A5A00);
  static const amberSoft = Color(0xFFFBF0D9);
  static const red = Color(0xFFC0392B);
  static const redSoft = Color(0xFFFBE5E2);
  static const blue = Color(0xFF2861B8);
  static const blueSoft = Color(0xFFE3ECF9);

  /// Text colours on the forest field.
  static const onForest = Color(0xFFFFFFFF);
  static const onForestMuted = Color(0xFFB9D5C5);
}

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 72.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
}

abstract final class AppShadow {
  static const card = [
    BoxShadow(color: Color(0x0F0B2A1A), blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A0B2A1A), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const raised = [
    BoxShadow(color: Color(0x1F0B2A1A), blurRadius: 32, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x0F0B2A1A), blurRadius: 6, offset: Offset(0, 2)),
  ];
}

const _fallback = ['FiraSans'];
const tabular = [FontFeature.tabularFigures()];

TextStyle _t(double size, FontWeight weight, {double height = 1.3, double spacing = 0, Color color = AppColors.ink}) {
  return TextStyle(
    fontFamily: 'Barlow',
    fontFamilyFallback: _fallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: spacing,
    color: color,
  );
}

ThemeData buildAppTheme() {
  final textTheme = TextTheme(
    displayLarge: _t(64, FontWeight.w800, height: 0.96, spacing: -1.6),
    displayMedium: _t(46, FontWeight.w800, height: 1.0, spacing: -1.0),
    displaySmall: _t(36, FontWeight.w800, height: 1.04, spacing: -0.6),
    headlineLarge: _t(30, FontWeight.w700, height: 1.1, spacing: -0.4),
    headlineMedium: _t(25, FontWeight.w700, height: 1.15, spacing: -0.2),
    headlineSmall: _t(21, FontWeight.w700, height: 1.2),
    titleLarge: _t(18, FontWeight.w700, height: 1.25),
    titleMedium: _t(16, FontWeight.w600, height: 1.3),
    titleSmall: _t(14, FontWeight.w600, height: 1.3),
    bodyLarge: _t(17, FontWeight.w400, height: 1.5, color: AppColors.inkSoft),
    bodyMedium: _t(15, FontWeight.w400, height: 1.45, color: AppColors.inkSoft),
    bodySmall: _t(13, FontWeight.w400, height: 1.4, color: AppColors.muted),
    labelLarge: _t(15, FontWeight.w600, height: 1.2),
    labelMedium: _t(13, FontWeight.w600, height: 1.2),
    labelSmall: _t(12, FontWeight.w600, height: 1.2, spacing: 0.2, color: AppColors.muted),
  );

  // Component themes use the fully resolved (Material-merged) styles so they match what
  // widgets read from Theme.of(context); mixing the two breaks button text-style animations.
  final resolved = ThemeData(useMaterial3: true, fontFamily: 'Barlow', fontFamilyFallback: _fallback, textTheme: textTheme).textTheme;

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.forest,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.forest,
    onPrimary: Colors.white,
    secondary: AppColors.leaf,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.red,
    outline: AppColors.lineStrong,
    outlineVariant: AppColors.line,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Barlow',
    fontFamilyFallback: _fallback,
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.ground,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.forest,
      selectionColor: AppColors.mintStrong,
      selectionHandleColor: AppColors.forest,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.lineStrong),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: resolved.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppColors.lineStrong;
          if (states.contains(WidgetState.hovered)) return AppColors.forestHover;
          return AppColors.forest;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? AppColors.muted : Colors.white,
        ),
        minimumSize: WidgetStateProperty.all(const Size(48, 50)),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
        textStyle: WidgetStateProperty.all(resolved.labelLarge),
        shape: WidgetStateProperty.all(shape),
        elevation: WidgetStateProperty.all(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: const BorderSide(color: AppColors.lineStrong),
        textStyle: resolved.labelLarge,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.forest,
        minimumSize: const Size(48, 44),
        textStyle: resolved.labelLarge,
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.inkSoft, minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: resolved.bodyMedium?.copyWith(color: AppColors.muted),
      labelStyle: resolved.bodyMedium?.copyWith(color: AppColors.muted),
      floatingLabelStyle: resolved.labelMedium?.copyWith(color: AppColors.forest),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.forest, width: 1.8)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.red)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.red, width: 1.8)),
      errorStyle: resolved.bodySmall?.copyWith(color: AppColors.red),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.forest,
      disabledColor: AppColors.surfaceSunk,
      side: const BorderSide(color: AppColors.lineStrong),
      labelStyle: resolved.labelMedium,
      secondaryLabelStyle: resolved.labelMedium?.copyWith(color: Colors.white),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.mint,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => resolved.labelSmall?.copyWith(
          color: states.contains(WidgetState.selected) ? AppColors.forest : AppColors.muted,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.forest : AppColors.muted),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.mint,
      selectedIconTheme: const IconThemeData(color: AppColors.forest),
      unselectedIconTheme: const IconThemeData(color: AppColors.muted),
      selectedLabelTextStyle: resolved.labelMedium?.copyWith(color: AppColors.forest),
      unselectedLabelTextStyle: resolved.labelMedium?.copyWith(color: AppColors.muted),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.forest : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.inkSoft,
        ),
        side: WidgetStateProperty.all(const BorderSide(color: AppColors.lineStrong)),
        textStyle: WidgetStateProperty.all(resolved.labelMedium),
        minimumSize: WidgetStateProperty.all(const Size(48, 46)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: resolved.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: AppColors.leaf,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      titleTextStyle: resolved.headlineSmall,
      contentTextStyle: resolved.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.muted,
      titleTextStyle: resolved.titleSmall,
      subtitleTextStyle: resolved.bodySmall,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.sm)),
      textStyle: resolved.labelSmall?.copyWith(color: Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.forest, linearTrackColor: AppColors.mint),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.forest : AppColors.line),
    ),
  );
}
