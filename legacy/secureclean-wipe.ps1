# ============================================================
#  SecureClean - Secure wipe (overwrite + delete)
#  Securely deletes sensitive residue with overwrite to prevent recovery.
#  Auto-elevates. Only processes items marked safe-to-delete / secure-wipe.
#  Run:  powershell -ExecutionPolicy Bypass -File "secureclean-wipe.ps1"
#  Output: console + secureclean-wipe.log
# ============================================================

# Auto-elevate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Not admin. Requesting elevation...' -ForegroundColor Cyan
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { $self = 'E:\PrometheusProjects\PowerShellCleaner\secureclean-wipe.ps1' }
    $arg = '-ExecutionPolicy Bypass -File "' + $self + '"'
    try {
        Start-Process powershell -Verb RunAs -ArgumentList $arg
        Write-Host 'Elevation requested. Click YES in UAC.' -ForegroundColor Green
    } catch {
        Write-Host 'Elevation failed. Run from admin shell.' -ForegroundColor Red
    }
    return
}

$log = 'E:\PrometheusProjects\PowerShellCleaner\secureclean-wipe.log'
"Wipe time: $(Get-Date)" | Out-File $log -Encoding utf8

# Overwrite a file with random data before delete (prevents recovery)
function Secure-WipeFile($path) {
    try {
        $size = (Get-Item $path -Force).Length
        $fs = [System.IO.File]::Open($path, 'Open', 'Write')
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $buffer = New-Object byte[] 65536
        $remaining = $size
        while ($remaining -gt 0) {
            $chunk = [Math]::Min($remaining, $buffer.Length)
            $rng.GetBytes($buffer, 0, $chunk)
            $fs.Write($buffer, 0, $chunk)
            $remaining -= $chunk
        }
        $fs.Close()
        $rng.Dispose()
        return $true
    } catch {
        return $false
    }
}

# Securely delete a directory (overwrite files then remove)
function Secure-WipeDir($path) {
    if (-not (Test-Path $path)) { return 'skip' }
    Write-Host "Wiping: $path" -ForegroundColor Yellow
    $files = Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue
    $ok = 0; $fail = 0
    foreach ($f in $files) {
        if (Secure-WipeFile $f.FullName) { $ok++ } else { $fail++ }
    }
    try {
        Remove-Item $path -Recurse -Force -ErrorAction Stop
        Write-Host "  [WIPED] ($ok files overwritten, $fail failed)" -ForegroundColor Green
        "[WIPED] $path ($ok files)" | Out-File $log -Append -Encoding utf8
        return 'ok'
    } catch {
        Write-Host ("  [FAILED] " + $_.Exception.Message) -ForegroundColor Red
        "[FAILED] $path - $($_.Exception.Message)" | Out-File $log -Append -Encoding utf8
        return 'fail'
    }
}

Write-Host '=== SecureClean secure wipe start ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'WARNING: This securely deletes the following. Review carefully.' -ForegroundColor Red

# Items safe to securely wipe (temp, recent, recycle bin)
$wipeList = @(
    "$env:USERPROFILE\AppData\Local\Temp",
    "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Recent",
    "$env:SystemDrive\`$Recycle.Bin"
)

foreach ($item in $wipeList) {
    $result = Secure-WipeDir $item
    Write-Host "  Result: $result"
}

Write-Host ''
Write-Host '=== Wipe done ===' -ForegroundColor Green
Write-Host "Log: $log"
Write-Host ''
Write-Host 'NOTE: Browser passwords, chat history, credentials were NOT wiped.' -ForegroundColor Yellow
Write-Host 'These need manual review (use browser/WeChat built-in clear functions).'
