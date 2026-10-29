# Graph Report - codebase-security-audit-79261d  (2026-10-29)

## Corpus Check
- 155 files · ~164,679 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 27 file(s) not represented in the graph (top: (none) 9, .xml 7, .properties 2)

## Summary
- 3978 nodes · 8066 edges · 173 communities (158 shown, 15 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 706 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `35500945`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- entities.dart
- EbtDbContext
- shell.dart
- sales_quotes.dart
- .Imports_legacy_pcp_data_and_is_idempotent
- SalesService
- dashboard.dart
- production_orders.dart
- PurchasingEndpoints.cs
- record_list.dart
- State
- stock_documents.dart
- entity_form.dart
- StockService
- PurchasingService
- deliveries.dart
- command_palette.dart
- receipts.dart
- orders.dart
- quotations.dart
- requisitions.dart
- sales_orders.dart
- Quotation
- models.dart
- production_floor.dart
- pipeline.dart
- .Arrange
- StockReservation
- ProductionImport
- product_detail.dart
- StockLot
- ProductionOrder
- stock_closing.dart
- session.dart
- actions.dart
- .MapInventory
- SalesEndpoints.cs
- widgets.dart
- MasterDataEndpoints.cs
- SalesEndpoints
- Material
- PurchaseRequisition
- Quote
- package:flutter/material.dart
- entity_list.dart
- microsoft_entityframeworkcore
- RoutingOperation
- stock_purchasing_test.dart
- Ebt.Tests.csproj
- .Arrange
- PurchaseOrderLine
- api.dart
- .MapProducts
- ProductionEndpoints.cs
- PurchasingImport
- ProductionReport
- sales_test.dart
- ProductionModels.cs
- ImportReport
- app_test.dart
- SalesOrder
- SalesOrderLine
- Importer
- GoodsReceiptLine
- .MapQuotations
- Supplier
- StatelessWidget
- ../entities.dart
- PurchasingFixture
- StockLine
- Entities.cs
- Delivery
- dashboard_test.dart
- .AdminAsync
- .MapOrders
- GoodsReceipt
- GoodsReceived
- Sales.cs
- production_test.dart
- http
- .OnModelCreating
- .Conflict
- PurchaseOrder
- Product
- ProductionOrderOperation
- Ebt.Core.Data.Migrations
- CustomerAddress
- FlutterWindow
- .CreateOrderCoreAsync
- CrudSpec
- labels.dart
- win32_window.cpp
- .UserAsync
- StockMovement
- ProductionService
- .ScheduleTreeAsync
- StockDocument
- QuoteLine
- .ComputeAveragesAsync
- .ProgressAsync
- UserRole
- AppUser
- SupplierAddress
- AverageCost
- MovementType
- alerts.dart
- Ebt.Api.Infrastructure
- PurchasingFixture.cs
- ApiFixture
- SiderGest — Engenharia, Estoque, Suprimentos, PCP
- Ebt.Core.Entities
- OutsideShipment
- ProductionOrderMaterial
- utils.cpp
- TrigramSearchIndexes
- JwtOptions
- Errors.cs
- start.ps1
- .Describe
- loader.dart
- cards.dart
- Ebt.Api/Program.cs
- Production
- PriceListEntry
- ImportOptions
- QuoteExpiryService
- main.dart
- manifest.json
- Win32Window
- flutter_window.h
- Sales
- Employee
- LegacyRow
- Screens
- MessageHandler
- RowVersionFilter
- .ConfigureProduction
- Inventory
- Purchasing
- Security_TokenVersion_Xmin
- BomItem
- Production.cs
- QuoteStatus
- OverrunRelease
- ProductionSettings
- Point
- InitialEngineering
- Shift
- SalesSettings
- StockException
- .BuildModel
- .TryHandleAsync
- Auth.cs
- Clock
- .InTransactionAsync
- .Safe
- StockReceiptHandler
- RegisterPlugins
- MainActivity.kt
- .ReleaseAsync
- EntityFormDialog
- LookupField
- LookupPicker
- role_permissions.dart
- generated_plugin_registrant.h
- GlobalUsings.cs
- Exception
- List
- String?

## God Nodes (most connected - your core abstractions)
1. `EbtDbContext` - 182 edges
2. `ProductionOrder` - 74 edges
3. `SalesService` - 61 edges
4. `StockService` - 58 edges
5. `ProductionService` - 58 edges
6. `Ebt.Core.Entities` - 50 edges
7. `ProductionReport` - 46 edges
8. `Ebt.Core.Data` - 45 edges
9. `Quote` - 42 edges
10. `Product` - 41 edges

## Surprising Connections (you probably didn't know these)
- `PCP + Apontamento` --references--> `OutsideShipment`  [INFERRED]
  README.md → src/Ebt.Core/Entities/Production.cs
- `Estoque` --references--> `StockService`  [INFERRED]
  README.md → src/Ebt.Core/Inventory/StockService.Costing.cs
- `Suprimentos` --references--> `StockReceiptHandler`  [INFERRED]
  README.md → src/Ebt.Core/Purchasing/StockReceiptHandler.cs
- `Suprimentos` --references--> `GoodsReceived`  [INFERRED]
  README.md → src/Ebt.Core/Purchasing/GoodsReceived.cs
- `Suprimentos` --references--> `IGoodsReceiptHandler`  [INFERRED]
  README.md → src/Ebt.Core/Purchasing/GoodsReceived.cs

## Import Cycles
- None detected.

## Communities (173 total, 15 thin omitted)

### Community 0 - "entities.dart"
Cohesion: 0.02
Nodes (80): b, bomItemFields, choices, codeName, col, columns, ColumnSpec, d (+72 more)

### Community 1 - "EbtDbContext"
Cohesion: 0.03
Nodes (70): DbContext, IDesignTimeDbContextFactory, DbContextOptions, DesignTimeFactory, DbContextOptions, DbSet, BomItems, CustomerAddresses (+62 more)

### Community 2 - "shell.dart"
Cohesion: 0.03
Nodes (67): access_placeholder.dart, build, deliveryPath, deliveryTone, flowSteps, gap, main, openDelivery (+59 more)

### Community 3 - "sales_quotes.dart"
Cohesion: 0.03
Nodes (62): _accept, _act, _addresses, _addressId, api, asOrder, base, _body (+54 more)

### Community 4 - ".Imports_legacy_pcp_data_and_is_idempotent"
Cohesion: 0.06
Nodes (38): IDisposable, Seq, Component, Item, CancellationToken, Dictionary, IReadOnlyList, List (+30 more)

### Community 5 - "SalesService"
Cohesion: 0.15
Nodes (18): ResolvedLine, Quote, SalesException, Field, Status, CancellationToken, DateOnly, Func (+10 more)

### Community 6 - "dashboard.dart"
Cohesion: 0.04
Nodes (55): bool?, _alerts, _all, _bucket, build, _c, _combine, createState (+47 more)

### Community 7 - "production_orders.dart"
Cohesion: 0.04
Nodes (55): _actions, api, base, build, _bump, _children, context, _cost (+47 more)

### Community 8 - "PurchasingEndpoints.cs"
Cohesion: 0.12
Nodes (41): DateOnly, DateTimeOffset, IReadOnlyList, AwardIn, BidOut, ComparisonBidOut, ComparisonItemOut, DueDateIn (+33 more)

### Community 9 - "record_list.dart"
Cohesion: 0.04
Nodes (50): actions, actionsFirst, alert, allLabel, api, attach, attachItem, attachSupplier (+42 more)

### Community 10 - "State"
Cohesion: 0.06
Nodes (48): DeliveriesScreen, _DeliveriesScreenState, build, createState, initialStatus, inspect, _list, LotsView (+40 more)

### Community 11 - "stock_documents.dart"
Cohesion: 0.04
Nodes (48): _body, _open, build, _receive, _materials, newProduct, _order, _new (+40 more)

### Community 12 - "entity_form.dart"
Cohesion: 0.04
Nodes (45): LookupSpec, api, _applyFill, _body, build, _busy, _clientErrors, confirm (+37 more)

### Community 13 - "StockService"
Cohesion: 0.15
Nodes (18): L, M, P, StockService, CancellationToken, DateOnly, Dictionary, Func (+10 more)

### Community 14 - "PurchasingService"
Cohesion: 0.16
Nodes (11): PurchaseOrder, CancellationToken, GeneratedRegex, IEnumerable, List, Regex, Task, PurchasingException (+3 more)

### Community 15 - "deliveries.dart"
Cohesion: 0.05
Nodes (43): ApiClient get, api, base, build, _cancel, _confirm, createState, _d (+35 more)

### Community 16 - "command_palette.dart"
Cohesion: 0.05
Nodes (44): actions, add, build, _close, compact, createState, _debounce, dispose (+36 more)

### Community 17 - "receipts.dart"
Cohesion: 0.05
Nodes (41): allowNew, api, build, _busy, _calculated, createState, _date, dispose (+33 more)

### Community 18 - "orders.dart"
Cohesion: 0.05
Nodes (40): active, api, base, _busy, createState, d, dispose, _error (+32 more)

### Community 19 - "quotations.dart"
Cohesion: 0.05
Nodes (40): _addSupplier, api, base, bidFields, _bids, build, _busy, _call (+32 more)

### Community 20 - "requisitions.dart"
Cohesion: 0.05
Nodes (39): act, api, base, build, _cancellable, createState, initialStatus, initState (+31 more)

### Community 21 - "sales_orders.dart"
Cohesion: 0.05
Nodes (40): api, base, _body, build, _cancel, _carrier, context, createState (+32 more)

### Community 22 - "Quotation"
Cohesion: 0.05
Nodes (40): QuotationSummaryOut, DateTimeOffset, BidStatus, Approved, Pending, Rejected, PurchasingSettings, AllowEarlyReceipt (+32 more)

### Community 23 - "models.dart"
Cohesion: 0.05
Nodes (39): approved, belowMinimum, blocked, count, countBy, counts, DashboardData, fromJson (+31 more)

### Community 24 - "production_floor.dart"
Cohesion: 0.05
Nodes (39): build, _color, context, createState, cs, _fetch, _from, _grid (+31 more)

### Community 25 - "pipeline.dart"
Cohesion: 0.05
Nodes (39): actions, amount, at, badge, build, c, caption, _Chevron (+31 more)

### Community 26 - ".Arrange"
Cohesion: 0.12
Nodes (27): Setup, StockLocationOut, CustomerAddressOut, PaymentTermIn, PaymentTermOut, SalesOrderIn, SalesReasonIn, SalesReleaseIn (+19 more)

### Community 27 - "StockReservation"
Cohesion: 0.06
Nodes (38): DateOnly, ReservationStatus, Consumed, Open, Released, StockLocation, Active, Code (+30 more)

### Community 28 - "ProductionImport"
Cohesion: 0.17
Nodes (14): ProductionOrderKind, Internal, Standard, CancellationToken, DateOnly, DateTimeOffset, Dictionary, Encoding (+6 more)

### Community 29 - "product_detail.dart"
Cohesion: 0.06
Nodes (37): _add, api, base, build, canWrite, createState, dispose, _done (+29 more)

### Community 30 - "StockLot"
Cohesion: 0.06
Nodes (35): ModelBuilder, StockSettings, DateTimeOffset, StockBalance, Id, Location, LocationId, Lot (+27 more)

### Community 31 - "ProductionOrder"
Cohesion: 0.06
Nodes (36): List, ProductionOrder, AdjustedEnd, AdjustedStart, Bales, ClosedAt, ClosedBy, CostClosedAt (+28 more)

### Community 32 - "stock_closing.dart"
Cohesion: 0.06
Nodes (34): build, _busy, _card, _close, _closings, ClosingScreen, _ClosingScreenState, createState (+26 more)

### Community 33 - "session.dart"
Cohesion: 0.06
Nodes (34): alerts, api, baseUrl, canApproveSales, canBuy, canMoveProduction, canProduce, canReceive (+26 more)

### Community 34 - "actions.dart"
Cohesion: 0.06
Nodes (34): api, build, _c, columns, confirmLabel, createState, describeError, dispose (+26 more)

### Community 35 - ".MapInventory"
Cohesion: 0.10
Nodes (28): ebt_api_infrastructure_crud, CancellationToken, ClaimsPrincipal, DateOnly, DateTimeOffset, Expression, IReadOnlyList, StockSettings (+20 more)

### Community 36 - "SalesEndpoints.cs"
Cohesion: 0.12
Nodes (32): DateOnly, DateTimeOffset, IReadOnlyList, ConfirmDeliveryIn, DeliveryLineOut, DeliveryOut, DeliverySummaryOut, PipelineCard (+24 more)

### Community 37 - "widgets.dart"
Cohesion: 0.06
Nodes (32): ModuleInfo, alert, badge, build, child, count, DashAlert, dashCardShape (+24 more)

### Community 38 - "MasterDataEndpoints.cs"
Cohesion: 0.12
Nodes (21): CancellationToken, Dictionary, Func, Task, WebApplication, CodeNameIn, CodeNameOut, CustomerAddressIn (+13 more)

### Community 39 - "SalesEndpoints"
Cohesion: 0.16
Nodes (14): CancellationToken, ClaimsPrincipal, Expression, Func, IQueryable, List, RouteGroupBuilder, SalesSettings (+6 more)

### Community 40 - "Material"
Cohesion: 0.06
Nodes (33): Material, Active, Class, ClassId, Code, Description, ExternalProcessing, GeneratesPurchaseOrder (+25 more)

### Community 41 - "PurchaseRequisition"
Cohesion: 0.06
Nodes (33): PurchaseRequisition, Application, ApprovedQuantity, DecidedAt, DecidedBy, DecisionNote, Department, Description (+25 more)

### Community 42 - "Quote"
Cohesion: 0.06
Nodes (33): Quote, Address, AddressId, ApprovedAt, ApprovedBy, Conditions, ContactEmail, ContactName (+25 more)

### Community 43 - "package:flutter/material.dart"
Cohesion: 0.07
Nodes (29): ../api.dart, ChangeNotifier, AccessPlaceholderScreen, build, description, icon, title, build (+21 more)

### Community 44 - "entity_list.dart"
Cohesion: 0.06
Nodes (31): bool get, EntitySpec, api, build, canWrite, createState, _debounce, dispose (+23 more)

### Community 45 - "microsoft_entityframeworkcore"
Cohesion: 0.14
Nodes (10): Ebt.DbfImport, Ebt.Core.Data, dbfdatareader, microsoft_entityframeworkcore, microsoft_entityframeworkcore_design, microsoft_entityframeworkcore_metadata_builders, system_globalization, system_linq_expressions (+2 more)

### Community 46 - "RoutingOperation"
Cohesion: 0.06
Nodes (32): Machine, Code, Family, Id, Name, WorkCenter, WorkCenterId, RoutingOperation (+24 more)

### Community 47 - "stock_purchasing_test.dart"
Cohesion: 0.06
Nodes (30): bidStatus, body, client, comparison, doc, Fake, json, last (+22 more)

### Community 48 - "Ebt.Tests.csproj"
Cohesion: 0.08
Nodes (24): coverlet.collector (6.0.2), DbfDataReader (0.9.0), EFCore.NamingConventions (8.0.3), Microsoft.AspNetCore.Authentication.JwtBearer (8.0.11), Microsoft.AspNetCore.Mvc.Testing (8.0.11), Microsoft.Extensions.Identity.Core (8.0.11), Microsoft.NET.Test.Sdk (17.11.1), Npgsql.EntityFrameworkCore.PostgreSQL (8.0.11) (+16 more)

### Community 49 - ".Arrange"
Cohesion: 0.22
Nodes (15): StockDocumentSummary, OccurrenceIn, OccurrenceOut, ProductionOrderIn, ProductionSettingsDto, ReleaseIn, IReadOnlyList, Page (+7 more)

### Community 50 - "PurchaseOrderLine"
Cohesion: 0.07
Nodes (31): List, PurchaseOrderLine, Closed, Description, DiscountPercent, DueDate, IcmsPercent, Id (+23 more)

### Community 51 - "api.dart"
Cohesion: 0.07
Nodes (29): Client, _baseUrl, clearVersions, delete, _error, fieldErrors, fromJson, _headers (+21 more)

### Community 52 - ".MapProducts"
Cohesion: 0.11
Nodes (20): CancellationToken, DateTimeOffset, Dictionary, Expression, IReadOnlyList, IResult, List, Task (+12 more)

### Community 53 - "ProductionEndpoints.cs"
Cohesion: 0.11
Nodes (29): DateOnly, DateTimeOffset, IReadOnlyList, TimeOnly, EmployeeIn, HolidayIn, HolidayOut, OrderUpdateIn (+21 more)

### Community 54 - "PurchasingImport"
Cohesion: 0.20
Nodes (11): Material, QuotationItem, CancellationToken, DateTimeOffset, Encoding, HashSet, List, Preferred (+3 more)

### Community 55 - "ProductionReport"
Cohesion: 0.07
Nodes (30): ProductionReport, Date, DowntimeHours, DowntimeOccurrence, DowntimeOccurrenceId, EmployeeId, EndTime, GoodQuantity (+22 more)

### Community 56 - "sales_test.dart"
Cohesion: 0.07
Nodes (28): body, client, delivery, deliveryStatus, history, json, last, log (+20 more)

### Community 57 - "ProductionModels.cs"
Cohesion: 0.13
Nodes (26): SupplierIn, SupplierOut, BomItemIn, AvailabilityCheckIn, DateOnly, IReadOnlyList, TimeOnly, AvailabilityLine (+18 more)

### Community 58 - "ImportReport"
Cohesion: 0.14
Nodes (17): Averages, Balances, Settings, ImportReport, Warnings, TableReport, File, Inserted (+9 more)

### Community 59 - "app_test.dart"
Cohesion: 0.08
Nodes (26): ApiException, main, enterText, fakeBackend, json, login, main, page (+18 more)

### Community 60 - "SalesOrder"
Cohesion: 0.07
Nodes (28): List, SalesOrder, Address, AddressId, CreatedAt, CreatedBy, Customer, CustomerId (+20 more)

### Community 61 - "SalesOrderLine"
Cohesion: 0.07
Nodes (28): DeliveryLine, Delivery, DeliveryId, Id, OrderLine, OrderLineId, Packages, Quantity (+20 more)

### Community 62 - "Importer"
Cohesion: 0.27
Nodes (10): CancellationToken, DbSet, Dictionary, Encoding, Func, List, Preferred, Prefix (+2 more)

### Community 63 - "GoodsReceiptLine"
Cohesion: 0.09
Nodes (22): PropertyBuilder, PurchasingSettings, ModelBuilder, ModelBuilder, SalesSettings, GoodsReceiptLine, DiscountPercent, GoodsReceipt (+14 more)

### Community 64 - ".MapQuotations"
Cohesion: 0.17
Nodes (14): CancellationToken, IQueryable, IResult, Task, WebApplication, PurchasingEndpoints, DateOnly, DateTimeOffset (+6 more)

### Community 65 - "Supplier"
Cohesion: 0.08
Nodes (26): List, Customer, Active, Addresses, Id, LegacyCode, Name, TradeName (+18 more)

### Community 66 - "StatelessWidget"
Cohesion: 0.08
Nodes (25): DashBarPanel, DashGrid, DashModuleCard, DashNotice, DashTile, OverdueScreen, _Summary, OutsideProcessingScreen (+17 more)

### Community 67 - "../entities.dart"
Cohesion: 0.09
Nodes (23): api, icon, label, of, QuickAction, quickActionsFor, r, createState (+15 more)

### Community 68 - "PurchasingFixture"
Cohesion: 0.15
Nodes (12): IAsyncLifetime, HttpClient, Task, WebApplicationFactory, PurchasingFixture, ConnectionString, Handler, ReceivingLocationId (+4 more)

### Community 69 - "StockLine"
Cohesion: 0.34
Nodes (10): StockLocationIn, StockSettingsIn, StockLine, DateOnly, Fact, HttpClient, HttpResponseMessage, List (+2 more)

### Community 70 - "Entities.cs"
Cohesion: 0.08
Nodes (24): RevisionIn, DateTimeOffset, ConsumerType, FinalConsumer, Normal, Revision, Code, CreatedAt (+16 more)

### Community 71 - "Delivery"
Cohesion: 0.08
Nodes (25): Delivery, Address, AddressId, Carrier, CreatedAt, CreatedBy, DeliveredAt, GrossWeightKg (+17 more)

### Community 72 - "dashboard_test.dart"
Cohesion: 0.08
Nodes (23): backArrowTests, client, json, lists, log, main, openPalette, page (+15 more)

### Community 73 - ".AdminAsync"
Cohesion: 0.24
Nodes (11): CustomerIn, CustomerOut, ProductOut, ConsumerType, ProductKind, Part, Fact, HttpClient (+3 more)

### Community 74 - ".MapOrders"
Cohesion: 0.13
Nodes (14): CancellationToken, Exception, Expression, Func, HttpContext, IResult, IServiceCollection, ProductionSettings (+6 more)

### Community 75 - "GoodsReceipt"
Cohesion: 0.09
Nodes (24): DateOnly, GoodsReceipt, CalculatedTotal, DivergenceJustification, Id, Installments, InvoiceDate, InvoiceNumber (+16 more)

### Community 76 - "GoodsReceived"
Cohesion: 0.11
Nodes (18): ConcurrentQueue, Suprimentos, Exception, HttpContext, IServiceCollection, ValueTask, PurchasingExceptionHandler, CancellationToken (+10 more)

### Community 77 - "Sales.cs"
Cohesion: 0.09
Nodes (22): DateTimeOffset, PaymentTerm, Active, Code, CreditLimit, Days, Id, Name (+14 more)

### Community 78 - "production_test.dart"
Cohesion: 0.09
Nodes (21): body, client, Fake, json, last, log, main, order (+13 more)

### Community 79 - "http"
Cohesion: 0.10
Nodes (21): ASPNETCORE_ENVIRONMENT, applicationUrl, commandName, dotnetRunMessages, environmentVariables, launchBrowser, applicationUrl, commandName (+13 more)

### Community 80 - ".OnModelCreating"
Cohesion: 0.11
Nodes (17): ModelBuilder, MaterialClass, Code, Id, Name, ProductCustomer, Active, Customer (+9 more)

### Community 81 - ".Conflict"
Cohesion: 0.30
Nodes (5): ProductionException, Field, Status, CancellationToken, Task

### Community 82 - "PurchaseOrder"
Cohesion: 0.10
Nodes (21): OrderSummaryOut, PurchaseOrder, ClosedAt, ClosedBy, CloseReason, Id, IssuedAt, IssuedBy (+13 more)

### Community 83 - "Product"
Cohesion: 0.10
Nodes (21): Product, Blocked, Code, Customers, DiameterMm, DrawingRevision, HeightMm, Id (+13 more)

### Community 84 - "ProductionOrderOperation"
Cohesion: 0.10
Nodes (21): ProductionOrderOperation, Description, External, ExternalLeadDays, Id, Machine, MachineId, Operators (+13 more)

### Community 85 - "Ebt.Core.Data.Migrations"
Cohesion: 0.37
Nodes (6): Ebt.Core.Data.Migrations, microsoft_entityframeworkcore_infrastructure, microsoft_entityframeworkcore_migrations, microsoft_entityframeworkcore_storage_valueconversion, npgsql_entityframeworkcore_postgresql_metadata, system

### Community 86 - "CustomerAddress"
Cohesion: 0.10
Nodes (20): CustomerAddress, Buyer, City, CityIbgeCode, Complement, Customer, CustomerId, DefaultCfop (+12 more)

### Community 87 - "FlutterWindow"
Cohesion: 0.11
Nodes (18): DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM, FlutterWindow, flutter_controller_ (+10 more)

### Community 88 - ".CreateOrderCoreAsync"
Cohesion: 0.18
Nodes (10): Ipi, Price, SalesOrderInput, IEnumerable, List, Qty, CancellationToken, Dictionary (+2 more)

### Community 89 - "CrudSpec"
Cohesion: 0.11
Nodes (17): Action, CancellationToken, Dictionary, Expression, Func, IQueryable, RouteGroupBuilder, Task (+9 more)

### Community 90 - "labels.dart"
Cohesion: 0.11
Nodes (17): bidStatuses, deliveryStatuses, freightTerms, lotStatuses, movementTypes, orderStatuses, pipelineStages, postableTypes (+9 more)

### Community 91 - "win32_window.cpp"
Cohesion: 0.18
Nodes (14): wchar_t, Scale(), Create, Destroy, Show, UpdateTheme, Win32Window::Win32Window(), WindowClassRegistrar (+6 more)

### Community 92 - ".UserAsync"
Cohesion: 0.30
Nodes (6): WorkCenterIn, CreateUserRequest, LoginRequest, Fact, Task, AuthTests

### Community 93 - "StockMovement"
Cohesion: 0.11
Nodes (18): StockMovement, Date, Document, DocumentId, IcmsRate, Id, Location, LocationId (+10 more)

### Community 94 - "ProductionService"
Cohesion: 0.37
Nodes (4): CancellationToken, Func, Task, ProductionService

### Community 95 - ".ScheduleTreeAsync"
Cohesion: 0.27
Nodes (7): IReadOnlySet, ProductionSettings, DateOnly, IReadOnlyList, List, WorkCalendar, HoursPerDay

### Community 96 - "StockDocument"
Cohesion: 0.12
Nodes (17): List, StockDocument, CreatedAt, CreatedBy, Customer, CustomerId, Date, Id (+9 more)

### Community 97 - "QuoteLine"
Cohesion: 0.12
Nodes (17): QuoteLine, CustomerPartNumber, DeliveryDate, Description, IcmsPercent, Id, IpiPercent, LeadTimeDays (+9 more)

### Community 98 - ".ComputeAveragesAsync"
Cohesion: 0.19
Nodes (8): CancellationToken, DateOnly, List, Task, BeforeRow, BucketKey, PeriodRow, Sums

### Community 99 - ".ProgressAsync"
Cohesion: 0.28
Nodes (6): CancellationToken, Dictionary, IEnumerable, IReadOnlyList, List, Task

### Community 100 - "UserRole"
Cohesion: 0.14
Nodes (13): AuthorizationOptions, IReadOnlyDictionary, Access, WebApplication, UserRole, Admin, Engineering, Production (+5 more)

### Community 101 - "AppUser"
Cohesion: 0.13
Nodes (15): IConfiguration, IPasswordHasher, PasswordHasher, ILogger, TimeSpan, AuthEndpoints, AppUser, Active (+7 more)

### Community 102 - "SupplierAddress"
Cohesion: 0.12
Nodes (16): SupplierAddress, City, CityIbgeCode, District, Document, Email, Id, LegacyCode (+8 more)

### Community 103 - "AverageCost"
Cohesion: 0.12
Nodes (16): AverageCost, Average, AverageGross, Id, Imported, Material, MaterialId, MonthAverage (+8 more)

### Community 104 - "MovementType"
Cohesion: 0.12
Nodes (16): MovementType, AdjustmentIn, AdjustmentOut, CustomerReturn, IndirectIssue, InventoryCount, Issue, OpeningBalance (+8 more)

### Community 105 - "alerts.dart"
Cohesion: 0.13
Nodes (14): AlertBell, AlertCenter, AlertInfo, build, center, count, filter, icon (+6 more)

### Community 106 - "Ebt.Api.Infrastructure"
Cohesion: 0.30
Nodes (7): Ebt.Api.Infrastructure, Ebt.Api.Endpoints, Ebt.Tests, microsoft_aspnetcore_authorization, ProductCustomerIn, system_net, system_net_http_json

### Community 107 - "PurchasingFixture.cs"
Cohesion: 0.16
Nodes (12): Ebt.Core.Purchasing, ICollectionFixture, microsoft_aspnetcore_hosting, microsoft_aspnetcore_mvc_testing, microsoft_aspnetcore_testhost, microsoft_extensions_dependencyinjection, system_collections_concurrent, system_net_http_headers (+4 more)

### Community 108 - "ApiFixture"
Cohesion: 0.21
Nodes (9): JsonSerializerOptions, LoginResponse, HttpClient, HttpResponseMessage, Task, WebApplicationFactory, ApiFixture, ConnectionString (+1 more)

### Community 109 - "SiderGest — Engenharia, Estoque, Suprimentos, PCP"
Cohesion: 0.13
Nodes (14): Auth and roles, Endpoints, Estoque, Import legacy DBFs, Layout, PCP + Apontamento, Quick start (Windows), Rules carried over from the legacy system (+6 more)

### Community 110 - "Ebt.Core.Entities"
Cohesion: 0.41
Nodes (5): Ebt.Core.Production, Ebt.Core.Entities, Ebt.Core.Inventory, Ebt.Core.Sales, ebt_core_services_text

### Community 111 - "OutsideShipment"
Cohesion: 0.14
Nodes (14): OutsideShipment, CreatedBy, Id, InvoiceNumber, Notes, Operation, OperationId, Quantity (+6 more)

### Community 112 - "ProductionOrderMaterial"
Cohesion: 0.14
Nodes (14): ProductionOrderMaterial, ComponentProduct, ComponentProductId, Id, Material, MaterialId, OperationSequence, Order (+6 more)

### Community 113 - "utils.cpp"
Cohesion: 0.19
Nodes (12): wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16(), flutter_windows, _In_ (+4 more)

### Community 114 - "TrigramSearchIndexes"
Cohesion: 0.17
Nodes (9): Column, Migration, MigrationBuilder, DateOnly, DateTimeOffset, ModelBuilder, TimeOnly, TrigramSearchIndexes (+1 more)

### Community 115 - "JwtOptions"
Cohesion: 0.15
Nodes (11): ExpiresAt, DateTimeOffset, Task, JwtOptions, Audience, ExpiresMinutes, Issuer, SigningKey (+3 more)

### Community 116 - "Errors.cs"
Cohesion: 0.22
Nodes (10): IExceptionHandler, microsoft_aspnetcore_diagnostics, npgsql, CancellationToken, Exception, HttpContext, ILogger, ValueTask (+2 more)

### Community 117 - "start.ps1"
Cohesion: 0.19
Nodes (4): Fail(), Find-Port(), Test-Bindable(), Test-Port()

### Community 118 - ".Describe"
Cohesion: 0.18
Nodes (9): Tables, GeneratedRegex, IReadOnlyList, Regex, LegacyDbf, LegacyTable, Control, Control (+1 more)

### Community 119 - "loader.dart"
Cohesion: 0.17
Nodes (11): ApiClient, api, _counted, DashboardLoader, engineering, production, purchasing, sales (+3 more)

### Community 120 - "cards.dart"
Cohesion: 0.17
Nodes (11): actions, build, OnboardingCard, OnboardingStep, onDismiss, QuickActionsCard, steps, quick_actions.dart (+3 more)

### Community 121 - "Ebt.Api/Program.cs"
Cohesion: 0.17
Nodes (9): Ebt.Core.Services, microsoft_aspnetcore_authentication_jwtbearer, microsoft_aspnetcore_httpoverrides, microsoft_aspnetcore_identity, microsoft_identitymodel_tokens, microsoft_openapi_models, Program, Text (+1 more)

### Community 122 - "Production"
Cohesion: 0.18
Nodes (9): DateOnly, DateTimeOffset, MigrationBuilder, TimeOnly, DateOnly, DateTimeOffset, ModelBuilder, TimeOnly (+1 more)

### Community 123 - "PriceListEntry"
Cohesion: 0.17
Nodes (12): DateOnly, PriceListEntry, Customer, CustomerId, IcmsPercent, Id, IpiPercent, Product (+4 more)

### Community 124 - "ImportOptions"
Cohesion: 0.18
Nodes (11): IReadOnlyList, ImportOptions, CodePage, DefaultNcm, Directory, DryRun, Steps, CancellationToken (+3 more)

### Community 125 - "QuoteExpiryService"
Cohesion: 0.24
Nodes (8): BackgroundService, IServiceScopeFactory, PeriodicTimer, CancellationToken, ILogger, Task, TimeSpan, QuoteExpiryService

### Community 126 - "main.dart"
Cohesion: 0.18
Nodes (10): appTheme, build, cs, EbtApp, main, restore, session, package:flutter_localizations/flutter_localizations.dart (+2 more)

### Community 127 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 128 - "Win32Window"
Cohesion: 0.24
Nodes (11): OnCreate, HWND, Win32Window, child_content_, GetClientArea, OnCreate, quit_on_close_, SetChildContent (+3 more)

### Community 129 - "flutter_window.h"
Cohesion: 0.27
Nodes (7): dart_project, flutter_view_controller, functional, memory, string, vector, windows

### Community 130 - "Sales"
Cohesion: 0.20
Nodes (8): DateOnly, DateTimeOffset, MigrationBuilder, DateOnly, DateTimeOffset, ModelBuilder, TimeOnly, Sales

### Community 131 - "Employee"
Cohesion: 0.18
Nodes (11): Employee, Active, Code, Function, Id, Name, Nickname, Shift (+3 more)

### Community 132 - "LegacyRow"
Cohesion: 0.33
Nodes (4): IReadOnlyDictionary, LegacyRow, DateOnly, LegacyRowDates

### Community 133 - "Screens"
Cohesion: 0.20
Nodes (9): Build, Estoque, Painel, Roles, Run, Screens, SiderGest — Flutter client, Suprimentos (+1 more)

### Community 134 - "MessageHandler"
Cohesion: 0.36
Nodes (10): HWND, LPARAM, LRESULT, UINT, WPARAM, EnableFullDpiSupportIfAvailable(), GetHandle, GetThisFromHandle (+2 more)

### Community 135 - "RowVersionFilter"
Cohesion: 0.24
Nodes (7): EndpointFilterDelegate, EndpointFilterInvocationContext, IEndpointFilter, CancellationToken, Task, ValueTask, RowVersionFilter

### Community 136 - ".ConfigureProduction"
Cohesion: 0.20
Nodes (9): ModelBuilder, ProductionSettings, DateOnly, Holiday, Date, Id, Name, Employee (+1 more)

### Community 137 - "Inventory"
Cohesion: 0.22
Nodes (7): DateOnly, DateTimeOffset, MigrationBuilder, DateOnly, DateTimeOffset, ModelBuilder, Inventory

### Community 138 - "Purchasing"
Cohesion: 0.22
Nodes (7): DateOnly, DateTimeOffset, MigrationBuilder, DateOnly, DateTimeOffset, ModelBuilder, Purchasing

### Community 139 - "Security_TokenVersion_Xmin"
Cohesion: 0.22
Nodes (7): DateTimeOffset, MigrationBuilder, DateOnly, DateTimeOffset, ModelBuilder, TimeOnly, Security_TokenVersion_Xmin

### Community 140 - "BomItem"
Cohesion: 0.20
Nodes (10): BomItem, ComponentProduct, ComponentProductId, Factor, Id, MaterialId, Quantity, RoutingOperation (+2 more)

### Community 141 - "Production.cs"
Cohesion: 0.22
Nodes (9): OccurrenceKind, Downtime, Scrap, ProductionOccurrence, Code, Description, Id, Kind (+1 more)

### Community 142 - "QuoteStatus"
Cohesion: 0.20
Nodes (10): QuoteStatus, Accepted, Approved, Cancelled, Converted, Draft, Expired, PendingApproval (+2 more)

### Community 143 - "OverrunRelease"
Cohesion: 0.22
Nodes (9): DateTimeOffset, OverrunRelease, Id, Justification, Operation, OperationId, Quantity, ReleasedAt (+1 more)

### Community 144 - "ProductionSettings"
Cohesion: 0.22
Nodes (9): ProductionSettings, HoursPerDay, Id, IssueLocation, IssueLocationId, OverrunTolerancePercent, ReceiptLocation, ReceiptLocationId (+1 more)

### Community 145 - "Point"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 146 - "InitialEngineering"
Cohesion: 0.29
Nodes (5): DateTimeOffset, MigrationBuilder, DateTimeOffset, ModelBuilder, InitialEngineering

### Community 147 - "Shift"
Cohesion: 0.25
Nodes (8): TimeOnly, Shift, Code, EndsAt, Hours, Id, Name, StartsAt

### Community 148 - "SalesSettings"
Cohesion: 0.25
Nodes (8): SalesSettings, DefaultConditions, DefaultValidityDays, Id, MaxDiscountPercent, MinimumOrderValue, ShippingLocation, ShippingLocationId

### Community 149 - "StockException"
Cohesion: 0.29
Nodes (7): StockErrorKind, Conflict, Invalid, NotFound, StockException, Field, Kind

### Community 150 - ".BuildModel"
Cohesion: 0.29
Nodes (6): ModelSnapshot, DateOnly, DateTimeOffset, ModelBuilder, TimeOnly, EbtDbContextModelSnapshot

### Community 151 - ".TryHandleAsync"
Cohesion: 0.29
Nodes (5): Exception, HttpContext, IServiceCollection, ValueTask, SalesExceptionHandler

### Community 152 - "Auth.cs"
Cohesion: 0.33
Nodes (5): Policies, UpdateUserRequest, UserDto, system_identitymodel_tokens_jwt, List

### Community 153 - "Clock"
Cohesion: 0.38
Nodes (3): DateOnly, Clock, TimeZoneInfo

### Community 154 - ".InTransactionAsync"
Cohesion: 0.33
Nodes (4): CancellationToken, Func, Task, DbTransactions

### Community 155 - ".Safe"
Cohesion: 0.50
Nodes (3): GeneratedRegex, Regex, SqlIdentifier

### Community 156 - "StockReceiptHandler"
Cohesion: 0.70
Nodes (3): CancellationToken, Task, StockReceiptHandler

### Community 157 - "RegisterPlugins"
Cohesion: 0.50
Nodes (3): RegisterPlugins(), flutter_secure_storage_windows_plugin, PluginRegistry

## Knowledge Gaps
- **2124 isolated node(s):** `status`, `message`, `fieldErrors`, `items`, `total` (+2119 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 2460 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ApiException` connect `app_test.dart` to `api.dart`?**
  _High betweenness centrality (0.446) - this node is a cross-community bridge._
- **Why does `EbtDbContext` connect `EbtDbContext` to `.Imports_legacy_pcp_data_and_is_idempotent`, `SalesService`, `RowVersionFilter`, `.ConfigureProduction`, `BomItem`, `Production.cs`, `PurchasingService`, `OverrunRelease`, `StockService`, `Quotation`, `.InTransactionAsync`, `StockReservation`, `StockReceiptHandler`, `ProductionImport`, `StockLot`, `ProductionOrder`, `.MapInventory`, `MasterDataEndpoints.cs`, `SalesEndpoints`, `Material`, `PurchaseRequisition`, `microsoft_entityframeworkcore`, `RoutingOperation`, `PurchaseOrderLine`, `.MapProducts`, `PurchasingImport`, `ProductionReport`, `ImportReport`, `SalesOrder`, `SalesOrderLine`, `Importer`, `GoodsReceiptLine`, `.MapQuotations`, `Supplier`, `PurchasingFixture`, `Entities.cs`, `Delivery`, `.MapOrders`, `GoodsReceipt`, `Sales.cs`, `.OnModelCreating`, `Product`, `ProductionOrderOperation`, `CustomerAddress`, `CrudSpec`, `StockMovement`, `ProductionService`, `StockDocument`, `QuoteLine`, `AppUser`, `SupplierAddress`, `AverageCost`, `OutsideShipment`, `ProductionOrderMaterial`, `JwtOptions`, `PriceListEntry`, `ImportOptions`?**
  _High betweenness centrality (0.174) - this node is a cross-community bridge._
- **Why does `BomCycleException` connect `.Imports_legacy_pcp_data_and_is_idempotent` to `app_test.dart`?**
  _High betweenness centrality (0.123) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `StockService` (e.g. with `Estoque` and `.RunAsync()`) actually correct?**
  _`StockService` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `status`, `message`, `fieldErrors` to the rest of the system?**
  _2124 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `entities.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.024691358024691357 - nodes in this community are weakly interconnected._
- **Should `EbtDbContext` be split into smaller, more focused modules?**
  _Cohesion score 0.028951486697965573 - nodes in this community are weakly interconnected._