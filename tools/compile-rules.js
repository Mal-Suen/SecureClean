// winget-pkgs 规则库编译脚本
// 从 git ls-tree 导出的路径列表提取 (Publisher, AppName) 名称字典, 输出 rules.json
// 用法: node compile-rules.js <ls-tree路径文件> <输出rules.json路径>
// 路径格式: manifests/<letter>/<Publisher>/<AppName>/<version>/<yaml>
// 路径本身就是名称, 无需下载/解析 YAML 内容
// 获取路径文件:
//   git clone --depth 1 --filter=blob:none --no-checkout https://github.com/microsoft/winget-pkgs.git
//   git -C winget-pkgs ls-tree -r --name-only HEAD -- manifests/ > paths.txt

const fs = require('fs');

const pathsFile = process.argv[2];
const outFile = process.argv[3];

if (!pathsFile || !outFile) {
  console.error('Usage: node compile-rules.js <ls-tree-paths-file> <output-rules.json>');
  process.exit(1);
}

function normName(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9\u4e00-\u9fa5]/g, '');
}

const content = fs.readFileSync(pathsFile, 'utf8');
const lines = content.split('\n');

const seen = new Set();
const apps = [];
let totalLines = 0;

for (const line of lines) {
  const t = line.trim();
  if (!t) continue;
  totalLines++;
  // manifests/<letter>/<Publisher>/<AppName>/<version>/<file>
  const parts = t.split('/');
  if (parts.length < 6) continue;
  if (parts[0] !== 'manifests') continue;
  const publisher = parts[2];
  const appName = parts[3];
  if (!publisher || !appName) continue;
  const key = normName(publisher) + '|' + normName(appName);
  if (seen.has(key)) continue;
  seen.add(key);
  apps.push({
    publisher: publisher,
    name: appName,
    publisherN: normName(publisher),
    nameN: normName(appName)
  });
}

const result = {
  source: 'microsoft/winget-pkgs',
  compiledAt: new Date().toISOString(),
  pathLines: totalLines,
  appCount: apps.length,
  apps: apps
};

fs.writeFileSync(outFile, JSON.stringify(result), 'utf8');
console.log('路径行数: ' + totalLines);
console.log('软件条目(去重后): ' + apps.length);
console.log('输出: ' + outFile + ' (' + Math.round(fs.statSync(outFile).size / 1024) + ' KB)');
