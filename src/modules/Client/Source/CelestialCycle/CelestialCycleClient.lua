local require = require(script.Parent.loader).load(script)

local Table: any = require("Table")

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
	getRuntime():Init(container)
end

function CelestialCycleClient.ObserveState(_self: any): any
	return getRuntime():ObserveState()
end

function CelestialCycleClient.GetStateChangedSignal(_self: any): any
	return getRuntime():GetStateChangedSignal()
end

function CelestialCycleClient.GetState(_self: any): any
	return getRuntime():GetState()
end

function CelestialCycleClient.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:Destroy()
	runtime = nil
end
return Table.readonly(CelestialCycleClient)
