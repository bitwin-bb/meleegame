local require = require(script.Parent.loader).load(script)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ContentProviderUtils = require("ContentProviderUtils")
local Maid = require("Maid")
local Rx = require("Rx")
local RxSignal = require("RxSignal")
local Table = require("Table")
local ValueObject = require("ValueObject")
local WorkspaceFolders = require("WorkspaceFolders")

local CelestialBodyRoot = require("CelestialBodyRoot")
local CelestialCycleConstants = require("CelestialCycleConstants")
local CelestialCycleTypes = require("CelestialCycleTypes")
local CelestialThunks = require("celestialThunks")
local MoonAssets = require("MoonAssets")
local RotationMath = require("RotationMath")
local SunAsset = require("SunAsset")
local WeatherServiceClient = require("WeatherServiceClient")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState

local CelestialCycleClassClient = {}
CelestialCycleClassClient.__index = CelestialCycleClassClient

local ROOT_FOLDER_NAME = "CelestialCycle"

local function resolveWorldDayIndex(): number
	local weatherState = (WeatherServiceClient :: any).state
	if typeof(weatherState) == "table" and typeof(weatherState.worldDayIndex) == "number" then
		return weatherState.worldDayIndex
	end
	return 0
end

local function cloneState(state: CelestialCycleState): CelestialCycleState
	return RotationMath.resolveCycleState(state.clockTime, state.worldDayIndex)
end

function CelestialCycleClassClient.new(): CelestialCycleClassClient
	local self = setmetatable({}, CelestialCycleClassClient)
	self.maid = Maid.new()
	self.stateValue =
		ValueObject.new(RotationMath.resolveCycleState(Lighting.ClockTime, resolveWorldDayIndex()), "table")
	self.stateChangedSignal = RxSignal.new(function()
		return self:ObserveState()
	end)
	self.initialized = false
	self.rootFolder = nil
	self.anchorRoot = nil
	self.maid:GiveTask(self.stateValue)
	return (self :: any) :: CelestialCycleClassClient
end

function CelestialCycleClassClient.PreloadAssets(self: CelestialCycleClassClient)
	local assets = { SunAsset.getImage() }
	for _, phaseName in CelestialCycleConstants.MOON_PHASES do
		table.insert(assets, MoonAssets.getImageForPhase(phaseName))
	end
	self.maid:GivePromise(ContentProviderUtils.promisePreload(assets))
end

function CelestialCycleClassClient.Publish(self: CelestialCycleClassClient)
	local cycleState = RotationMath.resolveCycleState(Lighting.ClockTime, resolveWorldDayIndex())
	self.stateValue.Value = cycleState
	if self.anchorRoot == nil then
		return
	end

	self.anchorRoot:update(Workspace.CurrentCamera)
	CelestialThunks.publishSurfaceState({
		visible = true,
		adornee = self.anchorRoot:getAdornee(),
		face = CelestialCycleConstants.SURFACE_FACE,
		brightness = CelestialCycleConstants.SURFACE_BRIGHTNESS,
		canvasSize = self.anchorRoot:getCanvasSize(),
		cycle = cycleState,
	})
end

function CelestialCycleClassClient.Init(self: CelestialCycleClassClient, container: Instance?)
	if self.initialized then
		return
	end
	self.initialized = true
	self.rootFolder = WorkspaceFolders.getOrCreateFolderInGame(ROOT_FOLDER_NAME)
	self.anchorRoot = CelestialBodyRoot.new(container or self.rootFolder)
	self:PreloadAssets()
	self:Publish()
	self.maid:GiveTask(RunService.RenderStepped:Connect(function()
		self:Publish()
	end))
end

function CelestialCycleClassClient.ObserveState(self: CelestialCycleClassClient): any
	return self.stateValue:Observe():Pipe({
		Rx.map(function(state: CelestialCycleState)
			return cloneState(state)
		end),
	})
end

function CelestialCycleClassClient.GetStateChangedSignal(self: CelestialCycleClassClient): any
	return self.stateChangedSignal
end

function CelestialCycleClassClient.GetState(self: CelestialCycleClassClient): CelestialCycleState
	return cloneState(self.stateValue.Value)
end

function CelestialCycleClassClient.Destroy(self: CelestialCycleClassClient)
	CelestialThunks.clearSurfaceState()
	if self.anchorRoot ~= nil then
		self.anchorRoot:destroy()
		self.anchorRoot = nil
	end
	if self.maid ~= nil then
		self.maid:Destroy()
	end
	self.initialized = false
end

CelestialCycleClassClient.preloadAssets = CelestialCycleClassClient.PreloadAssets
CelestialCycleClassClient.publish = CelestialCycleClassClient.Publish
CelestialCycleClassClient.init = CelestialCycleClassClient.Init
CelestialCycleClassClient.observeState = CelestialCycleClassClient.ObserveState
CelestialCycleClassClient.getStateChangedSignal = CelestialCycleClassClient.GetStateChangedSignal
CelestialCycleClassClient.getState = CelestialCycleClassClient.GetState
CelestialCycleClassClient.destroy = CelestialCycleClassClient.Destroy

export type CelestialCycleClassClient = typeof(setmetatable(
	{} :: {
		maid: any,
		rootFolder: Folder?,
		anchorRoot: CelestialBodyRoot.CelestialBodyRoot?,
		stateValue: any,
		stateChangedSignal: any,
		initialized: boolean,
	},
	{} :: typeof({ __index = CelestialCycleClassClient })
))

return Table.readonly(CelestialCycleClassClient)
