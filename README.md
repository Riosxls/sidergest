# SiderGest — Engenharia, Estoque, Suprimentos, PCP

## Quick start (Windows)

Prerequisites: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running) and [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop) with Visual Studio 2022 "Desktop development with C++" for the Windows app.

1. `git clone https://github.com/Riosxls/sidergest` (or `git pull`)
2. Double-click `start.bat` (or run it in a terminal). It starts PostgreSQL + API in Docker, applies migrations, creates the admin user and opens the Windows app.
3. Log in with `admin` / `sidergest123`. Stop everything with `stop.bat`.

| Command | What it does |
|---------|--------------|
| `start.bat` | DB + API (Docker) + Flutter Windows app |
| `start.bat -Web` | same, app in Chrome at http://localhost:8081 (`-Device edge` for Edge) |
| `start.bat -ApiOnly` | DB + API only |
| `start.bat -NoDocker` | API via `dotnet run` against a local PostgreSQL 16 on 5432 or `EBT_DB_PORT` (needs .NET 8 SDK; creates role/db `ebt` via `psql` if missing) |
| `stop.bat` | stop API and containers, data kept |
| `stop.bat -Purge` | also delete the database volume |

API http://localhost:8080, Swagger http://localhost:8080/swagger. Dev defaults (DB password `ebt-dev-password`, JWT key, admin password) are built in, so no `.env` is needed for development. The admin user is only created when the database has no users. Ports: API 8080, Postgres 25432 (Docker, bound to 127.0.0.1), web app 8081. If one is taken or reserved by Windows, `start.bat` picks the next free one and prints the URLs; the app and CORS follow it. Override with `EBT_API_PORT`, `EBT_DB_PORT`, `EBT_WEB_PORT`. For production copy `.env.example` to `.env` and set real secrets.

ASP.NET Core 8 + EF Core + PostgreSQL 16. First module of the HDS "Emissor NF" replacement (see `system-map.md` §9). Clients (Flutter: Windows, Android, Web) live in `clients/flutter` and talk to this REST API.

## Layout

```
Ebt.sln
src/
  Ebt.Core/          Entities, EbtDbContext, EF migrations, BomService, TubeWeight, Inventory/, Purchasing/, Production/
  Ebt.Api/           Minimal API: auth (JWT), master data, products, routing, BOM
    Endpoints/       MasterDataEndpoints.cs, ProductEndpoints.cs, InventoryEndpoints.cs, PurchasingEndpoints.cs, ProductionEndpoints.cs
    Infrastructure/  Crud.cs (generic CRUD), Auth.cs, Errors.cs
  Ebt.DbfImport/     CLI that migrates legacy DBF master data into Postgres
tests/
  Ebt.Tests/         Integration tests against real Postgres (API + DBF import)
clients/
  flutter/           Flutter client (Windows, Android, Web), see its README
Dockerfile           targets: api, dbf-import
compose.yaml         db + api (+ dbf-import under the "tools" profile)
```

## Run with Docker

```
cp .env.example .env          # production: set real passwords / JWT key (optional for dev)
docker compose up -d --build
```

API at http://localhost:8080, Swagger at http://localhost:8080/swagger, health at `/health`.
The first start applies migrations and creates the admin user from `EBT_ADMIN_USER` / `EBT_ADMIN_PASSWORD`.

## Import legacy DBFs

Copy the Engenharia DBFs (SE090, SE030, SE040, SE100, SE070, MAQUINAS, FERRAMENTA, XY030, NF010, NF020, SE060, SE080, NF060, NF330, XY050, XY040) into `./legacy` (or set `EBT_DBF_DIR`), then:

```
docker compose run --rm dbf-import --dir /legacy --dry-run
docker compose run --rm dbf-import
```

Without Docker:

```
dotnet run --project src/Ebt.DbfImport -- --dir C:\EBT\dados --conn "Host=localhost;Database=ebt;Username=ebt;Password=..." [--dry-run] [--migrate]
```

