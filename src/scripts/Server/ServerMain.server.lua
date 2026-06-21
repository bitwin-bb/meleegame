local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local PACKAGE_NAME = "AquariaBackup"
local PACKAGE_LOAD_TIMEOUT_SECONDS = 60

local PROJECT_loader_LINK_NAME = "loader"
local NEVERMORE_loader_LINK_NAME = "loader"

local PACKAGE_TRACKER_IGNORED_MODULE_PATHS = {
	"game/Client/Audio/network/Replication",
	"game/Client/Replication",
	"game/Client/SnackbarNotifications",
	"game/Client/Npc/ui/components/SlimeComponent",
	"game/Server/Npc/npc/EyeOfCthulhuNpc",
	"game/Server/Npc/npc/QueenBeeNpc",
	"game/Shared/Replication",
	"game/Shared/Replication/Packets",
	"game/Shared/StateMachine/Machines/Enemies/SlimeStateMachine",
}

local REQUIRED_ARCHIVABLE_MODULE_PATHS = {
	"game/Client/Notification/FeatureSnackbarNotifications",
	"game/Client/NetClient/ClientNetPackets",
	"game/Client/Npc/ui/components/EyeOfCthulhuComponent",
	"game/Client/Npc/ui/components/QueenBeeComponent",
}

local PACKAGE_TRACKER_IGNORE_TIMEOUT_SECONDS = 5
local PROJECT_MODULE_PACKAGE_LINK_ATTRIBUTE = "AquariaProjectModulePackageLink"

local function disableStudioWallyIndexPackageTrackerModules(packageRoot: Instance)
	if not RunService:IsStudio() then
		return
	end

	local nodeModules = packageRoot:FindFirstChild("node_modules")
	if nodeModules == nil then
		return
	end

	local wallyIndex = nodeModules:FindFirstChild("_Index")
	if wallyIndex == nil then
		return
	end

	for _, descendant in wallyIndex:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			descendant.Archivable = false
		end
	end
end

local function waitForDescendantByPath(root: Instance, path: string, timeoutSeconds: number): Instance?
	local deadline = os.clock() + timeoutSeconds
	local current = root

	for segment in string.gmatch(path, "[^/]+") do
		local child = current:FindFirstChild(segment)
		while child == nil and os.clock() < deadline do
			child = current:WaitForChild(segment, math.min(0.25, math.max(0, deadline - os.clock())))
		end
		if child == nil then
			return nil
		end

		current = child
	end

	return current
end

local function disableDuplicatePackageTrackerModules(packageRoot: Instance)
	local deadline = os.clock() + PACKAGE_TRACKER_IGNORE_TIMEOUT_SECONDS

	for _, path in REQUIRED_ARCHIVABLE_MODULE_PATHS do
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			return
		end

		local moduleScript = waitForDescendantByPath(packageRoot, path, remaining)
		if moduleScript ~= nil and moduleScript:IsA("ModuleScript") then
			moduleScript.Archivable = true
		end
	end

	for _, path in PACKAGE_TRACKER_IGNORED_MODULE_PATHS do
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			return
		end

		local moduleScript = waitForDescendantByPath(packageRoot, path, remaining)
		if moduleScript ~= nil and moduleScript:IsA("ModuleScript") then
			moduleScript.Archivable = false
		end
	end
end

