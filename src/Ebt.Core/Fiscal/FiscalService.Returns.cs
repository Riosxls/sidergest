using Ebt.Core.Data;
using Ebt.Core.Entities;
using Ebt.Core.Inventory;
using Microsoft.EntityFrameworkCore;

namespace Ebt.Core.Fiscal;

/// <summary>Devolução de venda (finNFe 4, CFOP 1202/2202) and carta de correção (CC-e, event 110110) on authorized NFs.</summary>
public sealed partial class FiscalService
{
    private static readonly TimeSpan Brazil = TimeSpan.FromHours(-3);

    /// <summary>
    /// Issues the return NF of all or part of an Authorized sale NF: an entry NF (tpNF 0, finNFe 4) issued by us, referencing the original key, with quantities limited to
    /// the balance not returned yet and prices/taxes taken from the original lines. The goods go back into stock at <see cref="ReturnInput.LocationId"/> (same lot as
    /// shipped when known) in the same transaction as the NF: if SEFAZ refuses, stock is untouched.
    /// </summary>
    public async Task<FiscalDocument> IssueReturnAsync(int originalId, ReturnInput input, string? user, CancellationToken ct = default)
    {
        var reason = Clean(input.Reason);
        if (reason is null || reason.Length < 5) throw FiscalException.Invalid("reason", "Give the reason for the return");
        if (reason.Length > 500) throw FiscalException.Invalid("reason", "At most 500 characters");
        if (input.Lines is null || input.Lines.Count == 0) throw FiscalException.Invalid("lines", "Pick at least one item to return");
        return await InTransaction(async () =>
        {
            var settings = await ReadSettingsAsync(ct);
            if (!settings.Enabled) throw FiscalException.Conflict("NF emission is disabled");
            RequireIssuer(settings);
            // Serializes returns of the same NF, so two clerks cannot return the same balance twice.
            await LockDocumentAsync(originalId, ct);
            var original = await db.FiscalDocuments.AsNoTracking().Include(d => d.Lines).AsSplitQuery().FirstOrDefaultAsync(d => d.Id == originalId, ct) ?? throw FiscalException.NotFound("NF");
            if (original.Kind != FiscalKind.Sale) throw FiscalException.Conflict($"NF {original.Number} is not a sale NF; only sales can be returned");
            if (original.Status != FiscalStatus.Authorized) throw FiscalException.Conflict($"NF {original.Number} is {original.Status}; only an authorized NF can be returned");
            if (original.DeliveryId is not { } deliveryId) throw FiscalException.Conflict($"NF {original.Number} has no delivery attached");
            var delivery = await db.Deliveries.AsNoTracking().Include(d => d.Order).FirstAsync(d => d.Id == deliveryId, ct);
            var address = await db.CustomerAddresses.AsNoTracking().FirstOrDefaultAsync(a => a.Id == delivery.AddressId, ct) ?? throw FiscalException.NotFound("Delivery address");
            var customer = await db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == original.CustomerId, ct) ?? throw FiscalException.NotFound("Customer");
            var recipient = new NfeParty(customer.Name, address.Document, address.StateRegistration, address.IcmsContributor, address.Street, address.Number, address.Complement, address.District, address.City, address.CityIbgeCode, address.Uf, address.ZipCode, address.Email ?? customer.Email, address.Phone);
            RequireRecipient(recipient, $"customer {customer.Name} (address {address.Id})");
            var interstate = !string.Equals(recipient.Uf, settings.Uf, StringComparison.OrdinalIgnoreCase);
            var cfop = await CfopAsync(interstate ? "2202" : "1202", FiscalKind.Return, ct);
            RequireOperationScope(cfop, settings, recipient.Uf);

            var location = await db.StockLocations.AsNoTracking().FirstOrDefaultAsync(l => l.Id == input.LocationId, ct) ?? throw FiscalException.Invalid("locationId", "Stock location not found");
            if (!location.Active || location.Kind == StockLocationKind.ThirdParty) throw FiscalException.Invalid("locationId", "Pick an active location of the company");

            var returned = await ReturnedByLineAsync(db, original.Lines.Select(l => l.Id).ToList(), ct);
            var issuedAt = DateTimeOffset.UtcNow;
            var doc = NewDocument(settings, cfop, FiscalKind.Return, issuedAt, user, recipient, customerId: customer.Id, supplierId: null);
            doc.ReferencedDocumentId = original.Id;
            doc.ReferencedAccessKey = original.AccessKey;
            var picked = new List<(FiscalDocumentLine Line, FiscalDocumentLine Source)>();
            foreach (var (req, n) in input.Lines.Select((r, n) => (r, n)))
            {
                var field = $"lines[{n}]";
                if (input.Lines.Count(x => x.ItemId == req.ItemId) > 1) throw FiscalException.Invalid($"{field}.itemId", "Repeated item");
                var src = original.Lines.FirstOrDefault(l => l.Id == req.ItemId) ?? throw FiscalException.Invalid($"{field}.itemId", $"Item not found on NF {original.Number}");
                if (req.Quantity <= 0) throw FiscalException.Invalid($"{field}.quantity", "Must be greater than zero");
                var balance = src.Quantity - returned.GetValueOrDefault(src.Id);
                if (req.Quantity > balance) throw FiscalException.Invalid($"{field}.quantity", balance <= 0 ? $"{src.Code} was already fully returned" : $"Only {balance:0.####} of {src.Code} left to return");
                var share = req.Quantity / src.Quantity;
                var line = new FiscalDocumentLine
                {
                    Sequence = (n + 1) * 10, ProductId = src.ProductId, ProductionOrderId = src.ProductionOrderId, ReferencedLineId = src.Id, Code = src.Code, Description = src.Description, Ncm = src.Ncm, Unit = src.Unit,
                    Quantity = req.Quantity, UnitPrice = src.UnitPrice, Total = Money(req.Quantity * src.UnitPrice), Freight = req.Quantity == src.Quantity ? src.Freight : Money(src.Freight * share),
                    IcmsCst = src.IcmsCst, IcmsPercent = src.IcmsPercent, IcmsBaseReductionPercent = src.IcmsBaseReductionPercent, IpiCst = ReturnIpiCst(src.IpiCst), IpiPercent = src.IpiPercent,
                    PisCst = src.PisCst, PisPercent = src.PisPercent, CofinsCst = src.CofinsCst, CofinsPercent = src.CofinsPercent
                };
                doc.Lines.Add(line);
                picked.Add((line, src));
            }
            doc.ProductsTotal = doc.Lines.Sum(l => l.Total);
            doc.FreightTotal = doc.Lines.Sum(l => l.Freight);
            CalculateTaxes(doc, cfop, customerIcmsContributor: address.IcmsContributor);
            doc.AdditionalInfo = Join($"Devolução ref. NF {original.Number} série {original.Series}", reason, $"Entrega ({delivery.Reference})", cfop.LegalText);

            // Stock first, in the caller's transaction: a period closed or a refusal by SEFAZ leaves nothing behind.
            var stockDoc = await stock.PostAsync(new StockPost(MovementType.CustomerReturn, DateOnly.FromDateTime(issuedAt.ToOffset(Brazil).DateTime), await StockLinesAsync(delivery, original, picked, input.LocationId, ct),
                delivery.Reference, CustomerId: customer.Id, Notes: $"Devolução da NF {original.Number}: {reason}"), user ?? "system", ct);
            doc.StockDocumentId = stockDoc.Id;

            var saved = await AuthorizeAndSaveAsync(settings, doc, cfop, recipient, new NfeTransport(9, null, null, 0, null), interstate, ct);
            stockDoc.Notes = $"{stockDoc.Notes} · NF {saved.Number}";
            var note = $"NF de devolução {saved.Number} (ref. NF {original.Number}): {string.Join(", ", picked.Select(p => $"{p.Line.Quantity:0.####} {p.Line.Code}"))}. {reason}";
            db.SalesEvents.Add(new SalesEvent { Kind = SalesRecordKind.Delivery, RecordId = delivery.Id, Action = "nf-return", Note = Cut(note, 500), User = user, At = DateTimeOffset.UtcNow });
            db.SalesEvents.Add(new SalesEvent { Kind = SalesRecordKind.Order, RecordId = delivery.OrderId, Action = "nf-return", Note = Cut($"{delivery.Reference}: {note}", 500), User = user, At = DateTimeOffset.UtcNow });
            db.AuditLog.Add(new AuditEntry
            {
                At = DateTimeOffset.UtcNow, User = user, Entity = nameof(FiscalDocument), EntityId = saved.Id.ToString(), Action = "Return",
                Changes = System.Text.Json.JsonSerializer.Serialize(new { originalNf = original.Number, returnNf = saved.Number, reason, lines = picked.Select(p => new { p.Line.Code, p.Line.Quantity }) })
            });
            await db.SaveChangesAsync(ct);
            return saved;
        }, ct);
    }