PCP (field names taken from PCP.EXE / APONT.EXE strings, untested on live data): `CACONTR` → overrun tolerance (`TOL_APONTA`) and OF/OPI counters, `G29` shifts, `G28` employees, `G27` occurrences (`G27STATOF` → stops order), `X09` (`XY090`) orders with status, dates, parent/previous OF, `X31` (`XY310`) OPIs, `X06` (`XY060`) committed materials (replace the BOM snapshot; `X06QTMATER` read as the order total), `X28` overrun releases, `X13` reports (+ `X14` employee and `X15` machine by PK), `E24` scrap. Operations missing from today's routing are created from the legacy data. Imported open orders get no stock reservations.

Suprimentos (field names taken from GSC.EXE): `SGCONTRO` → purchasing settings and number counters, `E37` → supplier × material (last price, qualification), `G06`/`G07` → quotations, items and bids (`G07PENDENC` P/A/R), `G19`/`G12` → purchase orders and lines, `G09` → due date (earliest) and received quantity (Σ `G09QTDIGIT`) per line, `G20` → cancelled orders, `G02` → requisitions (`G02PK` number, `G02STATUS` 0–8, links to quotation item and order line). Orders that already have receipts in the new system are left untouched. Legacy receipts (E11/E12) are not imported as receipts. The purchasing step runs inside the master-data transaction, so `--dry-run` covers it.

Stock: `SHCONTR`/`ESCONTR` → stock settings, `SG280` → average-cost history per thickness (imported rows never overwrite months the new system closed), `SALDOEST` → one opening-balance document per location (`SALDO` → ALM, `SALDOTER` → TER, lot `INICIAL`, cost = SG280 average before `--opening-date`). Opening balances import once; reverse the document to redo it. E50/E51/E43 (locations, balances per location, lots) are not in the project copy, so they are not mapped yet.

Files are recognised by their field prefix (E10*, F06*, X04* …), so names may differ. Rows are matched by legacy code; re-running updates in place. BOM lines of each imported operation are replaced. Deleted DBF rows are ignored. Text is read as code page 850 (`--codepage`). Products without a valid NCM get `--default-ncm` and a warning.

## Run locally (dev)

Needs .NET 8 SDK and Postgres 16 (or just `start.bat -NoDocker`).

```
createuser -P ebt   # password: ebt-dev-password
createdb -O ebt ebt
dotnet run --project src/Ebt.Api
```

`appsettings.Development.json` points at `localhost/ebt`, listens on http://localhost:8080, migrates on start, enables Swagger, uses a dev JWT key and creates `admin` / `sidergest123`.

## Tests

```
dotnet test
```

Each run creates a throw-away database `ebt_test_<guid>` and drops it afterwards. Server defaults to `Host=localhost;Username=postgres`; override with `EBT_TEST_PG`.

## Auth and roles

`POST /api/auth/login {username, password}` → bearer token (8 h).

| Role        | Read | Write master data | Manage users |
|-------------|------|-------------------|--------------|
| Admin       | ✓    | ✓                 | ✓            |
| Engineering | ✓    | ✓                 |              |
| Stock       | ✓    |                   |              |
| Purchasing  | ✓    |                   |              |
| Production  | ✓    |                   |              |
| Reader      | ✓    |                   |              |

Stock writes (locations, documents, lots, reservations, monthly close) need Admin or Stock. Stock settings and reopening a closed month need Admin.

Suprimentos: create/cancel requisitions → Admin, Engineering, Stock, Purchasing. Approve requisitions, quotations, purchase orders, supplier materials → Admin, Purchasing. Goods receipts → Admin, Purchasing, Stock. Purchasing settings → Admin.

PCP: orders, status changes, scheduling, shop-floor reports, outside processing, overrun releases, employees/shifts/occurrences/holidays → Admin, Production. Material issue/return and finished-goods receipt → Admin, Production, Stock. Production settings → Admin.

## Endpoints

