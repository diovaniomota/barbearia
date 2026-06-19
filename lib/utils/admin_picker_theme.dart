import 'package:flutter/material.dart';

/// Tema escuro com dourado para showDatePicker / showTimePicker no painel admin.
/// Uso: builder: (ctx, child) => adminPickerTheme(ctx, child!)
Widget adminPickerTheme(BuildContext context, Widget child) {
  return Theme(
    data: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFF5C200),
        onPrimary: Color(0xFF080808),
        secondary: Color(0xFFF5C200),
        onSecondary: Color(0xFF080808),
        surface: Color(0xFF111111),
        onSurface: Color(0xFFF0EDE8),
        surfaceContainerHighest: Color(0xFF1C1C1C),
        outline: Color(0xFF333333),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Color(0xFFF5C200)),
      ),
    ),
    child: child,
  );
}