    /// <summary>Quantity already sent back per sale NF line, counting return NFs that are Authorized or still Pending.</summary>
    public static async Task<Dictionary<int, decimal>> ReturnedByLineAsync(EbtDbContext db, IReadOnlyCollection<int> lineIds, CancellationToken ct = default) =>
        await db.FiscalDocumentLines.AsNoTracking()
            .Where(l => l.ReferencedLineId != null && lineIds.Contains(l.ReferencedLineId.Value) && l.Document!.Kind == FiscalKind.Return && (l.Document.Status == FiscalStatus.Authorized || l.Document.Status == FiscalStatus.Pending))
            .GroupBy(l => l.ReferencedLineId!.Value).Select(g => new { g.Key, Quantity = g.Sum(x => x.Quantity) }).ToDictionaryAsync(x => x.Key, x => x.Quantity, ct);

    /// <summary>IPI CST of an entry: the sale CST 50..55 becomes 00..05 and 99 becomes 49 (layout CSTs of the entry group).</summary>
    internal static string ReturnIpiCst(string saleCst) => saleCst switch
    {
        "50" => "00",
        "99" => "49",
        "51" or "52" or "53" or "54" or "55" => "0" + (saleCst[1] - '0' ),
        _ => saleCst
    };

    /// <summary>Goes back to the lot(s) the delivery took the goods from (minus what earlier returns already put back); the rest goes without a lot.</summary>
    private async Task<List<StockLine>> StockLinesAsync(Delivery delivery, FiscalDocument original, List<(FiscalDocumentLine Line, FiscalDocumentLine Source)> picked, int locationId, CancellationToken ct)
    {
        var shipped = delivery.StockDocumentId is { } sd
            ? await db.StockMovements.AsNoTracking().Where(m => m.DocumentId == sd && m.Quantity < 0 && m.ProductId != null).OrderBy(m => m.Id).ToListAsync(ct)
            : [];
        var earlier = await db.FiscalDocuments.AsNoTracking().Where(d => d.ReferencedDocumentId == original.Id && d.Kind == FiscalKind.Return && d.Status == FiscalStatus.Authorized && d.StockDocumentId != null).Select(d => d.StockDocumentId!.Value).ToListAsync(ct);
        var back = earlier.Count == 0 ? [] : await db.StockMovements.AsNoTracking().Where(m => earlier.Contains(m.DocumentId) && m.Quantity > 0 && m.ProductId != null).ToListAsync(ct);
        var lines = new List<StockLine>();
        foreach (var (line, _) in picked)
        {
            if (line.ProductId is not { } productId) throw FiscalException.Blocked($"Item {line.Code} has no product; it cannot go back into stock");
            var left = line.Quantity;
            foreach (var m in shipped.Where(m => m.ProductId == productId && m.LotId != null))
            {
                if (left <= 0) break;
                var room = -m.Quantity - back.Where(b => b.ProductId == productId && b.LotId == m.LotId).Sum(b => b.Quantity);
                var take = Math.Min(left, room);
                if (take <= 0) continue;
                lines.Add(new StockLine(null, productId, locationId, take, LotId: m.LotId, UnitCost: m.UnitCost));
                left -= take;
            }
            if (left > 0) lines.Add(new StockLine(null, productId, locationId, left, UnitCost: shipped.FirstOrDefault(m => m.ProductId == productId)?.UnitCost));
        }
        return lines;
    }

