<!-- Snapshot of graphify-out/GRAPH_REPORT.md. Regenerate with: graphify update . -->

# Graph Report - extract-certificates-improve-design-289a54  (2026-11-01)

## Corpus Check
- 219 files · ~229,789 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 25 file(s) not represented in the graph (top: .xsd 10, (none) 8, .ttf 2)

## Summary
- 6279 nodes · 12990 edges · 242 communities (201 shown, 41 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 1191 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `740e888d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- entities.dart
- EbtDbContext
- shell.dart
- sales_quotes.dart
- .NewDb
- StockLot
- dashboard.dart
- production_orders.dart
- PurchasingEndpoints.cs
- record_list.dart
- sales_common.dart
- stock_documents.dart
- entity_form.dart
- StockService
- PurchasingService
- Ebt.Core.Entities
- command_palette.dart
- receipts.dart
- orders.dart
- quotations.dart
- stock_balances.dart
- sales_orders.dart
- GoodsReceipt
- print_docs.dart
- production_floor.dart
- pipeline.dart
- .AdminAsync
- PurchaseOrder
- ProductionImport
- State
- danfe_doc.dart
- ProductionOrder
- stock_closing.dart
- session.dart
- actions.dart
- dashboard_test.dart
- SalesEndpoints.cs
- dash.dart
- NfeTaxTests
- .MapQuotes
- Material
- PurchaseRequisition
- Quote
- app_test.dart
- entity_list.dart
- microsoft_entityframeworkcore
- RoutingOperation
- stock_purchasing_test.dart
- Ebt.Core.csproj
- .Arrange
- nf_doc.dart
- api.dart
- .MapProducts
- ProductionOrderStatus
- PurchasingImport
- ProductionReport
- sales_test.dart
- .Import_creates_templates_for_known_customers_and_products_and_keeps_existing_ones
- ImportReport
- Sales.cs
- SalesOrder
- SalesOrderLine
- LegacyRow
- certificates.dart
- PurchasingEndpoints
- Customer
- StatelessWidget
- String?
- PurchasingFixture
- StockLine
- dashboard_data.dart
- Delivery
- dart:convert
- CustomerIn
- Inventory.cs
- GoodsReceiptLine
- GoodsReceived
- SalesEvent
- production_test.dart
- http
- ProductionModels.cs
- ProductionService
- QualityCertificate
- Product
- ProductionOrderOperation
- CLAUDE.md — MetaGest
- CustomerAddress
- Ebt.Api.Infrastructure
- NfeSchema
- CrudSpec
- labels.dart
- .Conflict
- ApiFixture
- SteelLot
- FiscalService
- .Has
- modules.dart
- QuoteLine
- FiscalDocument
- print_panel.dart
- AppUser
- customers.dart
- SupplierAddress
- AverageCost
- reports.dart
- SourceFlagger
- ProductionEndpoints.cs
- ICurrentUser
- steel.dart
- viability.dart
- alerts.dart
- OutsideShipment
- Production.cs
- dart_project
- StockBalance
- SefazSpClient
- IExceptionHandler
- start.ps1
- MetaGest — Engenharia, Estoque, Suprimentos, PCP
- api_integration_test.dart
- fiscal.dart
- SalesService
- .ProgressAsync
- .Delivery_records_lot_invoiced_value_and_balances
- ImportOptions
- QuoteExpiryService
- ../entities.dart
- StockMovement
- ebt_core_certificates
- CertificateService
- ebt_core_fiscal
- Employee
- ebt_core_inventory
- MetaGest — Flutter client
- ebt_core_production
- ebt_core_viability
- SefazEnvironment
- SlitterJob
- RowVersionFilter
- FiscalDocumentLine
- Revision
- FeasibilityStudy
- QuoteStatus
- report_doc.dart
- UserRole
- .MapInventory
- .ConfigureSales
- deliveries.dart
- package:flutter_test/flutter_test.dart
- StockException
- Auth.cs
- SearchEndpoints.cs
- certificate_doc.dart
- Clock
- .InTransactionAsync
- .Safe
- .MapReports
- flutter_secure_storage_windows_plugin
- LegacySpecImporter.cs
- Cfop
- ProductionOrderMaterial
- admin_screens_test.dart
- BomService
- role_permissions.dart
- plugin_registry
- .ResetAsync
- StockDocument
- .ScheduleTreeAsync
- PurchasingFixture.cs
- Exception
- List
- discard_guard.dart
- FiscalSettings
- print_gate.dart
- AuditInterceptor
- viability_steel_test.dart
- SalesOrderStatus
- user_settings.dart
- .MapViability
- .MapMasterData
- .Steel_lot_slitter_and_usage_balance
- FiscalInutilization
- data_reset.dart
- AuditEntry
- login.dart
- PurchaseOrderLine
- fiscal_test.dart
- SteelUsage
- Page
- .ConfigureProduction
- FeasibilityOut
- .Production_dashboard_splits_late_orders_into_recent_and_legacy
- package:flutter/material.dart
- _CustomPrazoDialog
- EntityFormDialog
- LookupField
- LookupPicker
- .FlushInserts
- MetaGest operations
- OverrunRelease
- .Build
- .ListAsync
- JwtOptions
- .Search_returns_grouped_hits_capped_by_take
- .Load
- .MapSteel
- DataResetOut
- .MapAudit
- ResetScope
- SalesException
- WorkDaysTests.cs
- microsoft_openapi_models
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
- StatefulWidget
- Product
- BomItem
- .Add
- SalesModels.cs

## God Nodes (most connected - your core abstractions)
1. `EbtDbContext` - 265 edges
2. `Ebt.Core.Entities` - 86 edges
3. `SalesService` - 80 edges
4. `FiscalDocument` - 68 edges
5. `ProductionService` - 68 edges
6. `StockService` - 62 edges
7. `SalesOrder` - 60 edges
8. `QualityCertificate` - 57 edges
9. `Ebt.Core.Data` - 56 edges
10. `Material` - 53 edges

## Surprising Connections (you probably didn't know these)
- `Fiscal / NF` --references--> `StubSefazClient`  [INFERRED]
  CLAUDE.md → src/Ebt.Core/Fiscal/StubSefazClient.cs
- `Estoque` --references--> `StockService`  [INFERRED]
  README.md → src/Ebt.Core/Inventory/StockService.Costing.cs
- `Permissions` --references--> `AccessParityTests`  [INFERRED]
  ARCHITECTURE.md → tests/Ebt.Tests/AccessParityTests.cs
- `Backend conventions` --references--> `FiscalEndpoints`  [INFERRED]
  CLAUDE.md → src/Ebt.Api/Endpoints/FiscalEndpoints.cs
- `Backend conventions` --references--> `InventoryEndpoints`  [INFERRED]
  CLAUDE.md → src/Ebt.Api/Endpoints/InventoryEndpoints.cs

## Import Cycles
- None detected.

## Communities (242 total, 41 thin omitted)

### Community 0 - "entities.dart"
Cohesion: 0.02
Nodes (85): b, bomItemFields, choices, codeName, col, columns, ColumnSpec, d (+77 more)

### Community 1 - "EbtDbContext"
Cohesion: 0.02
Nodes (93): DbContext, IDesignTimeDbContextFactory, DbContextOptions, DesignTimeFactory, DbSet, EbtDbContext, CertificateMeasures, CertificateTemplateMeasures (+85 more)

### Community 2 - "shell.dart"
Cohesion: 0.02
Nodes (88): audit.dart, api, icon, label, of, QuickAction, quickActionsFor, r (+80 more)

### Community 3 - "sales_quotes.dart"
Cohesion: 0.02
Nodes (124): _accept, _acceptedStep, _act, _addresses, _addressId, api, _applyDefaultTerm, _approvalBanner (+116 more)

### Community 4 - ".NewDb"
Cohesion: 0.07
Nodes (29): IDisposable, Component, DateOnly, StockImportOptions, CodePage, Directory, DryRun, OpeningDate (+21 more)

### Community 5 - "StockLot"
Cohesion: 0.05
Nodes (40): ModelBuilder, StockSettings, DateOnly, DateTimeOffset, StockClosing, ClosedAt, ClosedBy, Id (+32 more)

### Community 6 - "dashboard.dart"
Cohesion: 0.04
Nodes (57): _alerts, _all, allOverdue, attention, blurb, build, buildAlerts, _combine (+49 more)

### Community 7 - "production_orders.dart"
Cohesion: 0.03
Nodes (66): _actions, api, base, build, _bump, _children, context, _cost (+58 more)

### Community 8 - "PurchasingEndpoints.cs"
Cohesion: 0.12
Nodes (42): DateOnly, DateTimeOffset, IReadOnlyList, AwardIn, BidOut, ComparisonBidOut, ComparisonItemOut, DueDateIn (+34 more)

### Community 9 - "record_list.dart"
Cohesion: 0.03
Nodes (73): actions, actionsFirst, alert, _aligned, allLabel, api, _ascending, attach (+65 more)

### Community 10 - "sales_common.dart"
Cohesion: 0.08
Nodes (25): build, deliveryPath, deliveryTone, flowSteps, gap, isSuperseded, main, openDelivery (+17 more)

### Community 11 - "stock_documents.dart"
Cohesion: 0.04
Nodes (52): _body, _open, build, _receive, _materials, newProduct, _order, _new (+44 more)

### Community 12 - "entity_form.dart"
Cohesion: 0.04
Nodes (54): LookupSpec, api, _applyFill, askCustomPrazo, _body, build, _busy, _clientErrors (+46 more)

### Community 13 - "StockService"
Cohesion: 0.11
Nodes (26): L, M, P, CancellationToken, DateOnly, List, Task, BeforeRow (+18 more)

### Community 14 - "PurchasingService"
Cohesion: 0.16
Nodes (12): PurchaseOrder, CancellationToken, GeneratedRegex, IEnumerable, List, Regex, Task, BidInput (+4 more)

### Community 15 - "Ebt.Core.Entities"
Cohesion: 0.12
Nodes (13): Ebt.DbfImport, Ebt.Core.Services, Ebt.Core.Fiscal, Ebt.Core.Entities, dbfdatareader, system_globalization, system_reflection, system_security_cryptography_x509certificates (+5 more)

### Community 16 - "command_palette.dart"
Cohesion: 0.04
Nodes (46): actions, add, build, clear, _close, compact, createState, _debounce (+38 more)

### Community 17 - "receipts.dart"
Cohesion: 0.05
Nodes (44): allowNew, api, build, _busy, _calculated, createState, _date, dispose (+36 more)

### Community 18 - "orders.dart"
Cohesion: 0.05
Nodes (43): active, api, base, _busy, createState, d, dispose, _error (+35 more)

### Community 19 - "quotations.dart"
Cohesion: 0.05
Nodes (40): _addSupplier, api, base, bidFields, _bids, build, _busy, _call (+32 more)

### Community 20 - "stock_balances.dart"
Cohesion: 0.11
Nodes (18): _Availability, BalancesScreen, _BalancesScreenState, createState, _includeZero, initState, item, ItemStockScreen (+10 more)

### Community 21 - "sales_orders.dart"
Cohesion: 0.03
Nodes (74): api, base, _billTo, _body, build, _cancel, _cardPrint, _certified (+66 more)

### Community 22 - "GoodsReceipt"
Cohesion: 0.04
Nodes (61): QuotationSummaryOut, DateTimeOffset, List, BidStatus, Approved, Pending, Rejected, GoodsReceipt (+53 more)

### Community 23 - "print_docs.dart"
Cohesion: 0.02
Nodes (87): _b, blankRows, _blue, box, _build, buildProductionOrderPdf, buildQuotePdf, buildSalesOrderPdf (+79 more)

### Community 24 - "production_floor.dart"
Cohesion: 0.05
Nodes (42): build, _color, context, createState, cs, _fetch, _from, _grid (+34 more)

### Community 25 - "pipeline.dart"
Cohesion: 0.05
Nodes (40): actions, amount, at, badge, build, c, caption, _Chevron (+32 more)

### Community 26 - ".AdminAsync"
Cohesion: 0.20
Nodes (15): IServiceScope, DataResetIn, QuoteOut, QuoteRequestIn, SalesOrderIn, SalesReleaseIn, ConvertInput, SalesLineInput (+7 more)

### Community 27 - "PurchaseOrder"
Cohesion: 0.10
Nodes (21): PurchaseOrder, ClosedAt, ClosedBy, CloseReason, Id, IssuedAt, IssuedBy, Lines (+13 more)

### Community 28 - "ProductionImport"
Cohesion: 0.15
Nodes (16): ProductionOrderKind, Internal, Standard, CancellationToken, Control, DateOnly, DateTimeOffset, Dictionary (+8 more)

### Community 29 - "State"
Cohesion: 0.06
Nodes (41): bool get, _CustomerAddressesState, _add, api, base, build, canWrite, createState (+33 more)

### Community 30 - "danfe_doc.dart"
Cohesion: 0.05
Nodes (39): banner, bold, buildDanfePdf, c, cancelled, _cell, _cep, d (+31 more)

### Community 31 - "ProductionOrder"
Cohesion: 0.05
Nodes (38): List, ProductionOrder, AdjustedEnd, AdjustedStart, Bales, ClosedAt, ClosedBy, CostClosedAt (+30 more)

### Community 32 - "stock_closing.dart"
Cohesion: 0.06
Nodes (33): build, _busy, _card, _close, _closings, ClosingScreen, _ClosingScreenState, createState (+25 more)

### Community 33 - "session.dart"
Cohesion: 0.04
Nodes (56): alerts, api, _apply, baseUrl, canApproveSales, canBuy, canCertificate, canCustomers (+48 more)

### Community 34 - "actions.dart"
Cohesion: 0.06
Nodes (35): addEnabled, addLabel, api, build, _c, columns, confirmLabel, createState (+27 more)

### Community 35 - "dashboard_test.dart"
Cohesion: 0.09
Nodes (21): Card, client, json, legacyListTest, lists, log, main, openPalette (+13 more)

### Community 36 - "SalesEndpoints.cs"
Cohesion: 0.12
Nodes (32): DateOnly, DateTimeOffset, IReadOnlyList, ConfirmDeliveryIn, DeliveryLineOut, DeliveryOut, DeliverySummaryOut, LostReasonOut (+24 more)

### Community 37 - "dash.dart"
Cohesion: 0.07
Nodes (29): alert, BarPanel, build, child, dashCardShape, DashGrid, DashNotice, DashTile (+21 more)

### Community 38 - "NfeTaxTests"
Cohesion: 0.12
Nodes (20): Case, Expected, NfeTransport, CultureInfo, DateTimeOffset, XNamespace, NfeInut, Fact (+12 more)

### Community 39 - ".MapQuotes"
Cohesion: 0.13
Nodes (17): Id, CancellationToken, ClaimsPrincipal, Dictionary, Expression, Func, IEnumerable, IQueryable (+9 more)

### Community 40 - "Material"
Cohesion: 0.05
Nodes (39): ModelBuilder, Material, Active, Class, ClassId, Code, Description, ExternalProcessing (+31 more)

### Community 41 - "PurchaseRequisition"
Cohesion: 0.06
Nodes (34): PurchaseRequisition, Application, ApprovedQuantity, DecidedAt, DecidedBy, DecisionNote, Department, Description (+26 more)

### Community 42 - "Quote"
Cohesion: 0.05
Nodes (40): Quote, Address, AddressId, ApprovedAt, ApprovedBy, Conditions, ContactEmail, ContactName (+32 more)

### Community 43 - "app_test.dart"
Cohesion: 0.12
Nodes (15): enterText, fakeBackend, json, login, main, page, path, product (+7 more)

### Community 44 - "entity_list.dart"
Cohesion: 0.06
Nodes (33): PageResult, EntitySpec, api, build, canWrite, createState, _debounce, dispose (+25 more)

### Community 45 - "microsoft_entityframeworkcore"
Cohesion: 0.14
Nodes (10): Ebt.Core.Viability, Ebt.Core.Production, Ebt.Core.Inventory, Ebt.Core.Data, Ebt.Core.Sales, ebt_core_services_text, microsoft_entityframeworkcore, microsoft_entityframeworkcore_design (+2 more)

### Community 46 - "RoutingOperation"
Cohesion: 0.05
Nodes (45): ConsumerType, FinalConsumer, Normal, Machine, Code, Family, Id, Name (+37 more)

### Community 47 - "stock_purchasing_test.dart"
Cohesion: 0.06
Nodes (30): bidStatus, body, client, comparison, doc, Fake, json, last (+22 more)

### Community 48 - "Ebt.Core.csproj"
Cohesion: 0.07
Nodes (26): coverlet.collector (6.0.2), DbfDataReader (0.9.0), EFCore.NamingConventions (10.0.1), Microsoft.AspNetCore.Authentication.JwtBearer (10.0.14), Microsoft.AspNetCore.Mvc.Testing (10.0.14), Microsoft.Extensions.Identity.Core (10.0.14), Microsoft.NET.Test.Sdk (17.11.1), Npgsql.EntityFrameworkCore.PostgreSQL (10.0.3) (+18 more)

### Community 49 - ".Arrange"
Cohesion: 0.16
Nodes (25): StockDocumentSummary, MachineOut, SupplierIn, SupplierOut, BomItemIn, DateTimeOffset, AvailabilityCheckIn, OccurrenceIn (+17 more)

### Community 50 - "nf_doc.dart"
Cohesion: 0.03
Nodes (75): a, ad, addresses, askNfFiscal, base, buildOutsideNfPdf, buildSaleNfPdf, _cell (+67 more)

### Community 51 - "api.dart"
Cohesion: 0.04
Nodes (47): Client, _baseUrl, _call, cap, clearVersions, delete, describeError, _doRefresh (+39 more)

### Community 52 - ".MapProducts"
Cohesion: 0.13
Nodes (18): CancellationToken, DateTimeOffset, Dictionary, Expression, IReadOnlyDictionary, IReadOnlyList, IResult, List (+10 more)

### Community 53 - "ProductionOrderStatus"
Cohesion: 0.25
Nodes (8): ProductionOrderStatus, Cancelled, Closed, Created, Finished, InProduction, Released, Stopped

### Community 54 - "PurchasingImport"
Cohesion: 0.12
Nodes (16): QuotationItem, Tables, CancellationToken, Control, DateOnly, DateTimeOffset, Dictionary, Encoding (+8 more)

### Community 55 - "ProductionReport"
Cohesion: 0.07
Nodes (30): ProductionReport, Date, DowntimeHours, DowntimeOccurrence, DowntimeOccurrenceId, EmployeeId, EndTime, GoodQuantity (+22 more)

### Community 56 - "sales_test.dart"
Cohesion: 0.05
Nodes (39): body, client, credit, daysLeft, delivery, deliveryStatus, history, json (+31 more)

### Community 57 - ".Import_creates_templates_for_known_customers_and_products_and_keeps_existing_ones"
Cohesion: 0.19
Nodes (11): DateOnly, DateTimeOffset, IReadOnlyList, CertificateMeasureOut, CertificateOut, CertificateSummaryOut, CertificateTemplateOut, Fact (+3 more)

### Community 58 - "ImportReport"
Cohesion: 0.10
Nodes (22): Averages, Balances, Settings, ImportReport, Warnings, TableReport, File, Inserted (+14 more)

### Community 59 - "Sales.cs"
Cohesion: 0.06
Nodes (30): BillTo, Bts, Ebt, DeliveryCondition, Bk, Gbk, Nbk, DeliveryStatus (+22 more)

### Community 60 - "SalesOrder"
Cohesion: 0.05
Nodes (34): MVC mapping, IServiceCollection, Exception, HttpContext, IServiceCollection, ValueTask, SalesExceptionHandler, SalesOrder (+26 more)

### Community 61 - "SalesOrderLine"
Cohesion: 0.06
Nodes (32): SalesOrderLine, Condition, CustomerPartNumber, Description, DueDate, FeasibilityStudyId, FromStock, IcmsPercent (+24 more)

### Community 62 - "LegacyRow"
Cohesion: 0.24
Nodes (14): Action, CancellationToken, DbSet, Dictionary, Encoding, Func, List, Name (+6 more)

### Community 63 - "certificates.dart"
Cohesion: 0.03
Nodes (80): _addNote, _addRow, api, _banner, base, _body, build, _busy (+72 more)

### Community 64 - "PurchasingEndpoints"
Cohesion: 0.17
Nodes (14): CancellationToken, IQueryable, IResult, Task, WebApplication, PurchasingEndpoints, DateOnly, DateTimeOffset (+6 more)

### Community 65 - "Customer"
Cohesion: 0.05
Nodes (40): DataSource, Imported, Manual, Test, IHasSource, Source, List, Customer (+32 more)

### Community 66 - "StatelessWidget"
Cohesion: 0.10
Nodes (20): PrintButton, PeriodPicker, _ReportPage, ReportTable, LinesEditor, KpiTile, NextStepCard, ProgressMeter (+12 more)

### Community 67 - "String?"
Cohesion: 0.07
Nodes (31): AuditDetailDialog, AuditScreen, _AuditScreenState, build, createState, _entity, entry, session (+23 more)

### Community 68 - "PurchasingFixture"
Cohesion: 0.20
Nodes (9): IAsyncLifetime, Program, HttpClient, Task, WebApplicationFactory, PurchasingFixture, ConnectionString, Handler (+1 more)

### Community 69 - "StockLine"
Cohesion: 0.25
Nodes (15): List, AverageCostOut, LowStockRequisitionsIn, ReverseIn, StockSettingsIn, MaterialIn, MaterialOut, StockLine (+7 more)

### Community 70 - "dashboard_data.dart"
Cohesion: 0.03
Nodes (67): approved, blocked, blockedTotal, byKind, byShape, byStatus, closings, CommercialDashboard (+59 more)

### Community 71 - "Delivery"
Cohesion: 0.07
Nodes (29): List, Delivery, Address, AddressId, Carrier, CreatedAt, CreatedBy, DeliveredAt (+21 more)

### Community 72 - "dart:convert"
Cohesion: 0.07
Nodes (42): CheckboxListTile, main, _certificate, client, _json, log, main, pumpAndSettle (+34 more)

### Community 73 - "CustomerIn"
Cohesion: 0.18
Nodes (14): CustomerAddressIn, CustomerIn, ProductIn, ProductKind, Part, TubeShape, Circular, Rectangular (+6 more)

### Community 74 - "Inventory.cs"
Cohesion: 0.09
Nodes (22): InspectionIn, StockBalanceOut, LotStatus, Quarantine, Rejected, Released, ReservationStatus, Consumed (+14 more)

### Community 75 - "GoodsReceiptLine"
Cohesion: 0.12
Nodes (16): GoodsReceiptLine, DiscountPercent, GoodsReceipt, GoodsReceiptId, IcmsPercent, Id, IpiPercent, LotCode (+8 more)

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

### Community 80 - "ProductionModels.cs"
Cohesion: 0.13
Nodes (24): List, ProcessIn, DateOnly, IReadOnlyList, TimeOnly, AvailabilityLine, AvailabilityResult, BulkResult (+16 more)

### Community 81 - "ProductionService"
Cohesion: 0.19
Nodes (12): Sales flow, Shortages, ProductionOrder, CancellationToken, Func, IReadOnlyList, List, ProductionSettings (+4 more)

### Community 82 - "QualityCertificate"
Cohesion: 0.03
Nodes (72): ModelBuilder, DateOnly, DateTimeOffset, List, CertificateMeasure, Certificate, CertificateId, Found (+64 more)

### Community 83 - "Product"
Cohesion: 0.09
Nodes (22): Product, Blocked, Code, Customers, DiameterMm, DrawingRevision, HeightMm, Id (+14 more)

### Community 84 - "ProductionOrderOperation"
Cohesion: 0.08
Nodes (24): ProductionOrderOperation, Description, External, ExternalLeadDays, Id, Machine, MachineId, MeasureEnd (+16 more)

### Community 85 - "CLAUDE.md — MetaGest"
Cohesion: 0.10
Nodes (19): CLAUDE.md — MetaGest, Dev setup, Features built, Fiscal / NF, Flutter conventions, Gotchas, graphify, Migrations (+11 more)

### Community 86 - "CustomerAddress"
Cohesion: 0.10
Nodes (20): CustomerAddress, Buyer, City, CityIbgeCode, Complement, Customer, CustomerId, DefaultCfop (+12 more)

### Community 87 - "Ebt.Api.Infrastructure"
Cohesion: 0.13
Nodes (17): Ebt.Core.Certificates, Ebt.Api.Infrastructure, Ebt.Api.Endpoints, Ebt.Core.Purchasing, Ebt.Tests, ebt_api_infrastructure_crud, CertificateLinkIn, CertificatePolicies (+9 more)

### Community 88 - "NfeSchema"
Cohesion: 0.15
Nodes (11): Lazy, IReadOnlyList, Type, EmbeddedResolver, NfeSchema, Schemas NF-e (layout 4.00), Stream, Uri (+3 more)

### Community 89 - "CrudSpec"
Cohesion: 0.08
Nodes (22): IQueryCollection, CancellationToken, Func, Task, CodeNameIn, CodeNameOut, CancellationToken, Expression (+14 more)

### Community 90 - "labels.dart"
Cohesion: 0.06
Nodes (31): auditActions, auditEntities, bidStatuses, billToLabels, certificateStatuses, deliveryConditions, deliveryStatuses, feasibilityActions (+23 more)

### Community 91 - ".Conflict"
Cohesion: 0.18
Nodes (11): Delivery, CancellationToken, Func, Task, CancellationToken, DateOnly, Task, CancellationToken (+3 more)

### Community 92 - "ApiFixture"
Cohesion: 0.12
Nodes (22): WorkCenterIn, ChangePasswordRequest, CreateUserRequest, LoginRequest, LoginResponse, RefreshRequest, UpdateUserRequest, UserDto (+14 more)

### Community 93 - "SteelLot"
Cohesion: 0.11
Nodes (19): DateTimeOffset, List, SteelLot, CreatedAt, CreatedBy, Id, LotCode, Notes (+11 more)

### Community 94 - "FiscalService"
Cohesion: 0.15
Nodes (11): NfeParty, CancellationToken, DateTimeOffset, DbContextOptions, FiscalSettings, Func, IReadOnlyList, List (+3 more)

### Community 95 - ".Has"
Cohesion: 0.19
Nodes (9): FiscalSettings, WebApplication, FiscalEndpoints, MonthlyPriceOut, TaxRuleIn, TaxRuleOut, ClaimsPrincipal, Dictionary (+1 more)

### Community 96 - "modules.dart"
Cohesion: 0.05
Nodes (38): ModuleInfo, Navigate, build, _commercial, _content, createState, _data, dispose (+30 more)

### Community 97 - "QuoteLine"
Cohesion: 0.07
Nodes (29): DateOnly, PriceListEntry, Customer, CustomerId, IcmsPercent, Id, IpiPercent, Product (+21 more)

### Community 98 - "FiscalDocument"
Cohesion: 0.04
Nodes (59): CfopIn, CfopOut, DateOnly, List, FiscalDocument, AccessKey, AdditionalInfo, CancelledAt (+51 more)

### Community 99 - "print_panel.dart"
Cohesion: 0.10
Nodes (19): build, customerOrderPdf, detail, doc, docs, id, label, name (+11 more)

### Community 100 - "AppUser"
Cohesion: 0.07
Nodes (31): IPasswordHasher, PasswordHasher, CancellationToken, DateTimeOffset, IConfiguration, ILogger, Task, TimeSpan (+23 more)

### Community 101 - "customers.dart"
Cohesion: 0.05
Nodes (42): _active, _addressFields, _addressLine, body, build, _c, canEdit, company (+34 more)

### Community 102 - "SupplierAddress"
Cohesion: 0.12
Nodes (16): SupplierAddress, City, CityIbgeCode, District, Document, Email, Id, LegacyCode (+8 more)

### Community 103 - "AverageCost"
Cohesion: 0.12
Nodes (16): AverageCost, Average, AverageGross, Id, Imported, Material, MaterialId, MonthAverage (+8 more)

### Community 104 - "reports.dart"
Cohesion: 0.05
Nodes (43): _asc, ascending, BillingSummaryScreen, _BillingSummaryScreenState, build, _cells, _code, _companies (+35 more)

### Community 105 - "SourceFlagger"
Cohesion: 0.20
Nodes (12): ISourceFlagger, CancellationToken, Dictionary, Func, IQueryable, List, Task, DataSourceCount (+4 more)

### Community 106 - "ProductionEndpoints.cs"
Cohesion: 0.07
Nodes (32): DateOnly, Expression, Func, IReadOnlyDictionary, IReadOnlyList, IResult, ProductionSettings, Task (+24 more)

### Community 107 - "ICurrentUser"
Cohesion: 0.40
Nodes (5): IHttpContextAccessor, HttpCurrentUser, Name, ICurrentUser, Name

### Community 108 - "steel.dart"
Cohesion: 0.05
Nodes (39): api, base, _body, build, _create, createState, _deleteChild, _deleteLot (+31 more)

### Community 109 - "viability.dart"
Cohesion: 0.05
Nodes (38): api, base, _body, build, context, createState, _delete, _edit (+30 more)

### Community 110 - "alerts.dart"
Cohesion: 0.13
Nodes (14): AlertBell, AlertCenter, AlertInfo, build, center, count, filter, icon (+6 more)

### Community 111 - "OutsideShipment"
Cohesion: 0.13
Nodes (15): PCP + Apontamento, OutsideShipment, CreatedBy, Id, InvoiceNumber, Notes, Operation, OperationId (+7 more)

### Community 112 - "Production.cs"
Cohesion: 0.12
Nodes (17): TimeOnly, OccurrenceKind, Downtime, Scrap, ProductionOccurrence, Code, Description, Id (+9 more)

### Community 114 - "StockBalance"
Cohesion: 0.06
Nodes (33): StockBalance, Id, Location, LocationId, Lot, LotId, Material, MaterialId (+25 more)

### Community 115 - "SefazSpClient"
Cohesion: 0.10
Nodes (31): Body, HttpMessageHandler, HttpRequestMessage, InlineData, IConfiguration, IServiceCollection, HttpClient, X509Certificate2 (+23 more)

### Community 116 - "IExceptionHandler"
Cohesion: 0.11
Nodes (17): IExceptionHandler, Exception, HttpContext, ValueTask, FiscalExceptionHandler, CancellationToken, Exception, HttpContext (+9 more)

### Community 117 - "start.ps1"
Cohesion: 0.19
Nodes (4): Fail(), Find-Port(), Test-Bindable(), Test-Port()

### Community 118 - "MetaGest — Engenharia, Estoque, Suprimentos, PCP"
Cohesion: 0.13
Nodes (14): Auth and roles, Endpoints, Estoque, Import legacy DBFs, Knowledge graph (Graphify), Layout (MVC mapping), MetaGest — Engenharia, Estoque, Suprimentos, PCP, Quick start (Windows) (+6 more)

### Community 119 - "api_integration_test.dart"
Cohesion: 0.18
Nodes (10): ApiClient, ApiException, api, login, main, password, skip, url (+2 more)

### Community 120 - "fiscal.dart"
Cohesion: 0.06
Nodes (34): api, base, _body, build, _cancel, createState, _d, _edit (+26 more)

### Community 121 - "SalesService"
Cohesion: 0.14
Nodes (17): Icms, Ipi, ResolvedLine, Quote, QuoteTotals, DateOnly, IEnumerable, IReadOnlyList (+9 more)

### Community 122 - ".ProgressAsync"
Cohesion: 0.20
Nodes (11): ItemConsumption, MaterialLineState, ProductionException, Field, Status, CancellationToken, Dictionary, IEnumerable (+3 more)

### Community 123 - ".Delivery_records_lot_invoiced_value_and_balances"
Cohesion: 0.30
Nodes (8): Setup, FeasibilityIn, FeasibilityNoteIn, DateOnly, Fact, HttpClient, Task, ViabilitySteelTests

### Community 124 - "ImportOptions"
Cohesion: 0.18
Nodes (11): IReadOnlyList, ImportOptions, CodePage, DefaultNcm, Directory, DryRun, Steps, CancellationToken (+3 more)

### Community 125 - "QuoteExpiryService"
Cohesion: 0.21
Nodes (9): Request lifecycle, BackgroundService, IServiceScopeFactory, PeriodicTimer, CancellationToken, ILogger, Task, TimeSpan (+1 more)

### Community 126 - "../entities.dart"
Cohesion: 0.04
Nodes (57): ../api.dart, ApiClient get, ChangeNotifier, api, build, createState, _draft, _list (+49 more)

### Community 127 - "StockMovement"
Cohesion: 0.11
Nodes (18): StockMovement, Date, Document, DocumentId, IcmsRate, Id, Location, LocationId (+10 more)

### Community 129 - "CertificateService"
Cohesion: 0.12
Nodes (21): Backend conventions, CancellationToken, ClaimsPrincipal, IServiceCollection, List, Task, WebApplication, CertificateEndpoints (+13 more)

### Community 131 - "Employee"
Cohesion: 0.18
Nodes (11): Employee, Active, Code, Function, Id, Name, Nickname, Shift (+3 more)

### Community 133 - "MetaGest — Flutter client"
Cohesion: 0.20
Nodes (9): Build, Estoque, MetaGest — Flutter client, Painel, Roles, Run, Screens, Suprimentos (+1 more)

### Community 136 - "SefazEnvironment"
Cohesion: 0.08
Nodes (34): Audit findings (coupling and bottlenecks), Data flow of the sales chain, Knowledge graph, MetaGest architecture, Permissions, Why there is no MVC folder move, ConcurrentDictionary, SefazEnvironment (+26 more)

### Community 137 - "SlitterJob"
Cohesion: 0.13
Nodes (15): SlitterJob, FinishedKg, Id, Lot, LotId, Notes, Processor, ProcessorId (+7 more)

### Community 138 - "RowVersionFilter"
Cohesion: 0.24
Nodes (7): EndpointFilterDelegate, EndpointFilterInvocationContext, IEndpointFilter, CancellationToken, Task, ValueTask, RowVersionFilter

### Community 139 - "FiscalDocumentLine"
Cohesion: 0.08
Nodes (35): FiscalDocumentLine, Code, CofinsCst, CofinsPercent, CofinsValue, Description, Document, DocumentId (+27 more)

### Community 140 - "Revision"
Cohesion: 0.13
Nodes (15): RevisionIn, DateTimeOffset, Revision, Code, CreatedAt, Id, Kind, Product (+7 more)

### Community 141 - "FeasibilityStudy"
Cohesion: 0.06
Nodes (31): DateTimeOffset, FeasibilityStudy, Characteristics, CommercialAt, CommercialBy, CommercialNote, CreatedAt, CreatedBy (+23 more)

### Community 142 - "QuoteStatus"
Cohesion: 0.18
Nodes (11): QuoteStatus, Accepted, Approved, Cancelled, Converted, Draft, Expired, PendingApproval (+3 more)

### Community 143 - "report_doc.dart"
Cohesion: 0.08
Nodes (25): build, cells, enabled, fileBase, filters, flex, headers, kind (+17 more)

### Community 144 - "UserRole"
Cohesion: 0.12
Nodes (15): AuthorizationOptions, IReadOnlyDictionary, Access, UserRole, Admin, Engineering, Production, Purchasing (+7 more)

### Community 145 - ".MapInventory"
Cohesion: 0.07
Nodes (35): CancellationToken, ClaimsPrincipal, DateOnly, DateTimeOffset, Expression, IReadOnlyList, StockSettings, Task (+27 more)

### Community 146 - ".ConfigureSales"
Cohesion: 0.10
Nodes (18): PropertyBuilder, FiscalSettings, ModelBuilder, ModelBuilder, SalesSettings, ModelBuilder, DeliveryLine, Delivery (+10 more)

### Community 147 - "deliveries.dart"
Cohesion: 0.04
Nodes (59): bool?, certificates.dart, api, base, build, _cancel, _certificateGate, _certified (+51 more)

### Community 148 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.09
Nodes (19): certificate, main, issuer, key, main, nf, ensureVisible, module (+11 more)

### Community 149 - "StockException"
Cohesion: 0.29
Nodes (7): StockErrorKind, Conflict, Invalid, NotFound, StockException, Field, Kind

### Community 150 - "Auth.cs"
Cohesion: 0.22
Nodes (9): microsoft_aspnetcore_authentication_jwtbearer, microsoft_aspnetcore_httpoverrides, microsoft_aspnetcore_identity, microsoft_identitymodel_tokens, microsoft_openapi, Policies, system_identitymodel_tokens_jwt, system_security_cryptography (+1 more)

### Community 151 - "SearchEndpoints.cs"
Cohesion: 0.23
Nodes (11): Key, microsoft_aspnetcore_authorization, Policy, CancellationToken, IReadOnlyList, Task, WebApplication, SearchEndpoints (+3 more)

### Community 152 - "certificate_doc.dart"
Cohesion: 0.08
Nodes (23): address, _b, buildCertificatePdf, cancelled, _cell, company, _dash, doc (+15 more)

### Community 153 - "Clock"
Cohesion: 0.31
Nodes (4): DateOnly, DateTimeOffset, Clock, TimeZoneInfo

### Community 154 - ".InTransactionAsync"
Cohesion: 0.33
Nodes (4): CancellationToken, Func, Task, DbTransactions

### Community 155 - ".Safe"
Cohesion: 0.50
Nodes (3): GeneratedRegex, Regex, SqlIdentifier

### Community 156 - ".MapReports"
Cohesion: 0.17
Nodes (18): From, CancellationToken, DateOnly, IReadOnlyList, List, Task, WebApplication, BillingRow (+10 more)

### Community 158 - "LegacySpecImporter.cs"
Cohesion: 0.24
Nodes (10): CancellationToken, IEnumerable, IReadOnlyList, JsonSerializerOptions, List, Task, LegacySpec, LegacySpecImporter (+2 more)

### Community 159 - "Cfop"
Cohesion: 0.12
Nodes (16): Cfop, Active, Code, CofinsCst, DefaultCofinsPercent, DefaultPisPercent, Description, GeneratesInstallments (+8 more)

### Community 160 - "ProductionOrderMaterial"
Cohesion: 0.14
Nodes (14): ProductionOrderMaterial, ComponentProduct, ComponentProductId, Id, Material, MaterialId, OperationSequence, Order (+6 more)

### Community 161 - "admin_screens_test.dart"
Cohesion: 0.09
Nodes (20): client, json, log, main, open, pumpAndSettle, pumpWidget, session (+12 more)

### Community 162 - "BomService"
Cohesion: 0.18
Nodes (14): Exception, Seq, Item, CancellationToken, Dictionary, IReadOnlyList, List, Task (+6 more)

### Community 165 - ".ResetAsync"
Cohesion: 0.23
Nodes (13): DbConnection, Fk, CancellationToken, Dictionary, HashSet, IEnumerable, IReadOnlyCollection, IReadOnlyList (+5 more)

### Community 166 - "StockDocument"
Cohesion: 0.12
Nodes (17): List, StockDocument, CreatedAt, CreatedBy, Customer, CustomerId, Date, Id (+9 more)

### Community 167 - ".ScheduleTreeAsync"
Cohesion: 0.32
Nodes (6): IReadOnlySet, DateOnly, IReadOnlyList, List, WorkCalendar, HoursPerDay

### Community 168 - "PurchasingFixture.cs"
Cohesion: 0.10
Nodes (18): Ebt.Core.Maintenance, ICollectionFixture, microsoft_aspnetcore_diagnostics, microsoft_aspnetcore_hosting, microsoft_aspnetcore_mvc_testing, microsoft_aspnetcore_testhost, microsoft_entityframeworkcore_changetracking, microsoft_entityframeworkcore_diagnostics (+10 more)

### Community 171 - "discard_guard.dart"
Cohesion: 0.18
Nodes (9): build, child, confirmDiscard, DiscardGuard, build, child, maxWidth, PageColumn (+1 more)

### Community 173 - "FiscalSettings"
Cohesion: 0.10
Nodes (21): FiscalSettings, CancelWindowHours, City, CityIbgeCode, Cnpj, CompanyName, Complement, District (+13 more)

### Community 174 - "print_gate.dart"
Cohesion: 0.15
Nodes (12): choice, continueLabel, isDone, _key, mark, printGate, PrintLog, savePdf (+4 more)

### Community 175 - "AuditInterceptor"
Cohesion: 0.18
Nodes (12): _Entry, DbContextEventData, EntityEntry, InterceptionResult, SaveChangesInterceptor, Dictionary, HashSet, JsonSerializerOptions (+4 more)

### Community 176 - "viability_steel_test.dart"
Cohesion: 0.11
Nodes (17): body, client, Fake, job, json, last, log, lot (+9 more)

### Community 177 - "SalesOrderStatus"
Cohesion: 0.15
Nodes (14): ProductId, SalesOrderStatus, Cancelled, Created, Delivered, PartiallyShipped, Released, CancellationToken (+6 more)

### Community 178 - "user_settings.dart"
Cohesion: 0.07
Nodes (27): _again, build, _busy, _ChangePassword, _ChangePasswordState, clear, _clearCache, clearLocalCache (+19 more)

### Community 179 - ".MapViability"
Cohesion: 0.23
Nodes (9): ClaimsPrincipal, WebApplication, ViabilityEndpoints, ViabilityPolicies, FeasibilityStudy, SignoffArea, Commercial, Production (+1 more)

### Community 180 - ".MapMasterData"
Cohesion: 0.23
Nodes (8): Dictionary, WebApplication, MasterDataEndpoints, SubgroupOut, SupplierAddressIn, SupplierAddressOut, ToolOut, WorkCenterOut

### Community 181 - ".Steel_lot_slitter_and_usage_balance"
Cohesion: 0.31
Nodes (10): DateOnly, DateTimeOffset, SlitterJobIn, SlitterJobOut, SteelLotIn, SteelLotOut, SteelPolicies, SteelUsageIn (+2 more)

### Community 182 - "FiscalInutilization"
Cohesion: 0.15
Nodes (13): DateTimeOffset, FiscalInutilization, CreatedAt, CreatedBy, Environment, FromNumber, Id, Protocol (+5 more)

### Community 183 - "data_reset.dart"
Cohesion: 0.08
Nodes (25): _body, build, _busy, _confirm, createState, dataResetConfirmWord, _DataResetDialog, _DataResetDialogState (+17 more)

### Community 184 - "AuditEntry"
Cohesion: 0.22
Nodes (9): DateTimeOffset, AuditEntry, Action, At, Changes, Entity, EntityId, Id (+1 more)

### Community 185 - "login.dart"
Cohesion: 0.09
Nodes (22): build, _busy, _capsLock, _clearError, createState, dispose, _error, _failures (+14 more)

### Community 186 - "PurchaseOrderLine"
Cohesion: 0.05
Nodes (39): PurchasingSettings, ModelBuilder, DateOnly, PayableInstallment, Amount, DueDate, GoodsReceipt, GoodsReceiptId (+31 more)

### Community 187 - "fiscal_test.dart"
Cohesion: 0.17
Nodes (11): client, json, log, main, nf, pump, pumpAndSettle, pumpWidget (+3 more)

### Community 188 - "SteelUsage"
Cohesion: 0.18
Nodes (10): DateOnly, SteelUsage, Date, Id, Kg, LaborCost, Lot, LotId (+2 more)

### Community 189 - "Page"
Cohesion: 0.10
Nodes (43): SaleSetup, DateTimeOffset, IReadOnlyList, CancelInvoiceIn, FiscalDocumentOut, FiscalSettingsDto, InutilizationOut, InutilizeIn (+35 more)

### Community 190 - ".ConfigureProduction"
Cohesion: 0.20
Nodes (9): ModelBuilder, ProductionSettings, DateOnly, Holiday, Date, Id, Name, Employee (+1 more)

### Community 191 - "FeasibilityOut"
Cohesion: 0.17
Nodes (13): CancellationToken, DateTimeOffset, IReadOnlyList, Task, FeasibilityOrderOut, FeasibilityOut, FeasibilitySummaryOut, SignoffOut (+5 more)

### Community 192 - ".Production_dashboard_splits_late_orders_into_recent_and_legacy"
Cohesion: 0.36
Nodes (5): DateOnly, Fact, JsonElement, Task, DashboardTests

### Community 193 - "package:flutter/material.dart"
Cohesion: 0.06
Nodes (35): appTheme, build, cs, EbtApp, main, restore, session, main (+27 more)

### Community 198 - ".FlushInserts"
Cohesion: 0.24
Nodes (6): DbContextErrorEventData, SaveChangesCompletedEventData, CancellationToken, DbContext, Task, ValueTask

### Community 199 - "MetaGest operations"
Cohesion: 0.22
Nodes (8): Backups, Behind a reverse proxy, Logs, MetaGest operations, Nightly backup (Windows Task Scheduler), Restart behavior, Restore, Secrets to rotate before real use

### Community 200 - "OverrunRelease"
Cohesion: 0.22
Nodes (9): DateTimeOffset, OverrunRelease, Id, Justification, Operation, OperationId, Quantity, ReleasedAt (+1 more)

### Community 201 - ".Build"
Cohesion: 0.31
Nodes (4): DateTimeOffset, IReadOnlyDictionary, NfeKey, NfeKeyTests

### Community 202 - ".ListAsync"
Cohesion: 0.29
Nodes (6): CancellationToken, IReadOnlyCollection, List, Task, LowStock, LowStockRow

### Community 203 - "JwtOptions"
Cohesion: 0.29
Nodes (7): JwtOptions, Audience, ClockSkewSeconds, ExpiresMinutes, Issuer, RefreshDays, SigningKey

### Community 204 - ".Search_returns_grouped_hits_capped_by_take"
Cohesion: 0.52
Nodes (3): Fact, Task, SearchTests

### Community 205 - ".Load"
Cohesion: 0.33
Nodes (5): CancellationToken, DateOnly, Task, FiscalInstallmentOut, FiscalLineOut

### Community 206 - ".MapSteel"
Cohesion: 0.33
Nodes (4): Expression, IServiceCollection, WebApplication, SteelEndpoints

### Community 207 - "DataResetOut"
Cohesion: 0.40
Nodes (4): IReadOnlyList, WebApplication, DataResetOut, ResetTableCount

### Community 208 - ".MapAudit"
Cohesion: 0.40
Nodes (4): DateTimeOffset, WebApplication, AuditEndpoints, AuditOut

### Community 209 - "ResetScope"
Cohesion: 0.40
Nodes (5): ResetScope, Production, Purchasing, Sales, Stock

### Community 210 - "SalesException"
Cohesion: 0.67
Nodes (3): SalesException, Field, Status

### Community 340 - "workdays.dart"
Cohesion: 0.10
Nodes (20): a, addWorkDays, d, day, _easter, goodFriday, h, _holidayCache (+12 more)

### Community 343 - "StatefulWidget"
Cohesion: 0.05
Nodes (45): _CustomerAddresses, build, createState, initialStatus, inspect, _list, LotsView, _LotsViewState (+37 more)

### Community 346 - "Product"
Cohesion: 0.06
Nodes (35): Customer, Product, ProductCustomer, Active, Customer, CustomerDescription, CustomerId, CustomerPartNumber (+27 more)

### Community 348 - "BomItem"
Cohesion: 0.18
Nodes (11): BomItem, ComponentProduct, ComponentProductId, Factor, Id, Material, MaterialId, Quantity (+3 more)

### Community 349 - ".Add"
Cohesion: 0.31
Nodes (4): DateOnly, WorkDays, Fact, WorkDaysTests

### Community 356 - "SalesModels.cs"
Cohesion: 0.10
Nodes (25): FreightTerms, Cif, CustomerPickup, Fob, OrderOrigin, Email, Fax, System (+17 more)

## Knowledge Gaps
- **3554 isolated node(s):** `status`, `message`, `fieldErrors`, `items`, `total` (+3549 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 4026 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **41 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AuditInterceptor` connect `AuditInterceptor` to `PurchasingFixture.cs`, `ICurrentUser`, `.FlushInserts`?**
  _High betweenness centrality (0.281) - this node is a cross-community bridge._
- **Why does `_Entry` connect `AuditInterceptor` to `command_palette.dart`?**
  _High betweenness centrality (0.280) - this node is a cross-community bridge._
- **Why does `EbtDbContext` connect `EbtDbContext` to `CertificateService`, `.NewDb`, `StockLot`, `SefazEnvironment`, `SlitterJob`, `RowVersionFilter`, `FiscalDocumentLine`, `Revision`, `StockService`, `PurchasingService`, `.MapInventory`, `.ConfigureSales`, `GoodsReceipt`, `SearchEndpoints.cs`, `.InTransactionAsync`, `.MapReports`, `ProductionImport`, `LegacySpecImporter.cs`, `Cfop`, `ProductionOrderMaterial`, `BomService`, `.ResetAsync`, `StockDocument`, `.MapQuotes`, `Material`, `PurchaseRequisition`, `microsoft_entityframeworkcore`, `RoutingOperation`, `SalesOrderStatus`, `.MapViability`, `.MapProducts`, `FiscalInutilization`, `ProductionReport`, `AuditEntry`, `PurchasingImport`, `PurchaseOrderLine`, `ImportReport`, `SalesOrder`, `SalesOrderLine`, `.ConfigureProduction`, `FeasibilityOut`, `PurchasingEndpoints`, `Customer`, `SteelUsage`, `LegacyRow`, `PurchasingFixture`, `OverrunRelease`, `.ListAsync`, `GoodsReceiptLine`, `GoodsReceived`, `.Load`, `SalesEvent`, `ProductionService`, `QualityCertificate`, `ProductionOrderOperation`, `CustomerAddress`, `CrudSpec`, `Product`, `.Conflict`, `.ConfigureViability`, `BomItem`, `SteelLot`, `FiscalService`, `QuoteLine`, `FiscalDocument`, `AppUser`, `SupplierAddress`, `AverageCost`, `SourceFlagger`, `ProductionEndpoints.cs`, `Production.cs`, `StockBalance`, `MetaGest — Engenharia, Estoque, Suprimentos, PCP`, `SalesService`, `ImportOptions`, `StockMovement`?**
  _High betweenness centrality (0.230) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `EbtDbContext` (e.g. with `Audit findings (coupling and bottlenecks)` and `MVC mapping`) actually correct?**
  _`EbtDbContext` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `SalesService` (e.g. with `Audit findings (coupling and bottlenecks)` and `MVC mapping`) actually correct?**
  _`SalesService` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `status`, `message`, `fieldErrors` to the rest of the system?**
  _3554 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `entities.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.023255813953488372 - nodes in this community are weakly interconnected._