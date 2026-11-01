# MetaGest architecture

MetaGest is a layered system that already follows the MVC separation. This file maps each layer to its MVC role, shows how a request flows, and records the audit findings. Engineering conventions for contributors are in `CLAUDE.md`; operations notes are in `docs/OPERATIONS.md`.

## Why there is no MVC folder move

The code base was audited before this document was written. The backend is an ASP.NET Core **minimal API** with a separate domain library. It has no `Controllers/` or `Views/` folders, but the three MVC responsibilities are already isolated in separate projects and folders. Moving files into `models/`, `controllers/` and `views/` would:

- break namespaces, EF migrations (`Ebt.Core.Data.Migrations`), the test project and the Dockerfile for no behavior gain;
- conflict with the rule "minimal disruption to imports, configuration and environment variables".

So the structure stays, and the table below is the official mapping.

## MVC mapping

| MVC role | Where it lives | Responsibility |
|---|---|---|
| **Model** | `src/Ebt.Core/Entities/` | EF entities and enums (`Quote`, `SalesOrder`, `ProductionOrder`, `StockLot`, `FiscalDocument`, `QualityCertificate`...) |
| **Model** | `src/Ebt.Core/Data/` | `EbtDbContext` (partial class, one file per module), EF migrations, audit interceptor |
| **Model (business logic)** | `src/Ebt.Core/{Sales,Production,Purchasing,Inventory,Fiscal,Certificates,Viability,Maintenance,Services}/` | Domain services: `SalesService`, `ProductionService`, `PurchasingService`, `StockService`, `FiscalService`, `CertificateService`, `BomService`. Rules, workflows, transactions. |
| **Controller** | `src/Ebt.Api/Endpoints/*.cs` | One static class per module. Maps routes, binds and validates input, checks policy, calls one service, returns a DTO. No business rules. |
| **Controller (shared)** | `src/Ebt.Api/Infrastructure/` | `Crud.cs` generic CRUD, `Access.cs` permission matrix, `Auth.cs`, `Errors.cs` exception-to-HTTP mapping, `RowVersionFilter.cs` (ETag / `If-Match`) |
| **View (API presenter)** | DTO records declared next to each endpoint, plus `*Models.cs` in each core module (e.g. `Sales/SalesModels.cs`) | Shape of the JSON sent to clients. Entities are not returned directly. |
| **View (UI)** | `clients/flutter/lib/screens/`, `widgets/` | Flutter screens and reusable widgets (Windows, Android, Web) |
| **View (documents)** | `clients/flutter/lib/reports/` | PDF builders: quote, order, OF, delivery, NF, certificate |
| **Client model/controller** | `clients/flutter/lib/{api,entities,session,labels}.dart` | HTTP client, DTO classes, signed-in state, pt-BR labels |
| Composition | `src/Ebt.Api/Program.cs` | DI registration (`AddSales()`, `AddProduction()`...), auth, rate limit, middleware |
| Legacy import | `src/Ebt.DbfImport/` | CLI that loads the old DBF data through `IImportStep` steps |

Dependency direction: `Ebt.Api` -> `Ebt.Core`. `Ebt.Core` never references `Ebt.Api`. The Flutter client talks to the API over HTTP only.

## Request lifecycle

```
Flutter screen
  -> api.dart (adds bearer token, If-Match ETag)
  -> HTTP  /api/...
  -> Program.cs middleware: HTTPS/HSTS, rate limit, JWT validation, token-version check
  -> Endpoints/<Module>Endpoints.cs      (controller)
       - policy from Access.cs           (401 / 403)
       - bind + validate input           (400)
       - RowVersionFilter                (412 on stale ETag)
  -> Ebt.Core service                    (model logic, one DB transaction)
       - EbtDbContext + AuditInterceptor (writes audit_log)
       - PostgreSQL 16
  -> DTO projection                      (view)
  -> JSON response + ETag
  -> Errors.cs maps exceptions: StockException / DatabaseException -> 409, 422, 400
  -> entities.dart -> screen state -> widget tree / PDF
```

Background work: `QuoteExpiryService` (hosted service, every 10 minutes) expires quotes and returns stale discount approvals to draft.

## Data flow of the sales chain

```
Quote -> (approve) -> customer PO -> SalesOrder -> ProductionOrder (OF)
      -> QualityCertificate -> Delivery -> FiscalDocument (NF-e)
```

Each arrow is a method on a core service. Endpoints only trigger them. Stock moves through `StockService` documents. Fiscal emission goes through `ISefazClient` (`StubSefazClient` by default, `SefazSpClient` when configured).

## Permissions

All role checks live in `src/Ebt.Api/Infrastructure/Access.cs`. Login and `GET /api/auth/me` return the caller's permission names; the Flutter client reads them. `AccessParityTests` fails when the client mirror drifts from the matrix.

## Audit findings (coupling and bottlenecks)

1. **`EbtDbContext` is the hub** (247 graph edges). Every module depends on it. Mitigated by the partial-class split per module. A repository layer would add code but no isolation today.
2. **Large services**: `SalesService` (72 edges) and `ProductionService` (61) are the biggest. Both are already split into partial files (`SalesService.Quotes.cs`, `.Orders.cs`, `.Deliveries.cs`, `ProductionService.ShopFloor.cs`). Next split candidates follow the same seam.
3. **DTOs declared inside endpoint files** couple the presenter to the controller file. Acceptable now; move to `*Models.cs` when a DTO is shared by two endpoints.
4. **Entities double as a few response shapes** in the generic CRUD (`CrudSpec<TEntity, TIn, TOut>` keeps `TOut` separate, so this is limited to old endpoints).
5. **No import cycles** between modules (graph check).
6. **Client mirrors server rules** in two places: `workdays.dart` vs `WorkDays.cs`, and `role_permissions.dart` vs `Access.cs`. Parity tests cover permissions; work days have no parity test.

## Knowledge graph

See the "Knowledge graph (Graphify)" section in `README.md` for how to build and query the graph, and the current god nodes.
