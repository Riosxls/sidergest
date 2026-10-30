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
- **Never push to GitHub unless Italo asks.** Commit locally only. Do not open PRs unless asked. When he does ask, push to `main` as a fast-forward (`git fetch`, check `origin/main` is an ancestor, then push).
- Work in `C:\Users\italo\Desktop\sidergest` on branch `main`; this is the folder Italo runs Flutter from. Claude worktrees under `.claude/worktrees/` are disposable copies: a build or edit there does not reach the folder he runs. Never leave work only in a worktree.
- GitHub CI is disabled on purpose (Italo does not want to spend Actions minutes). Run `dotnet test` and `flutter test` locally instead.
- Project root `AGENTS.md` (in `C:\Users\italo`) asks for graphify: use `graphify query/path/explain` before raw grep when `graphify-out/graph.json` exists; run `graphify update .` after modifying code. `graphify-out/` is regenerated output: it shows as modified after `graphify update .`; leave those changes out of commits.
- Untracked scratch files (`clients/flutter/devtools_options.yaml`, `flutter_01.png`, `ebt-backup-*.dump` database backups in the repo root) are not part of the project; do not commit them (the dumps contain real data; `*.dump` is gitignored).

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

If a port is taken, `start.ps1` picks the next free one. Override with `EBT_API_PORT`, `EBT_DB_PORT`, `EBT_WEB_PORT`. `compose.yaml` sets `Database__MigrateOnStartup=true`, so migrations apply on API start.

The Docker API needs a real `.env` in the repo root (gitignored): `EBT_DB_PASSWORD`, `EBT_JWT_KEY` (random; the API refuses placeholder keys), `EBT_ADMIN_PASSWORD`, `EBT_SWAGGER`. `start.ps1` creates it when missing; Italo's existing one reuses the DB password `ebt-dev-password`. Changing `EBT_JWT_KEY` signs everyone out.

**Rebuilding the API container.** `docker compose up --build` has left the old image in place on this machine. Build and recreate explicitly, then check that the login response has `permissions` and `refreshToken`:

```
docker build --target api -t sidergest-api:latest .
docker compose -p sidergest up -d --no-deps --force-recreate --pull never api
```

Never recreate the `db` container or run `stop.bat -Purge` without a fresh `pg_dump` (`docker exec sidergest-db-1 pg_dump -U ebt -d ebt -Fc > ebt-backup.dump`).

Manual Flutter run: `cd clients\flutter; flutter pub get; flutter run -d windows --dart-define=API_URL=http://localhost:8080`.

Tests:
- Backend: `dotnet test` (`tests/Ebt.Tests`, integration tests against real Postgres via `ApiFixture.cs`; also DBF import tests).
- Flutter: `cd clients\flutter; flutter test` (`clients/flutter/test`).

### Migrations

All live in `src/Ebt.Core/Data/Migrations/`. As of 2026-10-30 every migration, up to `QuoteFlowImprovements`, was applied (`CertificateTemplates` applies on the next API start) to Italo's running DB. New ones apply automatically on the next API start. Create them from `src/Ebt.Core` with `dotnet ef migrations add <Name> -s ../Ebt.Api` (design-time factory: `Data/DesignTimeFactory.cs`).

The live DB holds data imported from the old system (hundreds of OFs and purchase orders) next to test records. Treat it as real; never wipe it without a fresh backup.

## Repo layout

