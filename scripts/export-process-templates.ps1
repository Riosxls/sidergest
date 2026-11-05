<#
.SYNOPSIS
  Builds process-templates.csv (the file MetaGest imports into the process suggestion of the OF) from the legacy "Pedido Interno de Venda" workbooks.

.DESCRIPTION
  One xlsx per order (sheet1 "Pedido", sheet2 "OP"), read as zip + XML through a compiled helper (no Excel; thousands of files in seconds).
  Fields are found by position or by label, as in scripts/export-price-history.ps1:
    - order number: first non-empty cell to the right of column C in row 1 (sheet1, else sheet2);
    - customer: the cell "CLIENTE:" ; dimensions: "DIMENSOES DO TUBO (MM):" (for example  T 12,70 X 1,50 X 869 mm); specification: "ESPECIFICACAO DO MATERIAL:";
    - date: the signature date cell above the "DATA" label near the bottom of sheet1 (Excel serial or dd.mm.yyyy / dd/mm/yyyy); otherwise the year of the
      order number suffix; a date in the future is pulled back a year;
    - operations (sheet2 "OP"): the rows between the cell starting "PROCESSOS SECUNDARIOS" and the cell starting "SOLICITA". Per row: column A = number,
      E = description, I = requirement/tolerance, K = start, L = end, M = resource (Perfiladeira, Trefiladeira, Visual/Dimensional...). Rows without description
      (and the header rows) are dropped.
  Output: ';'-separated UTF-8 CSV, ONE ROW PER OPERATION, header
      of;date;customer;diameter;thickness;length;spec;seq;description;tolerance;start;end;resource
  with decimal points in the numbers. Rows of the same order share the same "of". An order number that appears in two files is written once more as "<of>/2", "/3"...
  The file holds real customer data: it is git-ignored (process-templates*.csv). Nothing is written to the database; import the CSV with
  POST /api/production/process-templates/import (admin).

  Windows PowerShell 5.1. Saved as UTF-8 with BOM.
