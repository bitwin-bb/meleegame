--!strict
local RunService = game:GetService("RunService")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local ServiceSync = require(script:FindFirstAncestor("game").Client.UI.core.utils.ServiceSync)
local bindingSlice = require(script:FindFirstAncestor("game").Client.UI.features.bindingHint.state.bindingSlice)
local itemThunks = require(script:FindFirstAncestor("game").Client.UI.features.item.state.itemThunks)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local MiningPower = require(script:FindFirstAncestor("game").Shared.Modules.Math.MiningPower)
local BuildServiceClient = require(script:FindFirstAncestor("game").Client.Services.BuildServiceClient)
local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildServiceUtils)
local InventoryServiceClient = require(script:FindFirstAncestor("game").Client.Services.InventoryServiceClient)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryServiceUtils)
local MagicServiceClient = require(script:FindFirstAncestor("game").Client.Services.MagicServiceClient)
local MagicServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.MagicServiceUtils)
local MeleeServiceClient = require(script:FindFirstAncestor("game").Client.Services.MeleeServiceClient)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local PlayerServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlayerServiceClient)

type BindingHintEntry = bindingSlice.BindingHintEntry
type BindingHintState = bindingSlice.BindingHintState
type InventoryState = InventoryServiceUtils.InventoryState

type HintDescriptor = {
	id: string,
	actionName: string,
	label: string,
	detail: string?,
	enabled: boolean,
	priority: number,
}

type PlatformSnapshot = {
	platform: string,
	deviceClass: string,
}

local bindingThunks = {}

local REFRESH_INTERVAL_SECONDS = 0.05

local runtime = {
	started = false,
	lastRefreshAt = -math.huge,
	renderConnection = nil :: RBXScriptConnection?,
	inventoryStateChangedConnection = nil :: RBXScriptConnection?,
	buildStateChangedConnection = nil :: RBXScriptConnection?,
	buildBreakProgressConnection = nil :: RBXScriptConnection?,
	magicStateChangedConnection = nil :: RBXScriptConnection?,
	platformDisconnect = nil :: (() -> ())?,
}

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
end

local function readPlatformSnapshot(): PlatformSnapshot
	local fallback: PlatformSnapshot = {
		platform = "KeyboardMouse",
		deviceClass = "Desktop",
	}

	if not PlatformServiceClient:isReady() then
		return fallback
	end

	local ok, stateOrError = pcall(function()
		return PlatformServiceClient:getState()
	end)
	if not ok or typeof(stateOrError) ~= "table" then
		return fallback
	end

	local state = stateOrError :: { [string]: any }
	local platform = trim(state.platform)
	local deviceClass = trim(state.deviceClass)
	return {
		platform = if platform ~= "" then platform else fallback.platform,
		deviceClass = if deviceClass ~= "" then deviceClass else fallback.deviceClass,
	}
end

local function readInventoryState(): InventoryState
	local fallback = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	local ok, stateOrError = pcall(function()
		return InventoryServiceClient:getState()
	end)
	if ok then
		return InventoryServiceUtils.sanitizeState(stateOrError, fallback)
	end
	return InventoryServiceUtils.sanitizeState(InventoryServiceClient.state, fallback)
end

local function readMagicState(): MagicServiceUtils.ReplicatedState
	local fallback = MagicServiceUtils.sanitizeReplicatedState(nil, {
		mana = MagicServiceUtils.DEFAULT_MAX_MANA,
		maxMana = MagicServiceUtils.DEFAULT_MAX_MANA,
		regenPerSecond = MagicServiceUtils.DEFAULT_MANA_REGEN,
		equippedWeaponId = nil,
		equippedSlot = nil,
		cooldowns = {},
		updatedAt = os.clock(),
	})
	local ok, stateOrError = pcall(function()
		return MagicServiceClient:getState()
	end)
	if ok then
		return MagicServiceUtils.sanitizeReplicatedState(stateOrError, fallback)
	end
	return MagicServiceUtils.sanitizeReplicatedState(MagicServiceClient.state, fallback)
end

