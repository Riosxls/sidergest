<!-- Snapshot of graphify-out/GRAPH_REPORT.md (2026-11-01, communities named with graphify label). Regenerate with: graphify update . -->

# Graph Report - sidergest  (2026-11-01)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 7303 nodes · 14844 edges · 272 communities (216 shown, 56 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1411 edges (avg confidence: 0.85)
- Token cost: 159,626 input · 2,298 output

## Graph Freshness
- Built from commit: `09437543`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Entity DTO Columns
- EF Core DB Context
- Shell Navigation Screen
- Quote Screen State
- DBF Import Tests
- Settings Widgets
- Dashboard Screen
- Production Orders Screen
- Purchasing Endpoints
- Record List Widget
- Graph Communities Overview
- Stock Documents Screen
- Entity Form Widget
- Stock Service Endpoints
- Purchase Quotations Endpoints
- Sales Common Utilities
- Command Palette Widget
- Goods Receipts Screen
- NF XML Validation Tests
- Quotations Screen
- Stock Movement Entity
- Sales Orders Screen
- Work Center Entities
- PDF Document Builders
- Production Floor Screen
- Production Order Status
- Admin Service Scopes
- DANFE PDF Builder
- Production Order Kinds
- Module Navigation
- Pipeline Widget
- Production Order Entity
- Production Orders Tests
- Session Auth Permissions
- Action Buttons Widget
- Fiscal Screen
- Production Report Models
- Customers Screen
- Sales Test Support
- Tax Calculation Logic
- Material Entities
- Admin Screens Tests
- Quote Entity
- Quick Actions Widget
- Graph Report Navigation
- Stock Closing Screen
- Routing Operation Entities
- Purchasing Stock Tests
- Solution Dependencies
- API Input Output Models
- NF Document PDF
- API Client Core
- BOM Product Endpoints
- EF Core Namespace Imports
- DBF Import Utilities
- Production DB Config
- Sales Integration Tests
- Backup Settings Screen
- Import Report Data
- DBF Import NF-e Files
- Certificate Tests
- Sales Order Line Entities
- DBF Import Core
- Certificates Screen
- Purchasing DB Config
- Customer Entity
- Master Data Endpoints
- Certificate Templates Screen
- Purchasing DI Setup
- Viability Endpoints
- Dashboard Data Models
- Delivery Entity
- Stock Balance Entity
- Backup Settings Entity
- App Navigation Tests
- Settings Dialog UI
- DB Model Configuration
- Inventory DB Config
- Dashboard UI
- API Launch Settings
- Feasibility Service
- Production Service Logic
- Quality Certificate Entities
- Employee Entity
- Auth Password Service
- Settings Sections Screen
- Customer Address Entity
- Row Version Filter
- Stock Endpoints Models
- Generic CRUD Mapping
- Labels Display Strings
- Steel Job Tests
- Auth Request Models
- Steel DB Config
- Fiscal Service Handlers
- Purchasing Endpoints
- BOM Service
- Sales DB Config
- Fiscal DB Config
- Data Reset Service
- Purchase Requisition Entity
- Backup Settings Tests
- Supplier Address Entity
- Production Bulk Operations
- Billing Reports Screen
- Print Panel Widget
- Production Endpoints
- Settings Screen Tests
- Steel Screen
- Devices Settings Screen
- API Test Fixture
- Reports Screen Widgets
- Supplier Entity
- Dart Project
- Sales Order Models
- SEFAZ HTTP Client
- Exception Handlers
- Start Script
- Permissions Screen
- Text Utilities
- Suppliers Tests
- Sales Service Logic
- Refresh Token Entity
- Frontend Widget Tests
- DBF Import Options
- Core Service Modules
- Certificate DTOs
- Data Reset Dialog
- Viability Steel Tests
- Certificate Endpoints DI
- Sales Setup Models
- Backup Status Tests
- Production Floor Tests
- Flutter README
- Stock Balance DTOs
- Purchasing Edge Tests
- Fiscal DI Architecture
- Legacy Spec Importer
- Purchase Order Tests
- Fiscal Document Line
- NF-e Signer
- Feasibility Study Entity
- Sales Endpoints
- Report Document Builder
- Alert Bell Widget
- Auth Access Policies
- Project README
- Deliveries Screen
- Print Gate Widget
- Stock Exceptions
- Fiscal Endpoints
- Stock Document DTOs
- Certificate PDF Builder
- Clock Service
- DB Transactions
- SQL Identifier Regex
- Billing Report Endpoints
- Secure Storage Plugin
- Fiscal Endpoints Models
- Entity List Screen
- Fiscal NF-e Docs
- Viability DI Setup
- Product Revision Entity
- Role Permissions Matrix
- Plugin Registry
- App Entry Point
- Stock Location Entities
- Work Calendar Service
- Production Order Material
- Exception
- List
- CFOP Fiscal Endpoints
- Fiscal Settings Entity
- Integration Tests Setup
- Save Changes Interceptor
- API Endpoint Assembly
- Viability Rules Service
- User Settings Screen
- Audit Screen
- Purchase Order Entities
- Steel Endpoints
- Fiscal Product Policies
- Legacy Cleanup Screen
- App Preferences
- Login Screen
- Viability EF Config
- Operations & Backup Docs
- Customers Tests
- NF-e Key Generation
- Delivery Endpoints
- Quote Expiry Service
- EF Core Data
- Audit Log Endpoints
- Data Source Maintenance
- Product Entity
- Core Entities
- Dashboard Tests
- Fiscal Module
- Inventory Module
- Production Module
- BOM Item Entity
- Quote Editor Screen
- Core Services
- OpenAPI Models
- Quote Detail Screen
- Low Stock Service
- Customer Product API Tests
- Quotes List Screen
- WorkDays Test Setup
- HTTP Client
- Material Cost Averages
- Stock Movement Types
- Viability Module
- Backup Settings
- API Test Infrastructure
- Page Layout Tests
- Product Customer Pricing
- DateTime
- Purchasing Module
- CLAUDE Project Docs
- Fiscal Inutilization Entity
- System Backup Endpoints
- Legacy Table Discovery
- Data Reset Scopes
- Quote Status Enum
- Backup Settings Tests UI
- API Endpoints
- DBF Stock Import Options
- Windows DWM API
- Flutter View Controller
- Flutter Windows
- Certificates Module
- Functional Utilities
- Plugin Registrant
- Sales Exception Handler
- Inventory Endpoints
- IO
- iostream
- Memory
- EF Core Infrastructure
- EF Core Migrations
- EF Value Converters
- JWT Configuration
- Npgsql EF Metadata
- Optional
- Maintenance Module
- Printing Plugin
- Data Source Marker
- Share Plus Windows
- Search Tests
- Backup Frequency
- Backup Schedule
- Auth Infrastructure
- API Infrastructure
- Backup Destination Tests
- Audit Endpoints
- Backup Agent Script
- Pre-push Hook
- Certificate Templates Tests
- stdio
- System
- URL Launcher Windows
- Windows
- Workdays Dart
- Purchase Orders Screen
- WorkDays Service

