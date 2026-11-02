using System.Text.RegularExpressions;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Fiscal;

/// <summary>
/// NF-e emission, pending-first: the number is reserved and the document committed as Pending (on its own connection) before SEFAZ is called, and the
/// answer is committed the same way, so a crash or lost answer never loses track of a number. A definite rejection gives the number back when possible.
/// Callers lower stock and update the delivery/shipment in their own transaction; only the lines and the link are written there.
/// </summary>
public sealed class FiscalService(EbtDbContext db, ISefazClient sefaz, DbContextOptions<EbtDbContext> options)
{
    private static readonly string[] IcmsCalculated = ["00", "20"];
    private static readonly string[] IpiCalculated = ["00", "49", "50", "99"];
    private static readonly string[] PisCofinsCalculated = ["01", "02"];
    private static readonly TimeSpan BrazilOffset = TimeSpan.FromHours(-3);

    public async Task<FiscalSettings> SettingsAsync(CancellationToken ct = default) =>
        await db.FiscalSettings.FirstOrDefaultAsync(ct) ?? throw new InvalidOperationException("fiscal_settings row missing");

    public async Task<bool> EnabledAsync(CancellationToken ct = default) => await db.FiscalSettings.AsNoTracking().Select(s => s.Enabled).FirstOrDefaultAsync(ct);

    public async Task<decimal?> MonthlyPriceAsync(int productId, int customerId, string cfop, int year, int month, CancellationToken ct = default) =>
        await db.MonthlyPrices.AsNoTracking().Where(p => p.ProductId == productId && p.CustomerId == customerId && p.CfopCode == cfop && p.Year == year && p.Month == month)
            .Select(p => (decimal?)p.UnitPrice).FirstOrDefaultAsync(ct);