| Area | Routes |
|------|--------|
| Auth / users | `/api/auth/login`, `/api/auth/me`, `/api/users` |
| Customers | `/api/customers`, `/api/customers/{id}/addresses` |
| Suppliers | `/api/suppliers`, `/api/suppliers/{id}/addresses` |
| Materials | `/api/material-classes`, `/api/material-groups`, `/api/material-subgroups`, `/api/materials`, `/api/materials/{id}/where-used` |
| Shop floor | `/api/work-centers`, `/api/machines`, `/api/tools`, `/api/standard-operations` |
| Products | `/api/products`, `/{id}/customers`, `/{id}/routing`, `/{id}/revisions`, `/{id}/bom/explode?quantity=`, `/{id}/where-used` |
| Routing / BOM | `/api/routing-operations/{id}`, `/api/routing-operations/{id}/items`, `/api/bom-items/{id}` |
| Stock locations | `/api/stock-locations` (kinds: Internal, Quarantine, ThirdParty, Shipping) |
| Stock documents | `POST /api/stock/documents`, `GET /api/stock/documents`, `/{id}`, `POST /{id}/reverse` |
| Stock queries | `/api/stock/movements` (kardex, running balance when filtered by one item), `/api/stock/balances`, `/api/stock/availability?materialId=` |
| Lots | `/api/stock/lots`, `/{id}`, `PUT /{id}/inspection` |
| Reservations | `/api/stock/reservations`, `POST /{id}/release` |
| Requisitions | `/api/requisitions` (`status`, `materialId`, `department`, `q`), `/{id}`, `POST /{id}/approve`, `/{id}/reject`, `/{id}/cancel` |
| Quotations | `/api/quotations`, `/{id}`, `POST /{id}/suppliers`, `PUT /{id}/bids/{bidId}`, `POST /{id}/items/{itemId}/award`, `/{id}/items/{itemId}/reject`, `/{id}/cancel`, `GET /{id}/comparison` |
| Purchase orders | `/api/purchase-orders` (`status`, `open`, `supplierId`, `materialId`), `/{id}`, `POST /from-quotation`, `POST /{id}/cancel`, `/{id}/close`, `PUT /{id}/lines/{lineId}/due-date` |
| Receiving | `/api/goods-receipts` (`supplierId`, `purchaseOrderId`, `from`, `to`), `/{id}` |
| Supplier tracking | `/api/purchasing/overdue?asOf=&supplierId=`, `/api/suppliers/{id}/materials` (+ `PUT/DELETE /{materialId}`), `/api/suppliers/{id}/performance?from=&to=`, `/api/purchasing/materials/{id}/history` |
| Purchasing settings | `/api/purchasing/settings` (tolerance %, early receipt, grace days, receiving location) |
| Production orders | `/api/production/orders` (`status`, `open`, `kind`, `productId`, `parentOrderId`, `dueFrom`, `dueTo`, `q`), `/{id}`, `POST /{id}/release` (`force`), `/stop`, `/resume`, `/finish`, `/reopen`, `/close`, `/close-cost`, `/cancel` (`reason`, `technical`), `/refresh-structure`, `/child-orders`, `/schedule`, `GET /{id}/availability`, `/reconciliation`, `/stock-documents`, `/overrun-releases` |
| Order material / FG | `POST /api/production/orders/{id}/issues`, `/material-returns`, `/receipts` |
| Outside processing | `PUT/DELETE /api/production/orders/{id}/operations/{seq}/outsource`, `POST /{id}/operations/{seq}/outside-shipments`, `/api/production/outside-shipments` (`orderId`, `supplierId`, `open`), `POST /{id}/returns` |
| Shop floor (APONT) | `/api/production/reports` (`orderId`, `employeeId`, `machineId`, `from`, `to`), `DELETE /{id}`, `POST /api/production/orders/{id}/operations/{seq}/overrun-releases` |
| PCP masters | `/api/production/employees`, `/shifts`, `/occurrences`, `/holidays`, `/settings` |
| Planning | `POST /api/production/availability` (what-if BOM explosion vs free stock + open POs), `POST /api/production/schedule` (all open orders), `GET /api/production/load?from=&to=&groupBy=machine\|workCenter` |
| Average cost | `/api/stock/settings`, `/api/stock/closings`, `POST/DELETE /api/stock/closings/{yyyymm}`, `/api/stock/average-costs`, `/api/stock/average-costs/preview?period=` |

Lists take `q`, `skip`, `take` (≤500) and return `{items, total, skip, take}`.
Errors: validation → 400, duplicate / still referenced / BOM cycle → 409.

## Estoque

One immutable ledger (`stock_movements`) replaces E12/E17/E18/E21/E36/E42/F15. Every post is a document; corrections are reversals. `stock_balances` holds quantity per item × location × lot.

