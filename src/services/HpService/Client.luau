--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local HpServiceUtils = require(ReplicatedStorage.Shared.Services.HpService.HpServiceUtils)
local PlayerDataServiceClient = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceClient)
local PlayerDataServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerDataService.PlayerDataServiceUtils)

type HpServiceState = HpServiceUtils.HpServiceState
type HeartState = HpServiceUtils.HeartState
type PlayerDataServiceState = PlayerDataServiceUtils.PlayerDataServiceState

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: HpServiceState) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: HpServiceState) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local HpServiceClient = {}

local DISABLE_HEALTH_UI_MAX_ATTEMPTS = 8
local DISABLE_HEALTH_UI_RETRY_DELAY = 0.2

local function disableDefaultHealthUi()
	local attempts = 0

	local function apply()
		attempts += 1
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)

		if attempts >= DISABLE_HEALTH_UI_MAX_ATTEMPTS then
			return
		end

		local getSuccess, isEnabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Health)
		end)
		if not getSuccess or isEnabled then
			task.delay(DISABLE_HEALTH_UI_RETRY_DELAY, apply)
		end
	end

	apply()
end

local function applyPersistedHpSnapshotFromPlayerData(self: HpServiceClient): boolean
	if PlayerDataServiceClient.isLoaded == nil or not PlayerDataServiceClient:isLoaded() then
		return false
	end

	local persistedHpRaw = PlayerDataServiceClient:getHpData(nil)
	local persistedHealth, persistedMaxHealth =
		HpServiceUtils.resolvePersistedHealthAndMaxHealth(persistedHpRaw, self.state.maxHealth)
	if persistedHealth == nil then
		return false
	end

	local nextState = HpServiceUtils.createState(persistedHealth, persistedMaxHealth, self.state.heartValue, self.state)
	nextState.delta = 0
	nextState.lastDamage = 0
	nextState.lastHeal = 0
	self.state = nextState
	self.isStateReady = true
	self.stateChanged:Fire(HpServiceUtils.cloneState(self.state))
	return true
end

function HpServiceClient.init(self: HpServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("HpService", self)
	self.janitor = Janitor.new()
	self.state = HpServiceUtils.createDefaultState()
	self.isStateReady = false
	self.stateChanged = Signal.new()
	self.hasReceivedServerState = false

	disableDefaultHealthUi()
	applyPersistedHpSnapshotFromPlayerData(self)

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function()
		disableDefaultHealthUi()
	end))
	if PlayerDataServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(PlayerDataServiceClient.stateChanged:Connect(function(nextState: PlayerDataServiceState)
			if PlayerDataServiceUtils.isLoadedState(nextState.loadState) then
				if not self.hasReceivedServerState then
					applyPersistedHpSnapshotFromPlayerData(self)
				end
				self:requestSync()
			end
		end))
	end

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	self.networker:fire("requestSync")
end

function HpServiceClient.applyState(self: HpServiceClient, stateRaw: any)
	self.state = HpServiceUtils.sanitizeState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.isStateReady = true
	self.stateChanged:Fire(HpServiceUtils.cloneState(self.state))
end

function HpServiceClient.requestSync(self: HpServiceClient)
	self.networker:fire("requestSync")
end

function HpServiceClient.getState(self: HpServiceClient): HpServiceState
	return HpServiceUtils.cloneState(self.state)
end

function HpServiceClient.getHearts(self: HpServiceClient): { HeartState }
	local state = self:getState()
	return state.hearts
end

function HpServiceClient.isReady(self: HpServiceClient): boolean
	return self.isStateReady == true
end

function HpServiceClient.destroy(self: HpServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end

export type HpServiceClient = typeof(HpServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	state: HpServiceState,
	hasReceivedServerState: boolean,
	isStateReady: boolean,
	stateChanged: SignalObject,
	isReady: (self: HpServiceClient) -> boolean,
}

return HpServiceClient :: HpServiceClient
