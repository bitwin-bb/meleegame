
local require = require(script.Parent.loader).load(script)

local Parallax = require("Parallax")
local ParallaxServiceUtils = require("ParallaxServiceUtils")

local ParallaxServiceClient = {}

local runtime: Parallax.Parallax? = nil

local function getRuntime(): Parallax.Parallax
	if runtime == nil then
		runtime = Parallax.new()
	end
	return runtime :: Parallax.Parallax
end

function ParallaxServiceClient.Init(_self: any, container: Instance?)
	getRuntime():Init(container)
end

function ParallaxServiceClient.SetBiome(_self: any, biomeNameRaw: any)
	getRuntime():SetBiome(biomeNameRaw)
end

function ParallaxServiceClient.ForceRefresh(_self: any)
	getRuntime():ForceRefresh()
end

function ParallaxServiceClient.ObserveState(_self: any): any
	return getRuntime():ObserveState()
end

function ParallaxServiceClient.GetStateChangedSignal(_self: any): any
	return getRuntime():GetStateChangedSignal()
end

function ParallaxServiceClient.GetState(_self: any): ParallaxServiceUtils.ServiceState
	return getRuntime():GetState()
end

function ParallaxServiceClient.GetCurrentBiome(_self: any): string
	return getRuntime():GetCurrentBiome()
end

function ParallaxServiceClient.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:Destroy()
	runtime = nil
end
return ParallaxServiceClient
