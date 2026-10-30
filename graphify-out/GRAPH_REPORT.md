# Graph Report - sidergest  (2026-10-30)

## Corpus Check
- 189 files · ~183,241 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 14 file(s) not represented in the graph (top: (none) 7, .ttf 2, .bat 2)

## Summary
- 5657 nodes · 11376 edges · 230 communities (192 shown, 38 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 955 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `deddc686`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- entities.dart
- EbtDbContext
- shell.dart
- sales_quotes.dart
- .NewDb
- StockDocument
- dashboard.dart
- production_orders.dart
- PurchasingEndpoints.cs
- record_list.dart
- sales_common.dart
- stock_documents.dart
- entity_form.dart
- StockService
- PurchasingService
- system_text
- command_palette.dart
- receipts.dart
- orders.dart
- quotations.dart
- Map
- sales_orders.dart
- Quotation
- print_docs.dart
- production_floor.dart
- pipeline.dart
- .AdminAsync
- sales_pipeline.dart
- ProductionImport
- State
- StockLot
- ProductionOrder
- stock_closing.dart
- session.dart
- actions.dart
- dashboard_test.dart
- SalesEndpoints.cs
- dash.dart
- requisitions.dart
- .MapQuotes
- Material
- PurchaseRequisition
- Quote
- app_test.dart
- entity_list.dart
- Ebt.Core.Entities
- RoutingOperation
- stock_purchasing_test.dart
- Ebt.Core.csproj
- ProductionEndpoints.cs
- nf_doc.dart
- api.dart
- .MapProducts
- ProductionOrderStatus
- PurchasingImport
- ProductionReport
- sales_test.dart
- CertificateMeasure
- ImportReport
- Sales.cs
- SalesOrder
- SalesOrderLine
- Importer
- certificates.dart
- PurchasingEndpoints
- Customer
- StatelessWidget
- SiderGest — Engenharia, Estoque, Suprimentos, PCP
- PurchasingFixture
- StockLine
- dashboard_data.dart
- Delivery
- ux_test.dart
- ProductOut
- .CreateOrderCoreAsync
- PurchaseOrderLine
- GoodsReceived
- SalesEvent
- production_test.dart
- http
- CertificateOut
- ProductionService
- QualityCertificate
- Product
- ProductionOrderOperation
- CLAUDE.md — SiderGest
- CustomerAddress
- Ebt.Api.Infrastructure
- LegacyRow
- CrudSpec
- labels.dart
- DataReset.cs
- AuthTests
- SteelLot
- FiscalService
- .LoginAsync
- modules.dart
- QuoteLine
- FiscalDocument
- ProductionSettings
- AppUser
- customers.dart
- Supplier
- AverageCost
- reports.dart
- FiscalInstallment
- FiscalEndpoints.cs
- ICurrentUser
- steel.dart
- viability.dart
- Ebt.Core.Services
- OutsideShipment
- ProductionOrderMaterial
- dart_project
- .Billing_summary_splits_companies_and_consumption_lists_shipped_lines
- SefazSpClient
- IExceptionHandler
- start.ps1
- .Describe
- api_integration_test.dart
- fiscal.dart
- SalesService
- .MapAudit
- PriceListEntry
- ImportOptions
- QuoteExpiryService
- package:flutter/material.dart
- StockMovement
- ebt_core_certificates
- CertificateService
- ebt_core_fiscal
- Employee
- ebt_core_inventory
- Screens
- ebt_core_production
- ebt_core_viability
- SefazEnvironment
- main.dart
- RowVersionFilter
- FiscalDocumentLine
- Revision
- FeasibilityStudy
- QuoteStatus
- report_doc.dart
- UserRole
- MovementType
- RefreshToken
- deliveries.dart
- nav.dart
- StockException
- Auth.cs
- .TryHandleAsync
- certificate_doc.dart
- Clock
- .InTransactionAsync
- .Safe
- .MapReports
- flutter_secure_storage_windows_plugin
- .ConfigureSales
- Cfop
- NfeSigner
- admin_screens_test.dart
- .SetMeasures
- role_permissions.dart
- plugin_registry
- .ResetAsync
- Shift
- .NewRefreshAsync
- PaymentTerm
- Exception
- List
- discard_guard.dart
- FiscalSettings
- ApiFixture
- SignoffArea
- viability_steel_test.dart
- .ValidateAsync
- user_settings.dart
- .MapViability
- .MapMasterData
- .Steel_lot_slitter_and_usage_balance
- NfeXml
- data_reset.dart
- AuditEntry
- login.dart
- .Deactivating_a_user_revokes_existing_tokens
- CertificateEndpoints
- .Load
- .Sale_nf_needs_monthly_price_is_recorded_only_after_authorization_and_can_be_cancelled
- SalesSettings
- FeasibilityStatus
- TaxRule
- package:flutter_test/flutter_test.dart
- .MapMaintenance
- AuditInterceptor
- .AddViability
- .ConfigureViability
- dwmapi
- flutter_view_controller
- flutter_windows
- functional
- generated_plugin_registrant
- io
- iostream
- memory
- microsoft_entityframeworkcore_infrastructure
- microsoft_entityframeworkcore_migrations
- microsoft_entityframeworkcore_storage_valueconversion
- npgsql_entityframeworkcore_postgresql_metadata
- optional
- printing_plugin
- share_plus_windows_plugin_c_api
- stdio
- system
- url_launcher_windows
- windows
- workdays.dart
- .OnModelCreating
- StatefulWidget
- GoodsReceiptLine
- Product
- BomItem
- .Add
- Production.cs
- .Full_stock_order_ships_and_completes
- OverrunRelease
- QuoteEditorScreen
- QuoteScreen
- QuotesScreen

## God Nodes (most connected - your core abstractions)
1. `EbtDbContext` - 247 edges
2. `Ebt.Core.Entities` - 76 edges
3. `SalesService` - 72 edges
4. `FiscalDocument` - 63 edges
5. `ProductionService` - 61 edges
6. `StockService` - 59 edges
7. `Ebt.Core.Data` - 52 edges
8. `QualityCertificate` - 52 edges
9. `SalesOrder` - 52 edges
10. `Material` - 50 edges

## Surprising Connections (you probably didn't know these)
- `PCP + Apontamento` --references--> `OutsideShipment`  [INFERRED]
  README.md → src/Ebt.Core/Entities/Production.cs
- `Fiscal / NF` --references--> `StubSefazClient`  [INFERRED]
  CLAUDE.md → src/Ebt.Core/Fiscal/StubSefazClient.cs
- `Estoque` --references--> `StockService`  [INFERRED]
  README.md → src/Ebt.Core/Inventory/StockService.Costing.cs
- `Backend conventions` --references--> `CertificateEndpoints`  [INFERRED]
  CLAUDE.md → src/Ebt.Api/Endpoints/CertificateEndpoints.cs
- `Backend conventions` --references--> `FiscalEndpoints`  [INFERRED]
  CLAUDE.md → src/Ebt.Api/Endpoints/FiscalEndpoints.cs

## Import Cycles
- None detected.

## Communities (230 total, 38 thin omitted)

### Community 0 - "entities.dart"
Cohesion: 0.02
Nodes (85): b, bomItemFields, choices, codeName, col, columns, ColumnSpec, d (+77 more)

### Community 1 - "EbtDbContext"
Cohesion: 0.02
Nodes (90): DbContext, IDesignTimeDbContextFactory, DbContextOptions, DesignTimeFactory, DbSet, EbtDbContext, CertificateMeasures, QualityCertificates (+82 more)

### Community 2 - "shell.dart"
Cohesion: 0.03
Nodes (64): audit.dart, api, icon, label, of, QuickAction, quickActionsFor, r (+56 more)

### Community 3 - "sales_quotes.dart"
Cohesion: 0.02
Nodes (114): _accept, _act, _addresses, _addressId, api, _applyDefaultTerm, _approvalBanner, asOrder (+106 more)

### Community 4 - ".NewDb"
Cohesion: 0.06
Nodes (38): IDisposable, Seq, Component, Item, CancellationToken, Dictionary, IReadOnlyList, List (+30 more)

### Community 5 - "StockDocument"
Cohesion: 0.04
Nodes (62): ModelBuilder, StockSettings, DateOnly, DateTimeOffset, List, ReservationStatus, Consumed, Open (+54 more)

### Community 6 - "dashboard.dart"
Cohesion: 0.04
Nodes (51): _alerts, _all, attention, blurb, build, buildAlerts, _combine, _commercial (+43 more)

### Community 7 - "production_orders.dart"
Cohesion: 0.04
Nodes (56): _actions, api, base, build, _bump, _children, context, _cost (+48 more)

### Community 8 - "PurchasingEndpoints.cs"
Cohesion: 0.12
Nodes (41): DateOnly, DateTimeOffset, IReadOnlyList, AwardIn, BidOut, ComparisonBidOut, ComparisonItemOut, DueDateIn (+33 more)

### Community 9 - "record_list.dart"
Cohesion: 0.03
Nodes (72): actions, actionsFirst, alert, _aligned, allLabel, api, _ascending, attach (+64 more)

### Community 10 - "sales_common.dart"
Cohesion: 0.08
Nodes (25): build, deliveryPath, deliveryTone, flowSteps, gap, isSuperseded, main, openDelivery (+17 more)

### Community 11 - "stock_documents.dart"
Cohesion: 0.04
Nodes (52): _body, _open, build, _receive, _materials, newProduct, _order, _new (+44 more)

### Community 12 - "entity_form.dart"
Cohesion: 0.03
Nodes (62): LookupSpec, api, _applyFill, askCustomPrazo, _body, build, _busy, _clientErrors (+54 more)

### Community 13 - "StockService"
Cohesion: 0.11
Nodes (25): L, M, P, WebApplication, CancellationToken, DateOnly, List, Task (+17 more)

### Community 14 - "PurchasingService"
Cohesion: 0.16
Nodes (11): PurchaseOrder, CancellationToken, GeneratedRegex, IEnumerable, List, Regex, Task, PurchasingException (+3 more)

### Community 15 - "system_text"
Cohesion: 0.22
Nodes (5): Ebt.DbfImport, dbfdatareader, system_globalization, system_text, system_xml_linq

### Community 16 - "command_palette.dart"
Cohesion: 0.05
Nodes (44): actions, add, build, clear, _close, compact, createState, _debounce (+36 more)

### Community 17 - "receipts.dart"
Cohesion: 0.05
Nodes (43): allowNew, api, build, _busy, _calculated, createState, _date, dispose (+35 more)

### Community 18 - "orders.dart"
Cohesion: 0.05
Nodes (42): active, api, base, _busy, createState, d, dispose, _error (+34 more)

### Community 19 - "quotations.dart"
Cohesion: 0.05
Nodes (40): _addSupplier, api, base, bidFields, _bids, build, _busy, _call (+32 more)

### Community 20 - "Map"
Cohesion: 0.11
Nodes (19): _Availability, BalancesScreen, _BalancesScreenState, createState, _includeZero, initState, item, ItemStockScreen (+11 more)

### Community 21 - "sales_orders.dart"
Cohesion: 0.04
Nodes (50): api, base, _billTo, _body, build, _cancel, _certified, _certs (+42 more)

### Community 22 - "Quotation"
Cohesion: 0.03
Nodes (71): DateTimeOffset, List, BidStatus, Approved, Pending, Rejected, PurchaseOrder, ClosedAt (+63 more)

### Community 23 - "print_docs.dart"
Cohesion: 0.02
Nodes (85): _b, blankRows, _blue, box, _build, buildProductionOrderPdf, buildQuotePdf, buildSalesOrderPdf (+77 more)

### Community 24 - "production_floor.dart"
Cohesion: 0.05
Nodes (40): build, _color, context, createState, cs, _fetch, _from, _grid (+32 more)

### Community 25 - "pipeline.dart"
Cohesion: 0.05
Nodes (40): actions, amount, at, badge, build, c, caption, _Chevron (+32 more)

### Community 26 - ".AdminAsync"
Cohesion: 0.21
Nodes (17): IReadOnlyList, List, DataResetIn, DataResetOut, QuoteOut, QuoteRequestIn, QuoteSummaryOut, DateTimeOffset (+9 more)

### Community 27 - "sales_pipeline.dart"
Cohesion: 0.09
Nodes (23): certificates.dart, _advance, api, build, _card, _column, createState, _customerId (+15 more)

### Community 28 - "ProductionImport"
Cohesion: 0.19
Nodes (12): CancellationToken, DateOnly, DateTimeOffset, Dictionary, Encoding, List, Name, Preferred (+4 more)

### Community 29 - "State"
Cohesion: 0.06
Nodes (41): bool get, _CustomerAddressesState, _add, api, base, build, canWrite, createState (+33 more)

### Community 30 - "StockLot"
Cohesion: 0.06
Nodes (32): InspectionIn, LotStatus, Quarantine, Rejected, Released, StockBalance, Id, Location (+24 more)

### Community 31 - "ProductionOrder"
Cohesion: 0.05
Nodes (37): List, ProductionOrder, AdjustedEnd, AdjustedStart, Bales, ClosedAt, ClosedBy, CostClosedAt (+29 more)

### Community 32 - "stock_closing.dart"
Cohesion: 0.04
Nodes (48): build, _busy, _card, _close, _closings, ClosingScreen, _ClosingScreenState, createState (+40 more)

### Community 33 - "session.dart"
Cohesion: 0.04
Nodes (53): alerts, api, _apply, baseUrl, canApproveSales, canBuy, canCertificate, canCustomers (+45 more)

### Community 34 - "actions.dart"
Cohesion: 0.06
Nodes (33): addEnabled, addLabel, api, build, _c, columns, confirmLabel, createState (+25 more)

### Community 35 - "dashboard_test.dart"
Cohesion: 0.10
Nodes (20): Card, client, json, lists, log, main, openPalette, page (+12 more)

### Community 36 - "SalesEndpoints.cs"
Cohesion: 0.11
Nodes (32): DateOnly, DateTimeOffset, IReadOnlyList, ConfirmDeliveryIn, DeliveryLineOut, DeliveryOut, DeliverySummaryOut, LostReasonOut (+24 more)

### Community 37 - "dash.dart"
Cohesion: 0.08
Nodes (24): alert, BarPanel, build, child, dashCardShape, DashGrid, DashNotice, DashTile (+16 more)

### Community 38 - "requisitions.dart"
Cohesion: 0.10
Nodes (20): act, api, base, build, _cancellable, createState, initialStatus, initState (+12 more)

### Community 39 - ".MapQuotes"
Cohesion: 0.10
Nodes (23): Icms, Id, Ipi, CancellationToken, ClaimsPrincipal, Dictionary, Expression, Func (+15 more)

### Community 40 - "Material"
Cohesion: 0.08
Nodes (24): Material, Active, Class, ClassId, Code, Description, ExternalProcessing, GeneratesPurchaseOrder (+16 more)

### Community 41 - "PurchaseRequisition"
Cohesion: 0.06
Nodes (33): PurchaseRequisition, Application, ApprovedQuantity, DecidedAt, DecidedBy, DecisionNote, Department, Description (+25 more)

### Community 42 - "Quote"
Cohesion: 0.05
Nodes (39): Quote, Address, AddressId, ApprovedAt, ApprovedBy, Conditions, ContactEmail, ContactName (+31 more)

### Community 43 - "app_test.dart"
Cohesion: 0.12
Nodes (15): enterText, fakeBackend, json, login, main, page, path, product (+7 more)

### Community 44 - "entity_list.dart"
Cohesion: 0.06
Nodes (32): PageResult, EntitySpec, api, build, canWrite, createState, _debounce, dispose (+24 more)

### Community 45 - "Ebt.Core.Entities"
Cohesion: 0.13
Nodes (9): Ebt.Core.Purchasing, Ebt.Core.Entities, Ebt.Core.Data, microsoft_entityframeworkcore, microsoft_entityframeworkcore_changetracking, microsoft_entityframeworkcore_design, microsoft_entityframeworkcore_diagnostics, microsoft_entityframeworkcore_metadata_builders (+1 more)

### Community 46 - "RoutingOperation"
Cohesion: 0.06
Nodes (32): Machine, Code, Family, Id, Name, WorkCenter, WorkCenterId, RoutingOperation (+24 more)

### Community 47 - "stock_purchasing_test.dart"
Cohesion: 0.06
Nodes (30): bidStatus, body, client, comparison, doc, Fake, json, last (+22 more)

### Community 48 - "Ebt.Core.csproj"
Cohesion: 0.07
Nodes (26): coverlet.collector (6.0.2), DbfDataReader (0.9.0), EFCore.NamingConventions (8.0.3), Microsoft.AspNetCore.Authentication.JwtBearer (8.0.33), Microsoft.AspNetCore.Mvc.Testing (8.0.33), Microsoft.Extensions.Identity.Core (8.0.11), Microsoft.NET.Test.Sdk (17.11.1), Npgsql.EntityFrameworkCore.PostgreSQL (8.0.11) (+18 more)

### Community 49 - "ProductionEndpoints.cs"
Cohesion: 0.10
Nodes (43): StockDocumentSummary, MaterialOut, BomItemIn, DateOnly, DateTimeOffset, TimeOnly, AvailabilityCheckIn, EmployeeIn (+35 more)

### Community 50 - "nf_doc.dart"
Cohesion: 0.03
Nodes (76): a, ad, addresses, askNfFiscal, base, buildOutsideNfPdf, buildSaleNfPdf, _cell (+68 more)

### Community 51 - "api.dart"
Cohesion: 0.04
Nodes (45): Client, _baseUrl, _call, cap, clearVersions, delete, describeError, _doRefresh (+37 more)

### Community 52 - ".MapProducts"
Cohesion: 0.16
Nodes (13): Backend conventions, CancellationToken, Dictionary, Expression, IReadOnlyList, IResult, List, Task (+5 more)

### Community 53 - "ProductionOrderStatus"
Cohesion: 0.25
Nodes (8): ProductionOrderStatus, Cancelled, Closed, Created, Finished, InProduction, Released, Stopped

### Community 54 - "PurchasingImport"
Cohesion: 0.20
Nodes (11): QuotationItem, CancellationToken, DateTimeOffset, Encoding, HashSet, List, Name, Preferred (+3 more)

### Community 55 - "ProductionReport"
Cohesion: 0.06
Nodes (35): ModelBuilder, ProductionSettings, OutsideShipment, ProductionReport, Date, DowntimeHours, DowntimeOccurrence, DowntimeOccurrenceId (+27 more)

### Community 56 - "sales_test.dart"
Cohesion: 0.06
Nodes (35): body, client, credit, daysLeft, delivery, deliveryStatus, history, json (+27 more)

### Community 57 - "CertificateMeasure"
Cohesion: 0.13
Nodes (14): ModelBuilder, CertificateMeasure, Certificate, CertificateId, Found, Id, Kind, Name (+6 more)

### Community 58 - "ImportReport"
Cohesion: 0.14
Nodes (17): Averages, Balances, Settings, ImportReport, Warnings, TableReport, File, Inserted (+9 more)

### Community 59 - "Sales.cs"
Cohesion: 0.11
Nodes (18): BillTo, Bts, Ebt, DeliveryCondition, Bk, Gbk, Nbk, DeliveryStatus (+10 more)

### Community 60 - "SalesOrder"
Cohesion: 0.07
Nodes (27): List, SalesOrder, Address, AddressId, CertificateWaived, Company, CreatedAt, CreatedBy (+19 more)

### Community 61 - "SalesOrderLine"
Cohesion: 0.06
Nodes (32): SalesOrderLine, Condition, CustomerPartNumber, Description, DueDate, FeasibilityStudyId, FromStock, IcmsPercent (+24 more)

### Community 62 - "Importer"
Cohesion: 0.24
Nodes (12): Action, CancellationToken, DbSet, Dictionary, Encoding, Func, List, Name (+4 more)

### Community 63 - "certificates.dart"
Cohesion: 0.04
Nodes (52): api, base, _body, build, _busy, c, _cancel, certificate (+44 more)

### Community 64 - "PurchasingEndpoints"
Cohesion: 0.16
Nodes (16): CancellationToken, IQueryable, IResult, Task, WebApplication, PurchasingEndpoints, PurchasingSettingsDto, ReceiptLineOut (+8 more)

### Community 65 - "Customer"
Cohesion: 0.09
Nodes (22): Customer, Active, Addresses, City, Complement, Contact, DefaultPaymentTerm, DefaultPaymentTermId (+14 more)

### Community 66 - "StatelessWidget"
Cohesion: 0.07
Nodes (27): PrintButton, _CustomerCompany, _CustomerOrders, _CustomerQuotes, ModuleCard, OverdueScreen, ReportsScreen, ReceiptScreen (+19 more)

### Community 67 - "SiderGest — Engenharia, Estoque, Suprimentos, PCP"
Cohesion: 0.13
Nodes (14): Auth and roles, Endpoints, Estoque, Import legacy DBFs, Layout, PCP + Apontamento, Quick start (Windows), Rules carried over from the legacy system (+6 more)

### Community 68 - "PurchasingFixture"
Cohesion: 0.13
Nodes (13): IAsyncLifetime, Program, HttpClient, Task, WebApplicationFactory, PurchasingFixture, ConnectionString, Handler (+5 more)

### Community 69 - "StockLine"
Cohesion: 0.28
Nodes (13): AverageCostOut, ReverseIn, StockSettingsIn, IReadOnlyList, StockLine, StockPost, DateOnly, Fact (+5 more)

### Community 70 - "dashboard_data.dart"
Cohesion: 0.04
Nodes (50): all, approved, blocked, closings, CommercialDashboard, count, countBy, counts (+42 more)

### Community 71 - "Delivery"
Cohesion: 0.07
Nodes (27): Delivery, Address, AddressId, Carrier, CreatedAt, CreatedBy, DeliveredAt, GrossWeightKg (+19 more)

### Community 72 - "ux_test.dart"
Cohesion: 0.09
Nodes (30): CheckboxListTile, main, main, open, main, _session, _login, main (+22 more)

### Community 73 - "ProductOut"
Cohesion: 0.22
Nodes (12): CustomerAddressIn, CustomerIn, ProductIn, ProductOut, RoutingOperationIn, ProductKind, Part, Fact (+4 more)

### Community 74 - ".CreateOrderCoreAsync"
Cohesion: 0.28
Nodes (6): DateOnly, ResolvedLine, CancellationToken, Dictionary, IReadOnlyCollection, Task

### Community 75 - "PurchaseOrderLine"
Cohesion: 0.04
Nodes (55): PurchasingSettings, ModelBuilder, DateOnly, GoodsReceipt, CalculatedTotal, DivergenceJustification, Id, Installments (+47 more)

### Community 76 - "GoodsReceived"
Cohesion: 0.10
Nodes (21): ConcurrentQueue, Suprimentos, Exception, HttpContext, IServiceCollection, ValueTask, PurchasingExceptionHandler, CancellationToken (+13 more)

### Community 77 - "SalesEvent"
Cohesion: 0.12
Nodes (16): DateTimeOffset, SalesEvent, Action, At, FromStatus, Id, Kind, Note (+8 more)

### Community 78 - "production_test.dart"
Cohesion: 0.10
Nodes (19): body, client, Fake, json, last, log, main, order (+11 more)

### Community 79 - "http"
Cohesion: 0.10
Nodes (21): ASPNETCORE_ENVIRONMENT, applicationUrl, commandName, dotnetRunMessages, environmentVariables, launchBrowser, applicationUrl, commandName (+13 more)

### Community 80 - "CertificateOut"
Cohesion: 0.18
Nodes (12): CancellationToken, DateOnly, DateTimeOffset, IReadOnlyList, Task, CertificateMeasureOut, CertificateOut, CertificateSummaryOut (+4 more)

### Community 81 - "ProductionService"
Cohesion: 0.06
Nodes (64): IReadOnlySet, Shortages, CancellationToken, Exception, Expression, Func, HttpContext, IReadOnlyList (+56 more)

### Community 82 - "QualityCertificate"
Cohesion: 0.06
Nodes (34): DateOnly, DateTimeOffset, List, QualityCertificate, ApprovedBy, CancelReason, Company, CreatedAt (+26 more)

### Community 83 - "Product"
Cohesion: 0.08
Nodes (25): Product, Blocked, Code, Customers, DiameterMm, DrawingRevision, HeightMm, Id (+17 more)

### Community 84 - "ProductionOrderOperation"
Cohesion: 0.08
Nodes (24): ProductionOrderOperation, Description, External, ExternalLeadDays, Id, Machine, MachineId, MeasureEnd (+16 more)

### Community 85 - "CLAUDE.md — SiderGest"
Cohesion: 0.14
Nodes (13): CLAUDE.md — SiderGest, Dev setup, Features built, Fiscal / NF, Flutter conventions, Gotchas, graphify, Migrations (+5 more)

### Community 86 - "CustomerAddress"
Cohesion: 0.10
Nodes (20): CustomerAddress, Buyer, City, CityIbgeCode, Complement, Customer, CustomerId, DefaultCfop (+12 more)

### Community 87 - "Ebt.Api.Infrastructure"
Cohesion: 0.15
Nodes (18): Ebt.Api.Infrastructure, Ebt.Api.Endpoints, Ebt.Core.Inventory, Ebt.Tests, ICollectionFixture, microsoft_aspnetcore_authorization, microsoft_aspnetcore_hosting, microsoft_aspnetcore_mvc_testing (+10 more)

### Community 88 - "LegacyRow"
Cohesion: 0.33
Nodes (4): IReadOnlyDictionary, LegacyRow, DateOnly, LegacyRowDates

### Community 89 - "CrudSpec"
Cohesion: 0.11
Nodes (17): IQueryCollection, CancellationToken, Expression, Func, IQueryable, RouteGroupBuilder, Task, CrudSpec (+9 more)

### Community 90 - "labels.dart"
Cohesion: 0.06
Nodes (31): auditActions, auditEntities, bidStatuses, billToLabels, certificateStatuses, deliveryConditions, deliveryStatuses, feasibilityActions (+23 more)

### Community 91 - "DataReset.cs"
Cohesion: 0.22
Nodes (8): Ebt.Core.Maintenance, microsoft_entityframeworkcore_storage, ResetScope, Production, Purchasing, Sales, Stock, system_data_common

### Community 92 - "AuthTests"
Cohesion: 0.25
Nodes (9): ChangePasswordRequest, CreateUserRequest, LoginRequest, RefreshRequest, IReadOnlyDictionary, Fact, JsonElement, Task (+1 more)

### Community 93 - "SteelLot"
Cohesion: 0.05
Nodes (45): ModelBuilder, DateOnly, DateTimeOffset, List, SlitterJob, FinishedKg, Id, Lot (+37 more)

### Community 94 - "FiscalService"
Cohesion: 0.15
Nodes (15): FiscalException, Field, Status, NfeParty, NfeTransport, OutsideInvoiceOptions, SaleInvoiceOptions, CancellationToken (+7 more)

### Community 95 - ".LoginAsync"
Cohesion: 0.33
Nodes (4): HttpClient, HttpResponseMessage, Task, HttpExtensions

### Community 96 - "modules.dart"
Cohesion: 0.05
Nodes (37): ModuleInfo, Navigate, _bucket, build, _commercial, _content, createState, _data (+29 more)

### Community 97 - "QuoteLine"
Cohesion: 0.12
Nodes (17): QuoteLine, CustomerPartNumber, DeliveryDate, Description, IcmsPercent, Id, IpiPercent, LeadTimeDays (+9 more)

### Community 98 - "FiscalDocument"
Cohesion: 0.05
Nodes (41): DateTimeOffset, List, FiscalDocument, AccessKey, AdditionalInfo, CancelledAt, CancelledBy, CancelProtocol (+33 more)

### Community 99 - "ProductionSettings"
Cohesion: 0.22
Nodes (9): ProductionSettings, HoursPerDay, Id, IssueLocation, IssueLocationId, OverrunTolerancePercent, ReceiptLocation, ReceiptLocationId (+1 more)

### Community 100 - "AppUser"
Cohesion: 0.12
Nodes (16): IPasswordHasher, PasswordHasher, IConfiguration, ILogger, TimeSpan, WebApplication, AuthEndpoints, AppUser (+8 more)

### Community 101 - "customers.dart"
Cohesion: 0.05
Nodes (39): _active, _addressFields, _addressLine, body, build, _c, canEdit, company (+31 more)

### Community 102 - "Supplier"
Cohesion: 0.08
Nodes (25): List, Supplier, Active, Addresses, GroupCode, Id, LegacyCode, Name (+17 more)

### Community 103 - "AverageCost"
Cohesion: 0.12
Nodes (16): AverageCost, Average, AverageGross, Id, Imported, Material, MaterialId, MonthAverage (+8 more)

### Community 104 - "reports.dart"
Cohesion: 0.05
Nodes (43): _asc, ascending, BillingSummaryScreen, _BillingSummaryScreenState, build, _cells, _code, _companies (+35 more)

### Community 105 - "FiscalInstallment"
Cohesion: 0.25
Nodes (8): DateOnly, FiscalInstallment, Amount, Document, DocumentId, DueDate, Id, Sequence

### Community 106 - "FiscalEndpoints.cs"
Cohesion: 0.13
Nodes (16): Ebt.Core.Certificates, ebt_api_infrastructure_crud, CertificateLinkIn, CertificatePolicies, CertificateReasonIn, CertificateWaiverIn, DateOnly, DateTimeOffset (+8 more)

### Community 107 - "ICurrentUser"
Cohesion: 0.40
Nodes (5): IHttpContextAccessor, HttpCurrentUser, Name, ICurrentUser, Name

### Community 108 - "steel.dart"
Cohesion: 0.05
Nodes (39): api, base, _body, build, _create, createState, _deleteChild, _deleteLot (+31 more)

### Community 109 - "viability.dart"
Cohesion: 0.05
Nodes (38): api, base, _body, build, context, createState, _delete, _edit (+30 more)

### Community 110 - "Ebt.Core.Services"
Cohesion: 0.18
Nodes (8): Ebt.Core.Viability, Ebt.Core.Services, Ebt.Core.Production, Ebt.Core.Fiscal, Ebt.Core.Sales, ebt_core_services_text, Text, xunit

### Community 111 - "OutsideShipment"
Cohesion: 0.11
Nodes (19): DateOnly, Holiday, Date, Id, Name, OutsideShipment, CreatedBy, Id (+11 more)

### Community 112 - "ProductionOrderMaterial"
Cohesion: 0.14
Nodes (14): ProductionOrderMaterial, ComponentProduct, ComponentProductId, Id, Material, MaterialId, OperationSequence, Order (+6 more)

### Community 114 - ".Billing_summary_splits_companies_and_consumption_lists_shipped_lines"
Cohesion: 0.11
Nodes (25): Setup, StockLocationIn, StockLocationOut, CustomerAddressOut, CustomerCompany, CustomerOut, PaymentTermOut, SalesReleaseIn (+17 more)

### Community 115 - "SefazSpClient"
Cohesion: 0.11
Nodes (26): Body, HttpMessageHandler, HttpRequestMessage, HttpClient, X509Certificate2, XNamespace, SefazOptions, CertificatePassword (+18 more)

### Community 116 - "IExceptionHandler"
Cohesion: 0.13
Nodes (15): IExceptionHandler, microsoft_aspnetcore_diagnostics, npgsql, CancellationToken, Exception, HttpContext, ValueTask, FiscalExceptionHandler (+7 more)

### Community 117 - "start.ps1"
Cohesion: 0.19
Nodes (4): Fail(), Find-Port(), Test-Bindable(), Test-Port()

### Community 118 - ".Describe"
Cohesion: 0.18
Nodes (9): Tables, GeneratedRegex, IReadOnlyList, Regex, LegacyDbf, LegacyTable, Control, Control (+1 more)

### Community 119 - "api_integration_test.dart"
Cohesion: 0.17
Nodes (11): ApiClient, ApiException, api, login, main, password, skip, url (+3 more)

### Community 120 - "fiscal.dart"
Cohesion: 0.07
Nodes (31): api, base, _body, build, _cancel, createState, _d, _edit (+23 more)

### Community 121 - "SalesService"
Cohesion: 0.14
Nodes (18): ResolvedLine, Delivery, Quote, SalesException, Field, Status, CancellationToken, Func (+10 more)

### Community 123 - "PriceListEntry"
Cohesion: 0.17
Nodes (12): DateOnly, PriceListEntry, Customer, CustomerId, IcmsPercent, Id, IpiPercent, Product (+4 more)

### Community 124 - "ImportOptions"
Cohesion: 0.18
Nodes (11): IReadOnlyList, ImportOptions, CodePage, DefaultNcm, Directory, DryRun, Steps, CancellationToken (+3 more)

### Community 125 - "QuoteExpiryService"
Cohesion: 0.27
Nodes (8): BackgroundService, IServiceScopeFactory, PeriodicTimer, CancellationToken, ILogger, Task, TimeSpan, QuoteExpiryService

### Community 126 - "package:flutter/material.dart"
Cohesion: 0.04
Nodes (57): ../api.dart, ApiClient get, ChangeNotifier, AuditDetailDialog, AuditScreen, _AuditScreenState, build, createState (+49 more)

### Community 127 - "StockMovement"
Cohesion: 0.11
Nodes (18): StockMovement, Date, Document, DocumentId, IcmsRate, Id, Location, LocationId (+10 more)

### Community 129 - "CertificateService"
Cohesion: 0.32
Nodes (6): WebApplication, CancellationToken, CultureInfo, Dictionary, Task, CertificateService

### Community 131 - "Employee"
Cohesion: 0.18
Nodes (11): Employee, Active, Code, Function, Id, Name, Nickname, Shift (+3 more)

### Community 133 - "Screens"
Cohesion: 0.20
Nodes (9): Build, Estoque, Painel, Roles, Run, Screens, SiderGest — Flutter client, Suprimentos (+1 more)

### Community 136 - "SefazEnvironment"
Cohesion: 0.15
Nodes (15): IConfiguration, IServiceCollection, SefazEnvironment, Homologation, Production, CancellationToken, Task, ISefazClient (+7 more)

### Community 137 - "main.dart"
Cohesion: 0.20
Nodes (9): appTheme, build, cs, EbtApp, main, restore, session, screens/login.dart (+1 more)

### Community 138 - "RowVersionFilter"
Cohesion: 0.24
Nodes (7): EndpointFilterDelegate, EndpointFilterInvocationContext, IEndpointFilter, CancellationToken, Task, ValueTask, RowVersionFilter

### Community 139 - "FiscalDocumentLine"
Cohesion: 0.06
Nodes (31): FiscalDocumentLine, Code, CofinsCst, CofinsPercent, CofinsValue, Description, Document, DocumentId (+23 more)

### Community 140 - "Revision"
Cohesion: 0.12
Nodes (17): DateTimeOffset, RevisionIn, RevisionOut, DateTimeOffset, Revision, Code, CreatedAt, Id (+9 more)

### Community 141 - "FeasibilityStudy"
Cohesion: 0.06
Nodes (31): DateTimeOffset, FeasibilityStudy, Characteristics, CommercialAt, CommercialBy, CommercialNote, CreatedAt, CreatedBy (+23 more)

### Community 142 - "QuoteStatus"
Cohesion: 0.18
Nodes (11): QuoteStatus, Accepted, Approved, Cancelled, Converted, Draft, Expired, PendingApproval (+3 more)

### Community 143 - "report_doc.dart"
Cohesion: 0.07
Nodes (27): build, cells, enabled, fileBase, filters, flex, headers, kind (+19 more)

### Community 144 - "UserRole"
Cohesion: 0.15
Nodes (12): AuthorizationOptions, IReadOnlyDictionary, Access, UserRole, Admin, Engineering, Production, Purchasing (+4 more)

### Community 145 - "MovementType"
Cohesion: 0.06
Nodes (33): CancellationToken, ClaimsPrincipal, DateOnly, DateTimeOffset, Expression, IReadOnlyList, StockSettings, Task (+25 more)

### Community 146 - "RefreshToken"
Cohesion: 0.22
Nodes (8): DateTimeOffset, RefreshToken, CreatedAt, Id, RevokedAt, TokenHash, User, UserId

### Community 147 - "deliveries.dart"
Cohesion: 0.08
Nodes (27): api, base, build, _cancel, _certs, _confirm, createState, _d (+19 more)

### Community 148 - "nav.dart"
Cohesion: 0.25
Nodes (7): ensureVisible, module, openModule, openScreen, pumpAndSettle, tap, tester

### Community 149 - "StockException"
Cohesion: 0.29
Nodes (7): StockErrorKind, Conflict, Invalid, NotFound, StockException, Field, Kind

### Community 150 - "Auth.cs"
Cohesion: 0.14
Nodes (12): microsoft_aspnetcore_authentication_jwtbearer, microsoft_aspnetcore_httpoverrides, microsoft_aspnetcore_identity, microsoft_identitymodel_tokens, microsoft_openapi_models, Policies, system_identitymodel_tokens_jwt, system_security_cryptography (+4 more)

### Community 151 - ".TryHandleAsync"
Cohesion: 0.29
Nodes (5): Exception, HttpContext, IServiceCollection, ValueTask, SalesExceptionHandler

### Community 152 - "certificate_doc.dart"
Cohesion: 0.08
Nodes (25): address, _b, buildCertificatePdf, cancelled, _cell, company, _dash, doc (+17 more)

### Community 153 - "Clock"
Cohesion: 0.38
Nodes (3): DateOnly, Clock, TimeZoneInfo

### Community 154 - ".InTransactionAsync"
Cohesion: 0.33
Nodes (4): CancellationToken, Func, Task, DbTransactions

### Community 155 - ".Safe"
Cohesion: 0.50
Nodes (3): GeneratedRegex, Regex, SqlIdentifier

### Community 156 - ".MapReports"
Cohesion: 0.17
Nodes (18): From, CancellationToken, DateOnly, IReadOnlyList, List, Task, WebApplication, BillingRow (+10 more)

### Community 158 - ".ConfigureSales"
Cohesion: 0.13
Nodes (14): ModelBuilder, SalesSettings, DeliveryLine, Delivery, DeliveryId, Id, OrderLine, OrderLineId (+6 more)

### Community 159 - "Cfop"
Cohesion: 0.08
Nodes (23): CfopIn, CfopOut, Cfop, Active, Code, CofinsCst, DefaultCofinsPercent, DefaultPisPercent (+15 more)

### Community 160 - "NfeSigner"
Cohesion: 0.24
Nodes (7): Como funciona, Emissão de NF-e, Ligar a SEFAZ real (SEFAZ-SP), O que é STUB / não feito, Premissas a confirmar com o contador, X509Certificate2, NfeSigner

### Community 161 - "admin_screens_test.dart"
Cohesion: 0.09
Nodes (21): client, json, log, main, open, pumpAndSettle, pumpWidget, session (+13 more)

### Community 162 - ".SetMeasures"
Cohesion: 0.25
Nodes (6): DateOnly, IEnumerable, IReadOnlyList, List, CertificateInput, CertificateMeasureInput

### Community 165 - ".ResetAsync"
Cohesion: 0.22
Nodes (14): DbConnection, Fk, CancellationToken, Dictionary, HashSet, IEnumerable, IReadOnlyCollection, IReadOnlyList (+6 more)

### Community 166 - "Shift"
Cohesion: 0.25
Nodes (8): TimeOnly, Shift, Code, EndsAt, Hours, Id, Name, StartsAt

### Community 167 - ".NewRefreshAsync"
Cohesion: 0.13
Nodes (15): CancellationToken, DateTimeOffset, Task, JwtOptions, Audience, ClockSkewSeconds, ExpiresMinutes, Issuer (+7 more)

### Community 168 - "PaymentTerm"
Cohesion: 0.29
Nodes (7): PaymentTerm, Active, Code, CreditLimit, Days, Id, Name

### Community 171 - "discard_guard.dart"
Cohesion: 0.33
Nodes (5): build, child, confirmDiscard, DiscardGuard, Widget?

### Community 173 - "FiscalSettings"
Cohesion: 0.10
Nodes (21): FiscalSettings, CancelWindowHours, City, CityIbgeCode, Cnpj, CompanyName, Complement, District (+13 more)

### Community 174 - "ApiFixture"
Cohesion: 0.33
Nodes (5): IServiceScope, JsonSerializerOptions, WebApplicationFactory, ApiFixture, ConnectionString

### Community 175 - "SignoffArea"
Cohesion: 0.33
Nodes (5): ViabilityPolicies, SignoffArea, Commercial, Production, Quality

### Community 176 - "viability_steel_test.dart"
Cohesion: 0.11
Nodes (17): body, client, Fake, job, json, last, log, lot (+9 more)

### Community 177 - ".ValidateAsync"
Cohesion: 0.29
Nodes (7): CancellationToken, Dictionary, IEnumerable, IReadOnlyCollection, Task, ViabilityRules, StudyId

### Community 178 - "user_settings.dart"
Cohesion: 0.08
Nodes (26): _again, build, _busy, _ChangePassword, _ChangePasswordState, clear, _clearCache, clearLocalCache (+18 more)

### Community 179 - ".MapViability"
Cohesion: 0.32
Nodes (5): ClaimsPrincipal, WebApplication, FeasibilityIn, ViabilityEndpoints, FeasibilityStudy

### Community 180 - ".MapMasterData"
Cohesion: 0.10
Nodes (22): FiscalSettings, WebApplication, FiscalEndpoints, MonthlyPriceOut, TaxRuleIn, TaxRuleOut, CancellationToken, Dictionary (+14 more)

### Community 181 - ".Steel_lot_slitter_and_usage_balance"
Cohesion: 0.21
Nodes (13): DateOnly, DateTimeOffset, Expression, IServiceCollection, SlitterJobIn, SlitterJobOut, SteelEndpoints, SteelLotIn (+5 more)

### Community 182 - "NfeXml"
Cohesion: 0.39
Nodes (4): CultureInfo, XElement, XNamespace, NfeXml

### Community 183 - "data_reset.dart"
Cohesion: 0.08
Nodes (25): _body, build, _busy, _confirm, createState, dataResetConfirmWord, _DataResetDialog, _DataResetDialogState (+17 more)

### Community 184 - "AuditEntry"
Cohesion: 0.22
Nodes (9): DateTimeOffset, AuditEntry, Action, At, Changes, Entity, EntityId, Id (+1 more)

### Community 185 - "login.dart"
Cohesion: 0.09
Nodes (22): build, _busy, _capsLock, _clearError, createState, dispose, _error, _failures (+14 more)

### Community 186 - ".Deactivating_a_user_revokes_existing_tokens"
Cohesion: 0.47
Nodes (3): UpdateUserRequest, UserDto, List

### Community 187 - "CertificateEndpoints"
Cohesion: 0.40
Nodes (3): ClaimsPrincipal, IServiceCollection, CertificateEndpoints

### Community 188 - ".Load"
Cohesion: 0.50
Nodes (3): CancellationToken, Task, FeasibilityOrderOut

### Community 189 - ".Sale_nf_needs_monthly_price_is_recorded_only_after_authorization_and_can_be_cancelled"
Cohesion: 0.10
Nodes (24): CancelInvoiceIn, FiscalSettingsDto, MonthlyPriceIn, StockBalanceOut, MachineIn, MachineOut, MaterialIn, SubgroupIn (+16 more)

### Community 190 - "SalesSettings"
Cohesion: 0.18
Nodes (11): SalesSettings, ApprovalValidityDays, DefaultConditions, DefaultValidityDays, FollowUpDays, Id, MaxDiscountPercent, MinimumOrderValue (+3 more)

### Community 191 - "FeasibilityStatus"
Cohesion: 0.22
Nodes (8): DateTimeOffset, FeasibilitySummaryOut, SignoffOut, FeasibilityStatus, Approved, Draft, InReview, Rejected

### Community 192 - "TaxRule"
Cohesion: 0.10
Nodes (18): PropertyBuilder, FiscalSettings, ModelBuilder, TaxRule, Cfop, CfopCode, CofinsPercent, Customer (+10 more)

### Community 193 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.11
Nodes (18): certificate, main, main, open, main, doc, main, main (+10 more)

### Community 198 - "AuditInterceptor"
Cohesion: 0.12
Nodes (18): _Entry, DbContextErrorEventData, DbContextEventData, EntityEntry, InterceptionResult, SaveChangesCompletedEventData, SaveChangesInterceptor, CancellationToken (+10 more)

### Community 340 - "workdays.dart"
Cohesion: 0.09
Nodes (21): a, addWorkDays, d, day, _easter, goodFriday, h, _holidayCache (+13 more)

### Community 341 - ".OnModelCreating"
Cohesion: 0.07
Nodes (27): ModelBuilder, ConsumerType, FinalConsumer, Normal, MaterialClass, Code, Id, Name (+19 more)

### Community 343 - "StatefulWidget"
Cohesion: 0.05
Nodes (45): _CustomerAddresses, build, createState, initialStatus, inspect, _list, LotsView, _LotsViewState (+37 more)

### Community 344 - "GoodsReceiptLine"
Cohesion: 0.12
Nodes (16): GoodsReceiptLine, DiscountPercent, GoodsReceipt, GoodsReceiptId, IcmsPercent, Id, IpiPercent, LotCode (+8 more)

### Community 346 - "Product"
Cohesion: 0.11
Nodes (19): Product, ProductCustomer, Active, Customer, CustomerDescription, CustomerId, CustomerPartNumber, Product (+11 more)

### Community 348 - "BomItem"
Cohesion: 0.18
Nodes (11): BomItem, ComponentProduct, ComponentProductId, Factor, Id, Material, MaterialId, Quantity (+3 more)

### Community 349 - ".Add"
Cohesion: 0.32
Nodes (4): DateOnly, WorkDays, Fact, WorkDaysTests

### Community 355 - "Production.cs"
Cohesion: 0.22
Nodes (9): OccurrenceKind, Downtime, Scrap, ProductionOccurrence, Code, Description, Id, Kind (+1 more)

### Community 356 - ".Full_stock_order_ships_and_completes"
Cohesion: 0.12
Nodes (25): SalesOrderIn, SalesOrderLineOut, FreightTerms, Cif, CustomerPickup, Fob, OrderOrigin, Email (+17 more)

### Community 357 - "OverrunRelease"
Cohesion: 0.22
Nodes (9): DateTimeOffset, OverrunRelease, Id, Justification, Operation, OperationId, Quantity, ReleasedAt (+1 more)

## Knowledge Gaps
- **3252 isolated node(s):** `status`, `message`, `fieldErrors`, `items`, `total` (+3247 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 3672 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **38 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AuditInterceptor` connect `AuditInterceptor` to `ICurrentUser`, `Ebt.Core.Entities`?**
  _High betweenness centrality (0.297) - this node is a cross-community bridge._
- **Why does `_Entry` connect `AuditInterceptor` to `command_palette.dart`?**
  _High betweenness centrality (0.296) - this node is a cross-community bridge._
- **Why does `EbtDbContext` connect `EbtDbContext` to `CertificateService`, `.NewDb`, `StockDocument`, `PurchasingEndpoints.cs`, `RowVersionFilter`, `FiscalDocumentLine`, `Revision`, `StockService`, `PurchasingService`, `MovementType`, `RefreshToken`, `Quotation`, `.InTransactionAsync`, `.MapReports`, `ProductionImport`, `.ConfigureSales`, `Cfop`, `StockLot`, `.ResetAsync`, `.MapQuotes`, `.NewRefreshAsync`, `Material`, `PurchaseRequisition`, `Ebt.Core.Entities`, `RoutingOperation`, `.ValidateAsync`, `.MapViability`, `.MapMasterData`, `.MapProducts`, `PurchasingImport`, `ProductionReport`, `AuditEntry`, `CertificateMeasure`, `ImportReport`, `.Load`, `SalesOrder`, `SalesOrderLine`, `Importer`, `PurchasingEndpoints`, `TaxRule`, `PurchasingFixture`, `PurchaseOrderLine`, `GoodsReceived`, `SalesEvent`, `CertificateOut`, `ProductionService`, `QualityCertificate`, `ProductionOrderOperation`, `.OnModelCreating`, `CustomerAddress`, `GoodsReceiptLine`, `CrudSpec`, `Product`, `.ConfigureViability`, `SteelLot`, `BomItem`, `FiscalService`, `QuoteLine`, `FiscalDocument`, `Production.cs`, `AppUser`, `OverrunRelease`, `Supplier`, `AverageCost`, `FiscalInstallment`, `FiscalEndpoints.cs`, `OutsideShipment`, `ProductionOrderMaterial`, `SalesService`, `PriceListEntry`, `ImportOptions`, `StockMovement`?**
  _High betweenness centrality (0.243) - this node is a cross-community bridge._
- **What connects `status`, `message`, `fieldErrors` to the rest of the system?**
  _3252 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `entities.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.023255813953488372 - nodes in this community are weakly interconnected._
- **Should `EbtDbContext` be split into smaller, more focused modules?**
  _Cohesion score 0.022455805064500716 - nodes in this community are weakly interconnected._
- **Should `shell.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.032167832167832165 - nodes in this community are weakly interconnected._