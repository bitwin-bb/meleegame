local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local AudioServiceClient = require("AudioServiceClient")
local CharacterUtils = require("CharacterUtils")
local Maid = require("Maid")
local Promise = require("Promise")
local Rx = require("Rx")
local SpaceShared = require("SpaceShared")
local WeatherServiceClient = require("WeatherServiceClient")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")
local biomeSlice = require("biomeSlice")

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	GivePromise: (self: MaidClass, promise: any) -> any,
	Destroy: (self: MaidClass) -> (),
}

local SpaceClient = {}

local runtime = {
	maid = nil :: MaidClass?,
	initPromise = nil :: any?,
	lastInSpace = nil :: boolean?,
}

local function getWorldState(): any?
	local ok, state = pcall(function()
		return WorldGenerationServiceClient:getState()
	end)
	if not ok then
		return nil
	end
	return state
end

local function resolveLocalRootPart(): BasePart?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end
	return CharacterUtils.getPlayerRootPart(localPlayer)
end

local function isLocalPlayerInSpace(): boolean
	local rootPart = resolveLocalRootPart()
	if rootPart == nil then
		return false
	end

	return SpaceShared.isInSpaceAtWorldPosition(
		rootPart.Position,
		getWorldState(),
		(WorldGenerationServiceClient :: any).worldOrigin
	)
end

local function applyCurrentWeatherSky()
	pcall(function()
		WeatherServiceClient:transitionToSky(WeatherServiceClient:resolveSkyKeyForLocalPlayer())
	end)
end

local function applyCurrentSoundtrack()
	pcall(function()
		local soundtrackBiome = AudioServiceClient:resolveSoundtrackBiomeForLocalPlayer()
		if soundtrackBiome ~= nil then
			AudioServiceClient:setSoundtrackBiome(soundtrackBiome)
		end
	end)
end

local function applySpaceState(inSpace: boolean)
	if inSpace then
		biomeSlice.showBiomeName({
			biomeKey = SpaceShared.SPACE_BIOME_KEY,
			biomeName = SpaceShared.SPACE_BIOME_NAME,
		})
		pcall(function()
			WeatherServiceClient:transitionToSky(SpaceShared.SPACE_SKY_KEY)
		end)
		pcall(function()
			AudioServiceClient:setSoundtrackBiome(SpaceShared.SPACE_SOUNDTRACK_BIOME)
		end)
		return
	end

	applyCurrentWeatherSky()
	applyCurrentSoundtrack()
end

function SpaceClient.Start(_self: any)
	if runtime.maid ~= nil then
		return
	end

	local maid = Maid.new()
	runtime.maid = maid
	runtime.lastInSpace = nil

	maid:GiveTask(Rx.timer(0, SpaceShared.SPACE_SAMPLE_INTERVAL_SECONDS):Pipe({
		Rx.map(function()
			return isLocalPlayerInSpace()
		end),
		Rx.distinct(),
	}):Subscribe(function(inSpace: boolean)
		local previousInSpace = runtime.lastInSpace
		runtime.lastInSpace = inSpace
		if previousInSpace == nil and not inSpace then
			return
		end
		applySpaceState(inSpace)
	end))
end

function SpaceClient.Init(self: any)
	if runtime.initPromise ~= nil then
		return runtime.initPromise
	end

	runtime.initPromise = Promise.defer(function(resolve)
		self:start()
		resolve(true)
	end)

	local maid = runtime.maid
	if maid ~= nil then
		maid:GivePromise(runtime.initPromise)
	end

	return runtime.initPromise
end

function SpaceClient.Destroy(_self: any)
	if runtime.maid ~= nil then
		runtime.maid:Destroy()
		runtime.maid = nil
	end
	runtime.initPromise = nil
	runtime.lastInSpace = nil
end

function SpaceClient.IsLocalPlayerInSpace(_self: any): boolean
	return isLocalPlayerInSpace()
end

SpaceClient.start = SpaceClient.Start
SpaceClient.init = SpaceClient.Init
SpaceClient.destroy = SpaceClient.Destroy
SpaceClient.isLocalPlayerInSpace = SpaceClient.IsLocalPlayerInSpace

return SpaceClient
