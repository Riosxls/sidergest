# EBT ERP — Engenharia + Estoque + Suprimentos backend

ASP.NET Core 8 + EF Core + PostgreSQL 16. First module of the HDS "Emissor NF" replacement (see `system-map.md` §9). Clients (Flutter: Windows, Android, Web) live in `clients/flutter` and talk to this REST API.

## Layout

```
Ebt.sln
src/
  Ebt.Core/          Entities, EbtDbContext, EF migrations, BomService, TubeWeight, Inventory/, Purchasing/
  Ebt.Api/           Minimal API: auth (JWT), master data, products, routing, BOM
    Endpoints/       MasterDataEndpoints.cs, ProductEndpoints.cs, InventoryEndpoints.cs, PurchasingEndpoints.cs
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
cp .env.example .env          # set real passwords / JWT key
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

Suprimentos (field names taken from GSC.EXE): `SGCONTRO` → purchasing settings and number counters, `E37` → supplier × material (last price, qualification), `G06`/`G07` → quotations, items and bids (`G07PENDENC` P/A/R), `G19`/`G12` → purchase orders and lines, `G09` → due date (earliest) and received quantity (Σ `G09QTDIGIT`) per line, `G20` → cancelled orders, `G02` → requisitions (`G02PK` number, `G02STATUS` 0–8, links to quotation item and order line). Orders that already have receipts in the new system are left untouched. Legacy receipts (E11/E12) are not imported as receipts. The purchasing step runs inside the master-data transaction, so `--dry-run` covers it.

Stock: `SHCONTR`/`ESCONTR` → stock settings, `SG280` → average-cost history per thickness (imported rows never overwrite months the new system closed), `SALDOEST` → one opening-balance document per location (`SALDO` → ALM, `SALDOTER` → TER, lot `INICIAL`, cost = SG280 average before `--opening-date`). Opening balances import once; reverse the document to redo it. E50/E51/E43 (locations, balances per location, lots) are not in the project copy, so they are not mapped yet.

Files are recognised by their field prefix (E10*, F06*, X04* …), so names may differ. Rows are matched by legacy code; re-running updates in place. BOM lines of each imported operation are replaced. Deleted DBF rows are ignored. Text is read as code page 850 (`--codepage`). Products without a valid NCM get `--default-ncm` and a warning.

## Run locally (dev)

Needs .NET 8 SDK and Postgres 16.

```
createuser -P ebt   # password: ebt-dev-password
createdb -O ebt ebt
dotnet user-secrets set Jwt:SigningKey "<32+ chars>" --project src/Ebt.Api
dotnet user-secrets set Bootstrap:AdminUser admin --project src/Ebt.Api
dotnet user-secrets set Bootstrap:AdminPassword "<10+ chars>" --project src/Ebt.Api
dotnet run --project src/Ebt.Api
```

`appsettings.Development.json` points at `localhost/ebt`, migrates on start and enables Swagger.

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
| Reader      | ✓    |                   |              |

Stock writes (locations, documents, lots, reservations, monthly close) need Admin or Stock. Stock settings and reopening a closed month need Admin.

Suprimentos: create/cancel requisitions → Admin, Engineering, Stock, Purchasing. Approve requisitions, quotations, purchase orders, supplier materials → Admin, Purchasing. Goods receipts → Admin, Purchasing, Stock. Purchasing settings → Admin.

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

## Rules carried over from the legacy system

- Routing sequences are multiples of 10, unique per product.
- A BOM line is either a material or a component product; cycles are rejected.
- Explosion multiplies quantity × factor through every level and totals materials.
- Tube net weight is computed from shape, diameter/width/height, wall and length (steel 7.85 g/cm³) when not given.
- CPF/CNPJ, CEP, IBGE and NCM accept formatted input and are stored as digits.
