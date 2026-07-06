import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Detecta quando o app está rodando no Safari do iOS fora da tela de
/// início. Nesse cenário o iOS pode apagar o login salvo (localStorage)
/// depois de alguns dias sem uso, forçando o usuário a logar de novo toda
/// vez. Instalar o PWA na tela de início evita essa limpeza automática.
class PwaHelper {
  static bool get _isIOS {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  static bool get _isStandalone {
    final mediaStandalone = web.window
        .matchMedia('(display-mode: standalone)')
        .matches;
    final navigator = web.window.navigator;
    final iosStandalone =
        navigator.has('standalone') &&
        navigator.getProperty<JSBoolean>('standalone'.toJS).toDart;
    return mediaStandalone || iosStandalone;
  }

  static bool get shouldPromptInstall => _isIOS && !_isStandalone;
}