    /// <summary>
    /// Carta de correção (event 110110) on an Authorized NF. Text 15..1000 characters, sequence 1..20 per NF; the row is locked while SEFAZ is called.
    /// The text cannot change values, taxes, recipient or dates (SEFAZ rule, not checkable here).
    /// </summary>
    public async Task<FiscalEvent> CorrectAsync(int id, string? text, string? user, CancellationToken ct = default)
    {
        var body = Clean(text) is { } t ? string.Join(" ", t.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)) : null;
        if (body is null || body.Length < 15) throw FiscalException.Invalid("text", "The correction needs at least 15 characters (SEFAZ rule)");
        if (body.Length > 1000) throw FiscalException.Invalid("text", "At most 1000 characters (SEFAZ rule)");
        return await InTransaction(async () =>
        {
            await LockDocumentAsync(id, ct);
            var doc = await db.FiscalDocuments.AsNoTracking().FirstOrDefaultAsync(d => d.Id == id, ct) ?? throw FiscalException.NotFound("NF");
            if (doc.Status != FiscalStatus.Authorized) throw FiscalException.Conflict($"NF {doc.Number} is {doc.Status}; only an authorized NF accepts a correction");
            var sequence = (await db.FiscalEvents.Where(e => e.DocumentId == id && e.EventType == CorrectionEvent).Select(e => (int?)e.Sequence).MaxAsync(ct) ?? 0) + 1;
            if (sequence > 20) throw FiscalException.Conflict($"NF {doc.Number} already has 20 corrections, the SEFAZ limit");
            var verdict = await sefaz.CorrectAsync(doc.AccessKey, sequence, body, doc.Environment, ct);
            if (!verdict.Authorized) throw FiscalException.Rejected(verdict.Status, verdict.Message);
            var ev = new FiscalEvent
            {
                DocumentId = id, EventType = CorrectionEvent, Sequence = sequence, Text = body, Environment = doc.Environment, Simulated = verdict.Simulated, CreatedAt = DateTimeOffset.UtcNow, CreatedBy = user,
                Protocol = verdict.Protocol ?? throw new InvalidOperationException("SEFAZ registered the CC-e without a protocol")
            };
            db.FiscalEvents.Add(ev);
            await db.SaveChangesAsync(ct);
            return ev;
        }, ct);
    }

    public const string CorrectionEvent = "110110";
}