| Type | Effect |
|------|--------|
| OpeningBalance, Receipt, ProductionReceipt, CustomerReturn, AdjustmentIn | + at `locationId` |
| Issue, IndirectIssue, Shipment, ReturnToSupplier, AdjustmentOut | − at `locationId` (FIFO over released lots when `lotId` is omitted) |
| Transfer | `fromLocationId` → `locationId`, same lot |
| ThirdPartySend | own location → ThirdParty location |
| ThirdPartyReturn | − source material at ThirdParty location (optional `sourceMaterialId`/`sourceQuantity`), + returned material at own location; `unitCost` = service price per kg |
| InventoryCount | `quantity` is the counted balance; the difference is posted |

- Quantities are `numeric(18,4)`; nothing is truncated to whole kg.
- Receipts of materials get a lot (given `lotCode` or a sequential number). Materials flagged for inspection enter in Quarantine and cannot be issued until `PUT /lots/{id}/inspection` releases them.
- Negative balances are refused unless `allowNegativeStock`. Issues, shipments and third-party sends also may not eat stock reserved for other orders; pass `reservationId` to consume a reservation.
- Concurrent posts on the same item are serialised with Postgres advisory locks. `StockService` joins an open transaction (used by the Suprimentos receipt hook).
- Months close in order. A closed month refuses new posts and reversals. Only the last closed month can be reopened.

Monthly weighted average cost per steel thickness (materials without thickness use their own bucket), from `PrecoMedioMaterial`:

```
purchases = Σ qty × unitCost × (1 − icms%)            (icms deducted when deductIcmsFromAverage)
services  = Σ qty × servicePrice × (1 − icms%) + serviceQty × cuttingServicePerKg
m         = (purchases + services) / (purchaseQty + serviceQty)
m        += scrapPercent% × (m − scrapResalePerKg)
average   = (prevAverage × openingQty + m × inflowQty) / (openingQty + inflowQty)
```

`openingQty` is the bucket's ledger balance at the start of the month; `prevAverage` is the previous month's row (or imported SG280 row). Issues are valued at the latest average before their month. Gross average (without ICMS deduction) is kept alongside.

## Suprimentos

Flow (GSC.EXE): requisition → approval → quotation → bids → award → purchase order → receipt → stock + payables.

| Requisition status | Meaning |
|---|---|
| 0 PendingApproval, 1 Approved, 2 Rejected | `G02STATUS` 0–2 |
| 3 Quoting, 4 QuoteApproved, 5 QuoteRejected | on a quotation; award / reject per item |
| 6 OrderIssued, 7 PartiallyReceived, 8 Received | linked to a PO line |
| 9 Cancelled | new; only before quoting/ordering |

- Requisitions can be for a material or free text (services, consumables). Free-text lines never reach stock.
- Quotation: one item per material (requisitions summed), one bid per invited supplier. Comparison ranks by landed price `price × (1 − disc%) × (1 + IPI%)` and shows the last purchase price (`GVLULCP`). Awarding one bid rejects the others; the quotation closes when every item is decided.
- Purchase orders: from awarded bids (`POST /from-quotation`, due date = today + lead time) or direct (approved requisitions optional). Cancel only without receipts (requisitions go back to approved); close shortens a partially received order.
- PO status: Open → PartiallyReceived → Received, or Closed / Cancelled.
- Receipt rules (`SGCONTRO`): cumulative quantity ≤ ordered × (1 + `TOLRECEBIM`%, default 5); no receipt before the line's due date unless `allowEarlyReceipt` (`ANTECIPAMP`) or within `earlyReceiptGraceDays`; invoice total vs calculated total (± 0.01) needs a justification (`INCONNF`); invoice number unique per supplier and series.
- A receipt creates payable installments from the order's payment terms (`30/60/90` → 3 dues from the invoice date; no digits → one due on the invoice date) and updates supplier × material last price (E37).
- Stock hook: after saving, `ReceiveAsync` calls every `IGoodsReceiptHandler` inside the same transaction with `GoodsReceived` (quantities converted to the stock unit via `purchaseFactor`, unit cost net of discount, ICMS/IPI %, lot, inspection flag). `StockReceiptHandler` posts a `Receipt` document at `receivingLocationId` (fallback: location `ALM`). Any handler failure rolls the receipt back.
- Numbers come from Postgres sequences; the DBF import moves them past the legacy counters.

