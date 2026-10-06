# ============================================================
#  SecureClean - Sensitive residue scanner v3 (universal/adaptive)
#  Adapts to different machines: system drive, user dir, and
#  auto-detects app install locations (registry + common paths).
#  Scan only - does NOT delete anything.
#  Run:  powershell -ExecutionPolicy Bypass -File "secureclean-scan.ps1"
#  Output: console report + secureclean-report.html
# ============================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$report = @()
$userHome = $env:USERPROFILE
$sysDrive = $env:SystemDrive          # adaptive system drive (C:, D:, etc.)
$userName = $env:USERNAME

# Load optional config file (secureclean-config.ps1) for custom paths
$configPath = Join-Path $PSScriptRoot 'secureclean-config.ps1'
$ConfigChatPaths = @()
$ConfigBrowserPaths = @()
$ConfigExtraPaths = @()
if (Test-Path $configPath) {
    try {
        . $configPath
        Write-Host "Loaded config: $configPath" -ForegroundColor Cyan
    } catch {
        Write-Host "Config load failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ---------- Adaptive path helpers ----------
function Add-Item($category, $path, $sizeMB, $risk, $action, $note) {
    $script:report += [PSCustomObject]@{
        Category = $category
        Path     = $path
        SizeMB   = $sizeMB
        Risk     = $risk
        Action   = $action
        Note     = $note
    }
}

function Get-DirSizeMB($path) {
    if (-not (Test-Path $path)) { return 0 }
    try {
        $s = (Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        return [math]::Round($s/1MB,1)
    } catch { return 0 }
}

# Detect app install location from registry Uninstall entries
function Find-InstallPath($displayNameMatch) {
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($r in $roots) {
        $items = Get-ItemProperty $r -ErrorAction SilentlyContinue
        foreach ($i in $items) {
            if ($i.DisplayName -match $displayNameMatch -and $i.InstallLocation) {
                return $i.InstallLocation.Trim('"')
            }
        }
    }
    return $null
}

Write-Host '=== SecureClean residue scan v3 (adaptive) ===' -ForegroundColor Cyan
Write-Host ("System drive: $sysDrive   User: $userName") -ForegroundColor Gray
Write-Host ''

# ========== 1. Browser residue (detect installed browsers) ==========
Write-Host '[1/8] Browser residue...' -ForegroundColor Yellow
$browserPaths = @(
    @{Name='Chrome';  Path="$userHome\AppData\Local\Google\Chrome\User Data"},
    @{Name='Edge';    Path="$userHome\AppData\Local\Microsoft\Edge\User Data"},
    @{Name='Firefox'; Path="$userHome\AppData\Roaming\Mozilla\Firefox\Profiles"},
    @{Name='Brave';   Path="$userHome\AppData\Local\BraveSoftware\Brave-Browser\User Data"},
    @{Name='Opera';   Path="$userHome\AppData\Roaming\Opera Software\Opera Stable"}
)
foreach ($b in $browserPaths) {
    if (Test-Path $b.Path) {
        # Check for sensitive sub-data (Login Data, Cookies, History)
        $login = Get-DirSizeMB "$($b.Path)\Default\Login Data"
        $cookies = Get-DirSizeMB "$($b.Path)\Default\Cookies"
        $history = Get-DirSizeMB "$($b.Path)\Default\History"
        $total = [math]::Round($login+$cookies+$history,1)
        if ($total -gt 0) {
            Add-Item 'Browser' $b.Path $total 'High' 'Secure wipe' "$($b.Name) saved passwords/cookies/history"
        }
    }
}

# Scan config-specified browser paths
foreach ($bp in $ConfigBrowserPaths) {
    if (Test-Path $bp) {
        $login = Get-DirSizeMB "$bp\Default\Login Data"
        $cookies = Get-DirSizeMB "$bp\Default\Cookies"
        $history = Get-DirSizeMB "$bp\Default\History"
        $total = [math]::Round($login+$cookies+$history,1)
        if ($total -gt 0) {
            Add-Item 'Browser' $bp $total 'High' 'Secure wipe' "custom browser saved passwords/cookies/history"
        }
    }
}

# ========== 2. Chat history cache (detect via registry + common paths) ==========
Write-Host '[2/8] Chat history cache...' -ForegroundColor Yellow
# WeChat - detect install location, then find data dir
$wechatInstall = Find-InstallPath 'Weixin|WeChat'
$chatCandidates = @(
    "$userHome\Documents\WeChat Files",
    "$userHome\Documents\xwechat_files",
    "$userHome\Documents\Tencent Files",
    "$userHome\Documents\WXWork"
)
# Also scan other drives for common chat data dirs
foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Free -gt 0}).Name) {
    $chatCandidates += "${drive}:\WeChat Files"
    $chatCandidates += "${drive}:\xwechat_files"
    $chatCandidates += "${drive}:\Tencent Files"
}
# Merge config-specified chat paths
$chatCandidates += $ConfigChatPaths
foreach ($c in $chatCandidates) {
    $size = Get-DirSizeMB $c
    if ($size -gt 0) {
        $name = if ($c -match 'WeChat|xwechat') { 'WeChat' } elseif ($c -match 'Tencent') { 'QQ' } else { 'Chat' }
        Add-Item 'Chat' $c $size 'High' 'Review/keep' "$name data (chat/files)"
    }
}

# ========== 3. Login credentials ==========
Write-Host '[3/8] Login credentials...' -ForegroundColor Yellow
$credCount = (cmdkey /list 2>$null | Measure-Object -Line).Lines
if ($credCount -gt 1) {
    Add-Item 'Credentials' 'Windows Credential Manager' 0 'High' 'Review' "detected $credCount credential entries"
}

