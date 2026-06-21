local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CelestialCycleClassClient = require("CelestialCycleClassClient")

local CelestialCycleClient = {}

local runtime: CelestialCycleClassClient.CelestialCycleClassClient? = nil

local function getRuntime(): CelestialCycleClassClient.CelestialCycleClassClient
	if runtime == nil then
		runtime = CelestialCycleClassClient.new()
	end
	return runtime :: CelestialCycleClassClient.CelestialCycleClassClient
end

function CelestialCycleClient.Init(_self: any, container: Instance?)
	getRuntime():init(container)
end

function CelestialCycleClient.ObserveState(_self: any): any
	return getRuntime():observeState()
end

function CelestialCycleClient.GetStateChangedSignal(_self: any): any
	return getRuntime():getStateChangedSignal()
end

function CelestialCycleClient.GetState(_self: any): any
	return getRuntime():getState()
end

function CelestialCycleClient.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:destroy()
	runtime = nil
end

CelestialCycleClient.init = CelestialCycleClient.Init
CelestialCycleClient.observeState = CelestialCycleClient.ObserveState
CelestialCycleClient.getStateChangedSignal = CelestialCycleClient.GetStateChangedSignal
CelestialCycleClient.getState = CelestialCycleClient.GetState
CelestialCycleClient.destroy = CelestialCycleClient.Destroy

return Table.readonly(CelestialCycleClient)
