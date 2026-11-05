<#
.SYNOPSIS
  Builds price-history.csv (the file MetaGest imports under Comercial > Sugestao de preco) from the legacy sales files.

.DESCRIPTION
  Two sources, merged and de-duplicated:
    1. The master workbook of sales ("PEDIDO DE VENDAS Anos 24 & 26 - EBT e BST.xlsx"): every sheet whose row 2 has the headers
       Diametro, Espessura, Comprim*, UNID, VALOR UNIT* (plus DATA, CLIENTE, PEDIDO, QUANT*). Read once per sheet through Excel COM, read-only.
    2. The folder of "Pedido Interno de Venda" workbooks (one xlsx per order, sheet "Pedido"). They are read as zip files (no Excel), cells are
       found by their LABEL (CLIENTE:, DIMENSOES DO TUBO (MM):, QUANTIDADE (KG/PC):, ESPECIFICACAO DO MATERIAL:, PRECO DE VENDA:, DATA) because the
       layout shifts between years. Gives the material specification, which moves the price.
  Output: ';'-separated UTF-8 CSV with the header  date;customer;diameter;thickness;length;unit;price;quantity;spec
  (spec is the raw text; the server classifies it into EN10305 / NBK / BK / NBR / SAE / other).
  The same sale repeated (monthly sheets, both sources) is kept once: key = first 6 letters of the customer | diameter | thickness | length | unit |
  price (2 decimals); the row with the latest date wins and a row with a specification is preferred. The file holds real customer prices:
  it is git-ignored (price-history*.csv). Nothing is written to the database; import the CSV in the app or with
  POST /api/sales/price-history/import.

  Windows PowerShell 5.1. Saved as UTF-8 with BOM.
#>
param(
    [string]$Workbook = 'C:\Users\italo\Desktop\EBT\Pedidos de Vendas\PEDIDO DE VENDAS Anos 24 & 26 - EBT e BST.xlsx',
    [string]$PedidosFolder = 'C:\Users\italo\Desktop\EBT\Pedidos de Vendas\PEDIDOS DE VENDAS  BST 25 & 26',
    [string]$Out = (Join-Path (Split-Path $PSScriptRoot -Parent) 'price-history.csv')
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

function Fold([string]$s) {
    if ($null -eq $s) { return '' }
    $d = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $d.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') { [void]$sb.Append($c) } }
    return $sb.ToString().ToUpperInvariant().Trim()
}

function ToNum($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [double] -or $v -is [int] -or $v -is [decimal]) { return [double]$v }
    $s = ([string]$v).Replace('R$', '').Replace(' ', '').Replace([string][char]0xA0, '')
    if ($s -eq '') { return $null }
    $comma = $s.LastIndexOf(','); $dot = $s.LastIndexOf('.')
    if ($comma -ge 0 -and $dot -ge 0) { if ($comma -gt $dot) { $s = $s.Replace('.', '').Replace(',', '.') } else { $s = $s.Replace(',', '') } }
    elseif ($comma -ge 0) { $s = $s.Replace(',', '.') }
    elseif (($s.ToCharArray() | Where-Object { $_ -eq '.' }).Count -gt 1) { $s = $s.Replace('.', '') }
    $r = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, $inv, [ref]$r)) { return $r }
    return $null
}

function ToUnit([string]$u) {
    $f = (Fold $u).Replace('.', '').Replace(' ', '')
    switch ($f) { 'KG' { return 'KG' } 'PC' { return 'PC' } 'PCS' { return 'PC' } default { return $null } }
}

function CustomerKey([string]$name) {
    $letters = ([regex]::Replace((Fold $name), '[^A-Z]', '')).ToLowerInvariant()
    if ($letters.Length -gt 6) { return $letters.Substring(0, 6) }
    return $letters
}

function Fmt([double]$v) { return $v.ToString('0.####', $inv) }

# ---------------------------------------------------------------------------------------------------------------------------------------------------
# Source 2: "Pedido Interno de Venda" workbooks, read as zip + XML (compiled helper: thousands of files in seconds).
# ---------------------------------------------------------------------------------------------------------------------------------------------------
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

public class PedidoRow
{
    public string File, Num, Customer, Spec, Unit, Problem;
    public double D, T, L, Qty, Price;
    public DateTime Date;
}