# ========== 4. SSH keys & git config ==========
Write-Host '[4/8] SSH keys & git config...' -ForegroundColor Yellow
$sshKey = "$userHome\.ssh"
if (Test-Path $sshKey) {
    $keys = Get-ChildItem $sshKey -File -EA SilentlyContinue | Where-Object {$_.Name -match 'id_rsa|id_ed25519|id_ecdsa'}
    if ($keys) { Add-Item 'SSH' $sshKey 0 'High' 'Secure wipe' 'SSH private keys found' }
}
$gitCred = "$userHome\.git-credentials"
if (Test-Path $gitCred) { Add-Item 'GitCred' $gitCred 0 'High' 'Secure wipe' 'git credentials (may contain tokens)' }

# ========== 5. Temp files (adaptive) ==========
Write-Host '[5/8] Temp files...' -ForegroundColor Yellow
$tempSize = Get-DirSizeMB "$userHome\AppData\Local\Temp"
if ($tempSize -gt 0) { Add-Item 'Temp' "$userHome\AppData\Local\Temp" $tempSize 'Medium' 'Safe delete' 'user temp files' }
$winTemp = Get-DirSizeMB "$sysDrive\Windows\Temp"
if ($winTemp -gt 0) { Add-Item 'Temp' "$sysDrive\Windows\Temp" $winTemp 'Medium' 'Safe delete' 'system temp files' }

# ========== 6. Recycle Bin (adaptive) ==========
Write-Host '[6/8] Recycle bin...' -ForegroundColor Yellow
$recycle = Get-DirSizeMB "$sysDrive\`$Recycle.Bin"
if ($recycle -gt 0) { Add-Item 'RecycleBin' "$sysDrive\`$Recycle.Bin" $recycle 'High' 'Empty' 'deleted but recoverable files' }

# ========== 7. Downloads / Desktop / Recent ==========
Write-Host '[7/8] Downloads/Desktop/Recent...' -ForegroundColor Yellow
$dl = Get-DirSizeMB "$userHome\Downloads"
if ($dl -gt 0) { Add-Item 'Downloads' "$userHome\Downloads" $dl 'Medium' 'Review' 'downloads folder' }
$desk = Get-DirSizeMB "$userHome\Desktop"
if ($desk -gt 0) { Add-Item 'Desktop' "$userHome\Desktop" $desk 'Low' 'Review' 'desktop files' }
$recent = Get-DirSizeMB "$userHome\AppData\Roaming\Microsoft\Windows\Recent"
if ($recent -gt 0) { Add-Item 'Recent' "$userHome\AppData\Roaming\Microsoft\Windows\Recent" $recent 'Medium' 'Safe delete' 'recent files list' }

# ========== 8. System logs (adaptive) ==========
Write-Host '[8/8] System logs...' -ForegroundColor Yellow
$logSize = Get-DirSizeMB "$sysDrive\Windows\Logs"
if ($logSize -gt 0) { Add-Item 'SystemLog' "$sysDrive\Windows\Logs" $logSize 'Medium' 'Review' 'system logs' }

# ========== Config extra paths ==========
foreach ($ep in $ConfigExtraPaths) {
    $size = Get-DirSizeMB $ep
    if ($size -gt 0) { Add-Item 'Custom' $ep $size 'High' 'Review' 'user-specified sensitive path' }
}

# ========== Output ==========
Write-Host ''
Write-Host '=== Scan complete ===' -ForegroundColor Green
if ($report.Count -eq 0) {
    Write-Host 'No obvious sensitive residue detected.' -ForegroundColor Green
} else {
    Write-Host ("Detected {0} residue items:" -f $report.Count)
    $report | Sort-Object Risk | Format-Table Category, Path, SizeMB, Risk, Action, Note -AutoSize
}

# Generate HTML report
$rows = ''
if ($report.Count -gt 0) {
    $rows = ($report | ForEach-Object {
        $riskClass = if ($_.Risk -eq 'High') { 'risk-high' } elseif ($_.Risk -eq 'Medium') { 'risk-mid' } else { '' }
        "<tr><td>$($_.Category)</td><td>$($_.Path)</td><td>$($_.SizeMB)</td><td class='$riskClass'>$($_.Risk)</td><td>$($_.Action)</td><td>$($_.Note)</td></tr>"
    }) -join "`n"
} else {
    $rows = "<tr><td colspan='6'>No obvious residue detected</td></tr>"
}

$html = @"
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>SecureClean Residue Report</title>
<style>
body{font-family:'Microsoft YaHei',sans-serif;margin:30px;background:#f5f5f5}
h1{color:#333}.card{background:#fff;border-radius:8px;padding:15px;margin:10px 0;box-shadow:0 2px 4px rgba(0,0,0,.1)}
table{width:100%;border-collapse:collapse}th,td{padding:8px;text-align:left;border-bottom:1px solid #eee}
th{background:#f0f0f0}.risk-high{color:#d9534f;font-weight:bold}.risk-mid{color:#f0ad0e}
</style></head>
<body>
<h1>SecureClean Sensitive Residue Report</h1>
<p>Scan time: $(Get-Date) | System: $sysDrive | User: $userName</p>
<div class="card"><h3>Detected $($report.Count) residue items</h3></div>
<div class="card"><table><tr><th>Category</th><th>Path</th><th>Size(MB)</th><th>Risk</th><th>Action</th><th>Note</th></tr>
$rows
</table></div>
<p style="color:#999">Generated by SecureClean v3 (adaptive). Scan only, nothing deleted.</p>
</body></html>
"@

$htmlPath = 'E:\PrometheusProjects\PowerShellCleaner\secureclean-report.html'
$html | Set-Content -Path $htmlPath -Encoding UTF8
Write-Host "HTML report: $htmlPath"
