local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Rx = require("Rx")
local RxSignal = require("RxSignal")
local Table = require("Table")
local ValueObject = require("ValueObject")

local CelestialCycleConstants = require("CelestialCycleConstants")
local CelestialCycleTypes = require("CelestialCycleTypes")
local RotationMath = require("RotationMath")
local WeatherServiceServer = require("WeatherServiceServer")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState

local CelestialCycleClassServer = {}
CelestialCycleClassServer.__index = CelestialCycleClassServer

local function cloneState(state: CelestialCycleState): CelestialCycleState
	return RotationMath.GetCycleState(state.clockTime, state.worldDayIndex)
end

function CelestialCycleClassServer.new(): CelestialCycleClassServer
	local self = setmetatable({}, CelestialCycleClassServer)
	self.maid = Maid.new()
	self.stateValue = ValueObject.new(RotationMath.GetCycleState(0, 0), "table")
	self.stateChangedSignal = RxSignal.new(function()
		return self:ObserveState()
	end)
	self.initialized = false
	self.maid:GiveTask(self.stateValue)
	return (self :: any) :: CelestialCycleClassServer
end

function CelestialCycleClassServer.PublishFromWeather(self: CelestialCycleClassServer)
	local weatherState = WeatherServiceServer:GetState()
	self.stateValue.Value = RotationMath.GetCycleState(weatherState.clockTime, weatherState.worldDayIndex)
end

function CelestialCycleClassServer.Init(self: CelestialCycleClassServer)
	if self.initialized then
		return
	end
	self.initialized = true
	self:PublishFromWeather()
	self.maid:GiveTask(
		Rx.timer(
			CelestialCycleConstants.SERVER_OBSERVE_INTERVAL_SECONDS,
			CelestialCycleConstants.SERVER_OBSERVE_INTERVAL_SECONDS
		):Subscribe(function()
			self:PublishFromWeather()
		end)
	)
end

function CelestialCycleClassServer.ObserveState(self: CelestialCycleClassServer): any
	return self.stateValue:Observe():Pipe({
		Rx.map(function(state: CelestialCycleState)
			return cloneState(state)
		end),
	})
end

function CelestialCycleClassServer.GetStateChangedSignal(self: CelestialCycleClassServer): any
	return self.stateChangedSignal
end

function CelestialCycleClassServer.GetState(self: CelestialCycleClassServer): CelestialCycleState
	return cloneState(self.stateValue.Value)
end

function CelestialCycleClassServer.Destroy(self: CelestialCycleClassServer)
	if self.maid ~= nil then
		self.maid:Destroy()
	end
	self.initialized = false
end
export type CelestialCycleClassServer = typeof(setmetatable(
	{} :: {
		maid: any,
		stateValue: any,
		stateChangedSignal: any,
		initialized: boolean,
	},
	{} :: typeof({ __index = CelestialCycleClassServer })
))

return Table.readonly(CelestialCycleClassServer)
