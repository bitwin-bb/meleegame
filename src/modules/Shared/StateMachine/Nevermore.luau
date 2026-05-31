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
	}),
	Runtime = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"ValueObject",
		"Table",
	}),
	Adapters = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"AnimationTrackUtils",
		"AnimationPromiseUtils",
		"HumanoidUtils",
		"PhysicsUtils",
		"NetworkOwnerUtils",
		"AttributeUtils",
		"AdorneeData",
		"Table",
	}),
	Controllers = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"StepUtils",
		"PlayersServicePromises",
		"Table",
	}),
	Handlers = table.freeze({
		"Maid",
		"Signal",
		"Promise",
		"AnimationTrackUtils",
		"AnimationPromiseUtils",
		"HumanoidUtils",
		"PhysicsUtils",
		"InputKeyMapUtils",
		"ToolUtils",
		"Table",
	}),
	Debug = table.freeze({
		"Maid",
		"Signal",
		"Table",
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

return Nevermore
