using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Ebt.Core.Data.Migrations
{
    /// <summary>Data-only migration: standard sales prazos (payment terms). Codes sort in display order.</summary>
    [DbContext(typeof(EbtDbContext))]
    [Migration("20261028043000_SeedSalesPrazos")]
    public class SeedSalesPrazos : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Terms from an earlier startup seed: drop when unused, otherwise just deactivate.
            const string old = "('AVISTA','7D','14D','21D','28D','30D','45D','60D','90D','30-60','30-60-90','30-60-90-120')";
            migrationBuilder.Sql($"""
                DELETE FROM payment_terms WHERE code IN {old}
                  AND id NOT IN (SELECT payment_term_id FROM quotes WHERE payment_term_id IS NOT NULL)
                  AND id NOT IN (SELECT payment_term_id FROM sales_orders WHERE payment_term_id IS NOT NULL);
                UPDATE payment_terms SET active = false WHERE code IN {old};
                """);
            migrationBuilder.Sql("""
                INSERT INTO payment_terms (code, name, days, active) VALUES
                  ('01', '30 dias', '30', true),
                  ('02', '60 dias', '60', true),
                  ('03', '90 dias', '90', true),
                  ('04', '120 dias', '120', true),
                  ('05', '28 ddf (dias da data do faturamento)', '28', true),
                  ('06', '30 / 60 dias', '30/60', true),
                  ('07', '30 / 60 / 90 dias', '30/60/90', true),
                  ('08', '30 / 60 / 90 / 120 dias', '30/60/90/120', true),
                  ('09', '15 / 30 / 45 / 60 dias', '15/30/45/60', true),
                  ('10', '7 dias (para insumos de altíssimo giro)', '7', true)
                ON CONFLICT (code) DO NOTHING;
                """);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DELETE FROM payment_terms WHERE code IN ('01','02','03','04','05','06','07','08','09','10')
                  AND id NOT IN (SELECT payment_term_id FROM quotes WHERE payment_term_id IS NOT NULL)
                  AND id NOT IN (SELECT payment_term_id FROM sales_orders WHERE payment_term_id IS NOT NULL);
                """);
        }
    }
}
