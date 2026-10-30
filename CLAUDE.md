# CLAUDE.md — SiderGest

Primary context file for future sessions. Read fully before changing code.

## Project overview

EBT (Brazilian steel-tube manufacturer) is replacing its legacy **Emissor NF** system (HDS / xHarbour / DBF files; old executable `C:\Users\italo\Desktop\EBT\SI\NF\NF.exe`) with **SiderGest**:

- Backend: ASP.NET Core 8 minimal API + EF Core + PostgreSQL 16 (`src/`).
- Clients: Flutter for Windows, Android and Web (`clients/flutter`).
- Modules: Engenharia (products, BOM, routing), Estoque, Suprimentos (purchasing), PCP (production), Vendas (sales), Fiscal (NF-e), Certificados (quality).
- UI language is Brazilian Portuguese. Code identifiers are English. Keep both.

## Workflow rules

- All code changes happen locally on Italo's machine (`C:\Users\italo\Desktop\sidergest`), via Remote Control sessions.
- **Never push to GitHub unless Italo asks.** Commit locally only. Do not open PRs unless asked.
- Project root `AGENTS.md` (in `C:\Users\italo`) asks for graphify: use `graphify query/path/explain` before raw grep when `graphify-out/graph.json` exists; run `graphify update .` after modifying code. `graphify-out/` is untracked; dirty is expected.
- Untracked scratch files (`clients/flutter/devtools_options.yaml`, `flutter_01.png`) are not part of the project; do not commit them.

## Dev setup

```
start.bat              # DB + API (Docker) + Flutter Windows app
start.bat -Web         # app in Chrome at http://localhost:8081 (-Device edge for Edge)
start.bat -ApiOnly     # DB + API only
start.bat -NoDocker    # API via dotnet run against local PostgreSQL 16 (EBT_DB_PORT)
stop.bat [-Purge]      # stop; -Purge also deletes DB volume
```

`start.bat` -> `scripts/start.ps1` (starts containers, migrates, creates admin, launches app).

| Thing | Value |
|---|---|
| API | http://localhost:8080 (Swagger at `/swagger`) |
| Postgres (Docker) | `127.0.0.1:25432`, db/user `ebt`, password `ebt-dev-password` |
| Flutter web | http://localhost:8081 |
| Login | `admin` / `sidergest123` (created only when DB has no users) |

If a port is taken, `start.ps1` picks the next free one. Override with `EBT_API_PORT`, `EBT_DB_PORT`, `EBT_WEB_PORT`. Dev defaults are built in; no `.env` needed. `compose.yaml` sets `Database__MigrateOnStartup=true`, so migrations apply on API start.

Manual Flutter run: `cd clients\flutter; flutter pub get; flutter run -d windows --dart-define=API_URL=http://localhost:8080`.

Tests:
- Backend: `dotnet test` (`tests/Ebt.Tests`, integration tests against real Postgres via `ApiFixture.cs`; also DBF import tests).
- Flutter: `cd clients\flutter; flutter test` (`clients/flutter/test`).

### Pending migrations (apply on next start)

All live in `src/Ebt.Core/Data/Migrations/`. Not yet applied to Italo's running DB; they apply automatically on next API start:

`SeedSalesPrazos`, `QuoteCustomPaymentTerm`, `SalesOrderCustomPaymentTerm`, `CustomerCompanyData` (x2: `CustomerCompanyData` + `CustomerDefaultPaymentTerm`), `QuoteCustomerRequest`, `OrderOperationDetails`, `QualityCertificates`.

(`FiscalEmission` is also newer than the first batch; same rule.) Create new migrations from `src/Ebt.Core` with `dotnet ef migrations add <Name> -s ../Ebt.Api` (design-time factory: `Data/DesignTimeFactory.cs`).

## Repo layout

