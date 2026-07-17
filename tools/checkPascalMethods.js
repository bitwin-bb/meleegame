const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SOURCE_ROOT = path.join(ROOT, "src");
const LUA_EXTENSIONS = new Set([".lua", ".luau"]);
const EXCLUDED_DIRECTORIES = new Set([
	"_index",
	"node_modules",
	"packages",
	"playermodule",
	"serverpackages",
	"vendor",
]);
const REACT_LIFECYCLE_METHODS = new Set([
	"componentDidCatch",
	"componentDidMount",
	"componentDidUpdate",
	"componentWillMount",
	"componentWillReceiveProps",
	"componentWillUnmount",
	"componentWillUpdate",
	"didCatch",
	"didMount",
	"didUpdate",
	"init",
	"render",
	"shouldComponentUpdate",
	"shouldUpdate",
	"willUnmount",
]);
const REACT_COMPONENT_LOCAL_FUNCTIONS = new Map([
	["src/bootstrap/Client/LoadingScreen.client.luau", new Set(["LoadingScreenApp"])],
	["src/bootstrap/UI/Components/LoaderGui.luau", new Set(["LoaderGui"])],
	["src/modules/Client/Source/Binding/UI/Hud/BindingHintBottomBar.luau", new Set(["HintPrompt", "HintBody", "HintItem"])],
	["src/modules/Client/Source/Buff/UI/Components/Buff.lua", new Set(["BuffSlot"])],
	["src/modules/Client/Source/Health/UI/Hud/TopBar/Components/HeartMeter.luau", new Set(["HeartItem"])],
	["src/modules/Client/Source/Mana/UI/Hud/TopBar/Components/ManaMeter.luau", new Set(["ManaStarItem"])],
	["src/modules/Client/Source/Npc/UI/Components/SlimeComponent.luau", new Set(["SpriteImage"])],
	["src/modules/Client/Source/Parallax/UI/Components/CloudView.luau", new Set(["CloudImage"])],
	["src/modules/Client/Source/Parallax/UI/Components/ParallaxView.luau", new Set(["ParallaxLayer"])],
	["src/modules/Client/Source/Player/UI/Screens/InfoPlayerScreen.luau", new Set(["PopupEntry"])],
	["src/modules/Client/Source/Tile/UI/Components/BreakSurface.luau", new Set(["BreakImage", "ShinySpeck", "TileBreakSurface"])],
	["src/modules/Client/Source/UI/Core/hooks/useViewportScale.luau", new Set(["Provider"])],
	["src/modules/Client/Source/UI/Core/Primitives/UITextLabel.luau", new Set(["TextLabel"])],
	["src/modules/Client/Source/UI/Hud/LeftSideBar/LeftSideBarButtons.luau", new Set(["ExpandInventoryButton", "CraftingHudButton"])],
	["src/modules/Client/Source/UI/Shared/Gif.luau", new Set(["Gif"])],
]);
const METHOD_DEFINITION_PATTERN =
	/^[\t ]*function\s+([A-Za-z_][A-Za-z0-9_.]*)\s*([:.])\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^()\r\n]*>)?\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)?/gm;