local function getMeleeServiceClient(): any
	if typeof(MeleeServiceClient) ~= "table" then
		return nil
	end

	return MeleeServiceClient
end

local function readSelectedStack(inventoryState: InventoryState): InventoryServiceUtils.InventoryItemStack?
	local selectedSlot = inventoryState.selectedSlot
	if selectedSlot == nil then
		return nil
	end
	return InventoryServiceUtils.getStack(inventoryState, selectedSlot)
end

local function resolveDisplayNameFromStack(stackRaw: any, fallbackRaw: any?): string
	local fallback = trim(fallbackRaw)
	if typeof(stackRaw) == "table" then
		local ok, displayNameOrError = pcall(function()
			return itemThunks.resolveDisplayNameForStack(stackRaw)
		end)
		if ok and typeof(displayNameOrError) == "string" and trim(displayNameOrError) ~= "" then
			return trim(displayNameOrError)
		end
	end
	if fallback ~= "" then
		return fallback
	end
	return "Action"
end

local function resolveDeployableItemId(stackRaw: any): string?
	if typeof(stackRaw) ~= "table" then
		return nil
	end
	local itemId = ItemRegistry.resolveCanonicalItemId((stackRaw :: { [string]: any }).itemId)
	if itemId == nil then
		return nil
	end
	local definition = ItemRegistry.resolveDefinition(itemId)
	if typeof(definition) ~= "table" then
		return nil
	end
	local deployable = (definition :: { [string]: any }).deployable
	if typeof(deployable) ~= "table" then
		return nil
	end
	local stationTag = trim((deployable :: { [string]: any }).stationTag)
	if stationTag == "" then
		return nil
	end
	return itemId
end

local function resolvePromptData(actionName: string): (string?, string?)
	local ok, promptOrError = pcall(function()
		return PlatformServiceClient:getPromptForAction(actionName)
	end)
	if not ok or typeof(promptOrError) ~= "table" then
		return nil, nil
	end

	local prompt = promptOrError :: { [string]: any }
	local promptText = trim(prompt.text)
	local promptIcon = trim(prompt.icon)
	return if promptText ~= "" then promptText else nil, if promptIcon ~= "" then promptIcon else nil
end

local function pushHint(hints: { BindingHintEntry }, descriptor: HintDescriptor): boolean
	local promptText, promptIcon = resolvePromptData(descriptor.actionName)
	if promptText == nil and promptIcon == nil then
		return false
	end

	hints[#hints + 1] = {
		id = descriptor.id,
		actionName = descriptor.actionName,
		label = descriptor.label,
		detail = descriptor.detail,
		promptText = promptText,
		promptIcon = promptIcon,
		enabled = descriptor.enabled,
		priority = descriptor.priority,
	}
	return true
end

local function formatPlaceFailureReason(reasonRaw: any): string
	local reason = trim(reasonRaw)
	if reason == "missing_support" then
		return "Need Support"
	end
	if reason == "occupied" then
		return "Blocked"
	end
	if reason == "tile_out_of_bounds" then
		return "Out of Bounds"
	end
	if reason == "invalid_tile_coordinate_or_id" then
		return "No Target"
	end
	return "Cannot Place"
end

local function formatTileBreakFailureReason(reasonRaw: any): string
	local reason = trim(reasonRaw)
	if reason == "tile_requires_pickaxe" then
		return "Need Pickaxe"
	end
	if reason == "insufficient_pickaxe_power" then
		return "Need Better Pickaxe"
	end
	if reason == "air" then
		return "No Target"
	end
	return "Cannot Mine"
end

local function formatTreeBreakFailureReason(reasonRaw: any): string
	local reason = trim(reasonRaw)
	if reason == "tree_requires_axe" then
		return "Need Axe"
	end
	if reason == "insufficient_axe_power" then
		return "Need Better Axe"
	end
	return "Cannot Chop"
end

local function resolveMiningToolContext(inventoryState: InventoryState)
	local ok, toolContextOrError = pcall(function()
		return MiningPower.resolveSelectedToolContextFromInventoryState(inventoryState)
	end)
	if ok and typeof(toolContextOrError) == "table" then
		return toolContextOrError :: { [string]: any }
	end
	return nil