## PCP + Apontamento

Flow (PCP.EXE / APONT.EXE): order → release (reserve) → issue material → report per operation → finished goods in → finish → close → close cost.

| Status | Legacy `X09STATUS` |
|---|---|
| Created, Released, Stopped, InProduction, Cancelled, Finished | 0 Cadastrada, 1 Impressa, 2 Parada, 3 Em produção, 4 Cancelada, 5 Fim processo |
| Closed (+ `costClosedAt`) | `X09DTENCER` / `X09DTENCUS` |

- Orders (OF, reference `OF n`) and internal orders (OPI, `OPI n`, bales) have separate Postgres sequences; the DBF import moves them past `CA_NROP` / `CA_NROPI`.
- Creating an order snapshots the product's routing and first-level BOM (quantity × factor × order quantity). Component products are first-level lines: issue them from stock or create subassembly orders (`/child-orders` creates one per short component, linked through `parentOrderId`, legacy `CDOPPAI`). `refresh-structure` re-reads engineering while the order is still Created.
- Release reserves remaining material per line in Estoque (reference = order reference). Missing stock → 409 listing shortages, unless `force` (reserves what is free). Finish/cancel release open reservations.
- Issue/return/receipt post Estoque documents with the order reference. Issued quantity and material value are read from the ledger, so reversing a document in Estoque is reflected. Issues consume the order's reservation first. Material returns post `AdjustmentIn` at the issued average cost. Finished goods post `ProductionReceipt` with lot = reference and unit cost = (issued material value + outside service) ÷ max(planned, received). Component products issue at cost 0 (Estoque has no product average).
- Shop floor: each report has good/scrap (scrap needs a scrap occurrence), hours (or start/end time, across midnight), setup, operators, downtime + occurrence, employee, shift, machine (defaults to the operation's), weight. A downtime occurrence flagged `stopsOrder` (`G27STATOF`) stops the order. Limits: op 1 ≤ order × (1 + `TOL_APONTA`%, default 3) + released overruns (`X28`); op n ≤ good of op n−1 + released overruns. Finished goods ≤ good at the last operation. Deleting a report is refused if later operations or receipts already used it. Reports on one order are serialised with a row lock.
- Outside processing: mark an operation external with supplier + lead days, send quantities (`OutsideShipment`), record returns (good, scrap, service price per piece). A return creates the operation's report; manual reports on external operations are refused. Service value goes into order cost. Closing needs nothing left at the supplier. WIP at the third party is tracked on the order, not in the stock ledger.
- Cancel needs a reason; orders with movements or reports need `technical: true` (`gep166`). Delete only for never-released orders without activity. Close needs Finished and no open subassembly order.
- Scheduling (`gep137` "Data Mais Tarde"): backward from the due date in working hours (`hoursPerDay`, weekends off unless `workSaturdays`, holidays). Hours = setup (if not started) + remaining ÷ pieces/hour; external operations take lead days. Late orders also get a forward `adjustedStart/End` from today (`AJUSTARATRASO`). Subassemblies are scheduled to end before the parent operation that consumes them. Warnings: Sem operação, Produto sem materiais, sem máquina, sem peças/hora. Load = scheduled hours per machine or work center per week vs capacity.
- Reconciliation (`GEPMATCO`): per item, issued − (scrap × per-unit for operations at or after the consuming one + received × per-unit), valued at the last purchase price (E37) or current average. `close-cost` freezes material cost, service cost and actual unit cost.
- Not built yet: customer orders/delivery programs (P15/P13) and their netting, labor cost rates, OF/OPI print layouts.

## Rules carried over from the legacy system

- Routing sequences are multiples of 10, unique per product.
- A BOM line is either a material or a component product; cycles are rejected.
- Explosion multiplies quantity × factor through every level and totals materials.
- Tube net weight is computed from shape, diameter/width/height, wall and length (steel 7.85 g/cm³) when not given.
- CPF/CNPJ, CEP, IBGE and NCM accept formatted input and are stored as digits.
