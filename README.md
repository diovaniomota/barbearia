# Barbearia

Aplicativo Flutter para agendamentos de barbearia, com suporte para Android,
iOS, desktop e Web.

## Rodar localmente

```sh
flutter pub get
flutter run
```

## Build web

```sh
flutter build web --release --base-href /
```

Os arquivos estaticos ficam em `build/web`.

## Deploy na Cloudflare

O projeto usa `wrangler.jsonc` para publicar `build/web` como Cloudflare
Workers Static Assets, com fallback de SPA para as rotas internas.

Fluxo recomendado:

```sh
flutter build web --release --base-href / --no-web-resources-cdn
npx wrangler deploy
```