end

local function tryBuildPlaceHint(hints: { BindingHintEntry }, selectedStack: any): boolean
	local ok, activePlaceSourceOrError = pcall(function()
		return BuildServiceClient:resolveActivePlaceSource()
	end)
	if not ok or typeof(activePlaceSourceOrError) ~= "table" then
		return false
	end

	local activePlaceSource = activePlaceSourceOrError :: { [string]: any }
	local config = activePlaceSource.config
	if typeof(config) ~= "table" then
		return false
	end

	local itemName = resolveDisplayNameFromStack(selectedStack, config.itemId)
	local cursorTileX = BuildServiceClient.cursorTileX
	local cursorTileY = BuildServiceClient.cursorTileY
	local canPlace = false
	local detail = "No Target"
	if typeof(cursorTileX) == "number" and typeof(cursorTileY) == "number" then
		local placeOk, canPlaceOrError, reasonOrError = pcall(function()
			return BuildServiceClient:canPlaceAt(cursorTileX, cursorTileY, config.tileId)
		end)
		if placeOk then
			canPlace = canPlaceOrError == true
			detail = if canPlace then "" else formatPlaceFailureReason(reasonOrError)
		else
			detail = "Cannot Place"
		end
	end

	return pushHint(hints, {
		id = "build_place",
		actionName = PlatformServiceClient.ACTIONS.BUILD_PRIMARY,
		label = ("Place %s"):format(itemName),
		detail = if canPlace then nil else detail,
		enabled = canPlace,
		priority = 100,
	})
end

local function tryBuildDeployableHint(hints: { BindingHintEntry }, selectedStack: any): boolean
	local deployableItemId = resolveDeployableItemId(selectedStack)
	if deployableItemId == nil then
		return false
	end

	local cursorTileX = BuildServiceClient.cursorTileX
	local cursorTileY = BuildServiceClient.cursorTileY
	local canPlace = typeof(cursorTileX) == "number" and typeof(cursorTileY) == "number"
	return pushHint(hints, {
		id = "inventory_place_deployable",
		actionName = PlatformServiceClient.ACTIONS.PLACE_DEPLOYABLE,
		label = ("Place %s"):format(resolveDisplayNameFromStack(selectedStack, deployableItemId)),
		detail = if canPlace then nil else "No Target",
		enabled = canPlace,
		priority = 110,
	})
end

local function tryBuildBreakHint(hints: { BindingHintEntry }, inventoryState: InventoryState): boolean
	local cursorTileX = BuildServiceClient.cursorTileX
	local cursorTileY = BuildServiceClient.cursorTileY
	if typeof(cursorTileX) ~= "number" or typeof(cursorTileY) ~= "number" then
		return false
	end

	local isBreakable = false
	local breakableOk, breakableOrError = pcall(function()
		return BuildServiceClient:isBreakableTarget(cursorTileX, cursorTileY)
	end)
	if breakableOk then
		isBreakable = breakableOrError == true
	end
	if not isBreakable then
		return false
	end

	local toolContext = resolveMiningToolContext(inventoryState)
	local toolType = if toolContext ~= nil then toolContext.toolType else nil
	local toolPower = if toolContext ~= nil then toolContext.toolPower else 0

	local treeOk, treeOrError = pcall(function()
		return BuildServiceClient:resolveTreeHitAtTile(cursorTileX, cursorTileY)
	end)
	local treeHit = if treeOk and typeof(treeOrError) == "table" then treeOrError else nil
	if treeHit ~= nil then
		local canBreak, reason = BuildServiceUtils.canBreakTree(treeHit, toolType, toolPower)
		return pushHint(hints, {
			id = "build_break_tree",
			actionName = PlatformServiceClient.ACTIONS.BUILD_PRIMARY,
			label = "Chop Tree",
			detail = if canBreak then nil else formatTreeBreakFailureReason(reason),
			enabled = canBreak,
			priority = 120,
		})
	end

	local tileId = BuildServiceUtils.AIR_TILE_ID
	local tileOk, tileOrError = pcall(function()
		return BuildServiceClient:getTileAt(cursorTileX, cursorTileY, false)
	end)
	if tileOk and typeof(tileOrError) == "number" then
		tileId = tileOrError
	end
	if tileId == BuildServiceUtils.AIR_TILE_ID then
		return false
	end

	local tileRule = BuildServiceUtils.getTileRule(tileId)
	local canBreak, reason = BuildServiceUtils.canBreakTile(tileId, toolType, toolPower)
	return pushHint(hints, {
		id = "build_break_tile",
		actionName = PlatformServiceClient.ACTIONS.BUILD_PRIMARY,
		label = ("Mine %s"):format(trim(tileRule.name) ~= "" and tileRule.name or "Block"),
		detail = if canBreak then nil else formatTileBreakFailureReason(reason),
		enabled = canBreak,
		priority = 120,
	})
