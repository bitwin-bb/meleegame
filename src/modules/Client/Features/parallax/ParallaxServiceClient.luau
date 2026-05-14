--!strict

local Parallax = require(script.Parent.classes.Parallax)
local ParallaxServiceUtils = require(script.Parent.ParallaxServiceUtils)

local ParallaxServiceClient = {}

local runtime: Parallax.Parallax? = nil

local function getRuntime(): Parallax.Parallax
	if runtime == nil then
		runtime = Parallax.new()
	end
	return runtime :: Parallax.Parallax
end

function ParallaxServiceClient.Init(_self: any, container: Instance?)
	getRuntime():init(container)
end

function ParallaxServiceClient.SetBiome(_self: any, biomeNameRaw: any)
	getRuntime():setBiome(biomeNameRaw)
end

function ParallaxServiceClient.ForceRefresh(_self: any)
	getRuntime():forceRefresh()
end

function ParallaxServiceClient.ObserveState(_self: any): any
	return getRuntime():observeState()
end

function ParallaxServiceClient.GetStateChangedSignal(_self: any): any
	return getRuntime():getStateChangedSignal()
end

function ParallaxServiceClient.GetState(_self: any): ParallaxServiceUtils.ServiceState
	return getRuntime():getState()
end

function ParallaxServiceClient.GetCurrentBiome(_self: any): string
	return getRuntime():getCurrentBiome()
end

function ParallaxServiceClient.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:destroy()
	runtime = nil
end

ParallaxServiceClient.init = ParallaxServiceClient.Init
ParallaxServiceClient.setBiome = ParallaxServiceClient.SetBiome
ParallaxServiceClient.forceRefresh = ParallaxServiceClient.ForceRefresh
ParallaxServiceClient.observeState = ParallaxServiceClient.ObserveState
ParallaxServiceClient.getStateChangedSignal = ParallaxServiceClient.GetStateChangedSignal
ParallaxServiceClient.getState = ParallaxServiceClient.GetState
ParallaxServiceClient.getCurrentBiome = ParallaxServiceClient.GetCurrentBiome
ParallaxServiceClient.destroy = ParallaxServiceClient.Destroy

return ParallaxServiceClient
