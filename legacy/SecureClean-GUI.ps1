# ============================================================
#  SecureClean GUI - Apple 设计语言 + 中文 + 后台线程扫描
#  使用 TableLayoutPanel 自动布局, Thread + Invoke 避免卡死
#  运行:  powershell -ExecutionPolicy Bypass -File "SecureClean-GUI.ps1"
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- Apple 设计令牌 ----------
$cPrimary   = [System.Drawing.Color]::FromArgb(0, 102, 204)      # Action Blue #0066cc
$cInk       = [System.Drawing.Color]::FromArgb(29, 29, 31)       # ink #1d1d1f
$cMuted     = [System.Drawing.Color]::FromArgb(122, 122, 122)    # ink-muted-48
$cCanvas    = [System.Drawing.Color]::White
$cParchment = [System.Drawing.Color]::FromArgb(245, 245, 247)    # #f5f5f7
$cPearl     = [System.Drawing.Color]::FromArgb(250, 250, 252)    # #fafafc
$cDivider   = [System.Drawing.Color]::FromArgb(240, 240, 240)    # #f0f0f0
$cOnPrimary = [System.Drawing.Color]::White
$cRed       = [System.Drawing.Color]::FromArgb(231, 76, 60)
$cAmber     = [System.Drawing.Color]::FromArgb(241, 196, 15)
$cGreen     = [System.Drawing.Color]::FromArgb(46, 204, 113)

# ---------- 圆角按钮 (PS5.1 兼容 C#) ----------
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
public class PillButton : Button {
    private int _radius = 9999;
    public int Radius { get { return _radius; } set { _radius = value; } }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var path = new GraphicsPath()) {
            int r = _radius;
            path.AddArc(0, 0, r*2, r*2, 180, 90);
            path.AddArc(Width-r*2-1, 0, r*2, r*2, 270, 90);
            path.AddArc(Width-r*2-1, Height-r*2-1, r*2, r*2, 0, 90);
            path.AddArc(0, Height-r*2-1, r*2, r*2, 90, 90);
            path.CloseFigure();
            using (var brush = new SolidBrush(BackColor)) {
                e.Graphics.FillPath(brush, path);
            }
        }
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, ForeColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }
}
"@ -ReferencedAssemblies @('System.Windows.Forms','System.Drawing')

# ========== 构建窗体 ==========
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SecureClean - 敏感数据清理'
$form.Size = New-Object System.Drawing.Size(960, 640)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cParchment
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.MinimumSize = New-Object System.Drawing.Size(900, 580)

# 主布局: 垂直堆叠
$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = 'Fill'
$mainLayout.Padding = New-Object System.Windows.Forms.Padding(24)
$mainLayout.ColumnCount = 1
$mainLayout.RowCount = 5
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 70)))
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 90)))
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 60)))
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 30)))

# ---- 行0: 标题 ----
$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Dock = 'Fill'
$titlePanel.BackColor = $cParchment

$title = New-Object System.Windows.Forms.Label
$title.Text = 'SecureClean'
$title.Location = New-Object System.Drawing.Point(0, 4)
$title.AutoSize = $true
$title.Font = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $cInk

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = '检测并清理电脑上的敏感数据残留'
$subtitle.Location = New-Object System.Drawing.Point(0, 44)
$subtitle.AutoSize = $true
$subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$subtitle.ForeColor = $cMuted

$titlePanel.Controls.Add($title)
$titlePanel.Controls.Add($subtitle)

# ---- 行1: 统计卡片 (水平排列) ----
$statsPanel = New-Object System.Windows.Forms.TableLayoutPanel
$statsPanel.Dock = 'Fill'
$statsPanel.ColumnCount = 3
$statsPanel.RowCount = 1
$statsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 33)))
$statsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 33)))
$statsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 33)))

