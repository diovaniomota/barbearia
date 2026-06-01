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

## Deploy na Vercel

O projeto ja inclui `vercel.json`. Ao importar o repositorio na Vercel, ela
instala o Flutter stable, executa o build web e publica `build/web`.

Configuracao usada:

- Build command: `./flutter/bin/flutter build web --release --base-href /`
- Output directory: `build/web`
- Rewrite: todas as rotas apontam para `index.html`
