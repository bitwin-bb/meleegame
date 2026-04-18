--!strict

local RunService = game:GetService("RunService")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local nevermoreRequire = require(loaderUtils.Parent).load(script)

local ServiceBag = nevermoreRequire("ServiceBag")

local NevermoreSupport = {}

local clientServiceBag = nil
local serverServiceBag = nil

local function getActiveServiceBag()
	if RunService:IsClient() then
		return clientServiceBag
	end

	return serverServiceBag
end

local function setActiveServiceBag(serviceBag: any)
	if RunService:IsClient() then
		clientServiceBag = serviceBag
	else
		serverServiceBag = serviceBag
	end
end

function NevermoreSupport.Start(serviceTypesRaw: any): any
	local existing = getActiveServiceBag()
	if existing ~= nil then
		return existing
	end

	local serviceBag = ServiceBag.new()
	setActiveServiceBag(serviceBag)

	local ok, err = xpcall(function()
		if typeof(serviceTypesRaw) == "table" then
			for _, serviceType in serviceTypesRaw do
				if serviceType ~= nil then
					serviceBag:GetService(serviceType)
				end
			end
		end

		serviceBag:Init()
		serviceBag:Start()
	end, debug.traceback)

	if not ok then
		setActiveServiceBag(nil)
		serviceBag:Destroy()
		error(err)
	end

	return serviceBag
end

function NevermoreSupport.GetServiceBag(): any
	local serviceBag = getActiveServiceBag()
	if serviceBag == nil then
		error("NevermoreSupport.Start() must be called before retrieving services.")
	end

	return serviceBag
end

function NevermoreSupport.GetService(serviceType: any): any
	return NevermoreSupport.GetServiceBag():GetService(serviceType)
end

function NevermoreSupport.IsStarted(): boolean
	return getActiveServiceBag() ~= nil
end

function NevermoreSupport.Destroy()
	local serviceBag = getActiveServiceBag()
	if serviceBag == nil then
		return
	end

	setActiveServiceBag(nil)
	serviceBag:Destroy()
end

NevermoreSupport.start = NevermoreSupport.Start
NevermoreSupport.getServiceBag = NevermoreSupport.GetServiceBag
NevermoreSupport.getService = NevermoreSupport.GetService
NevermoreSupport.isStarted = NevermoreSupport.IsStarted
NevermoreSupport.destroy = NevermoreSupport.Destroy

return NevermoreSupport