    /// <summary>Venda (default CFOP 5101) for a delivery being shipped. Needs the order and delivery lines loaded.</summary>
    public async Task<FiscalDocument> IssueSaleAsync(Delivery delivery, SalesOrder order, SaleInvoiceOptions opt, string? user, CancellationToken ct = default)
    {
        return await InTransaction(async () =>
        {
            var settings = await ReadSettingsAsync(ct);
            RequireIssuer(settings);
            var customer = await db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == order.CustomerId, ct) ?? throw FiscalException.NotFound("Customer");
            var address = await db.CustomerAddresses.AsNoTracking().FirstOrDefaultAsync(a => a.Id == delivery.AddressId, ct) ?? throw FiscalException.NotFound("Delivery address");
            var cfop = await CfopAsync(opt.Cfop ?? Clean(address.DefaultCfop) ?? "5101", FiscalKind.Sale, ct);
            var recipient = new NfeParty(customer.Name, address.Document, address.StateRegistration, address.IcmsContributor, address.Street, address.Number, address.Complement, address.District, address.City, address.CityIbgeCode, address.Uf, address.ZipCode, address.Email ?? customer.Email, address.Phone);
            RequireRecipient(recipient, $"customer {customer.Name} (address {address.Id})");
            var interstate = RequireOperationScope(cfop, settings, recipient.Uf);

            var issuedAt = DateTimeOffset.UtcNow;
            var local = issuedAt.ToOffset(BrazilOffset);
            var productIds = delivery.Lines.Select(l => order.Lines.First(x => x.Id == l.OrderLineId).ProductId).Distinct().ToList();
            var products = await db.Products.AsNoTracking().Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, ct);
            var rules = await db.TaxRules.AsNoTracking().Where(r => r.CfopCode == cfop.Code && productIds.Contains(r.ProductId) && (r.CustomerId == customer.Id || r.CustomerId == null)).ToListAsync(ct);

            var doc = NewDocument(settings, cfop, FiscalKind.Sale, issuedAt, user, recipient, customerId: customer.Id, supplierId: null);
            doc.DeliveryId = delivery.Id;
            foreach (var (dl, n) in delivery.Lines.Select((dl, n) => (dl, n)))
            {
                var ol = order.Lines.First(x => x.Id == dl.OrderLineId);
                var p = products[ol.ProductId];
                var price = await MonthlyPriceAsync(p.Id, customer.Id, cfop.Code, local.Year, local.Month, ct)
                    ?? throw FiscalException.Blocked($"No monthly price for {p.Code} / {customer.Name} / CFOP {cfop.Code} in {local.Month:00}/{local.Year}; register it in the monthly price table before issuing the NF");
                var rule = rules.Where(r => r.ProductId == p.Id).OrderBy(r => r.CustomerId == null).FirstOrDefault();
                doc.Lines.Add(new FiscalDocumentLine
                {
                    Sequence = (n + 1) * 10, ProductId = p.Id, ProductionOrderId = ol.ProductionOrderId, Code = p.Code, Description = ol.Description, Ncm = RequireNcm(p), Unit = p.StockUnit,
                    Quantity = dl.Quantity, UnitPrice = price, Total = Money(dl.Quantity * price),
                    IcmsCst = "", IpiCst = "", PisCst = "", CofinsCst = ""
                }.WithRates(cfop, rule, ol.IcmsPercent, ol.IpiPercent));
            }
            doc.ProductsTotal = doc.Lines.Sum(l => l.Total);
            doc.FreightTotal = Money(opt.Freight);
            if (doc.FreightTotal < 0) throw FiscalException.Invalid("freight", "Cannot be negative");
            AllocateFreight(doc);
            CalculateTaxes(doc, cfop, customerIcmsContributor: recipient.IcmsContributor);
            doc.Installments = cfop.GeneratesInstallments ? await InstallmentsAsync(order, customer, doc.InvoiceTotal, local, ct) : [];

            var ofIds = doc.Lines.Where(l => l.ProductionOrderId != null).Select(l => l.ProductionOrderId!.Value).ToList();
            var ofs = await db.ProductionOrders.AsNoTracking().Where(o => ofIds.Contains(o.Id)).Select(o => o.Reference).ToListAsync(ct);
            doc.AdditionalInfo = Join(order.Reference, $"Entrega ({delivery.Reference})", ofs.Count > 0 ? string.Join(", ", ofs) : null, order.CustomerPo is { } po ? $"Pedido cliente {po}" : null, delivery.Notes, cfop.LegalText);
            var transport = new NfeTransport(order.Freight == FreightTerms.Cif ? 0 : 1, opt.Carrier ?? delivery.Carrier, opt.VehiclePlate ?? delivery.VehiclePlate, delivery.Packages, opt.GrossWeightKg ?? delivery.GrossWeightKg);

            // A shipment that failed after SEFAZ authorized its NF was rolled back, but the authorized NF (committed on its own connection) stayed without a delivery.
            // Shipping again must pick that NF up, not issue a second one for the same goods.
            var marker = $"({delivery.Reference})";
            var orphan = await db.FiscalDocuments.FirstOrDefaultAsync(f => f.Kind == FiscalKind.Sale && f.Status == FiscalStatus.Authorized && f.DeliveryId == null
                && f.CustomerId == customer.Id && f.AdditionalInfo != null && f.AdditionalInfo.Contains(marker), ct);
            if (orphan is not null)
            {
                if (orphan.InvoiceTotal != doc.InvoiceTotal)
                    throw FiscalException.Conflict($"NF {orphan.Number} was authorized for {delivery.Reference} but never linked to it, and its total ({orphan.InvoiceTotal:0.00}) differs from this shipment ({doc.InvoiceTotal:0.00}). Cancel that NF before shipping again");
                orphan.DeliveryId = delivery.Id;
                foreach (var l in doc.Lines) orphan.Lines.Add(l);
                foreach (var i in doc.Installments) orphan.Installments.Add(i);
                await db.SaveChangesAsync(ct);
                return orphan;
            }
            return await AuthorizeAndSaveAsync(settings, doc, cfop, recipient, transport, interstate, ct);
        }, ct);
    }

    /// <summary>Remessa para industrialização (default CFOP 5901) for an outside-processing shipment already saved (has an Id).</summary>
    public async Task<FiscalDocument> IssueOutsideShipmentAsync(OutsideShipment shipment, ProductionOrder order, ProductionOrderOperation operation, OutsideInvoiceOptions opt, string? user, CancellationToken ct = default)
    {
        if (opt.UnitValue <= 0) throw FiscalException.Invalid("unitValue", "Give the reference unit value of the pieces sent");
        return await InTransaction(async () =>
        {
            var settings = await ReadSettingsAsync(ct);
            RequireIssuer(settings);
            var supplier = await db.Suppliers.AsNoTracking().Include(s => s.Addresses).FirstOrDefaultAsync(s => s.Id == shipment.SupplierId, ct) ?? throw FiscalException.NotFound("Supplier");
            var a = supplier.Addresses.Where(x => !string.IsNullOrWhiteSpace(x.Document)).OrderBy(x => x.Id).FirstOrDefault()
                ?? throw FiscalException.Blocked($"Supplier {supplier.Name} has no address with CNPJ; register it before sending to outside processing");
            var cfop = await CfopAsync(opt.Cfop ?? "5901", FiscalKind.OutsideShipment, ct);
            var recipient = new NfeParty(supplier.Name, a.Document!, a.StateRegistration, !string.IsNullOrWhiteSpace(a.StateRegistration), a.Street, a.Number, null, a.District, a.City, a.CityIbgeCode, a.Uf, a.ZipCode, a.Email, a.Phone);
            RequireRecipient(recipient, $"supplier {supplier.Name}");
            var interstate = RequireOperationScope(cfop, settings, recipient.Uf);

            var product = await db.Products.AsNoTracking().FirstAsync(p => p.Id == order.ProductId, ct);
            var issuedAt = DateTimeOffset.UtcNow;
            var doc = NewDocument(settings, cfop, FiscalKind.OutsideShipment, issuedAt, user, recipient, customerId: null, supplierId: supplier.Id);
            doc.OutsideShipmentId = shipment.Id;
            doc.Lines.Add(new FiscalDocumentLine
            {
                Sequence = 10, ProductId = product.Id, ProductionOrderId = order.Id, Code = product.Code, Description = $"{Clean(operation.Description)?.ToUpperInvariant() ?? "INDUSTRIALIZACAO"} - APLICADO EM {product.Code}",
                Ncm = RequireNcm(product), Unit = product.StockUnit, Quantity = shipment.Quantity, UnitPrice = opt.UnitValue, Total = Money(shipment.Quantity * opt.UnitValue),
                IcmsCst = "", IpiCst = "", PisCst = "", CofinsCst = ""
            }.WithRates(cfop, null, 0m, 0m));
            doc.ProductsTotal = doc.Lines.Sum(l => l.Total);
            CalculateTaxes(doc, cfop, customerIcmsContributor: false);
            doc.AdditionalInfo = Join(order.Reference, $"Operação {operation.Sequence}", shipment.Notes, cfop.LegalText);
            return await AuthorizeAndSaveAsync(settings, doc, cfop, recipient, new NfeTransport(9, null, null, 0, null), interstate, ct);
        }, ct);
    }

    /// <summary>Cancels an authorized NF at SEFAZ and records it. Sale NFs must be cancelled through <c>SalesService.CancelInvoiceAsync</c>, which also reverses the delivery.</summary>
    public async Task<FiscalDocument> CancelAsync(int id, string? reason, string? user, CancellationToken ct = default)
    {
        var why = Clean(reason);
        if (why is null || why.Length < 15) throw FiscalException.Invalid("reason", "Give the reason for the cancellation (at least 15 characters, SEFAZ rule)");
        return await InTransaction(async () =>
        {
            var settings = await ReadSettingsAsync(ct);
            var doc = await db.FiscalDocuments.FirstOrDefaultAsync(d => d.Id == id, ct) ?? throw FiscalException.NotFound("NF");
            if (doc.Status != FiscalStatus.Authorized) throw FiscalException.Conflict($"NF {doc.Number} is {doc.Status}");
            if (settings.CancelWindowHours > 0 && DateTimeOffset.UtcNow - doc.IssuedAt > TimeSpan.FromHours(settings.CancelWindowHours))
                throw FiscalException.Conflict($"NF {doc.Number} was issued more than {settings.CancelWindowHours}h ago; SEFAZ no longer accepts the cancellation, issue a return NF instead");
            OutsideShipment? shipment = null;
            if (doc.OutsideShipmentId is { } sid)
            {
                shipment = await db.OutsideShipments.FirstAsync(s => s.Id == sid, ct);
                if (shipment.ReturnedQuantity + shipment.ScrapQuantity > 0)
                    throw FiscalException.Conflict($"NF {doc.Number} has a processing return ({shipment.ReturnedQuantity + shipment.ScrapQuantity:0.####} received); undo the return before cancelling it");
            }
            // Contas a pagar: no abatement/deduction record exists in this system yet, so there is nothing else to check here.
            var verdict = await sefaz.CancelAsync(doc.AccessKey, doc.Protocol, why, doc.Environment, ct);
            if (!verdict.Authorized) throw FiscalException.Rejected(verdict.Status, verdict.Message);
            doc.Status = FiscalStatus.Cancelled;
            doc.CancelledAt = DateTimeOffset.UtcNow;
            doc.CancelledBy = user;
            doc.CancelReason = why;
            doc.CancelProtocol = verdict.Protocol;
            if (shipment is not null) shipment.InvoiceNumber = null;
            await db.SaveChangesAsync(ct);
            return doc;
        }, ct);
    }

    /// <summary>
    /// Pending-first emission. 1) the layout is validated with the provisional number (a bad layout burns nothing); 2) on its own connection the number is
    /// reserved and the document saved as Pending, committed before SEFAZ is called, holding the fiscal_settings lock only for that short transaction;
    /// 3) SEFAZ is called with no lock held; 4) the answer is committed on its own connection too: Authorized, or the reservation is released/kept as Rejected.
    /// A lost answer leaves the document Pending for <see cref="ReconcileAsync"/>. The caller's own transaction only receives the lines and the delivery/shipment link.
    /// </summary>
    private async Task<FiscalDocument> AuthorizeAndSaveAsync(FiscalSettings settings, FiscalDocument doc, Cfop cfop, NfeParty recipient, NfeTransport transport, bool interstate, CancellationToken ct)
    {
        NfeSchema.ValidateNfe(NfeXml.Build(settings, doc, cfop, recipient, transport, interstate));
        await ReserveAsync(doc, cfop, recipient, transport, interstate, ct);

        SefazResult verdict;
        try { verdict = await sefaz.AuthorizeAsync(doc.AccessKey, doc.Xml, doc.Environment, ct); }
        catch (Exception e)
        {
            await NoteAsync(doc.Id, $"SEFAZ answer unknown: {e.Message}");
            throw;
        }
        if (!verdict.Authorized)
        {
            var denied = verdict.Status is "110" or "301" or "302" or "303";
            await ReleaseOrRejectAsync(doc.Id, verdict.Status, verdict.Message, reusable: !denied, ct);
            throw FiscalException.Rejected(verdict.Status, verdict.Message);
        }
        if (verdict.Protocol is null)
        {
            await NoteAsync(doc.Id, "SEFAZ authorized without a protocol; reconcile it");
            throw new InvalidOperationException("SEFAZ authorized without a protocol");
        }
        await using (var c = new EbtDbContext(options))
        {
            var done = await c.FiscalDocuments.FirstAsync(d => d.Id == doc.Id, CancellationToken.None);
            done.Status = FiscalStatus.Authorized;
            done.Protocol = verdict.Protocol;
            done.Simulated = verdict.Simulated;
            done.StatusMessage = null;
            if (verdict.AuthorizedXml is { } authorizedXml) done.Xml = authorizedXml;
            await c.SaveChangesAsync(CancellationToken.None);
        }
        // Back in the caller's transaction: attach the lines and link the delivery/shipment to the already authorized row.
        var row = await db.FiscalDocuments.FirstAsync(d => d.Id == doc.Id, ct);
        row.DeliveryId = doc.DeliveryId;
        row.OutsideShipmentId = doc.OutsideShipmentId;
        foreach (var l in doc.Lines) row.Lines.Add(l);
        foreach (var i in doc.Installments) row.Installments.Add(i);
        await db.SaveChangesAsync(ct);
        return row;
    }

    private async Task ReserveAsync(FiscalDocument doc, Cfop cfop, NfeParty recipient, NfeTransport transport, bool interstate, CancellationToken ct)
    {
        await using var c = new EbtDbContext(options);
        await using var tx = await c.Database.BeginTransactionAsync(ct);
        var s = await LockSettingsAsync(c, ct);
        RequireIssuer(s);
        doc.Series = s.Series;
        doc.Number = s.NextNumber;
        doc.Environment = s.Environment;
        doc.AccessKey = NfeKey.Build(NfeKey.UfCodes[s.Uf], doc.IssuedAt.ToOffset(BrazilOffset), s.Cnpj!, s.Series, doc.Number, NfeKey.NewCodeNumber(doc.Number));
        doc.Xml = NfeXml.Build(s, doc, cfop, recipient, transport, interstate);
        NfeSchema.ValidateNfe(doc.Xml);
        // Only the header is saved now (no links to rows the caller may hold locked); lines and links follow once SEFAZ authorizes.
        var shell = new FiscalDocument
        {
            Kind = doc.Kind, Status = FiscalStatus.Pending, CfopCode = doc.CfopCode, Series = doc.Series, Number = doc.Number, AccessKey = doc.AccessKey, Environment = doc.Environment, Simulated = sefaz.IsSimulated, Protocol = "", IssuedAt = doc.IssuedAt,
            IssuedBy = doc.IssuedBy, CustomerId = doc.CustomerId, SupplierId = doc.SupplierId, RecipientName = doc.RecipientName, RecipientDocument = doc.RecipientDocument, RecipientUf = doc.RecipientUf,
            ProductsTotal = doc.ProductsTotal, FreightTotal = doc.FreightTotal, IcmsBase = doc.IcmsBase, IcmsTotal = doc.IcmsTotal, IpiTotal = doc.IpiTotal, PisTotal = doc.PisTotal, CofinsTotal = doc.CofinsTotal,
            InvoiceTotal = doc.InvoiceTotal, AdditionalInfo = doc.AdditionalInfo, Xml = doc.Xml
        };
        c.FiscalDocuments.Add(shell);
        s.NextNumber = doc.Number + 1;
        await c.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        doc.Id = shell.Id;
    }

    private async Task NoteAsync(int id, string message)
    {
        await using var c = new EbtDbContext(options);
        var row = await c.FiscalDocuments.FirstAsync(d => d.Id == id, CancellationToken.None);
        row.StatusMessage = Cut(message, 500);
        await c.SaveChangesAsync(CancellationToken.None);
    }

    /// <summary>A definite refusal: the number goes back to <c>next_number</c> when nobody took a later one (and SEFAZ did not deny the NF); otherwise the row stays Rejected, a gap for inutilização.</summary>
    private async Task<bool> ReleaseOrRejectAsync(int id, string status, string message, bool reusable, CancellationToken ct)
    {
        await using var c = new EbtDbContext(options);
        await using var tx = await c.Database.BeginTransactionAsync(ct);
        var s = await LockSettingsAsync(c, ct);
        var row = await c.FiscalDocuments.FirstAsync(d => d.Id == id, ct);
        var release = reusable && row.Status == FiscalStatus.Pending && s.Series == row.Series && s.NextNumber == row.Number + 1;
        if (release)
        {
            s.NextNumber = row.Number;
            c.FiscalDocuments.Remove(row);
        }
        else if (row.Status == FiscalStatus.Pending)
        {
            row.Status = FiscalStatus.Rejected;
            row.StatusMessage = Cut($"SEFAZ {status}: {message}", 500);
        }
        await c.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return release;
    }

    /// <summary>
    /// Gives up the numbers <paramref name="from"/>..<paramref name="to"/> for good (inutilização, SEFAZ rule: reason of at least 15 characters). Only numbers that were already
    /// issued (below <c>next_number</c>) and have no live NF are accepted: Rejected documents and holes left by a crash. Pending, Authorized and Cancelled numbers are refused.
    /// </summary>
    public async Task<FiscalInutilization> InutilizeAsync(int? series, int from, int to, string? reason, string? user, CancellationToken ct = default)
    {
        var why = Clean(reason);
        if (why is null || why.Length < 15) throw FiscalException.Invalid("reason", "Give the reason (at least 15 characters, SEFAZ rule)");
        if (why.Length > 255) throw FiscalException.Invalid("reason", "At most 255 characters");
        if (from < 1) throw FiscalException.Invalid("from", "Must be 1 or more");
        if (to < from) throw FiscalException.Invalid("to", "Must not be smaller than the first number");
        if (to - from >= 1000) throw FiscalException.Invalid("to", "At most 1000 numbers per request");
        var settings = await ReadSettingsAsync(ct);
        RequireIssuer(settings);
        var serie = series ?? settings.Series;
        if (serie is < 1 or > 999) throw FiscalException.Invalid("series", "Between 1 and 999");
        if (serie == settings.Series && to >= settings.NextNumber)
            throw FiscalException.Conflict($"Number {to} was not issued yet (next number is {settings.NextNumber}); only numbers already skipped can be inutilized");

        var used = await db.FiscalDocuments.AsNoTracking().Where(d => d.Series == serie && d.Number >= from && d.Number <= to && d.Status != FiscalStatus.Rejected)
            .OrderBy(d => d.Number).Select(d => new { d.Number, d.Status }).FirstOrDefaultAsync(ct);
        if (used is not null) throw FiscalException.Conflict($"NF {used.Number} is {used.Status}; only Rejected or missing numbers can be inutilized");
        if (await db.FiscalInutilizations.AnyAsync(i => i.Series == serie && i.FromNumber <= to && i.ToNumber >= from, ct))
            throw FiscalException.Conflict("Part of this range was already inutilized");

        var now = DateTimeOffset.UtcNow;
        var xml = NfeInut.Build(settings, now, serie, from, to, why, settings.Environment);
        NfeSchema.ValidateInutilizacao(xml);
        var verdict = await sefaz.InutilizeAsync(xml, settings.Environment, ct);
        if (!verdict.Authorized) throw FiscalException.Rejected(verdict.Status, verdict.Message);

        var record = new FiscalInutilization
        {
            Series = serie, FromNumber = from, ToNumber = to, Reason = why, Environment = settings.Environment, Protocol = verdict.Protocol ?? throw new InvalidOperationException("SEFAZ homologated the inutilização without a protocol"),
            Simulated = verdict.Simulated, Xml = xml, CreatedAt = now, CreatedBy = user
        };
        db.FiscalInutilizations.Add(record);
        foreach (var d in await db.FiscalDocuments.Where(d => d.Series == serie && d.Number >= from && d.Number <= to && d.Status == FiscalStatus.Rejected).ToListAsync(ct))
            d.StatusMessage = Cut($"{d.StatusMessage} | Inutilizada (protocolo {record.Protocol})", 500);
        await db.SaveChangesAsync(ct);
        return record;
    }

    /// <summary>
    /// Resolves one Pending NF by asking SEFAZ about its access key (NFeConsultaProtocolo4). Documents younger than <paramref name="minAgeMinutes"/> are left alone
    /// (the original request may still be waiting for SEFAZ). Authorized: becomes Authorized; unknown to SEFAZ: the number is released or the row kept Rejected.
    /// </summary>
    public async Task<ReconcileResult> ReconcileAsync(int id, int minAgeMinutes = 10, CancellationToken ct = default)
    {
        var doc = await db.FiscalDocuments.AsNoTracking().FirstOrDefaultAsync(d => d.Id == id, ct) ?? throw FiscalException.NotFound("NF");
        if (doc.Status != FiscalStatus.Pending) throw FiscalException.Conflict($"NF {doc.Number} is {doc.Status}, not Pending");
        if (DateTimeOffset.UtcNow - doc.IssuedAt < TimeSpan.FromMinutes(minAgeMinutes))
            return Result(doc, "waiting", $"Sent less than {minAgeMinutes} minutes ago; the original request may still be waiting for SEFAZ", doc.Status);
        SefazConsultResult r;
        try { r = await sefaz.ConsultAsync(doc.AccessKey, doc.Xml, doc.Environment, ct); }
        catch (FiscalException e) when (e.Status == 502) { return Result(doc, "unreachable", e.Message, doc.Status); }

        switch (r.Outcome)
        {
            case SefazConsultOutcome.Authorized:
            {
                await using var c = new EbtDbContext(options);
                var row = await c.FiscalDocuments.FirstAsync(d => d.Id == id, ct);
                if (row.Status != FiscalStatus.Pending) return Result(row, "skipped", $"NF {row.Number} is now {row.Status}", row.Status);
                row.Status = FiscalStatus.Authorized;
                row.Protocol = r.Protocol ?? throw new InvalidOperationException("SEFAZ reported the NF authorized without a protocol");
                row.Simulated = r.Simulated;
                if (r.AuthorizedXml is { } proc) row.Xml = proc;
                var unlinked = row.DeliveryId is null && row.OutsideShipmentId is null;
                row.StatusMessage = unlinked
                    ? "Authorized by SEFAZ after the answer was lost, with no delivery/shipment attached: cancel this NF (within the window) or link it by hand before issuing another"
                    : null;
                await c.SaveChangesAsync(ct);
                return Result(row, "authorized", row.StatusMessage ?? r.Message, row.Status, unlinked);
            }
            case SefazConsultOutcome.Cancelled:
            {
                await using var c = new EbtDbContext(options);
                var row = await c.FiscalDocuments.FirstAsync(d => d.Id == id, ct);
                if (row.Status != FiscalStatus.Pending) return Result(row, "skipped", $"NF {row.Number} is now {row.Status}", row.Status);
                row.Status = FiscalStatus.Cancelled;
                row.CancelledAt = DateTimeOffset.UtcNow;
                row.CancelledBy = "conciliação";
                row.CancelReason = "Cancelada direto na SEFAZ (encontrada na conciliação)";
                row.CancelProtocol = r.Protocol;
                await c.SaveChangesAsync(ct);
                return Result(row, "cancelled", r.Message, row.Status);
            }
            case SefazConsultOutcome.NotFound or SefazConsultOutcome.Denied:
            {
                var released = await ReleaseOrRejectAsync(id, r.Status, r.Message, reusable: r.Outcome == SefazConsultOutcome.NotFound, ct);
                if (released) return Result(doc, "released", $"SEFAZ has no record of NF {doc.Number}; the number went back to the sequence", FiscalStatus.Rejected);
                var after = await db.FiscalDocuments.AsNoTracking().FirstAsync(d => d.Id == id, ct);
                return Result(after, "rejected", $"SEFAZ {r.Status}: {r.Message}. The number stays used: inutilize it if it will not be reissued", after.Status);
            }
            default:
                return Result(doc, "unknown", $"SEFAZ {r.Status}: {r.Message}", doc.Status);
        }
    }

    /// <summary>Reconciles every Pending NF (oldest first).</summary>
    public async Task<IReadOnlyList<ReconcileResult>> ReconcilePendingAsync(int minAgeMinutes = 10, CancellationToken ct = default)
    {
        var ids = await db.FiscalDocuments.AsNoTracking().Where(d => d.Status == FiscalStatus.Pending).OrderBy(d => d.Series).ThenBy(d => d.Number).Select(d => d.Id).ToListAsync(ct);
        var results = new List<ReconcileResult>();
        foreach (var id in ids) results.Add(await ReconcileAsync(id, minAgeMinutes, ct));
        return results;
    }

    private static ReconcileResult Result(FiscalDocument d, string outcome, string message, FiscalStatus status, bool unlinked = false) =>
        new(d.Id, d.Series, d.Number, d.AccessKey, outcome, message, status, unlinked);

    private static FiscalDocument NewDocument(FiscalSettings s, Cfop cfop, FiscalKind kind, DateTimeOffset issuedAt, string? user, NfeParty recipient, int? customerId, int? supplierId)
    {
        var number = s.NextNumber;
        var key = NfeKey.Build(NfeKey.UfCodes[s.Uf], issuedAt.ToOffset(BrazilOffset), s.Cnpj!, s.Series, number, NfeKey.NewCodeNumber(number));
        return new FiscalDocument
        {
            Kind = kind, Status = FiscalStatus.Pending, CfopCode = cfop.Code, Series = s.Series, Number = number, AccessKey = key, Environment = s.Environment, Protocol = "", IssuedAt = issuedAt, IssuedBy = user,
            CustomerId = customerId, SupplierId = supplierId, RecipientName = recipient.Name, RecipientDocument = Digits(recipient.Document), RecipientUf = recipient.Uf, Xml = ""
        };
    }

    internal static void AllocateFreight(FiscalDocument doc)
    {
        var left = doc.FreightTotal;
        foreach (var (l, n) in doc.Lines.Select((l, n) => (l, n)))
        {
            l.Freight = n == doc.Lines.Count - 1 ? left : doc.ProductsTotal == 0 ? 0m : Money(doc.FreightTotal * l.Total / doc.ProductsTotal);
            left -= l.Freight;
        }
    }

    /// <summary>
    /// Bases: ICMS and IPI on goods + freight; the IPI joins the ICMS base when the buyer is not an ICMS contributor. PIS/COFINS on goods.
    /// The exact rounding/base rules still need confirmation against real NFs (see the analysis, last section).
    /// </summary>
    internal static void CalculateTaxes(FiscalDocument doc, Cfop cfop, bool customerIcmsContributor)
    {
        foreach (var l in doc.Lines)
        {
            if (!cfop.Taxed)
            {
                l.IcmsBase = l.IcmsValue = l.IpiBase = l.IpiValue = l.PisValue = l.CofinsValue = 0m;
                l.IcmsPercent = l.IpiPercent = l.PisPercent = l.CofinsPercent = 0m;
                continue;
            }
            var goods = l.Total + l.Freight;
            if (IpiCalculated.Contains(l.IpiCst)) { l.IpiBase = goods; l.IpiValue = Money(goods * l.IpiPercent / 100m); }
            else { l.IpiBase = l.IpiValue = 0m; l.IpiPercent = 0m; }
            if (IcmsCalculated.Contains(l.IcmsCst))
            {
                var baseValue = goods + (customerIcmsContributor ? 0m : l.IpiValue);
                if (l.IcmsCst == "20") baseValue = Money(baseValue * (1 - l.IcmsBaseReductionPercent / 100m));
                l.IcmsBase = baseValue;
                l.IcmsValue = Money(baseValue * l.IcmsPercent / 100m);
            }
            else { l.IcmsBase = l.IcmsValue = 0m; l.IcmsPercent = 0m; }
            l.PisValue = PisCofinsCalculated.Contains(l.PisCst) ? Money(l.Total * l.PisPercent / 100m) : 0m;
            l.CofinsValue = PisCofinsCalculated.Contains(l.CofinsCst) ? Money(l.Total * l.CofinsPercent / 100m) : 0m;
            if (!PisCofinsCalculated.Contains(l.PisCst)) l.PisPercent = 0m;
            if (!PisCofinsCalculated.Contains(l.CofinsCst)) l.CofinsPercent = 0m;
        }
        doc.IcmsBase = doc.Lines.Sum(l => l.IcmsBase);
        doc.IcmsTotal = doc.Lines.Sum(l => l.IcmsValue);
        doc.IpiTotal = doc.Lines.Sum(l => l.IpiValue);
        doc.PisTotal = doc.Lines.Sum(l => l.PisValue);
        doc.CofinsTotal = doc.Lines.Sum(l => l.CofinsValue);
        doc.InvoiceTotal = doc.ProductsTotal + doc.FreightTotal + doc.IpiTotal;
    }

    private async Task<List<FiscalInstallment>> InstallmentsAsync(SalesOrder order, Customer customer, decimal total, DateTimeOffset issuedLocal, CancellationToken ct)
    {
        var termId = order.PaymentTermId ?? customer.DefaultPaymentTermId;
        var text = termId is { } t ? await db.PaymentTerms.AsNoTracking().Where(p => p.Id == t).Select(p => p.Days).FirstOrDefaultAsync(ct) : Clean(order.CustomPaymentTerm);
        var days = text is null ? [] : Regex.Matches(text, @"\d+").Select(m => int.Parse(m.Value)).ToList();
        if (days.Count == 0) throw FiscalException.Blocked($"{order.Reference} has no payment term to build the duplicatas; set one on the order or the customer");
        var start = DateOnly.FromDateTime(issuedLocal.DateTime);
        var each = Math.Round(total / days.Count, 2, MidpointRounding.AwayFromZero);
        return days.Select((d, n) => new FiscalInstallment { Sequence = n + 1, DueDate = start.AddDays(d), Amount = n == days.Count - 1 ? total - each * (days.Count - 1) : each }).ToList();
    }

    private async Task<Cfop> CfopAsync(string code, FiscalKind kind, CancellationToken ct)
    {
        var cfop = await db.Cfops.AsNoTracking().FirstOrDefaultAsync(c => c.Code == code, ct) ?? throw FiscalException.Blocked($"CFOP {code} is not registered");
        if (!cfop.Active) throw FiscalException.Blocked($"CFOP {code} is inactive");
        if (kind == FiscalKind.OutsideShipment && cfop.Kind != FiscalKind.OutsideShipment) throw FiscalException.Blocked($"CFOP {code} is not a remessa para industrialização CFOP");
        if (kind == FiscalKind.Sale && cfop.Kind != FiscalKind.Sale) throw FiscalException.Blocked($"CFOP {code} cannot be used on a sale NF");
        return cfop;
    }

    private static bool RequireOperationScope(Cfop cfop, FiscalSettings settings, string recipientUf)
    {
        var interstate = !string.Equals(recipientUf, settings.Uf, StringComparison.OrdinalIgnoreCase);
        if (cfop.Code[0] == '5' && interstate) throw FiscalException.Blocked($"CFOP {cfop.Code} is for operations inside {settings.Uf}, but the recipient is in {recipientUf}; use the 6xxx CFOP");
        if (cfop.Code[0] == '6' && !interstate) throw FiscalException.Blocked($"CFOP {cfop.Code} is for operations outside {settings.Uf}, but the recipient is in {recipientUf}; use the 5xxx CFOP");
        return interstate;
    }

    private static void RequireIssuer(FiscalSettings s)
    {
        var missing = new List<string>();
        if (Digits(s.Cnpj).Length != 14) missing.Add("CNPJ");
        if (string.IsNullOrWhiteSpace(s.StateRegistration)) missing.Add("state registration");
        if (string.IsNullOrWhiteSpace(s.CompanyName)) missing.Add("company name");
        if (string.IsNullOrWhiteSpace(s.Street) || string.IsNullOrWhiteSpace(s.District) || string.IsNullOrWhiteSpace(s.City)) missing.Add("address");
        if (Digits(s.CityIbgeCode).Length != 7) missing.Add("city IBGE code");
        if (Digits(s.ZipCode).Length != 8) missing.Add("ZIP code");
        if (!NfeKey.UfCodes.ContainsKey(s.Uf)) missing.Add("UF");
        if (missing.Count > 0) throw FiscalException.Blocked($"Fiscal settings incomplete: {string.Join(", ", missing)}");
    }

    private static void RequireRecipient(NfeParty r, string who)
    {
        var missing = new List<string>();
        if (Digits(r.Document).Length is not (11 or 14)) missing.Add("CNPJ/CPF");
        if (string.IsNullOrWhiteSpace(r.Street) || string.IsNullOrWhiteSpace(r.District) || string.IsNullOrWhiteSpace(r.City)) missing.Add("address");
        if (Digits(r.CityIbgeCode).Length != 7) missing.Add("city IBGE code");
        if (Digits(r.ZipCode).Length != 8) missing.Add("ZIP code");
        if (!NfeKey.UfCodes.ContainsKey(r.Uf?.ToUpperInvariant() ?? "")) missing.Add("UF");
        if (missing.Count > 0) throw FiscalException.Blocked($"Registration of {who} is incomplete for the NF: {string.Join(", ", missing)}");
    }

    private static string RequireNcm(Product p) => Digits(p.Ncm) is { Length: 8 } ncm ? ncm : throw FiscalException.Blocked($"Product {p.Code} has no valid 8-digit NCM");

    /// <summary>Current issuer settings, neither locked nor tracked: emission needs only the issuer data, the number is taken later on its own connection.</summary>
    private async Task<FiscalSettings> ReadSettingsAsync(CancellationToken ct) => await db.FiscalSettings.AsNoTracking().FirstAsync(ct);

    private static async Task<FiscalSettings> LockSettingsAsync(EbtDbContext c, CancellationToken ct)
    {
        await c.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM fiscal_settings WHERE id = 1 FOR UPDATE").ToListAsync(ct);
        var s = await c.FiscalSettings.FirstAsync(ct);
        await c.Entry(s).ReloadAsync(ct);
        return s;
    }

    private async Task<T> InTransaction<T>(Func<Task<T>> work, CancellationToken ct)
    {
        if (db.Database.CurrentTransaction is not null) return await work();
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        try
        {
            var result = await work();
            await tx.CommitAsync(ct);
            return result;
        }
        catch
        {
            await tx.RollbackAsync(CancellationToken.None);
            db.ChangeTracker.Clear();
            throw;
        }
    }

    private static string Cut(string s, int max) => s.Length <= max ? s : s[..max];
    private static string Join(params string?[] parts) => string.Join(" | ", parts.Where(p => !string.IsNullOrWhiteSpace(p)).Select(p => p!.Trim()));
    private static decimal Money(decimal d) => Math.Round(d, 2, MidpointRounding.AwayFromZero);
    private static string Digits(string? s) => string.Concat((s ?? "").Where(char.IsDigit));
    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}

internal static class FiscalLineExtensions
{
    /// <summary>Fills CSTs and rates: tax rule first, then the CFOP defaults, then the rates already on the order line.</summary>
    public static FiscalDocumentLine WithRates(this FiscalDocumentLine l, Cfop cfop, TaxRule? rule, decimal orderIcms, decimal orderIpi)
    {
        l.IcmsCst = rule?.IcmsCst ?? cfop.IcmsCst;
        l.IcmsPercent = rule?.IcmsPercent ?? orderIcms;
        l.IcmsBaseReductionPercent = rule?.IcmsBaseReductionPercent ?? 0m;
        l.IpiCst = rule?.IpiCst ?? cfop.IpiCst;
        l.IpiPercent = rule?.IpiPercent ?? orderIpi;
        l.PisCst = cfop.PisCst;
        l.PisPercent = rule?.PisPercent ?? cfop.DefaultPisPercent;
        l.CofinsCst = cfop.CofinsCst;
        l.CofinsPercent = rule?.CofinsPercent ?? cfop.DefaultCofinsPercent;
        return l;
    }
}