```
Ebt.sln
src/Ebt.Core/        Entities/, Data/ (EbtDbContext partials + Migrations), Services/ (BomService, TubeWeight),
                     Inventory/, Purchasing/, Production/, Sales/, Fiscal/, Certificates/
src/Ebt.Api/         Program.cs, Endpoints/*.cs, Infrastructure/ (Crud.cs generic CRUD, Auth.cs, Errors.cs)
src/Ebt.DbfImport/   CLI migrating legacy DBF data (IImportStep, Importer, StockImporter, PurchasingImport, ProductionImport)
tests/Ebt.Tests/     xUnit integration tests
clients/flutter/lib/ api.dart, entities.dart, labels.dart, session.dart, main.dart,
                     screens/, widgets/, reports/ (PDF builders)
scripts/             start.ps1, stop.ps1
```

### Backend conventions

- `EbtDbContext` is a **partial class**, one file per module: `EbtDbContext.cs` (engineering/master data), `.Inventory.cs`, `.Purchasing.cs`, `.Production.cs`, `.Sales.cs`, `.Fiscal.cs`, `.Certificates.cs`. Add a new module as a new partial file + entities file in `Entities/`.
- Endpoints: one static class per module in `src/Ebt.Api/Endpoints/` (`MasterDataEndpoints`, `ProductEndpoints`, `InventoryEndpoints`, `PurchasingEndpoints`, `ProductionEndpoints`, `SalesEndpoints`, `FiscalEndpoints`, `CertificateEndpoints`, `ReportsEndpoints`). Simple master data uses `MapCrud(new CrudSpec<TEntity, TIn, TOut>{...})` from `Infrastructure/Crud.cs`.
- Auth policies: `Policies.Read` etc.; roles include Admin, SalesManager.
- Business logic lives in `Ebt.Core` services (`SalesService`, `ProductionService` (+`.ShopFloor.cs`), `PurchasingService`, `StockService`, `FiscalService`, `CertificateService`, `BomService`), not in endpoints.
- DBF import: each importer step implements `IImportStep` (`Ebt.DbfImport/ImportStep.cs`) and is listed in `Importer.Steps`. Tests build DBF fixtures with `tests/Ebt.Tests/DbfWriter.cs`.
- Table/column names are snake_case in Postgres (e.g. `fiscal_settings`, `monthly_prices`, `tax_rules`, `cfops`).

### Flutter conventions

- API access through `api.dart`; DTOs in `entities.dart`; Portuguese display strings/enums in `labels.dart`.
- Screens in `lib/screens/` (e.g. `sales_pipeline.dart`, `sales_quotes.dart`, `sales_orders.dart`, `production_orders.dart`, `deliveries.dart`, `certificates.dart`, `customers.dart`, `reports.dart`, `dashboard.dart`, `fiscal.dart`, `shell.dart`). Reusable widgets in `lib/widgets/` (`entity_form`, `record_list`, `pipeline`, `discard_guard`, `command_palette`...).
- Unsaved-edit guard: forms confirm before discard (`discard_guard.dart`).
- All PDF output goes through `lib/reports/`: `print_docs.dart` (quote, sales order, OF, delivery, viabilidade, controle de aço...), `certificate_doc.dart`, `nf_doc.dart`, `report_doc.dart`.

## Sales flow

**Orçamento → Enviada ao cliente → Aprovada → Pedido de compra → Pedido de venda → Ordem de Produção → Certificado → Entrega**

(8-step pipeline shown in `sales_pipeline.dart` / `widgets/pipeline.dart`. "Proposta" was renamed "Orçamento"; "condição de pagamento" renamed **Prazo**.)

- Quote requires customer and Prazo before lines can be added. Quote can carry a **custom prazo** (stored on quote, copied to the sales order). Customer has a default prazo.
- Quote estimate includes ICMS on top of IPI. Lines have lead-time days synced with delivery date.
- Quote **revisions** use letter suffixes (A, B, C...).
- Sales order carries company (EBT/BST), customer PO ("pedido de compra") step, and custom prazo.
- Production order (OF, "Ordem de Produção") is generated from the sales order; shop-floor operations in `ProductionService.ShopFloor.cs`. Operations can be done outside ("remessa para industrialização").
- Delivery ("Entrega") ships from stock; with fiscal enabled, shipping emits the NF.

