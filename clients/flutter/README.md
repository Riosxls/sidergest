# EBT Engenharia — Flutter client

Flutter 3.47 (Dart 3.13). One codebase for Windows, Android and Web, talking to the Engenharia REST API in `../../src/Ebt.Api`.

| Platform | Opens on | Layout |
|----------|----------|--------|
| Windows  | Produtos | side menu + data tables (≥ 900 px) |
| Web      | Painel   | side menu or drawer, by width |
| Android  | Painel   | drawer + list tiles, full-screen forms |

## Screens

- Login (JWT, token kept until expiry; server URL editable under the button)
- Painel: counts, blocked products, products without routing, breakdowns
- CRUD with search and paging: Produtos, Materiais, Máquinas, Operações padrão, Centros de trabalho, Ferramentas, Classes/Grupos/Subgrupos de material
- Produto: roteiro (operations, seq. multiple of 10) with BOM items per operation, explosão (any quantity, tree + material totals), onde é usado, revisões
- Material: onde é usado
- Role `Reader` sees everything read-only; `Admin`/`Engineering` can write

Lookups (machine, material, component…) open a search dialog. Picking a machine fills its work center; picking a material/component fills the unit. Decimals accept `1,5` and `1.234,5`.

## Run

```
flutter pub get
flutter run -d windows --dart-define=API_URL=http://ebtservidor:8080
flutter run -d chrome  --dart-define=API_URL=http://localhost:5241
flutter run -d <android-device> --dart-define=API_URL=http://192.168.0.10:8080
```

`API_URL` is only the default; the login screen can change it and remembers it. Default is `http://localhost:5241` (the API's dev profile).

## Build

```
flutter build windows --release --dart-define=API_URL=http://ebtservidor:8080
flutter build apk     --release --dart-define=API_URL=http://ebtservidor:8080
flutter build web     --release --no-web-resources-cdn --dart-define=API_URL=http://ebtservidor:8080
```

- Windows: needs Visual Studio 2022 with "Desktop development with C++". Output: `build/windows/x64/runner/Release/` (copy the whole folder).
- Android: cleartext HTTP is allowed so the app works against an intranet API without TLS.
- Web: `--no-web-resources-cdn` bundles CanvasKit so it works without internet. Serve `build/web/` from any static server, and add its origin to the API's `Cors:Origins` (e.g. `Cors__Origins__0=http://ebtservidor:8081`).

## Test

```
flutter analyze
flutter test
```

Tests use a fake HTTP backend: login, validation errors from the server, product list, routing/BOM view, explosion, narrow layout.
