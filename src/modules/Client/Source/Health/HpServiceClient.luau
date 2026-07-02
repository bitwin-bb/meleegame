local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local HpServiceUtils = require("HpServiceUtils")
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local HpServicePackets = require("NetPacketsShared").HpService

local function sendPacket(methodName: string, ...: any)
	local packet = HpServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for HpService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = HpServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for HpService`)
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
	bindPacket(self, "applyState")
	bindPacket(self, "requestSync")
end

local PlayerDataServiceClient = require("PlayerDataServiceClient")
local PlayerDataServiceUtils = require("PlayerDataServiceUtils")
local Signal = require("Signal")

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
	if PlayerDataServiceClient.IsLoaded == nil or not PlayerDataServiceClient:IsLoaded() then
		return false
	end

	local persistedHpRaw = PlayerDataServiceClient:GetHpData(nil)
	local persistedHealth, persistedMaxHealth =
		HpServiceUtils.GetPersistedHealthAndMaxHealth(persistedHpRaw, self.state.maxHealth)
	if persistedHealth == nil then
		return false
	end

	local nextState = HpServiceUtils.CreateState(persistedHealth, persistedMaxHealth, self.state.heartValue, self.state)
	nextState.delta = 0
	nextState.lastDamage = 0
	nextState.lastHeal = 0
	self.state = nextState
	self.isStateReady = true
	self.stateChanged:Fire(HpServiceUtils.CloneState(self.state))
	return true
end

function HpServiceClient.Init(self: HpServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = HpServiceUtils.CreateDefaultState()
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
			if PlayerDataServiceUtils.IsLoadedState(nextState.loadState) then
				if not self.hasReceivedServerState then
					applyPersistedHpSnapshotFromPlayerData(self)
				end
				self:RequestSync()
			end
		end))
	end

	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)

	sendPacket("requestSync")
end

function HpServiceClient.ApplyState(self: HpServiceClient, stateRaw: any)
	self.state = HpServiceUtils.CoerceState(stateRaw, self.state)
	self.hasReceivedServerState = true
	self.isStateReady = true
	self.stateChanged:Fire(HpServiceUtils.CloneState(self.state))
end

function HpServiceClient.RequestSync(self: HpServiceClient)
	sendPacket("requestSync")
end

function HpServiceClient.GetState(self: HpServiceClient): HpServiceState
	return HpServiceUtils.CloneState(self.state)
end

function HpServiceClient.GetHearts(self: HpServiceClient): { HeartState }
	local state = self:GetState()
	return state.hearts
end

function HpServiceClient.IsReady(self: HpServiceClient): boolean
	return self.isStateReady == true
end

function HpServiceClient.Destroy(self: HpServiceClient)
	if self.janitor then
		self.janitor:Destroy()
	end
end
export type HpServiceClient = typeof(HpServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass,
	state: HpServiceState,
	hasReceivedServerState: boolean,
	isStateReady: boolean,
	stateChanged: SignalObject,
	isReady: (self: HpServiceClient) -> boolean,
}

return HpServiceClient :: HpServiceClient
