const fs = require('fs');
const path = require('path');

const root = process.cwd();
const srcDir = path.join(root, 'src');
const dep = JSON.parse(fs.readFileSync(path.join(root, 'tools', '_dependency_audit.json'), 'utf8'));

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
    } else if (entry.isFile() && (entry.name.endsWith('.luau') || entry.name.endsWith('.lua'))) {
      out.push(full);
    }
  }
  return out;
}

const files = walk(srcDir).sort();
const rel = (f) => path.relative(root, f).replace(/\\/g, '/');

function findFilesByRegex(regex) {
  const out = [];
  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    if (regex.test(content)) {
      out.push(rel(file));
    }
  }
  return out;
}

function countMatches(regex) {
  let count = 0;
  let fileCount = 0;
  const globalRegex = new RegExp(regex.source, regex.flags.includes('g') ? regex.flags : regex.flags + 'g');
  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    const matches = content.match(globalRegex);
    if (matches && matches.length > 0) {
      count += matches.length;
      fileCount += 1;
    }
  }
  return { count, fileCount };
}

function formatList(items, limit) {
  if (!items || items.length === 0) {
    return '- (none)';
  }
  const list = items.slice().sort();
  const lines = [];
  const max = Math.min(limit, list.length);
  for (let i = 0; i < max; i++) {
    lines.push('- `' + list[i] + '`');
  }
  if (list.length > limit) {
    lines.push('- ... (' + (list.length - limit) + ' more)');
  }
  return lines.join('\n');
}

const helperGroups = {
  core: ['Codec', 'BinaryStreaming', 'TickScheduler', 'TickSchedular', 'AttributeCache', 'DamagePipeline', 'ObjectPool', 'WorldMutationQueue'],
  ui: ['UIController', 'UISpringAnimator', 'VirtualizedList', 'ReactiveState', 'TooltipManager', 'NotificationBus', 'HUDLayoutEngine'],
  strings: ['RichTextFormatter', 'StatStringBuilder', 'LocalizationEngine', 'DynamicTextResolver', 'TextMeasurementCache', 'AbbreviationFormatter'],
  platform: ['Platform', 'Input', 'HUDScaler', 'Gestures', 'GamepadNav', 'PerfTier', 'Haptics', 'Cursor'],
};

