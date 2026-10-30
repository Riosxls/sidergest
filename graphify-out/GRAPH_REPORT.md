# Graph Report - sidergest  (2026-10-30)

## Corpus Check
- 195 files · ~206,904 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 14 file(s) not represented in the graph (top: (none) 7, .ttf 2, .bat 2)

## Summary
- 5666 nodes · 11384 edges · 230 communities (190 shown, 40 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 955 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7ea84a89`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- entities.dart
- EbtDbContext
- shell.dart
- sales_quotes.dart
- StockImportOptions
- StockReservation
- dashboard.dart
- production_orders.dart
- PurchasingEndpoints.cs
- record_list.dart
- sales_common.dart
- stock_documents.dart
- entity_form.dart
- StockItem
- PurchasingService
- Ebt.Tests
- command_palette.dart
- receipts.dart
- orders.dart
- quotations.dart
- package:flutter/material.dart
- sales_orders.dart
- Quotation
- print_docs.dart
- production_floor.dart
- pipeline.dart
- .Arrange
- PurchaseOrderLine
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
- microsoft_entityframeworkcore
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
- .For
- Sales.cs
- SalesOrder
- SalesOrderLine
- Importer
- certificates.dart
- PurchasingEndpoints
- Customer
- StatelessWidget
- StockService
- PurchasingFixture
- StockLine
- dashboard_data.dart
- Delivery
- ux_test.dart
- CustomerOut
- .CreateOrderCoreAsync
- GoodsReceipt
- SiderGest — Engenharia, Estoque, Suprimentos, PCP
- SalesEvent
- production_test.dart
- http
- ProductionModels.cs
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
- .InTransaction
- .AdminAsync
- SteelLot
- FiscalService
- .Has
- modules.dart
- QuoteLine
- FiscalDocument
- ProductionSettings
- AppUser
- customers.dart
- SupplierAddress
- AverageCost
- reports.dart
- FiscalInstallment
- Backend conventions
- Audit.cs
- steel.dart
- viability.dart
- Ebt.Core.Entities
- Supplier
- ProductionOrderMaterial
- dart_project
- StockBalance
- SefazOptions
- FiscalDocumentOut
- start.ps1
- .Describe
- api_integration_test.dart
- fiscal.dart
- SalesService
- .ProgressAsync
- PriceListEntry
- ImportReport
- QuoteExpiryService
- ../api.dart
- StockMovement
- ebt_core_certificates
- CertificateService
- ebt_core_fiscal
- Employee
- ebt_core_inventory
- Screens
- ebt_core_production
- ebt_core_viability
- SefazSpClient
- main.dart
- RowVersionFilter
- FiscalDocumentLine
- RevisionKind
- FeasibilityStudy
- QuoteStatus
- report_doc.dart
- UserRole
- MovementType
- .ConfigurePurchasing
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
- DeliveryLine
- Cfop
- NfeSigner
- admin_screens_test.dart
- .ExplodeAsync
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
- .MapInventory
- AuditInterceptor
- viability_steel_test.dart
- SalesOrderStatus
- user_settings.dart
- .MapViability
- MasterDataEndpoints.cs
- .Steel_lot_slitter_and_usage_balance
- NfeXml
- data_reset.dart
- AuditEntry
- login.dart
- SupplierMaterial
- .TryHandleAsync
- LostReason
- .Sale_nf_needs_monthly_price_is_recorded_only_after_authorization_and_can_be_cancelled
- SalesSettings
- FeasibilityOut
- TaxRule
- package:flutter_test/flutter_test.dart
- _CustomPrazoDialog
- EntityFormDialog
- LookupField
- LookupPicker
- .FlushInserts
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
- Customer
- Product
- .Add
- SalesLineInput
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
7. `SalesOrder` - 52 edges
8. `QualityCertificate` - 52 edges
9. `Ebt.Core.Data` - 52 edges
10. `Material` - 50 edges

## Surprising Connections (you probably didn't know these)
- `PCP + Apontamento` --references--> `OutsideShipment`  [INFERRED]
  README.md → src/Ebt.Core/Entities/Production.cs
- `Estoque` --references--> `StockService`  [INFERRED]
  README.md → src/Ebt.Core/Inventory/StockService.Costing.cs
- `Fiscal / NF` --references--> `StubSefazClient`  [INFERRED]
  CLAUDE.md → src/Ebt.Core/Fiscal/StubSefazClient.cs
- `Backend conventions` --references--> `EbtDbContext`  [INFERRED]
  CLAUDE.md → src/Ebt.Core/Data/EbtDbContext.Certificates.cs
- `Features built` --references--> `SefazSpClient`  [INFERRED]
  CLAUDE.md → src/Ebt.Core/Fiscal/SefazSpClient.cs

## Import Cycles
- None detected.

## Communities (230 total, 40 thin omitted)

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
Nodes (123): _accept, _acceptedStep, _act, _addresses, _addressId, api, _applyDefaultTerm, _approvalBanner (+115 more)

### Community 4 - "StockImportOptions"
Cohesion: 0.08
Nodes (22): IDisposable, DateOnly, StockImportOptions, CodePage, Directory, DryRun, OpeningDate, OwnLocation (+14 more)

### Community 5 - "StockReservation"
Cohesion: 0.06
Nodes (33): DateOnly, DateTimeOffset, ReservationStatus, Consumed, Open, Released, StockClosing, ClosedAt (+25 more)

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
Cohesion: 0.04
Nodes (54): LookupSpec, api, _applyFill, askCustomPrazo, _body, build, _busy, _clientErrors (+46 more)

### Community 13 - "StockItem"
Cohesion: 0.17
Nodes (12): LotId, CancellationToken, DateOnly, Func, IEnumerable, IReadOnlyList, List, Qty (+4 more)

### Community 14 - "PurchasingService"
Cohesion: 0.16
Nodes (11): PurchaseOrder, CancellationToken, GeneratedRegex, IEnumerable, List, Regex, Task, PurchasingException (+3 more)

### Community 15 - "Ebt.Tests"
Cohesion: 0.14
Nodes (9): Ebt.DbfImport, Ebt.Core.Services, Ebt.Tests, dbfdatareader, Text, system_globalization, system_text, system_xml_linq (+1 more)

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

### Community 20 - "package:flutter/material.dart"
Cohesion: 0.05
Nodes (41): ChangeNotifier, AuditDetailDialog, AuditScreen, _AuditScreenState, build, createState, _entity, entry (+33 more)

### Community 21 - "sales_orders.dart"
Cohesion: 0.04
Nodes (50): api, base, _billTo, _body, build, _cancel, _certified, _certs (+42 more)

### Community 22 - "Quotation"
Cohesion: 0.05
Nodes (39): DateTimeOffset, BidStatus, Approved, Pending, Rejected, PurchasingSettings, AllowEarlyReceipt, EarlyReceiptGraceDays (+31 more)

### Community 23 - "print_docs.dart"
Cohesion: 0.02
Nodes (85): _b, blankRows, _blue, box, _build, buildProductionOrderPdf, buildQuotePdf, buildSalesOrderPdf (+77 more)

### Community 24 - "production_floor.dart"
Cohesion: 0.05
Nodes (40): build, _color, context, createState, cs, _fetch, _from, _grid (+32 more)

### Community 25 - "pipeline.dart"
Cohesion: 0.05
Nodes (40): actions, amount, at, badge, build, c, caption, _Chevron (+32 more)

### Community 26 - ".Arrange"
Cohesion: 0.19
Nodes (17): IServiceScope, IReadOnlyList, List, DataResetIn, DataResetOut, LostReasonOut, PaymentTermIn, QuoteOut (+9 more)

### Community 27 - "PurchaseOrderLine"
Cohesion: 0.04
Nodes (51): List, PurchaseOrder, ClosedAt, ClosedBy, CloseReason, Id, IssuedAt, IssuedBy (+43 more)

### Community 28 - "ProductionImport"
Cohesion: 0.16
Nodes (15): ProductionOrderKind, Internal, Standard, CancellationToken, DateOnly, DateTimeOffset, Dictionary, Encoding (+7 more)

### Community 29 - "State"
Cohesion: 0.06
Nodes (41): bool get, _CustomerAddressesState, _add, api, base, build, canWrite, createState (+33 more)

### Community 30 - "StockLot"
Cohesion: 0.12
Nodes (16): StockLot, Code, HeatNumber, Id, InspectedAt, InspectedBy, InspectionNote, InvoiceNumber (+8 more)

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
Cohesion: 0.10
Nodes (36): DateOnly, DateTimeOffset, IReadOnlyList, ConfirmDeliveryIn, DeliveryLineOut, DeliveryOut, DeliverySummaryOut, PipelineCard (+28 more)

### Community 37 - "dash.dart"
Cohesion: 0.08
Nodes (24): alert, BarPanel, build, child, dashCardShape, DashGrid, DashNotice, DashTile (+16 more)

### Community 38 - "requisitions.dart"
Cohesion: 0.10
Nodes (20): act, api, base, build, _cancellable, createState, initialStatus, initState (+12 more)

### Community 39 - ".MapQuotes"
Cohesion: 0.10
Nodes (24): Icms, Id, Ipi, CancellationToken, ClaimsPrincipal, Dictionary, Expression, Func (+16 more)

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

### Community 45 - "microsoft_entityframeworkcore"
Cohesion: 0.14
Nodes (7): Ebt.Core.Certificates, Ebt.Core.Purchasing, Ebt.Core.Data, microsoft_entityframeworkcore, microsoft_entityframeworkcore_design, microsoft_entityframeworkcore_metadata_builders, system_text_regularexpressions

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
Nodes (44): CancelInvoiceIn, StockDocumentSummary, MachineIn, MachineOut, MaterialOut, SupplierIn, SupplierOut, WorkCenterOut (+36 more)

### Community 50 - "nf_doc.dart"
Cohesion: 0.03
Nodes (76): a, ad, addresses, askNfFiscal, base, buildOutsideNfPdf, buildSaleNfPdf, _cell (+68 more)

### Community 51 - "api.dart"
Cohesion: 0.04
Nodes (45): Client, _baseUrl, _call, cap, clearVersions, delete, describeError, _doRefresh (+37 more)

### Community 52 - ".MapProducts"
Cohesion: 0.18
Nodes (12): CancellationToken, Dictionary, Expression, IReadOnlyList, IResult, List, Task, WebApplication (+4 more)

### Community 53 - "ProductionOrderStatus"
Cohesion: 0.25
Nodes (8): ProductionOrderStatus, Cancelled, Closed, Created, Finished, InProduction, Released, Stopped

### Community 54 - "PurchasingImport"
Cohesion: 0.20
Nodes (11): QuotationItem, CancellationToken, DateTimeOffset, Encoding, HashSet, List, Name, Preferred (+3 more)

### Community 55 - "ProductionReport"
Cohesion: 0.04
Nodes (49): ModelBuilder, ProductionSettings, OutsideShipment, DateOnly, DateTimeOffset, Holiday, Date, Id (+41 more)

### Community 56 - "sales_test.dart"
Cohesion: 0.06
Nodes (35): body, client, credit, daysLeft, delivery, deliveryStatus, history, json (+27 more)

### Community 57 - "CertificateMeasure"
Cohesion: 0.08
Nodes (26): CancellationToken, DateOnly, DateTimeOffset, IReadOnlyList, Task, CertificateMeasureOut, CertificateOut, CertificateSummaryOut (+18 more)

### Community 58 - ".For"
Cohesion: 0.19
Nodes (11): Averages, Balances, Settings, Encoding, IEnumerable, LegacyDbf, CancellationToken, Encoding (+3 more)

### Community 59 - "Sales.cs"
Cohesion: 0.10
Nodes (19): BillTo, Bts, Ebt, DeliveryCondition, Bk, Gbk, Nbk, DeliveryStatus (+11 more)

### Community 60 - "SalesOrder"
Cohesion: 0.08
Nodes (26): SalesOrder, Address, AddressId, CertificateWaived, Company, CreatedAt, CreatedBy, Customer (+18 more)

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

### Community 67 - "StockService"
Cohesion: 0.15
Nodes (15): L, M, P, CancellationToken, DateOnly, List, Task, BeforeRow (+7 more)

### Community 68 - "PurchasingFixture"
Cohesion: 0.13
Nodes (13): IAsyncLifetime, Program, HttpClient, Task, WebApplicationFactory, PurchasingFixture, ConnectionString, Handler (+5 more)

### Community 69 - "StockLine"
Cohesion: 0.12
Nodes (35): DateOnly, DateTimeOffset, IReadOnlyList, AvailabilityOut, AverageCostOut, ClosingOut, InspectionIn, LocationQuantity (+27 more)

### Community 70 - "dashboard_data.dart"
Cohesion: 0.04
Nodes (50): all, approved, blocked, closings, CommercialDashboard, count, countBy, counts (+42 more)

### Community 71 - "Delivery"
Cohesion: 0.07
Nodes (28): List, Delivery, Address, AddressId, Carrier, CreatedAt, CreatedBy, DeliveredAt (+20 more)

### Community 72 - "ux_test.dart"
Cohesion: 0.09
Nodes (30): CheckboxListTile, main, main, open, main, _session, _login, main (+22 more)

### Community 73 - "CustomerOut"
Cohesion: 0.17
Nodes (18): CustomerAddressIn, CustomerAddressOut, CustomerCompany, CustomerIn, CustomerOut, ProductIn, ProductOut, PaymentTermOut (+10 more)

### Community 74 - ".CreateOrderCoreAsync"
Cohesion: 0.33
Nodes (4): CancellationToken, Dictionary, IReadOnlyCollection, Task

### Community 75 - "GoodsReceipt"
Cohesion: 0.05
Nodes (40): DateOnly, GoodsReceipt, CalculatedTotal, DivergenceJustification, Id, Installments, InvoiceDate, InvoiceNumber (+32 more)

### Community 76 - "SiderGest — Engenharia, Estoque, Suprimentos, PCP"
Cohesion: 0.06
Nodes (35): ConcurrentQueue, Auth and roles, Endpoints, Estoque, Import legacy DBFs, Layout, PCP + Apontamento, Quick start (Windows) (+27 more)

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
Cohesion: 0.15
Nodes (22): IReadOnlyList, ReleaseOut, DateOnly, IReadOnlyList, TimeOnly, AvailabilityLine, AvailabilityResult, FinishedGoodsInput (+14 more)

### Community 81 - "ProductionService"
Cohesion: 0.21
Nodes (11): Shortages, ProductionOrder, OperationDetailsInput, CancellationToken, Func, IReadOnlyList, ProductionSettings, Task (+3 more)

### Community 82 - "QualityCertificate"
Cohesion: 0.06
Nodes (33): DateOnly, DateTimeOffset, List, QualityCertificate, ApprovedBy, CancelReason, Company, CreatedAt (+25 more)

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
Nodes (13): Ebt.Api.Infrastructure, Ebt.Api.Endpoints, ebt_api_infrastructure_crud, microsoft_aspnetcore_authorization, CertificateLinkIn, CertificatePolicies, CertificateReasonIn, CertificateWaiverIn (+5 more)

### Community 88 - "LegacyRow"
Cohesion: 0.33
Nodes (4): IReadOnlyDictionary, LegacyRow, DateOnly, LegacyRowDates

### Community 89 - "CrudSpec"
Cohesion: 0.10
Nodes (18): IQueryCollection, CancellationToken, Dictionary, Expression, Func, IQueryable, RouteGroupBuilder, Task (+10 more)

### Community 90 - "labels.dart"
Cohesion: 0.06
Nodes (31): auditActions, auditEntities, bidStatuses, billToLabels, certificateStatuses, deliveryConditions, deliveryStatuses, feasibilityActions (+23 more)

### Community 91 - ".InTransaction"
Cohesion: 0.23
Nodes (8): Delivery, SalesException, Field, Status, Func, CancellationToken, DateOnly, Task

### Community 92 - ".AdminAsync"
Cohesion: 0.13
Nodes (22): WorkCenterIn, ChangePasswordRequest, CreateUserRequest, LoginRequest, LoginResponse, RefreshRequest, UpdateUserRequest, UserDto (+14 more)

### Community 93 - "SteelLot"
Cohesion: 0.05
Nodes (45): ModelBuilder, DateOnly, DateTimeOffset, List, SlitterJob, FinishedKg, Id, Lot (+37 more)

### Community 94 - "FiscalService"
Cohesion: 0.15
Nodes (15): FiscalException, Field, Status, NfeParty, NfeTransport, OutsideInvoiceOptions, SaleInvoiceOptions, CancellationToken (+7 more)

### Community 95 - ".Has"
Cohesion: 0.19
Nodes (8): FiscalSettings, WebApplication, FiscalEndpoints, MonthlyPriceOut, TaxRuleIn, TaxRuleOut, ClaimsPrincipal, Crud

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
Cohesion: 0.06
Nodes (38): IPasswordHasher, PasswordHasher, CancellationToken, DateTimeOffset, IConfiguration, ILogger, Task, TimeSpan (+30 more)

### Community 101 - "customers.dart"
Cohesion: 0.05
Nodes (39): _active, _addressFields, _addressLine, body, build, _c, canEdit, company (+31 more)

### Community 102 - "SupplierAddress"
Cohesion: 0.12
Nodes (16): SupplierAddress, City, CityIbgeCode, District, Document, Email, Id, LegacyCode (+8 more)

### Community 103 - "AverageCost"
Cohesion: 0.12
Nodes (16): AverageCost, Average, AverageGross, Id, Imported, Material, MaterialId, MonthAverage (+8 more)

### Community 104 - "reports.dart"
Cohesion: 0.05
Nodes (43): _asc, ascending, BillingSummaryScreen, _BillingSummaryScreenState, build, _cells, _code, _companies (+35 more)

### Community 105 - "FiscalInstallment"
Cohesion: 0.25
Nodes (8): DateOnly, FiscalInstallment, Amount, Document, DocumentId, DueDate, Id, Sequence

### Community 106 - "Backend conventions"
Cohesion: 0.14
Nodes (13): Backend conventions, Expression, Func, IResult, ProductionSettings, TimeOnly, WebApplication, ProductionEndpoints (+5 more)

### Community 107 - "Audit.cs"
Cohesion: 0.20
Nodes (8): IHttpContextAccessor, microsoft_entityframeworkcore_changetracking, microsoft_entityframeworkcore_diagnostics, HttpCurrentUser, Name, ICurrentUser, Name, system_text_json

### Community 108 - "steel.dart"
Cohesion: 0.05
Nodes (39): api, base, _body, build, _create, createState, _deleteChild, _deleteLot (+31 more)

### Community 109 - "viability.dart"
Cohesion: 0.05
Nodes (38): api, base, _body, build, context, createState, _delete, _edit (+30 more)

### Community 110 - "Ebt.Core.Entities"
Cohesion: 0.32
Nodes (7): Ebt.Core.Viability, Ebt.Core.Production, Ebt.Core.Fiscal, Ebt.Core.Entities, Ebt.Core.Inventory, Ebt.Core.Sales, ebt_core_services_text

### Community 111 - "Supplier"
Cohesion: 0.09
Nodes (23): List, Supplier, Active, Addresses, GroupCode, Id, LegacyCode, Name (+15 more)

### Community 112 - "ProductionOrderMaterial"
Cohesion: 0.06
Nodes (31): TimeOnly, OccurrenceKind, Downtime, Scrap, ProductionOccurrence, Code, Description, Id (+23 more)

### Community 114 - "StockBalance"
Cohesion: 0.11
Nodes (18): ModelBuilder, StockSettings, StockBalance, Id, Location, LocationId, Lot, Material (+10 more)

### Community 115 - "SefazOptions"
Cohesion: 0.12
Nodes (23): Body, HttpMessageHandler, HttpRequestMessage, X509Certificate2, SefazOptions, CertificatePassword, CertificatePath, IsReal (+15 more)

### Community 116 - "FiscalDocumentOut"
Cohesion: 0.09
Nodes (22): IExceptionHandler, microsoft_aspnetcore_diagnostics, npgsql, CancellationToken, DateOnly, DateTimeOffset, Exception, HttpContext (+14 more)

### Community 117 - "start.ps1"
Cohesion: 0.19
Nodes (4): Fail(), Find-Port(), Test-Bindable(), Test-Port()

### Community 118 - ".Describe"
Cohesion: 0.18
Nodes (8): Tables, GeneratedRegex, IReadOnlyList, Regex, LegacyTable, Control, Control, Dictionary

### Community 119 - "api_integration_test.dart"
Cohesion: 0.17
Nodes (11): ApiClient, ApiException, api, login, main, password, skip, url (+3 more)

### Community 120 - "fiscal.dart"
Cohesion: 0.07
Nodes (31): api, base, _body, build, _cancel, createState, _d, _edit (+23 more)

### Community 121 - "SalesService"
Cohesion: 0.19
Nodes (12): ResolvedLine, Quote, CancellationToken, DateOnly, IReadOnlyList, SalesSettings, Task, SalesService (+4 more)

### Community 122 - ".ProgressAsync"
Cohesion: 0.21
Nodes (10): Task, ProductionException, Field, Status, CancellationToken, Dictionary, IEnumerable, IReadOnlyList (+2 more)

### Community 123 - "PriceListEntry"
Cohesion: 0.17
Nodes (12): DateOnly, PriceListEntry, Customer, CustomerId, IcmsPercent, Id, IpiPercent, Product (+4 more)

### Community 124 - "ImportReport"
Cohesion: 0.11
Nodes (18): IReadOnlyList, ImportOptions, CodePage, DefaultNcm, Directory, DryRun, Steps, ImportReport (+10 more)

### Community 125 - "QuoteExpiryService"
Cohesion: 0.27
Nodes (8): BackgroundService, IServiceScopeFactory, PeriodicTimer, CancellationToken, ILogger, Task, TimeSpan, QuoteExpiryService

### Community 126 - "../api.dart"
Cohesion: 0.06
Nodes (35): ../api.dart, ApiClient get, build, createState, _fetch, _future, PermissionsScreen, _PermissionsScreenState (+27 more)

### Community 127 - "StockMovement"
Cohesion: 0.11
Nodes (18): StockMovement, Date, Document, DocumentId, IcmsRate, Id, Location, LocationId (+10 more)

### Community 129 - "CertificateService"
Cohesion: 0.16
Nodes (15): ClaimsPrincipal, IServiceCollection, WebApplication, CertificateEndpoints, CancellationToken, CultureInfo, DateOnly, Dictionary (+7 more)

### Community 131 - "Employee"
Cohesion: 0.18
Nodes (11): Employee, Active, Code, Function, Id, Name, Nickname, Shift (+3 more)

### Community 133 - "Screens"
Cohesion: 0.20
Nodes (9): Build, Estoque, Painel, Roles, Run, Screens, SiderGest — Flutter client, Suprimentos (+1 more)

### Community 136 - "SefazSpClient"
Cohesion: 0.13
Nodes (18): IConfiguration, IServiceCollection, SefazEnvironment, Homologation, Production, CancellationToken, Task, ISefazClient (+10 more)

### Community 137 - "main.dart"
Cohesion: 0.20
Nodes (9): appTheme, build, cs, EbtApp, main, restore, session, screens/login.dart (+1 more)

### Community 138 - "RowVersionFilter"
Cohesion: 0.24
Nodes (7): EndpointFilterDelegate, EndpointFilterInvocationContext, IEndpointFilter, CancellationToken, Task, ValueTask, RowVersionFilter

### Community 139 - "FiscalDocumentLine"
Cohesion: 0.06
Nodes (32): FiscalDocumentLine, Code, CofinsCst, CofinsPercent, CofinsValue, Description, Document, DocumentId (+24 more)

### Community 140 - "RevisionKind"
Cohesion: 0.29
Nodes (7): DateTimeOffset, RevisionIn, RevisionOut, RevisionKind, Drawing, Process, Structure

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
Cohesion: 0.12
Nodes (16): MovementType, AdjustmentIn, AdjustmentOut, CustomerReturn, IndirectIssue, InventoryCount, Issue, OpeningBalance (+8 more)

### Community 146 - ".ConfigurePurchasing"
Cohesion: 0.16
Nodes (11): PropertyBuilder, PurchasingSettings, FiscalSettings, ModelBuilder, ModelBuilder, ModelBuilder, SalesSettings, QuoteRequestFile (+3 more)

### Community 147 - "deliveries.dart"
Cohesion: 0.04
Nodes (50): certificates.dart, api, base, build, _cancel, _certs, _confirm, createState (+42 more)

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

### Community 158 - "DeliveryLine"
Cohesion: 0.25
Nodes (8): DeliveryLine, Delivery, DeliveryId, Id, OrderLine, OrderLineId, Packages, Quantity

### Community 159 - "Cfop"
Cohesion: 0.09
Nodes (24): CfopIn, CfopOut, Cfop, Active, Code, CofinsCst, DefaultCofinsPercent, DefaultPisPercent (+16 more)

### Community 160 - "NfeSigner"
Cohesion: 0.24
Nodes (7): Como funciona, Emissão de NF-e, Ligar a SEFAZ real (SEFAZ-SP), O que é STUB / não feito, Premissas a confirmar com o contador, X509Certificate2, NfeSigner

### Community 161 - "admin_screens_test.dart"
Cohesion: 0.09
Nodes (21): client, json, log, main, open, pumpAndSettle, pumpWidget, session (+13 more)

### Community 162 - ".ExplodeAsync"
Cohesion: 0.21
Nodes (12): Seq, Item, CancellationToken, Dictionary, IReadOnlyList, List, Task, BomCycleException (+4 more)

### Community 165 - ".ResetAsync"
Cohesion: 0.12
Nodes (24): Ebt.Core.Maintenance, DbConnection, Fk, microsoft_entityframeworkcore_storage, WebApplication, MaintenanceEndpoints, CancellationToken, Dictionary (+16 more)

### Community 166 - "StockDocument"
Cohesion: 0.12
Nodes (16): List, StockDocument, CreatedAt, CreatedBy, Customer, CustomerId, Date, Id (+8 more)

### Community 167 - ".ScheduleTreeAsync"
Cohesion: 0.32
Nodes (6): IReadOnlySet, DateOnly, IReadOnlyList, List, WorkCalendar, HoursPerDay

### Community 168 - "PurchasingFixture.cs"
Cohesion: 0.21
Nodes (10): ICollectionFixture, microsoft_aspnetcore_hosting, microsoft_aspnetcore_mvc_testing, microsoft_aspnetcore_testhost, microsoft_extensions_dependencyinjection, system_collections_concurrent, system_net_http_headers, system_text_json_serialization (+2 more)

### Community 171 - "discard_guard.dart"
Cohesion: 0.33
Nodes (5): build, child, confirmDiscard, DiscardGuard, Widget?

### Community 173 - "FiscalSettings"
Cohesion: 0.10
Nodes (21): FiscalSettings, CancelWindowHours, City, CityIbgeCode, Cnpj, CompanyName, Complement, District (+13 more)

### Community 174 - ".MapInventory"
Cohesion: 0.24
Nodes (7): CancellationToken, ClaimsPrincipal, Expression, StockSettings, Task, WebApplication, InventoryEndpoints

### Community 175 - "AuditInterceptor"
Cohesion: 0.20
Nodes (9): _Entry, DbContextErrorEventData, SaveChangesInterceptor, HashSet, JsonSerializerOptions, List, AuditInterceptor, Type (+1 more)

### Community 176 - "viability_steel_test.dart"
Cohesion: 0.11
Nodes (17): body, client, Fake, job, json, last, log, lot (+9 more)

### Community 177 - "SalesOrderStatus"
Cohesion: 0.15
Nodes (14): ProductId, SalesOrderStatus, Cancelled, Created, Delivered, PartiallyShipped, Released, CancellationToken (+6 more)

### Community 178 - "user_settings.dart"
Cohesion: 0.08
Nodes (26): _again, build, _busy, _ChangePassword, _ChangePasswordState, clear, _clearCache, clearLocalCache (+18 more)

### Community 179 - ".MapViability"
Cohesion: 0.23
Nodes (9): ClaimsPrincipal, WebApplication, ViabilityEndpoints, ViabilityPolicies, FeasibilityStudy, SignoffArea, Commercial, Production (+1 more)

### Community 180 - "MasterDataEndpoints.cs"
Cohesion: 0.16
Nodes (15): CancellationToken, Dictionary, Func, Task, WebApplication, CodeNameIn, CodeNameOut, MasterDataEndpoints (+7 more)

### Community 181 - ".Steel_lot_slitter_and_usage_balance"
Cohesion: 0.19
Nodes (14): DateOnly, DateTimeOffset, Expression, IServiceCollection, WebApplication, SlitterJobIn, SlitterJobOut, SteelEndpoints (+6 more)

### Community 182 - "NfeXml"
Cohesion: 0.39
Nodes (4): CultureInfo, XElement, XNamespace, NfeXml

### Community 183 - "data_reset.dart"
Cohesion: 0.08
Nodes (25): _body, build, _busy, _confirm, createState, dataResetConfirmWord, _DataResetDialog, _DataResetDialogState (+17 more)

### Community 184 - "AuditEntry"
Cohesion: 0.17
Nodes (11): EntityEntry, DateTimeOffset, Dictionary, AuditEntry, Action, At, Changes, Entity (+3 more)

### Community 185 - "login.dart"
Cohesion: 0.09
Nodes (22): build, _busy, _capsLock, _clearError, createState, dispose, _error, _failures (+14 more)

### Community 186 - "SupplierMaterial"
Cohesion: 0.20
Nodes (10): SupplierMaterial, LastPurchaseDate, LastUnitPrice, Material, MaterialId, Notes, Qualification, QualifiedAt (+2 more)

### Community 187 - ".TryHandleAsync"
Cohesion: 0.25
Nodes (6): CancellationToken, Exception, HttpContext, IServiceCollection, ValueTask, ProductionExceptionHandler

### Community 188 - "LostReason"
Cohesion: 0.25
Nodes (8): LostReason, Competitor, CustomerGaveUp, LeadTime, NoLongerNeeded, Other, Price, Specification

### Community 189 - ".Sale_nf_needs_monthly_price_is_recorded_only_after_authorization_and_can_be_cancelled"
Cohesion: 0.11
Nodes (17): FiscalSettingsDto, MonthlyPriceIn, DateTimeOffset, WebApplication, AuditEndpoints, AuditOut, IReadOnlyList, Page (+9 more)

### Community 190 - "SalesSettings"
Cohesion: 0.18
Nodes (11): SalesSettings, ApprovalValidityDays, DefaultConditions, DefaultValidityDays, FollowUpDays, Id, MaxDiscountPercent, MinimumOrderValue (+3 more)

### Community 191 - "FeasibilityOut"
Cohesion: 0.17
Nodes (13): CancellationToken, DateTimeOffset, IReadOnlyList, Task, FeasibilityOrderOut, FeasibilityOut, FeasibilitySummaryOut, SignoffOut (+5 more)

### Community 192 - "TaxRule"
Cohesion: 0.13
Nodes (15): TaxRule, Cfop, CfopCode, CofinsPercent, Customer, CustomerId, IcmsBaseReductionPercent, IcmsCst (+7 more)

### Community 193 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.11
Nodes (18): certificate, main, main, open, main, doc, main, main (+10 more)

### Community 198 - ".FlushInserts"
Cohesion: 0.22
Nodes (7): DbContextEventData, InterceptionResult, SaveChangesCompletedEventData, CancellationToken, DbContext, Task, ValueTask

### Community 340 - "workdays.dart"
Cohesion: 0.09
Nodes (21): a, addWorkDays, d, day, _easter, goodFriday, h, _holidayCache (+13 more)

### Community 341 - ".OnModelCreating"
Cohesion: 0.07
Nodes (27): ModelBuilder, ConsumerType, FinalConsumer, Normal, MaterialClass, Code, Id, Name (+19 more)

### Community 343 - "StatefulWidget"
Cohesion: 0.05
Nodes (45): _CustomerAddresses, build, createState, initialStatus, inspect, _list, LotsView, _LotsViewState (+37 more)

### Community 346 - "Customer"
Cohesion: 0.11
Nodes (18): ProductCustomer, Active, Customer, CustomerDescription, CustomerId, CustomerPartNumber, Product, ProductId (+10 more)

### Community 348 - "Product"
Cohesion: 0.08
Nodes (24): Product, DateTimeOffset, BomItem, ComponentProduct, ComponentProductId, Factor, Id, Material (+16 more)

### Community 349 - ".Add"
Cohesion: 0.32
Nodes (4): DateOnly, WorkDays, Fact, WorkDaysTests

### Community 356 - "SalesLineInput"
Cohesion: 0.12
Nodes (26): Setup, FeasibilityIn, FeasibilityNoteIn, FreightTerms, Cif, CustomerPickup, Fob, DateOnly (+18 more)

## Knowledge Gaps
- **3256 isolated node(s):** `_requestExtensions`, `n`, `files`, `f`, `quoteLineFields` (+3251 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 3680 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **40 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `EbtDbContext` connect `EbtDbContext` to `CertificateService`, `StockReservation`, `PurchasingEndpoints.cs`, `RowVersionFilter`, `FiscalDocumentLine`, `PurchasingService`, `.ConfigurePurchasing`, `Quotation`, `.InTransactionAsync`, `PurchaseOrderLine`, `.MapReports`, `ProductionImport`, `StockLot`, `Cfop`, `DeliveryLine`, `.Arrange`, `.ResetAsync`, `StockDocument`, `.MapQuotes`, `Material`, `PurchaseRequisition`, `microsoft_entityframeworkcore`, `.MapInventory`, `RoutingOperation`, `SalesOrderStatus`, `.MapViability`, `MasterDataEndpoints.cs`, `.MapProducts`, `PurchasingImport`, `ProductionReport`, `AuditEntry`, `CertificateMeasure`, `SupplierMaterial`, `.For`, `SalesOrder`, `SalesOrderLine`, `Importer`, `FeasibilityOut`, `PurchasingEndpoints`, `TaxRule`, `StockService`, `GoodsReceipt`, `SiderGest — Engenharia, Estoque, Suprimentos, PCP`, `SalesEvent`, `ProductionService`, `QualityCertificate`, `ProductionOrderOperation`, `.OnModelCreating`, `CustomerAddress`, `CrudSpec`, `Customer`, `.InTransaction`, `.ConfigureViability`, `SteelLot`, `Product`, `FiscalService`, `QuoteLine`, `FiscalDocument`, `AppUser`, `SupplierAddress`, `AverageCost`, `FiscalInstallment`, `Backend conventions`, `Supplier`, `ProductionOrderMaterial`, `StockBalance`, `FiscalDocumentOut`, `SalesService`, `.ProgressAsync`, `PriceListEntry`, `ImportReport`, `StockMovement`?**
  _High betweenness centrality (0.267) - this node is a cross-community bridge._
- **Why does `AuditInterceptor` connect `AuditInterceptor` to `AuditEntry`, `Audit.cs`, `.FlushInserts`?**
  _High betweenness centrality (0.234) - this node is a cross-community bridge._
- **Why does `_Entry` connect `AuditInterceptor` to `command_palette.dart`?**
  _High betweenness centrality (0.232) - this node is a cross-community bridge._
- **What connects `_requestExtensions`, `n`, `files` to the rest of the system?**
  _3256 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `entities.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.023255813953488372 - nodes in this community are weakly interconnected._
- **Should `EbtDbContext` be split into smaller, more focused modules?**
  _Cohesion score 0.022455805064500716 - nodes in this community are weakly interconnected._
- **Should `shell.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.032167832167832165 - nodes in this community are weakly interconnected._