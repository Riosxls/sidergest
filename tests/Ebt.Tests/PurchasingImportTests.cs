using Ebt.Core.Entities;
using Ebt.DbfImport;
using Microsoft.EntityFrameworkCore;
using static Ebt.Tests.DbfWriter;

namespace Ebt.Tests;

[Collection("purchasing")]
public class PurchasingImportTests(PurchasingFixture api) : IDisposable
{
    private readonly string dir = Directory.CreateTempSubdirectory("ebt-gsc-").FullName;

    public void Dispose()
    {
        Directory.Delete(dir, true);
        using var db = api.NewDb();
        db.PurchasingSettings.ExecuteUpdate(s => s.SetProperty(x => x.ReceivingTolerancePercent, 5m).SetProperty(x => x.AllowEarlyReceipt, false));
    }

    private string P(string file) => Path.Combine(dir, file);

    private static DbfField D(string name) => new(name, 'D', 8);

    private void WriteFixtures(decimal receivedQty)
    {
        Write(P("SE100.DBF"), [C("E10CDMATER", 15), C("E10DSMATER", 40), C("E10UNIDADE", 3), C("E10UNCOMPR", 3), N("E10FATOR", 10, 4)],
            [["GSCBOB", "Bobina 2,00mm", "KG", "KG", 1m]]);
        Write(P("SE060.DBF"), [C("E06CDFORNE", 6), C("E06RSFORNE", 40)], [["F0001", "Aços Paulista Ltda"], ["F0002", "Metal Sul"]]);
        Write(P("SE370.DBF"), [C("E37CDFORNE", 6), C("E37CDMATER", 15), N("E37VLUNIT", 12, 4), D("E37DATA"), C("E37QUALIF", 2)],
            [["F0001", "GSCBOB", 6.1m, "20240310", "A"], ["F0009", "GSCBOB", 1m, "20240310", "B"]]);
        Write(P("SG060.DBF"), [C("G06NRCOTAC", 6), C("G06ITEM", 2), C("G06CDMATER", 10), C("G06DSMATER", 20), C("G06UNIDADE", 2), N("G06QTD", 11, 3), D("G06DTCAD")],
            [["000501", "1", "GSCBOB", "BOBINA 2,00", "KG", 5000m, "20240301"], ["000501", "2", null, "LUVAS RASPA", "PR", 20m, "20240301"]]);
        Write(P("SG070.DBF"), [C("G07NRCOTAC", 6), C("G07ITEM", 1), C("G07CDFORN", 6), N("G07VLCOMPR", 12, 4), N("G07IPI", 5, 2), N("G07ICMS", 5, 2), N("G07PZENTR", 3), C("G07DDL", 10), C("G07PENDENC", 1)],
            [["000501", "1", "F0001", 6.2m, 5m, 18m, 10, "28/42", "A"], ["000501", "1", "F0002", 6.5m, 0m, 12m, 5, "30", "R"], ["000501", "2", "F0001", 0m, 0m, 0m, 0, null, "P"]]);
        Write(P("SG190.DBF"), [C("G19NRPEDID", 6), C("G19IDFORNE", 6), D("G19DTCADAS"), C("G19DDL", 10), C("G19TEXTO", 30)],
            [["000777", "F0001", "20240305", "28/42", "Entregar portaria 2"], ["000778", "F0002", "20240306", null, null]]);
        Write(P("SG120.DBF"), [C("G12NRPEDID", 6), C("G12CDMATER", 10), N("G12QTD", 11, 3), N("G12PRUNIT", 12, 4), N("G12IPI", 5, 2), N("G12ICMS", 5, 2), C("G12NRCOTAC", 6), C("G12CDFORN", 6), C("G12ENCERRA", 1), D("G12DTPEDID")],
            [["000777", "GSCBOB", 5000m, 6.2m, 5m, 18m, "000501", "F0001", "N", "20240305"], ["000778", "GSCBOB", 100m, 7m, 0m, 0m, null, "F0002", "N", "20240306"]]);
        Write(P("SG090.DBF"), [C("G09NRPEDID", 6), C("G09NRCOTAC", 6), C("G09ITEM", 1), D("G09DTENTR"), N("G09QTENTR", 11, 3), N("G09QTDIGIT", 11, 3)],
            [["000777", "000501", "1", "20240320", 2500m, receivedQty], ["000777", "000501", "1", "20240315", 2500m, 0m]]);
        Write(P("SG200.DBF"), [C("G20NRPEDID", 6), C("G20MOTIVO", 30), D("G20DATACAN")], [["000778", "Fornecedor sem prazo", "20240307"]]);
        Write(P("SG020.DBF"),
            [N("G02PK", 6), C("G02CDMATER", 10), C("G02DSMATER", 20), C("G02UNIDADE", 2), N("G02QTNECES", 11, 3), C("G02CDDEPTO", 3), D("G02DTMOVIM"), D("G02DTENTR"), C("G02STATUS", 1), C("G02NRCOTAC", 6), C("G02ITEM", 2), C("G02NRPEDID", 6), C("G02USUARIO", 15)],
            [[1201, "GSCBOB", "BOBINA 2,00", "KG", 5000m, "PCP", "20240228", "20240320", "7", "000501", "1", "000777", "MARIA"],
             [1202, null, "LUVAS RASPA", "PR", 20m, "MAN", "20240228", null, "3", "000501", "2", null, "JOAO"],
             [1203, "GSCBOB", "BOBINA 2,00", "KG", 0m, "PCP", "20240228", null, "0", null, null, null, null]]);
        Write(P("SGCONTRO.DBF"), [N("GNRPEDIDO", 6), N("GNRCOTACAO", 6), N("GPKREQUIS", 6), N("TOLRECEBIM", 3), C("ANTECIPAMP", 1)], [[780, 502, 1300, 10, "N"]]);
    }

