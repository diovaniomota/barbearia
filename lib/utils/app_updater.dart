import 'package:web/web.dart' as web;

/// Recarrega a página direto da rede. O app não usa service worker (ver
/// `web/index.html`), então isso já basta pra buscar a versão mais recente
/// publicada — sem precisar fechar e reabrir o app manualmente.
void reloadApp() {
  web.window.location.reload();
}
