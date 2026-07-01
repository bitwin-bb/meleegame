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
	getRuntime():Init()
end

function CelestialCycleServer.ObserveState(_self: any): any
	return getRuntime():ObserveState()
end

function CelestialCycleServer.GetStateChangedSignal(_self: any): any
	return getRuntime():GetStateChangedSignal()
end

function CelestialCycleServer.GetState(_self: any): any
	return getRuntime():GetState()
end

function CelestialCycleServer.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:Destroy()
	runtime = nil
end
return Table.readonly(CelestialCycleServer)