#>
param(
    [string]$PedidosFolder = 'C:\Users\italo\Desktop\EBT\Pedidos de Vendas\PEDIDOS DE VENDAS  BST 25 & 26',
    [string]$Out = (Join-Path (Split-Path $PSScriptRoot -Parent) 'process-templates.csv')
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

$source = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

public class ProcessOp { public string Seq, Description, Tolerance, Start, End, Resource; }

public class ProcessOrder
{
    public string File, Num, Customer, Spec, Problem;
    public double D, T, L;
    public bool HasT, HasL;
    public DateTime Date;
    public List<ProcessOp> Ops = new List<ProcessOp>();
}

public static class ProcessReader
{
    class Cell { public int Row, Col; public string Text; public bool IsNum; public double Num; public string Fold; }
    static readonly XNamespace Ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";

    static string Fold(string s)
    {
        if (s == null) return "";
        string d = s.Normalize(NormalizationForm.FormD);
        StringBuilder sb = new StringBuilder();
        foreach (char c in d)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return Regex.Replace(sb.ToString().ToUpperInvariant(), @"\s+", " ").Trim();
    }

    static int ColIndex(string reference, out int row)
    {
        int i = 0, col = 0;
        while (i < reference.Length && char.IsLetter(reference[i])) { col = col * 26 + (char.ToUpperInvariant(reference[i]) - 'A' + 1); i++; }
        row = int.Parse(reference.Substring(i), CultureInfo.InvariantCulture);
        return col;
    }

    public static double? ParseNum(string raw, bool thousandsDot)
    {
        if (raw == null) return null;
        string s = raw.Replace("R$", "").Replace(" ", "").Replace("\u00A0", "").Trim().TrimEnd('.', ',');
        if (s.Length == 0) return null;
        int comma = s.LastIndexOf(','), dot = s.LastIndexOf('.');
        if (comma >= 0 && dot >= 0) s = comma > dot ? s.Replace(".", "").Replace(',', '.') : s.Replace(",", "");
        else if (comma >= 0) s = s.Replace(',', '.');
        else if (s.Count(c => c == '.') > 1) s = s.Replace(".", "");
        else if (thousandsDot && Regex.IsMatch(s, @"^\d{1,3}\.\d{3}$")) s = s.Replace(".", "");
        double v;
        if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v)) return v;
        return null;
    }

    static DateTime? ParseDate(Cell c)
    {
        if (c == null) return null;
        if (c.IsNum) return c.Num >= 40000 && c.Num <= 48000 ? (DateTime?)DateTime.FromOADate(Math.Floor(c.Num)) : null;
        Match m = Regex.Match(c.Text, @"(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})");
        if (!m.Success) return null;
        int day = int.Parse(m.Groups[1].Value), month = int.Parse(m.Groups[2].Value), year = int.Parse(m.Groups[3].Value);
        if (year < 100) year += 2000;
        if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > DateTime.DaysInMonth(year, month)) return null;
        return new DateTime(year, month, day);
    }

    static List<string> SharedStrings(ZipArchive zip)
    {
        List<string> shared = new List<string>();
        ZipArchiveEntry se = zip.GetEntry("xl/sharedStrings.xml");
        if (se != null)
            using (Stream st = se.Open())
                foreach (XElement si in XDocument.Load(st).Root.Elements(Ns + "si"))
                    shared.Add(string.Concat(si.Elements(Ns + "t").Concat(si.Elements(Ns + "r").Elements(Ns + "t")).Select(x => x.Value)));
        return shared;
    }

    static List<Cell> Load(ZipArchive zip, List<string> shared, string entryName)
    {
        ZipArchiveEntry sheet = zip.GetEntry(entryName);
        List<Cell> cells = new List<Cell>();
        if (sheet == null) return cells;
        using (Stream st = sheet.Open())
            foreach (XElement c in XDocument.Load(st).Descendants(Ns + "c"))
            {
                XAttribute r = c.Attribute("r");
                if (r == null) continue;
                int row;
                int col = ColIndex(r.Value, out row);
                string t = c.Attribute("t") == null ? "" : c.Attribute("t").Value;
                XElement v = c.Element(Ns + "v");
                string text = null;
                bool isNum = false;
                double num = 0;
                if (t == "s") { int idx; if (v != null && int.TryParse(v.Value, out idx) && idx < shared.Count) text = shared[idx]; }
                else if (t == "inlineStr") { XElement iss = c.Element(Ns + "is"); if (iss != null) text = string.Concat(iss.Descendants(Ns + "t").Select(x => x.Value)); }
                else if (t == "str") { if (v != null) text = v.Value; }
                else if (t == "b" || t == "e") { }
                else if (v != null && double.TryParse(v.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out num)) { isNum = true; text = num.ToString("R", CultureInfo.InvariantCulture); }
                if (string.IsNullOrWhiteSpace(text)) continue;
                cells.Add(new Cell { Row = row, Col = col, Text = text.Trim(), IsNum = isNum, Num = num, Fold = Fold(text) });
            }
        return cells.OrderBy(x => x.Row).ThenBy(x => x.Col).ToList();
    }

    static List<Cell> Right(List<Cell> cells, Cell from)
    {
        return cells.Where(x => x.Row == from.Row && x.Col > from.Col).OrderBy(x => x.Col).ToList();
    }

    static string ValueOf(List<Cell> cells, Cell label)
    {
        int i = label.Text.IndexOf(':');
        if (i >= 0 && label.Text.Substring(i + 1).Trim().Length > 0) return label.Text.Substring(i + 1).Trim();
        Cell next = Right(cells, label).FirstOrDefault();
        return next == null ? null : next.Text;
    }

    static Cell Label(List<Cell> a, List<Cell> b, string prefix)
    {
        Cell c = a.FirstOrDefault(x => x.Fold.StartsWith(prefix, StringComparison.Ordinal));
        if (c == null) c = b.FirstOrDefault(x => x.Fold.StartsWith(prefix, StringComparison.Ordinal));
        return c;
    }

    static string At(List<Cell> cells, int row, int col)
    {
        Cell c = cells.FirstOrDefault(x => x.Row == row && x.Col == col);
        if (c == null) return null;
        string t = Regex.Replace(c.Text, @"\s+", " ").Trim();
        return t.Length == 0 ? null : t;
    }

    public static ProcessOrder Read(string path)
    {
        ProcessOrder o = new ProcessOrder { File = Path.GetFileName(path) };
        try
        {
            List<Cell> pedido, op;
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (ZipArchive zip = new ZipArchive(fs, ZipArchiveMode.Read))
            {
                List<string> shared = SharedStrings(zip);
                pedido = Load(zip, shared, "xl/worksheets/sheet1.xml");
                op = Load(zip, shared, "xl/worksheets/sheet2.xml");
            }
            Cell first = pedido.FirstOrDefault(x => x.Row == 1 && x.Col > 3);
            if (first == null) first = op.FirstOrDefault(x => x.Row == 1 && x.Col > 3);
            o.Num = first == null ? "" : first.Text;

            Cell cl = Label(pedido, op, "CLIENTE:");
            o.Customer = cl == null ? null : ValueOf(pedido.Contains(cl) ? pedido : op, cl);
            Cell dl = Label(pedido, op, "DIMENSOES DO TUBO");
            string dims = dl == null ? null : ValueOf(pedido.Contains(dl) ? pedido : op, dl);
            if (dims != null)
            {
                Match m = Regex.Match(Fold(dims), @"(\d[\d.,]*)\s*X\s*(\d[\d.,]*)(?:\s*X\s*(\d[\d.,]*))?");
                if (m.Success)
                {
                    o.D = ParseNum(m.Groups[1].Value, false) ?? 0;
                    o.T = ParseNum(m.Groups[2].Value, false) ?? 0;
                    o.L = m.Groups[3].Success ? (ParseNum(m.Groups[3].Value, true) ?? 0) : 0; // a roll ("X ROLO") has no length
                    o.HasT = o.T > 0;
                    o.HasL = o.L > 0;
                }
            }
            Cell sl = Label(pedido, op, "ESPECIFICACAO DO MATERIAL");
            o.Spec = sl == null ? null : ValueOf(pedido.Contains(sl) ? pedido : op, sl);

            // Signature date: the cell just above the last "DATA" label.
            DateTime? date = null;
            foreach (List<Cell> sheet in new[] { pedido, op })
            {
                foreach (Cell lab in sheet.Where(x => x.Fold == "DATA" || x.Fold == "DATA:").OrderByDescending(x => x.Row).ThenBy(x => x.Col))
                {
                    Cell above = sheet.Where(x => x.Col == lab.Col && x.Row < lab.Row && x.Row >= lab.Row - 3).OrderByDescending(x => x.Row).FirstOrDefault();
                    date = ParseDate(above);
                    if (date != null) break;
                }
                if (date != null) break;
            }
            if (date == null && pedido.Count > 0)
            {
                int maxRow = pedido.Max(x => x.Row);
                Cell dc = pedido.Where(x => x.Row >= maxRow - 8 && x.Col <= 5 && ParseDate(x) != null).OrderByDescending(x => x.Row).FirstOrDefault();
                if (dc != null) date = ParseDate(dc);
            }
            if (date == null)
            {
                Match y = Regex.Match(o.Num ?? "", @"[-/](\d{2})\s*$");
                if (y.Success) date = new DateTime(2000 + int.Parse(y.Groups[1].Value), 6, 30);
            }
            if (date != null && date.Value > DateTime.Today.AddDays(30)) date = date.Value.AddYears(-1);
            if (date != null) o.Date = date.Value;

            // Operations: rows between "PROCESSOS SECUNDARIOS" and "SOLICITA" on the OP sheet.
            Cell from = op.FirstOrDefault(x => x.Fold.StartsWith("PROCESSOS SECUNDARIOS", StringComparison.Ordinal));
            Cell to = from == null ? null : op.Where(x => x.Row > from.Row && x.Fold.StartsWith("SOLICITA", StringComparison.Ordinal)).OrderBy(x => x.Row).FirstOrDefault();
            if (from != null)
            {
                int last = to == null ? from.Row + 40 : to.Row - 1;
                for (int r = from.Row + 1; r <= last; r++)
                {
                    string desc = At(op, r, 5);
                    if (desc == null || Fold(desc).StartsWith("DESCRICAO")) continue;
                    o.Ops.Add(new ProcessOp { Seq = At(op, r, 1), Description = desc, Tolerance = At(op, r, 9), Start = At(op, r, 11), End = At(op, r, 12), Resource = At(op, r, 13) });
                }
            }

            if (string.IsNullOrWhiteSpace(o.Customer)) o.Problem = "no customer";
            else if (!(o.D > 0) || (o.HasT && o.T * 2 >= o.D)) o.Problem = "dimensions";
            else if (date == null) o.Problem = "date";
            else if (o.Ops.Count == 0) o.Problem = "no operations";
        }
        catch (Exception ex) { o.Problem = "error: " + ex.Message; }
        return o;
    }
}
'@
if (-not ('ProcessReader' -as [type])) {
    Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Xml.Linq', 'System.IO.Compression', 'System.IO.Compression.FileSystem', 'System.Xml', 'System.Core'
}

