const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { execSync } = require('child_process');
const iconv = require('iconv-lite');

let win = null;

function createWindow() {
  win = new BrowserWindow({
    width: 980,
    height: 660,
    minWidth: 900,
    minHeight: 600,
    title: 'SecureClean',
    backgroundColor: '#f5f5f7',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  win.loadFile('index.html');
}

// ============ 基础工具 ============
function getDirSizeMB(p) {
  if (!fs.existsSync(p)) return 0;
  let sum = 0;
  const stack = [p];
  while (stack.length > 0) {
    const dir = stack.pop();
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) {
          stack.push(full);
        } else {
          try { sum += fs.statSync(full).size; } catch (err) { }
        }
      }
    } catch (err) { }
  }
  return Math.round(sum / 1024 / 1024 * 10) / 10;
}

function getSizeMB(p) {
  try {
    const st = fs.statSync(p);
    if (st.isFile()) return Math.round(st.size / 1024 / 1024 * 10) / 10;
    return getDirSizeMB(p);
  } catch (err) { return 0; }
}

// 执行命令(GBK 解码)
function runCmd(cmd) {
  try {
    const buf = execSync(cmd, { timeout: 30000, windowsHide: true });
    return iconv.decode(buf, 'gbk');
  } catch (e) { return ''; }
}

function getDrives() {
  const drives = [];
  for (let i = 67; i <= 90; i++) {
    const d = String.fromCharCode(i) + ':';
    if (fs.existsSync(d + '\\')) drives.push(d);
  }
  return drives;
}

// ============ A. 残留检测 ============
// 收集注册表卸载项
function collectUninstallEntries() {
  const roots = [
    'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
    'HKLM\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
    'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall'
  ];
  const entries = [];
  for (const root of roots) {
    const out = runCmd('reg query "' + root + '" /s');
    if (!out) continue;
    const lines = out.split('\n');
    let current = null;
    for (const line of lines) {
      const t = line.trim();
      if (t.startsWith('HKEY_')) {
        if (current && current.displayName) entries.push(current);
        current = { key: t, displayName: '', location: '' };
      } else if (current && t.includes('REG_SZ')) {
        if (t.startsWith('DisplayName')) {
          current.displayName = t.replace(/^DisplayName\s+REG_SZ\s*/, '').trim();
        } else if (t.startsWith('InstallLocation')) {
          current.location = t.replace(/^InstallLocation\s+REG_SZ\s*/, '').trim();
        }
      }
    }
    if (current && current.displayName) entries.push(current);
  }
  return entries;
}

// Windows 系统目录白名单(不报为孤儿)
const SYSTEM_WHITELIST = new Set([
  // Windows 系统组件
  'Common Files', 'Internet Explorer', 'Windows Defender', 'Windows Defender Advanced Threat Protection',
  'Windows Mail', 'Windows Media Player', 'Windows NT', 'Windows Photo Viewer', 'WindowsPowerShell',
  'ModifiableWindowsApps', 'Microsoft Update Health Tools', 'RUXIM', 'Application Verifier',
  'Microsoft', 'dotnet', 'Windows Kits', 'Uninstall Information', 'Microsoft SQL Server',
  'Windows Terminal', 'NVIDIA GPU Computing Toolkit', 'WSL', 'WindowsApps', 'Npcap',
  'Ctyun UsbDk Runtime Library', 'Package Cache', 'Windows Sidebar', 'Temp',
  // SDK / 开发组件目录
  'Microsoft SDKs', 'Microsoft.NET', 'MSBuild', 'Reference Assemblies', 'InstallShield Installation Information',
  // 厂商父目录(组件分散安装, 注册表引用指向子目录或别处)
  'Adobe', 'Kingsoft', 'Google', 'Microsoft Office', 'Tencent',
  // 已知常驻组件(无独立卸载项)
  'Qwen', 'QianwenUpdater', 'QuarkUpdater', 'AOne'
]);

