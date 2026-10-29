import 'package:flutter/material.dart';

import '../models/models.dart';

/// Палитра в духе THE FINALS: почти чёрный фон, кислотный акцент,
/// зелёный/красный для усилений и ослаблений.
///
/// Перекрашена по оформлению Telegram-канала @tf_darkside (Darkside):
/// тёплый почти-чёрный фон, кремовый текст, янтарный акцент, «лента»
/// для заголовков разделов и зелёные/красные чипы у цифр.
class AppColors {
  static const Color bg = Color(0xFF131313);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceAlt = Color(0xFF232322);
  static const Color stroke = Color(0xFF35342F);
  static const Color accent = Color(0xFFF2A33C);

  /// Жёлтая плашка-«лента» под заголовки разделов: у Darkside на ней
  /// чёрный жирный курсив общий на весь канал.
  static const Color tape = Color(0xFFF5B12E);
  static const Color buff = Color(0xFF3EC95B);
  static const Color nerf = Color(0xFFFF4D5E);
  static const Color textPrimary = Color(0xFFEDE9DC);
  static const Color textDim = Color(0xFFA5A296);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.black,
      secondary: AppColors.buff,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surfaceAlt,
      side: const BorderSide(color: AppColors.stroke),
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.stroke, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
  );
}

Color impactColor(Impact impact) => switch (impact) {
      Impact.buff => AppColors.buff,
      Impact.nerf => AppColors.nerf,
      Impact.neutral => AppColors.textDim,
    };