    private async Task<ImportReport> Run(bool dryRun = false)
    {
        await using var db = api.NewDb();
        return await new Importer(db, new ImportOptions { Directory = dir, DryRun = dryRun, Steps = [new PurchasingImport()] }).RunAsync();
    }

    [Fact]
    public async Task Imports_legacy_purchasing_data_and_is_idempotent()
    {
        WriteFixtures(1000m);
        var dry = await Run(dryRun: true);
        Assert.Equal(2, dry.Tables["requisitions"].Inserted);
        await using (var db = api.NewDb())
            Assert.False(await db.PurchaseOrders.AnyAsync(o => o.Number == 777));

        var first = await Run();
        Assert.Equal((2, 1), (first.Tables["requisitions"].Inserted, first.Tables["requisitions"].Skipped));
        Assert.Equal(1, first.Tables["supplier materials"].Skipped);
        Assert.Contains(first.Warnings, w => w.Contains("unknown supplier F0009"));

        await using (var db = api.NewDb())
        {
            var settings = await db.PurchasingSettings.SingleAsync();
            Assert.Equal((10m, false), (settings.ReceivingTolerancePercent, settings.AllowEarlyReceipt));

            var q = await db.Quotations.Include(x => x.Items).ThenInclude(i => i.Bids).SingleAsync(x => x.Number == 501);
            Assert.Equal(QuotationStatus.Open, q.Status);
            var coilItem = q.Items.Single(i => i.Item == 1);
            Assert.Equal(BidStatus.Approved, coilItem.Bids.Single(b => b.UnitPrice == 6.2m).Status);
            Assert.Null(q.Items.Single(i => i.Item == 2).Bids.Single().UnitPrice);

            var po = await db.PurchaseOrders.Include(o => o.Lines).Include(o => o.Supplier).SingleAsync(o => o.Number == 777);
            Assert.Equal(("Aços Paulista Ltda", PurchaseOrderStatus.PartiallyReceived, "28/42"), (po.Supplier!.Name, po.Status, po.PaymentTerms));
            var line = Assert.Single(po.Lines);
            Assert.Equal((1000m, new DateOnly(2024, 3, 15)), (line.ReceivedQuantity, line.DueDate));
            Assert.Equal(coilItem.Bids.Single(b => b.Status == BidStatus.Approved).Id, line.QuotationBidId);

            var cancelled = await db.PurchaseOrders.Include(o => o.Lines).SingleAsync(o => o.Number == 778);
            Assert.Equal(PurchaseOrderStatus.Cancelled, cancelled.Status);
            Assert.Equal("Fornecedor sem prazo", cancelled.CloseReason);

            var reqs = await db.PurchaseRequisitions.Where(r => r.Number >= 1201 && r.Number <= 1203).OrderBy(r => r.Number).ToListAsync();
            Assert.Equal([RequisitionStatus.PartiallyReceived, RequisitionStatus.Quoting], reqs.Select(r => r.Status));
            Assert.Equal(line.Id, reqs[0].PurchaseOrderLineId);
            Assert.Null(reqs[1].MaterialId);
            Assert.Equal("LUVAS RASPA", reqs[1].Description);
            Assert.Equal(q.Items.Single(i => i.Item == 2).Id, reqs[1].QuotationItemId);

            var sm = await db.SupplierMaterials.SingleAsync(s => s.Material!.Code == "GSCBOB");
            Assert.Equal((6.1m, "A"), (sm.LastUnitPrice, sm.Qualification));
        }

        WriteFixtures(5000m);
        var second = await Run();
        Assert.Equal(0, second.Tables["requisitions"].Inserted);
        Assert.Equal(0, second.Tables["order lines"].Inserted);
        await using (var db = api.NewDb())
        {
            var po = await db.PurchaseOrders.Include(o => o.Lines).SingleAsync(o => o.Number == 777);
            Assert.Equal((PurchaseOrderStatus.Received, 5000m), (po.Status, po.Lines[0].ReceivedQuantity));
            Assert.Single(await db.PurchaseOrders.Where(o => o.Number == 777).ToListAsync());
        }

        var c = await api.AdminAsync();
        var req = await (await c.Post("/api/requisitions", new Api.Endpoints.RequisitionIn(null, "Teste", "UN", 1m, null, null, null, null))).Read<Api.Endpoints.RequisitionOut>();
        Assert.True(req.Number > 1300);
    }
}
