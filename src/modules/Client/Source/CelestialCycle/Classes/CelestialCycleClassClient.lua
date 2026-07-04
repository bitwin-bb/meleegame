local require = require(script.Parent.loader).load(script)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ContentProviderUtils = require("ContentProviderUtils")
local Maid = require("Maid")
local Rx: any = require("Rx")
local RxSignal: any = require("RxSignal")
local Table: any = require("Table")
local ValueObject: any = require("ValueObject")
local WorkspaceFolders = require("WorkspaceFolders")

local CelestialBodyRoot = require("CelestialBodyRoot")
local CelestialCycleConstants = require("CelestialCycleConstants")
local CelestialCycleTypes = require("CelestialCycleTypes")
local CelestialThunks = require("CelestialThunks")
local MoonAssets = require("MoonAssets")
local RotationMath = require("RotationMath")
local SunAsset = require("SunAsset")
local WeatherServiceClient = require("WeatherServiceClient")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState

local CelestialCycleClassClient = {}
CelestialCycleClassClient.__index = CelestialCycleClassClient

local ROOT_FOLDER_NAME = "CelestialCycle"

local function GetWorldDayIndex(): number
	local weatherState = (WeatherServiceClient :: any).state
	if typeof(weatherState) == "table" and typeof(weatherState.worldDayIndex) == "number" then
		return weatherState.worldDayIndex
	end
	return 0
end

local function cloneState(state: CelestialCycleState): CelestialCycleState
	return RotationMath.GetCycleState(state.clockTime, state.worldDayIndex)
end

function CelestialCycleClassClient.new(): CelestialCycleClassClient
	local self: any = setmetatable({}, CelestialCycleClassClient)
	self.maid = Maid.new()
	self.stateValue =
		ValueObject.new(RotationMath.GetCycleState(Lighting.ClockTime, GetWorldDayIndex()), "table")
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
	local assets = { SunAsset.GetImage() }
	for _, phaseName in CelestialCycleConstants.MOON_PHASES do
		table.insert(assets, MoonAssets.GetImageForPhase(phaseName))
	end
	self.maid:GivePromise(ContentProviderUtils.promisePreload(assets))
end

function CelestialCycleClassClient.Publish(self: CelestialCycleClassClient)
	local cycleState = RotationMath.GetCycleState(Lighting.ClockTime, GetWorldDayIndex())
	self.stateValue.Value = cycleState
	if self.anchorRoot == nil then
		return
	end

	self.anchorRoot:Update(Workspace.CurrentCamera)
	CelestialThunks.PublishSurfaceState({
		visible = true,
		adornee = self.anchorRoot:GetAdornee(),
		face = CelestialCycleConstants.SURFACE_FACE,
		brightness = CelestialCycleConstants.SURFACE_BRIGHTNESS,
		canvasSize = self.anchorRoot:GetCanvasSize(),
		cycle = cycleState,
	})
end

function CelestialCycleClassClient.Init(self: CelestialCycleClassClient, container: Instance?)
	if self.initialized then
		return
	end
	self.initialized = true
	self.rootFolder = WorkspaceFolders.GetOrCreateFolderInGame(ROOT_FOLDER_NAME)
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
	CelestialThunks.ClearSurfaceState()
	if self.anchorRoot ~= nil then
		self.anchorRoot:Destroy()
		self.anchorRoot = nil
	end
	if self.maid ~= nil then
		self.maid:Destroy()
	end
	self.initialized = false
end
export type CelestialCycleClassClient = any

return Table.readonly(CelestialCycleClassClient)
