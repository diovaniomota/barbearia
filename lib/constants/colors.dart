import 'package:flutter/material.dart';

/// Paleta de cores exportada do projeto Barbearia
/// Para uso em outros projetos ou documentação
class BarbeariaColors {
  
  // ========================
  // MODO CLARO (LIGHT THEME)
  // ========================
  
  /// Cores Primárias - Light Mode
  static const Color lightPrimary = Color(0xFF8B4513); // Saddle Brown
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFE8D5B7); // Light Tan
  static const Color lightOnPrimaryContainer = Color(0xFF3E2723);
  
  /// Cores Secundárias - Light Mode
  static const Color lightSecondary = Color(0xFF795548); // Brown
  static const Color lightOnSecondary = Color(0xFFFFFFFF);
  
  /// Cores Terciárias - Light Mode
  static const Color lightTertiary = Color(0xFFFF8C00); // Dark Orange
  static const Color lightOnTertiary = Color(0xFFFFFFFF);
  
  /// Cores de Sistema - Light Mode
  static const Color lightError = Color(0xFFBA1A1A);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightErrorContainer = Color(0xFFFFDAD6);
  static const Color lightOnErrorContainer = Color(0xFF410002);
  
  /// Cores de Superfície - Light Mode
  static const Color lightSurface = Color(0xFFFDFBF7);
  static const Color lightOnSurface = Color(0xFF1C1B1A);
  static const Color lightAppBarBackground = Color(0xFFE8D5B7);
  static const Color lightInversePrimary = Color(0xFFD7B899);
  static const Color lightShadow = Color(0xFF000000);
  
  // ========================
  // MODO ESCURO (DARK THEME)
  // ========================
  
  /// Cores Primárias - Dark Mode
  static const Color darkPrimary = Color(0xFFD7B899); // Light Brown
  static const Color darkOnPrimary = Color(0xFF3E2723);
  static const Color darkPrimaryContainer = Color(0xFF5D4037);
  static const Color darkOnPrimaryContainer = Color(0xFFE8D5B7);
  
  /// Cores Secundárias - Dark Mode
  static const Color darkSecondary = Color(0xFFBCAAA4); // Light Brown Grey
  static const Color darkOnSecondary = Color(0xFF2E1C13);
  
  /// Cores Terciárias - Dark Mode
  static const Color darkTertiary = Color(0xFFFFAB91); // Light Orange
  static const Color darkOnTertiary = Color(0xFF4E2723);
  
  /// Cores de Sistema - Dark Mode
  static const Color darkError = Color(0xFFFFB4AB);
  static const Color darkOnError = Color(0xFF690005);
  static const Color darkErrorContainer = Color(0xFF93000A);
  static const Color darkOnErrorContainer = Color(0xFFFFDAD6);
  
  /// Cores de Superfície - Dark Mode
  static const Color darkSurface = Color(0xFF1A1110);
  static const Color darkOnSurface = Color(0xFFEDE0DB);
  static const Color darkAppBarBackground = Color(0xFF5D4037);
  static const Color darkInversePrimary = Color(0xFF8B4513);
  static const Color darkShadow = Color(0xFF000000);
  
  // ========================
  // PALETA PERSONALIZADA
  // ========================
  
  /// Tons de Marrom (principais do projeto)
  static const Color saddleBrown = Color(0xFF8B4513);
  static const Color brown = Color(0xFF795548);
  static const Color darkBrown = Color(0xFF5D4037);
  static const Color veryDarkBrown = Color(0xFF3E2723);
  static const Color darkerBrown = Color(0xFF2E1C13);
  
  /// Tons de Bege (complementares)
  static const Color lightTan = Color(0xFFE8D5B7);
  static const Color lightBrown = Color(0xFFD7B899);
  static const Color lightBrownGrey = Color(0xFFBCAAA4);
  static const Color veryLightBeige = Color(0xFFEDE0DB);
  
  /// Tons de Laranja (destaque)
  static const Color darkOrange = Color(0xFFFF8C00);
  static const Color lightOrange = Color(0xFFFFAB91);
  
  /// Superfícies Neutras
  static const Color offWhite = Color(0xFFFDFBF7);
  static const Color almostBlack = Color(0xFF1A1110);
  
  /// Sistema
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  
  // ========================
  // MÉTODOS DE CONVENIÊNCIA
  // ========================
  
  /// Retorna o ColorScheme para modo claro
  static ColorScheme get lightColorScheme => ColorScheme.light(
    primary: lightPrimary,
    onPrimary: lightOnPrimary,
    primaryContainer: lightPrimaryContainer,
    onPrimaryContainer: lightOnPrimaryContainer,
    secondary: lightSecondary,
    onSecondary: lightOnSecondary,
    tertiary: lightTertiary,
    onTertiary: lightOnTertiary,
    error: lightError,
    onError: lightOnError,
    errorContainer: lightErrorContainer,
    onErrorContainer: lightOnErrorContainer,
    inversePrimary: lightInversePrimary,
    shadow: lightShadow,
    surface: lightSurface,
    onSurface: lightOnSurface,
  );
  
  /// Retorna o ColorScheme para modo escuro
  static ColorScheme get darkColorScheme => ColorScheme.dark(
    primary: darkPrimary,
    onPrimary: darkOnPrimary,
    primaryContainer: darkPrimaryContainer,
    onPrimaryContainer: darkOnPrimaryContainer,
    secondary: darkSecondary,
    onSecondary: darkOnSecondary,
    tertiary: darkTertiary,
    onTertiary: darkOnTertiary,
    error: darkError,
    onError: darkOnError,
    errorContainer: darkErrorContainer,
    onErrorContainer: darkOnErrorContainer,
    inversePrimary: darkInversePrimary,
    shadow: darkShadow,
    surface: darkSurface,
    onSurface: darkOnSurface,
  );
  
  /// Lista com todas as cores em hex para fácil exportação
  static const List<Map<String, String>> colorPalette = [
    {'name': 'Saddle Brown (Primary)', 'hex': '#8B4513', 'usage': 'Cor principal, botões importantes'},
    {'name': 'Brown (Secondary)', 'hex': '#795548', 'usage': 'Cor secundária, elementos de apoio'},
    {'name': 'Light Tan', 'hex': '#E8D5B7', 'usage': 'Backgrounds claros, containers'},
    {'name': 'Dark Orange', 'hex': '#FF8C00', 'usage': 'Destaques, call-to-action'},
    {'name': 'Very Dark Brown', 'hex': '#3E2723', 'usage': 'Textos em fundos claros'},
    {'name': 'Off White', 'hex': '#FDFBF7', 'usage': 'Background principal (claro)'},
    {'name': 'Almost Black', 'hex': '#1A1110', 'usage': 'Background principal (escuro)'},
    {'name': 'Light Brown (Dark)', 'hex': '#D7B899', 'usage': 'Primary no modo escuro'},
    {'name': 'Light Orange', 'hex': '#FFAB91', 'usage': 'Tertiary no modo escuro'},
    {'name': 'Very Light Beige', 'hex': '#EDE0DB', 'usage': 'Textos em fundos escuros'},
  ];
}