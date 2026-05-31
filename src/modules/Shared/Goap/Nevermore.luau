--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local PACKAGE_ROLES = table.freeze({
	Core = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"Brio",
		"Rx",
		"RxSignal",
		"ValueObject",
		"Table",
		"StateStack",
		"Queue",
		"Time",
		"Cooldown",
		"Counter",
		"FunctionUtils",
		"Optional",
	}),
	Planning = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"Brio",
		"Rx",
		"RxSignal",
		"ValueObject",
		"Table",
		"StateStack",
		"Queue",
		"Time",
		"Cooldown",
		"Counter",
		"FunctionUtils",
		"Optional",
		"Conditions",
		"Probability",
		"Memoize",
		"LRUCache",
	}),
	Runtime = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"Brio",
		"Rx",
		"RxSignal",
		"ValueObject",
		"Table",
		"StateStack",
		"Queue",
		"Time",
		"Cooldown",
		"Counter",
		"FunctionUtils",
		"Optional",
	}),
	Examples = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"Brio",
		"Rx",
		"RxSignal",
		"ValueObject",
		"Table",
		"StateStack",
		"Queue",
		"Time",
		"Cooldown",
		"Counter",
		"FunctionUtils",
		"Optional",
	}),
	Integrations = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"Brio",
		"Rx",
		"RxSignal",
		"ValueObject",
		"Table",
		"PathfindingUtils",
		"HumanoidUtils",
		"PhysicsUtils",
		"AttributeUtils",
		"AdorneeData",
		"Octree",
		"Raycaster",
		"Vector3Utils",
		"CFrameUtils",
	}),
	Debug = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"Brio",
		"Rx",
		"RxSignal",
		"ValueObject",
		"Table",
		"JSONUtils",
		"Time",
		"Counter",
		"FunctionUtils",
	}),
	Exports = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"Brio",
		"Rx",
		"RxSignal",
		"ValueObject",
		"Table",
		"StateStack",
		"Queue",
	}),
})

local Nevermore = {}

local packageCache: { [string]: any } = {}

function Nevermore.Get(packageNameRaw: any): any
	assert(typeof(packageNameRaw) == "string" and packageNameRaw ~= "", "Bad packageName")

	local package = packageCache[packageNameRaw]
	if package == nil then
		package = loader(packageNameRaw)
		packageCache[packageNameRaw] = package
	end

	return package
end

function Nevermore.GetOptional(packageNameRaw: any): any?
	local ok, package = pcall(Nevermore.Get, packageNameRaw)
	return if ok then package else nil
end

function Nevermore.GetLoader(): any
	return loader
end

function Nevermore.GetRolePackages(roleRaw: any): { [string]: any }
	assert(typeof(roleRaw) == "string" and roleRaw ~= "", "Bad role")

	local names = PACKAGE_ROLES[roleRaw]
	if names == nil then
		return {}
	end

	local packages = {}
	for _, packageName in names do
		packages[packageName] = Nevermore.Get(packageName)
	end

	return packages
end

function Nevermore.CopyArray<T>(values: { T }): { T }
	return table.clone(values)
end

function Nevermore.CopyDictionary<T>(values: { [string]: T }): { [string]: T }
	return table.clone(values)
end

Nevermore.get = Nevermore.Get
Nevermore.getOptional = Nevermore.GetOptional
Nevermore.getLoader = Nevermore.GetLoader
Nevermore.getRolePackages = Nevermore.GetRolePackages
Nevermore.copyArray = Nevermore.CopyArray
Nevermore.copyDictionary = Nevermore.CopyDictionary

Nevermore.GetRolePackages("Core")

return Nevermore