## God Nodes (most connected - your core abstractions)
1. `EbtDbContext` - 274 edges
2. `Communities (259 total, 56 thin omitted)` - 204 edges
3. `Ebt.Core.Entities` - 102 edges
4. `SalesService` - 86 edges
5. `ProductionService` - 74 edges
6. `FiscalDocument` - 70 edges
7. `Ebt.Core.Data` - 66 edges
8. `StockService` - 65 edges
9. `SalesOrder` - 62 edges
10. `QualityCertificate` - 59 edges

## Surprising Connections (you probably didn't know these)
- `Estoque` --references--> `StockService`  [INFERRED]
  README.md → src/Ebt.Core/Inventory/StockService.Costing.cs
- `Fiscal / NF` --references--> `StubSefazClient`  [INFERRED]
  CLAUDE.md → src/Ebt.Core/Fiscal/StubSefazClient.cs
- `Permissions` --references--> `AccessParityTests`  [INFERRED]
  docs/mvc/ARCHITECTURE.md → tests/Ebt.Tests/AccessParityTests.cs
- `Backend conventions` --references--> `EbtDbContext`  [INFERRED]
  CLAUDE.md → src/Ebt.Core/Data/EbtDbContext.Backup.cs
- `Audit findings (coupling and bottlenecks)` --references--> `EbtDbContext`  [INFERRED]
  docs/mvc/ARCHITECTURE.md → src/Ebt.Core/Data/EbtDbContext.Backup.cs

## Import Cycles
- None detected.

## Communities (272 total, 56 thin omitted)

### Community 0 - "Entity DTO Columns"
Cohesion: 0.02
Nodes (85): b, bomItemFields, choices, codeName, col, columns, ColumnSpec, d (+77 more)

### Community 1 - "EF Core DB Context"
Cohesion: 0.02
Nodes (98): DbContext, IDesignTimeDbContextFactory, PropertyBuilder, DbContextOptions, DesignTimeFactory, BackupSettings, DbSet, ModelBuilder (+90 more)

### Community 2 - "Shell Navigation Screen"
Cohesion: 0.04
Nodes (56): audit.dart, admin, base, build, _collapsed, _comercialGroups, createState, _current (+48 more)

### Community 3 - "Quote Screen State"
Cohesion: 0.01
Nodes (140): _accept, _acceptedStep, _act, _addresses, _addressId, api, _applyDefaultTerm, _approvalBanner (+132 more)

### Community 4 - "DBF Import Tests"
Cohesion: 0.10
Nodes (17): IDisposable, Component, Fact, Task, DbfImportTests, IEnumerable, IReadOnlyList, DbfField (+9 more)

### Community 5 - "Settings Widgets"
Cohesion: 0.06
Nodes (30): build, children, control, createState, _data, _error, formatMoment, icon (+22 more)

### Community 6 - "Dashboard Screen"
Cohesion: 0.03
Nodes (58): _alerts, _all, allOverdue, _armedMinutes, _armTimer, attention, blurb, build (+50 more)

### Community 7 - "Production Orders Screen"
Cohesion: 0.03
Nodes (68): _actions, api, base, build, _bump, _children, context, _cost (+60 more)

### Community 8 - "Purchasing Endpoints"
Cohesion: 0.17
Nodes (14): CancellationToken, IQueryable, IResult, Task, WebApplication, PurchasingEndpoints, DateOnly, DateTimeOffset (+6 more)

### Community 9 - "Record List Widget"
Cohesion: 0.03
Nodes (73): actions, actionsFirst, alert, _aligned, allLabel, api, _ascending, attach (+65 more)

### Community 10 - "Graph Communities Overview"
Cohesion: 0.01
Nodes (204): Communities (259 total, 56 thin omitted), Community 0 - "entities.dart", Community 100 - "PurchaseRequisition", Community 101 - "BackupSettingsTests", Community 102 - "SupplierAddress", Community 103 - ".SnapshotStructureAsync", Community 104 - "reports.dart", Community 105 - "print_panel.dart" (+196 more)

### Community 11 - "Stock Documents Screen"
Cohesion: 0.04
Nodes (53): _itemsSection, _open, build, _receive, newProduct, _order, _new, showRequisition (+45 more)

### Community 12 - "Entity Form Widget"
Cohesion: 0.03
Nodes (62): LookupSpec, api, _applyFill, askCustomPrazo, _body, build, _busy, _clientErrors (+54 more)

### Community 13 - "Stock Service Endpoints"
Cohesion: 0.11
Nodes (25): L, M, P, WebApplication, CancellationToken, DateOnly, List, Task (+17 more)

### Community 14 - "Purchase Quotations Endpoints"
Cohesion: 0.16
Nodes (11): PurchaseOrder, CancellationToken, GeneratedRegex, IEnumerable, List, Regex, Task, PurchasingException (+3 more)

### Community 15 - "Sales Common Utilities"
Cohesion: 0.04
Nodes (50): certificates.dart, build, deliveryPath, deliveryTone, flowSteps, gap, isSuperseded, main (+42 more)

### Community 16 - "Command Palette Widget"
Cohesion: 0.04
Nodes (45): actions, add, build, clear, _close, compact, createState, _debounce (+37 more)

### Community 17 - "Goods Receipts Screen"
Cohesion: 0.05
Nodes (43): allowNew, api, build, _busy, _calculated, createState, _date, dispose (+35 more)

### Community 18 - "NF XML Validation Tests"
Cohesion: 0.12
Nodes (20): Case, Expected, NfeTransport, CultureInfo, DateTimeOffset, XNamespace, NfeInut, Fact (+12 more)

### Community 19 - "Quotations Screen"
Cohesion: 0.05
Nodes (40): _addSupplier, api, base, bidFields, _bids, build, _busy, _call (+32 more)

### Community 20 - "Stock Movement Entity"
Cohesion: 0.11
Nodes (18): StockMovement, Date, Document, DocumentId, IcmsRate, Id, Location, LocationId (+10 more)

### Community 21 - "Sales Orders Screen"
Cohesion: 0.03
Nodes (79): api, base, _billTo, _body, build, _cancel, _cardPrint, _certificatesSection (+71 more)

### Community 22 - "Work Center Entities"
Cohesion: 0.06
Nodes (36): Machine, Code, Family, Id, Name, WorkCenter, WorkCenterId, WorkCenter (+28 more)

### Community 23 - "PDF Document Builders"
Cohesion: 0.02
Nodes (87): _b, blankRows, _blue, box, _build, buildProductionOrderPdf, buildQuotePdf, buildSalesOrderPdf (+79 more)

### Community 24 - "Production Floor Screen"
Cohesion: 0.05
Nodes (40): build, _color, context, createState, cs, _fetch, _from, _grid (+32 more)

### Community 25 - "Production Order Status"
Cohesion: 0.25
Nodes (8): ProductionOrderStatus, Cancelled, Closed, Created, Finished, InProduction, Released, Stopped

### Community 26 - "Admin Service Scopes"
Cohesion: 0.22
Nodes (13): IServiceScope, DataResetIn, OrderCancelIn, QuoteOut, QuoteRequestIn, ConvertInput, DateOnly, Fact (+5 more)

### Community 27 - "DANFE PDF Builder"
Cohesion: 0.05
Nodes (39): banner, bold, buildDanfePdf, c, cancelled, _cell, _cep, d (+31 more)

### Community 28 - "Production Order Kinds"
Cohesion: 0.16
Nodes (15): ProductionOrderKind, Internal, Standard, CancellationToken, DateOnly, DateTimeOffset, Dictionary, Encoding (+7 more)