// PATH 引用豁免: 目录出现在 PATH 环境变量里则视为在用
function isInPath(full) {
  const pathEntries = (process.env.PATH || '').split(';')
    .map(p => p.trim().toLowerCase().replace(/\\+$/, ''))
    .filter(p => p);
  const flc = full.toLowerCase();
  for (const pe of pathEntries) {
    if (pe === flc || pe.startsWith(flc + '\\') || flc.startsWith(pe + '\\')) return true;
  }
  return false;
}

// 泛引用: InstallLocation 恰好指向 Program Files 根(如 Adobe 写 "D:\Program Files"),
// 这种引用不能豁免其下的子目录
function isGenericRef(ref) {
  const r = ref.replace(/\\+$/, '').toLowerCase();
  return r.endsWith('\\program files') || r.endsWith('\\program files (x86)');
}

// 运行中进程的可执行文件路径(用于豁免在用软件)
function getProcessPaths() {
  const out = runCmd('powershell -NoProfile -Command "Get-Process | Where-Object {$_.Path} | Select-Object -ExpandProperty Path"');
  return out.split('\n').map(l => l.trim().toLowerCase()).filter(l => l && l.includes('\\'));
}

// 名称归一化(去非字母数字中文, 小写), 用于目录名与卸载项 DisplayName 匹配
function normName(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9\u4e00-\u9fa5]/g, '');
}

function residueScan() {
  const groups = [];
  const uninstallEntries = collectUninstallEntries();
  const procPaths = getProcessPaths();
  const displayNames = uninstallEntries
    .map(e => normName(e.displayName))
    .filter(n => n.length >= 4);

  // ===== 1. 孤儿目录(Program Files 下无注册表/PATH 引用) =====
  const referenced = [];
  for (const e of uninstallEntries) {
    if (e.location) referenced.push(e.location.toLowerCase().replace(/\\+$/, ''));
    if (e.displayIcon) {
      const m = e.displayIcon.match(/^"?([A-Za-z]:\\[^",]+)/);
      if (m) referenced.push(m[1].toLowerCase());
    }
    if (e.uninstallString) {
      const m = e.uninstallString.match(/^"?([A-Za-z]:\\[^",]+)/);
      if (m) referenced.push(m[1].toLowerCase());
    }
  }
  const orphanGroup = { category: '孤儿目录(疑似搬家/卸载残留)', children: [] };
  for (const drive of getDrives()) {
    for (const pf of ['Program Files', 'Program Files (x86)']) {
      const base = path.join(drive, pf);
      if (!fs.existsSync(base)) continue;
      let names;
      try { names = fs.readdirSync(base); } catch (e) { continue; }
      for (const name of names) {
        if (SYSTEM_WHITELIST.has(name)) continue;
        const full = path.join(base, name);
        // 只报目录(过滤 desktop.ini 等文件)
        try {
          if (!fs.statSync(full).isDirectory()) continue;
        } catch (e) { continue; }
        // PATH 豁免(开发工具等在 PATH 里的目录视为在用)
        if (isInPath(full)) continue;
        const fullLc = full.toLowerCase();
        // 运行中进程豁免(目录下有进程 exe 在跑 → 在用)
        if (procPaths.some(pp => pp.startsWith(fullLc + '\\'))) continue;
        // DisplayName 匹配豁免(目录名与卸载项软件名归一化后相等/包含)
        const nameN = normName(name);
        if (nameN.length >= 4 && displayNames.some(dn => dn === nameN || dn.includes(nameN))) continue;
        // 注册表引用豁免(泛引用如 "D:\Program Files" 不豁免子目录)
        let isRef = false;
        for (const ref of referenced) {
          if (ref === fullLc) { isRef = true; break; }
          if (isGenericRef(ref)) continue;
          if (ref.startsWith(fullLc + '\\') || fullLc.startsWith(ref + '\\')) {
            isRef = true; break;
          }
        }
        if (!isRef) {
          const size = getDirSizeMB(full);
          if (size > 0) {
            orphanGroup.children.push({
              name: name, path: full, sizeMB: size, risk: '中',
              canDelete: true, note: '无注册表/PATH 引用, 疑似残留(删除前请确认)'
            });
          }
        }
      }
    }
  }
  if (orphanGroup.children.length > 0) groups.push(orphanGroup);

  // ===== 2. 悬空注册表项(InstallLocation 不存在) =====
  const danglingGroup = { category: '悬空注册表(指向已不存在的位置)', children: [] };
  for (const e of uninstallEntries) {
    if (e.location && !fs.existsSync(e.location)) {
      danglingGroup.children.push({
        name: e.displayName, path: e.key, sizeMB: 0, risk: '低',
        canDelete: true, actionType: 'registry', note: '删除悬空的卸载注册表项(仅清理无效指向, 不影响系统)'
      });
    }
  }
  if (danglingGroup.children.length > 0) groups.push(danglingGroup);

  // ===== 3. PATH 失效项 =====
  const pathGroup = { category: 'PATH 失效引用(环境变量指向不存在的目录)', children: [] };
  const pathEnv = process.env.PATH || '';
  for (const p of pathEnv.split(';')) {
    const t = p.trim();
    if (!t) continue;
    if (!fs.existsSync(t)) {
      pathGroup.children.push({
        name: t, path: t, sizeMB: 0, risk: '低',
        canDelete: true, actionType: 'path-env', note: '从 PATH 环境变量移除该失效条目(仅处理用户级)'
      });
    }
  }
  if (pathGroup.children.length > 0) groups.push(pathGroup);

  return { groups, uninstallCount: uninstallEntries.length };
}

