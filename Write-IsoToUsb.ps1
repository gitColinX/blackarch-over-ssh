#Requires -Version 5.1
<#
.SYNOPSIS
  Raw-writes a Linux ISO to a USB stick (Windows equivalent of `dd if=file.iso of=/dev/sdX`).
.DESCRIPTION
  BlackArch says: do NOT use UNetbootin; just dd the hybrid ISO to the whole device.
  Rufus is unreliable on this PC, so this script does the dd part natively:
    1. self-elevates (needs admin to open \\.\PhysicalDriveN)
    2. optional SHA1 check of the ISO against the value on blackarch.org
    3. refuses anything that is not a USB bus device, or that is the Windows system disk
    4. dismounts volumes, Clear-Disk, then streams the ISO byte-for-byte to the raw device
.EXAMPLE
  .\Write-IsoToUsb.ps1 -IsoPath "$env:USERPROFILE\Downloads\blackarch-linux-netinst-2023.04.01-x86_64.iso" -DiskNumber 2 -ExpectedSha1 df2dfcfafa1a8f9bab8afd9aa6b788de00e03e09
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $IsoPath,
  [Parameter(Mandatory)] [int]    $DiskNumber,
  [string] $ExpectedSha1,
  [switch] $Force          # skip the interactive "type the disk number" confirmation
)

$ErrorActionPreference = 'Stop'

# ---- self-elevate -----------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
if (-not $isAdmin) {
  Write-Host "Not elevated - relaunching as Administrator..." -ForegroundColor Yellow
  $argList = @('-NoExit','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-IsoPath',"`"$IsoPath`"",'-DiskNumber',$DiskNumber)
  if ($ExpectedSha1) { $argList += @('-ExpectedSha1',$ExpectedSha1) }
  if ($Force)        { $argList += '-Force' }
  $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
  Start-Process $exe -Verb RunAs -ArgumentList $argList
  return
}

# ---- checks -----------------------------------------------------------------
$iso = Get-Item -LiteralPath $IsoPath
Write-Host ("ISO : {0} ({1:N1} MB)" -f $iso.FullName, ($iso.Length/1MB))

if ($ExpectedSha1) {
  Write-Host "Checking SHA1..." -NoNewline
  $actual = (Get-FileHash -LiteralPath $iso.FullName -Algorithm SHA1).Hash.ToLower()
  if ($actual -ne $ExpectedSha1.ToLower()) { throw "SHA1 mismatch! expected $ExpectedSha1 got $actual - download is corrupt, do not write it." }
  Write-Host " OK ($actual)" -ForegroundColor Green
}

$disk = Get-Disk -Number $DiskNumber
$sysDisk = (Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) ).DiskNumber
if ($disk.BusType -ne 'USB')     { throw "Disk $DiskNumber ($($disk.FriendlyName)) is on bus '$($disk.BusType)', not USB. Refusing." }
if ($DiskNumber -eq $sysDisk)    { throw "Disk $DiskNumber is the Windows system disk. Refusing." }
if ($disk.Size -lt $iso.Length)  { throw "Disk is smaller than the ISO." }

$vols = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("TARGET: Disk {0}  {1}  {2:N1} GB  [{3}]" -f $disk.Number, $disk.FriendlyName, ($disk.Size/1GB), $disk.BusType) -ForegroundColor Cyan
foreach ($v in $vols) { Write-Host ("        volume {0}: '{1}' {2} {3:N1} GB" -f $v.DriveLetter, $v.FileSystemLabel, $v.FileSystem, ($v.Size/1GB)) -ForegroundColor Cyan }
Write-Host "EVERYTHING ON THIS DISK WILL BE ERASED." -ForegroundColor Red
if (-not $Force) {
  $ans = Read-Host "Type the disk number ($DiskNumber) to continue"
  if ($ans -ne "$DiskNumber") { Write-Host "Aborted."; return }
}

# ---- wipe + dismount --------------------------------------------------------
Write-Host "Dismounting and clearing disk $DiskNumber..."
Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.DriveLetter) { Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $_.PartitionNumber -AccessPath "$($_.DriveLetter):" -ErrorAction SilentlyContinue }
}
Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
Set-Disk -Number $DiskNumber -IsOffline  $false -ErrorAction SilentlyContinue
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
Start-Sleep -Seconds 2

# ---- raw write --------------------------------------------------------------
$dev = "\\.\PhysicalDrive$DiskNumber"
Write-Host "Writing $($iso.Name) -> $dev"
$sector = 512
$chunk  = 4MB
$buf    = New-Object byte[] $chunk
$in  = [System.IO.File]::Open($iso.FullName, 'Open', 'Read', 'Read')
$out = New-Object System.IO.FileStream($dev, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, $chunk, [System.IO.FileOptions]::WriteThrough)
try {
  $total = $iso.Length; $done = 0L; $sw = [Diagnostics.Stopwatch]::StartNew(); $lastPct = -1
  while (($n = $in.Read($buf, 0, $chunk)) -gt 0) {
    if ($n % $sector) {                       # pad final partial sector with zeros
      $pad = $sector - ($n % $sector)
      [Array]::Clear($buf, $n, $pad); $n += $pad
    }
    $out.Write($buf, 0, $n); $done += $n
    $pct = [int](100 * $done / $total)
    if ($pct -ne $lastPct) {
      $mbps = if ($sw.Elapsed.TotalSeconds -gt 0) { ($done/1MB)/$sw.Elapsed.TotalSeconds } else { 0 }
      Write-Progress -Activity "Writing ISO to $dev" -Status ("{0}%  {1:N0} / {2:N0} MB  {3:N1} MB/s" -f $pct, ($done/1MB), ($total/1MB), $mbps) -PercentComplete $pct
      $lastPct = $pct
    }
  }
  $out.Flush()
}
finally { $out.Dispose(); $in.Dispose() }
Write-Progress -Activity "Writing ISO to $dev" -Completed
Write-Host ("Done: {0:N0} MB written in {1:N0}s" -f ($done/1MB), $sw.Elapsed.TotalSeconds) -ForegroundColor Green

# ---- verify first bytes -----------------------------------------------------
Update-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
$chk = New-Object System.IO.FileStream($dev, 'Open', 'Read', 'ReadWrite', 1MB)
try { $rb = New-Object byte[] 1MB; [void]$chk.Read($rb,0,1MB) } finally { $chk.Dispose() }
$in2 = [System.IO.File]::OpenRead($iso.FullName); $ib = New-Object byte[] 1MB; [void]$in2.Read($ib,0,1MB); $in2.Dispose()
if ([Linq.Enumerable]::SequenceEqual($rb,$ib)) { Write-Host "Verify: first 1 MB on stick matches ISO." -ForegroundColor Green }
else { Write-Host "Verify: first 1 MB DOES NOT match - re-run." -ForegroundColor Red }
Write-Host ""
Write-Host "If Windows pops up 'You need to format the disk' - click CANCEL. That is normal for a Linux ISO stick." -ForegroundColor Yellow
Write-Host "Safely eject the stick, then boot the Dell from it (F12 one-time boot menu, UEFI entry, Secure Boot OFF)."