### Community 29 - "Module Navigation"
Cohesion: 0.05
Nodes (37): ModuleInfo, Navigate, build, _commercial, _content, createState, _data, dispose (+29 more)

### Community 30 - "Pipeline Widget"
Cohesion: 0.05
Nodes (41): actions, amount, at, badge, build, c, caption, _Chevron (+33 more)

### Community 31 - "Production Order Entity"
Cohesion: 0.05
Nodes (38): List, ProductionOrder, AdjustedEnd, AdjustedStart, Bales, ClosedAt, ClosedBy, CostClosedAt (+30 more)

### Community 32 - "Production Orders Tests"
Cohesion: 0.05
Nodes (38): body, children, childResult, client, costClosedAt, ensureVisible, _Fake, has (+30 more)

### Community 33 - "Session Auth Permissions"
Cohesion: 0.03
Nodes (78): _activitySent, alerts, api, _apply, baseUrl, canApproveSales, canBuy, canCertificate (+70 more)

### Community 34 - "Action Buttons Widget"
Cohesion: 0.06
Nodes (35): addEnabled, addLabel, api, build, _c, columns, confirmLabel, createState (+27 more)

### Community 35 - "Fiscal Screen"
Cohesion: 0.06
Nodes (38): api, _authSection, base, _body, build, _cancel, createState, _d (+30 more)

### Community 36 - "Production Report Models"
Cohesion: 0.09
Nodes (34): Description, DateOnly, IReadOnlyList, TimeOnly, AvailabilityLine, AvailabilityResult, FinishedGoodsInput, ItemConsumption (+26 more)

### Community 37 - "Customers Screen"
Cohesion: 0.05
Nodes (42): _active, _addressFields, _addressLine, body, build, _c, canEdit, company (+34 more)

### Community 38 - "Sales Test Support"
Cohesion: 0.06
Nodes (31): answer, body, called, certs, client, credit, defaultOrder, defaultQuote (+23 more)

### Community 39 - "Tax Calculation Logic"
Cohesion: 0.09
Nodes (26): Icms, Id, Ipi, CancellationToken, ClaimsPrincipal, Dictionary, Expression, Func (+18 more)

### Community 40 - "Material Entities"
Cohesion: 0.06
Nodes (34): Material, Active, Class, ClassId, Code, Description, ExternalProcessing, GeneratesPurchaseOrder (+26 more)

### Community 41 - "Admin Screens Tests"
Cohesion: 0.05
Nodes (41): Card, client, json, log, main, open, pumpAndSettle, pumpWidget (+33 more)

### Community 42 - "Quote Entity"
Cohesion: 0.05
Nodes (40): Quote, Address, AddressId, ApprovedAt, ApprovedBy, Conditions, ContactEmail, ContactName (+32 more)

### Community 43 - "Quick Actions Widget"
Cohesion: 0.07
Nodes (31): api, icon, label, of, QuickAction, quickActionsFor, r, act (+23 more)

### Community 44 - "Graph Report Navigation"
Cohesion: 0.05
Nodes (44): Community Hubs (Navigation), Corpus Check, God Nodes (most connected - your core abstractions), Graph Freshness, Graph Report - sidergest  (2026-11-01), Import Cycles, Knowledge Gaps, Suggested Questions (+36 more)

### Community 45 - "Stock Closing Screen"
Cohesion: 0.06
Nodes (33): build, _busy, _card, _close, _closings, ClosingScreen, _ClosingScreenState, createState (+25 more)

### Community 46 - "Routing Operation Entities"
Cohesion: 0.06
Nodes (33): ConsumerType, FinalConsumer, Normal, RoutingOperation, Description, Id, Items, Machine (+25 more)

### Community 47 - "Purchasing Stock Tests"
Cohesion: 0.07
Nodes (29): bidStatus, body, client, comparison, doc, Fake, json, last (+21 more)

### Community 48 - "Solution Dependencies"
Cohesion: 0.08
Nodes (23): coverlet.collector (6.0.2), DbfDataReader (0.9.0), EFCore.NamingConventions (10.0.1), Microsoft.AspNetCore.Authentication.JwtBearer (10.0.14), Microsoft.AspNetCore.Mvc.Testing (10.0.14), Microsoft.Extensions.Identity.Core (10.0.14), Microsoft.NET.Test.Sdk (17.11.1), Npgsql.EntityFrameworkCore.PostgreSQL (10.0.3) (+15 more)

### Community 49 - "API Input Output Models"
Cohesion: 0.17
Nodes (24): SupplierIn, SupplierOut, BomItemIn, List, OccurrenceIn, OccurrenceOut, ProcessIn, ProductionOrderIn (+16 more)

### Community 50 - "NF Document PDF"
Cohesion: 0.03
Nodes (75): a, ad, addresses, askNfFiscal, base, buildOutsideNfPdf, buildSaleNfPdf, _cell (+67 more)

### Community 51 - "API Client Core"
Cohesion: 0.04
Nodes (46): _baseUrl, _call, cap, clearVersions, delete, describeError, _doRefresh, download (+38 more)

### Community 52 - "BOM Product Endpoints"
Cohesion: 0.13
Nodes (18): CancellationToken, DateTimeOffset, Dictionary, Expression, IReadOnlyDictionary, IReadOnlyList, IResult, List (+10 more)

### Community 53 - "EF Core Namespace Imports"
Cohesion: 0.13
Nodes (9): Ebt.Core.Purchasing, Ebt.Core.Entities, Ebt.Core.Data, microsoft_entityframeworkcore, microsoft_entityframeworkcore_changetracking, microsoft_entityframeworkcore_design, microsoft_entityframeworkcore_diagnostics, microsoft_entityframeworkcore_metadata_builders (+1 more)

### Community 54 - "DBF Import Utilities"
Cohesion: 0.14
Nodes (15): QuotationItem, IReadOnlyDictionary, LegacyRow, CancellationToken, DateOnly, DateTimeOffset, Encoding, HashSet (+7 more)

### Community 55 - "Production DB Config"
Cohesion: 0.03
Nodes (66): ModelBuilder, ProductionSettings, OutsideShipment, DateOnly, DateTimeOffset, TimeOnly, Holiday, Date (+58 more)

### Community 56 - "Sales Integration Tests"
Cohesion: 0.05
Nodes (38): body, client, credit, daysLeft, delivery, deliveryStatus, history, json (+30 more)

### Community 57 - "Backup Settings Screen"
Cohesion: 0.05
Nodes (41): agentMissing, agentSeenAt, _AgentWarning, backupAgentStaleAfter, _BackupForm, _BackupFormState, BackupSettings, BackupSettingsView (+33 more)

### Community 58 - "Import Report Data"
Cohesion: 0.13
Nodes (18): Averages, Balances, Settings, ImportReport, Warnings, TableReport, File, Inserted (+10 more)

### Community 59 - "DBF Import NF-e Files"
Cohesion: 0.13
Nodes (10): Ebt.DbfImport, dbfdatareader, system_globalization, system_reflection, system_security_cryptography_x509certificates, system_security_cryptography_xml, system_text, system_xml (+2 more)

### Community 60 - "Certificate Tests"
Cohesion: 0.07
Nodes (29): body, cert, certs, certStatus, client, deleteStatus, deliveries, _err (+21 more)