## Features built

- **Pipeline** view of the 8 sales steps.
- **Quote revisions** with letter suffixes.
- **OF PDF** with Tolerância, Medidas and Tubo primário fields (`OrderOperationDetails` migration).
- **Quality certificates** (`Certificates/CertificateService.cs`, `Entities/Certificates.cs`, `screens/certificates.dart`, `reports/certificate_doc.dart`): EBT and BST templates.
- **NF-e emission** (`Fiscal/`): `FiscalService`, `NfeXml`, `NfeSigner` (XMLDSig A1), `SefazSpClient` (real, never run against SEFAZ), `StubSefazClient` (default). See `src/Ebt.Core/Fiscal/FISCAL.md` for the full status table and SEFAZ-enable steps.
- **Print PDFs for all steps**: quote, sales order, OF, delivery, NF (sale and outside-processing shipments), certificate.
- **Clientes CRUD** (`screens/customers.dart`, `/api/customers` with addresses, company data, default prazo).
- **Relatórios** (`screens/reports.dart`, `ReportsEndpoints.cs`): material consumption (`/api/reports/material-consumption`) and billing summary (`/api/reports/billing-summary`).
- **Painel** (`screens/dashboard.dart`): module cards with badges, quick actions (`quick_actions.dart`), command palette.
- **Análise de viabilidade** and **Controle de aço** print documents (in `reports/print_docs.dart`; steel weight math in `Ebt.Core/Services/TubeWeight.cs`).
- Engineering, Estoque (balances, lots, closing, documents), Suprimentos (requisitions, quotations, orders, receipts), PCP (shop floor) modules.

## Fiscal / NF

- CFOPs used: **5101** (venda), **5901** (remessa para industrialização), **5124 / 5902** (industrialização por encomenda / retorno), **5920 / 5921** (embalagem). All seeded in `cfops`; only 5101 and 5901 have emission triggers. Sale accepts another CFOP via `ship.cfop`.
- Emission off by default (`PUT /api/fiscal/settings`, `enabled: true`, needs full emitter data). Next NF number starts at 2581 (`fiscal_settings.next_number`), advances only on authorized NF.
- Pricing: `monthly_prices` (product x customer x CFOP x month); missing price blocks emission (422). Taxes: `tax_rules` -> order item rates -> CFOP default CSTs.
- **Pending: A1 `.pfx` certificate from the accountant.** Until then `StubSefazClient` runs (`simulated = true`; put `#SEFAZ-REJEITAR#` in observations to force rejection in tests). To enable real SEFAZ-SP set `Fiscal__Sefaz__Mode=Sp`, `Fiscal__Sefaz__CertificatePath`, `Fiscal__Sefaz__CertificatePassword` (env only, never in files) and start in Homologation.
- Not done: DANFE PDF, XSD validation, devolução, CC-e, inutilização, status lookup by access key.

## Quality certificates

- Source files: 826 files in `C:\Users\italo\Desktop\EBT\Certificados` (2025+).
- Numbering: **EBT starts at 2146**, **BST starts at 5176**.
- Two templates (EBT, BST) rendered by `certificate_doc.dart`; test in `clients/flutter/test/certificate_doc_test.dart`.

## Gotchas

- Do not edit generated migration `.Designer.cs`/snapshot by hand; regenerate via `dotnet ef`.
- PCP/navigation tests depend on sidebar height (see commit "Fix PCP nav tests for taller sidebar"); adding nav items can break `app_test.dart`.
- SEFAZ timeout means unknown outcome; check access key in portal before re-emitting.
- README.md has the user-facing quick start; this file is the engineering context.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
