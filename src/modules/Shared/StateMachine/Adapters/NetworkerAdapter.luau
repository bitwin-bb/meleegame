--!strict

local Nevermore = require(script.Parent.Parent.Nevermore)
local Promise = Nevermore.Get("Promise")
local Table = Nevermore.Get("Table")

local NetworkerAdapter = {}
NetworkerAdapter.__index = NetworkerAdapter

export type NetworkerAdapter = typeof(setmetatable(
	{} :: {
		networker: any?,
	},
	NetworkerAdapter
))

function NetworkerAdapter.new(networkerRaw: any?): NetworkerAdapter
	return setmetatable({
		networker = networkerRaw,
	}, NetworkerAdapter)
end

function NetworkerAdapter.Fire(self: NetworkerAdapter, methodName: string, ...: any)
	local networker = self.networker
	if networker == nil then
		return
	end
	local fire = networker.Fire or networker.fire
	if typeof(fire) == "function" then
		fire(networker, methodName, ...)
	end
end

function NetworkerAdapter.Fetch(self: NetworkerAdapter, methodName: string, ...: any): any?
	local networker = self.networker
	if networker == nil then
		return nil
	end
	local fetch = networker.Fetch or networker.fetch
	if typeof(fetch) == "function" then
		return fetch(networker, methodName, ...)
	end
	return nil
end

function NetworkerAdapter.PromiseFetch(self: NetworkerAdapter, methodName: string, ...: any): any
	local args = table.pack(...)
	return Promise.new(function(resolve)
		resolve(self:Fetch(methodName, table.unpack(args, 1, args.n)))
	end)
end

function NetworkerAdapter.IsNetworkOwner(_self: NetworkerAdapter, partRaw: any, playerRaw: any?): boolean
	if typeof(partRaw) ~= "Instance" or not partRaw:IsA("BasePart") then
		return false
	end
	if playerRaw ~= nil and (typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player")) then
		return false
	end
	local NetworkOwnerUtils = Nevermore.GetOptional("NetworkOwnerUtils")
	if NetworkOwnerUtils == nil then
		return false
	end
	return NetworkOwnerUtils.isNetworkOwner(partRaw, playerRaw)
end

function NetworkerAdapter.Destroy(self: NetworkerAdapter)
	self.networker = nil
end

NetworkerAdapter.fire = NetworkerAdapter.Fire
NetworkerAdapter.fetch = NetworkerAdapter.Fetch
NetworkerAdapter.promiseFetch = NetworkerAdapter.PromiseFetch
NetworkerAdapter.isNetworkOwner = NetworkerAdapter.IsNetworkOwner
NetworkerAdapter.destroy = NetworkerAdapter.Destroy
NetworkerAdapter.copy = Table.copy

return NetworkerAdapter