function Fmt([double]$v) { return $v.ToString('0.####', $inv) }
function Clean([string]$s) { if ($null -eq $s) { return '' }; return (($s -replace '[;\r\n"]+', ' ') -replace '\s+', ' ').Trim() }

if (-not (Test-Path -LiteralPath $PedidosFolder)) { throw "Pedidos folder not found: $PedidosFolder" }

$sb = New-Object Text.StringBuilder
[void]$sb.Append("of;date;customer;diameter;thickness;length;spec;seq;description;tolerance;start;end;resource`r`n")
$files = 0; $usable = 0; $opCount = 0; $problems = @{}; $seenOf = @{}
foreach ($f in Get-ChildItem -LiteralPath $PedidosFolder -Filter '*.xlsx' -File | Sort-Object Name) {
    if ($f.Name.StartsWith('~$')) { continue }
    $files++
    $o = [ProcessReader]::Read($f.FullName)
    if ($o.Problem) { if ($problems.ContainsKey($o.Problem)) { $problems[$o.Problem]++ } else { $problems[$o.Problem] = 1 }; continue }
    $usable++
    $of = Clean $o.Num
    if ($of -eq '') { $of = Clean $o.File }
    if ($seenOf.ContainsKey($of)) { $seenOf[$of]++; $of = '{0}/{1}' -f $of, $seenOf[$of] } else { $seenOf[$of] = 1 }
    $thick = ''; if ($o.HasT) { $thick = Fmt $o.T }
    $len = ''; if ($o.HasL) { $len = Fmt $o.L }
    $n = 0
    foreach ($p in $o.Ops) {
        $n++
        $seq = Clean $p.Seq
        if ($seq -notmatch '^\d+$') { $seq = [string]($n * 10) }
        [void]$sb.Append(('{0};{1};{2};{3};{4};{5};{6};{7};{8};{9};{10};{11};{12}' -f $of, $o.Date.ToString('yyyy-MM-dd'), (Clean $o.Customer), (Fmt $o.D), $thick, $len, (Clean $o.Spec), $seq, (Clean $p.Description), (Clean $p.Tolerance), (Clean $p.Start), (Clean $p.End), (Clean $p.Resource)))
        [void]$sb.Append("`r`n")
        $opCount++
    }
}
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Host ("Pedidos internos: {0} files, {1} usable, {2} operation lines" -f $files, $usable, $opCount)
foreach ($k in $problems.Keys) { Write-Host ("  skipped ({0}): {1}" -f $k, $problems[$k]) }
Write-Host "Written: $Out"