// ============ C. 隐私体检(换机/卖机泄露面) ============
function privacyScan() {
  const userHome = os.homedir();
  const sysDrive = process.env.SystemDrive || 'C:';
  const groups = [];

  // ===== 浏览器泄露面 =====
  const browserGroup = { category: '浏览器(密码/登录态可被提取)', children: [] };
  const browsers = [
    { name: 'Chrome', data: path.join(userHome, 'AppData', 'Local', 'Google', 'Chrome', 'User Data') },
    { name: 'Edge', data: path.join(userHome, 'AppData', 'Local', 'Microsoft', 'Edge', 'User Data') }
  ];
  for (const b of browsers) {
    const def = path.join(b.data, 'Default');
    const subs = [
      { name: b.name + ' 保存的密码', p: path.join(def, 'Login Data'), risk: '高', canDelete: true, note: '登录密码数据库(可被提取)' },
      { name: b.name + ' 登录态 Cookie', p: path.join(def, 'Cookies'), risk: '高', canDelete: true, note: '会话 Cookie(可被用于免密登录)' },
      { name: b.name + ' 浏览历史', p: path.join(def, 'History'), risk: '中', canDelete: true, note: '浏览记录' },
      { name: b.name + ' 自动填充', p: path.join(def, 'Web Data'), risk: '高', canDelete: true, note: '表单/地址/银行卡自动填充' },
      { name: b.name + ' 本地存储', p: path.join(def, 'Local Storage'), risk: '中', canDelete: true, note: '网站本地数据' }
    ];
    for (const s of subs) {
      const size = getSizeMB(s.p);
      if (size > 0) {
        browserGroup.children.push({ name: s.name, path: s.p, sizeMB: size, risk: s.risk, canDelete: s.canDelete, note: s.note });
      }
    }
  }
  const ff = path.join(userHome, 'AppData', 'Roaming', 'Mozilla', 'Firefox', 'Profiles');
  const ffSize = getDirSizeMB(ff);
  if (ffSize > 0) {
    browserGroup.children.push({ name: 'Firefox 配置数据', path: ff, sizeMB: ffSize, risk: '高', canDelete: true, note: '密码/历史/配置' });
  }
  if (browserGroup.children.length > 0) groups.push(browserGroup);

  // ===== 聊天记录 =====
  const chatGroup = { category: '聊天记录(换机后新主人可查看)', children: [] };
  const chats = [
    { name: '微信(旧版数据)', p: path.join(userHome, 'Documents', 'WeChat Files') },
    { name: '微信(新版数据)', p: path.join(userHome, 'Documents', 'xwechat_files') },
    { name: 'QQ', p: path.join(userHome, 'Documents', 'Tencent Files') },
    { name: '企业微信', p: path.join(userHome, 'Documents', 'WXWork') }
  ];
  for (const c of chats) {
    const size = getDirSizeMB(c.p);
    if (size > 0) {
      chatGroup.children.push({ name: c.name, path: c.p, sizeMB: size, risk: '高', canDelete: true, note: '聊天记录/文件(确认不需要再删)' });
    }
  }
  if (chatGroup.children.length > 0) groups.push(chatGroup);

  // ===== 凭证 =====
  const credGroup = { category: '登录凭证', children: [] };
  const cmdkeyOut = runCmd('cmdkey /list');
  const credCount = (cmdkeyOut.match(/目标:/g) || []).length;
  if (credCount > 0) {
    credGroup.children.push({
      name: 'Windows 凭据管理器(' + credCount + ' 条)', path: '__credentials__', sizeMB: 0,
      risk: '高', canDelete: true, actionType: 'credential', note: '删除全部保存的凭据, 相关网站/远程登录将失效'
    });
  }
  const sshDir = path.join(userHome, '.ssh');
  if (fs.existsSync(sshDir)) {
    const keys = fs.readdirSync(sshDir).filter(f => /^id_(rsa|ed25519|ecdsa)/.test(f));
    if (keys.length > 0) {
      credGroup.children.push({
        name: 'SSH 私钥(' + keys.length + ' 个)', path: sshDir, sizeMB: getDirSizeMB(sshDir),
        risk: '高', canDelete: true, note: keys.join(', ')
      });
    }
  }
  const gitCred = path.join(userHome, '.git-credentials');
  if (fs.existsSync(gitCred)) {
    credGroup.children.push({
      name: 'Git 凭证', path: gitCred, sizeMB: getSizeMB(gitCred),
      risk: '高', canDelete: true, note: '明文保存的 git 账号密码/token'
    });
  }
  if (credGroup.children.length > 0) groups.push(credGroup);

  // ===== 可恢复数据 =====
  const recoverGroup = { category: '可恢复数据(删除后仍可被还原)', children: [] };
  const recycle = getDirSizeMB(path.join(sysDrive, '$Recycle.Bin'));
  if (recycle > 0) {
    recoverGroup.children.push({
      name: '回收站', path: path.join(sysDrive, '$Recycle.Bin'), sizeMB: recycle,
      risk: '高', canDelete: true, note: '已删除但可恢复的文件(普通删除可被还原)'
    });
  }
  const recent = getDirSizeMB(path.join(userHome, 'AppData', 'Roaming', 'Microsoft', 'Windows', 'Recent'));
  if (recent > 0) {
    recoverGroup.children.push({
      name: '最近使用记录', path: path.join(userHome, 'AppData', 'Roaming', 'Microsoft', 'Windows', 'Recent'),
      sizeMB: recent, risk: '中', canDelete: true, note: '最近打开的文件/文件夹记录'
    });
  }
  if (recoverGroup.children.length > 0) groups.push(recoverGroup);

  return groups;
}

