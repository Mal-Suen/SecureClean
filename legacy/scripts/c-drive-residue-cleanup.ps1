# ============================================================
#  C-drive residue cleanup (auto-elevate version)
#  Deletes verified leftover dirs from the D-drive migration.
#  Run once; if not admin it auto-requests elevation via UAC.
#  Usage: powershell -ExecutionPolicy Bypass -File "C:\Users\malco\c-drive-residue-cleanup.ps1"
# ============================================================

# Check admin; if not, relaunch elevated
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Not admin. Requesting elevation...' -ForegroundColor Cyan
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { $self = 'C:\Users\malco\c-drive-residue-cleanup.ps1' }
    $arg = '-ExecutionPolicy Bypass -File "' + $self + '"'
    try {
        Start-Process powershell -Verb RunAs -ArgumentList $arg
        Write-Host 'Elevation requested. Click YES in the UAC prompt.' -ForegroundColor Green
    } catch {
        Write-Host 'Elevation failed (UAC declined). Run this script from an admin shell.' -ForegroundColor Red
    }
    return
}

# Verified leftover directories to delete
$targets = @(
    'C:\Program Files\Tencent\Weixin',                    # old WeChat 817MB; new on D:
    'C:\Program Files (x86)\VMware\VMware VIX',           # VIX SDK leftover 103MB
    'C:\Program Files\Quark',                             # empty
    'C:\Program Files\JianyingPro',                       # empty
    'C:\Program Files (x86)\Microsoft Visual Studio\18',  # empty
    'C:\Program Files (x86)\Tencent\QQLive',              # license pdf only
    'C:\Program Files (x86)\Tencent\UpdateSvr',           # Tencent Meeting updater
    'C:\Users\malco\AppData\Local\GitHubDesktop'          # empty
)

Write-Host '=== Cleanup start ===' -ForegroundColor Cyan
$log = 'C:\Users\malco\c-drive-residue-cleanup.log'
"Cleanup time: $(Get-Date)" | Out-File $log -Encoding utf8

foreach ($t in $targets) {
    if (Test-Path $t) {
        $size = (Get-ChildItem $t -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $mb = [math]::Round($size/1MB,1)
        Write-Host "Deleting: $t ($mb MB)" -ForegroundColor Yellow
        try {
            Remove-Item $t -Recurse -Force -ErrorAction Stop
            Write-Host "  [DELETED]" -ForegroundColor Green
            "[DELETED] $t ($mb MB)" | Out-File $log -Append -Encoding utf8
        } catch {
            Write-Host ("  [FAILED] " + $_.Exception.Message) -ForegroundColor Red
            "[FAILED] $t - $($_.Exception.Message)" | Out-File $log -Append -Encoding utf8
        }
    } else {
        Write-Host "Skip (not exist): $t"
    }
}

Write-Host ''
Write-Host '=== Cleanup done ===' -ForegroundColor Green
Write-Host "Log: $log"
Write-Host 'Verify WeChat / VMware still work normally.'
