# ============================================================
#  C-drive cleanup (auto-elevate, self-contained)
#  Cleans: old NVIDIA driver installers (C:\DrvPath),
#  user Temp leftovers, Windows Update download cache.
#  Run once; auto-requests elevation via UAC if not admin.
#  Usage: powershell -ExecutionPolicy Bypass -File "C:\Users\malco\c-drive-cleanup.ps1"
# ============================================================

# Auto-elevate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Not admin. Requesting elevation...' -ForegroundColor Cyan
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { $self = 'C:\Users\malco\c-drive-cleanup.ps1' }
    $arg = '-ExecutionPolicy Bypass -File "' + $self + '"'
    try {
        Start-Process powershell -Verb RunAs -ArgumentList $arg
        Write-Host 'Elevation requested. Click YES in the UAC prompt.' -ForegroundColor Green
    } catch {
        Write-Host 'Elevation failed. Run from an admin shell.' -ForegroundColor Red
    }
    return
}

$log = 'C:\Users\malco\c-drive-cleanup.log'
"Cleanup time: $(Get-Date)" | Out-File $log -Encoding utf8

function Clean-Dir($path, $label) {
    if (Test-Path $path) {
        $size = (Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $mb = [math]::Round($size/1MB,1)
        Write-Host ("Deleting {0}: {1} ({2} MB)" -f $label, $path, $mb) -ForegroundColor Yellow
        try {
            Remove-Item $path -Recurse -Force -ErrorAction Stop
            Write-Host "  [DELETED]" -ForegroundColor Green
            "[DELETED] $label $path ($mb MB)" | Out-File $log -Append -Encoding utf8
        } catch {
            Write-Host ("  [FAILED] " + $_.Exception.Message) -ForegroundColor Red
            "[FAILED] $label $path - $($_.Exception.Message)" | Out-File $log -Append -Encoding utf8
        }
    } else {
        Write-Host "Skip (not exist): $path"
    }
}

Write-Host '=== C-drive cleanup start ===' -ForegroundColor Cyan

# 1. Old NVIDIA driver installers (C:\DrvPath) - current driver is 591.86, these are 473/555
Clean-Dir 'C:\DrvPath' 'Old NVIDIA driver installers'

# 2. User Temp leftovers (Clash updater installers, etc.) - safe to clear
$temp = 'C:\Users\malco\AppData\Local\Temp'
if (Test-Path $temp) {
    Write-Host "Cleaning user Temp: $temp" -ForegroundColor Yellow
    Get-ChildItem $temp -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            # skip files in use
        }
    }
    Write-Host "  [Temp cleaned]" -ForegroundColor Green
    "[CLEANED] user Temp" | Out-File $log -Append -Encoding utf8
}

# 3. Windows Update download cache
$wu = 'C:\Windows\SoftwareDistribution\Download'
if (Test-Path $wu) {
    $size = (Get-ChildItem $wu -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $mb = [math]::Round($size/1MB,1)
    Write-Host "Cleaning Windows Update cache: $wu ($mb MB)" -ForegroundColor Yellow
    try {
        Remove-Item $wu -Recurse -Force -ErrorAction Stop
        Write-Host "  [DELETED]" -ForegroundColor Green
        "[DELETED] Windows Update cache ($mb MB)" | Out-File $log -Append -Encoding utf8
    } catch {
        Write-Host ("  [FAILED] " + $_.Exception.Message) -ForegroundColor Red
        "[FAILED] Windows Update cache - $($_.Exception.Message)" | Out-File $log -Append -Encoding utf8
    }
}

Write-Host ''
Write-Host '=== Cleanup done ===' -ForegroundColor Green
Write-Host "Log: $log"
Write-Host 'Verify NVIDIA driver / apps still work normally.'