public static class PedidoReader
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

    static List<Cell> Load(ZipArchive zip)
    {
        List<string> shared = new List<string>();
        ZipArchiveEntry se = zip.GetEntry("xl/sharedStrings.xml");
        if (se != null)
            using (Stream st = se.Open())
                foreach (XElement si in XDocument.Load(st).Root.Elements(Ns + "si"))
                    shared.Add(string.Concat(si.Elements(Ns + "t").Concat(si.Elements(Ns + "r").Elements(Ns + "t")).Select(x => x.Value)));
        ZipArchiveEntry sheet = zip.GetEntry("xl/worksheets/sheet1.xml");
        if (sheet == null) sheet = zip.Entries.Where(e => Regex.IsMatch(e.FullName, @"^xl/worksheets/sheet\d+\.xml$")).OrderBy(e => e.FullName).FirstOrDefault();
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

    // Text after the colon of the label cell, or else the next non-empty cell to the right.
    static string ValueOf(List<Cell> cells, Cell label)
    {
        int i = label.Text.IndexOf(':');
        if (i >= 0 && label.Text.Substring(i + 1).Trim().Length > 0) return label.Text.Substring(i + 1).Trim();
        Cell next = Right(cells, label).FirstOrDefault();
        return next == null ? null : next.Text;
    }

    static Cell Label(List<Cell> cells, string prefix)
    {
        return cells.FirstOrDefault(x => x.Fold.StartsWith(prefix, StringComparison.Ordinal));
    }

    public static PedidoRow Read(string path)
    {
        PedidoRow o = new PedidoRow { File = Path.GetFileName(path) };
        try
        {
            List<Cell> cells;
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (ZipArchive zip = new ZipArchive(fs, ZipArchiveMode.Read))
                cells = Load(zip);
            Cell first = cells.FirstOrDefault(x => x.Row == 1 && x.Col > 3);
            o.Num = first == null ? "" : first.Text;

            Cell cl = Label(cells, "CLIENTE:");
            o.Customer = cl == null ? null : ValueOf(cells, cl);
            Cell dl = Label(cells, "DIMENSOES DO TUBO");
            string dims = dl == null ? null : ValueOf(cells, dl);
            if (dims != null)
            {
                Match m = Regex.Match(Fold(dims), @"(\d[\d.,]*)\s*X\s*(\d[\d.,]*)\s*X\s*(\d[\d.,]*)");
                if (m.Success)
                {
                    o.D = ParseNum(m.Groups[1].Value, false) ?? 0;
                    o.T = ParseNum(m.Groups[2].Value, false) ?? 0;
                    o.L = ParseNum(m.Groups[3].Value, true) ?? 0;
                }
            }
            Cell ql = Label(cells, "QUANTIDADE");
            if (ql != null)
            {
                List<Cell> r = Right(cells, ql);
                if (r.Count >= 1) o.Qty = r[0].IsNum ? r[0].Num : (ParseNum(r[0].Text, false) ?? 0);
                if (r.Count >= 2) o.Unit = Fold(r[1].Text).Replace(".", "").Replace(" ", "");
            }
            Cell sl = Label(cells, "ESPECIFICACAO DO MATERIAL");
            o.Spec = sl == null ? null : ValueOf(cells, sl);
            Cell pl = Label(cells, "PRECO DE VENDA");
            if (pl != null)
            {
                Cell p = Right(cells, pl).FirstOrDefault();
                if (p != null) o.Price = p.IsNum ? p.Num : (ParseNum(p.Text, false) ?? 0);
            }

            // Signature date: the cell just above the last "DATA" label.
            DateTime? date = null;
            foreach (Cell lab in cells.Where(x => x.Fold == "DATA" || x.Fold == "DATA:").OrderByDescending(x => x.Row).ThenBy(x => x.Col))
            {
                Cell above = cells.Where(x => x.Col == lab.Col && x.Row < lab.Row && x.Row >= lab.Row - 3).OrderByDescending(x => x.Row).FirstOrDefault();
                date = ParseDate(above);
                if (date != null) break;
            }
            if (date == null && cells.Count > 0)
            {
                // No usable "DATA" label (blank or missing): a date in the left columns of the last rows is the signature date.
                int maxRow = cells.Max(x => x.Row);
                Cell dc = cells.Where(x => x.Row >= maxRow - 8 && x.Col <= 5 && ParseDate(x) != null).OrderByDescending(x => x.Row).FirstOrDefault();
                if (dc != null) date = ParseDate(dc);
            }
            if (date == null)
            {
                Match y = Regex.Match(o.Num ?? "", @"[-/](\d{2})\s*$");
                if (y.Success) date = new DateTime(2000 + int.Parse(y.Groups[1].Value), 6, 30);
            }
            // A year typo in the future (e.g. 2027 for 2026) is pulled back a year.
            if (date != null && date.Value > DateTime.Today.AddDays(30)) date = date.Value.AddYears(-1);
            if (date != null) o.Date = date.Value;

            if (string.IsNullOrWhiteSpace(o.Customer)) o.Problem = "no customer";
            else if (!(o.D > 0 && o.T > 0 && o.L > 0) || o.T * 2 >= o.D) o.Problem = "dimensions";
            else if (!(o.Price > 0)) o.Problem = "price";
            else if (o.Unit != "KG" && o.Unit != "PC" && o.Unit != "PCS") o.Problem = "unit";
            else if (date == null) o.Problem = "date";
            if (o.Unit == "PCS") o.Unit = "PC";
        }
        catch (Exception ex) { o.Problem = "error: " + ex.Message; }
        return o;
    }
}
'@
if (-not ('PedidoReader' -as [type])) {
    Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Xml.Linq', 'System.IO.Compression', 'System.IO.Compression.FileSystem', 'System.Xml', 'System.Core'
}

