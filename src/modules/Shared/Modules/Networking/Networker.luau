--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local networkingFolder = script.Parent

local BlinkClient = if RunService:IsClient() or not RunService:IsServer()
	then require(networkingFolder.BlinkClient)
	else nil
local BlinkServer = if RunService:IsServer() then require(networkingFolder.BlinkServer) else nil

local SET_TAG = "__set"
local INSTANCE_ATTRIBUTE = "__networkTag"
local INSTANCE_TAG = "__instance"
type PackedArguments = {
	Count: number,
	NilIndices: { number },
	Values: { any },
}
type PlayerGroup = Player | { Player }

export type ClientAccess = { (...any) -> any }
export type NetworkTag = string | Instance

local NetworkerClient = {}
NetworkerClient.__index = NetworkerClient

export type Client = typeof(setmetatable(
	{} :: {
		networkTag: string,
		module: { [string]: any },
		disconnect: (() -> ())?,
		changedSignals: { [string]: Signal.Signal<any> },
		destroyed: boolean,
	},
	NetworkerClient
))

local NetworkerServer = {}
NetworkerServer.__index = NetworkerServer

export type Server = typeof(setmetatable(
	{} :: {
		networkTag: string,
		module: { [string]: any }?,
		clientAccess: ClientAccess?,
		instance: Instance?,
		instanceConn: RBXScriptConnection?,
		recipients: { Player }?,
		destroyed: boolean,
	},
	NetworkerServer
))

local serverRegistry: { [string]: Server } = {}
local serverListenersBound = false

local function emptyPackedArguments(): PackedArguments
	return {
		Count = 0,
		NilIndices = {},
		Values = {},
	}
end

local function packValues(...: any): PackedArguments
	local count = select("#", ...)
	local nilIndices: { number } = {}
	local values: { any } = {}
	local valueIndex = 1

	for index = 1, count do
		local value = select(index, ...)
		if value == nil then
			table.insert(nilIndices, index)
		else
			values[valueIndex] = value
			valueIndex += 1
		end
	end

	return {
		Count = count,
		NilIndices = nilIndices,
		Values = values,
	}
end

local function unpackValues(packed: PackedArguments): (number, { any })
	local count = packed.Count
	local unpacked: { any } = table.create(count)
	local nilCursor = 1
	local valueCursor = 1

	for index = 1, count do
		if packed.NilIndices[nilCursor] == index then
			nilCursor += 1
			unpacked[index] = nil
		else
			unpacked[index] = packed.Values[valueCursor]
			valueCursor += 1
		end
	end

	return count, unpacked
end

local function resolveNetworkTag(networkTag: NetworkTag): string
	if typeof(networkTag) == "Instance" then
		local instance = networkTag :: Instance
		local attributeTag = instance:GetAttribute(INSTANCE_ATTRIBUTE)
		if typeof(attributeTag) ~= "string" then
			instance:GetAttributeChangedSignal(INSTANCE_ATTRIBUTE):Wait()
			attributeTag = instance:GetAttribute(INSTANCE_ATTRIBUTE)
		end

		assert(typeof(attributeTag) == "string", "NetworkerClient instance does not have a networkTag attribute")
		return attributeTag
	end

	return networkTag
end

function NetworkerClient.new(networkTag: NetworkTag, module: { [string]: any }): Client
	assert(RunService:IsClient(), "NetworkerClient can only be created on the client")

	local self = setmetatable({
		networkTag = if typeof(networkTag) == "string" then networkTag else "",
		module = module,
		changedSignals = {},
		destroyed = false,
	}, NetworkerClient)

	if not RunService:IsRunning() then
		return self
	end

	self.networkTag = resolveNetworkTag(networkTag)

	assert(BlinkClient ~= nil, "Blink client transport is unavailable")
	self.disconnect = BlinkClient.ServerToClient.On(
		function(serviceTag: string, method: string, packedArgs: PackedArguments)
			if self.destroyed or serviceTag ~= self.networkTag then
				return
			end

			local argumentCount, arguments = unpackValues(packedArgs)
			if method == SET_TAG then
				local key = arguments[1]
				if typeof(key) ~= "string" then
					return
				end

				self.module[key] = arguments[2]
				local changedSignal = self.changedSignals[key]
				if changedSignal then
					changedSignal:Fire(self.module[key])
				end
				return
			end

			local moduleFunc = self.module[method]
			assert(moduleFunc, "Method " .. method .. " does not exist on networkTag " .. self.networkTag)
			task.defer(moduleFunc, self.module, table.unpack(arguments, 1, argumentCount))
		end
	)

	return self
