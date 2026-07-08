import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Detecta quando o app está rodando no Safari do iOS fora da tela de
/// início. Nesse cenário o iOS pode apagar o login salvo (localStorage)
/// depois de alguns dias sem uso, forçando o usuário a logar de novo toda
/// vez. Instalar o PWA na tela de início evita essa limpeza automática.
class PwaHelper {
  static bool get isIOS {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  static bool get isAndroid {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('android');
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

  static bool get shouldPromptInstall => (isIOS || isAndroid) && !_isStandalone;

  /// No Android o Chrome dispara o evento `beforeinstallprompt` (capturado em
  /// `web/index.html`) quando o site pode ser instalado. Sem isso disparar,
  /// não existe um "Adicionar à Tela de Início" nativo pra sugerir — o menu
  /// de instalação do Chrome já cuida disso sozinho.
  static bool get canInstallAndroid {
    final w = web.window;
    return w.has('__canInstallPWA') &&
        w.getProperty<JSBoolean>('__canInstallPWA'.toJS).toDart;
  }

  /// Dispara o prompt nativo de instalação do Android (o mesmo diálogo que
  /// o Chrome mostraria pelo menu "Instalar app"). Retorna se o usuário
  /// aceitou instalar.
  static Future<bool> promptAndroidInstall() async {
    if (!web.window.has('__promptPWAInstall')) return false;
    final promise = web.window.callMethod<JSPromise<JSBoolean>>(
      '__promptPWAInstall'.toJS,
    );
    final accepted = await promise.toDart;
    return accepted.toDart;
  }
}
