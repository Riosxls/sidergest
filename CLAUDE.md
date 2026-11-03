# CLAUDE.md — MetaGest

The app was renamed from SiderGest to **MetaGest**. `compose.yaml` pins the docker project name to `metagest` (containers `metagest-db-1`, `metagest-api-1`, volume `metagest_pgdata`, image `metagest-api`), so it no longer depends on the folder name. The dev password `sidergest123` stays until production. Remaining old names: the repo folder and GitHub repo until Italo renames them.

Primary context file for future sessions. Read fully before changing code.

## Project overview

EBT (Brazilian steel-tube manufacturer) is replacing its legacy **Emissor NF** system (HDS / xHarbour / DBF files; old executable `C:\Users\italo\Desktop\EBT\SI\NF\NF.exe`) with **MetaGest**:

- Backend: ASP.NET Core 10 minimal API + EF Core + PostgreSQL 16 (`src/`).
- Clients: Flutter for Windows, Android and Web (`clients/flutter`).
- Modules: Engenharia (products, BOM, routing), Estoque, Suprimentos (purchasing), PCP (production), Vendas (sales), Fiscal (NF-e), Certificados (quality).
- UI language is Brazilian Portuguese. Code identifiers are English. Keep both.

## Workflow rules

- All code changes happen locally on Italo's machine (`C:\Users\italo\Desktop\sidergest`), via Remote Control sessions.
- **Never push to GitHub unless Italo asks.** Commit locally only. Do not open PRs unless asked. When he does ask, push to `main` as a fast-forward (`git fetch`, check `origin/main` is an ancestor, then push).
- Work in `C:\Users\italo\Desktop\sidergest` on branch `main`; this is the folder Italo runs Flutter from. Claude worktrees under `.claude/worktrees/` are disposable copies: a build or edit there does not reach the folder he runs. Never leave work only in a worktree.
- GitHub CI is disabled on purpose (Italo does not want to spend Actions minutes). Run `dotnet test` and `flutter test` locally instead.
- Project root `AGENTS.md` (in `C:\Users\italo`) asks for graphify: use `graphify query/path/explain` before raw grep when `graphify-out/graph.json` exists; run `graphify update .` after modifying code. `graphify-out/` is tracked only for `graph.json`, `graph.html`, `GRAPH_REPORT.md`, `manifest.json` and the label files; commit them after `graphify update .` when the code changed. `graphify-out/cache/` and the dated snapshot folders (`graphify-out/2026-...`) are ignored.
- Untracked scratch files (`clients/flutter/devtools_options.yaml`, `flutter_01.png`, `ebt-backup-*.dump` database backups in the repo root) are not part of the project; do not commit them (the dumps contain real data; `*.dump` is gitignored).

## Dev setup

```
start.bat              # DB + API (Docker) + Flutter Windows app
start.bat -Web         # app in Chrome at http://localhost:8081 (-Device edge for Edge)
start.bat -ApiOnly     # DB + API only
start.bat -NoDocker    # API via dotnet run against local PostgreSQL 16 (EBT_DB_PORT)
stop.bat [-Purge]      # stop; -Purge dumps the DB, asks for DELETE, then deletes the DB volume
```

`start.bat` -> `scripts/start.ps1` (starts containers, migrates, creates admin, launches app).

