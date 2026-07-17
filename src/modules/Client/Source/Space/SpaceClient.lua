local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local ServiceBag = require("ServiceBag")
local AudioServiceClient = require("AudioServiceClient")
local CharacterUtils = require("CharacterUtils")
local Maid = require("Maid")
local Promise: any = require("Promise")
local Rx: any = require("Rx")
local SpaceShared = require("SpaceShared")
local WeatherServiceClient = require("WeatherServiceClient")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")
local biomeSlice = require("BiomeSlice")

type MaidClass = any

local SpaceClient = {}
SpaceClient.ServiceName = "SpaceClient"

local runtime = {
	maid = nil :: MaidClass?,
	initPromise = nil :: any?,
	lastInSpace = nil :: boolean?,
}

local function getWorldState(): any?
	local ok, state = pcall(function()
		return WorldGenerationServiceClient:GetState()
	end)
	if not ok then
		return nil
	end
	return state
end

local function getLocalRootPart(): BasePart?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end
	return CharacterUtils.getPlayerRootPart(localPlayer)
end

local function isLocalPlayerInSpace(): boolean
	local rootPart = getLocalRootPart()
	if rootPart == nil then
		return false
	end

	return SpaceShared.IsInSpaceAtWorldPosition(
		rootPart.Position,
		getWorldState(),
		(WorldGenerationServiceClient :: any).worldOrigin
	)
end

local function applyCurrentWeatherSky()
	pcall(function()
		WeatherServiceClient:TransitionToSky(WeatherServiceClient:GetSkyKeyForLocalPlayer())
	end)
end

local function applyCurrentSoundtrack()
	pcall(function()
		local soundtrackBiome = AudioServiceClient:GetSoundtrackBiomeForLocalPlayer()
		if soundtrackBiome ~= nil then
			AudioServiceClient:SetSoundtrackBiome(soundtrackBiome)
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
			WeatherServiceClient:TransitionToSky(SpaceShared.SPACE_SKY_KEY)
		end)
		pcall(function()
			AudioServiceClient:SetSoundtrackBiome(SpaceShared.SPACE_SOUNDTRACK_BIOME)
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

function SpaceClient.Init(self: any, serviceBag: ServiceBag.ServiceBag?)
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	if runtime.initPromise ~= nil then
		return runtime.initPromise
	end

	runtime.initPromise = Promise.defer(function(fulfill)
		self:Start()
		fulfill(true)
	end)

	local maid = runtime.maid
	if maid ~= nil then
		maid:GivePromise(runtime.initPromise)
	end

	return runtime.initPromise
end

function SpaceClient.Destroy(self: any)
	self._serviceBag = nil
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
return SpaceClient
