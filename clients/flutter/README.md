# SiderGest — Flutter client

Flutter 3.47 (Dart 3.13). One codebase for Windows, Android and Web, talking to the REST API in `../../src/Ebt.Api` (Engenharia, Estoque, Suprimentos).

| Platform | Opens on | Layout |
|----------|----------|--------|
| Windows  | Produtos (Engineering/Admin/Reader), Saldos (Stock), Pedidos de compra (Purchasing) | side menu + data tables (≥ 900 px) |
| Web      | Painel   | side menu or drawer, by width |
| Android  | Painel   | drawer + list tiles, full-screen forms |

## Screens

- Login (JWT, token kept until expiry; server URL editable under the button)
- Painel: counts, blocked products, products without routing, breakdowns
- CRUD with search and paging: Produtos, Materiais, Máquinas, Operações padrão, Centros de trabalho, Ferramentas, Classes/Grupos/Subgrupos de material
- Produto: roteiro (operations, seq. multiple of 10) with BOM items per operation, explosão (any quantity, tree + material totals), onde é usado, revisões
- Material: onde é usado
- Role `Reader` sees everything read-only; `Admin`/`Engineering` can write

### Estoque

- Saldos: item × local × lote, filter by local, zero balances optional; quarantine/rejected lots and negative balances highlighted
- Item: disponibilidade (em estoque, liberado, bloqueado, terceiros, reservado, livre, custo médio, por local), kardex with running balance, lotes, reservas, histórico de compras
- Movimentações: documents by type/reference; new posting for every movement type (lines editor adapts: origem/destino, lote/corrida/custo/ICMS on valued entries, FIFO or chosen lot, reservation consumed, source material on third-party return); document view with estorno
- Lotes e inspeção: opens on quarentena for Stock users; liberar, rejeitar (laudo obrigatório), voltar para quarentena
- Reservas: create, filter by status/reference, release remaining
- Fechamento e custo médio: prévia, consulta, fechar mês, reabrir último (Admin), history
- Locais de estoque (CRUD), Parâmetros (stock + purchasing settings, Admin edits)

### Suprimentos

- Requisições: create (any operational role), approve with quantity / reject / cancel; buyers open on "aguardando aprovação"
- Cotações: build from approved requisitions + suppliers, record bids, comparativo ranked by price with IPI vs. last purchase, approve winner, reject item, add supplier, generate purchase order per winning supplier
- Pedidos de compra: open-only filter, late next delivery highlighted, manual order with lines, reschedule line, cancel / close balance, receipts tab
- Recebimentos: "Receber NF" lists open lines of the supplier, quantity/price/lot per line, live calculated total, divergence justification when the typed NF total differs; receipt view with installments
- Entregas em atraso, Fornecedores (CRUD, pontualidade 3/6/12/36 meses, materiais qualificados, atrasos, pedidos, recebimentos)

### Painel

Engenharia, Estoque (quarentena, reservas, último fechamento) and Suprimentos (requisições a aprovar, cotações e pedidos abertos, atrasos por fornecedor, pontualidade 12 meses dos fornecedores com pedidos abertos), ordered by the user's role.

### Roles

| Action | Roles |
|--------|-------|
| Engenharia master data, suppliers | Admin, Engineering |
| Stock posts, lots, reservations, locations, close month | Admin, Stock |
| Requisitions (create/cancel) | Admin, Engineering, Stock, Purchasing |
| Approve requisitions, quotations, orders, supplier materials | Admin, Purchasing |
| Receive NF | Admin, Purchasing, Stock |
| Settings, reopen month | Admin |

Buttons are hidden for other roles; Reader sees everything read-only.

Lookups (machine, material, component…) open a search dialog. Picking a machine fills its work center; picking a material/component fills the unit. Decimals accept `1,5` and `1.234,5`.

## Run

```
flutter pub get
flutter run -d windows --dart-define=API_URL=http://ebtservidor:8080
flutter run -d chrome --web-port 8081 --dart-define=API_URL=http://localhost:8080
flutter run -d <android-device> --dart-define=API_URL=http://192.168.0.10:8080
```

`API_URL` is only the default; the login screen can change it and remembers it. Default is `http://localhost:8080` (Docker and the API dev profile).

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

Tests use a fake HTTP backend: login, validation errors from the server, product list, routing/BOM view, explosion, narrow layout, stock posting + estorno, lot release, monthly close, role gating, requisition approval, quotation comparison/award/order, NF receipt with divergence, purchasing dashboard on a phone.