### Community 61 - "Sales Order Line Entities"
Cohesion: 0.05
Nodes (37): DeliveryCondition, Bk, Gbk, Nbk, SalesOrderLine, Condition, CustomerPartNumber, Description (+29 more)

### Community 62 - "DBF Import Core"
Cohesion: 0.24
Nodes (12): Action, CancellationToken, DbSet, Dictionary, Encoding, Func, List, Name (+4 more)

### Community 63 - "Certificates Screen"
Cohesion: 0.02
Nodes (85): _addNote, _addRow, api, _banner, base, _body, build, _busy (+77 more)

### Community 64 - "Purchasing DB Config"
Cohesion: 0.03
Nodes (71): PurchasingSettings, ModelBuilder, DateOnly, GoodsReceipt, CalculatedTotal, DivergenceJustification, Id, Installments (+63 more)

### Community 65 - "Customer Entity"
Cohesion: 0.08
Nodes (24): Customer, Active, Addresses, City, Complement, Contact, CreditLimit, DefaultPaymentTerm (+16 more)

### Community 66 - "Master Data Endpoints"
Cohesion: 0.15
Nodes (16): CancellationToken, Dictionary, Func, Task, WebApplication, CodeNameIn, CodeNameOut, MachineIn (+8 more)

### Community 67 - "Certificate Templates Screen"
Cohesion: 0.03
Nodes (85): CertificateTemplatesScreen, _CertificateTemplatesScreenState, _CustomerAddresses, _add, api, base, build, canWrite (+77 more)

### Community 68 - "Purchasing DI Setup"
Cohesion: 0.07
Nodes (32): ConcurrentQueue, IAsyncLifetime, Suprimentos, Exception, HttpContext, IServiceCollection, ValueTask, PurchasingExceptionHandler (+24 more)

### Community 69 - "Viability Endpoints"
Cohesion: 0.23
Nodes (9): ClaimsPrincipal, WebApplication, ViabilityEndpoints, ViabilityPolicies, FeasibilityStudy, SignoffArea, Commercial, Production (+1 more)

### Community 70 - "Dashboard Data Models"
Cohesion: 0.03
Nodes (68): approved, blocked, blockedTotal, byKind, byShape, byStatus, closings, CommercialDashboard (+60 more)

### Community 71 - "Delivery Entity"
Cohesion: 0.07
Nodes (29): List, Delivery, Address, AddressId, Carrier, CreatedAt, CreatedBy, DeliveredAt (+21 more)

### Community 72 - "Stock Balance Entity"
Cohesion: 0.07
Nodes (27): StockBalance, Id, Location, LocationId, Lot, LotId, Material, MaterialId (+19 more)

### Community 73 - "Backup Settings Entity"
Cohesion: 0.12
Nodes (16): DateTimeOffset, DayOfWeek, TimeOnly, BackupSettings, AgentSeenAt, Destination, Enabled, Frequency (+8 more)

### Community 74 - "App Navigation Tests"
Cohesion: 0.12
Nodes (15): enterText, fakeBackend, json, login, main, page, path, product (+7 more)

### Community 75 - "Settings Dialog UI"
Cohesion: 0.07
Nodes (28): build, builder, _content, createState, _header, icon, id, initState (+20 more)

### Community 76 - "DB Model Configuration"
Cohesion: 0.22
Nodes (5): ModelBuilder, MaterialGroup, Code, Id, Name

### Community 77 - "Inventory DB Config"
Cohesion: 0.04
Nodes (52): ModelBuilder, StockSettings, DateOnly, DateTimeOffset, List, ReservationStatus, Consumed, Open (+44 more)

### Community 78 - "Dashboard UI"
Cohesion: 0.06
Nodes (30): alert, BarPanel, build, child, dashCardShape, DashGrid, DashNotice, DashTile (+22 more)

### Community 79 - "API Launch Settings"
Cohesion: 0.10
Nodes (21): ASPNETCORE_ENVIRONMENT, applicationUrl, commandName, dotnetRunMessages, environmentVariables, launchBrowser, applicationUrl, commandName (+13 more)

### Community 80 - "Feasibility Service"
Cohesion: 0.17
Nodes (13): CancellationToken, DateTimeOffset, IReadOnlyList, Task, FeasibilityOrderOut, FeasibilityOut, FeasibilitySummaryOut, SignoffOut (+5 more)

### Community 81 - "Production Service Logic"
Cohesion: 0.20
Nodes (12): Shortages, ProductionOrder, ProductionService, CancellationToken, Func, IReadOnlyList, ProductionSettings, Task (+4 more)

### Community 82 - "Quality Certificate Entities"
Cohesion: 0.03
Nodes (71): ModelBuilder, DateOnly, DateTimeOffset, List, CertificateMeasure, Certificate, CertificateId, Found (+63 more)

### Community 83 - "Employee Entity"
Cohesion: 0.18
Nodes (11): Employee, Active, Code, Function, Id, Name, Nickname, Shift (+3 more)

### Community 84 - "Auth Password Service"
Cohesion: 0.08
Nodes (31): IPasswordHasher, PasswordHasher, CancellationToken, DateTimeOffset, HttpContext, IConfiguration, ILogger, Task (+23 more)

### Community 85 - "Settings Sections Screen"
Cohesion: 0.05
Nodes (38): bool?, AboutSection, AccountSection, _AccountSectionState, AppearanceSection, build, _busy, _clearCache (+30 more)

### Community 86 - "Customer Address Entity"
Cohesion: 0.10
Nodes (20): CustomerAddress, Buyer, City, CityIbgeCode, Complement, Customer, CustomerId, DefaultCfop (+12 more)

### Community 87 - "Row Version Filter"
Cohesion: 0.24
Nodes (7): EndpointFilterDelegate, EndpointFilterInvocationContext, IEndpointFilter, CancellationToken, Task, ValueTask, RowVersionFilter

### Community 88 - "Stock Endpoints Models"
Cohesion: 0.25
Nodes (15): List, AverageCostOut, LowStockRequisitionsIn, ReverseIn, StockSettingsIn, MaterialIn, MaterialOut, StockLine (+7 more)

### Community 89 - "Generic CRUD Mapping"
Cohesion: 0.11
Nodes (17): IQueryCollection, CancellationToken, Expression, Func, IQueryable, RouteGroupBuilder, Task, CrudSpec (+9 more)

### Community 90 - "Labels Display Strings"
Cohesion: 0.06
Nodes (33): auditActions, auditEntities, backupFrequencyLabels, bidStatuses, billToLabels, certificateStatuses, deliveryConditions, deliveryStatuses (+25 more)

### Community 91 - "Steel Job Tests"
Cohesion: 0.07
Nodes (28): body, client, deleteStatus, ensureVisible, f, _Fake, has, _job (+20 more)

### Community 92 - "Auth Request Models"
Cohesion: 0.20
Nodes (11): WorkCenterIn, CreateUserRequest, LoginRequest, UpdateUserRequest, UserDto, IReadOnlyDictionary, Fact, JsonElement (+3 more)

### Community 93 - "Steel DB Config"
Cohesion: 0.05
Nodes (45): ModelBuilder, DateOnly, DateTimeOffset, List, SlitterJob, FinishedKg, Id, Lot (+37 more)