| Thing | Value |
|---|---|
| API | http://localhost:8080 (Swagger at `/swagger`) |
| Postgres (Docker) | `127.0.0.1:25432`, db/user `ebt`, password `ebt-dev-password` |
| Flutter web | http://localhost:8081 |
| Login | `admin` / `sidergest123` (fresh DBs only: created when the DB has no users. On Italo's live DB the admin password and `EBT_JWT_KEY` were rotated on 2026-11-01; the current admin password is `EBT_ADMIN_PASSWORD` in `.env`) |

If a port is taken, `start.ps1` picks the next free one. Override with `EBT_API_PORT`, `EBT_DB_PORT`, `EBT_WEB_PORT`. `compose.yaml` sets `Database__MigrateOnStartup=true`, so migrations apply on API start.

The Docker API needs a real `.env` in the repo root (gitignored): `EBT_DB_PASSWORD`, `EBT_JWT_KEY` (random; the API refuses placeholder keys), `EBT_ADMIN_PASSWORD`, `EBT_SWAGGER`. `start.ps1` creates it when missing; Italo's existing one reuses the DB password `ebt-dev-password`. Changing `EBT_JWT_KEY` signs everyone out.

**Rebuilding the API container.** `docker compose up --build` has left the old image in place on this machine. Build and recreate explicitly, then check that the login response has `permissions` and `refreshToken`:

```
docker build --target api -t metagest-api:latest .
docker compose -p metagest up -d --no-deps --force-recreate --pull never api
```

`powershell -File scripts\update.ps1` does this safely in one go (refuses with uncommitted changes in `src/` unless `-Force`, verified backup first, keeps the old image as `metagest-api:previous`, builds `metagest-api:<sha>` + `latest`, recreates only `api`, waits up to 90 s for `GET /health/ready`, rolls the image back and exits non-zero if it never answers; a migration may already be applied then, so the pre-update dump is the way back). `start.ps1` uses the same tags.

Other ops scripts (details in `docs/OPERATIONS.md`): `restore-drill.ps1` (restores the newest dump into a throwaway database, compares counts and migrations with the live one, always drops it, writes `backup-status/drill.json`; `backup-agent.ps1` runs it weekly), `build-web.ps1` (Flutter web build for the optional Caddy proxy: `docker compose --profile proxy up -d caddy`, `caddy/Caddyfile`, `EBT_PUBLIC_HOST`), `release-android.ps1` (signed APK/AAB into `releases/`, `-Bump`, `-Bundle`; signing from the untracked `clients/flutter/android/key.properties`, debug key with a warning without it). `start.ps1` installs the git hooks once (`install-hooks.ps1`). `check.ps1` also lists vulnerable NuGet packages (warning only).

Never recreate the `db` container or run `stop.bat -Purge` without a fresh dump: `powershell -File scripts\backup.ps1` (writes `backups/`, gitignored; `start.ps1` runs it before every API rebuild and aborts if it fails). Restore, nightly task and the other ops notes are in `docs/OPERATIONS.md`. `db` and `api` have `restart: unless-stopped`.

Manual Flutter run: `cd clients\flutter; flutter pub get; flutter run -d windows --dart-define=API_URL=http://localhost:8080`.

Tests:
- Backend: `dotnet test` (`tests/Ebt.Tests`, integration tests against real Postgres via `ApiFixture.cs`; also DBF import tests). The fixture needs a superuser connection in `EBT_TEST_PG`; with the Docker DB: `Host=localhost;Port=25432;Username=ebt;Password=<EBT_DB_PASSWORD from .env>`. It creates and drops its own database.
- Everything: `powershell -File scripts\check.ps1` (build, backend tests, `flutter analyze`, `flutter test`; sets `EBT_TEST_PG` from `.env`). Run it before pushing, since CI is off.
- Flutter: `cd clients\flutter; flutter test` (`clients/flutter/test`).
- Coverage gate: `powershell -File scripts\coverage.ps1` runs both suites with coverage and fails under the minimums: backend lines 89% (measured 90.8%), backend branches 73% (75.4%), Flutter lines 86% (88.6%); EF migrations are excluded, `Ebt.DbfImport` is counted. Override with `-BackendMin`/`-BackendBranchMin`/`-FlutterMin`, skip with `-SkipBackend`/`-SkipFlutter`. `scripts\check.ps1 -Coverage` runs it in place of the plain test steps. Raise the minimums when coverage grows.

### Migrations

All live in `src/Ebt.Core/Data/Migrations/`. As of 2026-11-01 every migration, up to `IdleLock`, was applied to Italo's running DB. New ones apply automatically on the next API start. Create them from `src/Ebt.Core` with `dotnet ef migrations add <Name> -s ../Ebt.Api` (design-time factory: `Data/DesignTimeFactory.cs`).

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
- **Permissions** live in one matrix, `src/Ebt.Api/Infrastructure/Access.cs` (mirrored by `clients/flutter/test/role_permissions.dart` and described in `policyDescriptions` in `labels.dart`, shown on the read-only Permissões screen). Besides read/write/admin/stock: `sales-ship` = confirm the physical shipment (Admin, Sales, SalesManager, Stock); `fiscal-emit` = emit the sale NF (Admin, Sales, SalesManager); `fiscal-cancel`, `fiscal-prices`; `certificates` = draft certificates, `certificates-issue` = issue/cancel/delete a certificate and waive it on an order (Admin, Engineering, Production, SalesManager); `price-edit` = edit the price list (Admin, SalesManager). Adding a policy means touching all three places plus a test; `AccessParityTests` (backend) fails when `role_permissions.dart` or `policyDescriptions` drift from `Access.cs`.
- **Ship vs NF**: a caller without `fiscal-emit` (the Stock role) ships physically and, with fiscal enabled, the delivery is left without NF (history note "NF pendente"); Sales/SalesManager then emit it with `POST /api/sales/deliveries/{id}/emit-invoice` ("Emitir NF" button).
- **Source marker**: `DataSource` (Manual/Imported/Test, `Entities/DataSource.cs`, `IHasSource`) on Customer, Supplier, Product, Material, Quote, SalesOrder, Delivery, ProductionOrder, PurchaseRequisition, PurchaseOrder, StockDocument. DBF importers set Imported; the migration backfilled Imported from `legacy_code` (customers, suppliers) and `legacy_key` reports (OFs). Dashboard/report endpoints (`/sales/pipeline`, `/purchasing/overdue`, `/production/load`, `/reports/*`) skip Test unless `includeTest=true`; the dashboard lists pass `excludeTest=true`. Admin flags records with `POST /api/admin/data-source` (`entity`, `ids` or `allManual` (rows whose source is `from`, default Manual), `target`, `apply:false` previews; audited); `GET` returns counts per entity. Screen: Configurações > Administração > Fonte dos dados (`settings_data_source.dart`).
- **Estoque mínimo**: `GET /api/stock/low-stock` (materials with `MinStock` above on-hand, minus open PO lines; suggestion up to `MaxStock`, rounded to `PurchaseLot`), `POST /api/stock/low-stock/requisitions` drafts one pending requisition per material (skips ones with an open requisition). Screen "Estoque mínimo" and a Painel alert. `MaxStock` is only used for the suggestion.
- **Credit limit**: `Customer.CreditLimit` overrides `PaymentTerm.CreditLimit` (`CreditCheck.LimitSource`). Checked at order creation (existing), at release and at shipment (`SalesService.EnsureCreditAsync`): exceeded blocks with 409 unless the order already has a `credit-override` event or Admin/SalesManager sends `overrideCredit` (logged on the order history). The quote screen shows a warning banner, it never blocks approval.
- **Idle lock is server-side**: `PUT /api/auth/idle-lock {minutes}` stores the user's choice; `POST /api/auth/activity` only records `LastActivityAt` (a client value in its body is ignored); `TokenService.EffectiveIdle` applies the admin cap `Security:MaxIdleMinutes` (env `EBT_MAX_IDLE_MINUTES`, 0 = none; "never" and larger values become the cap) in token validation and refresh; `/me` and login return `idleLockMinutes` (effective) and `maxIdleMinutes`. The bootstrap admin may not use `sidergest123` outside Development/Testing, and passwords equal to it or to the username are rejected.
- **E-mail from the system** (`Ebt.Core/Mail`: `IMailSender`, `SmtpMailSender` on MailKit, config section `Mail`, env `EBT_SMTP_*` in `.env`/`compose.yaml`; off when host or from is empty): `GET /api/system/mail` -> `{enabled, from}`; `POST /api/sales/quotes/{id}/email` (`to`, `cc`, `subject`, `body`, `pdfBase64` built by the app, `fileName`) mails the PDF and, for a draft without pending approval or an approved quote, also registers the send (history `sent`); a Sent quote is mailed again (history `emailed`). Encryption by port (`EBT_SMTP_SECURITY`, Auto: 465 = SSL, else STARTTLS). Tests replace `IMailSender` with a fake. Setup in `docs/OPERATIONS.md`.
- **Health and alerts** (`Endpoints/OpsHealth.cs`, `AlertService.cs`): anonymous `GET /health/ready` returns `{status, db, pendingMigrations, backup:{lastOkAt, ageHours, agentSeenAt, drill}, warnings}`, 503 only when the DB is down or migrations are pending; warnings `backup_failed`, `backup_stale` (plan on, > 26 h), `agent_silent` (plan on, heartbeat > 10 min), `drill_failed` never make it 503. `AlertService` (hosted) checks the same every 5 min and mails `Alerts:To` (env `EBT_ALERT_TO`, off when empty or mail disabled) at most once per 6 h (last alert time in memory, no migration). compose also sets `Maximum Pool Size` (`EBT_DB_POOL`) and `mem_limit` (`EBT_API_MEM`, `EBT_DB_MEM`).
- **Account and system endpoints** (`Auth.cs`, `SystemEndpoints.cs`): `POST /api/auth/sessions` lists own devices (`RefreshToken.Device/UserAgent/Ip`, login sends optional `device`), `DELETE /api/auth/sessions/{id}`, `POST /api/auth/sessions/revoke-others`; `PUT /api/auth/profile` sets `displayName`/`email` (returned by `/me`); `POST /api/auth/activity` (idle-lock heartbeat: `AppUser.IdleLockMinutes`/`LastActivityAt`, enforced in `TokenService.ValidateAsync` and refresh; the client sends it from `Session.reportActivity`); `GET /api/system/about`; admin `GET /api/admin/backup-status` (reads `status.json` that `scripts/backup.ps1` writes to `backup-status/`, mounted read-only as `Backup:Directory`; the dumps are never mounted).
- **Backup plan** (`SystemEndpoints.cs`, `BackupSettings`, admin only): `GET/PUT /api/admin/backup-settings` (on/off, frequency Hourly/Every6Hours/Daily/Weekly, time, weekday, destination folder or share, keep count) and `POST /api/admin/backup-settings/run-now`. The API container cannot run `pg_dump`, so the host task `scripts\backup-agent.ps1` (installed once with `scripts\install-backup-agent.ps1`, a loop that checks every few seconds; watchdog every minute) reads the table, runs `backup.ps1` when due and writes `last_run_*` and the heartbeat `agent_seen_at` back; `backup.ps1` writes `backup-status/progress.json` that the API returns as `progress` for the app's progress bar; `POST /api/admin/backup-settings/cancel` sets `cancel_requested_at` and the agent kills the run, removes partial files and records "Backup cancelado.". Schedule rules are mirrored in `Ebt.Core/Maintenance/BackupSchedule.cs` and the agent; change both. `backup.ps1` verifies every dump (pg_restore -l, SHA-256 across the container copy and the destination copy), rotates only scheduled/manual dumps by count and gets the destination from `METAGEST_BACKUP_COPYTO`. Details in `docs/OPERATIONS.md`.
- **Audit log** (`Ebt.Core/Data/Audit.cs`): the interceptor logs inserts/updates/deletes of the master-data types in `Audited` and, for `ProductionOrder` and `QualityCertificate`, only status changes (action `Status`, who and from/to). Delete through the change tracker, never `ExecuteDelete`, on audited types. Security events that touch only hidden columns (password, lockout, tokens) are written explicitly with `AuthEndpoints.AuditSecurity` (actions `PasswordReset`, `PasswordChange`, `Unlock`, `Lockout`, `SessionRevoked`, `SessionsRevoked`, `AccessChanged`; entity `AppUser`).
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
- **Navigation** (`screens/shell.dart`, `widgets/record_nav.dart`, `screens/record_links.dart`): the Shell keeps visited screens alive (`_PageSlot`; reloaded after 3 minutes away, the Painel always) and a history for Esc/Back/Alt+←/Alt+→ (Ctrl+1…9 modules, Ctrl+0 Painel). On wide windows record pages open in an inner Navigator under the sidebar with a breadcrumb and previous/next buttons; on phones they cover the screen and a bottom bar holds Início/Buscar/Alertas/Menu. Open records only through `pushRecord` (the `open*` helpers): it names the route `record:kind:id`, returns to a record already open instead of stacking it, and asks before closing pages with unsaved edits (`DiscardGuard.anyDirty`). Never close pages with `popUntil` without that check. Add a record kind in `recordScreen`/`recordLabels`. `RecordList` reloads when a page closes or the list shows again, and remembers sort and unset filters per `path` (SharedPreferences `listView:<path>`). Record kinds registered in `recordScreen`/`recordLabels`: quote, sales-order, delivery, production-order, certificate, fiscal, feasibility, steel-lot, purchase-order, quotation, receipt, stock-document, product, customer, supplier, requisition, material-stock, product-stock (each has an `open*` helper; customer/supplier take a loaded map or load by id with `RecordLoader`). Record pages list what they point to in `RelatedMenu` (app bar link icon). Load failures use `LoadError` (retry + back). Lists: ↑/↓ or J/K, Enter, `/` for search. Stars (`navPins`) list screens under Fixados; `Copiar link` copies the address, and pasting it in the palette opens it. Forms built on `EntityFormDialog` keep a draft (`DraftStore`, 24 h) when the session ends under them. The window/tab asks before closing with unsaved edits (`unload_guard`, `AppLifecycleListener`). Web: the address bar follows `/s/<screen>[/r/<kind>/<id>][?f=<filter>]` and a reload opens it; the same form (`Shell.lastLocation`) returns a user to the last place after an idle lock.
- Esc goes back or cancels: `EscBack` (main.dart) pops pushed pages, Shell returns to the Painel, the settings dialog closes sub-views first; popups and dialogs use Flutter's default.
- All PDF output goes through `lib/reports/`: `print_docs.dart` (quote, sales order, OF, delivery, viabilidade, controle de aço...), `certificate_doc.dart`, `nf_doc.dart`, `report_doc.dart`.

## Sales flow

**Orçamento → Enviada ao cliente → Aprovada → Pedido de compra → Pedido de venda → Ordem de Produção → Certificado → Entrega**

(8-step pipeline shown in `sales_pipeline.dart` / `widgets/pipeline.dart`. "Proposta" was renamed "Orçamento"; "condição de pagamento" renamed **Prazo**.)

- Quote requires customer and Prazo before lines can be added. Quote can carry a **custom prazo** (stored on quote, copied to the sales order). Customer has a default prazo.
- Quote estimate includes ICMS on top of IPI. IPI and ICMS are not typed on the item card; they come from the price table. Lines have lead-time **working days** (Mon-Fri, national holidays) synced with the delivery date; the server uses the same math when a quote becomes an order.
- Quote items require the unit price and a lead time in working days; the lead time counts from the day the customer approves the quote (`DecidedAt`), not from the day it was sent or converted, and the quote screen and PDF say so. The sales order dates are computed from the approval date on conversion.
- When the customer's purchase order carries its own delivery date for an item, it is typed on the "Registrar pedido de compra" step (`deliveryDates` on `POST /quotes/{id}/purchase-order`, stored on the quote line, history action `delivery-dates`) and wins over our lead time even when it is later; items without a customer date keep our date (approval + working days).
- Admins can delete draft, cancelled, rejected and expired quotes; a quote that already has a sales order is never deleted.
- Quote **revisions** use letter suffixes (A, B, C...). A revision replaces the earlier version, which is shown as **Substituída** (not "Cancelada"); the API exposes `supersededById`/`supersededBy` for it.
- **Quote outcomes** are named after what the customer did, not after system actions. While Sent: *Cliente aprovou* (accept), *Cliente pediu alteração* (revise: new revision, old one superseded), *Cliente recusou* (decline: status Rejected, shown **Perdida**, with a lost reason), *Prorrogar validade* (`/extend`; an Expired quote goes back to Sent). After approval or a purchase order: *Cliente desistiu* (decline with `CustomerGaveUp`, history action `gave-up`). Before sending: *Voltar para rascunho* (`/reopen`, from PendingApproval/Approved) and *Cancelar* (only for a quote that never left the company). Do not add menu items that duplicate these outcomes.
- Sales order carries company (EBT/BST), customer PO ("pedido de compra") step, and custom prazo.
- Production order (OF, "Ordem de Produção") is generated from the sales order; shop-floor operations in `ProductionService.ShopFloor.cs`. Operations can be done outside ("remessa para industrialização").
- The OF paper must always carry the whole process (middle of the sheet, "PROCESSOS SECUNDÁRIOS"). The process is the product's routing copied onto the OF. About 70% of the live OFs (imported legacy, products without routing) have none, so a new OF for a product without routing gets a **suggested process** (`ProductionService.SuggestProcess`: Perfilar from the primary tube, Trefilar para Ø, Endireitar e Cortar L, Inspeção Final; top-level standard OFs only, never imports or subassemblies). Before release the planner rewrites it with **Editar processo** on the Operações tab (`PUT /api/production/orders/{id}/process`, `ProductionService.ReplaceProcessAsync`; renumbers 10, 20, 30... by position and keeps material links). Legacy OFs already without operations are filled in batch by the admin tool **Limpeza do legado** (Configurações > Administração; `POST /api/production/orders/bulk/suggest-process` and `/bulk/cancel-stale`, both admin only, preview first with `apply:false`). The tool also cancels Created OFs overdue for N days (min 30) with no stock movement or report, so imported legacy stops drowning the Painel alerts. Certificate specification templates are editable without issuing a certificate (`PUT /api/sales/certificates/templates/{id}`, "Editar modelo"). Shipping a delivery offers to print or download its issued certificates once (`printGate`, key `delivery:{id}:certificates:...`).
- **Order changes after release**: *Alterar prazos ou pedido do cliente* (`POST /orders/{id}/reschedule`, reason required for date changes, open OFs follow the new date), *Encerrar saldo* (`/close-balance`, only after something shipped: lines shrink to the shipped quantity, planned deliveries cancel, order becomes Expedido/Entregue), cancel shows a preview (`GET /orders/{id}/cancel-preview`) and can also cancel running OFs (`cancelProduction`, technical cancel). Shipping is blocked unless every item of the delivery has an issued certificate (for that order line, or for its product when the certificate names no line; one linked to another delivery does not count) or the order has a waiver, unless `withoutCertificate` is sent (logged as "sem certificado"). A certificate can only be issued with a found value on every row (remove the rows that do not apply); a delivery with a Pending NF (unknown SEFAZ outcome) cannot be cancelled.
- Delivery ("Entrega") ships from stock; with fiscal enabled, shipping emits the NF.

## Features built

- **Pipeline** view of the 8 sales steps.
- **Quote revisions** with letter suffixes.
- **OF PDF** with Tolerância, Medidas and Tubo primário fields (`OrderOperationDetails` migration).
- **Quality certificates** (`Certificates/CertificateService.cs`, `Entities/Certificates.cs`, `screens/certificates.dart`, `reports/certificate_doc.dart`): EBT and BST templates. Specification templates per customer+product (`CertificateTemplate`) are learned when a certificate is issued (limits, title, finish, standing observation; never the found values or the "certificado de origem" line) and prefill the next draft; list/forget them under Certificados > Modelos de especificação. `POST /api/sales/certificates/for-delivery/{id}` drafts one certificate per delivery item. Title variant "GARANTIA DA QUALIDADE DO PRODUTO", add/remove table rows and observation snippets in the editor. Facts about the Excel certificates are in the project memory (certificate-excel-findings).
- **NF-e emission** (`Fiscal/`): `FiscalService`, `NfeXml`, `NfeSigner` (XMLDSig A1), `SefazSpClient` (real, never run against SEFAZ), `StubSefazClient` (default). See `src/Ebt.Core/Fiscal/FISCAL.md` for the full status table and SEFAZ-enable steps.
- **Print PDFs for all steps**: quote, sales order, OF, delivery, NF (sale and outside-processing shipments), certificate.  The order screen has a "Documentos para imprimir" panel (`widgets/print_panel.dart`) with the five papers of every purchase: customer purchase order (the attached file or text, printed as PDF), pedido interno de venda, ordem de fabricação, nota fiscal, certificado; each row prints or says what unlocks it. Step cards carry the matching print shortcut.  Before the flow leaves a step whose paper was never printed or downloaded on this computer (customer purchase order on "Registrar pedido de compra", pedido interno on "Liberar para produção", OFs on "Programar entrega"), `printGate` (`widgets/print_gate.dart`) asks Imprimir / Baixar / Ignorar once; `PrintLog` remembers it in SharedPreferences.
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
- PowerShell scripts that contain accented text (`backup.ps1`, `backup-agent.ps1`) are saved as UTF-8 with BOM: Windows PowerShell 5.1 reads BOM-less files as ANSI and double-encodes the accents. Keep the BOM when editing them.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