```
Ebt.sln
src/Ebt.Core/        Entities/, Data/ (EbtDbContext partials + Migrations), Services/ (BomService, TubeWeight, WorkDays, Clock),
                     Inventory/, Purchasing/, Production/, Sales/, Fiscal/, Certificates/, Maintenance/ (DataResetService)
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

- API access through `api.dart`; DTOs in `entities.dart`; Portuguese display strings/enums in `labels.dart`. Show errors with `friendlyError(e)` (never `'$e'`): it keeps API messages, translates field names and hides raw exception text.
- `workdays.dart` mirrors `Ebt.Core/Services/WorkDays.cs` (Mon-Fri minus national holidays); keep the two in sync.
- `session.dart` holds the signed-in state and personal preferences (theme, density, text size, remember-me). A stored session re-reads its permissions from `/api/auth/me` on start.
- Lists use `RecordList` (empty state with clear-filters, retry, sortable columns); wire `filtersActive`/`onClearFilters` when a screen adds filters. Settings dialog: `widgets/user_settings.dart` (opened from the avatar menu), data reset dialog: `screens/data_reset.dart`.
- Screens in `lib/screens/` (e.g. `sales_pipeline.dart`, `sales_quotes.dart`, `sales_orders.dart`, `production_orders.dart`, `deliveries.dart`, `certificates.dart`, `customers.dart`, `reports.dart`, `dashboard.dart`, `fiscal.dart`, `shell.dart`). Reusable widgets in `lib/widgets/` (`entity_form`, `record_list`, `pipeline`, `discard_guard`, `command_palette`...).
- Unsaved-edit guard: forms confirm before discard (`discard_guard.dart`).
- All PDF output goes through `lib/reports/`: `print_docs.dart` (quote, sales order, OF, delivery, viabilidade, controle de aço...), `certificate_doc.dart`, `nf_doc.dart`, `report_doc.dart`.

## Sales flow

**Orçamento → Enviada ao cliente → Aprovada → Pedido de compra → Pedido de venda → Ordem de Produção → Certificado → Entrega**

(8-step pipeline shown in `sales_pipeline.dart` / `widgets/pipeline.dart`. "Proposta" was renamed "Orçamento"; "condição de pagamento" renamed **Prazo**.)

- Quote requires customer and Prazo before lines can be added. Quote can carry a **custom prazo** (stored on quote, copied to the sales order). Customer has a default prazo.
- Quote estimate includes ICMS on top of IPI. IPI and ICMS are not typed on the item card; they come from the price table. Lines have lead-time **working days** (Mon-Fri, national holidays) synced with the delivery date; the server uses the same math when a quote becomes an order.
- Quote items require the unit price and a lead time in working days; the lead time counts from the day the customer approves the quote (`DecidedAt`), not from the day it was sent or converted, and the quote screen and PDF say so. The sales order dates are computed from the approval date on conversion.
- Admins can delete draft, cancelled, rejected and expired quotes; a quote that already has a sales order is never deleted.
- Quote **revisions** use letter suffixes (A, B, C...). A revision replaces the earlier version, which is shown as **Substituída** (not "Cancelada"); the API exposes `supersededById`/`supersededBy` for it.
- **Quote outcomes** are named after what the customer did, not after system actions. While Sent: *Cliente aprovou* (accept), *Cliente pediu alteração* (revise: new revision, old one superseded), *Cliente recusou* (decline: status Rejected, shown **Perdida**, with a lost reason), *Prorrogar validade* (`/extend`; an Expired quote goes back to Sent). After approval or a purchase order: *Cliente desistiu* (decline with `CustomerGaveUp`, history action `gave-up`). Before sending: *Voltar para rascunho* (`/reopen`, from PendingApproval/Approved) and *Cancelar* (only for a quote that never left the company). Do not add menu items that duplicate these outcomes.
- Sales order carries company (EBT/BST), customer PO ("pedido de compra") step, and custom prazo.
- Production order (OF, "Ordem de Produção") is generated from the sales order; shop-floor operations in `ProductionService.ShopFloor.cs`. Operations can be done outside ("remessa para industrialização").
- **Order changes after release**: *Alterar prazos ou pedido do cliente* (`POST /orders/{id}/reschedule`, reason required for date changes, open OFs follow the new date), *Encerrar saldo* (`/close-balance`, only after something shipped: lines shrink to the shipped quantity, planned deliveries cancel, order becomes Expedido/Entregue), cancel shows a preview (`GET /orders/{id}/cancel-preview`) and can also cancel running OFs (`cancelProduction`, technical cancel). Shipping is blocked without an issued certificate or a waiver unless `withoutCertificate` is sent (logged as "sem certificado").
- Delivery ("Entrega") ships from stock; with fiscal enabled, shipping emits the NF.

## Features built

- **Pipeline** view of the 8 sales steps.
- **Quote revisions** with letter suffixes.
- **OF PDF** with Tolerância, Medidas and Tubo primário fields (`OrderOperationDetails` migration).
- **Quality certificates** (`Certificates/CertificateService.cs`, `Entities/Certificates.cs`, `screens/certificates.dart`, `reports/certificate_doc.dart`): EBT and BST templates. Specification templates per customer+product (`CertificateTemplate`) are learned when a certificate is issued (limits, title, finish, standing observation; never the found values or the "certificado de origem" line) and prefill the next draft; list/forget them under Certificados > Modelos de especificação. `POST /api/sales/certificates/for-delivery/{id}` drafts one certificate per delivery item. Title variant "GARANTIA DA QUALIDADE DO PRODUTO", add/remove table rows and observation snippets in the editor. Facts about the Excel certificates are in the project memory (certificate-excel-findings).
- **NF-e emission** (`Fiscal/`): `FiscalService`, `NfeXml`, `NfeSigner` (XMLDSig A1), `SefazSpClient` (real, never run against SEFAZ), `StubSefazClient` (default). See `src/Ebt.Core/Fiscal/FISCAL.md` for the full status table and SEFAZ-enable steps.
- **Print PDFs for all steps**: quote, sales order, OF, delivery, NF (sale and outside-processing shipments), certificate.  The order screen has a "Documentos para imprimir" panel (`widgets/print_panel.dart`) with the five papers of every purchase: customer purchase order (the attached file or text, printed as PDF), pedido interno de venda, ordem de fabricação, nota fiscal, certificado; each row prints or says what unlocks it. Step cards carry the matching print shortcut.
- **Clientes CRUD** (`screens/customers.dart`, `/api/customers` with addresses, company data, default prazo).
- **Relatórios** (`screens/reports.dart`, `ReportsEndpoints.cs`): material consumption (`/api/reports/material-consumption`) and billing summary (`/api/reports/billing-summary`).
- **Painel** (`screens/dashboard.dart`): module cards with badges, quick actions (`quick_actions.dart`), command palette.
- **Análise de viabilidade** and **Controle de aço** print documents (in `reports/print_docs.dart`; steel weight math in `Ebt.Core/Services/TubeWeight.cs`).
- Engineering, Estoque (balances, lots, closing, documents), Suprimentos (requisitions, quotations, orders, receipts), PCP (shop floor) modules.
- **Configurações** (avatar menu): theme, density, text size, stay signed in, change own password (`POST /api/auth/password`, min 10 characters, revokes other sessions), clear local cache, and for admins the data reset.
- **Data reset** (`/api/admin/data-reset`, admin only, `Maintenance/DataReset.cs`): deletes movement data by group (Sales, Purchasing, Production, Stock) in foreign-key order after a preview and the typed word `LIMPAR`; master data is never touched, real (non-simulated) fiscal documents block it, each run is audited. Only Sales is ticked by default because Purchasing and Production hold imported legacy data.

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
- Many Flutter and docs files are CRLF in the working copy; `dart format -l 160` on a whole old file produces noisy diffs. Format only what you wrote.
- A stale app window shows old code: stop it and run `flutter run` again from `clients/flutter` on `main`. Release Android builds block cleartext HTTP; use HTTPS (debug builds allow it).

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
