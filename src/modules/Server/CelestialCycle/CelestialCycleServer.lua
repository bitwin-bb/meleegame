local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CelestialCycleClassServer = require("CelestialCycleClassServer")

local CelestialCycleServer = {}

local runtime: CelestialCycleClassServer.CelestialCycleClassServer? = nil

local function getRuntime(): CelestialCycleClassServer.CelestialCycleClassServer
	if runtime == nil then
		runtime = CelestialCycleClassServer.new()
	end
	return runtime :: CelestialCycleClassServer.CelestialCycleClassServer
end

function CelestialCycleServer.Init(_self: any)
	getRuntime():init()
end

function CelestialCycleServer.ObserveState(_self: any): any
	return getRuntime():observeState()
end

function CelestialCycleServer.GetStateChangedSignal(_self: any): any
	return getRuntime():getStateChangedSignal()
end

function CelestialCycleServer.GetState(_self: any): any
	return getRuntime():getState()
end

function CelestialCycleServer.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:destroy()
	runtime = nil
end

CelestialCycleServer.init = CelestialCycleServer.Init
CelestialCycleServer.observeState = CelestialCycleServer.ObserveState
CelestialCycleServer.getStateChangedSignal = CelestialCycleServer.GetStateChangedSignal
CelestialCycleServer.getState = CelestialCycleServer.GetState
CelestialCycleServer.destroy = CelestialCycleServer.Destroy

return Table.readonly(CelestialCycleServer)
