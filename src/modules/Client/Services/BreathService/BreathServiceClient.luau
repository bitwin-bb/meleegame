--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local BreathServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BreathService.BreathServiceUtils)

type BreathServiceState = BreathServiceUtils.BreathServiceState

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local BreathServiceClient = {}

function BreathServiceClient:EnsureEffects()
	if self.colorCorrection == nil or self.colorCorrection.Parent == nil then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "BreathService_UnderwaterColor"
		effect.Enabled = false
		effect.Parent = Lighting
		self.colorCorrection = effect
	end
	if self.blur == nil or self.blur.Parent == nil then
		local effect = Instance.new("BlurEffect")
		effect.Name = "BreathService_UnderwaterBlur"
		effect.Enabled = false
		effect.Size = 0
		effect.Parent = Lighting
		self.blur = effect
	end
end

function BreathServiceClient:ApplyFeedback()
	self:ensureEffects()
	local state = self.state
	local correction = self.colorCorrection
	local blur = self.blur
	if correction == nil or blur == nil then
		return
	end

	local breathAlpha = 1 - math.clamp(state.breath / math.max(1, state.maxBreath), 0, 1)
	local underwaterAlpha = if state.isUnderwater then math.max(state.submersionRatio, 0.35) else 0
	local drowningBoost = if state.isDrowning then 0.4 else 0
	local pulse = self.eventPulse
	local strength = math.clamp(underwaterAlpha * 0.7 + breathAlpha * 0.35 + drowningBoost + pulse, 0, 1)

	local enabled = strength > 0.01
	correction.Enabled = enabled
	blur.Enabled = enabled
	if not enabled then
		blur.Size = 0
		return
	end

	correction.TintColor = Color3.fromRGB(
		math.floor(255 - 78 * strength),
		math.floor(255 - 36 * strength),
		math.floor(255 - 12 * strength)
	)
	correction.Brightness = -0.03 * strength
	correction.Contrast = 0.08 * strength
	correction.Saturation = -0.12 * strength
	blur.Size = 5 * strength + if state.isDrowning then 4 else 0
end

function BreathServiceClient:OnRenderStep(deltaTime: number)
	if self.eventPulse > 0 then
		self.eventPulse = math.max(0, self.eventPulse - deltaTime * 2.4)
	end
	self:applyFeedback()
end

function BreathServiceClient:ApplyState(stateRaw: any)
	self.state = BreathServiceUtils.createState(stateRaw, self.state)
	self.stateChanged:Fire(BreathServiceUtils.cloneState(self.state))
end

function BreathServiceClient:OnEvent(payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	if payload.eventType == BreathServiceUtils.EVENT_BREATH_DEPLETED then
		self.eventPulse = math.max(self.eventPulse, 0.55)
	end
	self.eventReceived:Fire(payload)
end

function BreathServiceClient:RequestSync()
	self.networker:fire(BreathServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function BreathServiceClient:GetState(): BreathServiceState
	return BreathServiceUtils.cloneState(self.state)
end

function BreathServiceClient:IsReady(): boolean
	return self.state.ready == true
end

function BreathServiceClient:Init()
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("BreathService", self)
	self.janitor = Janitor.new()
	self.state = BreathServiceUtils.createDefaultState()
	self.stateChanged = Signal.new()
	self.eventReceived = Signal.new()
	self.eventPulse = 0
	self.colorCorrection = nil :: ColorCorrectionEffect?
	self.blur = nil :: BlurEffect?

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
		self.eventReceived:Destroy()
	end)
	self.janitor:GiveChore(RunService.RenderStepped:Connect(function(deltaTime: number)
		self:onRenderStep(deltaTime)
	end))
	self.janitor:GiveChore(function()
		if self.colorCorrection ~= nil and self.colorCorrection.Parent ~= nil then
			self.colorCorrection:Destroy()
		end
		if self.blur ~= nil and self.blur.Parent ~= nil then
			self.blur:Destroy()
		end
	end)

	self:requestSync()
end

function BreathServiceClient:Destroy()
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

BreathServiceClient.ensureEffects = BreathServiceClient.EnsureEffects
BreathServiceClient.applyFeedback = BreathServiceClient.ApplyFeedback
BreathServiceClient.onRenderStep = BreathServiceClient.OnRenderStep
BreathServiceClient.applyState = BreathServiceClient.ApplyState
BreathServiceClient.onEvent = BreathServiceClient.OnEvent
BreathServiceClient.requestSync = BreathServiceClient.RequestSync
BreathServiceClient.getState = BreathServiceClient.GetState
BreathServiceClient.isReady = BreathServiceClient.IsReady
BreathServiceClient.init = BreathServiceClient.Init
BreathServiceClient.destroy = BreathServiceClient.Destroy

type BreathServiceClient = typeof(BreathServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	state: BreathServiceState,
	stateChanged: SignalObject,
	eventReceived: SignalObject,
	eventPulse: number,
	colorCorrection: ColorCorrectionEffect?,
	blur: BlurEffect?,
	getState: (self: BreathServiceClient) -> BreathServiceState,
	isReady: (self: BreathServiceClient) -> boolean,
}

return BreathServiceClient :: BreathServiceClient

