--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local ServiceSync = require(ReplicatedStorage.UI.core.utils.ServiceSync)
local infoPlayerSlice = require(ReplicatedStorage.UI.features.infoPlayer.state.infoPlayerSlice)
local BossServiceClient = require(ReplicatedStorage.Shared.Services.BossService.BossServiceClient)
local InventoryServiceClient = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceClient)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local HpServiceClient = require(ReplicatedStorage.Shared.Services.HpService.HpServiceClient)
local HpServiceUtils = require(ReplicatedStorage.Shared.Services.HpService.HpServiceUtils)
local NpcServiceClient = require(ReplicatedStorage.Shared.Services.NpcService.NpcServiceClient)

type InfoPlayerState = infoPlayerSlice.InfoPlayerState
type InventoryState = InventoryServiceUtils.InventoryState
type HpServiceState = HpServiceUtils.HpServiceState
type NpcServiceClientState = {
	byId: { [string]: { hp: number } },
	orderedIds: { string },
	updatedAt: number,
}

type BossServiceClientState = {
	byId: { [string]: { hp: number } },
	orderedIds: { string },
	updatedAt: number,
}

local infoPlayerThunks = {}

local DAMAGE_DEALT_INPUT_WINDOW_SECONDS = 1.35

local runtime = {
	started = false,
	localPlayer = nil :: Player?,
	inventoryStateChangedConnection = nil :: RBXScriptConnection?,
	hpStateChangedConnection = nil :: RBXScriptConnection?,
	npcStateChangedConnection = nil :: RBXScriptConnection?,
	bossStateChangedConnection = nil :: RBXScriptConnection?,
	inputBeganConnection = nil :: RBXScriptConnection?,
	previousInventoryCounts = {} :: { [string]: number },
	previousHp = nil :: number?,
	previousHpUpdatedAt = nil :: number?,
	previousNpcHpById = {} :: { [string]: number },
	previousBossHpById = {} :: { [string]: number },
	hasPrimedInventory = false,
	hasPrimedHp = false,
	hasPrimedNpc = false,
	hasPrimedBoss = false,
	lastCombatIntentAt = -math.huge,
}

