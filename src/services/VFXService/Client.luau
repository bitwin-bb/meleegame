--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local VFXServiceUtils = require(ReplicatedStorage.Shared.Services.VFXService.VFXServiceUtils)

type VFXPlaybackOptions = VFXServiceUtils.VFXPlaybackOptions

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local VFXServiceClient = {}

function VFXServiceClient.trackRuntime(self: VFXServiceClient, runtimeRoot: BasePart, channelName: string?)
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

function VFXServiceClient.play(self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any): BasePart?
	local effectTemplate = VFXServiceUtils.resolveEffectTemplate(effectSourceRaw)
	if effectTemplate == nil then
		return nil
	end

	local options: VFXPlaybackOptions = VFXServiceUtils.sanitizePlaybackOptions(optionsRaw)
	if options.channel ~= nil and options.replaceChannel then
		self:stopChannel(options.channel)
	end

	local runtimeParent = self.runtimeFolder
	if options.parent ~= nil and options.parent.Parent ~= nil then
		runtimeParent = options.parent
	end

	local runtimeRoot = VFXServiceUtils.createRuntimeEffect(effectTemplate, runtimeParent)
	if runtimeRoot == nil then
		return nil
	end

	local playbackCFrame = VFXServiceUtils.resolvePlaybackCFrame(options)
	if playbackCFrame ~= nil then
		runtimeRoot.CFrame = playbackCFrame
	end

	if options.channel ~= nil then
		self.channelRuntimes[options.channel] = runtimeRoot
	end
	self:trackRuntime(runtimeRoot, options.channel)

	VFXServiceUtils.setRuntimeEffectEnabled(runtimeRoot, true)
	if options.emitCount ~= nil then
		VFXServiceUtils.emitRuntimeParticles(runtimeRoot, options.emitCount)
	end

	local enabledDuration = math.max(0, options.enabledDuration)
	if enabledDuration <= 0 then
		VFXServiceUtils.setRuntimeEffectEnabled(runtimeRoot, false)
	else
		task.delay(enabledDuration, function()
			if runtimeRoot.Parent ~= nil then
				VFXServiceUtils.setRuntimeEffectEnabled(runtimeRoot, false)
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

			local followBaseCFrame = VFXServiceUtils.resolveInstanceWorldCFrame(options.followInstance)
			if followBaseCFrame ~= nil then
				runtimeRoot.CFrame = followBaseCFrame * options.offset
			end
		end)
	end

	local cleanupDelay = VFXServiceUtils.resolveCleanupDelay(runtimeRoot, options)
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

function VFXServiceClient.playEffect(self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any): BasePart?
	return self:play(effectSourceRaw, optionsRaw)
end

function VFXServiceClient.emit(self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any): BasePart?
	return self:play(effectSourceRaw, optionsRaw)
end

function VFXServiceClient.stopChannel(self: VFXServiceClient, channelNameRaw: any)
	local channelName = VFXServiceUtils.sanitizeChannelName(channelNameRaw)
	if channelName == nil then
		return
	end

	local runtimeRoot = self.channelRuntimes[channelName]
	if runtimeRoot == nil then
		return
	end

	self.channelRuntimes[channelName] = nil
	if runtimeRoot.Parent ~= nil then
		runtimeRoot:Destroy()
	end
end

function VFXServiceClient.stopAll(self: VFXServiceClient)
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

function VFXServiceClient.init(self: VFXServiceClient)
	self.networker = Networker.client.new("VFXService", self)
	self.janitor = Janitor.new()
	self.runtimeFolder = VFXServiceUtils.ensureRuntimeFolder()
	self.activeRuntimes = {} :: { [BasePart]: boolean }
	self.channelRuntimes = {} :: { [string]: BasePart }

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self:stopAll()
	end)
end

function VFXServiceClient.destroy(self: VFXServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

type VFXServiceClient = typeof(VFXServiceClient) & {
	trackRuntime: (self: VFXServiceClient, runtimeRoot: BasePart, channelName: string?) -> (),
	play: (self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any) -> BasePart?,
	playEffect: (self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any) -> BasePart?,
	emit: (self: VFXServiceClient, effectSourceRaw: any, optionsRaw: any) -> BasePart?,
	stopChannel: (self: VFXServiceClient, channelNameRaw: any) -> (),
	stopAll: (self: VFXServiceClient) -> (),
	networker: Networker.Client,
	janitor: JanitorClass,
	runtimeFolder: Folder,
	activeRuntimes: { [BasePart]: boolean },
	channelRuntimes: { [string]: BasePart },
}

return VFXServiceClient :: VFXServiceClient