function New-StatCard($label, $color) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Dock = 'Fill'
    $card.Margin = New-Object System.Windows.Forms.Padding(6)
    $card.BackColor = $cCanvas
    $card.BorderStyle = 'FixedSingle'
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $label
    $lbl.Dock = 'Top'
    $lbl.Height = 22
    $lbl.ForeColor = $cMuted
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lbl.TextAlign = 'MiddleCenter'
    $val = New-Object System.Windows.Forms.Label
    $val.Text = '0'
    $val.Dock = 'Fill'
    $val.ForeColor = $color
    $val.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
    $val.TextAlign = 'MiddleCenter'
    $card.Controls.Add($val)
    $card.Controls.Add($lbl)
    return $card
}

$statHigh = New-StatCard '高风险项' $cRed
$statTotal = New-StatCard '总项目' $cPrimary
$statSize = New-StatCard '总大小' $cGreen

$statsPanel.Controls.Add($statHigh, 0, 0)
$statsPanel.Controls.Add($statTotal, 1, 0)
$statsPanel.Controls.Add($statSize, 2, 0)

# ---- 行2: 按钮 + 进度 ----
$actionPanel = New-Object System.Windows.Forms.TableLayoutPanel
$actionPanel.Dock = 'Fill'
$actionPanel.ColumnCount = 3
$actionPanel.RowCount = 1
$actionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 150)))
$actionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 150)))
$actionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))

$scanBtn = New-Object PillButton
$scanBtn.Text = '开始扫描'
$scanBtn.Dock = 'Fill'
$scanBtn.Margin = New-Object System.Windows.Forms.Padding(0, 10, 10, 10)
$scanBtn.BackColor = $cPrimary
$scanBtn.ForeColor = $cOnPrimary
$scanBtn.FlatStyle = 'Flat'
$scanBtn.FlatAppearance.BorderSize = 0
$scanBtn.Cursor = 'Hand'
$scanBtn.Font = New-Object System.Drawing.Font('Segoe UI', 11)

$wipeBtn = New-Object PillButton
$wipeBtn.Text = '安全清除'
$wipeBtn.Dock = 'Fill'
$wipeBtn.Margin = New-Object System.Windows.Forms.Padding(0, 10, 10, 10)
$wipeBtn.BackColor = $cRed
$wipeBtn.ForeColor = $cOnPrimary
$wipeBtn.FlatStyle = 'Flat'
$wipeBtn.FlatAppearance.BorderSize = 0
$wipeBtn.Cursor = 'Hand'
$wipeBtn.Enabled = $false
$wipeBtn.Font = New-Object System.Drawing.Font('Segoe UI', 11)

$rightPanel = New-Object System.Windows.Forms.TableLayoutPanel
$rightPanel.Dock = 'Fill'
$rightPanel.ColumnCount = 1
$rightPanel.RowCount = 2

$status = New-Object System.Windows.Forms.Label
$status.Text = '就绪'
$status.Dock = 'Fill'
$status.ForeColor = $cMuted
$status.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$status.TextAlign = 'MiddleLeft'

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Dock = 'Fill'
$progress.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 8)
$progress.Minimum = 0
$progress.Maximum = 100

$rightPanel.Controls.Add($progress, 0, 1)
$rightPanel.Controls.Add($status, 0, 0)

$actionPanel.Controls.Add($scanBtn, 0, 0)
$actionPanel.Controls.Add($wipeBtn, 1, 0)
$actionPanel.Controls.Add($rightPanel, 2, 0)

# ---- 行3: 表格 ----
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.BackgroundColor = $cCanvas
$grid.BorderStyle = 'FixedSingle'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToResizeRows = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.RowHeadersVisible = $false
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersBorderStyle = 'None'
$grid.ColumnHeadersDefaultCellStyle.BackColor = $cParchment
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $cInk
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grid.ColumnHeadersHeight = 32
$grid.DefaultCellStyle.BackColor = $cCanvas
$grid.DefaultCellStyle.ForeColor = $cInk
$grid.DefaultCellStyle.SelectionBackColor = $cPrimary
$grid.DefaultCellStyle.SelectionForeColor = $cOnPrimary
$grid.AlternatingRowsDefaultCellStyle.BackColor = $cPearl
$grid.RowTemplate.Height = 30
$grid.AutoSizeColumnsMode = 'Fill'
$grid.CellBorderStyle = 'SingleHorizontal'
$grid.GridColor = $cDivider

