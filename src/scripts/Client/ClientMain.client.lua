--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = ReplicatedStorage:WaitForChild("AquariaBackup")
local gameRoot = packageRoot:WaitForChild("game")
local ItemRegistry = require(gameRoot.Shared.Modules.Items.Registry)

local loader = packageRoot:WaitForChild("loader")
local loaderRequire = require(loader).bootstrapGame(packageRoot)

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