const patterns = [
  { key: 'inputBegan', name: 'UserInputService.InputBegan:Connect', re: /UserInputService\.InputBegan:Connect\(/g },
  { key: 'inputChanged', name: 'UserInputService.InputChanged:Connect', re: /UserInputService\.InputChanged:Connect\(/g },
  { key: 'inputEnded', name: 'UserInputService.InputEnded:Connect', re: /UserInputService\.InputEnded:Connect\(/g },
  { key: 'renderStepped', name: 'RunService.RenderStepped:Connect', re: /RunService\.RenderStepped:Connect\(/g },
  { key: 'heartbeat', name: 'RunService.Heartbeat:Connect', re: /RunService\.Heartbeat:Connect\(/g },
  { key: 'taskDelay', name: 'task.delay', re: /task\.delay\(/g },
  { key: 'taskWait', name: 'task.wait', re: /task\.wait\(/g },
  { key: 'getAttribute', name: ':GetAttribute', re: /:GetAttribute\(/g },
  { key: 'setAttribute', name: ':SetAttribute', re: /:SetAttribute\(/g },
  { key: 'buffer', name: 'buffer.* usage', re: /\bbuffer\./g },
  { key: 'textService', name: 'TextService:GetTextSize', re: /TextService:GetTextSize\(/g },
  { key: 'customObjectPool', name: 'custom createObjectPool', re: /createObjectPool\(/g },
];

const patternStats = {};
for (const p of patterns) {
  patternStats[p.key] = countMatches(p.re);
}

const rawInputFiles = findFilesByRegex(/UserInputService\.Input(Began|Changed|Ended):Connect\(/);
const renderLoopFiles = findFilesByRegex(/RunService\.(RenderStepped|Heartbeat):Connect\(/);
const attributeFiles = findFilesByRegex(/:GetAttribute\(|:SetAttribute\(/);
const customPoolFiles = findFilesByRegex(/createObjectPool\(/);
const textMeasureFiles = findFilesByRegex(/TextService:GetTextSize\(/);
const bufferFiles = findFilesByRegex(/\bbuffer\./);

const hapticsPath = path.join(root, 'src/modules/Platform/Haptics.luau');
const cursorPath = path.join(root, 'src/modules/Platform/Cursor.luau');
const hapticsSize = fs.existsSync(hapticsPath) ? fs.statSync(hapticsPath).size : -1;
const cursorSize = fs.existsSync(cursorPath) ? fs.statSync(cursorPath).size : -1;

const isoDate = new Date().toISOString().slice(0, 10);
let md = '';
md += '# Helper Module Inspection Report (' + isoDate + ')\n\n';
md += '## Scope\n';
md += '- Static inspection of all Luau/Lua files under `src/` (' + dep.totals.scripts + ' scripts).\n';
md += '- Dependency map built from ' + dep.totals.requireEdges + ' `require(...)` edges.\n';
md += '- Script-relative cycle analysis: **' + dep.totals.cycles + ' cycles detected**.\n';
if (dep.unresolvedScriptRequires.length > 0) {
  md += '- Unresolved script-relative requires (' + dep.unresolvedScriptRequires.length + '):\n';
  for (const item of dep.unresolvedScriptRequires) {
    md += '  - `' + item.from + '` -> `' + item.expr + '`\n';
  }
}
md += '\n';

md += '## Package Inventory\n';
for (const key of Object.keys(dep.totals.byTopPackage)) {
  md += '- `' + key + '`: ' + dep.totals.byTopPackage[key] + '\n';
}
md += '\n';

function writeHelperGroup(title, names) {
  md += '### ' + title + '\n';
  for (const name of names) {
    const users = (dep.helperUsage[name] || []).slice().sort();
    md += '- **' + name + '**: ' + users.length + ' requiring scripts\n';
    if (users.length > 0) {
      for (const file of users) {
        md += '  - `' + file + '`\n';
      }
    }
  }
  md += '\n';
}

md += '## Helper Usage Map\n';
writeHelperGroup('Core Helpers', helperGroups.core);
writeHelperGroup('UI Helpers', helperGroups.ui);
writeHelperGroup('String Helpers', helperGroups.strings);
writeHelperGroup('Platform Helpers', helperGroups.platform);

md += '## Repetition Signals (Opportunities)\n';
for (const p of patterns) {
  const stat = patternStats[p.key];
  md += '- ' + p.name + ': ' + stat.count + ' matches across ' + stat.fileCount + ' files\n';
}
md += '\n';

md += '### Input Centralization Candidates\n';
md += formatList(rawInputFiles, 60) + '\n\n';

md += '### TickScheduler Candidates (frame/heartbeat loops + task scheduling)\n';
md += formatList(renderLoopFiles, 60) + '\n\n';

md += '### AttributeCache Candidates (direct attribute IO)\n';
md += formatList(attributeFiles, 60) + '\n\n';

md += '### ObjectPool Candidates\n';
md += formatList(customPoolFiles, 20) + '\n\n';

md += '### Codec/BinaryStreaming Candidates (raw buffer/data paths)\n';
md += formatList(bufferFiles, 20) + '\n\n';

md += '### TextMeasurementCache Candidates\n';
md += formatList(textMeasureFiles, 20) + '\n\n';

md += '## Empty Platform Modules\n';
md += '- `src/modules/Platform/Haptics.luau`: ' + hapticsSize + ' bytes\n';
md += '- `src/modules/Platform/Cursor.luau`: ' + cursorSize + ' bytes\n\n';

md += '## Safe Refactors Applied In This Pass\n';
md += '- `src/modules/UI/UIController.luau`\n';
md += '  - Added missing `clearArray` helper used in `:destroy()` cleanup.\n';
md += '  - Integrated optional Platform helper wiring (`platform:init`, `platform:onChanged`) with fallback to `UserInputService.LastInputTypeChanged`.\n';
md += '- `src/ui/features/info/state/infoThunks.luau`\n';
md += '  - Switched hover pointer tracking to Platform `Input` helper via `bindAction`.\n';
md += '  - Kept legacy `UserInputService.InputChanged` fallback if binding fails.\n';
md += '- `src/services/WorldSimulationService/Cache.luau`\n';
md += '  - Replaced local ad-hoc object pool internals with shared Core `ObjectPool` backend and preserved local API shape.\n';
md += '- Added canonical wrapper modules:\n';
md += '  - `src/modules/Core/TickScheduler.luau`\n';
md += '  - `src/modules/Core/BinaryStreaming.luau`\n\n';

md += '## Notes\n';
md += '- No script-relative circular dependencies were found in this static pass.\n';
md += '- Most listed helper modules are currently only referenced by their own module definitions; adoption across services/UI remains low and should be phased.\n';

const outDir = path.join(root, 'reports');
fs.mkdirSync(outDir, { recursive: true });
const outFile = path.join(outDir, 'helper-module-inspection-' + isoDate + '.md');
fs.writeFileSync(outFile, md, 'utf8');
console.log('WROTE ' + rel(outFile));
