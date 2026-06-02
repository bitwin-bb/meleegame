--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local PROJECT_loader_LINK_NAME = "loader"
local NEVERMORE_loader_LINK_NAME = "loader"

local PACKAGE_TRACKER_IGNORED_MODULE_PATHS = {
	"game/Client/Features/audio/network/Replication",
	"game/Client/Features/notification/SnackbarNotifications",
	"game/Client/NetClient/Packets",
	"game/Client/Replication",
	"game/Client/SnackbarNotifications",
	"game/Shared/Features/npc/ui/components/Slime",
	"game/Shared/Features/npc/npc/EyeOfCthulhu",
	"game/Shared/Features/npc/npc/QueenBee",
	"game/Shared/NetShared/Packets",
	"game/Shared/Replication",
	"game/Shared/Replication/Packets",
	"game/Shared/StateMachine/Machines/Enemies/Slime",
}

local REQUIRED_ARCHIVABLE_MODULE_PATHS = {
	"game/Shared/Features/npc/ui/components/EyeOfCthulhu",
	"game/Shared/Features/npc/ui/components/QueenBee",
}

local PACKAGE_TRACKER_IGNORE_TIMEOUT_SECONDS = 5

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

local function ensureExternalPackageLinks(packageRoot: Instance, packagesRoot: Instance)
	local nodeModules = packageRoot:FindFirstChild("node_modules")
	if nodeModules == nil or not nodeModules:IsA("Folder") then
		return
	end

	for _, packageModule in packagesRoot:GetChildren() do
		if not packageModule:IsA("ModuleScript") then
			continue
		end

		local existing = nodeModules:FindFirstChild(packageModule.Name)
		if existing == nil then
			local link = Instance.new("ObjectValue")
			link.Name = packageModule.Name
			link.Value = packageModule
			link.Archivable = false
			link.Parent = nodeModules
		elseif existing:IsA("ObjectValue") then
			existing.Value = packageModule
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

local function resolveloaderModule(loader: Instance?): ModuleScript
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

local packageRoot = ServerScriptService:WaitForChild("AquariaBackup")
local packagesRoot = ReplicatedStorage:WaitForChild("Packages")
local loader =
	resolveloaderModule(assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils").Parent)
ensureExternalPackageLinks(packageRoot, packagesRoot)
disableStudioWallyIndexPackageTrackerModules(packageRoot)
disableDuplicatePackageTrackerModules(packageRoot)
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
