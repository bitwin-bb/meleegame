const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SOURCE_ROOT = path.join(ROOT, "src");
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
	const pending = [SOURCE_ROOT];

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

			let match = methodPattern.exec(text);
			while (match !== null) {
				const methodName = match[3];
				if (!(componentFile && COMPONENT_LIFECYCLE_METHODS.has(methodName))) {
					const line = text.slice(0, match.index).split(/\r?\n/).length;
					violations.push(`${relativePath}:${line} ${match[1]}${match[2]}${methodName}`);
				}
				match = methodPattern.exec(text);
			}
		}
	}

	return violations.sort();
}

const violations = collectViolations();
if (violations.length === 0) {
	console.log("All repo-defined Luau method declarations follow PascalCase.");
	process.exit(0);
}

console.error("Found non-PascalCase Luau method declarations:");
for (const violation of violations) {
	console.error(`- ${violation}`);
}
process.exit(1);
