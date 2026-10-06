using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace SecureClean
{
    // 扫描结果项(供 DataGrid 绑定)
    public class ScanItem
    {
        public bool Selected { get; set; }
        public string Category { get; set; }
        public string Path { get; set; }
        public double SizeMB { get; set; }
        public string Risk { get; set; }
        public Brush RiskBrush { get; set; }
        public bool CanDelete { get; set; }
        public string Note { get; set; }
    }

    public class MainWindow : Window
    {
        // Apple 设计令牌
        static readonly Color cPrimary = Color.FromRgb(0, 102, 204);      // Action Blue #0066cc
        static readonly Color cPrimaryHover = Color.FromRgb(0, 122, 235);
        static readonly Color cInk = Color.FromRgb(29, 29, 31);           // ink #1d1d1f
        static readonly Color cMuted = Color.FromRgb(122, 122, 122);      // muted
        static readonly Color cParchment = Color.FromRgb(245, 245, 247);  // #f5f5f7
        static readonly Color cHairline = Color.FromRgb(230, 230, 235);
        static readonly Color cRed = Color.FromRgb(231, 76, 60);
        static readonly Color cRedHover = Color.FromRgb(240, 90, 75);
        static readonly Color cAmber = Color.FromRgb(200, 160, 20);
        static readonly Color cGreen = Color.FromRgb(40, 180, 100);
        static readonly Color cSelBg = Color.FromRgb(232, 240, 254);

        private DataGrid grid;
        private TextBlock status;
        private ProgressBar progress;
        private TextBlock statHighVal, statTotalVal, statSizeVal;
        private Button scanBtn, wipeBtn;
        private List<ScanItem> items = new List<ScanItem>();

        public MainWindow()
        {
            BuildUI();
        }

        void BuildUI()
        {
            this.Title = "SecureClean";
            this.Width = 960;
            this.Height = 640;
            this.MinWidth = 880;
            this.MinHeight = 580;
            this.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            this.Background = new SolidColorBrush(cParchment);
            this.FontFamily = new FontFamily("Segoe UI");

            // 根布局: 5 行自动布局
            Grid root = new Grid();
            root.Margin = new Thickness(32, 24, 32, 20);
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(80) });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(100) });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(64) });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(26) });

            // ---- 行0: 标题 ----
            StackPanel titlePanel = new StackPanel();
            TextBlock title = new TextBlock();
            title.Text = "SecureClean";
            title.FontSize = 28;
            title.FontWeight = FontWeights.Bold;
            title.Foreground = new SolidColorBrush(cInk);
            TextBlock subtitle = new TextBlock();
            subtitle.Text = "检测并清理电脑上的敏感数据残留";
            subtitle.FontSize = 13;
            subtitle.Foreground = new SolidColorBrush(cMuted);
            subtitle.Margin = new Thickness(1, 4, 0, 0);
            titlePanel.Children.Add(title);
            titlePanel.Children.Add(subtitle);
            Grid.SetRow(titlePanel, 0);
            root.Children.Add(titlePanel);

            // ---- 行1: 统计卡片 ----
            StackPanel statsPanel = new StackPanel();
            statsPanel.Orientation = Orientation.Horizontal;
            statHighVal = MakeStatCard(statsPanel, "高风险项", "0", cRed);
            statTotalVal = MakeStatCard(statsPanel, "总项目", "0", cPrimary);
            statSizeVal = MakeStatCard(statsPanel, "总大小", "0 MB", cGreen);
            Grid.SetRow(statsPanel, 1);
            root.Children.Add(statsPanel);

            // ---- 行2: 按钮 + 状态 + 进度 ----
            StackPanel actionPanel = new StackPanel();
            actionPanel.Orientation = Orientation.Horizontal;
            actionPanel.VerticalAlignment = VerticalAlignment.Center;

            scanBtn = MakePillButton("开始扫描", cPrimary, cPrimaryHover);
            scanBtn.Click += ScanBtn_Click;
            actionPanel.Children.Add(scanBtn);

            wipeBtn = MakePillButton("安全清除", cRed, cRedHover);
            wipeBtn.Margin = new Thickness(12, 0, 0, 0);
            wipeBtn.IsEnabled = false;
            wipeBtn.Click += WipeBtn_Click;
            actionPanel.Children.Add(wipeBtn);

            StackPanel statusPanel = new StackPanel();
            statusPanel.Margin = new Thickness(20, 0, 0, 0);
            statusPanel.VerticalAlignment = VerticalAlignment.Center;
            statusPanel.Width = double.NaN;
            statusPanel.MinWidth = 400;
            status = new TextBlock();
            status.Text = "就绪";
            status.FontSize = 12;
            status.Foreground = new SolidColorBrush(cMuted);
            progress = new ProgressBar();
            progress.Height = 5;
            progress.MinWidth = 380;
            progress.Margin = new Thickness(0, 8, 0, 0);
            progress.Minimum = 0;
            progress.Maximum = 100;
            progress.Foreground = new SolidColorBrush(cPrimary);
            progress.Background = new SolidColorBrush(cHairline);
            progress.BorderThickness = new Thickness(0);
            statusPanel.Children.Add(status);
            statusPanel.Children.Add(progress);
            actionPanel.Children.Add(statusPanel);

            Grid.SetRow(actionPanel, 2);
            root.Children.Add(actionPanel);

            // ---- 行3: 数据表格 ----
            grid = BuildGrid();
            Grid.SetRow(grid, 3);
            root.Children.Add(grid);

            // ---- 行4: 底部提示 ----
            TextBlock footer = new TextBlock();
            footer.Text = "勾选要清除的项目后点\"安全清除\"。聊天记录和浏览器密码建议用软件自带功能处理。";
            footer.FontSize = 11;
            footer.Foreground = new SolidColorBrush(cMuted);
            footer.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetRow(footer, 4);
            root.Children.Add(footer);

            this.Content = root;
        }

        // 圆角阴影统计卡片
        TextBlock MakeStatCard(StackPanel parent, string label, string value, Color color)
        {
            Border card = new Border();
            card.Width = 200;
            card.Height = 84;
            card.Margin = new Thickness(0, 0, 16, 0);
            card.Background = Brushes.White;
            card.CornerRadius = new CornerRadius(14);
            card.Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 24,
                ShadowDepth = 2,
                Opacity = 0.10,
                Direction = 270
            };

            StackPanel sp = new StackPanel();
            sp.VerticalAlignment = VerticalAlignment.Center;
            TextBlock lbl = new TextBlock();
            lbl.Text = label;
            lbl.FontSize = 12;
            lbl.Foreground = new SolidColorBrush(cMuted);
            lbl.HorizontalAlignment = HorizontalAlignment.Center;
            TextBlock val = new TextBlock();
            val.Text = value;
            val.FontSize = 24;
            val.FontWeight = FontWeights.Bold;
            val.Foreground = new SolidColorBrush(color);
            val.HorizontalAlignment = HorizontalAlignment.Center;
            val.Margin = new Thickness(0, 4, 0, 0);
            sp.Children.Add(lbl);
            sp.Children.Add(val);
            card.Child = sp;
            parent.Children.Add(card);
            return val;
        }

        // 胶囊按钮(圆角模板 + hover/disabled 触发器)
        Button MakePillButton(string text, Color bg, Color hoverBg)
        {
            Button btn = new Button();
            btn.Content = text;
            btn.Width = 132;
            btn.Height = 42;
            btn.FontSize = 14;
            btn.FontWeight = FontWeights.SemiBold;
            btn.Foreground = Brushes.White;
            btn.Background = new SolidColorBrush(bg);
            btn.Cursor = Cursors.Hand;
            btn.BorderThickness = new Thickness(0);

            // 胶囊模板
            ControlTemplate template = new ControlTemplate(typeof(Button));
            FrameworkElementFactory border = new FrameworkElementFactory(typeof(Border));
            border.SetValue(Border.CornerRadiusProperty, new CornerRadius(21));
            border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Button.BackgroundProperty));
            FrameworkElementFactory presenter = new FrameworkElementFactory(typeof(ContentPresenter));
            presenter.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            presenter.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
            border.AppendChild(presenter);
            template.VisualTree = border;
            btn.Template = template;

            // hover / disabled 触发器
            Style style = new Style(typeof(Button));
            Trigger hover = new Trigger();
            hover.Property = UIElement.IsMouseOverProperty;
            hover.Value = true;
            hover.Setters.Add(new Setter(Button.BackgroundProperty, new SolidColorBrush(hoverBg)));
            style.Triggers.Add(hover);
            Trigger disabled = new Trigger();
            disabled.Property = Button.IsEnabledProperty;
            disabled.Value = false;
            disabled.Setters.Add(new Setter(Button.BackgroundProperty, new SolidColorBrush(Color.FromRgb(200, 200, 205))));
            style.Triggers.Add(disabled);
            btn.Style = style;
            return btn;
        }

        // 数据表格
        DataGrid BuildGrid()
        {
            DataGrid g = new DataGrid();
            g.AutoGenerateColumns = false;
            g.CanUserAddRows = false;
            g.CanUserResizeRows = false;
            g.CanUserReorderColumns = false;
            g.SelectionMode = DataGridSelectionMode.Single;
            g.SelectionUnit = DataGridSelectionUnit.FullRow;
            g.Background = Brushes.White;
            g.BorderBrush = new SolidColorBrush(cHairline);
            g.BorderThickness = new Thickness(1);
            g.RowBackground = Brushes.White;
            g.AlternatingRowBackground = new SolidColorBrush(Color.FromRgb(250, 250, 252));
            g.RowHeight = 38;
            g.FontSize = 13;
            g.GridLinesVisibility = DataGridGridLinesVisibility.Horizontal;
            g.HorizontalGridLinesBrush = new SolidColorBrush(Color.FromRgb(240, 240, 240));
            g.HeadersVisibility = DataGridHeadersVisibility.Column;

            // 列头样式
            Style headerStyle = new Style(typeof(DataGridColumnHeader));
            headerStyle.Setters.Add(new Setter(DataGridColumnHeader.BackgroundProperty, Brushes.White));
            headerStyle.Setters.Add(new Setter(DataGridColumnHeader.ForegroundProperty, new SolidColorBrush(cMuted)));
            headerStyle.Setters.Add(new Setter(DataGridColumnHeader.FontWeightProperty, FontWeights.Bold));
            headerStyle.Setters.Add(new Setter(DataGridColumnHeader.FontSizeProperty, 12.0));
            headerStyle.Setters.Add(new Setter(DataGridColumnHeader.HeightProperty, 42.0));
            headerStyle.Setters.Add(new Setter(DataGridColumnHeader.BorderThicknessProperty, new Thickness(0, 0, 0, 1)));
            headerStyle.Setters.Add(new Setter(DataGridColumnHeader.BorderBrushProperty, new SolidColorBrush(Color.FromRgb(240, 240, 240))));
            g.ColumnHeaderStyle = headerStyle;

            // 单元格样式(去边框, 选中浅蓝)
            Style cellStyle = new Style(typeof(DataGridCell));
            cellStyle.Setters.Add(new Setter(DataGridCell.BorderThicknessProperty, new Thickness(0)));
            cellStyle.Setters.Add(new Setter(DataGridCell.PaddingProperty, new Thickness(10, 0, 10, 0)));
            cellStyle.Setters.Add(new Setter(DataGridCell.VerticalContentAlignmentProperty, VerticalAlignment.Center));
            Trigger sel = new Trigger();
            sel.Property = DataGridCell.IsSelectedProperty;
            sel.Value = true;
            sel.Setters.Add(new Setter(DataGridCell.BackgroundProperty, new SolidColorBrush(cSelBg)));
            sel.Setters.Add(new Setter(DataGridCell.ForegroundProperty, new SolidColorBrush(cInk)));
            cellStyle.Triggers.Add(sel);
            g.CellStyle = cellStyle;

            // 复选框列(绑定 Selected, 禁用绑定 CanDelete)
            DataGridTemplateColumn chkCol = new DataGridTemplateColumn();
            chkCol.Header = "清除";
            chkCol.Width = new DataGridLength(52);
            FrameworkElementFactory cb = new FrameworkElementFactory(typeof(CheckBox));
            cb.SetBinding(CheckBox.IsCheckedProperty, new Binding("Selected") { Mode = BindingMode.TwoWay, UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged });
            cb.SetBinding(CheckBox.IsEnabledProperty, new Binding("CanDelete"));
            cb.SetValue(CheckBox.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            cb.SetValue(CheckBox.VerticalAlignmentProperty, VerticalAlignment.Center);
            DataTemplate chkTpl = new DataTemplate();
            chkTpl.VisualTree = cb;
            chkCol.CellTemplate = chkTpl;
            g.Columns.Add(chkCol);

            // 文本列
            g.Columns.Add(MakeTextCol("类别", "Category", 90));
            g.Columns.Add(MakeTextCol("路径", "Path", new DataGridLength(1, GridUnitType.Star)));
            g.Columns.Add(MakeTextCol("大小(MB)", "SizeMB", 90));
            g.Columns.Add(MakeBrushCol("风险", "Risk", "RiskBrush", 60));
            g.Columns.Add(MakeTextCol("说明", "Note", 190));

            return g;
        }

        DataGridTextColumn MakeTextCol(string header, string prop, object width)
        {
            DataGridTextColumn col = new DataGridTextColumn();
            col.Header = header;
            col.Binding = new Binding(prop);
            if (width is DataGridLength) col.Width = (DataGridLength)width;
            else col.Width = new DataGridLength((double)width);
            col.ElementStyle = new Style(typeof(TextBlock));
            col.ElementStyle.Setters.Add(new Setter(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center));
            col.ElementStyle.Setters.Add(new Setter(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis));
            return col;
        }

        // 带颜色绑定的列(风险着色)
        DataGridTemplateColumn MakeBrushCol(string header, string textProp, string brushProp, double width)
        {
            DataGridTemplateColumn col = new DataGridTemplateColumn();
            col.Header = header;
            col.Width = new DataGridLength(width);
            FrameworkElementFactory tb = new FrameworkElementFactory(typeof(TextBlock));
            tb.SetBinding(TextBlock.TextProperty, new Binding(textProp));
            tb.SetBinding(TextBlock.ForegroundProperty, new Binding(brushProp));
            tb.SetValue(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center);
            tb.SetValue(TextBlock.FontWeightProperty, FontWeights.SemiBold);
            DataTemplate tpl = new DataTemplate();
            tpl.VisualTree = tb;
            col.CellTemplate = tpl;
            return col;
        }

        // ============ 扫描逻辑 ============
        double GetDirSizeMB(string p)
        {
            if (!Directory.Exists(p)) return 0;
            long sum = 0;
            try
            {
                Stack<string> dirs = new Stack<string>();
                dirs.Push(p);
                while (dirs.Count > 0)
                {
                    string dir = dirs.Pop();
                    try
                    {
                        foreach (string sub in Directory.GetDirectories(dir)) dirs.Push(sub);
                        foreach (string f in Directory.GetFiles(dir))
                        {
                            try { sum += new FileInfo(f).Length; } catch { }
                        }
                    }
                    catch { }
                }
            }
            catch { }
            return Math.Round(sum / 1024.0 / 1024.0, 1);
        }

        List<ScanItem> Scan()
        {
            List<ScanItem> results = new List<ScanItem>();
            string userHome = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string sysDrive = Environment.GetEnvironmentVariable("SystemDrive");
            Brush redBrush = new SolidColorBrush(cRed);
            Brush amberBrush = new SolidColorBrush(cAmber);

            string[] browsers = new string[] {
                userHome + @"\AppData\Local\Google\Chrome\User Data",
                userHome + @"\AppData\Local\Microsoft\Edge\User Data",
                userHome + @"\AppData\Roaming\Mozilla\Firefox\Profiles"
            };
            string[] browserNames = new string[] { "Chrome", "Edge", "Firefox" };
            for (int i = 0; i < browsers.Length; i++)
            {
                double size = GetDirSizeMB(browsers[i]);
                if (size > 0)
                {
                    results.Add(new ScanItem { Category = "浏览器", Path = browsers[i], SizeMB = size, Risk = "高", RiskBrush = redBrush, CanDelete = true, Note = browserNames[i] + " 密码/记录/缓存" });
                }
            }

            string[] chats = new string[] {
                userHome + @"\Documents\WeChat Files",
                userHome + @"\Documents\xwechat_files",
                userHome + @"\Documents\Tencent Files",
                userHome + @"\Documents\WXWork"
            };
            string[] chatNames = new string[] { "微信", "微信新版", "QQ", "企业微信" };
            for (int i = 0; i < chats.Length; i++)
            {
                double size = GetDirSizeMB(chats[i]);
                if (size > 0)
                {
                    results.Add(new ScanItem { Category = "聊天记录", Path = chats[i], SizeMB = size, Risk = "高", RiskBrush = redBrush, CanDelete = false, Note = chatNames[i] + " 数据(建议保留)" });
                }
            }

            double temp = GetDirSizeMB(userHome + @"\AppData\Local\Temp");
            if (temp > 0)
            {
                results.Add(new ScanItem { Category = "临时文件", Path = userHome + @"\AppData\Local\Temp", SizeMB = temp, Risk = "中", RiskBrush = amberBrush, CanDelete = true, Note = "用户临时文件" });
            }

            double recycle = GetDirSizeMB(sysDrive + @"\$Recycle.Bin");
            if (recycle > 0)
            {
                results.Add(new ScanItem { Category = "回收站", Path = sysDrive + @"\$Recycle.Bin", SizeMB = recycle, Risk = "高", RiskBrush = redBrush, CanDelete = true, Note = "已删除文件" });
            }

            double log = GetDirSizeMB(sysDrive + @"\Windows\Logs");
            if (log > 0)
            {
                results.Add(new ScanItem { Category = "系统日志", Path = sysDrive + @"\Windows\Logs", SizeMB = log, Risk = "中", RiskBrush = amberBrush, CanDelete = false, Note = "系统日志(建议保留)" });
            }

            return results;
        }

        // ============ 事件 ============
        void ScanBtn_Click(object sender, RoutedEventArgs e)
        {
            scanBtn.IsEnabled = false;
            wipeBtn.IsEnabled = false;
            status.Text = "正在扫描...";
            progress.Value = 10;
            grid.ItemsSource = null;
            this.Cursor = Cursors.Wait;

            Thread t = new Thread(delegate()
            {
                List<ScanItem> results = Scan();
                this.Dispatcher.Invoke((Action)delegate
                {
                    items = results;
                    grid.ItemsSource = results;
                    int high = 0;
                    double totalSize = 0;
                    foreach (ScanItem r in results)
                    {
                        if (r.Risk == "高") high++;
                        totalSize += r.SizeMB;
                    }
                    statHighVal.Text = high.ToString();
                    statTotalVal.Text = results.Count.ToString();
                    statSizeVal.Text = Math.Round(totalSize, 1) + " MB";
                    status.Text = "扫描完成, 检测到 " + results.Count + " 处残留";
                    progress.Value = 100;
                    wipeBtn.IsEnabled = true;
                    scanBtn.IsEnabled = true;
                    this.Cursor = Cursors.Arrow;
                });
            });
            t.IsBackground = true;
            t.Start();
        }

        void WipeBtn_Click(object sender, RoutedEventArgs e)
        {
            List<ScanItem> toDelete = new List<ScanItem>();
            foreach (ScanItem it in items)
            {
                if (it.Selected && it.CanDelete) toDelete.Add(it);
            }
            if (toDelete.Count == 0)
            {
                MessageBox.Show("请先勾选要清除的项目", "提示", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            string paths = "";
            foreach (ScanItem it in toDelete) paths += it.Path + "\n";
            MessageBoxResult confirm = MessageBox.Show("确认安全清除以下项目?\n\n" + paths, "确认清除", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (confirm != MessageBoxResult.Yes) return;

            status.Text = "正在安全清除...";
            this.Cursor = Cursors.Wait;
            this.Dispatcher.Invoke((Action)delegate { }, System.Windows.Threading.DispatcherPriority.Background);

            int success = 0, fail = 0;
            foreach (ScanItem it in toDelete)
            {
                try
                {
                    SecureWipeDir(it.Path);
                    success++;
                }
                catch { fail++; }
            }
            this.Cursor = Cursors.Arrow;
            status.Text = "清除完成: 成功 " + success + " 项, 失败 " + fail + " 项";
            MessageBox.Show("清除完成: 成功 " + success + " 项, 失败 " + fail + " 项", "完成", MessageBoxButton.OK, MessageBoxImage.Information);
            ScanBtn_Click(null, null);
        }

        // 覆盖写入 + 删除
        void SecureWipeDir(string path)
        {
            if (!Directory.Exists(path)) return;
            Stack<string> dirs = new Stack<string>();
            dirs.Push(path);
            while (dirs.Count > 0)
            {
                string dir = dirs.Pop();
                try
                {
                    foreach (string sub in Directory.GetDirectories(dir)) dirs.Push(sub);
                    foreach (string f in Directory.GetFiles(dir))
                    {
                        try
                        {
                            using (FileStream fs = new FileStream(f, FileMode.Open, FileAccess.Write))
                            {
                                byte[] buf = new byte[65536];
                                long rem = fs.Length;
                                using (RNGCryptoServiceProvider rng = new RNGCryptoServiceProvider())
                                {
                                    while (rem > 0)
                                    {
                                        int chunk = (int)Math.Min(rem, (long)buf.Length);
                                        rng.GetBytes(buf, 0, chunk);
                                        fs.Write(buf, 0, chunk);
                                        rem -= chunk;
                                    }
                                }
                            }
                        }
                        catch { }
                    }
                }
                catch { }
            }
            Directory.Delete(path, true);
        }
    }

    public class Program
    {
        [STAThread]
        static void Main()
        {
            Application app = new Application();
            MainWindow win = new MainWindow();
            app.Run(win);
        }
    }
}