// ============ 安全清除(覆盖写入 + 删除) ============
function secureWipeDir(dirPath) {
  if (!fs.existsSync(dirPath)) return;
  const stack = [dirPath];
  while (stack.length > 0) {
    const dir = stack.pop();
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) {
          stack.push(full);
        } else {
          try {
            const size = fs.statSync(full).size;
            if (size > 0) {
              const fd = fs.openSync(full, 'r+');
              const buf = crypto.randomBytes(65536);
              let rem = size;
              while (rem > 0) {
                const chunk = Math.min(rem, buf.length);
                if (chunk < buf.length) {
                  fs.writeSync(fd, buf.subarray(0, chunk), 0, chunk);
                } else {
                  fs.writeSync(fd, buf, 0, chunk);
                }
                rem -= chunk;
              }
              fs.closeSync(fd);
            }
          } catch (err) { }
        }
      }
    } catch (err) { }
  }
  fs.rmSync(dirPath, { recursive: true, force: true });
}

function secureWipeFile(filePath) {
  try {
    const size = fs.statSync(filePath).size;
    if (size > 0) {
      const fd = fs.openSync(filePath, 'r+');
      const buf = crypto.randomBytes(65536);
      let rem = size;
      while (rem > 0) {
        const chunk = Math.min(rem, buf.length);
        if (chunk < buf.length) {
          fs.writeSync(fd, buf.subarray(0, chunk), 0, chunk);
        } else {
          fs.writeSync(fd, buf, 0, chunk);
        }
        rem -= chunk;
      }
      fs.closeSync(fd);
    }
    fs.rmSync(filePath, { force: true });
  } catch (err) { }
}

