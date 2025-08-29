# Correções aplicadas (2025-08-29T00:31:12)

1. **pubspec.yaml**
   - `name` alterado para `barbearia` para alinhar com imports `package:barbearia/...`.
   - Dependências adicionadas: `google_fonts: ^6.2.1` e `intl: ^0.19.0` (usadas em `lib/theme.dart` e `lib/widgets/appointment_card.dart`).

2. **Geral**
   - Projeto parece direcionado ao **Web** (pastas android/ios ausentes). Para Android/iOS, rode `flutter create .` para gerar as plataformas e ajuste configurações conforme necessário.

## Como rodar
```bash
flutter pub get
flutter run -d chrome
```
