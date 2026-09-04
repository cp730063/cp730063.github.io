# Zips the parts staged by scripts/make_methodology_xlsx.pl into a real .xlsx.
#   perl scripts/make_methodology_xlsx.pl      # stage the XML parts
#   powershell -File scripts/make_methodology_xlsx.ps1
$root  = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root '.xlsx_stage'
$out   = Join-Path $root 'FantasyMags-Methodology.xlsx'
if (Test-Path -LiteralPath $out) { [System.IO.File]::Delete($out) }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fs  = [System.IO.File]::Open($out, [System.IO.FileMode]::CreateNew)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
$parts = @(
  '[Content_Types].xml',
  '_rels/.rels',
  'xl/workbook.xml',
  'xl/_rels/workbook.xml.rels',
  'xl/styles.xml',
  'xl/worksheets/sheet1.xml'
)
$sep = [char]92
foreach ($p in $parts) {
  $src   = Join-Path $stage ($p.Replace('/', $sep))
  $entry = $zip.CreateEntry($p, [System.IO.Compression.CompressionLevel]::Optimal)
  $es    = $entry.Open()
  $bytes = [System.IO.File]::ReadAllBytes($src)
  $es.Write($bytes, 0, $bytes.Length); $es.Close()
}
$zip.Dispose(); $fs.Close()
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Output ("wrote {0} ({1} bytes)" -f $out, (Get-Item -LiteralPath $out).Length)
