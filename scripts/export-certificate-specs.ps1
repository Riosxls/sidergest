<#
.SYNOPSIS
  Adds the "found" (Encontrado) value of the source certificate to every row of
  src/Ebt.Core/Certificates/legacy-specs.json.

.DESCRIPTION
  For each entry (customer + product) the Excel certificate named in "learnedFrom"
  (e.g. "1904-25") is located under -Root, opened read-only through Excel COM (once per
  workbook) and the printed "Encontr." text of each chemical / dimensional / mechanical row
  is stored as "found" right after "specified". Existing fields are kept as they are.
  A "-" on the sheet stays "-"; an empty cell becomes null; a missing or unreadable file
  leaves found = null for that entry and is listed at the end.

  Rows are matched by name (chemical: column B, dimensional and mechanical: column F), with the
  header row located on each sheet because the layout shifts by one or two rows. A name that
  appears twice (e.g. two "Teste Destrutivo" rows) is matched in order of appearance.

.EXAMPLE
  powershell -File scripts\export-certificate-specs.ps1
#>
param(
    [string]$Root = 'C:\Users\italo\Desktop\EBT\Certificados',
    [string]$Json = (Join-Path $PSScriptRoot '..\src\Ebt.Core\Certificates\legacy-specs.json')
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$Json = [IO.Path]::GetFullPath($Json)

function Norm([string]$s) {
    if ($null -eq $s) { return '' }
    $d = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) }
    }
    return ($sb.ToString().ToLowerInvariant() -replace '\s+', ' ').Trim()
}

# Minimal JSON writer: 1-space indent, CRLF, raw UTF-8, property order kept, no trailing newline.
function ToJson($v, [int]$level) {
    $pad = ' ' * ($level + 1)
    $padEnd = ' ' * $level
    if ($null -eq $v) { return 'null' }
    if ($v -is [string]) {
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in $v.ToCharArray()) {
            switch ($ch) {
                '"' { [void]$sb.Append('\"') }
                '\' { [void]$sb.Append('\\') }
                "`n" { [void]$sb.Append('\n') }
                "`r" { [void]$sb.Append('\r') }
                "`t" { [void]$sb.Append('\t') }
                default { if ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
            }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [double] -or $v -is [decimal] -or $v -is [single]) { return ([double]$v).ToString('R', $inv) }
    if ($v -is [int] -or $v -is [long]) { return $v.ToString($inv) }
    if ($v -is [System.Collections.IList]) {
        if ($v.Count -eq 0) { return '[]' }
        $items = foreach ($i in $v) { $pad + (ToJson $i ($level + 1)) }
        return "[`r`n" + ($items -join ",`r`n") + "`r`n" + $padEnd + ']'
    }
    if ($v -is [pscustomobject]) {
        $props = @($v.PSObject.Properties)
        if ($props.Count -eq 0) { return '{}' }
        $items = foreach ($p in $props) { $pad + (ToJson $p.Name 0) + ': ' + (ToJson $p.Value ($level + 1)) }
        return "{`r`n" + ($items -join ",`r`n") + "`r`n" + $padEnd + '}'
    }
    throw "Unsupported type $($v.GetType().FullName)"
}

function CellText($ws, [int]$row, [string]$col) {
    $c = $ws.Range("$col$row")
    $t = [string]$c.Text
    if ($t -match '^#+$') { $t = [string]$c.Value2 }
    $t = $t.Trim()
    if ($t -eq '') { return $null }
    return $t
}

function SameSpec($jsonSpec, $sheetSpec) {
    $a = if ($null -eq $jsonSpec -or $jsonSpec -eq '-') { '' } else { Norm $jsonSpec }
    $b = if ($null -eq $sheetSpec -or $sheetSpec -eq '-') { '' } else { Norm $sheetSpec }
    return $a -eq $b
}

function AddRow($map, [string]$key, [int]$row) {
    if (-not $map.ContainsKey($key)) { $map[$key] = New-Object Collections.Generic.List[int] }
    $map[$key].Add($row)
}

# ---- load -------------------------------------------------------------------------------
$entries = [IO.File]::ReadAllText($Json, [Text.Encoding]::UTF8) | ConvertFrom-Json
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in '.xls', '.xlsx', '.xlsm' })
Write-Host "Certificate files under ${Root}: $($files.Count)"

function FindFile($e) {
    $n = [regex]::Escape($e.learnedFrom)
    $m = @($files | Where-Object { $_.Name -match "^Certificado\s+$n\s*-" })
    if ($m.Count -le 1) { return $m }
    # the same number on two files: pick the one whose D x E x C in the name matches the entry
    $dims = @([double]$e.diameter, [double]$e.thickness, [double]$e.length)
    $hit = @($m | Where-Object {
            if ($_.Name -match '(?i)(\d+(?:,\d+)?)\s*X\s*(\d+(?:,\d+)?)\s*X\s*(\d+(?:,\d+)?)') {
                $vals = 1..3 | ForEach-Object { [double]::Parse($Matches[$_].Replace(',', '.'), $inv) }
                $ok = $true
                for ($i = 0; $i -lt 3; $i++) { if ([math]::Abs($vals[$i] - $dims[$i]) -gt 0.001) { $ok = $false } }
                $ok
            } else { $false }
        })
    return $hit
}

