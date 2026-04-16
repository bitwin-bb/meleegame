--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationService.WorldGenerationServiceClient)
local biomeSlice = require(script:FindFirstAncestor("game").Client.UI.features.biome.state.biomeSlice)

type BiomeState = biomeSlice.BiomeState

local biomeThunks = {}

local BIOME_SAMPLE_INTERVAL = 0.2
local BIOME_BANNER_DURATION = 2.6
local BIOME_TYPE_CORRUPTION = 2
local DEPTH_LAYER_UNDERGROUND = 2
local DEPTH_LAYER_CAVERN = 3
local DEPTH_LAYER_DEEP = 4
local BIOME_ID_TO_NAME: { [number]: string } = {
	[1] = "The Overworld",
	[2] = "Desert",
	[3] = "Snow",
	[4] = "The Jungle",
	[5] = "The Corruption",
}

local runtime = {
	started = false,
	sampleAccumulator = 0,
	hideAt = nil :: number?,
	lastBiomeKey = nil :: string?,
	localPlayer = nil :: Player?,
	heartbeatConnection = nil :: RBXScriptConnection?,
	characterAddedConnection = nil :: RBXScriptConnection?,
}

local function resolveCharacterRootPart(characterRaw: any): BasePart?
	if typeof(characterRaw) ~= "Instance" or not characterRaw:IsA("Model") then
		return nil
	end

	local primaryPart = characterRaw.PrimaryPart
	if primaryPart ~= nil and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	local humanoidRootPart = characterRaw:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local upperTorso = characterRaw:FindFirstChild("UpperTorso")
	if upperTorso ~= nil and upperTorso:IsA("BasePart") then
		return upperTorso
	end

	local torso = characterRaw:FindFirstChild("Torso")
	if torso ~= nil and torso:IsA("BasePart") then
		return torso
	end

	return nil
end

local function resolveLocalPlayerRootPart(): BasePart?
	local localPlayer = runtime.localPlayer
	if localPlayer == nil then
		return nil
	end

	local character = localPlayer.Character
	if character == nil then
		return nil
	end

	return resolveCharacterRootPart(character)
end

local function isWorldReady(): boolean
	if typeof((WorldGenerationServiceClient :: any).state) ~= "table" then
		return false
	end

	local ok, worldState = pcall(function()
		return WorldGenerationServiceClient:getState()
	end)
	if not ok or typeof(worldState) ~= "table" then
		return false
	end

	return (worldState :: any).ready == true
end

local function resolveBiomeAtPosition(worldPosition: Vector3): (string?, string?)
	if not isWorldReady() then
		return nil, nil
	end

	local depthLayer: number?
	local depthLayerOk, depthLayerResult = pcall(function()
		return (WorldGenerationServiceClient :: any):getDepthLayerAtWorldPosition(worldPosition)
	end)
	if depthLayerOk and typeof(depthLayerResult) == "number" then
		depthLayer = math.floor(depthLayerResult)
	end

	if depthLayer == DEPTH_LAYER_CAVERN or depthLayer == DEPTH_LAYER_DEEP then
		return "caverns", "Caverns"
	end
	if depthLayer == DEPTH_LAYER_UNDERGROUND then
		return "the underground", "The Underground"
	end

	local biomeType: number?
	local biomeTypeOk, biomeTypeResult = pcall(function()
		return WorldGenerationServiceClient:getBiomeTypeAtWorldPosition(worldPosition)
	end)
	if biomeTypeOk and typeof(biomeTypeResult) == "number" then
		biomeType = math.floor(biomeTypeResult)
	end

	if biomeType == BIOME_TYPE_CORRUPTION then
		return "corruption", "The Corruption"
	end

	local biomeId: number?
	local biomeIdOk, biomeIdResult = pcall(function()
		return WorldGenerationServiceClient:getBiomeIdAtWorldPosition(worldPosition)
	end)
	if not biomeIdOk or typeof(biomeIdResult) ~= "number" then
		return nil, nil
	end

	biomeId = math.floor(biomeIdResult)
	local biomeName = BIOME_ID_TO_NAME[biomeId]
	if biomeName == nil then
		return nil, nil
	end

	return string.lower(biomeName), biomeName
end

local function showBiome(biomeKey: string, biomeName: string)
	runtime.lastBiomeKey = biomeKey
	runtime.hideAt = os.clock() + BIOME_BANNER_DURATION
	biomeSlice.showBiomeName({
		biomeKey = biomeKey,
		biomeName = biomeName,
	})
end

local function step(deltaTimeRaw: any)
	local deltaTime = if typeof(deltaTimeRaw) == "number" and deltaTimeRaw == deltaTimeRaw then deltaTimeRaw else 0
	local now = os.clock()

	local hideAt = runtime.hideAt
	if hideAt ~= nil and now >= hideAt then
		runtime.hideAt = nil
		biomeSlice.hideBiomeName()
	end

	runtime.sampleAccumulator += math.max(0, deltaTime)
	if runtime.sampleAccumulator < BIOME_SAMPLE_INTERVAL then
		return
	end
	runtime.sampleAccumulator = 0

	local rootPart = resolveLocalPlayerRootPart()
	if rootPart == nil then
		return
	end

	local biomeKey, biomeName = resolveBiomeAtPosition(rootPart.Position)
	if biomeKey == nil or biomeName == nil then
		return
	end

	if runtime.lastBiomeKey == biomeKey then
		return
	end

	showBiome(biomeKey, biomeName)
end

function biomeThunks.Start(): () -> ()
	if runtime.started then
		return biomeThunks.Stop
	end

	runtime.started = true
	runtime.sampleAccumulator = BIOME_SAMPLE_INTERVAL
	runtime.hideAt = nil
	runtime.lastBiomeKey = nil
	runtime.localPlayer = Players.LocalPlayer

	local localPlayer = runtime.localPlayer
	if localPlayer ~= nil then
		runtime.characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
			runtime.lastBiomeKey = nil
			runtime.hideAt = nil
			biomeSlice.hideBiomeName()
		end)
	end

	runtime.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if not runtime.started then
			return
		end
		step(deltaTime)
	end)

	step(BIOME_SAMPLE_INTERVAL)

	return biomeThunks.Stop
end

function biomeThunks.Stop()
	ConnectionUtils.disconnectMany({
		runtime.heartbeatConnection,
		runtime.characterAddedConnection,
	})
	runtime.heartbeatConnection = nil
	runtime.characterAddedConnection = nil

	runtime.started = false
	runtime.sampleAccumulator = 0
	runtime.hideAt = nil
	runtime.lastBiomeKey = nil
	runtime.localPlayer = nil
	biomeSlice.resetBiomeState()
end

function biomeThunks.GetBiomeState(): BiomeState
	return biomeSlice.getBiomeState()
end

biomeThunks.start = biomeThunks.Start
biomeThunks.stop = biomeThunks.Stop
biomeThunks.getBiomeState = biomeThunks.GetBiomeState

return biomeThunks
