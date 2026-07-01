const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SOURCE_ROOTS = [
	path.join(ROOT, "src", "bootstrap"),
	path.join(ROOT, "src", "modules"),
];
const LUA_EXTENSIONS = new Set([".lua", ".luau"]);
const COMPONENT_LIFECYCLE_METHODS = new Set([
	"init",
	"render",
	"didMount",
	"didUpdate",
	"willUnmount",
	"shouldUpdate",
	"didCatch",
]);

function isComponentFile(text) {
	return /:extend\(|Roact\.Component|React\.Component/.test(text);
}

function collectViolations() {
	const violations = [];
	const pending = SOURCE_ROOTS.filter((sourceRoot) => fs.existsSync(sourceRoot));

	while (pending.length > 0) {
		const directory = pending.pop();
		for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
			if (entry.name === "Packages" || entry.name === "node_modules" || entry.name === "_Index") {
				continue;
			}

			const fullPath = path.join(directory, entry.name);
			if (entry.isDirectory()) {
				pending.push(fullPath);
				continue;
			}

			if (!LUA_EXTENSIONS.has(path.extname(entry.name))) {
				continue;
			}

			const text = fs.readFileSync(fullPath, "utf8");
			const componentFile = isComponentFile(text);
			const relativePath = path.relative(ROOT, fullPath);
			const methodPattern = /function\s+([A-Za-z_][A-Za-z0-9_]*)\s*([:.])\s*([a-z][A-Za-z0-9_]*)\s*\(/g;
			const aliasPattern =
				/^\s*([A-Za-z_][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)\s*=\s*\1\.([A-Z][A-Za-z0-9_]*)\s*$/gm;
			const selfAssignmentPattern =
				/^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\1\.\2\s*$/gm;

			let match = methodPattern.exec(text);
			while (match !== null) {
				const methodName = match[3];
				if (!(componentFile && COMPONENT_LIFECYCLE_METHODS.has(methodName))) {
					const line = text.slice(0, match.index).split(/\r?\n/).length;
					violations.push(`${relativePath}:${line} ${match[1]}${match[2]}${methodName}`);
				}
				match = methodPattern.exec(text);
			}

			match = aliasPattern.exec(text);
			while (match !== null) {
				const line = text.slice(0, match.index).split(/\r?\n/).length;
				violations.push(`${relativePath}:${line} ${match[1]}.${match[2]} alias for ${match[1]}.${match[3]}`);
				match = aliasPattern.exec(text);
			}

			match = selfAssignmentPattern.exec(text);
			while (match !== null) {
				const line = text.slice(0, match.index).split(/\r?\n/).length;
				violations.push(`${relativePath}:${line} ${match[1]}.${match[2]} no-op self-assignment`);
				match = selfAssignmentPattern.exec(text);
			}
		}
	}

	return violations.sort();
}

const violations = collectViolations();
if (violations.length === 0) {
	console.log("All repo-defined Luau methods are PascalCase without redundant method assignments.");
	process.exit(0);
}

console.error("Found Luau method casing/export issues:");
for (const violation of violations) {
	console.error(`- ${violation}`);
}
process.exit(1);