$stats = [ordered]@{ entries = 0; entriesFound = 0; rows = 0; rowsFound = 0 }
$problems = New-Object Collections.Generic.List[string]
$specDiffs = New-Object Collections.Generic.List[string]
$sections = 'chemical', 'dimensional', 'mechanical'

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false
$xl.AskToUpdateLinks = $false
try {
    foreach ($e in $entries) {
        $stats.entries++
        $label = "$($e.learnedFrom) $($e.customer) $($e.diameter)x$($e.thickness)x$($e.length)"
        foreach ($s in $sections) { foreach ($r in @($e.$s)) { $stats.rows++ } }

        $m = @(FindFile $e)
        $values = @{}   # section -> array of found values by row index
        $wb = $null
        $ok = $false
        if ($m.Count -ne 1) {
            $problems.Add("$label : certificate file " + $(if ($m.Count -eq 0) { 'not found' } else { "ambiguous ($($m.Count))" }))
        } else {
            try {
                $wb = $xl.Workbooks.Open($m[0].FullName, 0, $true)
                $ws = $wb.Worksheets.Item(1)
                $last = 70

                # header row of the chemical table: first row with "Especif" in column C
                $chemHead = 0; $ensaios = 0; $acab = 0
                for ($r = 15; $r -le $last; $r++) {
                    $c = Norm ([string]$ws.Range("C$r").Value2)
                    $f = Norm ([string]$ws.Range("F$r").Value2)
                    if (-not $chemHead -and $c -like 'especif*') { $chemHead = $r }
                    if (-not $ensaios -and $f -like 'ensaios*') { $ensaios = $r }
                    if (-not $acab -and $f -like 'acabamento*') { $acab = $r }
                }
                if (-not $chemHead) { throw 'layout not recognised (no chemical header)' }
                if (-not $acab) { $acab = $last }
                # some sheets have no mechanical block: dimensional then runs to the finish line
                if (-not $ensaios) { $ensaios = $acab }

                $chemRows = @{}; $dimRows = @{}; $mecRows = @{}
                # chemical: element name in column B
                for ($r = $chemHead + 1; $r -le $chemHead + 14; $r++) {
                    $k = Norm ([string]$ws.Range("B$r").Value2)
                    if ($k) { AddRow $chemRows $k $r }
                }
                # dimensional: column F between the chemical header and "Ensaios"
                for ($r = $chemHead + 1; $r -lt $ensaios; $r++) {
                    $k = Norm ([string]$ws.Range("F$r").Value2)
                    if ($k) { AddRow $dimRows $k $r }
                }
                # mechanical: column F between "Ensaios" and "Acabamento"
                for ($r = $ensaios + 1; $r -lt $acab; $r++) {
                    $k = Norm ([string]$ws.Range("F$r").Value2)
                    if ($k -and $k -notmatch '^-+$') { AddRow $mecRows $k $r }
                }

                $plan = @(
                    @{ s = 'chemical'; map = $chemRows; spec = 'C'; found = 'D' },
                    @{ s = 'dimensional'; map = $dimRows; spec = 'H'; found = 'I' },
                    @{ s = 'mechanical'; map = $mecRows; spec = 'H'; found = 'I' }
                )
                foreach ($p in $plan) {
                    $arr = @()
                    $seen = @{}   # n-th JSON row with a name takes the n-th sheet row with that name
                    foreach ($row in @($e.($p.s))) {
                        $k = Norm $row.name
                        $nth = [int]$seen[$k]
                        $seen[$k] = $nth + 1
                        if (-not $p.map.ContainsKey($k) -or $nth -ge $p.map[$k].Count) {
                            $arr += , $null
                            $problems.Add("$label : $($p.s) row '$($row.name)' not on the sheet")
                            continue
                        }
                        $rr = $p.map[$k][$nth]
                        $sheetSpec = CellText $ws $rr $p.spec
                        if (-not (SameSpec $row.specified $sheetSpec)) {
                            $specDiffs.Add("$label : $($p.s) '$($row.name)' json='$($row.specified)' sheet='$sheetSpec'")
                        }
                        $arr += , (CellText $ws $rr $p.found)
                    }
                    $values[$p.s] = $arr
                }
                $ok = $true
            } catch {
                $problems.Add("$label : could not read $($m[0].Name): $($_.Exception.Message)")
            } finally {
                if ($wb) { $wb.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
            }
        }

        foreach ($s in $sections) {
            $rows = @($e.$s)
            for ($i = 0; $i -lt $rows.Count; $i++) {
                $val = $null
                if ($ok -and $values.ContainsKey($s)) { $val = $values[$s][$i] }
                if ($null -ne $val) { $stats.rowsFound++ }
                # rebuild the row so that "found" follows "specified"
                $o = [ordered]@{}
                foreach ($p in $rows[$i].PSObject.Properties) { if ($p.Name -ne 'found') { $o[$p.Name] = $p.Value } }
                $o['found'] = $val
                $rows[$i] = [pscustomobject]$o
            }
            $e.$s = $rows
        }
        if ($ok) { $stats.entriesFound++ }
    }
} finally {
    $xl.Quit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl)
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

[IO.File]::WriteAllText($Json, (ToJson $entries 0), (New-Object Text.UTF8Encoding($false)))

Write-Host "Entries: $($stats.entriesFound)/$($stats.entries) read; rows with a found value: $($stats.rowsFound)/$($stats.rows)"
if ($problems.Count) { Write-Host "`nProblems:"; $problems | ForEach-Object { Write-Host "  $_" } }
if ($specDiffs.Count) { Write-Host "`nSpec on sheet differs from JSON ($($specDiffs.Count)):"; $specDiffs | ForEach-Object { Write-Host "  $_" } }
