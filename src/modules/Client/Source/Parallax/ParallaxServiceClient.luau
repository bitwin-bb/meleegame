
local require = require(script.Parent.loader).load(script)

local ServiceBag = require("ServiceBag")
local Parallax = require("Parallax")
local ParallaxServiceUtils = require("ParallaxServiceUtils")

local ParallaxServiceClient = {}
ParallaxServiceClient.ServiceName = "ParallaxServiceClient"

local runtime: Parallax.Parallax? = nil

local function getRuntime(): Parallax.Parallax
	if runtime == nil then
		runtime = Parallax.new()
	end
	return runtime :: Parallax.Parallax
end

function ParallaxServiceClient.Init(
	self: any,
	containerOrServiceBag: Instance | ServiceBag.ServiceBag?
)
	local serviceBag = if ServiceBag.isServiceBag(containerOrServiceBag)
		then containerOrServiceBag :: ServiceBag.ServiceBag
		else nil
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	local container = if typeof(containerOrServiceBag) == "Instance" then containerOrServiceBag else nil
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

function ParallaxServiceClient.Destroy(self: any)
	self._serviceBag = nil
	if runtime == nil then
		return
	end
	runtime:Destroy()
	runtime = nil
end
return ParallaxServiceClient