end

local function appendBuildHints(hints: { BindingHintEntry }, inventoryState: InventoryState, selectedStack: any): string?
	if tryBuildPlaceHint(hints, selectedStack) then
		return "Place"
	end
	if tryBuildDeployableHint(hints, selectedStack) then
		return "Deployable"
	end
	if tryBuildBreakHint(hints, inventoryState) then
		return "Break"
	end
	return nil
end

local function appendMeleeHint(hints: { BindingHintEntry }, contextualBuildKind: string?)
	local meleeServiceClient = getMeleeServiceClient()
	if meleeServiceClient == nil then
		return
	end

	local weaponConfig = meleeServiceClient.equippedWeaponConfig
	if typeof(weaponConfig) ~= "table" then
		return
	end

	local usingHarvestTool = false
	local axeOk, isAxe = pcall(function()
		return meleeServiceClient:isEquippedAxe()
	end)
	local pickaxeOk, isPickaxe = pcall(function()
		return meleeServiceClient:isEquippedPickaxe()
	end)
	if axeOk and isAxe == true then
		usingHarvestTool = true
	end
	if pickaxeOk and isPickaxe == true then
		usingHarvestTool = true
	end

	if contextualBuildKind ~= nil and usingHarvestTool then
		return
	end

	local blocked = true
	local blockedOk, blockedOrError = pcall(function()
		return meleeServiceClient:isAttackBlocked()
	end)
	if blockedOk then
		blocked = blockedOrError == true
	end

	pushHint(hints, {
		id = "melee_attack",
		actionName = PlatformServiceClient.ACTIONS.MELEE_ATTACK,
		label = "Attack",
		detail = if blocked then "Unavailable" else nil,
		enabled = not blocked,
		priority = 200,
	})
end

local function resolveMagicWeaponConfig(): MagicServiceUtils.WeaponRuntimeConfig?
	local equippedTool = MagicServiceClient.equippedTool
	if typeof(equippedTool) ~= "Instance" then
		return nil
	end

	local ok, configOrError = pcall(function()
		return MagicServiceUtils.buildWeaponRuntimeConfig(equippedTool)
	end)
	if ok and typeof(configOrError) == "table" then
		return configOrError :: MagicServiceUtils.WeaponRuntimeConfig
	end
	return nil
end

local function appendMagicHint(hints: { BindingHintEntry })
	local config = resolveMagicWeaponConfig()
	if config == nil then
		return
	end

	local magicState = readMagicState()
	local equippedWeaponId = trim(config.itemId)
	local cooldowns = magicState.cooldowns
	local cooldownRemaining = 0
	if equippedWeaponId ~= "" then
		cooldownRemaining = math.max(
			cooldowns[equippedWeaponId] or 0,
			cooldowns[string.lower(equippedWeaponId)] or 0
		)
	end

	local enabled = true
	local detail = nil :: string?
	if cooldownRemaining > 0.05 then
		enabled = false
		detail = string.format("%.1fs Cooldown", cooldownRemaining)
	elseif magicState.mana < config.manaCost then
		enabled = false
		detail = ("Need %d Mana"):format(math.ceil(config.manaCost))
	end

	pushHint(hints, {
		id = "magic_cast",
		actionName = PlatformServiceClient.ACTIONS.MAGIC_CAST,
		label = "Cast",
		detail = detail,
		enabled = enabled,
		priority = 210,
	})