### Community 94 - "Fiscal Service Handlers"
Cohesion: 0.14
Nodes (12): NfeParty, ReconcileResult, CancellationToken, DateTimeOffset, DbContextOptions, FiscalSettings, Func, IReadOnlyList (+4 more)

### Community 95 - "Purchasing Endpoints"
Cohesion: 0.12
Nodes (39): DateOnly, DateTimeOffset, IReadOnlyList, AwardIn, BidOut, ComparisonBidOut, ComparisonItemOut, DueDateIn (+31 more)

### Community 96 - "BOM Service"
Cohesion: 0.21
Nodes (12): Seq, Item, CancellationToken, Dictionary, IReadOnlyList, List, Task, BomExplosion (+4 more)

### Community 97 - "Sales DB Config"
Cohesion: 0.03
Nodes (69): ModelBuilder, SalesSettings, DateOnly, DateTimeOffset, BillTo, Bts, Ebt, DeliveryLine (+61 more)

### Community 98 - "Fiscal DB Config"
Cohesion: 0.04
Nodes (51): FiscalSettings, ModelBuilder, DateOnly, List, FiscalDocument, AccessKey, AdditionalInfo, CancelledAt (+43 more)

### Community 99 - "Data Reset Service"
Cohesion: 0.23
Nodes (13): DbConnection, Fk, CancellationToken, Dictionary, HashSet, IEnumerable, IReadOnlyCollection, IReadOnlyList (+5 more)

### Community 100 - "Purchase Requisition Entity"
Cohesion: 0.06
Nodes (34): PurchaseRequisition, Application, ApprovedQuantity, DecidedAt, DecidedBy, DecisionNote, Department, Description (+26 more)

### Community 101 - "Backup Settings Tests"
Cohesion: 0.29
Nodes (6): BackupSettingsDto, BackupSettingsInput, DateTimeOffset, Fact, Task, BackupSettingsTests

### Community 102 - "Supplier Address Entity"
Cohesion: 0.12
Nodes (16): SupplierAddress, City, CityIbgeCode, District, Document, Email, Id, LegacyCode (+8 more)

### Community 103 - "Production Bulk Operations"
Cohesion: 0.29
Nodes (6): Sales flow, BulkResult, CancellationToken, IReadOnlyList, List, Task

### Community 104 - "Billing Reports Screen"
Cohesion: 0.05
Nodes (43): _asc, ascending, BillingSummaryScreen, _BillingSummaryScreenState, build, _cells, _code, _companies (+35 more)

### Community 105 - "Print Panel Widget"
Cohesion: 0.10
Nodes (19): build, customerOrderPdf, detail, doc, docs, id, label, name (+11 more)

### Community 106 - "Production Endpoints"
Cohesion: 0.08
Nodes (35): StockDocumentSummary, DateOnly, DateTimeOffset, Expression, Func, IReadOnlyDictionary, IReadOnlyList, IResult (+27 more)

### Community 107 - "Settings Screen Tests"
Cohesion: 0.07
Nodes (31): CheckboxListTile, main, open, main, _session, client, ensureVisible, goTo (+23 more)

### Community 108 - "Steel Screen"
Cohesion: 0.05
Nodes (45): api, base, _body, build, _create, createState, _deleteChild, _deleteLot (+37 more)

### Community 109 - "Devices Settings Screen"
Cohesion: 0.04
Nodes (58): build, _busy, createState, current, DeviceInfo, DevicesView, _DevicesViewState, _error (+50 more)

### Community 110 - "API Test Fixture"
Cohesion: 0.23
Nodes (8): HttpClient, HttpResponseMessage, JsonSerializerOptions, Task, WebApplicationFactory, ApiFixture, ConnectionString, HttpExtensions

### Community 111 - "Reports Screen Widgets"
Cohesion: 0.08
Nodes (26): PrintButton, _CustomerCompany, _CustomerOrders, ModuleCard, OverdueScreen, OutsideProcessingScreen, ReportsScreen, ReceiptScreen (+18 more)

### Community 112 - "Supplier Entity"
Cohesion: 0.08
Nodes (25): PCP + Apontamento, List, Supplier, Active, Addresses, GroupCode, Id, LegacyCode (+17 more)

### Community 114 - "Sales Order Models"
Cohesion: 0.12
Nodes (22): FreightTerms, Cif, CustomerPickup, Fob, OrderOrigin, Email, Fax, System (+14 more)

### Community 115 - "SEFAZ HTTP Client"
Cohesion: 0.11
Nodes (29): Body, HttpMessageHandler, HttpRequestMessage, HttpClient, X509Certificate2, XNamespace, SefazOptions, CertificatePassword (+21 more)

### Community 116 - "Exception Handlers"
Cohesion: 0.11
Nodes (18): IExceptionHandler, CancellationToken, Exception, HttpContext, ValueTask, FiscalExceptionHandler, CancellationToken, Exception (+10 more)

### Community 117 - "Start Script"
Cohesion: 0.19
Nodes (4): Fail(), Find-Port(), Test-Bindable(), Test-Port()

### Community 118 - "Permissions Screen"
Cohesion: 0.04
Nodes (56): ../api.dart, build, _cellBox, createState, dispose, _fetch, _future, _gridColumn (+48 more)

### Community 120 - "Suppliers Tests"
Cohesion: 0.15
Nodes (12): client, _json, log, main, _page, _performance, _pump, pumpAndSettle (+4 more)

### Community 121 - "Sales Service Logic"
Cohesion: 0.12
Nodes (23): ResolvedLine, Quote, SalesException, Field, Status, SalesService, CancellationToken, DateOnly (+15 more)

### Community 122 - "Refresh Token Entity"
Cohesion: 0.17
Nodes (11): DateTimeOffset, RefreshToken, CreatedAt, Device, Id, Ip, RevokedAt, TokenHash (+3 more)

### Community 123 - "Frontend Widget Tests"
Cohesion: 0.04
Nodes (52): main, main, open, client, json, log, main, nf (+44 more)

### Community 124 - "DBF Import Options"
Cohesion: 0.15
Nodes (12): IReadOnlyList, ImportOptions, CodePage, DefaultNcm, Directory, DryRun, Steps, CancellationToken (+4 more)

### Community 125 - "Core Service Modules"
Cohesion: 0.34
Nodes (7): Ebt.Core.Viability, Ebt.Core.Services, Ebt.Core.Production, Ebt.Core.Fiscal, Ebt.Core.Inventory, Ebt.Core.Sales, ebt_core_services_text

### Community 126 - "Certificate DTOs"
Cohesion: 0.18
Nodes (19): DateOnly, DateTimeOffset, IReadOnlyList, List, CertificateLinkIn, CertificateMeasureOut, CertificateOut, CertificateReasonIn (+11 more)

### Community 127 - "Data Reset Dialog"
Cohesion: 0.08
Nodes (25): _body, build, _busy, _confirm, createState, dataResetConfirmWord, _DataResetDialog, _DataResetDialogState (+17 more)

### Community 128 - "Viability Steel Tests"
Cohesion: 0.11
Nodes (17): body, client, Fake, job, json, last, log, lot (+9 more)

