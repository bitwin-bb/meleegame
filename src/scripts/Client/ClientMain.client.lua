--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REPLICATION_TIMEOUT_SECONDS = 60
local BLOOD_ENGINE_INDEX_TOKEN = "blood-engine@"
local BLOOD_ENGINE_PACKAGE_FOLDER_NAME = "blood-engine"

local function findBloodEnginePackageRoot(packagesRoot: Instance): Instance?
	local indexRoot = packagesRoot:FindFirstChild("_Index")
	if indexRoot == nil then
		return nil
	end

	for _, packageFolder in indexRoot:GetChildren() do
		if string.find(packageFolder.Name, BLOOD_ENGINE_INDEX_TOKEN, 1, true) == nil then
			continue
		end

		local bloodEngineRoot = packageFolder:FindFirstChild(BLOOD_ENGINE_PACKAGE_FOLDER_NAME)
		if bloodEngineRoot ~= nil then
			return bloodEngineRoot
		end
	end

	return nil
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

local function waitForBloodEngineAssets(packagesRoot: Instance)
	local deadline = os.clock() + REPLICATION_TIMEOUT_SECONDS
	local bloodEngineRoot = findBloodEnginePackageRoot(packagesRoot)
	while bloodEngineRoot == nil and os.clock() < deadline do
		task.wait(0.05)
		bloodEngineRoot = findBloodEnginePackageRoot(packagesRoot)
	end

	if bloodEngineRoot == nil then
		error("timed out waiting for BloodEngine package root")
	end

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

local loader = packageRoot:WaitForChild("loader")
local loaderRequire = require(loader).bootstrapGame(packageRoot)
waitForBloodEngineAssets(ReplicatedStorage:WaitForChild("Packages"))

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
