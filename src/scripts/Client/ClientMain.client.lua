--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REPLICATION_TIMEOUT_SECONDS = 60
local BLOOD_ENGINE_PACKAGE_NAME = "BloodEngine"
local SHARED_FOLDER_NAME = "Shared"
local VENDOR_FOLDER_NAME = "Vendor"

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

local function findLoaderModule(packageRoot: Instance): ModuleScript
	local loaderUtils = waitForRequiredDescendant(packageRoot, "LoaderUtils", REPLICATION_TIMEOUT_SECONDS)
	local loader = loaderUtils.Parent
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

local packageRoot = ReplicatedStorage:WaitForChild("AquariaBackup")
local gameRoot = packageRoot:WaitForChild("game")
local ItemRegistry = require(gameRoot.Shared.Modules.Items.Registry)
local vendorRoot =
	waitForInstancePath(ReplicatedStorage, { SHARED_FOLDER_NAME, VENDOR_FOLDER_NAME }, REPLICATION_TIMEOUT_SECONDS)

local loader = findLoaderModule(packageRoot)
local loaderRequire = require(loader).bootstrapGame(packageRoot)
waitForBloodEngineAssets(vendorRoot)

local ServiceBag = loaderRequire("ServiceBag")
local NevermoreSupport = loaderRequire("NevermoreSupport")

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

serviceBag:GetService(loaderRequire("AquariaBackupServiceClient"))

serviceBag:Init()
serviceBag:Start()