# ---- 行4: 底部提示 ----
$footer = New-Object System.Windows.Forms.Label
$footer.Text = '提示: 安全清除会覆盖写入后删除。聊天记录和浏览器密码需用软件自带功能处理。'
$footer.Dock = 'Fill'
$footer.ForeColor = $cMuted
$footer.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$footer.TextAlign = 'MiddleLeft'

# 组装
$mainLayout.Controls.Add($titlePanel, 0, 0)
$mainLayout.Controls.Add($statsPanel, 0, 1)
$mainLayout.Controls.Add($actionPanel, 0, 2)
$mainLayout.Controls.Add($grid, 0, 3)
$mainLayout.Controls.Add($footer, 0, 4)
$form.Controls.Add($mainLayout)

# ========== 扫描逻辑 (返回结果) ==========
function Get-ScanResults {
    $results = @()
    $userHome = $env:USERPROFILE
    $sysDrive = $env:SystemDrive
    function Get-DirSizeMB($p) {
        if (-not (Test-Path $p)) { return 0 }
        try {
            $s = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            return [math]::Round($s/1MB,1)
        } catch { return 0 }
    }
    $browsers = @(
        @{Name='Chrome'; Path="$userHome\AppData\Local\Google\Chrome\User Data"},
        @{Name='Edge'; Path="$userHome\AppData\Local\Microsoft\Edge\User Data"},
        @{Name='Firefox'; Path="$userHome\AppData\Roaming\Mozilla\Firefox\Profiles"}
    )
    foreach ($b in $browsers) {
        if (Test-Path $b.Path) {
            $login = Get-DirSizeMB "$($b.Path)\Default\Login Data"
            $cookies = Get-DirSizeMB "$($b.Path)\Default\Cookies"
            $history = Get-DirSizeMB "$($b.Path)\Default\History"
            $total = [math]::Round($login+$cookies+$history,1)
            if ($total -gt 0) {
                $results += [PSCustomObject]@{Category='浏览器'; Path=$b.Path; SizeMB=$total; Risk='高'; Action='清除'; Note="$($b.Name) 密码/记录"}
            }
        }
    }
    $chat = @(
        @{Name='微信'; Path="$userHome\Documents\WeChat Files"},
        @{Name='微信新版'; Path="$userHome\Documents\xwechat_files"},
        @{Name='QQ'; Path="$userHome\Documents\Tencent Files"},
        @{Name='企业微信'; Path="$userHome\Documents\WXWork"}
    )
    foreach ($c in $chat) {
        $size = Get-DirSizeMB $c.Path
        if ($size -gt 0) {
            $results += [PSCustomObject]@{Category='聊天记录'; Path=$c.Path; SizeMB=$size; Risk='高'; Action='保留'; Note="$($c.Name) 数据"}
        }
    }
    $temp = Get-DirSizeMB "$userHome\AppData\Local\Temp"
    if ($temp -gt 0) {
        $results += [PSCustomObject]@{Category='临时文件'; Path="$userHome\AppData\Local\Temp"; SizeMB=$temp; Risk='中'; Action='清除'; Note='用户临时文件'}
    }
    $recycle = Get-DirSizeMB "$sysDrive\`$Recycle.Bin"
    if ($recycle -gt 0) {
        $results += [PSCustomObject]@{Category='回收站'; Path="$sysDrive\`$Recycle.Bin"; SizeMB=$recycle; Risk='高'; Action='清空'; Note='已删除文件'}
    }
    $log = Get-DirSizeMB "$sysDrive\Windows\Logs"
    if ($log -gt 0) {
        $results += [PSCustomObject]@{Category='系统日志'; Path="$sysDrive\Windows\Logs"; SizeMB=$log; Risk='中'; Action='保留'; Note='系统日志'}
    }
    return $results
}