### Community 129 - "Certificate Endpoints DI"
Cohesion: 0.13
Nodes (17): Backend conventions, Surprising Connections (you probably didn't know these), CancellationToken, ClaimsPrincipal, IServiceCollection, Task, WebApplication, CertificateEndpoints (+9 more)

### Community 130 - "Sales Setup Models"
Cohesion: 0.12
Nodes (25): Setup, StockLocationOut, CustomerAddressOut, CustomerCompany, CustomerOut, MachineOut, ProductOut, FeasibilityIn (+17 more)

### Community 131 - "Backup Status Tests"
Cohesion: 0.16
Nodes (15): BackupStatusFile, Login, BackupStatus, ProfileRequest, RefreshRequest, SessionsRequest, Client, Fact (+7 more)

### Community 132 - "Production Floor Tests"
Cohesion: 0.05
Nodes (43): body, client, _Fake, has, _json, last, load, loadStatus (+35 more)

### Community 133 - "Flutter README"
Cohesion: 0.20
Nodes (9): Build, Estoque, MetaGest — Flutter client, Painel, Roles, Run, Screens, Suprimentos (+1 more)

### Community 134 - "Stock Balance DTOs"
Cohesion: 0.13
Nodes (15): IReadOnlyList, AvailabilityOut, InspectionIn, LocationQuantity, LowStockRequisitionsOut, StockBalanceOut, LotStatus, Quarantine (+7 more)

### Community 135 - "Purchasing Edge Tests"
Cohesion: 0.25
Nodes (11): OrderFromQuotationIn, QuotationSupplierIn, ReasonIn, BidInput, DateOnly, Fact, HttpClient, HttpResponseMessage (+3 more)

### Community 136 - "Fiscal DI Architecture"
Cohesion: 0.08
Nodes (30): ConcurrentDictionary, Audit findings (coupling and bottlenecks), Data flow of the sales chain, Knowledge graph, MetaGest architecture, Permissions, Why there is no MVC folder move, IConfiguration (+22 more)

### Community 137 - "Legacy Spec Importer"
Cohesion: 0.24
Nodes (10): CancellationToken, IEnumerable, IReadOnlyList, JsonSerializerOptions, List, Task, LegacySpec, LegacySpecImporter (+2 more)

### Community 138 - "Purchase Order Tests"
Cohesion: 0.08
Nodes (25): main, answer, body, _day, _Env, failWith, _json, last (+17 more)

### Community 139 - "Fiscal Document Line"
Cohesion: 0.08
Nodes (35): FiscalDocumentLine, Code, CofinsCst, CofinsPercent, CofinsValue, Description, Document, DocumentId (+27 more)

### Community 140 - "NF-e Signer"
Cohesion: 0.25
Nodes (8): FiscalException, Field, Status, X509Certificate2, NfeSigner, CancellationToken, Task, XElement

### Community 141 - "Feasibility Study Entity"
Cohesion: 0.06
Nodes (31): DateTimeOffset, FeasibilityStudy, Characteristics, CommercialAt, CommercialBy, CommercialNote, CreatedAt, CreatedBy (+23 more)

### Community 142 - "Sales Endpoints"
Cohesion: 0.09
Nodes (39): DateOnly, DateTimeOffset, IReadOnlyList, List, ConfirmDeliveryIn, DeliveryLineOut, DeliveryOut, DeliverySummaryOut (+31 more)

### Community 143 - "Report Document Builder"
Cohesion: 0.08
Nodes (24): build, cells, enabled, fileBase, filters, flex, headers, kind (+16 more)

### Community 144 - "Alert Bell Widget"
Cohesion: 0.13
Nodes (14): AlertBell, AlertCenter, AlertInfo, build, center, count, filter, icon (+6 more)

### Community 145 - "Auth Access Policies"
Cohesion: 0.12
Nodes (16): AuthorizationOptions, IReadOnlyDictionary, Access, LoginResponse, UserRole, Admin, Engineering, Production (+8 more)

### Community 146 - "Project README"
Cohesion: 0.13
Nodes (14): Auth and roles, Endpoints, Estoque, Import legacy DBFs, Knowledge graph (Graphify), Layout (MVC mapping), MetaGest — Engenharia, Estoque, Suprimentos, PCP, Quick start (Windows) (+6 more)

### Community 147 - "Deliveries Screen"
Cohesion: 0.05
Nodes (38): api, base, _body, build, _cancel, _certificateGate, _certified, _certs (+30 more)

### Community 148 - "Print Gate Widget"
Cohesion: 0.13
Nodes (14): choice, clear, continueLabel, count, isDone, _key, mark, printGate (+6 more)

### Community 149 - "Stock Exceptions"
Cohesion: 0.29
Nodes (7): StockErrorKind, Conflict, Invalid, NotFound, StockException, Field, Kind

### Community 150 - "Fiscal Endpoints"
Cohesion: 0.18
Nodes (9): FiscalSettings, WebApplication, FiscalEndpoints, MonthlyPriceOut, TaxRuleIn, TaxRuleOut, ClaimsPrincipal, Dictionary (+1 more)

### Community 151 - "Stock Document DTOs"
Cohesion: 0.20
Nodes (17): DateOnly, DateTimeOffset, ClosingOut, ReservationIn, ReservationOut, StockDocumentOut, StockLotOut, StockMovementOut (+9 more)

### Community 152 - "Certificate PDF Builder"
Cohesion: 0.08
Nodes (23): address, _b, buildCertificatePdf, cancelled, _cell, company, _dash, doc (+15 more)

### Community 153 - "Clock Service"
Cohesion: 0.26
Nodes (5): DateOnly, DateTime, DateTimeOffset, Clock, TimeZoneInfo

### Community 154 - "DB Transactions"
Cohesion: 0.33
Nodes (4): CancellationToken, Func, Task, DbTransactions

### Community 155 - "SQL Identifier Regex"
Cohesion: 0.50
Nodes (3): GeneratedRegex, Regex, SqlIdentifier

### Community 156 - "Billing Report Endpoints"
Cohesion: 0.17
Nodes (18): From, CancellationToken, DateOnly, IReadOnlyList, List, Task, WebApplication, BillingRow (+10 more)

### Community 158 - "Fiscal Endpoints Models"
Cohesion: 0.14
Nodes (31): SaleSetup, DateOnly, DateTimeOffset, IReadOnlyList, Task, CancelInvoiceIn, FiscalDocumentOut, FiscalInstallmentOut (+23 more)

### Community 159 - "Entity List Screen"
Cohesion: 0.03
Nodes (65): ApiClient get, ChangeNotifier, PageResult, EntitySpec, api, build, canWrite, createState (+57 more)

### Community 160 - "Fiscal NF-e Docs"
Cohesion: 0.11
Nodes (16): Lazy, Como funciona, Emissão de NF-e, Ligar a SEFAZ real (SEFAZ-SP), O que é STUB / não feito, Premissas a confirmar com o contador, IReadOnlyList, Type (+8 more)

### Community 162 - "Product Revision Entity"
Cohesion: 0.13
Nodes (15): RevisionIn, DateTimeOffset, Revision, Code, CreatedAt, Id, Kind, Product (+7 more)

### Community 165 - "App Entry Point"
Cohesion: 0.14
Nodes (13): appTheme, build, cs, EbtApp, main, _NoTransitions, restore, session (+5 more)

### Community 166 - "Stock Location Entities"
Cohesion: 0.06
Nodes (33): StockLocation, Active, Code, Id, Kind, Name, ProductionSettings, HoursPerDay (+25 more)

### Community 167 - "Work Calendar Service"
Cohesion: 0.23
Nodes (9): IReadOnlySet, CancellationToken, DateOnly, IReadOnlyList, List, Task, DateOnly, WorkCalendar (+1 more)

### Community 168 - "Production Order Material"
Cohesion: 0.14
Nodes (14): ProductionOrderMaterial, ComponentProduct, ComponentProductId, Id, Material, MaterialId, OperationSequence, Order (+6 more)

### Community 171 - "CFOP Fiscal Endpoints"
Cohesion: 0.05
Nodes (40): CfopIn, CfopOut, Cfop, Active, Code, CofinsCst, DefaultCofinsPercent, DefaultPisPercent (+32 more)

### Community 173 - "Fiscal Settings Entity"
Cohesion: 0.10
Nodes (21): FiscalSettings, CancelWindowHours, City, CityIbgeCode, Cnpj, CompanyName, Complement, District (+13 more)

### Community 174 - "Integration Tests Setup"
Cohesion: 0.05
Nodes (35): ApiClient, ApiException, certificate, main, issuer, key, main, nf (+27 more)

### Community 175 - "Save Changes Interceptor"
Cohesion: 0.12
Nodes (18): _Entry, DbContextErrorEventData, DbContextEventData, EntityEntry, InterceptionResult, SaveChangesCompletedEventData, SaveChangesInterceptor, CancellationToken (+10 more)

### Community 176 - "API Endpoint Assembly"
Cohesion: 0.16
Nodes (9): Ebt.Core.Certificates, Ebt.Api.Infrastructure, Ebt.Api.Endpoints, Ebt.Core.Maintenance, Ebt.Tests, CertificatePolicies, system_net, system_net_http_json (+1 more)

### Community 177 - "Viability Rules Service"
Cohesion: 0.26
Nodes (8): ProductId, CancellationToken, Dictionary, IEnumerable, IReadOnlyCollection, Task, ViabilityRules, StudyId

### Community 178 - "User Settings Screen"
Cohesion: 0.10
Nodes (21): _again, build, _busy, _ChangePassword, _ChangePasswordState, clear, clearLocalCache, createState (+13 more)

### Community 179 - "Audit Screen"
Cohesion: 0.04
Nodes (47): bool get, AuditDetailDialog, AuditScreen, _AuditScreenState, build, createState, _entity, entry (+39 more)

### Community 180 - "Purchase Order Entities"
Cohesion: 0.03
Nodes (65): DateTimeOffset, List, BidStatus, Approved, Pending, Rejected, PurchaseOrder, ClosedAt (+57 more)

### Community 181 - "Steel Endpoints"
Cohesion: 0.19
Nodes (14): DateOnly, DateTimeOffset, Expression, IServiceCollection, WebApplication, SlitterJobIn, SlitterJobOut, SteelEndpoints (+6 more)

### Community 182 - "Fiscal Product Policies"
Cohesion: 0.15
Nodes (15): ebt_api_infrastructure_crud, Key, microsoft_aspnetcore_authorization, Policy, FiscalPolicies, ProductCustomerIn, CancellationToken, IReadOnlyList (+7 more)

### Community 183 - "Legacy Cleanup Screen"
Cohesion: 0.10
Nodes (20): _applyProcess, _applyStale, build, _busy, _call, createState, _days, _daysValue (+12 more)

### Community 184 - "App Preferences"
Cohesion: 0.22
Nodes (8): AppPrefs, appVersion, printPrompts, rowsPerPage, rowsPerPageChoices, static bool, static const, static int

### Community 185 - "Login Screen"
Cohesion: 0.07
Nodes (28): build, _busy, _capsLock, _capsLockHint, _clearError, createState, dispose, _error (+20 more)

### Community 187 - "Operations & Backup Docs"
Cohesion: 0.22
Nodes (8): Automatic backup (set in the app), Backups, Behind a reverse proxy, Logs, MetaGest operations, Restart behavior, Restore, Secrets to rotate before real use

### Community 188 - "Customers Tests"
Cohesion: 0.12
Nodes (15): _address, addresses, answer, _customer, _Env, _json, log, main (+7 more)

### Community 189 - "NF-e Key Generation"
Cohesion: 0.31
Nodes (4): DateTimeOffset, IReadOnlyDictionary, NfeKey, NfeKeyTests

### Community 190 - "Delivery Endpoints"
Cohesion: 0.20
Nodes (9): Delivery, CancellationToken, DateOnly, Task, CancellationToken, Func, Task, CancellationToken (+1 more)

### Community 191 - "Quote Expiry Service"
Cohesion: 0.24
Nodes (9): BackgroundService, Request lifecycle, IServiceScopeFactory, PeriodicTimer, CancellationToken, ILogger, Task, TimeSpan (+1 more)

### Community 193 - "Audit Log Endpoints"
Cohesion: 0.18
Nodes (10): WebApplication, DateTimeOffset, AuditEntry, Action, At, Changes, Entity, EntityId (+2 more)

### Community 194 - "Data Source Maintenance"
Cohesion: 0.20
Nodes (12): ISourceFlagger, CancellationToken, Dictionary, Func, IQueryable, List, Task, DataSourceCount (+4 more)

### Community 195 - "Product Entity"
Cohesion: 0.09
Nodes (22): Product, Blocked, Code, Customers, DiameterMm, DrawingRevision, HeightMm, Id (+14 more)

### Community 197 - "Dashboard Tests"
Cohesion: 0.31
Nodes (6): OpenOrdersSummaryOut, DateOnly, Fact, JsonElement, Task, DashboardTests

### Community 201 - "BOM Item Entity"
Cohesion: 0.18
Nodes (11): BomItem, ComponentProduct, ComponentProductId, Factor, Id, Material, MaterialId, Quantity (+3 more)

### Community 206 - "Low Stock Service"
Cohesion: 0.29
Nodes (6): CancellationToken, IReadOnlyCollection, List, Task, LowStock, LowStockRow

### Community 207 - "Customer Product API Tests"
Cohesion: 0.14
Nodes (18): CustomerAddressIn, CustomerIn, ProductIn, ProductKind, Part, TubeShape, Circular, Rectangular (+10 more)

### Community 213 - "Material Cost Averages"
Cohesion: 0.12
Nodes (16): AverageCost, Average, AverageGross, Id, Imported, Material, MaterialId, MonthAverage (+8 more)

### Community 214 - "Stock Movement Types"
Cohesion: 0.12
Nodes (16): MovementType, AdjustmentIn, AdjustmentOut, CustomerReturn, IndirectIssue, InventoryCount, Issue, OpeningBalance (+8 more)

### Community 217 - "API Test Infrastructure"
Cohesion: 0.12
Nodes (15): ICollectionFixture, microsoft_aspnetcore_diagnostics, microsoft_aspnetcore_hosting, microsoft_aspnetcore_httpoverrides, microsoft_aspnetcore_mvc_testing, microsoft_aspnetcore_testhost, microsoft_extensions_dependencyinjection, microsoft_openapi (+7 more)

### Community 218 - "Page Layout Tests"
Cohesion: 0.10
Nodes (19): build, child, maxWidth, _host, main, api, build, createState (+11 more)

### Community 219 - "Product Customer Pricing"
Cohesion: 0.11
Nodes (20): Customer, Product, ProductCustomer, Active, Customer, CustomerDescription, CustomerId, CustomerPartNumber (+12 more)

### Community 222 - "CLAUDE Project Docs"
Cohesion: 0.15
Nodes (12): CLAUDE.md — MetaGest, Dev setup, Features built, Fiscal / NF, Flutter conventions, Gotchas, graphify, Migrations (+4 more)

### Community 223 - "Fiscal Inutilization Entity"
Cohesion: 0.15
Nodes (13): DateTimeOffset, FiscalInutilization, CreatedAt, CreatedBy, Environment, FromNumber, Id, Protocol (+5 more)

### Community 224 - "System Backup Endpoints"
Cohesion: 0.20
Nodes (8): AssemblyInformationalVersionAttribute, BackupSettings, CancellationToken, DateTimeOffset, Task, WebApplication, BackupStatusFile, SystemEndpoints

### Community 225 - "Legacy Table Discovery"
Cohesion: 0.18
Nodes (8): Tables, GeneratedRegex, IReadOnlyList, Regex, LegacyTable, Control, Control, Dictionary

### Community 226 - "Data Reset Scopes"
Cohesion: 0.18
Nodes (10): microsoft_entityframeworkcore_storage, IReadOnlyList, DataResetOut, ResetScope, Production, Purchasing, Sales, Stock (+2 more)

### Community 227 - "Quote Status Enum"
Cohesion: 0.18
Nodes (11): QuoteStatus, Accepted, Approved, Cancelled, Converted, Draft, Expired, PendingApproval (+3 more)

### Community 228 - "Backup Settings Tests UI"
Cohesion: 0.14
Nodes (13): client, current, ensureVisible, _json, log, main, pumpAndSettle, pumpWidget (+5 more)

### Community 230 - "DBF Stock Import Options"
Cohesion: 0.22
Nodes (9): DateOnly, StockImportOptions, CodePage, Directory, DryRun, OpeningDate, OwnLocation, ThirdPartyLocation (+1 more)

### Community 237 - "Sales Exception Handler"
Cohesion: 0.20
Nodes (7): MVC mapping, IServiceCollection, Exception, HttpContext, IServiceCollection, ValueTask, SalesExceptionHandler

### Community 238 - "Inventory Endpoints"
Cohesion: 0.22
Nodes (6): CancellationToken, ClaimsPrincipal, Expression, StockSettings, Task, InventoryEndpoints

### Community 245 - "JWT Configuration"
Cohesion: 0.25
Nodes (8): JwtOptions, Audience, ClockSkewSeconds, ExpiresMinutes, Issuer, RefreshDays, RefreshReuseGraceSeconds, SigningKey

### Community 250 - "Data Source Marker"
Cohesion: 0.33
Nodes (6): DataSource, Imported, Manual, Test, IHasSource, Source

### Community 252 - "Search Tests"
Cohesion: 0.52
Nodes (3): Fact, Task, SearchTests

### Community 253 - "Backup Frequency"
Cohesion: 0.33
Nodes (5): BackupFrequency, Daily, Every6Hours, Hourly, Weekly

### Community 254 - "Backup Schedule"
Cohesion: 0.47
Nodes (4): DateTimeOffset, DayOfWeek, TimeOnly, BackupSchedule

### Community 255 - "Auth Infrastructure"
Cohesion: 0.20
Nodes (9): microsoft_aspnetcore_authentication_jwtbearer, microsoft_aspnetcore_identity, microsoft_identitymodel_tokens, ActivityRequest, ChangePasswordRequest, Policies, system_identitymodel_tokens_jwt, system_net_mail (+1 more)

### Community 260 - "Audit Endpoints"
Cohesion: 0.25
Nodes (7): IHttpContextAccessor, DateTimeOffset, WebApplication, AuditEndpoints, AuditOut, HttpCurrentUser, Name

### Community 264 - "Backup Agent Script"
Cohesion: 0.60
Nodes (5): Get-Instant(), Get-NextDue(), Invoke-Agent(), Invoke-Sql(), Test-Destination()

### Community 275 - "Certificate Templates Tests"
Cohesion: 0.06
Nodes (30): _certificate, client, _json, log, main, pumpAndSettle, pumpWidget, session (+22 more)

### Community 340 - "Workdays Dart"
Cohesion: 0.10
Nodes (20): a, addWorkDays, d, day, _easter, goodFriday, h, _holidayCache (+12 more)

### Community 343 - "Purchase Orders Screen"
Cohesion: 0.05
Nodes (42): active, api, base, _busy, createState, d, dispose, _error (+34 more)

### Community 349 - "WorkDays Service"
Cohesion: 0.23
Nodes (6): DateOnly, WorkDays, Fact, WorkDaysParityTests, Fact, WorkDaysTests

## Knowledge Gaps
- **4280 isolated node(s):** `EmployeeIn`, `OperationDetailsIn`, `ProductionPolicies`, `SalesPolicies`, `CertificatePolicies` (+4275 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 4816 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **56 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AuditInterceptor` connect `Save Changes Interceptor` to `Graph Report Navigation`, `EF Core Namespace Imports`?**
  _High betweenness centrality (0.364) - this node is a cross-community bridge._
- **Why does `Suggested Questions` connect `Graph Report Navigation` to `Certificate Endpoints DI`, `EF Core DB Context`, `Purchasing Endpoints`, `Fiscal Document Line`, `Stock Service Endpoints`, `Purchase Quotations Endpoints`, `Work Center Entities`, `Production Order Kinds`, `Product Revision Entity`, `Routing Operation Entities`, `Save Changes Interceptor`, `DBF Import Utilities`, `Production DB Config`, `Sales Order Line Entities`, `Purchasing DB Config`, `Audit Log Endpoints`, `Data Source Maintenance`, `Customer Entity`, `Purchasing DI Setup`, `Stock Balance Entity`, `BOM Item Entity`, `Inventory DB Config`, `Production Service Logic`, `Quality Certificate Entities`, `Auth Password Service`, `Material Cost Averages`, `Customer Address Entity`, `Row Version Filter`, `Generic CRUD Mapping`, `Steel DB Config`, `Fiscal Service Handlers`, `Sales DB Config`, `Fiscal DB Config`, `Purchase Requisition Entity`, `Supplier Address Entity`, `SEFAZ HTTP Client`, `Sales Service Logic`?**
  _High betweenness centrality (0.360) - this node is a cross-community bridge._
- **Why does `_Entry` connect `Save Changes Interceptor` to `Command Palette Widget`?**
  _High betweenness centrality (0.357) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `EbtDbContext` (e.g. with `Backend conventions` and `Audit findings (coupling and bottlenecks)`) actually correct?**
  _`EbtDbContext` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `EmployeeIn`, `OperationDetailsIn`, `ProductionPolicies` to the rest of the system?**
  _4280 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Entity DTO Columns` be split into smaller, more focused modules?**
  _Cohesion score 0.023255813953488372 - nodes in this community are weakly interconnected._
- **Should `EF Core DB Context` be split into smaller, more focused modules?**
  _Cohesion score 0.02036931277365315 - nodes in this community are weakly interconnected._