// 从用户级 PATH 移除失效条目(系统级需管理员, 会报失败提示)
function removeFromPath(entry) {
  const out = runCmd('reg query "HKCU\\Environment" /v Path');
  const m = out.match(/Path\s+REG_EXPAND_SZ\s+(.*)/i);
  if (!m) throw new Error('无法读取用户级 PATH');
  const current = m[1].trim();
  const entries = current.split(';');
  const filtered = entries.filter(e => e.trim().toLowerCase() !== entry.toLowerCase());
  if (filtered.length === entries.length) {
    throw new Error('该条目不在用户级 PATH(可能在系统级, 需管理员手动处理)');
  }
  const newVal = filtered.join(';');
  execSync('reg add "HKCU\\Environment" /v Path /t REG_EXPAND_SZ /d "' + newVal + '" /f', { windowsHide: true, timeout: 15000 });
}

// 删除凭据管理器全部凭据
function deleteAllCredentials() {
  const out = runCmd('cmdkey /list');
  const targets = [];
  for (const line of out.split('\n')) {
    const t = line.trim();
    if (t.startsWith('目标:')) {
      targets.push(t.replace(/^目标:\s*/, '').trim());
    }
  }
  for (const target of targets) {
    try {
      execSync('cmdkey /delete:' + target, { windowsHide: true, timeout: 10000 });
    } catch (e) { }
  }
}

// ============ IPC ============
ipcMain.handle('privacy-scan', () => {
  return privacyScan();
});

ipcMain.handle('residue-scan', () => {
  return residueScan();
});

// 点击路径打开: 目录直接打开, 文件打开所在目录并选中
ipcMain.handle('open-path', (event, p) => {
  const { shell } = require('electron');
  try {
    if (!fs.existsSync(p)) {
      return { ok: false, msg: '路径不存在: ' + p };
    }
    const st = fs.statSync(p);
    if (st.isFile()) {
      shell.showItemInFolder(p);
    } else {
      shell.openPath(p);
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, msg: e.message };
  }
});

// 安全清除: 按类型分发
// items: [{ type: 'dir'|'registry'|'path-env'|'credential', target: '...' }]
ipcMain.handle('wipe', (event, items) => {
  let success = 0, fail = 0;
  const errors = [];
  for (const item of items) {
    try {
      if (item.type === 'registry') {
        execSync('reg delete "' + item.target + '" /f', { windowsHide: true, timeout: 15000 });
      } else if (item.type === 'path-env') {
        removeFromPath(item.target);
      } else if (item.type === 'credential') {
        deleteAllCredentials();
      } else {
        if (fs.existsSync(item.target)) {
          if (fs.statSync(item.target).isFile()) {
            secureWipeFile(item.target);
          } else {
            secureWipeDir(item.target);
          }
        }
      }
      success++;
    } catch (err) {
      fail++;
      errors.push(item.target + ': ' + err.message);
    }
  }
  return { success, fail, errors };
});

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  app.quit();
});