local function sanitizeCount(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.max(0, math.floor(valueRaw + 0.5))
end

local function buildInventoryCounts(stateRaw: any): { [string]: number }
	local counts: { [string]: number } = {}
	if typeof(stateRaw) ~= "table" then
		return counts
	end
	local slotsRaw = (stateRaw :: any).slots
	if typeof(slotsRaw) ~= "table" then
		return counts
	end

	for _, slotRaw in slotsRaw do
		if typeof(slotRaw) ~= "table" then
			continue
		end
		local stackRaw = (slotRaw :: any).stack
		if typeof(stackRaw) ~= "table" then
			continue
		end
		local itemIdRaw = (stackRaw :: any).itemId
		local amountRaw = (stackRaw :: any).amount
		if typeof(itemIdRaw) ~= "string" or itemIdRaw == "" then
			continue
		end
		local amount = sanitizeCount(amountRaw)
		if amount <= 0 then
			continue
		end
		counts[itemIdRaw] = (counts[itemIdRaw] or 0) + amount
	end

	return counts
end

local function buildNpcHpMap(stateRaw: any): { [string]: number }
	local output: { [string]: number } = {}
	if typeof(stateRaw) ~= "table" then
		return output
	end
	local byIdRaw = (stateRaw :: any).byId
	if typeof(byIdRaw) ~= "table" then
		return output
	end

	for runtimeIdRaw, snapshotRaw in byIdRaw do
		if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
			continue
		end
		if typeof(snapshotRaw) ~= "table" then
			continue
		end
		local hp = sanitizeCount((snapshotRaw :: any).hp)
		output[runtimeIdRaw] = hp
	end

	return output
end

local function buildBossHpMap(stateRaw: any): { [string]: number }
	local output: { [string]: number } = {}
	if typeof(stateRaw) ~= "table" then
		return output
	end
	local byIdRaw = (stateRaw :: any).byId
	if typeof(byIdRaw) ~= "table" then
		return output
	end

	for runtimeIdRaw, snapshotRaw in byIdRaw do
		if typeof(runtimeIdRaw) ~= "string" or runtimeIdRaw == "" then
			continue
		end
		if typeof(snapshotRaw) ~= "table" then
			continue
		end
		local hp = sanitizeCount((snapshotRaw :: any).hp)
		output[runtimeIdRaw] = hp
	end

	return output
end

local function isCombatIntentInput(inputObject: InputObject): boolean
	if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		return true
	end
	if inputObject.UserInputType == Enum.UserInputType.Touch then
		return true
	end
	if inputObject.KeyCode == Enum.KeyCode.ButtonR2 then
		return true
	end
	return false
end

local function onInventoryStateChanged(nextStateRaw: any)
	local fallback = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	local nextState = InventoryServiceUtils.sanitizeState(nextStateRaw, fallback)
	if not InventoryServiceUtils.isLoadedState(nextState.loadState) then
		runtime.previousInventoryCounts = {}
		runtime.hasPrimedInventory = false
		return
	end

	local nextCounts = buildInventoryCounts(nextState)
	if not runtime.hasPrimedInventory then
		runtime.hasPrimedInventory = true
		runtime.previousInventoryCounts = nextCounts
		return
	end

	for itemId, nextAmount in nextCounts do
		local previousAmount = runtime.previousInventoryCounts[itemId] or 0
		local delta = nextAmount - previousAmount
		if delta > 0 then
			infoPlayerSlice.pushPickup(itemId, delta)
		end
	end

	runtime.previousInventoryCounts = nextCounts
end

local function onHpStateChanged(nextStateRaw: any)
	local fallback = HpServiceUtils.createDefaultState()
	local nextState = HpServiceUtils.sanitizeState(nextStateRaw, fallback)

	if not runtime.hasPrimedHp then
		runtime.hasPrimedHp = true
		runtime.previousHp = nextState.health
		runtime.previousHpUpdatedAt = nextState.updatedAt
		return
	end

	local previousHp = if runtime.previousHp ~= nil then runtime.previousHp else nextState.health
	if nextState.isAlive == false or nextState.health <= 0 then
		runtime.previousHp = nextState.health
		runtime.previousHpUpdatedAt = nextState.updatedAt
		return
	end

	local deltaDamage = math.max(0, previousHp - nextState.health)
	local previousUpdatedAt = if runtime.previousHpUpdatedAt ~= nil then runtime.previousHpUpdatedAt else -math.huge
	local explicitDamage = if nextState.updatedAt > previousUpdatedAt then math.max(0, nextState.lastDamage) else 0
	local damageTaken = math.max(deltaDamage, explicitDamage)
	if damageTaken > 0 then
		infoPlayerSlice.pushDamageTaken(damageTaken)
	end

	runtime.previousHp = nextState.health
	runtime.previousHpUpdatedAt = nextState.updatedAt
end

local function onNpcStateChanged(nextStateRaw: any)
	local nextState = if typeof(nextStateRaw) == "table" then (nextStateRaw :: NpcServiceClientState) else nil
	if nextState == nil then
		return
	end

	local nextHpById = buildNpcHpMap(nextState)
	if not runtime.hasPrimedNpc then
		runtime.hasPrimedNpc = true
		runtime.previousNpcHpById = nextHpById
		return
	end

	local totalDealt = 0
	for runtimeId, nextHp in nextHpById do
		local previousHp = runtime.previousNpcHpById[runtimeId]
		if previousHp ~= nil and previousHp > nextHp then
			totalDealt += math.max(0, previousHp - nextHp)
		end
	end

	if totalDealt > 0 then
		local now = os.clock()
		if now - runtime.lastCombatIntentAt <= DAMAGE_DEALT_INPUT_WINDOW_SECONDS then
			infoPlayerSlice.pushDamageDealt(totalDealt)
		end
	end

	runtime.previousNpcHpById = nextHpById
end

local function onBossStateChanged(nextStateRaw: any)
	local nextState = if typeof(nextStateRaw) == "table" then (nextStateRaw :: BossServiceClientState) else nil
	if nextState == nil then
		return
	end

	local nextHpById = buildBossHpMap(nextState)
	if not runtime.hasPrimedBoss then
		runtime.hasPrimedBoss = true
		runtime.previousBossHpById = nextHpById
		return
	end

	local totalDealt = 0
	for runtimeId, nextHp in nextHpById do
		local previousHp = runtime.previousBossHpById[runtimeId]
		if previousHp ~= nil and previousHp > nextHp then
			totalDealt += math.max(0, previousHp - nextHp)
		end
	end

	if totalDealt > 0 then
		local now = os.clock()
		if now - runtime.lastCombatIntentAt <= DAMAGE_DEALT_INPUT_WINDOW_SECONDS then
			infoPlayerSlice.pushDamageDealt(totalDealt)
		end
	end

	runtime.previousBossHpById = nextHpById
end

local function syncFromServices()
	if InventoryServiceClient.getState ~= nil then
		local inventoryOk, inventoryStateOrError = pcall(function()
			return InventoryServiceClient:getState()
		end)
		if inventoryOk then
			onInventoryStateChanged(inventoryStateOrError)
		end
	end

	if HpServiceClient.getState ~= nil then
		local shouldReadHp = true
		if HpServiceClient.isReady ~= nil then
			local readyOk, isReady = pcall(function()
				return HpServiceClient:isReady()
			end)
			if not readyOk or not isReady then
				shouldReadHp = false
			end
		end

		if shouldReadHp then
			local hpOk, hpStateOrError = pcall(function()
				return HpServiceClient:getState()
			end)
			if hpOk then
				onHpStateChanged(hpStateOrError)
			end
		end
	end

	if NpcServiceClient.getState ~= nil then
		local npcOk, npcStateOrError = pcall(function()
			return NpcServiceClient:getState()
		end)
		if npcOk then
			onNpcStateChanged(npcStateOrError)
		end
	end

	if BossServiceClient.getState ~= nil then
		local bossOk, bossStateOrError = pcall(function()
			return BossServiceClient:getState()
		end)
		if bossOk then
			onBossStateChanged(bossStateOrError)
		end
	end
end

function infoPlayerThunks.start(): () -> ()
	if runtime.started then
		return infoPlayerThunks.stop
	end

	runtime.started = true
	runtime.localPlayer = Players.LocalPlayer
	runtime.previousInventoryCounts = {}
	runtime.previousNpcHpById = {}
	runtime.previousBossHpById = {}
	runtime.previousHp = nil
	runtime.previousHpUpdatedAt = nil
	runtime.hasPrimedInventory = false
	runtime.hasPrimedHp = false
	runtime.hasPrimedNpc = false
	runtime.hasPrimedBoss = false
	runtime.lastCombatIntentAt = -math.huge

	runtime.inventoryStateChangedConnection =
		ServiceSync.connectStateChanged(InventoryServiceClient, function(nextState: InventoryState)
			onInventoryStateChanged(nextState)
		end)

	runtime.hpStateChangedConnection = ServiceSync.connectStateChanged(HpServiceClient, function(nextState: HpServiceState)
		onHpStateChanged(nextState)
	end)

	runtime.npcStateChangedConnection = ServiceSync.connectStateChanged(NpcServiceClient, function(nextState: NpcServiceClientState)
		onNpcStateChanged(nextState)
	end)

	runtime.bossStateChangedConnection =
		ServiceSync.connectStateChanged(BossServiceClient, function(nextState: BossServiceClientState)
			onBossStateChanged(nextState)
		end)

	runtime.inputBeganConnection = UserInputService.InputBegan:Connect(function(inputObject: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if isCombatIntentInput(inputObject) then
			runtime.lastCombatIntentAt = os.clock()
		end
	end)

	syncFromServices()

	ServiceSync.requestSyncMany({
		InventoryServiceClient,
		HpServiceClient,
		NpcServiceClient,
		BossServiceClient,
	})

	return infoPlayerThunks.stop
end

function infoPlayerThunks.stop()
	ConnectionUtils.disconnectMany({
		runtime.inventoryStateChangedConnection,
		runtime.hpStateChangedConnection,
		runtime.npcStateChangedConnection,
		runtime.bossStateChangedConnection,
		runtime.inputBeganConnection,
	})
	runtime.inventoryStateChangedConnection = nil
	runtime.hpStateChangedConnection = nil
	runtime.npcStateChangedConnection = nil
	runtime.bossStateChangedConnection = nil
	runtime.inputBeganConnection = nil

	runtime.started = false
	runtime.localPlayer = nil
	runtime.previousInventoryCounts = {}
	runtime.previousNpcHpById = {}
	runtime.previousBossHpById = {}
	runtime.previousHp = nil
	runtime.previousHpUpdatedAt = nil
	runtime.hasPrimedInventory = false
	runtime.hasPrimedHp = false
	runtime.hasPrimedNpc = false
	runtime.hasPrimedBoss = false
	runtime.lastCombatIntentAt = -math.huge
	infoPlayerSlice.resetInfoPlayerState()
end

function infoPlayerThunks.getInfoPlayerState(): InfoPlayerState
	return infoPlayerSlice.getInfoPlayerState()
end

return infoPlayerThunks
