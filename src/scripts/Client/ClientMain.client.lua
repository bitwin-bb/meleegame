local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REPLICATION_TIMEOUT_SECONDS = 60
local BLOOD_ENGINE_PACKAGE_NAME = "BloodEngine"
local PROJECT_loader_LINK_NAME = "loader"
local NEVERMORE_loader_LINK_NAME = "loader"
local SHARED_FOLDER_NAME = "Shared"
local VENDOR_FOLDER_NAME = "Vendor"

local PACKAGE_TRACKER_IGNORED_MODULE_PATHS = {
	"game/Client/Audio/network/Replication",
	"game/Client/Replication",
	"game/Client/SnackbarNotifications",
	"game/Server/Net/ServerNetPackets",
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

local function waitForInstancePath(root: Instance, path: { string }, timeoutSeconds: number): Instance
	local deadline = os.clock() + timeoutSeconds
	local current = root

	for _, childName in path do
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			error(`timed out waiting for {current:GetFullName()}.{childName}`)
		end

		local child = current:FindFirstChild(childName)
		if child == nil then
			child = current:WaitForChild(childName, remaining)
		end
		if child == nil then
			error(`timed out waiting for {current:GetFullName()}.{childName}`)
		end

		current = child
	end

	return current
end

local function waitForRequiredDescendant(parent: Instance, name: string, timeoutSeconds: number): Instance
	local deadline = os.clock() + timeoutSeconds
	local existing = parent:FindFirstChild(name, true)
	while existing == nil and os.clock() < deadline do
		task.wait(0.05)
		existing = parent:FindFirstChild(name, true)
	end

	if existing == nil then
		error(`timed out waiting for descendant {name} under {parent:GetFullName()}`)
	end

	return existing
end

local function waitForRequiredChild(parent: Instance, name: string, timeoutSeconds: number): Instance
	local child = parent:FindFirstChild(name)
	if child ~= nil then
		return child
	end

	local waitedChild = parent:WaitForChild(name, timeoutSeconds)
	if waitedChild == nil then
		error(`timed out waiting for child {name} under {parent:GetFullName()}`)
	end

	return waitedChild
end

local function findloaderModule(packageRoot: Instance): ModuleScript
	local loader = waitForRequiredDescendant(packageRoot, "LoaderUtils", REPLICATION_TIMEOUT_SECONDS).Parent
	if loader == nil or not loader:IsA("ModuleScript") then
		error("replicated loader is not a ModuleScript")
	end

	waitForRequiredChild(loader, "Dependencies", REPLICATION_TIMEOUT_SECONDS)
	waitForRequiredChild(loader, "LoaderLink", REPLICATION_TIMEOUT_SECONDS)
	waitForRequiredChild(loader, "Replication", REPLICATION_TIMEOUT_SECONDS)
	waitForRequiredChild(loader, "Maid", REPLICATION_TIMEOUT_SECONDS)
	waitForRequiredChild(loader, "Utils", REPLICATION_TIMEOUT_SECONDS)

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

local function waitForBloodEngineAssets(vendorRoot: Instance)
	local bloodEngineRoot = waitForInstancePath(vendorRoot, { BLOOD_ENGINE_PACKAGE_NAME }, REPLICATION_TIMEOUT_SECONDS)

	for _, path in
		{
			{ "Assets", "Meshes", "Droplet" },
			{ "Assets", "Meshes", "Decal" },
			{ "Assets", "Images" },
			{ "Assets", "Sounds" },
		}
	do
		waitForInstancePath(bloodEngineRoot, path, REPLICATION_TIMEOUT_SECONDS)
	end
end

local packageRoot = waitForRequiredChild(ReplicatedStorage, "AquariaBackup", REPLICATION_TIMEOUT_SECONDS)
waitForRequiredChild(packageRoot, "game", REPLICATION_TIMEOUT_SECONDS)
local packagesRoot = waitForRequiredChild(ReplicatedStorage, "Packages", REPLICATION_TIMEOUT_SECONDS)
local vendorRoot =
	waitForInstancePath(ReplicatedStorage, { SHARED_FOLDER_NAME, VENDOR_FOLDER_NAME }, REPLICATION_TIMEOUT_SECONDS)

local loader = findloaderModule(packageRoot)
ensureExternalPackageLinks(packageRoot, packagesRoot)
disableStudioWallyIndexPackageTrackerModules(packageRoot)
disableDuplicatePackageTrackerModules(packageRoot)
ensureProjectModulePackageLinks(packageRoot)
local require = require(loader).bootstrapGame(packageRoot)
ensureProjectloaderLinks(packageRoot, loader)
waitForBloodEngineAssets(vendorRoot)

local ItemRegistry = require("ItemRegistry")
local NevermoreSupport = require("NevermoreSupport")
local ServiceBag = require("ServiceBag")

local ITEM_REGISTRY_WARMUP_TIMEOUT_SECONDS = 5
local ITEM_REGISTRY_STABLE_PASSES_REQUIRED = 2

local function countDictionaryEntries(dictionaryRaw: any): number
	if typeof(dictionaryRaw) ~= "table" then
		return 0
	end

	local count = 0
	for _ in dictionaryRaw do
		count += 1
	end
	return count
end

local function warmItemRegistry()
	local deadline = os.clock() + ITEM_REGISTRY_WARMUP_TIMEOUT_SECONDS
	local lastDefinitionCount = -1
	local stablePasses = 0

	while os.clock() < deadline do
		ItemRegistry.clearCache()

		local definitionCount = countDictionaryEntries(ItemRegistry.getDefinitionsById())
		if definitionCount > 0 then
			if definitionCount == lastDefinitionCount then
				stablePasses += 1
			else
				lastDefinitionCount = definitionCount
				stablePasses = 1
			end

			if stablePasses >= ITEM_REGISTRY_STABLE_PASSES_REQUIRED then
				return
			end
		else
			lastDefinitionCount = definitionCount
			stablePasses = 0
		end

		task.wait()
	end
end

local serviceBag = ServiceBag.new()

NevermoreSupport.setServiceBag(serviceBag)
warmItemRegistry()

serviceBag:GetService(require("AquariaBackupServiceClient"))

serviceBag:Init()
serviceBag:Start()
