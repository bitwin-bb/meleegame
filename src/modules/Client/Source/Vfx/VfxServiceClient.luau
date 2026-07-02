local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local VFXServicePackets = require("NetPacketsShared").VFXService

local function bindPacket(self: any, methodName: string)
	local packet = VFXServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for VFXService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "play")
	bindPacket(self, "stopAll")
	bindPacket(self, "stopChannel")
end

local VFXServiceUtils = require("VfxServiceUtils")

type VFXPlaybackOptions = VFXServiceUtils.VFXPlaybackOptions

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local VFXServiceClient = {}

function VFXServiceClient.TrackRuntime(self: VFXServiceClient, runtimeRoot: BasePart, channelName: string?)
	self.activeRuntimes[runtimeRoot] = true

	local destroyConnection: RBXScriptConnection?
	destroyConnection = runtimeRoot.Destroying:Connect(function()
		self.activeRuntimes[runtimeRoot] = nil
		if channelName ~= nil and self.channelRuntimes[channelName] == runtimeRoot then
			self.channelRuntimes[channelName] = nil
		end
		if destroyConnection ~= nil then
			destroyConnection:Disconnect()
			destroyConnection = nil
		end
	end)
end

function VFXServiceClient.Play(self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any): BasePart?
	local effectTemplate = VFXServiceUtils.GetEffectTemplate(effectSourceRaw)
	if effectTemplate == nil then
		return nil
	end

	local options: VFXPlaybackOptions = VFXServiceUtils.CoercePlaybackOptions(optionsRaw)
	if options.channel ~= nil and options.replaceChannel then
		self:StopChannel(options.channel)
	end

	local runtimeParent: Instance = self.runtimeFolder
	if options.parent ~= nil and options.parent.Parent ~= nil then
		runtimeParent = options.parent
	end

	local runtimeRoot = VFXServiceUtils.CreateRuntimeEffect(effectTemplate, runtimeParent)
	if runtimeRoot == nil then
		return nil
	end

	local playbackCFrame = VFXServiceUtils.GetPlaybackCFrame(options)
	if playbackCFrame ~= nil then
		runtimeRoot.CFrame = playbackCFrame
	end

	if options.channel ~= nil then
		self.channelRuntimes[options.channel] = runtimeRoot
	end
	self:TrackRuntime(runtimeRoot, options.channel)

	VFXServiceUtils.SetRuntimeEffectEnabled(runtimeRoot, true)
	if options.emitCount ~= nil then
		VFXServiceUtils.EmitRuntimeParticles(runtimeRoot, options.emitCount)
	end

	local enabledDuration = math.max(0, options.enabledDuration)
	if enabledDuration <= 0 then
		VFXServiceUtils.SetRuntimeEffectEnabled(runtimeRoot, false)
	else
		task.delay(enabledDuration, function()
			if runtimeRoot.Parent ~= nil then
				VFXServiceUtils.SetRuntimeEffectEnabled(runtimeRoot, false)
			end
		end)
	end

	if options.followInstance ~= nil and options.followDuration > 0 then
		local startedAt = os.clock()
		local followConnection: RBXScriptConnection?
		local destroyConnection: RBXScriptConnection?

		local function disconnect()
			if followConnection ~= nil then
				followConnection:Disconnect()
				followConnection = nil
			end
			if destroyConnection ~= nil then
				destroyConnection:Disconnect()
				destroyConnection = nil
			end
		end

		destroyConnection = runtimeRoot.Destroying:Connect(function()
			disconnect()
		end)

		followConnection = RunService.Heartbeat:Connect(function()
			if runtimeRoot.Parent == nil then
				disconnect()
				return
			end
			if os.clock() - startedAt >= options.followDuration then
				disconnect()
				return
			end

			local followBaseCFrame = VFXServiceUtils.GetInstanceWorldCFrame(options.followInstance)
			if followBaseCFrame ~= nil then
				runtimeRoot.CFrame = followBaseCFrame * options.offset
			end
		end)
	end

	local cleanupDelay = VFXServiceUtils.GetCleanupDelay(runtimeRoot, options)
	if cleanupDelay <= 0 then
		runtimeRoot:Destroy()
	else
		task.delay(cleanupDelay, function()
			if runtimeRoot.Parent ~= nil then
				runtimeRoot:Destroy()
			end
		end)
	end

	return runtimeRoot
end

function VFXServiceClient.PlayEffect(self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any): BasePart?
	return self:Play(effectSourceRaw, optionsRaw)
end

function VFXServiceClient.Emit(self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any): BasePart?
	return self:Play(effectSourceRaw, optionsRaw)
end

function VFXServiceClient.StopChannel(self: VFXServiceClient, channelNameRaw: any)
	local channelName = VFXServiceUtils.CoerceChannelName(channelNameRaw)
	if channelName == nil then
		return
	end

	local channelRuntimes = self.channelRuntimes :: { [string]: BasePart? }
	local runtimeRoot = channelRuntimes[channelName]
	if runtimeRoot == nil then
		return
	end

	channelRuntimes[channelName] = nil
	if runtimeRoot.Parent ~= nil then
		runtimeRoot:Destroy()
	end
end

function VFXServiceClient.StopAll(self: VFXServiceClient)
	local runtimes = {}
	for runtimeRoot in self.activeRuntimes do
		table.insert(runtimes, runtimeRoot)
	end

	for _, runtimeRoot in runtimes do
		if runtimeRoot.Parent ~= nil then
			runtimeRoot:Destroy()
		end
	end
end

function VFXServiceClient.Init(self: VFXServiceClient)
	bindPackets(self)
	self.janitor = Janitor.new()
	self.runtimeFolder = VFXServiceUtils.EnsureRuntimeFolder()
	self.activeRuntimes = {} :: { [BasePart]: boolean }
	self.channelRuntimes = {} :: { [string]: BasePart }

	self.janitor:GiveChore(function()
		self:StopAll()
	end)
end

function VFXServiceClient.Destroy(self: VFXServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end
type VFXServiceClient = typeof(VFXServiceClient) & {
	TrackRuntime: (self: VFXServiceClient, runtimeRoot: BasePart, channelName: string?) -> (),
	Play: (self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any) -> BasePart?,
	PlayEffect: (self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any) -> BasePart?,
	Emit: (self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any) -> BasePart?,
	StopChannel: (self: VFXServiceClient, channelNameRaw: any) -> (),
	StopAll: (self: VFXServiceClient) -> (),
	janitor: JanitorClass,
	runtimeFolder: Folder,
	activeRuntimes: { [BasePart]: boolean },
	channelRuntimes: { [string]: BasePart },
}

return VFXServiceClient :: VFXServiceClient
