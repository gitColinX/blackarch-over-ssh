#Requires -Version 5.1
<#
.SYNOPSIS
  Converts every .md in a folder to a styled .html and a .pdf next to it.
  md -> html : python 'markdown' module (pip install markdown)
  html -> pdf: Microsoft Edge headless (--print-to-pdf), present on every Windows 11.
.EXAMPLE
  .\Build-Guides.ps1 -Path C:\Projects\BlackArch
#>
param(
  [string] $Path = (Split-Path $PSScriptRoot -Parent),
  [string[]] $Exclude = @('README.md')
)
$ErrorActionPreference = 'Stop'
$edge = @('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "Edge not found - cannot make PDFs." }

$css = @'
body{font-family:Segoe UI,Arial,sans-serif;max-width:900px;margin:32px auto;padding:0 24px;line-height:1.5;color:#222}
h1{border-bottom:3px solid #c00;padding-bottom:6px} h2{margin-top:2em;border-bottom:1px solid #ccc;padding-bottom:4px;page-break-after:avoid}
code{background:#f3f3f3;padding:1px 5px;border-radius:3px;font-family:Consolas,monospace;font-size:0.95em}
pre{background:#1e1e1e;color:#eee;padding:12px 14px;border-radius:6px;overflow-x:auto;page-break-inside:avoid} pre code{background:none;color:inherit;padding:0}
table{border-collapse:collapse;width:100%;margin:12px 0;page-break-inside:avoid} th,td{border:1px solid #bbb;padding:6px 9px;text-align:left;vertical-align:top} th{background:#eee}
blockquote{border-left:4px solid #c00;margin:0;padding:4px 14px;background:#fff6f6}
strong{color:#000} @media print{body{margin:0;max-width:none;font-size:11pt} pre{white-space:pre-wrap}}
'@

$py = @'
import sys, markdown, io
src, dst, css, title = sys.argv[1:5]
text = io.open(src, encoding='utf-8').read()
body = markdown.markdown(text, extensions=['tables','fenced_code','sane_lists','toc'])
html = f"<!doctype html><html><head><meta charset='utf-8'><title>{title}</title><style>{css}</style></head><body>{body}</body></html>"
io.open(dst, 'w', encoding='utf-8').write(html)
'@
$pyFile = Join-Path $env:TEMP 'md2html.py'
Set-Content $pyFile $py -Encoding UTF8

Get-ChildItem -Path $Path -Filter *.md -File | Where-Object { $Exclude -notcontains $_.Name } | ForEach-Object {
  $html = [IO.Path]::ChangeExtension($_.FullName, '.html')
  $pdf  = [IO.Path]::ChangeExtension($_.FullName, '.pdf')
  python $pyFile $_.FullName $html $css $_.BaseName
  if ($LASTEXITCODE) { throw "markdown conversion failed for $($_.Name)" }
  $uri = 'file:///' + ($html -replace '\\','/')
  & $edge --headless=new --disable-gpu --no-first-run --no-default-browser-check --print-to-pdf="$pdf" --no-pdf-header-footer $uri 2>$null | Out-Null
  $i = 0; while (-not (Test-Path $pdf) -and $i -lt 30) { Start-Sleep -Milliseconds 500; $i++ }
  if (Test-Path $pdf) { "{0,-40} -> .html ({1:N0} KB) + .pdf ({2:N0} KB)" -f $_.Name, ((Get-Item $html).Length/1KB), ((Get-Item $pdf).Length/1KB) }
  else { Write-Warning "PDF not produced for $($_.Name)" }
}
