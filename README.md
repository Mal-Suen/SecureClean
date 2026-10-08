# SecureClean

<div align="center">

**Sensitive Data Residue Detection & Privacy Leak Scanning**

**敏感数据残留检测与隐私泄露面体检**

[![Electron](https://img.shields.io/badge/Electron-33+-47848F.svg)](https://www.electronjs.org/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://github.com/Mal-Suen/SecureClean)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)

</div>

---

## Table of Contents / 目录

- [English](#english)
- [中文](#中文)

---

<a name="english"></a>
## English

### Overview

**SecureClean** detects what antivirus cleaners miss: sensitive data that survives deletion, and orphan data left behind by software migration or uninstall. It answers two questions:

- **Privacy checkup (device handover)**: before selling or handing over this PC, what can the next owner extract or recover?
- **Residue detection (software migration)**: after moving or uninstalling software, what orphan data is still sitting on disk with no live references?

### Core Features

| Module | What it does |
|--------|--------------|
| **Privacy Checkup** | Scans the leak surface: browser saved passwords / cookies / history / autofill, chat records (WeChat / QQ / WXWork), Windows credentials, SSH keys, git credentials, recoverable recycle-bin files, recent-files history |
| **Residue Detection** | Finds orphan directories under Program Files with no registry / PATH / running-process / name reference (4-layer false-positive exemption), dangling uninstall registry entries, dead PATH entries |
| **Secure Wipe** | Overwrite-then-delete for files/directories (prevents recovery); registry-key removal; dead PATH-entry removal; credential deletion — each with per-type risk warnings |
| **Risk Report** | Aggregates both scans into a 0-100 score with graded advice |

### Why Not Antivirus Cleanup

| Dimension | SecureClean | Antivirus cleanup |
|-----------|-------------|-------------------|
| Migration/uninstall residue | Purpose-built (registry + PATH + process cross-validation) | Not detected |
| Privacy leak surface | Risk report for device handover | Not provided |
| Deletion method | Overwrite, anti-recovery | Plain delete, recoverable |
| Background service | None, runs on demand | Always resident |

### Detection Boundaries (Honest Limitations)

Residue detection distinguishes "alive" vs "dead" software using five system signals: registry references (InstallLocation / DisplayIcon / UninstallString), PATH entries, running processes, directory mtime activity (90-day window), and name matching. The exemption algorithms are universal — they read Windows mechanisms, not machine-specific presets. Each exemption creates a known blind spot:

1. **90-day activity lag** — recently uninstalled software keeps a fresh mtime and is exempted for up to 90 days; residue becomes detectable after the window. Irrelevant for device-handover scenarios (long past 90 days).
2. **Incomplete uninstalls** — if both the registry entry and the directory survive an uninstall, the registry still declares the software installed (it also still appears in Control Panel); the tool treats it as installed by design.
3. **Multiple copies** — the same software on multiple drives, where the older copy was active within 90 days, is exempted (dedicated multi-copy detection is on the roadmap).

Measured on a real machine: **83% recall** (5/6 known residues; the miss is a boundary case of blind spot 1) and **88% precision** (remaining false positives are user-recognizable). A rules dictionary compiled from microsoft/winget-pkgs (13,148 apps) labels findings with probable software names — labeling only, never exemption, so uninstalled software is never wrongly suppressed.

### Installation & Quick Start

```bash
git clone https://github.com/Mal-Suen/SecureClean.git
cd SecureClean/app
npm install --registry=https://registry.npmmirror.com
npm start
```

### Project Structure

```
SecureClean/
├── app/               # Electron app (current product)
│   ├── main.js        # Main process: scan/wipe logic + IPC
│   ├── preload.js     # contextBridge
│   ├── index.html     # Renderer: 3-tab UI, collapsible grouped results
│   └── package.json
├── docs/              # Product scenario plan
├── legacy/            # Archived history (PowerShell / C# WinForms versions)
└── DESIGN.md          # Apple design-language reference
```

---

<a name="中文"></a>
## 中文

### 概述

**SecureClean** 检测杀毒软件清理不覆盖的两类数据：删除后仍然存在的敏感数据，以及软件搬家/卸载后留下的孤儿数据。它回答两个问题：

- **隐私体检（换机/卖机）**：卖掉或移交这台电脑前，下一个主人能提取或恢复哪些数据？
- **残留检测（软件搬家）**：软件搬家或卸载后，磁盘上还残留哪些没有存活引用的孤儿数据？

### 核心功能

| 模块 | 功能 |
|------|------|
| **隐私体检** | 扫描泄露面：浏览器保存的密码/Cookie/历史/自动填充、聊天记录（微信/QQ/企业微信）、Windows 凭据、SSH 私钥、Git 凭证、回收站可恢复文件、最近使用记录 |
| **残留检测** | 检测 Program Files 下无注册表/PATH/运行进程/名称引用的孤儿目录（四层豁免防误报）、悬空的卸载注册表项、PATH 失效条目 |
| **安全清除** | 目录/文件覆盖写入后删除（防恢复）；注册表项删除；PATH 失效条目移除；凭据删除——每类操作均带风险提示 |
| **风险报告** | 汇总两项扫描，输出 0-100 风险评分与分级建议 |

### 与杀毒软件清理的区别

| 维度 | SecureClean | 杀毒软件清理 |
|------|-------------|-------------|
| 搬家/卸载残留 | 专门检测（注册表/PATH/进程交叉验证） | 不识别 |
| 隐私泄露面 | 按换机场景输出风险报告 | 不做 |
| 删除方式 | 覆盖写入，防数据恢复 | 普通删除，可被恢复 |
| 常驻后台 | 无，用完即走 | 有 |

残留检测以注册表引用、PATH、运行进程、目录活跃度（90 天窗口）、名称匹配五类信号交叉判定，规则字典（13148 个软件）仅为结果标注名称、不参与豁免。刚卸载的软件在 90 天活跃窗口内会被豁免，超过窗口必然检出。真机实测：召回率 83%，精确率 88%。

### 安装与运行

```bash
git clone https://github.com/Mal-Suen/SecureClean.git
cd SecureClean/app
npm install --registry=https://registry.npmmirror.com
npm start
```

### 项目结构

```
SecureClean/
├── app/               # Electron 应用（当前产品）
│   ├── main.js        # 主进程：扫描/清除逻辑 + IPC
│   ├── preload.js     # contextBridge
│   ├── index.html     # 渲染进程：三 Tab 界面，折叠分组结果
│   └── package.json
├── docs/              # 产品方案文档
├── legacy/            # 历史版本归档（PowerShell / C# WinForms）
└── DESIGN.md          # Apple 设计语言参考
```