$rows = New-Object System.Collections.Generic.List[object]

# ---------------------------------------------------------------------------------------------------------------------------------------------------
# Source 1: master workbook through Excel COM (read-only, one Value2 read per sheet).
# ---------------------------------------------------------------------------------------------------------------------------------------------------
if (Test-Path -LiteralPath $Workbook) {
    $excel = $null; $wb = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false; $excel.DisplayAlerts = $false
        $wb = $excel.Workbooks.Open($Workbook, 0, $true)
        $seen = @{}
        $masterRead = 0
        foreach ($ws in $wb.Worksheets) {
            $ur = $ws.UsedRange
            $lastRow = $ur.Row + $ur.Rows.Count - 1
            $lastCol = $ur.Column + $ur.Columns.Count - 1
            if ($lastRow -lt 3) { continue }
            $data = $ws.Range($ws.Cells(1, 1), $ws.Cells($lastRow, $lastCol)).Value2
            $col = @{}
            for ($c = 1; $c -le $lastCol; $c++) {
                $h = Fold ([string]$data[2, $c])
                if ($h -eq '') { continue }
                if ($h -eq 'DIAMETRO') { $col['d'] = $c }
                elseif ($h -eq 'ESPESSURA') { $col['t'] = $c }
                elseif ($h.StartsWith('COMPRIM')) { $col['l'] = $c }
                elseif ($h -eq 'UNID' -or $h -eq 'UNID.') { $col['u'] = $c }
                elseif ($h.StartsWith('VALOR UNIT')) { $col['p'] = $c }
                elseif ($h -eq 'DATA') { $col['date'] = $c }
                elseif ($h -eq 'CLIENTE') { $col['cust'] = $c }
                elseif ($h -match 'PEDIDO' -and -not $col.ContainsKey('ped')) { $col['ped'] = $c }
                elseif ($h.StartsWith('QUANT')) { $col['q'] = $c }
            }
            if (-not ($col.ContainsKey('d') -and $col.ContainsKey('t') -and $col.ContainsKey('l') -and $col.ContainsKey('u') -and $col.ContainsKey('p') -and $col.ContainsKey('date') -and $col.ContainsKey('cust'))) { continue }
            for ($r = 3; $r -le $lastRow; $r++) {
                $d = ToNum $data[$r, $col['d']]; $t = ToNum $data[$r, $col['t']]; $l = ToNum $data[$r, $col['l']]; $p = ToNum $data[$r, $col['p']]
                if ($null -eq $d -or $null -eq $t -or $null -eq $l -or $null -eq $p) { continue }
                if ($d -le 0 -or $t -le 0 -or $l -le 0 -or $p -le 0 -or $t * 2 -ge $d) { continue }
                $unit = ToUnit ([string]$data[$r, $col['u']])
                if ($null -eq $unit) { continue }
                $serial = $data[$r, $col['date']]
                if ($serial -isnot [double] -or $serial -lt 40000 -or $serial -gt 48000) { continue }
                $cust = ([string]$data[$r, $col['cust']]).Trim()
                if ($cust -eq '') { continue }
                $q = 0.0; if ($col.ContainsKey('q')) { $qv = ToNum $data[$r, $col['q']]; if ($null -ne $qv) { $q = $qv } }
                $ped = ''; if ($col.ContainsKey('ped')) { $ped = ([string]$data[$r, $col['ped']]).Trim() }
                $masterRead++
                # The same order repeated across the monthly sheets: keep the earliest.
                $k = ($ped, $cust.ToLowerInvariant(), (Fmt $d), (Fmt $t), (Fmt $l), (Fmt $p), (Fmt $q)) -join '|'
                $date = [DateTime]::FromOADate([math]::Floor($serial))
                if ($seen.ContainsKey($k)) { if ($date -lt $seen[$k].Date) { $seen[$k].Date = $date }; continue }
                $row = [pscustomobject]@{ Date = $date; Customer = $cust; D = $d; T = $t; L = $l; Unit = $unit; Price = $p; Qty = $q; Spec = '' }
                $seen[$k] = $row
                $rows.Add($row)
            }
        }
        Write-Host ("Master workbook: {0} sale lines read, {1} after removing repeats across sheets" -f $masterRead, $rows.Count)
    }
    finally {
        if ($wb) { $wb.Close($false) | Out-Null }
        if ($excel) { $excel.Quit() | Out-Null; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    }
}
else { Write-Warning "Master workbook not found: $Workbook (skipped)" }
$masterCount = $rows.Count