end

local function appendJumpHint(hints: { BindingHintEntry })
	if PlayerServiceClient.movementLocked == true then
		return
	end

	if PlayerServiceClient.flyEnabled == true then
		return
	end

	pushHint(hints, {
		id = "jump",
		actionName = PlatformServiceClient.ACTIONS.JUMP,
		label = "Jump",
		detail = nil,
		enabled = true,
		priority = 305,
	})
end

local function computeBindingState(): BindingHintState
	local platformSnapshot = readPlatformSnapshot()
	local inventoryState = readInventoryState()
	local selectedStack = readSelectedStack(inventoryState)
	local hints: { BindingHintEntry } = {}

	local contextualBuildKind = appendBuildHints(hints, inventoryState, selectedStack)
	appendMeleeHint(hints, contextualBuildKind)
	appendMagicHint(hints)
	appendJumpHint(hints)

	return bindingSlice.setBindingState({
		started = true,
		visible = #hints > 0,
		platform = platformSnapshot.platform,
		deviceClass = platformSnapshot.deviceClass,
		hints = hints,
	})
end

local function refreshBindingHints(forceRaw: any?)
	local force = forceRaw == true
	local now = os.clock()
	if not force and now - runtime.lastRefreshAt < REFRESH_INTERVAL_SECONDS then
		return
	end
	runtime.lastRefreshAt = now
	computeBindingState()
end

function bindingThunks.Start(): () -> ()
	if runtime.started then
		return bindingThunks.Stop
	end

	runtime.started = true
	runtime.lastRefreshAt = -math.huge

	if not PlatformServiceClient:isReady() then
		PlatformServiceClient:init()
	end

	runtime.inventoryStateChangedConnection =
		ServiceSync.connectStateChanged(InventoryServiceClient, function()
			refreshBindingHints(true)
		end)
	runtime.buildStateChangedConnection = ServiceSync.connectStateChanged(BuildServiceClient, function()
		refreshBindingHints(true)
	end)
	runtime.magicStateChangedConnection = ServiceSync.connectStateChanged(MagicServiceClient, function()
		refreshBindingHints(true)
	end)

	local breakProgressSignal = (BuildServiceClient :: any).breakProgressChanged
	if breakProgressSignal ~= nil then
		runtime.buildBreakProgressConnection = breakProgressSignal:Connect(function()
			refreshBindingHints(true)
		end)
	end

	runtime.platformDisconnect = PlatformServiceClient:onPlatformChanged(function()
		refreshBindingHints(true)
	end)

	runtime.renderConnection = RunService.RenderStepped:Connect(function()
		refreshBindingHints(false)
	end)

	ServiceSync.requestSyncMany({
		PlatformServiceClient,
		InventoryServiceClient,
		BuildServiceClient,
		MagicServiceClient,
	})
	refreshBindingHints(true)

	return bindingThunks.Stop
end

function bindingThunks.Stop()
	ConnectionUtils.disconnectMany({
		runtime.renderConnection,
		runtime.inventoryStateChangedConnection,
		runtime.buildStateChangedConnection,
		runtime.buildBreakProgressConnection,
		runtime.magicStateChangedConnection,
	})
	ConnectionUtils.call(runtime.platformDisconnect)

	runtime.started = false
	runtime.lastRefreshAt = -math.huge
	runtime.renderConnection = nil
	runtime.inventoryStateChangedConnection = nil
	runtime.buildStateChangedConnection = nil
	runtime.buildBreakProgressConnection = nil
	runtime.magicStateChangedConnection = nil
	runtime.platformDisconnect = nil
	bindingSlice.resetBindingState()
end

function bindingThunks.Refresh(): BindingHintState
	return computeBindingState()
end

function bindingThunks.GetState(): BindingHintState
	return bindingSlice.getBindingState()
end

bindingThunks.start = bindingThunks.Start
bindingThunks.stop = bindingThunks.Stop
bindingThunks.refresh = bindingThunks.Refresh
bindingThunks.getState = bindingThunks.GetState

return bindingThunks
