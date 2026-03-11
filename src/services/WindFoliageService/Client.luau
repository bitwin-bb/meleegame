--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local WindFoliage = require(ReplicatedStorage.Shared.Classes.WindFoliage)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local WindFoliageServiceClient = {}

local function resolveConfig(): { [string]: any }
	local configSource = if typeof(Configs) == "table" then (Configs :: any).windFoliage else nil
	return if typeof(configSource) == "table" then table.clone(configSource) else {}
end

function WindFoliageServiceClient.init(self: any)
	if self.janitor ~= nil then
		return
	end

	local config = resolveConfig()
	if config.enabled == false then
		return
	end

	local runtime = CoreRuntime.getClientRuntime()
	local tickScheduler = runtime:getTickScheduler()
	config.tickScheduler = tickScheduler

	self.simulation = WindFoliage.new(config)
	self.simulation:init()
	self.janitor = Janitor.new()

	local janitor = self.janitor :: JanitorClass
	janitor:GiveChore(function()
		if self.simulation ~= nil then
			self.simulation:destroy()
			self.simulation = nil
		end
	end)
end

function WindFoliageServiceClient.addDisturbance(self: any, paramsRaw: any): number?
	if self.simulation == nil then
		return nil
	end
	return self.simulation:addDisturbance(paramsRaw)
end

function WindFoliageServiceClient.registerFoliage(self: any, instanceRaw: any)
	if self.simulation == nil then
		return nil
	end
	return self.simulation:registerFoliage(instanceRaw)
end

function WindFoliageServiceClient.unregisterFoliage(self: any, instanceRaw: any)
	if self.simulation == nil then
		return
	end
	self.simulation:unregisterFoliage(instanceRaw)
end

function WindFoliageServiceClient.trackDisturber(self: any, instanceRaw: any, overrideConfigRaw: any?)
	if self.simulation == nil then
		return nil
	end
	return self.simulation:trackDisturber(instanceRaw, overrideConfigRaw)
end

function WindFoliageServiceClient.untrackDisturber(self: any, instanceRaw: any)
	if self.simulation == nil then
		return
	end
	self.simulation:untrackDisturber(instanceRaw)
end

function WindFoliageServiceClient.getStats(self: any): { [string]: number }
	if self.simulation == nil then
		return {}
	end
	return self.simulation:getStats()
end

function WindFoliageServiceClient.destroy(self: any)
	if self.janitor ~= nil then
		local janitor = self.janitor :: JanitorClass
		janitor:Destroy()
		self.janitor = nil
	end
	self.simulation = nil
end

return WindFoliageServiceClient