# Source 2: pedido internos.
$pedidoUsable = 0; $pedidoFiles = 0; $problems = @{}
if (Test-Path -LiteralPath $PedidosFolder) {
    foreach ($f in Get-ChildItem -LiteralPath $PedidosFolder -Filter '*.xlsx' -File) {
        if ($f.Name.StartsWith('~$')) { continue }
        $pedidoFiles++
        $o = [PedidoReader]::Read($f.FullName)
        if ($o.Problem) { if ($problems.ContainsKey($o.Problem)) { $problems[$o.Problem]++ } else { $problems[$o.Problem] = 1 }; continue }
        $pedidoUsable++
        $spec = ''
        if ($o.Spec) { $spec = ($o.Spec -replace '[;\r\n]+', ' ').Trim() }
        $rows.Add([pscustomobject]@{ Date = $o.Date; Customer = (($o.Customer -replace '[;\r\n]+', ' ').Trim()); D = $o.D; T = $o.T; L = $o.L; Unit = $o.Unit; Price = $o.Price; Qty = $o.Qty; Spec = $spec })
    }
    Write-Host ("Pedidos internos: {0} files, {1} usable" -f $pedidoFiles, $pedidoUsable)
    foreach ($k in $problems.Keys) { Write-Host ("  skipped ({0}): {1}" -f $k, $problems[$k]) }
}
else { Write-Warning "Pedidos folder not found: $PedidosFolder (skipped)" }

# Merge: one row per sale; latest date wins, a known specification is kept.
$merged = @{}
foreach ($r in $rows) {
    $k = ((CustomerKey $r.Customer), (Fmt $r.D), (Fmt $r.T), (Fmt $r.L), $r.Unit, $r.Price.ToString('0.00', $inv)) -join '|'
    if (-not $merged.ContainsKey($k)) { $merged[$k] = $r; continue }
    $old = $merged[$k]
    if ($r.Date -ge $old.Date) { if (-not $r.Spec) { $r.Spec = $old.Spec }; $merged[$k] = $r }
    elseif (-not $old.Spec) { $old.Spec = $r.Spec }
}
$final = $merged.Values | Sort-Object Date, Customer
$sb = New-Object Text.StringBuilder
[void]$sb.Append("date;customer;diameter;thickness;length;unit;price;quantity;spec`r`n")
foreach ($r in $final) {
    $cust = ($r.Customer -replace '[;\r\n"]+', ' ').Trim()
    [void]$sb.Append(('{0};{1};{2};{3};{4};{5};{6};{7};{8}' -f $r.Date.ToString('yyyy-MM-dd'), $cust, (Fmt $r.D), (Fmt $r.T), (Fmt $r.L), $r.Unit, (Fmt $r.Price), (Fmt $r.Qty), ($r.Spec -replace '"', '')))
    [void]$sb.Append("`r`n")
}
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
$withSpec = ($final | Where-Object { $_.Spec }).Count
Write-Host ("Merged: {0} unique sales ({1} with specification), {2} to {3}" -f $final.Count, $withSpec, ($final | Select-Object -First 1).Date.ToString('yyyy-MM'), ($final | Select-Object -Last 1).Date.ToString('yyyy-MM'))
Write-Host "Written: $Out"