const LOCAL_FUNCTION_DEFINITION_PATTERN =
	/^[\t ]*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^()\r\n]*>)?\s*\(/gm;

function isReactComponentFile(text) {
	return /\b(?:React|Roact)\.(?:Pure)?Component\s*:\s*extend\s*\(/.test(text);
}

function lineNumberAt(text, index) {
	return text.slice(0, index).split(/\r?\n/).length;
}

function getLongBracket(text, index) {
	if (text[index] !== "[") {
		return undefined;
	}

	let cursor = index + 1;
	while (text[cursor] === "=") {
		cursor += 1;
	}

	if (text[cursor] !== "[") {
		return undefined;
	}

	return {
		equals: cursor - index - 1,
		openEnd: cursor + 1,
	};
}

function maskNonCode(text) {
	const masked = text.split("");

	function maskRange(start, end) {
		for (let index = start; index < end; index += 1) {
			if (masked[index] !== "\n" && masked[index] !== "\r") {
				masked[index] = " ";
			}
		}
	}

	let index = 0;
	while (index < text.length) {
		const start = index;
		const character = text[index];

		if (character === "-" && text[index + 1] === "-") {
			const bracket = getLongBracket(text, index + 2);
			if (bracket !== undefined) {
				const closing = `]${"=".repeat(bracket.equals)}]`;
				const closingIndex = text.indexOf(closing, bracket.openEnd);
				index = closingIndex < 0 ? text.length : closingIndex + closing.length;
			} else {
				index += 2;
				while (index < text.length && text[index] !== "\n" && text[index] !== "\r") {
					index += 1;
				}
			}
			maskRange(start, index);
			continue;
		}

		if (character === "'" || character === '"' || character === "`") {
			const quote = character;
			index += 1;
			while (index < text.length) {
				if (text[index] === "\\") {
					index += 2;
					continue;
				}
				if (text[index] === quote) {
					index += 1;
					break;
				}
				index += 1;
			}
			maskRange(start, index);
			continue;
		}

		const bracket = getLongBracket(text, index);
		if (bracket !== undefined) {
			const closing = `]${"=".repeat(bracket.equals)}]`;
			const closingIndex = text.indexOf(closing, bracket.openEnd);
			index = closingIndex < 0 ? text.length : closingIndex + closing.length;
			maskRange(start, index);
			continue;
		}

		index += 1;
	}

	return masked.join("");
}

function toPascalCase(name) {
	return name[0].toUpperCase() + name.slice(1);
}

function toCamelCase(name) {
	return name[0].toLowerCase() + name.slice(1);
}

function toPosixPath(filePath) {
	return filePath.split(path.sep).join("/");
}

function collectSourceFiles() {
	const files = [];
	const pending = [SOURCE_ROOT];

	while (pending.length > 0) {
		const directory = pending.pop();
		for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
			if (entry.isDirectory() && EXCLUDED_DIRECTORIES.has(entry.name.toLowerCase())) {
				continue;
			}

			const fullPath = path.join(directory, entry.name);
			if (entry.isDirectory()) {
				pending.push(fullPath);
			} else if (entry.isFile() && LUA_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) {
				files.push(fullPath);
			}
		}
	}

	return files.sort();
}

function collectViolations(sourceFiles) {
	const violations = [];

	for (const fullPath of sourceFiles) {
		const text = fs.readFileSync(fullPath, "utf8");
		const codeText = maskNonCode(text);
		const componentFile = isReactComponentFile(codeText);
		const relativePath = toPosixPath(path.relative(ROOT, fullPath));

		METHOD_DEFINITION_PATTERN.lastIndex = 0;
		let match = METHOD_DEFINITION_PATTERN.exec(codeText);
		while (match !== null) {
			const owner = match[1];
			const separator = match[2];
			const methodName = match[3];
			const firstParameter = match[4];
			const usesColon = separator === ":";
			const usesExplicitSelf = separator === "." && firstParameter === "self";
			const isPublicLowercaseMethod = /^[a-z]/.test(methodName);
			const isReactLifecycle = componentFile && REACT_LIFECYCLE_METHODS.has(methodName);

			// Lowercase static functions (including .new, type guards, and utilities) are
			// idiomatic Nevermore APIs. Only instance methods use PascalCase.
			if ((usesColon || usesExplicitSelf) && isPublicLowercaseMethod && !isReactLifecycle) {
				violations.push({
					kind: "instance-method",
					line: lineNumberAt(text, match.index),
					name: methodName,
					owner,
					relativePath,
					separator,
					style: usesColon ? "colon" : "explicit self",
				});
			}

			match = METHOD_DEFINITION_PATTERN.exec(codeText);
		}

		const allowedLocalFunctions = REACT_COMPONENT_LOCAL_FUNCTIONS.get(relativePath) ?? new Set();
		LOCAL_FUNCTION_DEFINITION_PATTERN.lastIndex = 0;
		match = LOCAL_FUNCTION_DEFINITION_PATTERN.exec(codeText);
		while (match !== null) {
			const functionName = match[1];
			if (/^[A-Z]/.test(functionName) && !allowedLocalFunctions.has(functionName)) {
				violations.push({
					kind: "local-function",
					line: lineNumberAt(text, match.index),
					name: functionName,
					relativePath,
				});
			}

			match = LOCAL_FUNCTION_DEFINITION_PATTERN.exec(codeText);
		}
	}

	return violations.sort(
		(left, right) =>
			left.relativePath.localeCompare(right.relativePath) ||
			left.line - right.line ||
			left.name.localeCompare(right.name)
	);
}

const sourceFiles = collectSourceFiles();
const violations = collectViolations(sourceFiles);
if (violations.length === 0) {
	console.log(
		`Checked ${sourceFiles.length} authored Lua/Luau files; public instance methods use PascalCase and ordinary local functions use camelCase.`
	);
	process.exit(0);
}

const instanceMethodCount = violations.filter((violation) => violation.kind === "instance-method").length;
const localFunctionCount = violations.filter((violation) => violation.kind === "local-function").length;
console.error(`Found ${violations.length} authored naming violations in ${sourceFiles.length} Lua/Luau files:`);
console.error(`- ${instanceMethodCount} lowercase public instance methods`);
console.error(`- ${localFunctionCount} PascalCase ordinary local functions`);
for (const violation of violations) {
	if (violation.kind === "instance-method") {
		console.error(
			`- ${violation.relativePath}:${violation.line} ${violation.owner}${violation.separator}${violation.name}` +
				` (${violation.style}; expected ${toPascalCase(violation.name)})`
		);
	} else {
		console.error(
			`- ${violation.relativePath}:${violation.line} local function ${violation.name}` +
				` (expected ${toCamelCase(violation.name)})`
		);
	}
}
process.exit(1);