# ========== 扫描事件 (后台线程, Invoke 更新 UI) ==========
$scanBtn.Add_Click({
    $scanBtn.Enabled = $false
    $wipeBtn.Enabled = $false
    $status.Text = '正在扫描...'
    $progress.Value = 10
    $grid.Rows.Clear()
    $form.Refresh()

    # 后台线程执行扫描
    $thread = New-Object System.Threading.Thread([System.Threading.ThreadStart]{
        $results = Get-ScanResults
        # 回到 UI 线程更新
        $form.Invoke([System.Action]{
            $grid.Columns.Clear()
            $grid.Columns.Add('Category', '类别') | Out-Null
            $grid.Columns.Add('Path', '路径') | Out-Null
            $grid.Columns.Add('SizeMB', '大小(MB)') | Out-Null
            $grid.Columns.Add('Risk', '风险') | Out-Null
            $grid.Columns.Add('Action', '建议') | Out-Null
            $grid.Columns.Add('Note', '说明') | Out-Null
            foreach ($r in $results) {
                $grid.Rows.Add($r.Category, $r.Path, $r.SizeMB, $r.Risk, $r.Action, $r.Note) | Out-Null
            }
            $high = @($results | Where-Object {$_.Risk -eq '高'}).Count
            $totalSize = [math]::Round((($results | Measure-Object SizeMB -Sum).Sum),1)
            $statHigh.Controls[1].Text = "$high"
            $statTotal.Controls[1].Text = "$($results.Count)"
            $statSize.Controls[1].Text = "$totalSize MB"
            foreach ($row in $grid.Rows) {
                if ($row.Cells[3].Value -eq '高') { $row.Cells[3].Style.ForeColor = $cRed }
                elseif ($row.Cells[3].Value -eq '中') { $row.Cells[3].Style.ForeColor = $cAmber }
            }
            $status.Text = "扫描完成, 检测到 $($results.Count) 处残留"
            $progress.Value = 100
            $wipeBtn.Enabled = $true
            $scanBtn.Enabled = $true
        })
    })
    $thread.IsBackground = $true
    $thread.Start()
})

# ========== 清除事件 ==========
$wipeBtn.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('请先选择要清除的项目', '提示', 'OK', 'Information')
        return
    }
    $row = $grid.SelectedRows[0]
    $path = $row.Cells[1].Value
    $action = $row.Cells[4].Value
    if ($action -ne '清除' -and $action -ne '清空') {
        [System.Windows.Forms.MessageBox]::Show('该项目建议保留, 请勿清除', '提示', 'OK', 'Information')
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show("确认安全清除: $path ?", '确认', 'YesNo', 'Warning')
    if ($confirm -eq 'Yes') {
        $status.Text = "正在安全清除: $path ..."
        $form.Refresh()
        try {
            Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $fs = [System.IO.File]::Open($_.FullName, 'Open', 'Write')
                    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
                    $buf = New-Object byte[] 65536
                    $rem = $_.Length
                    while ($rem -gt 0) {
                        $chunk = [Math]::Min($rem, $buf.Length)
                        $rng.GetBytes($buf, 0, $chunk)
                        $fs.Write($buf, 0, $chunk)
                        $rem -= $chunk
                    }
                    $fs.Close(); $rng.Dispose()
                } catch {}
            }
            Remove-Item $path -Recurse -Force -ErrorAction Stop
            $status.Text = "已安全清除: $path"
            $grid.Rows.Remove($row)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("清除失败: $($_.Exception.Message)", '错误', 'OK', 'Error')
            $status.Text = '清除失败'
        }
    }
})

$form.ShowDialog() | Out-Null
