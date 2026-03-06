const fs = require('fs');
const path = require('path');

const root = process.cwd();
const srcDir = path.join(root, 'src');

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
      continue;
    }
    if (entry.isFile() && (entry.name.endsWith('.luau') || entry.name.endsWith('.lua'))) {
      out.push(full);
    }
  }
  return out;
}

const files = walk(srcDir).sort();
const rel = (f) => path.relative(root, f).replace(/\\/g, '/');

function countByTopPackage() {
  const out = {};
  for (const file of files) {
    const r = rel(file);
    const parts = r.split('/');
    const top = parts[1] || '(unknown)';
    out[top] = (out[top] || 0) + 1;
  }
  return out;
}

function extractRequires(content) {
  const regex = /require\(([^\)]*)\)/g;
  const out = [];
  let m;
  while ((m = regex.exec(content)) !== null) {
    out.push(m[1].trim());
  }
  return out;
}

function isInitFile(filePath) {
  const base = path.basename(filePath).toLowerCase();
  return base === 'init.luau' || base === 'init.lua';
}

function findModuleInDir(baseDir, name) {
  const directFiles = [
    path.join(baseDir, name + '.luau'),
    path.join(baseDir, name + '.lua'),
  ];
  for (const c of directFiles) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) {
      return { type: 'file', path: c };
    }
  }

  const folderPath = path.join(baseDir, name);
  if (fs.existsSync(folderPath) && fs.statSync(folderPath).isDirectory()) {
    const initFiles = [
      path.join(folderPath, 'init.luau'),
      path.join(folderPath, 'init.lua'),
    ];
    for (const c of initFiles) {
      if (fs.existsSync(c) && fs.statSync(c).isFile()) {
        return { type: 'file', path: c };
      }
    }
    return { type: 'dir', path: folderPath };
  }

  return null;
}

function resolveScriptRequire(fromFile, expr) {
  const compact = expr.replace(/\s+/g, '');
  if (!compact.startsWith('script')) {
    return null;
  }

  const parts = compact.split('.').filter(Boolean);
  const fromDir = path.dirname(fromFile);
  let currentDir = fromDir;

  for (let i = 1; i < parts.length; i++) {
    const part = parts[i];
    if (part === 'Parent') {
      if (isInitFile(fromFile) && i === 1) {
        currentDir = path.dirname(fromDir);
      } else if (!isInitFile(fromFile) && i === 1) {
        currentDir = fromDir;
      } else {
        currentDir = path.dirname(currentDir);
      }
      continue;
    }

    const found = findModuleInDir(currentDir, part);
    if (!found) {
      return null;
    }

    if (found.type === 'file') {
      if (i === parts.length - 1) {
        return rel(found.path);
      }
      currentDir = path.dirname(found.path);
    } else {
      // unresolved folder node, continue traversal inside folder
      currentDir = found.path;
      if (i === parts.length - 1) {
        const initA = path.join(currentDir, 'init.luau');
        const initB = path.join(currentDir, 'init.lua');
        if (fs.existsSync(initA)) return rel(initA);
        if (fs.existsSync(initB)) return rel(initB);
        return null;
      }
    }
  }

  // require(script.Parent) style
  if (parts.length > 1 && parts[parts.length - 1] === 'Parent') {
    const initA = path.join(currentDir, 'init.luau');
    const initB = path.join(currentDir, 'init.lua');
    if (fs.existsSync(initA)) return rel(initA);
    if (fs.existsSync(initB)) return rel(initB);
  }

  return null;
}

const edges = [];
const unresolvedScriptRequires = [];
for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');
  const reqs = extractRequires(content);
  for (const req of reqs) {
    const resolved = resolveScriptRequire(file, req);
    const from = rel(file);
    edges.push({ from, expr: req, resolved });
    if (req.replace(/\s+/g, '').startsWith('script') && !resolved) {
      unresolvedScriptRequires.push({ from, expr: req });
    }
  }
}

const allRelFiles = files.map(rel);
const adj = new Map(allRelFiles.map((f) => [f, []]));
for (const edge of edges) {
  if (!edge.resolved) continue;
  if (!adj.has(edge.from)) adj.set(edge.from, []);
  adj.get(edge.from).push(edge.resolved);
}

let index = 0;
const stack = [];
const onStack = new Set();
const indices = new Map();
const low = new Map();
const sccs = [];

function strongconnect(v) {
  indices.set(v, index);
  low.set(v, index);
  index++;
  stack.push(v);
  onStack.add(v);

  for (const w of adj.get(v) || []) {
    if (!indices.has(w)) {
      strongconnect(w);
      low.set(v, Math.min(low.get(v), low.get(w)));
    } else if (onStack.has(w)) {
      low.set(v, Math.min(low.get(v), indices.get(w)));
    }
  }

  if (low.get(v) === indices.get(v)) {
    const component = [];
    while (true) {
      const w = stack.pop();
      onStack.delete(w);
      component.push(w);
      if (w === v) break;
    }
    sccs.push(component);
  }
}

for (const v of adj.keys()) {
  if (!indices.has(v)) strongconnect(v);
}

const cycles = sccs
  .filter((c) => c.length > 1 || (c.length === 1 && (adj.get(c[0]) || []).includes(c[0])))
  .map((c) => c.sort());

const helperNames = [
  'Codec','BinaryStreaming','TickScheduler','TickSchedular','AttributeCache','DamagePipeline','ObjectPool','WorldMutationQueue',
  'UIController','UISpringAnimator','VirtualizedList','ReactiveState','TooltipManager','NotificationBus','HUDLayoutEngine',
  'RichTextFormatter','StatStringBuilder','LocalizationEngine','DynamicTextResolver','TextMeasurementCache','AbbreviationFormatter',
  'Platform','Input','HUDScaler','Gestures','GamepadNav','PerfTier','Haptics','Cursor'
];

function getFinalIdentifier(expr) {
  const compact = expr.replace(/\s+/g, '');
  const tokens = compact.split('.').filter(Boolean);
  if (tokens.length === 0) {
    return '';
  }
  const tail = tokens[tokens.length - 1];
  return tail.replace(/[^A-Za-z0-9_]/g, '');
}

const helperUsage = {};
for (const name of helperNames) helperUsage[name] = [];
for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');
  const reqs = extractRequires(content);
  const finalIds = reqs.map(getFinalIdentifier);
  for (const name of helperNames) {
    if (finalIds.some((id) => id === name)) {
      helperUsage[name].push(rel(file));
    }
  }
}

const output = {
  generatedAt: new Date().toISOString(),
  totals: {
    scripts: files.length,
    byTopPackage: countByTopPackage(),
    requireEdges: edges.length,
    resolvedScriptEdges: edges.filter((e) => !!e.resolved).length,
    unresolvedScriptRequires: unresolvedScriptRequires.length,
    cycles: cycles.length,
  },
  cycles,
  unresolvedScriptRequires,
  helperUsage,
  edges,
};

fs.writeFileSync(path.join(root, 'tools', '_dependency_audit.json'), JSON.stringify(output, null, 2));
console.log('WROTE tools/_dependency_audit.json');