end

function NetworkerClient.getServerChangedSignal<T>(self: Client, key: string): Signal.Signal<T>
	if not self.changedSignals[key] then
		self.changedSignals[key] = Signal.new()
	end

	return self.changedSignals[key]
end

function NetworkerClient.fire(self: Client, method: string, ...: any): ()
	if not RunService:IsRunning() then
		return
	end

	assert(BlinkClient ~= nil, "Blink client transport is unavailable")
	BlinkClient.ClientToServer.Fire(self.networkTag, method, packValues(...))
end

function NetworkerClient.fetch(self: Client, method: string, ...: any): any?
	if not RunService:IsRunning() then
		return nil
	end

	assert(BlinkClient ~= nil, "Blink client transport is unavailable")
	local packedReturns = BlinkClient.ClientFetch.Invoke(self.networkTag, method, packValues(...))
	local returnCount, returns = unpackValues(packedReturns)
	return table.unpack(returns, 1, returnCount)
end

function NetworkerClient.destroy(self: Client): ()
	if self.destroyed then
		return
	end

	self.destroyed = true
	if self.disconnect then
		self.disconnect()
		self.disconnect = nil
	end

	for _, signal in self.changedSignals do
		signal:Destroy()
	end
	table.clear(self.changedSignals)
end

function NetworkerServer:_invokeClientMethod(
	player: Player,
	method: string,
	packedArgs: PackedArguments
): PackedArguments
	local module = self.module
	if not module then
		return emptyPackedArguments()
	end

	local moduleFunc = module[method]
	if not moduleFunc then
		warn("Method " .. method .. " does not exist on module", self.networkTag)
		return emptyPackedArguments()
	end

	if self.clientAccess and not table.find(self.clientAccess, moduleFunc) then
		warn(player.Name .. " attempted to call restricted method " .. method .. " on service", self.networkTag)
		return emptyPackedArguments()
	end

	local argumentCount, arguments = unpackValues(packedArgs)
	local results = table.pack(moduleFunc(module, player, table.unpack(arguments, 1, argumentCount)))
	return packValues(table.unpack(results, 1, results.n))
end

local function ensureServerListeners()
	if serverListenersBound or not RunService:IsServer() then
		return
	end

	serverListenersBound = true
	assert(BlinkServer ~= nil, "Blink server transport is unavailable")

	BlinkServer.ClientToServer.On(
		function(player: Player, serviceTag: string, method: string, packedArgs: PackedArguments)
			local networker = serverRegistry[serviceTag]
			if not networker or networker.destroyed then
				return
			end

			networker:_invokeClientMethod(player, method, packedArgs)
		end
	)

	BlinkServer.ClientFetch.On(function(player: Player, serviceTag: string, method: string, packedArgs: PackedArguments)
		local networker = serverRegistry[serviceTag]
		if not networker or networker.destroyed then
			return emptyPackedArguments()
		end

		return networker:_invokeClientMethod(player, method, packedArgs)
	end)
end

function NetworkerServer.new(networkTag: NetworkTag, module: { [string]: any }?, clientAccess: ClientAccess?): Server
	assert(RunService:IsServer(), "NetworkerServer can only be created on the server")
	if clientAccess then
		assert(module, "Module must be provided when clientAccess is set")
	end

	ensureServerListeners()

	local resolvedTag = if typeof(networkTag) == "string" then networkTag else ""
	local instance: Instance? = nil
	local instanceConn: RBXScriptConnection? = nil

	if typeof(networkTag) == "Instance" then
		instance = networkTag :: Instance
		assert(
			instance:GetAttribute(INSTANCE_ATTRIBUTE) == nil,
			"NetworkerServer instance already has a networkTag attribute"
		)

		resolvedTag = HttpService:GenerateGUID(false):sub(1, 13)
		instance:SetAttribute(INSTANCE_ATTRIBUTE, resolvedTag)
	end

	assert(serverRegistry[resolvedTag] == nil, "NetworkerServer with the same name already exists")

	local self = setmetatable({
		networkTag = resolvedTag,
		module = module,
		clientAccess = clientAccess,
		instance = instance,
		instanceConn = instanceConn,
		recipients = nil,
		destroyed = false,
	}, NetworkerServer)

	serverRegistry[resolvedTag] = self

	if instance then
		self.instanceConn = instance.Destroying:Once(function()
			self:destroy()
		end)
	end

	return self
