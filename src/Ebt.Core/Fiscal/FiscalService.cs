using System.Text.RegularExpressions;
using Ebt.Core.Data;
using Ebt.Core.Entities;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Fiscal;

/// <summary>
/// NF-e emission. An NF is recorded only after SEFAZ authorizes it: on a rejection (or any later failure inside the caller's transaction)
/// no document row exists and the NF number is not consumed. Callers lower stock and update the delivery/shipment in the same transaction.
/// </summary>
public sealed class FiscalService(EbtDbContext db, ISefazClient sefaz)
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
            var settings = await LockSettingsAsync(ct);
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
            doc.AdditionalInfo = Join(order.Reference, ofs.Count > 0 ? string.Join(", ", ofs) : null, order.CustomerPo is { } po ? $"Pedido cliente {po}" : null, delivery.Notes, cfop.LegalText);
            var transport = new NfeTransport(order.Freight == FreightTerms.Cif ? 0 : 1, opt.Carrier ?? delivery.Carrier, opt.VehiclePlate ?? delivery.VehiclePlate, delivery.Packages, opt.GrossWeightKg ?? delivery.GrossWeightKg);
            return await AuthorizeAndSaveAsync(settings, doc, cfop, recipient, transport, interstate, ct);
        }, ct);
    }

    /// <summary>Remessa para industrialização (default CFOP 5901) for an outside-processing shipment already saved (has an Id).</summary>
    public async Task<FiscalDocument> IssueOutsideShipmentAsync(OutsideShipment shipment, ProductionOrder order, ProductionOrderOperation operation, OutsideInvoiceOptions opt, string? user, CancellationToken ct = default)
    {
        if (opt.UnitValue <= 0) throw FiscalException.Invalid("unitValue", "Give the reference unit value of the pieces sent");
        return await InTransaction(async () =>
        {
            var settings = await LockSettingsAsync(ct);
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
            var settings = await LockSettingsAsync(ct);
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

    private async Task<FiscalDocument> AuthorizeAndSaveAsync(FiscalSettings settings, FiscalDocument doc, Cfop cfop, NfeParty recipient, NfeTransport transport, bool interstate, CancellationToken ct)
    {
        doc.Xml = NfeXml.Build(settings, doc, cfop, recipient, transport, interstate);
        var verdict = await sefaz.AuthorizeAsync(doc.AccessKey, doc.Xml, doc.Environment, ct);
        if (!verdict.Authorized) throw FiscalException.Rejected(verdict.Status, verdict.Message);
        doc.Protocol = verdict.Protocol ?? throw new InvalidOperationException("SEFAZ authorized without a protocol");
        doc.Simulated = verdict.Simulated;
        if (verdict.AuthorizedXml is { } authorizedXml) doc.Xml = authorizedXml;
        settings.NextNumber = doc.Number + 1;
        db.FiscalDocuments.Add(doc);
        await db.SaveChangesAsync(ct);
        return doc;
    }

    private static FiscalDocument NewDocument(FiscalSettings s, Cfop cfop, FiscalKind kind, DateTimeOffset issuedAt, string? user, NfeParty recipient, int? customerId, int? supplierId)
    {
        var number = s.NextNumber;
        var key = NfeKey.Build(NfeKey.UfCodes[s.Uf], issuedAt.ToOffset(BrazilOffset), s.Cnpj!, s.Series, number, NfeKey.NewCodeNumber(number));
        return new FiscalDocument
        {
            Kind = kind, Status = FiscalStatus.Authorized, CfopCode = cfop.Code, Series = s.Series, Number = number, AccessKey = key, Environment = s.Environment, Protocol = "", IssuedAt = issuedAt, IssuedBy = user,
            CustomerId = customerId, SupplierId = supplierId, RecipientName = recipient.Name, RecipientDocument = Digits(recipient.Document), RecipientUf = recipient.Uf, Xml = ""
        };
    }

    private static void AllocateFreight(FiscalDocument doc)
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
    private static void CalculateTaxes(FiscalDocument doc, Cfop cfop, bool customerIcmsContributor)
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

    private async Task<FiscalSettings> LockSettingsAsync(CancellationToken ct)
    {
        await db.Database.SqlQuery<int>($"SELECT id AS \"Value\" FROM fiscal_settings WHERE id = 1 FOR UPDATE").ToListAsync(ct);
        var s = await db.FiscalSettings.FirstAsync(ct);
        await db.Entry(s).ReloadAsync(ct);
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