local function ensureProjectModulePackageLinks(packageRoot: Instance)
	local nodeModules = packageRoot:FindFirstChild("node_modules")
	local gameRoot = packageRoot:FindFirstChild("game")
	if nodeModules == nil or not nodeModules:IsA("Folder") or gameRoot == nil then
		return
	end

	local moduleByName: { [string]: ModuleScript } = {}
	local duplicateNames: { [string]: boolean } = {}

	for _, descendant in gameRoot:GetDescendants() do
		if
			descendant:IsA("ModuleScript")
			and descendant.Archivable
			and descendant.Name ~= PROJECT_loader_LINK_NAME
			and descendant.Name ~= NEVERMORE_loader_LINK_NAME
		then
			if moduleByName[descendant.Name] ~= nil then
				duplicateNames[descendant.Name] = true
			else
				moduleByName[descendant.Name] = descendant
			end
		end
	end

	for name in duplicateNames do
		moduleByName[name] = nil
	end

	for _, child in nodeModules:GetChildren() do
		if child:IsA("ObjectValue") and child:GetAttribute(PROJECT_MODULE_PACKAGE_LINK_ATTRIBUTE) == true then
			local target = child.Value
			if
				target == nil
				or not target:IsA("ModuleScript")
				or not target.Archivable
				or moduleByName[child.Name] ~= target
			then
				child:Destroy()
			end
		end
	end

	for name, moduleScript in moduleByName do
		local existing = nodeModules:FindFirstChild(name)
		if existing == nil then
			local link = Instance.new("ObjectValue")
			link.Name = name
			link.Value = moduleScript
			link.Archivable = false
			link:SetAttribute(PROJECT_MODULE_PACKAGE_LINK_ATTRIBUTE, true)
			link.Parent = nodeModules
		elseif existing:IsA("ObjectValue") and existing:GetAttribute(PROJECT_MODULE_PACKAGE_LINK_ATTRIBUTE) == true then
			existing.Value = moduleScript
		end
	end
end

local function resolveLoaderModule(loader: Instance?): ModuleScript
	if loader == nil or not loader:IsA("ModuleScript") then
		error("replicated loader is not a ModuleScript")
	end

	return loader
end

local function shouldAddProjectloaderLink(container: Instance): boolean
	if container:FindFirstChild(PROJECT_loader_LINK_NAME) ~= nil then
		return false
	end

	for _, child in container:GetChildren() do
		if
			child:IsA("ModuleScript")
			and child.Name ~= PROJECT_loader_LINK_NAME
			and child.Name ~= NEVERMORE_loader_LINK_NAME
		then
			return true
		end
	end

	return false
end

local function ensureProjectloaderLinks(packageRoot: Instance, loader: ModuleScript)
	local gameRoot = packageRoot:FindFirstChild("game")
	if gameRoot == nil then
		return
	end

	local loaderLinkUtils = require(loader.LoaderLink.LoaderLinkUtils)
	local function ensureContainerLink(container: Instance)
		if not shouldAddProjectloaderLink(container) then
			return
		end

		local link = loaderLinkUtils.create(loader, PROJECT_loader_LINK_NAME)
		link.Parent = container
	end

	if gameRoot:IsA("Folder") then
		ensureContainerLink(gameRoot)
	end

	for _, descendant in gameRoot:GetDescendants() do
		if descendant:IsA("Folder") or descendant:IsA("ModuleScript") then
			ensureContainerLink(descendant)
		end
	end
end

local packageRoot = ServerScriptService:WaitForChild(PACKAGE_NAME, PACKAGE_LOAD_TIMEOUT_SECONDS)
assert(packageRoot ~= nil, `timed out waiting for {PACKAGE_NAME}`)
packageRoot:WaitForChild("game", PACKAGE_LOAD_TIMEOUT_SECONDS)
packageRoot:WaitForChild("node_modules", PACKAGE_LOAD_TIMEOUT_SECONDS)
local loader =
	resolveLoaderModule(assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils").Parent)
disableStudioWallyIndexPackageTrackerModules(packageRoot)
disableDuplicatePackageTrackerModules(packageRoot)
ensureProjectModulePackageLinks(packageRoot)
local require = require(loader).bootstrapGame(packageRoot)
ensureProjectloaderLinks(packageRoot, loader)

local CmdrBootstrapServer = require("CmdrBootstrapServer")
local NevermoreSupport = require("NevermoreSupport")
local ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()

NevermoreSupport.setServiceBag(serviceBag)

serviceBag:GetService(require("AquariaBackupService"))

serviceBag:Init()
serviceBag:Start()

CmdrBootstrapServer.start(serviceBag)