end

function NetworkerServer.addRecipient(self: Server, player: Player): ()
	if not self.recipients then
		self.recipients = {}
	end

	assert(self.recipients, "Recipients list is nil")
	table.insert(self.recipients, player)
end

function NetworkerServer.removeRecipient(self: Server, player: Player): ()
	if not self.recipients then
		return
	end

	local index = table.find(self.recipients, player)
	if index then
		table.remove(self.recipients, index)
	end
end

function NetworkerServer.clearRecipients(self: Server): ()
	self.recipients = nil
end

function NetworkerServer.fire(self: Server, players: PlayerGroup, method: string, ...: any): ()
	assert(BlinkServer ~= nil, "Blink server transport is unavailable")

	local packedArgs = packValues(...)
	if typeof(players) == "Instance" then
		BlinkServer.ServerToClient.Fire(players :: Player, self.networkTag, method, packedArgs)
		return
	end

	BlinkServer.ServerToClient.FireList(players :: { Player }, self.networkTag, method, packedArgs)
end

function NetworkerServer.fireAll(self: Server, method: string, ...: any): ()
	assert(BlinkServer ~= nil, "Blink server transport is unavailable")
	BlinkServer.ServerToClient.FireAll(self.networkTag, method, packValues(...))
end

function NetworkerServer.fireAllExcept(self: Server, players: PlayerGroup, method: string, ...: any): ()
	assert(BlinkServer ~= nil, "Blink server transport is unavailable")

	local packedArgs = packValues(...)
	if typeof(players) == "Instance" then
		BlinkServer.ServerToClient.FireExcept(players :: Player, self.networkTag, method, packedArgs)
		return
	end

	local excludedPlayers = players :: { Player }
	for _, player in Players:GetPlayers() do
		if table.find(excludedPlayers, player) then
			continue
		end

		BlinkServer.ServerToClient.Fire(player, self.networkTag, method, packedArgs)
	end
end

function NetworkerServer.fireRecipients(self: Server, method: string, ...: any): ()
	if not self.recipients then
		warn("No recipients set for service ", self.networkTag)
		return
	end

	self:fire(self.recipients, method, ...)
end

function NetworkerServer.set(self: Server, players: PlayerGroup, index: string, value: any)
	self:fire(players, SET_TAG, index, value)
end

function NetworkerServer.setAll(self: Server, index: string, value: any)
	self:fireAll(SET_TAG, index, value)
end

function NetworkerServer.setAllExcept(self: Server, players: PlayerGroup, index: string, value: any)
	self:fireAllExcept(players, SET_TAG, index, value)
end

function NetworkerServer.setRecipients(self: Server, index: string, value: any): ()
	self:fireRecipients(SET_TAG, index, value)
end

function NetworkerServer.destroy(self: Server): ()
	if self.destroyed then
		return
	end

	self.destroyed = true
	serverRegistry[self.networkTag] = nil
	self:clearRecipients()

	if self.instanceConn then
		self.instanceConn:Disconnect()
		self.instanceConn = nil
	end

	if self.instance then
		self.instance:SetAttribute(INSTANCE_ATTRIBUTE, nil)
		self.instance = nil
	end
end

return {
	client = NetworkerClient,
	server = NetworkerServer,
	SET_TAG = SET_TAG,
	INSTANCE_ATTRIBUTE = INSTANCE_ATTRIBUTE,
	INSTANCE_TAG = INSTANCE_TAG,
}
