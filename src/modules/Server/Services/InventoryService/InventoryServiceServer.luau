--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local ResolveItem = require(script:FindFirstAncestor("game").Shared.Modules.Game.ResolveItem)
local ResolveToolInstance = require(script:FindFirstAncestor("game").Shared.Modules.Game.ResolveToolInstance)
local MiningPower = require(script:FindFirstAncestor("game").Shared.Modules.Math.MiningPower)
local TorchTilt = require(script:FindFirstAncestor("game").Shared.Modules.Math.TorchTilt)
local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildService.BuildServiceUtils)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryService.InventoryServiceUtils)
local InventoryProfile = require(script:FindFirstAncestor("game").Shared.Services.InventoryService.Profile)
local PlayerDataServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerDataService.PlayerDataServiceUtils)
local PlayerDataServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerDataService.PlayerDataServiceServer)
local WorldGenerationServiceServer = require(script:FindFirstAncestor("game").Server.Services.WorldGenerationService.WorldGenerationServiceServer)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)
local ToolBinder = require(script:FindFirstAncestor("game").Shared.Binders.ToolBinder)

type InventoryState = InventoryServiceUtils.InventoryState
type AddItemResult = InventoryServiceUtils.AddItemResult
type RemoveItemResult = InventoryServiceUtils.RemoveItemResult
type SlotMutationResult = InventoryServiceUtils.SlotMutationResult

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type PlayerDataServiceServerObject = {
	getValue: (self: PlayerDataServiceServerObject, player: Player, pathRaw: any, fallback: any) -> any,
	getLoadState: (self: PlayerDataServiceServerObject, player: Player) -> string,
	getProfile: (self: PlayerDataServiceServerObject, player: Player) -> any,
	isLoaded: (self: PlayerDataServiceServerObject, player: Player) -> boolean,
	requestSync: (self: PlayerDataServiceServerObject, player: Player) -> (),
	waitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	setValue: (
		self: PlayerDataServiceServerObject,
		player: Player,
		pathRaw: any,
		value: any,
		replicateToClientRaw: any
	) -> boolean,
}

type InventoryProfileObject = {
	cloneDefaultInventoryData: (self: InventoryProfileObject) -> { [string]: any },
	getDataPath: (self: InventoryProfileObject) -> { string },
	getDataPathString: (self: InventoryProfileObject) -> string,
	hasAuthoritativeProfile: (self: InventoryProfileObject, player: Player) -> boolean,
	saveProfile: (self: InventoryProfileObject, player: Player) -> (boolean, string),
	saveState: (self: InventoryProfileObject, player: Player, stateRaw: any) -> (boolean, string),
	writeState: (self: InventoryProfileObject, player: Player, stateRaw: any) -> (boolean, string),
}

type PendingToolImport = { itemId: string, itemType: string, amount: number }
type PlayerRuntime = {
	userId: number,
	player: Player,
	state: InventoryState,
	isLoading: boolean,
	isLoaded: boolean,
	isDirty: boolean,
	isSaving: boolean,
	saveQueued: boolean,
	loadState: string,
	lastReplicatedStateHash: string?,
	selectedSlot: number?,
	toolSyncJanitor: JanitorClass,
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
	pendingToolImports: { [string]: PendingToolImport },
	suppressedToolImports: { [string]: number },
	resolvedSource: string,
	joinToken: number,
	loadToken: number,
	hasResolvedInitialLoad: boolean,
	lastFailureReason: string?,
	loadStartedAt: number,
	saveDebounceToken: number,
	lastSavedRevision: number,
	lastStagedRevision: number,
	revision: number,
}

local InventoryServiceServer = {}

local PRIMARY_PERSISTENCE_TIMEOUT_SECONDS = 3
local FALLBACK_PERSISTENCE_TIMEOUT_SECONDS = 4
local PLAYER_DATA_SETTLE_TIMEOUT_SECONDS = 8
local SAVE_DEBOUNCE_SECONDS = 0.25
local SAVE_RETRY_SECONDS = 5
local TOOL_IMPORT_ATTRIBUTE_NAME = "itemId"
local TOOL_IMPORT_TYPE_ATTRIBUTE_NAME = "itemType"
local TOOL_IMPORT_METADATA_TYPE_KEY = "itemType"
local TOOL_IMPORT_STACK_ID_PREFIX = "tool"
local STACK_ID_ATTRIBUTE_NAME = "InventoryStackId"
local SELECTED_SLOT_ATTRIBUTE_NAME = "InventorySelectedSlot"
local MANAGED_TOOL_ATTRIBUTE_NAME = "InventoryManagedTool"
local GENERATED_TOOL_WELD_ATTRIBUTE_NAME = "InventoryManagedToolWeld"
local DEPLOYABLE_PLACED_ATTRIBUTE_NAME = "PlacedItemId"
local DEPLOYABLE_TILE_X_ATTRIBUTE_NAME = "DeployableTileX"
local DEPLOYABLE_TILE_Y_ATTRIBUTE_NAME = "DeployableTileY"
local DEPLOYABLE_SUPPORT_KIND_ATTRIBUTE_NAME = "DeployableSupportKind"
local TORCH_DEPLOYABLE_TAG = TagBinder.Tags.Light_Torch
local TORCH_GROUND_NORMAL = Vector3.new(0, 1, 0)
local TORCH_LEFT_WALL_NORMAL = Vector3.new(0, 0, 1)
local TORCH_RIGHT_WALL_NORMAL = Vector3.new(0, 0, -1)

local function createEmptyAddItemResult(): AddItemResult
	return { requested = 0, added = 0, leftover = 0, changed = false, touchedSlots = {} }
end

local function createEmptyRemoveItemResult(): RemoveItemResult
	return { requested = 0, removed = 0, leftover = 0, changed = false, touchedSlots = {} }
end

local function createEmptySlotMutationResult(): SlotMutationResult
	return {
		changed = false,
		touchedSlots = {},
		fromSlot = nil,
		toSlot = nil,
		movedAmount = 0,
		removedAmount = 0,
		swapped = false,
	}
end

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeItemId(itemIdRaw: any): string?
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return nil
	end
	return itemId
end

local function normalizeImportAmount(amountRaw: any): number
	if typeof(amountRaw) ~= "number" or amountRaw ~= amountRaw then
		return 1
	end
	return math.max(1, math.floor(amountRaw))
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.max(minimum, valueRaw)
end

local function sanitizeFailureReason(reasonRaw: any): string?
	local reason = trim(reasonRaw)
	if reason == "" then
		return nil
	end
	return reason
end

local function stringifyLogValue(valueRaw: any): string
	if valueRaw == nil then
		return "nil"
	end
	local valueType = typeof(valueRaw)
	if valueType == "string" or valueType == "number" or valueType == "boolean" then
		return tostring(valueRaw)
	end
	return valueType
end

local function resolveItemTypeForStack(stackRaw: any): string?
	if typeof(stackRaw) ~= "table" then
		return nil
	end
	local stack = stackRaw :: { [string]: any }
	local metadata = if typeof(stack.metadata) == "table" then stack.metadata else nil
	local metadataItemType = if metadata ~= nil
		then sanitizeItemId((metadata :: { [string]: any })[TOOL_IMPORT_METADATA_TYPE_KEY])
		else nil
	if metadataItemType ~= nil then
		return metadataItemType
	end
	local definition = ItemRegistry.resolveDefinition(stack.itemId)
	if typeof(definition) == "table" then
		local definitionTable = definition :: { [string]: any }
		local itemType = sanitizeItemId(definitionTable.itemType) or sanitizeItemId(definitionTable.type)
		if itemType ~= nil then
			return itemType
		end
	end
	return sanitizeItemId(stack.itemId)
end

local function resolveToolImportData(tool: Tool): (string?, string?)
	local itemId = ResolveToolInstance.resolveToolItemId(tool)
	if itemId == nil then
		return nil, nil
	end
	local itemType = sanitizeItemId(ResolveToolInstance.resolveToolItemType(tool)) or sanitizeItemId(tool.Name)
	if itemType == nil then
		return nil, nil
	end
	return itemId, itemType
end

local function isManagedInventoryTool(tool: Tool): boolean
	return tool:GetAttribute(MANAGED_TOOL_ATTRIBUTE_NAME) == true
end

local function applyToolHandleProperties(part: BasePart)
	part.Name = "Handle"
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function applyToolVisualProperties(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function createFallbackToolHandle(tool: Tool, itemIdRaw: any): BasePart
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 2.2, 0.45)
	handle.Material = Enum.Material.Metal
	handle.Color = if string.find(string.lower(sanitizeItemId(itemIdRaw) or tool.Name), "copper", 1, true) ~= nil
		then Color3.fromRGB(184, 115, 51)
		else Color3.fromRGB(163, 162, 165)
	handle.Parent = tool
	applyToolHandleProperties(handle)
	return handle
end

local function clearGeneratedToolWelds(tool: Tool)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("WeldConstraint") and descendant:GetAttribute(GENERATED_TOOL_WELD_ATTRIBUTE_NAME) == true then
			descendant:Destroy()
		end
	end
end

local function collectOwnedToolParts(tool: Tool): { BasePart }
	local parts = {}
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:FindFirstAncestorWhichIsA("Tool") == tool then
			parts[#parts + 1] = descendant
		end
	end
	return parts
end

local function bindToolDescendantsToHandle(tool: Tool, handle: BasePart)
	clearGeneratedToolWelds(tool)
	for _, part in collectOwnedToolParts(tool) do
		applyToolVisualProperties(part)
		if part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld:SetAttribute(GENERATED_TOOL_WELD_ATTRIBUTE_NAME, true)
			weld.Parent = handle
		end
	end
end

local function ensureToolHasVisibleHandle(tool: Tool, itemIdRaw: any): BasePart
	tool.RequiresHandle = true
	local existingHandle = tool:FindFirstChild("Handle")
	if existingHandle ~= nil and existingHandle:IsA("BasePart") then
		applyToolHandleProperties(existingHandle)
		bindToolDescendantsToHandle(tool, existingHandle)
		return existingHandle
	end
	local directPart = tool:FindFirstChildWhichIsA("BasePart")
	if directPart ~= nil then
		applyToolHandleProperties(directPart)
		bindToolDescendantsToHandle(tool, directPart)
		return directPart
	end
	local descendantPart = tool:FindFirstChildWhichIsA("BasePart", true)
	if descendantPart ~= nil then
		local clonedHandle = descendantPart:Clone()
		clonedHandle.Parent = tool
		clonedHandle.Transparency = 1
		applyToolHandleProperties(clonedHandle)
		bindToolDescendantsToHandle(tool, clonedHandle)
		return clonedHandle
	end
	local fallback = createFallbackToolHandle(tool, itemIdRaw)
	bindToolDescendantsToHandle(tool, fallback)
	return fallback
end

local function createFallbackManagedTool(itemIdRaw: any): Tool?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = itemId
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	return tool
end

local function configureManagedToolForInventoryStack(tool: Tool, itemIdRaw: any, stackRaw: any, selectedSlotRaw: any)
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return
	end
	tool:SetAttribute(MANAGED_TOOL_ATTRIBUTE_NAME, true)
	tool:SetAttribute(TOOL_IMPORT_ATTRIBUTE_NAME, itemId)
	tool:SetAttribute("ItemId", itemId)
	tool:SetAttribute(STACK_ID_ATTRIBUTE_NAME, if typeof(stackRaw) == "table" then (stackRaw :: any).stackId else nil)
	tool:SetAttribute(
		SELECTED_SLOT_ATTRIBUTE_NAME,
		if typeof(selectedSlotRaw) == "number" then math.floor(selectedSlotRaw) else nil
	)
	local itemType = resolveItemTypeForStack(stackRaw)
	tool:SetAttribute(TOOL_IMPORT_TYPE_ATTRIBUTE_NAME, itemType)
	tool:SetAttribute("ItemType", itemType)
	local definition = ItemRegistry.resolveDefinition(itemId)
	local toolAttributes = MiningPower.toToolAttributeBundle(definition, itemType, nil)
	for attributeName, attributeValue in toolAttributes do
		tool:SetAttribute(attributeName, attributeValue)
	end
	ensureToolHasVisibleHandle(tool, itemId)
	ToolBinder.applyTags(tool)
end

local function cloneToolForInventoryStack(itemIdRaw: any, stackRaw: any, selectedSlotRaw: any): Tool?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end
	local clone = ResolveItem.cloneToolTemplate(itemId)
	if clone == nil then
		clone = createFallbackManagedTool(itemId)
	end
	if clone == nil then
		return nil
	end
	configureManagedToolForInventoryStack(clone, itemId, stackRaw, selectedSlotRaw)
	return clone
end

local function destroyManagedToolsExcept(player: Player, preserveToolRaw: any)
	local preserveTool = if typeof(preserveToolRaw) == "Instance" and preserveToolRaw:IsA("Tool")
		then preserveToolRaw :: Tool
		else nil
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if typeof(container) ~= "Instance" then
			continue
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child ~= preserveTool and isManagedInventoryTool(child) then
				child:Destroy()
			end
		end
	end
end

local function destroyMatchingToolsInContainer(container: Instance?, itemId: string, amountRaw: any): number
	if container == nil or typeof(amountRaw) ~= "number" or amountRaw ~= amountRaw then
		return 0
	end
	local remaining = math.max(0, math.floor(amountRaw))
	if remaining <= 0 then
		return 0
	end
	local destroyed = 0
	for _, child in container:GetChildren() do
		if destroyed >= remaining then
			break
		end
		if not child:IsA("Tool") then
			continue
		end
		local toolItemId = select(1, resolveToolImportData(child))
		if toolItemId ~= itemId then
			continue
		end
		child:Destroy()
		destroyed += 1
	end
	return destroyed
end

local function queuePendingToolImport(runtime: PlayerRuntime, itemId: string, itemType: string, amountRaw: any)
	local amount = normalizeImportAmount(amountRaw)
	local key = ("%s::%s"):format(itemId, itemType)
	local existing = runtime.pendingToolImports[key]
	if existing == nil then
		runtime.pendingToolImports[key] = { itemId = itemId, itemType = itemType, amount = amount }
	else
		existing.amount += amount
	end
end

local function queueSuppressedToolImport(runtime: PlayerRuntime, itemIdRaw: any, amountRaw: any)
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return
	end
	local amount = normalizeImportAmount(amountRaw)
	runtime.suppressedToolImports[itemId] = (runtime.suppressedToolImports[itemId] or 0) + amount
end

local function consumeSuppressedToolImport(runtime: PlayerRuntime, itemIdRaw: any, amountRaw: any): boolean
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return false
	end
	local amount = normalizeImportAmount(amountRaw)
	local current = runtime.suppressedToolImports[itemId] or 0
	if current <= 0 then
		return false
	end
	local remaining = current - amount
	runtime.suppressedToolImports[itemId] = if remaining > 0 then remaining else nil
	return true
end

local function resolveHorizontalLookVector(rootPart: BasePart): Vector3
	local flat = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if flat.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function resolveDeployableConfig(itemIdRaw: any): { [string]: any }?
	local itemId = sanitizeItemId(itemIdRaw)
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
	if sanitizeItemId((deployable :: { [string]: any }).stationTag) == nil then
		return nil
	end
	return deployable :: { [string]: any }
end

local function resolveDeployablePrimaryPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		if instance.PrimaryPart ~= nil then
			return instance.PrimaryPart
		end
		local descendant = instance:FindFirstChildWhichIsA("BasePart", true)
		if descendant ~= nil then
			instance.PrimaryPart = descendant
			return descendant
		end
	end
	return nil
end

local function resolveWorldGridConfig(): (any, Vector3?, number?, number?)
	local getWorldMethod = (WorldGenerationServiceServer :: any).getWorld
	if typeof(getWorldMethod) ~= "function" then
		return nil, nil, nil, nil
	end

	local ok, world = pcall(function()
		return (WorldGenerationServiceServer :: any):getWorld()
	end)
	if not ok or typeof(world) ~= "table" then
		return nil, nil, nil, nil
	end

	local worldOrigin = if typeof((world :: any).worldOrigin) == "Vector3" then (world :: any).worldOrigin else nil
	local tileSize = if typeof((world :: any).tileSize) == "number" and (world :: any).tileSize == (world :: any).tileSize
		then (world :: any).tileSize
		else nil
	local basePlaneX = if typeof((world :: any).basePlaneX) == "number" and (world :: any).basePlaneX == (world :: any).basePlaneX
		then (world :: any).basePlaneX
		else nil
	return world, worldOrigin, tileSize, basePlaneX
end

local function getWorldTileId(worldRaw: any, tileX: number, tileY: number): number
	if typeof(worldRaw) ~= "table" then
		return BuildServiceUtils.AIR_TILE_ID
	end

	local getTileAtMethod = (worldRaw :: any).getTileAt
	if typeof(getTileAtMethod) ~= "function" then
		return BuildServiceUtils.AIR_TILE_ID
	end

	local ok, tileIdOrError = pcall(function()
		return (worldRaw :: any):getTileAt(tileX, tileY)
	end)
	if not ok then
		return BuildServiceUtils.AIR_TILE_ID
	end

	local tileId = BuildServiceUtils.sanitizeTileId(tileIdOrError)
	if tileId == nil then
		return BuildServiceUtils.AIR_TILE_ID
	end
	return tileId
end

local function findTorchDeployableAtTile(tileX: number, tileY: number, excludeInstance: Instance?): Instance?
	for _, tagged in TagBinder.getTagged(TORCH_DEPLOYABLE_TAG, CollectionService) do
		if tagged == excludeInstance then
			continue
		end
		local taggedTileX = tagged:GetAttribute(DEPLOYABLE_TILE_X_ATTRIBUTE_NAME)
		local taggedTileY = tagged:GetAttribute(DEPLOYABLE_TILE_Y_ATTRIBUTE_NAME)
		if typeof(taggedTileX) == "number" and typeof(taggedTileY) == "number" then
			if math.floor(taggedTileX) == tileX and math.floor(taggedTileY) == tileY then
				return tagged
			end
		end
	end
	return nil
end

local function canOccupyTorchTile(worldRaw: any, tileX: number, tileY: number, excludeInstance: Instance?): boolean
	local tileId = getWorldTileId(worldRaw, tileX, tileY)
	if not BuildServiceUtils.isReplaceableTile(tileId) then
		return false
	end
	return findTorchDeployableAtTile(tileX, tileY, excludeInstance) == nil
end

local function isTorchGroundSupported(worldRaw: any, tileX: number, tileY: number): boolean
	local belowTileId = getWorldTileId(worldRaw, tileX, tileY - 1)
	return not BuildServiceUtils.isReplaceableTile(belowTileId)
end

local function isSolidTorchSupportTile(worldRaw: any, tileX: number, tileY: number): boolean
	return BuildServiceUtils.isSolidTile(getWorldTileId(worldRaw, tileX, tileY))
end

local function isTorchPlacementInRange(
	rootPosition: Vector3,
	placement: TorchTilt.TilePlacement,
	maxPlacementDistance: number,
	tileSize: number
): boolean
	return BuildServiceUtils.WorldDistance2D(rootPosition, placement.cframe.Position) <= (maxPlacementDistance + tileSize)
end

local function buildTorchTilePlacement(
	tileX: number,
	tileY: number,
	supportNormal: Vector3,
	boundingRotation: CFrame,
	worldOrigin: Vector3,
	tileSize: number,
	basePlaneX: number,
	lookVector: Vector3
): TorchTilt.TilePlacement?
	local tileCenter = BuildServiceUtils.TileToWorldCenter(tileX, tileY, worldOrigin, tileSize, basePlaneX)
	local supportCFrame, supportKind = TorchTilt.resolveTileAlignedCFrame(tileCenter, supportNormal, lookVector)
	if supportCFrame == nil or supportKind == nil then
		return nil
	end

	local finalCFrame = supportCFrame * boundingRotation
	return {
		tileX = tileX,
		tileY = tileY,
		supportKind = supportKind,
		cframe = CFrame.new(tileCenter) * finalCFrame.Rotation,
	}
end

local function resolveTorchPlacementAtTargetTile(
	worldRaw: any,
	tileX: number,
	tileY: number,
	boundingRotation: CFrame,
	worldOrigin: Vector3,
	tileSize: number,
	basePlaneX: number,
	lookVector: Vector3
): TorchTilt.TilePlacement?
	if not canOccupyTorchTile(worldRaw, tileX, tileY, nil) then
		return nil
	end

	if isSolidTorchSupportTile(worldRaw, tileX, tileY - 1) then
		return buildTorchTilePlacement(
			tileX,
			tileY,
			TORCH_GROUND_NORMAL,
			boundingRotation,
			worldOrigin,
			tileSize,
			basePlaneX,
			lookVector
		)
	end

	local hasLeftWall = isSolidTorchSupportTile(worldRaw, tileX - 1, tileY)
	local hasRightWall = isSolidTorchSupportTile(worldRaw, tileX + 1, tileY)
	if hasLeftWall and hasRightWall then
		return buildTorchTilePlacement(
			tileX,
			tileY,
			if lookVector.Z >= 0 then TORCH_LEFT_WALL_NORMAL else TORCH_RIGHT_WALL_NORMAL,
			boundingRotation,
			worldOrigin,
			tileSize,
			basePlaneX,
			lookVector
		)
	end
	if hasLeftWall then
		return buildTorchTilePlacement(
			tileX,
			tileY,
			TORCH_LEFT_WALL_NORMAL,
			boundingRotation,
			worldOrigin,
			tileSize,
			basePlaneX,
			lookVector
		)
	end
	if hasRightWall then
		return buildTorchTilePlacement(
			tileX,
			tileY,
			TORCH_RIGHT_WALL_NORMAL,
			boundingRotation,
			worldOrigin,
			tileSize,
			basePlaneX,
			lookVector
		)
	end

	return nil
end

local function resolveTorchPlacementFromRequestedTile(
	worldRaw: any,
	requestedTileX: number,
	requestedTileY: number,
	rootPart: BasePart,
	lookVector: Vector3,
	boundingRotation: CFrame,
	worldOrigin: Vector3,
	tileSize: number,
	basePlaneX: number,
	maxPlacementDistance: number
): TorchTilt.TilePlacement?
	local candidates = {} :: { { tileX: number, tileY: number } }
	local seen = {} :: { [string]: boolean }

	local function appendCandidate(tileX: number, tileY: number)
		local key = ("%d:%d"):format(tileX, tileY)
		if seen[key] == true then
			return
		end
		seen[key] = true
		candidates[#candidates + 1] = {
			tileX = tileX,
			tileY = tileY,
		}
	end

	appendCandidate(requestedTileX, requestedTileY)

	local requestedTileId = getWorldTileId(worldRaw, requestedTileX, requestedTileY)
	if not BuildServiceUtils.isReplaceableTile(requestedTileId) then
		appendCandidate(requestedTileX, requestedTileY + 1)
		if lookVector.Z >= 0 then
			appendCandidate(requestedTileX + 1, requestedTileY)
			appendCandidate(requestedTileX - 1, requestedTileY)
		else
			appendCandidate(requestedTileX - 1, requestedTileY)
			appendCandidate(requestedTileX + 1, requestedTileY)
		end
	end

	for _, candidate in candidates do
		local placement = resolveTorchPlacementAtTargetTile(
			worldRaw,
			candidate.tileX,
			candidate.tileY,
			boundingRotation,
			worldOrigin,
			tileSize,
			basePlaneX,
			lookVector
		)
		if placement ~= nil and isTorchPlacementInRange(rootPart.Position, placement, maxPlacementDistance, tileSize) then
			return placement
		end
	end

	return nil
end

local function chooseTorchPlacement(
	worldRaw: any,
	groundPlacement: TorchTilt.TilePlacement?,
	wallPlacement: TorchTilt.TilePlacement?
): TorchTilt.TilePlacement?
	local validGround = if groundPlacement ~= nil
		then canOccupyTorchTile(worldRaw, groundPlacement.tileX, groundPlacement.tileY, nil)
		else false
	local validWall = if wallPlacement ~= nil
		then canOccupyTorchTile(worldRaw, wallPlacement.tileX, wallPlacement.tileY, nil)
		else false

	if validGround and validWall and groundPlacement ~= nil and wallPlacement ~= nil then
		if groundPlacement.tileX == wallPlacement.tileX and groundPlacement.tileY == wallPlacement.tileY then
			return groundPlacement
		end
		if isTorchGroundSupported(worldRaw, wallPlacement.tileX, wallPlacement.tileY) then
			return groundPlacement
		end
	end

	if validWall then
		return wallPlacement
	end
	if validGround then
		return groundPlacement
	end
	return nil
end

local function resolveTorchDeployablePlacement(
	player: Player,
	deployableConfig: { [string]: any },
	placedInstance: Instance,
	requestedTileXRaw: any?,
	requestedTileYRaw: any?
): TorchTilt.TilePlacement?
	local character = player.Character
	if character == nil then
		return nil
	end
	local rootPart = character.PrimaryPart or (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if rootPart == nil then
		return nil
	end

	local world, worldOrigin, tileSize, basePlaneX = resolveWorldGridConfig()
	if world == nil or worldOrigin == nil or tileSize == nil or basePlaneX == nil then
		return nil
	end

	local lookVector = resolveHorizontalLookVector(rootPart)
	local placementDistance = sanitizeNumber(deployableConfig.placementDistance, 6, 2)
	local maxPlacementDistance =
		sanitizeNumber(deployableConfig.maxPlacementDistance, placementDistance + 4, placementDistance)
	local supportDistance = math.min(placementDistance, maxPlacementDistance)
	local boundingCFrame: CFrame
	local boundingSize: Vector3
	local boundingRotation: CFrame
	if placedInstance:IsA("Model") then
		boundingCFrame, boundingSize = placedInstance:GetBoundingBox()
	else
		local placedPart = placedInstance :: BasePart
		boundingCFrame = placedPart.CFrame
		boundingSize = placedPart.Size
	end
	boundingRotation = boundingCFrame.Rotation

	local requestedTileX = BuildServiceUtils.sanitizeTileCoordinate(requestedTileXRaw)
	local requestedTileY = BuildServiceUtils.sanitizeTileCoordinate(requestedTileYRaw)
	if requestedTileX ~= nil and requestedTileY ~= nil then
		local requestedPlacement = resolveTorchPlacementFromRequestedTile(
			world,
			requestedTileX,
			requestedTileY,
			rootPart,
			lookVector,
			boundingRotation,
			worldOrigin,
			tileSize,
			basePlaneX,
			maxPlacementDistance
		)
		if requestedPlacement ~= nil then
			return requestedPlacement
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, placedInstance }

	local function buildPlacementFromSupport(hitPosition: Vector3, hitNormal: Vector3): TorchTilt.TilePlacement?
		local supportCFrame, supportKind = TorchTilt.resolvePlacementCFrame(hitPosition, hitNormal, boundingSize, lookVector)
		if supportCFrame == nil or supportKind == nil then
			return nil
		end

		local finalCFrame = supportCFrame * boundingRotation
		local tileX, tileY = BuildServiceUtils.WorldPositionToTile(finalCFrame.Position, worldOrigin, tileSize)
		local hitNormalUnit = hitNormal.Unit
		if not BuildServiceUtils.isReplaceableTile(getWorldTileId(world, tileX, tileY)) then
			if supportKind == "Ground" then
				tileY += 1
			else
				tileX += if hitNormalUnit.Z >= 0 then 1 else -1
			end
		end
		local tileCenter = BuildServiceUtils.TileToWorldCenter(tileX, tileY, worldOrigin, tileSize, basePlaneX)

		return {
			tileX = tileX,
			tileY = tileY,
			supportKind = supportKind,
			cframe = CFrame.new(tileCenter) * finalCFrame.Rotation,
		}
	end

	local wallPlacement = nil :: TorchTilt.TilePlacement?
	local wallOrigin = rootPart.Position + Vector3.new(0, 2, 0)
	local wallResult = Workspace:Raycast(wallOrigin, lookVector * supportDistance, params)
	if wallResult ~= nil and TorchTilt.isSolidSurface(wallResult.Instance) and TorchTilt.isWallNormal(wallResult.Normal) then
		wallPlacement = buildPlacementFromSupport(wallResult.Position, wallResult.Normal)
	end

	local groundPlacement = nil :: TorchTilt.TilePlacement?
	local desiredPosition = rootPart.Position + Vector3.new(0, 4, 0) + (lookVector * supportDistance)
	local groundResult = Workspace:Raycast(desiredPosition + Vector3.new(0, 12, 0), Vector3.new(0, -32, 0), params)
	if groundResult ~= nil and TorchTilt.isSolidSurface(groundResult.Instance) and TorchTilt.isGroundNormal(groundResult.Normal) then
		groundPlacement = buildPlacementFromSupport(groundResult.Position, groundResult.Normal)
	end

	return chooseTorchPlacement(world, groundPlacement, wallPlacement)
end

local function setModelAnchored(instance: Instance, anchored: boolean)
	if instance:IsA("BasePart") then
		instance.Anchored = anchored
		return
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
		end
	end
end

local function resolveDeployablePlacementCFrame(
	player: Player,
	deployableConfig: { [string]: any },
	placedInstance: Instance
): CFrame?
	local character = player.Character
	if character == nil then
		return nil
	end
	local rootPart = character.PrimaryPart or (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if rootPart == nil then
		return nil
	end
	local lookVector = resolveHorizontalLookVector(rootPart)
	local placementDistance = sanitizeNumber(deployableConfig.placementDistance, 6, 2)
	local maxPlacementDistance =
		sanitizeNumber(deployableConfig.maxPlacementDistance, placementDistance + 4, placementDistance)
	local placementProfile = sanitizeItemId((deployableConfig :: { [string]: any }).placementProfile)
	local boundingCFrame: CFrame
	local boundingSize: Vector3
	if placedInstance:IsA("Model") then
		boundingCFrame, boundingSize = placedInstance:GetBoundingBox()
	else
		local placedPart = placedInstance :: BasePart
		boundingCFrame = placedPart.CFrame
		boundingSize = placedPart.Size
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, placedInstance }

	if placementProfile == "Torch" then
		local supportDistance = math.min(placementDistance, maxPlacementDistance)
		local wallOrigin = rootPart.Position + Vector3.new(0, 2, 0)
		local wallResult = Workspace:Raycast(wallOrigin, lookVector * supportDistance, params)
		if wallResult ~= nil and TorchTilt.isSolidSurface(wallResult.Instance) and TorchTilt.isWallNormal(wallResult.Normal) then
			local supportCFrame = TorchTilt.resolvePlacementCFrame(
				wallResult.Position,
				wallResult.Normal,
				boundingSize,
				lookVector
			)
			if supportCFrame ~= nil then
				return supportCFrame * boundingCFrame.Rotation
			end
		end

		local desiredPosition = rootPart.Position + Vector3.new(0, 4, 0) + (lookVector * supportDistance)
		local groundResult = Workspace:Raycast(desiredPosition + Vector3.new(0, 12, 0), Vector3.new(0, -32, 0), params)
		if groundResult == nil then
			return nil
		end
		if not TorchTilt.isSolidSurface(groundResult.Instance) or not TorchTilt.isGroundNormal(groundResult.Normal) then
			return nil
		end

		local supportCFrame = TorchTilt.resolvePlacementCFrame(
			groundResult.Position,
			groundResult.Normal,
			boundingSize,
			lookVector
		)
		if supportCFrame == nil then
			return nil
		end
		return supportCFrame * boundingCFrame.Rotation
	end

	local desiredPosition = rootPart.Position
		+ Vector3.new(0, 4, 0)
		+ (lookVector * math.min(placementDistance, maxPlacementDistance))
	local groundResult = Workspace:Raycast(desiredPosition + Vector3.new(0, 12, 0), Vector3.new(0, -32, 0), params)
	local groundPosition = if groundResult ~= nil then groundResult.Position else desiredPosition
	local yaw = math.atan2(-lookVector.X, -lookVector.Z)
	local targetPosition =
		Vector3.new(groundPosition.X, groundPosition.Y + math.max(0, boundingSize.Y * 0.5), groundPosition.Z)
	return CFrame.new(targetPosition) * CFrame.Angles(0, yaw, 0) * boundingCFrame.Rotation
end

local function applyRuntimeState(runtime: PlayerRuntime, nextStateRaw: any)
	runtime.state = InventoryServiceUtils.sanitizeState(nextStateRaw, runtime.state)
	runtime.loadState = runtime.state.loadState
	runtime.selectedSlot = runtime.state.selectedSlot
	runtime.isLoaded = InventoryServiceUtils.isLoadedState(runtime.state.loadState)
	if runtime.state.loadState ~= InventoryServiceUtils.LOAD_STATE_LOADING then
		runtime.isLoading = false
	end
end

local function getRuntimeLoadElapsedSeconds(runtime: PlayerRuntime): number
	if runtime.loadStartedAt <= 0 then
		return 0
	end
	return math.max(0, os.clock() - runtime.loadStartedAt)
end

function InventoryServiceServer.LogEvent(
	_self: InventoryServiceServer,
	eventName: string,
	player: Player,
	runtime: PlayerRuntime?,
	extraFieldsRaw: any
)
	local fields = {
		("event=%s"):format(eventName),
		("player=%s"):format(player.Name),
		("userId=%d"):format(player.UserId),
	}
	if runtime ~= nil then
		fields[#fields + 1] = ("loadState=%s"):format(runtime.loadState)
		fields[#fields + 1] = ("isLoading=%s"):format(tostring(runtime.isLoading))
		fields[#fields + 1] = ("isLoaded=%s"):format(tostring(runtime.isLoaded))
		fields[#fields + 1] = ("isDirty=%s"):format(tostring(runtime.isDirty))
		fields[#fields + 1] = ("isSaving=%s"):format(tostring(runtime.isSaving))
		fields[#fields + 1] = ("saveQueued=%s"):format(tostring(runtime.saveQueued))
		fields[#fields + 1] = ("revision=%d"):format(runtime.revision)
		fields[#fields + 1] = ("lastSavedRevision=%d"):format(runtime.lastSavedRevision)
		fields[#fields + 1] = ("lastStagedRevision=%d"):format(runtime.lastStagedRevision)
		fields[#fields + 1] = ("selectedSlot=%s"):format(stringifyLogValue(runtime.selectedSlot))
		fields[#fields + 1] = ("joinToken=%d"):format(runtime.joinToken)
		fields[#fields + 1] = ("loadToken=%d"):format(runtime.loadToken)
		fields[#fields + 1] = ("hasResolvedInitialLoad=%s"):format(tostring(runtime.hasResolvedInitialLoad))
		fields[#fields + 1] = ("elapsed=%.3f"):format(getRuntimeLoadElapsedSeconds(runtime))
		if runtime.lastFailureReason ~= nil then
			fields[#fields + 1] = ("lastFailureReason=%s"):format(runtime.lastFailureReason)
		end
	end
	if typeof(extraFieldsRaw) == "table" then
		for key, value in extraFieldsRaw :: { [string]: any } do
			fields[#fields + 1] = ("%s=%s"):format(tostring(key), stringifyLogValue(value))
		end
	end
end

function InventoryServiceServer.GetInventoryDataPath(self: InventoryServiceServer): { string }
	local persistence = self.persistence
	if persistence ~= nil then
		return persistence:getDataPath()
	end
	return InventoryServiceUtils.getDefaultDataPath()
end

function InventoryServiceServer.GetInventoryDataPathString(self: InventoryServiceServer): string
	local persistence = self.persistence
	if persistence ~= nil then
		return persistence:getDataPathString()
	end
	return table.concat(InventoryServiceUtils.getDefaultDataPath(), ".")
end

function InventoryServiceServer.MarkRuntimeDirty(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	reasonRaw: any
)
	runtime.revision += 1
	runtime.isDirty = true
	self:logEvent("inventory_mutation_applied", player, runtime, {
		trigger = reasonRaw,
		path = self:getInventoryDataPathString(),
		occupiedSlots = runtime.state.occupiedSlotCount,
		totalItems = runtime.state.totalItemCount,
		updatedAt = runtime.state.updatedAt,
	})
	self:logEvent("runtime_marked_dirty", player, runtime, {
		trigger = reasonRaw,
		path = self:getInventoryDataPathString(),
	})
end

function InventoryServiceServer.StagePersistedState(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	reasonRaw: any
): boolean
	if not runtime.isLoaded then
		return false
	end

	local stageSuccess, didStage, stageReason = pcall(function()
		return self.persistence:writeState(player, runtime.state)
	end)
	if stageSuccess and didStage == true then
		runtime.lastStagedRevision = runtime.revision
		return true
	end

	self:logEvent("profile_writeback_failed", player, runtime, {
		trigger = reasonRaw,
		path = self:getInventoryDataPathString(),
		reason = if stageSuccess then stageReason else tostring(didStage),
	})
	return false
end

function InventoryServiceServer.CreateRuntime(self: InventoryServiceServer, player: Player): PlayerRuntime
	local state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADING)
	local runtime: PlayerRuntime = {
		userId = player.UserId,
		player = player,
		state = state,
		isLoading = true,
		isLoaded = false,
		isDirty = false,
		isSaving = false,
		saveQueued = false,
		loadState = state.loadState,
		lastReplicatedStateHash = nil,
		selectedSlot = state.selectedSlot,
		toolSyncJanitor = Janitor.new(),
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		pendingToolImports = {},
		suppressedToolImports = {},
		resolvedSource = "loading",
		joinToken = 0,
		loadToken = 0,
		hasResolvedInitialLoad = false,
		lastFailureReason = nil,
		loadStartedAt = 0,
		saveDebounceToken = 0,
		lastSavedRevision = 0,
		lastStagedRevision = 0,
		revision = 0,
	}
	self:logEvent("runtime_created", player, runtime, nil)
	return runtime
end

function InventoryServiceServer.GetRuntime(self: InventoryServiceServer, player: Player): PlayerRuntime?
	return self.playerRuntimesByUserId[player.UserId]
end

function InventoryServiceServer.GetOrCreateRuntime(self: InventoryServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimesByUserId[player.UserId]
	if runtime ~= nil then
		runtime.player = player
		return runtime
	end
	runtime = self:createRuntime(player)
	self.playerRuntimesByUserId[player.UserId] = runtime
	return runtime
end

function InventoryServiceServer.GetLoadedRuntime(self: InventoryServiceServer, player: Player): PlayerRuntime?
	local runtime = self.playerRuntimesByUserId[player.UserId]
	if runtime == nil or not runtime.isLoaded then
		return nil
	end
	return runtime
end

function InventoryServiceServer.ReplicateRuntimeState(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	reasonRaw: any,
	forceRaw: any?
): boolean
	applyRuntimeState(runtime, runtime.state)
	local stateHash = InventoryServiceUtils.hashState(runtime.state)
	if forceRaw ~= true and runtime.lastReplicatedStateHash == stateHash then
		return false
	end
	runtime.lastReplicatedStateHash = stateHash
	if self.networker ~= nil then
		self.networker:fire(player, "applyState", InventoryServiceUtils.cloneState(runtime.state))
	end
	self:logEvent("state_replicated", player, runtime, {
		reason = reasonRaw,
		hash = stateHash,
		occupiedSlots = runtime.state.occupiedSlotCount,
		totalItems = runtime.state.totalItemCount,
	})
	return true
end

function InventoryServiceServer.ScheduleSaveAttempt(
	self: InventoryServiceServer,
	userId: number,
	token: number,
	reasonRaw: any,
	delaySeconds: number
)
	task.delay(delaySeconds, function()
		local runtime = self.playerRuntimesByUserId[userId]
		if runtime == nil or runtime.saveDebounceToken ~= token or not runtime.isDirty then
			return
		end
		local player = runtime.player
		if player == nil then
			return
		end
		self:performSave(player, runtime, token, reasonRaw)
	end)
end

function InventoryServiceServer.RunQueuedSaveRerun(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	reasonRaw: any
)
	task.spawn(function()
		local currentRuntime = self.playerRuntimesByUserId[player.UserId]
		if currentRuntime == nil or currentRuntime ~= runtime or not runtime.isDirty then
			return
		end
		self:performSave(player, runtime, runtime.saveDebounceToken, reasonRaw)
	end)
end

function InventoryServiceServer.CanPersistRuntime(self: InventoryServiceServer, player: Player): (boolean, string)
	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return false, "player_data_service_missing"
	end

	local loadStateSuccess, loadState = pcall(function()
		return playerDataService:getLoadState(player)
	end)
	if not loadStateSuccess then
		return false, "player_data_load_state_error:" .. tostring(loadState)
	end
	if loadState ~= PlayerDataServiceUtils.LOAD_STATE_LOADED then
		return false, "player_data_not_active:" .. tostring(loadState)
	end

	local profileSuccess, hasProfile = pcall(function()
		return self.persistence:hasAuthoritativeProfile(player)
	end)
	if not profileSuccess then
		return false, "profile_check_error:" .. tostring(hasProfile)
	end
	if hasProfile ~= true then
		return false, "profile_unavailable"
	end

	return true, "ready"
end

function InventoryServiceServer.PerformSave(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	token: number,
	reasonRaw: any
): boolean
	if self.playerRuntimesByUserId[player.UserId] ~= runtime then
		return false
	end
	if not runtime.isLoaded then
		self:logEvent("save_skipped_not_loaded", player, runtime, {
			trigger = reasonRaw,
			token = token,
			path = self:getInventoryDataPathString(),
		})
		return false
	end
	if not runtime.isDirty then
		return false
	end
	if runtime.isSaving then
		runtime.saveQueued = true
		self:logEvent("save_queued_rerun", player, runtime, {
			trigger = reasonRaw,
			token = token,
			path = self:getInventoryDataPathString(),
			reason = "save_in_progress",
		})
		return false
	end

	local snapshotRevision = runtime.revision
	local snapshotState = InventoryServiceUtils.cloneState(runtime.state)
	local dataPath = self:getInventoryDataPathString()
	local canPersist, persistReason = self:canPersistRuntime(player)
	if not canPersist then
		self:logEvent("save_failed", player, runtime, {
			reason = persistReason,
			trigger = reasonRaw,
			token = token,
			snapshotRevision = snapshotRevision,
			path = dataPath,
		})
		self:scheduleSaveAttempt(
			runtime.userId,
			runtime.saveDebounceToken,
			"retry_" .. tostring(reasonRaw),
			SAVE_RETRY_SECONDS
		)
		return false
	end

	runtime.isSaving = true
	runtime.saveQueued = false
	self:logEvent("save_begin", player, runtime, {
		trigger = reasonRaw,
		token = token,
		snapshotRevision = snapshotRevision,
		path = dataPath,
	})

	local saveUsesStagedProfileData = runtime.lastStagedRevision >= snapshotRevision
	local okSave, didSave, saveReason = pcall(function()
		if saveUsesStagedProfileData then
			return self.persistence:saveProfile(player)
		end
		return self.persistence:saveState(player, snapshotState)
	end)

	runtime.isSaving = false

	if okSave and didSave == true then
		runtime.lastSavedRevision = math.max(runtime.lastSavedRevision, snapshotRevision)
		local newerRevisionExists = runtime.revision > snapshotRevision
		if not newerRevisionExists and not runtime.saveQueued then
			runtime.isDirty = false
		end
		self:logEvent("save_success", player, runtime, {
			trigger = reasonRaw,
			token = token,
			snapshotRevision = snapshotRevision,
			saveReason = saveReason,
			usedStagedProfileData = saveUsesStagedProfileData,
			path = dataPath,
			dirtyCleared = not runtime.isDirty,
		})
		if runtime.saveQueued or newerRevisionExists then
			runtime.saveQueued = false
			self:logEvent("save_queued_rerun", player, runtime, {
				trigger = reasonRaw,
				token = token,
				path = dataPath,
				reason = "newer_revision_waiting",
			})
			self:runQueuedSaveRerun(player, runtime, "queued_rerun")
		end
		return true
	end

	local failureReason = if okSave then tostring(saveReason) else tostring(didSave)
	self:logEvent("save_failed", player, runtime, {
		reason = failureReason,
		trigger = reasonRaw,
		token = token,
		snapshotRevision = snapshotRevision,
		usedStagedProfileData = saveUsesStagedProfileData,
		path = dataPath,
	})
	if runtime.saveQueued or runtime.revision > snapshotRevision then
		runtime.saveQueued = false
		self:logEvent("save_queued_rerun", player, runtime, {
			trigger = reasonRaw,
			token = token,
			path = dataPath,
			reason = "newer_revision_after_failure",
		})
		self:runQueuedSaveRerun(player, runtime, "queued_rerun_after_failure")
		return false
	end
	self:scheduleSaveAttempt(
		runtime.userId,
		runtime.saveDebounceToken,
		"retry_" .. tostring(reasonRaw),
		SAVE_RETRY_SECONDS
	)
	return false
end

function InventoryServiceServer.QueueSave(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	reasonRaw: any
)
	if not runtime.isLoaded then
		self:logEvent("save_skipped_not_loaded", player, runtime, {
			trigger = reasonRaw,
			path = self:getInventoryDataPathString(),
		})
		return
	end
	runtime.saveDebounceToken += 1
	local token = runtime.saveDebounceToken
	if runtime.isSaving then
		runtime.saveQueued = true
		self:logEvent("save_queued_rerun", player, runtime, {
			trigger = reasonRaw,
			token = token,
			path = self:getInventoryDataPathString(),
			reason = "save_in_progress",
		})
		return
	end
	self:logEvent("save_scheduled", player, runtime, {
		trigger = reasonRaw,
		token = token,
		path = self:getInventoryDataPathString(),
	})
	self:scheduleSaveAttempt(runtime.userId, token, reasonRaw, SAVE_DEBOUNCE_SECONDS)
end

function InventoryServiceServer.CommitState(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	nextStateRaw: any,
	reasonRaw: any,
	beforeCommitRaw: any?
)
	applyRuntimeState(runtime, nextStateRaw)
	if typeof(beforeCommitRaw) == "function" then
		local ok, err = pcall(beforeCommitRaw)
		if not ok then
			self:logEvent("before_commit_fail", player, runtime, { reason = tostring(err), trigger = reasonRaw })
		end
	end
	self:markRuntimeDirty(player, runtime, reasonRaw)
	self:stagePersistedState(player, runtime, reasonRaw)
	self:queueSave(player, runtime, reasonRaw)
	local syncOk, syncErr = pcall(function()
		self:syncSelectedTool(player, runtime, reasonRaw)
	end)
	if not syncOk then
		self:logEvent("tool_sync_fail", player, runtime, { trigger = reasonRaw, reason = tostring(syncErr) })
	end
	self:replicateRuntimeState(player, runtime, reasonRaw, true)
end

function InventoryServiceServer.FindMatchingTool(_self: InventoryServiceServer, player: Player, stackRaw: any): Tool?
	if typeof(stackRaw) ~= "table" then
		return nil
	end
	local stack = stackRaw :: { [string]: any }
	local itemId = sanitizeItemId(stack.itemId)
	if itemId == nil then
		return nil
	end
	local desiredStackId = sanitizeItemId(stack.stackId)
	local fallback = nil :: Tool?
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if typeof(container) ~= "Instance" then
			continue
		end
		for _, child in container:GetChildren() do
			if not child:IsA("Tool") then
				continue
			end
			local toolItemId = select(1, resolveToolImportData(child))
			if toolItemId ~= itemId then
				continue
			end
			if desiredStackId ~= nil and child:GetAttribute(STACK_ID_ATTRIBUTE_NAME) == desiredStackId then
				return child
			end
			fallback = fallback or child
		end
	end
	return fallback
end

function InventoryServiceServer.SyncSelectedTool(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	reasonRaw: any?
)
	runtime.toolSyncJanitor:Clean()
	if not runtime.isLoaded then
		destroyManagedToolsExcept(player, nil)
		return
	end
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local backpack = player:FindFirstChildOfClass("Backpack")
	local selectedSlot = runtime.selectedSlot
	local selectedStack = if selectedSlot ~= nil
		then InventoryServiceUtils.getStack(runtime.state, selectedSlot)
		else nil
	local selectedItemId = if selectedStack ~= nil then sanitizeItemId(selectedStack.itemId) else nil
	if selectedItemId == nil then
		destroyManagedToolsExcept(player, nil)
		if humanoid ~= nil then
			pcall(function()
				humanoid:UnequipTools()
			end)
		end
		self:logEvent("tool_sync_applied", player, runtime, { trigger = reasonRaw, outcome = "cleared" })
		return
	end
	local desiredTool = self:findMatchingTool(player, selectedStack)
	if desiredTool == nil and selectedStack ~= nil then
		desiredTool = cloneToolForInventoryStack(selectedItemId, selectedStack, selectedSlot)
		if desiredTool ~= nil then
			local targetParent = if backpack ~= nil then backpack else character
			if targetParent ~= nil then
				desiredTool.Parent = targetParent
			else
				desiredTool:Destroy()
				desiredTool = nil
			end
		end
	end
	if desiredTool == nil then
		destroyManagedToolsExcept(player, nil)
		self:logEvent(
			"tool_sync_applied",
			player,
			runtime,
			{ trigger = reasonRaw, outcome = "missing_template", itemId = selectedItemId }
		)
		return
	end
	configureManagedToolForInventoryStack(desiredTool, selectedItemId, selectedStack, selectedSlot)
	destroyManagedToolsExcept(player, desiredTool)
	local deployableConfig = resolveDeployableConfig(selectedItemId)
	if deployableConfig ~= nil then
		local placementProfile = sanitizeItemId((deployableConfig :: { [string]: any }).placementProfile)
		if placementProfile ~= "Torch" then
			runtime.toolSyncJanitor:GiveChore(desiredTool.Activated:Connect(function()
				self:tryPlaceDeployableFromTool(player, runtime, desiredTool)
			end))
		end
	end
	runtime.toolSyncJanitor:GiveChore(desiredTool.Destroying:Connect(function()
		task.defer(function()
			local currentRuntime = self:getRuntime(player)
			if currentRuntime ~= nil and currentRuntime == runtime then
				self:syncSelectedTool(player, runtime, "tool_destroyed")
			end
		end)
	end))
	if humanoid ~= nil and desiredTool.Parent ~= character then
		pcall(function()
			humanoid:EquipTool(desiredTool)
		end)
	end
	self:logEvent("tool_sync_applied", player, runtime, {
		trigger = reasonRaw,
		outcome = "equipped",
		itemId = selectedItemId,
		stackId = if selectedStack ~= nil then selectedStack.stackId else nil,
	})
end

function InventoryServiceServer.SuppressAndPurgePlayerTools(
	_self: InventoryServiceServer,
	runtime: PlayerRuntime,
	player: Player,
	itemIdRaw: any,
	amountRaw: any
)
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil or typeof(amountRaw) ~= "number" or amountRaw ~= amountRaw then
		return
	end
	local remaining = math.max(0, math.floor(amountRaw))
	if remaining <= 0 then
		return
	end
	local afterCharacter = remaining - destroyMatchingToolsInContainer(player.Character, itemId, remaining)
	local afterBackpack = afterCharacter
		- destroyMatchingToolsInContainer(player:FindFirstChildOfClass("Backpack"), itemId, afterCharacter)
	if afterBackpack > 0 then
		queueSuppressedToolImport(runtime, itemId, afterBackpack)
	end
end

function InventoryServiceServer.FlushPendingToolImports(_self: InventoryServiceServer, runtime: PlayerRuntime): boolean
	if not runtime.isLoaded then
		for key in runtime.pendingToolImports do
			runtime.pendingToolImports[key] = nil
		end
		return false
	end
	local changed = false
	for key, pending in runtime.pendingToolImports do
		if InventoryServiceUtils.countItem(runtime.state, pending.itemId, nil, false) <= 0 then
			local addResult = InventoryServiceUtils.addItem(runtime.state, pending.itemId, pending.amount, 1, {
				[TOOL_IMPORT_METADATA_TYPE_KEY] = pending.itemType,
			}, TOOL_IMPORT_STACK_ID_PREFIX)
			changed = changed or addResult.changed
		end
		runtime.pendingToolImports[key] = nil
	end
	return changed
end

function InventoryServiceServer.OnObservedTool(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	tool: Tool
)
	ToolBinder.applyTags(tool)
	if isManagedInventoryTool(tool) then
		return
	end
	local itemId, itemType = resolveToolImportData(tool)
	if itemId == nil or itemType == nil then
		return
	end
	if consumeSuppressedToolImport(runtime, itemId, 1) then
		tool:Destroy()
		return
	end
	if runtime.isLoading or not runtime.hasResolvedInitialLoad then
		queuePendingToolImport(runtime, itemId, itemType, 1)
		tool:Destroy()
		return
	end
	if not runtime.isLoaded then
		tool:Destroy()
		return
	end
	if InventoryServiceUtils.countItem(runtime.state, itemId, nil, false) <= 0 then
		local addResult = self:addItem(player, itemId, 1, {
			maxStack = 1,
			metadata = { [TOOL_IMPORT_METADATA_TYPE_KEY] = itemType },
			stackIdPrefix = TOOL_IMPORT_STACK_ID_PREFIX,
		})
		if addResult.added <= 0 then
			tool:Destroy()
		end
		return
	end
	self:syncSelectedTool(player, runtime, "observed_tool")
end

function InventoryServiceServer.ObserveToolContainer(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	janitor: JanitorClass,
	container: Instance
)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			self:onObservedTool(player, runtime, child)
		end
	end
	janitor:GiveChore(container.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:onObservedTool(player, runtime, child)
		end
	end))
end

function InventoryServiceServer.BindCharacter(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	character: Model
)
	runtime.characterJanitor:Clean()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid:UnequipTools()
	end
	self:observeToolContainer(player, runtime, runtime.characterJanitor, character)
	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			child:UnequipTools()
			self:syncSelectedTool(player, runtime, "humanoid_added")
		end
	end))
	self:syncSelectedTool(player, runtime, "character_bound")
end

function InventoryServiceServer.BindBackpack(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	backpack: Backpack
)
	self:observeToolContainer(player, runtime, runtime.playerJanitor, backpack)
	self:syncSelectedTool(player, runtime, "backpack_bound")
end

function InventoryServiceServer.TryPlaceDeployableFromTool(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	tool: Tool,
	requestedTileXRaw: any?,
	requestedTileYRaw: any?
): boolean
	local itemId = select(1, resolveToolImportData(tool))
	if itemId == nil then
		return false
	end
	return self:tryPlaceSelectedDeployable(player, runtime, itemId, requestedTileXRaw, requestedTileYRaw)
end

function InventoryServiceServer.TryPlaceSelectedDeployable(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	itemIdRaw: any,
	requestedTileXRaw: any?,
	requestedTileYRaw: any?
): boolean
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return false
	end
	local deployableConfig = resolveDeployableConfig(itemId)
	if deployableConfig == nil then
		return false
	end
	local selectedSlot = runtime.selectedSlot
	local selectedStack = if selectedSlot ~= nil
		then InventoryServiceUtils.getStack(runtime.state, selectedSlot)
		else nil
	if selectedSlot == nil or selectedStack == nil or sanitizeItemId(selectedStack.itemId) ~= itemId then
		return false
	end
	local primaryTemplate = ResolveItem.resolvePrimaryTemplate(itemId)
	if primaryTemplate == nil or primaryTemplate:IsA("Tool") then
		return false
	end
	local placedInstance = primaryTemplate:Clone()
	local primaryPart = resolveDeployablePrimaryPart(placedInstance)
	if primaryPart == nil then
		placedInstance:Destroy()
		return false
	end
	local placementProfile = sanitizeItemId((deployableConfig :: { [string]: any }).placementProfile)
	local placementCFrame = nil :: CFrame?
	local placedTileX = nil :: number?
	local placedTileY = nil :: number?
	local placedSupportKind = nil :: string?
	if placementProfile == "Torch" then
		local torchPlacement =
			resolveTorchDeployablePlacement(player, deployableConfig, placedInstance, requestedTileXRaw, requestedTileYRaw)
		if torchPlacement ~= nil then
			placementCFrame = torchPlacement.cframe
			placedTileX = torchPlacement.tileX
			placedTileY = torchPlacement.tileY
			placedSupportKind = torchPlacement.supportKind
		end
	else
		placementCFrame = resolveDeployablePlacementCFrame(player, deployableConfig, placedInstance)
	end
	if placementCFrame == nil then
		placedInstance:Destroy()
		return false
	end
	local removeResult = self:removeFromSlot(player, selectedSlot, 1)
	if removeResult.removedAmount <= 0 then
		placedInstance:Destroy()
		return false
	end
	setModelAnchored(placedInstance, true)
	if placedInstance:IsA("Model") then
		placedInstance:PivotTo(placementCFrame)
	else
		(placedInstance :: BasePart).CFrame = placementCFrame
	end
	local stationTag = sanitizeItemId((deployableConfig :: { [string]: any }).stationTag)
	if stationTag ~= nil then
		TagBinder.applyTag(placedInstance, stationTag, CollectionService)
	end
	if itemId == "Torch" then
		TagBinder.applyTag(placedInstance, TagBinder.Tags.Placeable_Torch, CollectionService)
	elseif itemId == "Workbench" then
		TagBinder.applyTag(placedInstance, TagBinder.Tags.Placeable_Workbench, CollectionService)
	else
		TagBinder.applyTag(placedInstance, TagBinder.Tags.Placeable, CollectionService)
	end
	placedInstance:SetAttribute(DEPLOYABLE_PLACED_ATTRIBUTE_NAME, itemId)
	if placedTileX ~= nil and placedTileY ~= nil then
		placedInstance:SetAttribute(DEPLOYABLE_TILE_X_ATTRIBUTE_NAME, placedTileX)
		placedInstance:SetAttribute(DEPLOYABLE_TILE_Y_ATTRIBUTE_NAME, placedTileY)
	end
	if placedSupportKind ~= nil then
		placedInstance:SetAttribute(DEPLOYABLE_SUPPORT_KIND_ATTRIBUTE_NAME, placedSupportKind)
	end
	placedInstance.Parent = Workspace
	return true
end

function InventoryServiceServer.Init(self: InventoryServiceServer)
	self.networker = Networker.server.new("InventoryService", self, {
		self.RequestSync,
		self.RequestSetSelectedSlot,
		self.RequestMoveSlot,
		self.RequestSplitSlot,
		self.RequestDropFromSlot,
		self.RequestTrashSlot,
		self.RequestTrashSelectedSlot,
		self.RequestUseSelectedSlot,
		self.RequestPlaceSelectedDeployable,
	})
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.persistence = InventoryProfile.new(self.playerDataService, {
		dataPath = InventoryServiceUtils.getDefaultDataPath(),
		primaryTimeoutSeconds = PRIMARY_PERSISTENCE_TIMEOUT_SECONDS,
		fallbackTimeoutSeconds = FALLBACK_PERSISTENCE_TIMEOUT_SECONDS,
	}) :: InventoryProfileObject
	self.playerRuntimesByUserId = {}
	self.didWarnMissingDropHandler = false
	self.dropFromSlotHandler = nil

	for _, player in Players:GetPlayers() do
		self:trackPlayer(player)
	end
	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:trackPlayer(player)
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)
end

function InventoryServiceServer.ReadInventoryDataFromPlayerData(
	self: InventoryServiceServer,
	player: Player
): (any, string)
	local defaultInventoryData = self.persistence:cloneDefaultInventoryData()
	local playerDataService = self.playerDataService
	if playerDataService == nil then
		return defaultInventoryData, "player_data_service_missing"
	end

	local readSuccess, readResult = pcall(function()
		return playerDataService:getValue(player, self:getInventoryDataPath(), defaultInventoryData)
	end)
	if not readSuccess then
		return defaultInventoryData, "player_data_read_error:" .. tostring(readResult)
	end
	if typeof(readResult) ~= "table" then
		return defaultInventoryData, "player_data_inventory_not_table"
	end
	return readResult, "player_data_value"
end

function InventoryServiceServer.FinalizeInitialLoad(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	loadToken: number,
	nextStateRaw: any,
	resolvedSourceRaw: any,
	failureReasonRaw: any?
): boolean
	if runtime.loadToken ~= loadToken or self.playerRuntimesByUserId[player.UserId] ~= runtime then
		return false
	end

	applyRuntimeState(runtime, nextStateRaw)
	runtime.isLoading = false
	runtime.hasResolvedInitialLoad = true
	runtime.lastFailureReason = sanitizeFailureReason(failureReasonRaw)
	runtime.resolvedSource = if typeof(resolvedSourceRaw) == "string" then resolvedSourceRaw else runtime.resolvedSource
	local importedPending = self:flushPendingToolImports(runtime)
	if importedPending and runtime.isLoaded then
		self:markRuntimeDirty(player, runtime, "pending_tool_imports")
		self:stagePersistedState(player, runtime, "pending_tool_imports")
	end
	local syncOk, syncErr = pcall(function()
		self:syncSelectedTool(player, runtime, "initial_load")
	end)
	if not syncOk then
		self:logEvent("tool_sync_fail", player, runtime, { trigger = "initial_load", reason = tostring(syncErr) })
	end
	self:replicateRuntimeState(player, runtime, "initial_load", true)
	if importedPending and runtime.isLoaded then
		self:queueSave(player, runtime, "pending_tool_imports")
	end
	return true
end

function InventoryServiceServer.LoadPlayerInventory(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	loadToken: number
)
	local playerDataService = self.playerDataService
	if playerDataService == nil then
		local failedState = InventoryServiceUtils.createStateFromData(
			self.persistence:cloneDefaultInventoryData(),
			runtime.state,
			InventoryServiceUtils.LOAD_STATE_FAILED
		)
		if
			self:finalizeInitialLoad(player, runtime, loadToken, failedState, "default", "player_data_service_missing")
		then
			self:logEvent("load_resolved_default_failure", player, runtime, {
				reason = "player_data_service_missing",
			})
		end
		return
	end

	local function resolveLoadedState(resolveReasonRaw: any, playerDataLoadStateRaw: any)
		local inventoryData, inventoryReason = self:readInventoryDataFromPlayerData(player)
		local nextState = InventoryServiceUtils.createStateFromData(
			inventoryData,
			runtime.state,
			InventoryServiceUtils.LOAD_STATE_LOADED
		)
		if self:finalizeInitialLoad(player, runtime, loadToken, nextState, "player_data", nil) then
			self:logEvent("load_resolved_from_player_data", player, runtime, {
				playerDataLoadState = playerDataLoadStateRaw,
				reason = resolveReasonRaw,
				readReason = inventoryReason,
			})
		end
	end

	local loadStateSuccess, loadStateResult = pcall(function()
		return playerDataService:getLoadState(player)
	end)
	local playerDataLoadState = if loadStateSuccess
		then loadStateResult
		else "load_state_error:" .. tostring(loadStateResult)
	if loadStateSuccess and loadStateResult == PlayerDataServiceUtils.LOAD_STATE_LOADED then
		resolveLoadedState("player_data_already_loaded", loadStateResult)
		return
	end
	if loadStateSuccess and loadStateResult == PlayerDataServiceUtils.LOAD_STATE_FAILED then
		local failedState = InventoryServiceUtils.createStateFromData(
			self.persistence:cloneDefaultInventoryData(),
			runtime.state,
			InventoryServiceUtils.LOAD_STATE_FAILED
		)
		if self:finalizeInitialLoad(player, runtime, loadToken, failedState, "default", "player_data_failed") then
			self:logEvent("load_resolved_default_failure", player, runtime, {
				reason = "player_data_failed",
				playerDataLoadState = loadStateResult,
			})
		end
		return
	end

	pcall(function()
		playerDataService:requestSync(player)
	end)
	self:logEvent("load_waiting_for_player_data", player, runtime, {
		playerDataLoadState = playerDataLoadState,
		timeoutSeconds = PLAYER_DATA_SETTLE_TIMEOUT_SECONDS,
	})
	local waitSuccess, waitResult = pcall(function()
		return playerDataService:waitForData(player, PLAYER_DATA_SETTLE_TIMEOUT_SECONDS)
	end)
	if runtime.loadToken ~= loadToken or self.playerRuntimesByUserId[player.UserId] ~= runtime then
		return
	end

	loadStateSuccess, loadStateResult = pcall(function()
		return playerDataService:getLoadState(player)
	end)
	playerDataLoadState = if loadStateSuccess then loadStateResult else "load_state_error:" .. tostring(loadStateResult)
	if loadStateSuccess and loadStateResult == PlayerDataServiceUtils.LOAD_STATE_LOADED then
		resolveLoadedState(
			if waitSuccess then "player_data_wait_resolved" else "player_data_wait_error_resolved",
			loadStateResult
		)
		return
	end

	local failureReason = if waitSuccess
		then "player_data_timeout:" .. tostring(playerDataLoadState)
		else "player_data_wait_error:" .. tostring(waitResult)
	if loadStateSuccess and loadStateResult == PlayerDataServiceUtils.LOAD_STATE_FAILED then
		failureReason = "player_data_failed"
	end
	local failedState = InventoryServiceUtils.createStateFromData(
		self.persistence:cloneDefaultInventoryData(),
		runtime.state,
		InventoryServiceUtils.LOAD_STATE_FAILED
	)
	if self:finalizeInitialLoad(player, runtime, loadToken, failedState, "default", failureReason) then
		self:logEvent("load_resolved_default_failure", player, runtime, {
			reason = failureReason,
			playerDataLoadState = playerDataLoadState,
		})
		if not waitSuccess then
			self:logEvent("load_wait_error", player, runtime, { reason = tostring(waitResult) })
		end
	end
end

function InventoryServiceServer.TrackPlayer(self: InventoryServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	if runtime ~= nil then
		runtime.player = player
		self:logEvent("trackPlayer_start", player, runtime, { reusedRuntime = true })
		self:replicateRuntimeState(player, runtime, "track_player_reused", true)
		return
	end

	runtime = self:createRuntime(player)
	self.playerRuntimesByUserId[player.UserId] = runtime
	runtime.joinToken += 1
	runtime.loadToken += 1
	runtime.isLoading = true
	runtime.hasResolvedInitialLoad = false
	runtime.isLoaded = false
	runtime.isDirty = false
	runtime.isSaving = false
	runtime.saveQueued = false
	runtime.resolvedSource = "loading"
	runtime.lastFailureReason = nil
	runtime.loadStartedAt = os.clock()
	runtime.lastReplicatedStateHash = nil
	runtime.saveDebounceToken += 1
	runtime.lastSavedRevision = 0
	runtime.lastStagedRevision = 0
	runtime.revision = 0
	runtime.pendingToolImports = {}
	runtime.suppressedToolImports = {}
	runtime.playerJanitor:Clean()
	runtime.characterJanitor:Clean()
	runtime.toolSyncJanitor:Clean()
	applyRuntimeState(
		runtime,
		InventoryServiceUtils.createStateFromData(
			self.persistence:cloneDefaultInventoryData(),
			runtime.state,
			InventoryServiceUtils.LOAD_STATE_LOADING
		)
	)
	self:logEvent("trackPlayer_start", player, runtime, nil)
	self:replicateRuntimeState(player, runtime, "track_player", true)
	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:bindCharacter(player, runtime, character)
	end))
	runtime.playerJanitor:GiveChore(player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			self:bindBackpack(player, runtime, child)
		end
	end))
	if player.Character ~= nil then
		self:bindCharacter(player, runtime, player.Character)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		self:bindBackpack(player, runtime, backpack)
	end
	local loadToken = runtime.loadToken
	task.spawn(function()
		self:loadPlayerInventory(player, runtime, loadToken)
	end)
end

function InventoryServiceServer.UntrackPlayer(self: InventoryServiceServer, player: Player)
	local runtime = self.playerRuntimesByUserId[player.UserId]
	if runtime == nil then
		return
	end
	runtime.player = player
	if runtime.isDirty then
		self:stagePersistedState(player, runtime, "player_removing")
	end
	self:performSave(player, runtime, runtime.saveDebounceToken, "player_removing")
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	runtime.toolSyncJanitor:Destroy()
	self.playerRuntimesByUserId[player.UserId] = nil
end

function InventoryServiceServer.RequestSync(self: InventoryServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	if runtime == nil then
		self:trackPlayer(player)
		return
	end
	runtime.player = player
	self:logEvent("requestSync_reused_runtime", player, runtime, { runtimeExists = true })
	self:replicateRuntimeState(player, runtime, "request_sync", true)
end
function InventoryServiceServer.RequestSetSelectedSlot(self: InventoryServiceServer, player: Player, slotIndexRaw: any)
	self:setSelectedSlot(player, slotIndexRaw)
end
function InventoryServiceServer.RequestMoveSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
)
	self:moveSlot(player, fromSlotRaw, toSlotRaw, amountRaw)
end
function InventoryServiceServer.RequestSplitSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
)
	self:splitSlot(player, fromSlotRaw, toSlotRaw, amountRaw)
end
function InventoryServiceServer.RequestDropFromSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	self:dropFromSlot(player, slotIndexRaw, amountRaw, throwDirectionRaw)
end
function InventoryServiceServer.RequestTrashSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any
)
	self:trashSlot(player, slotIndexRaw, amountRaw)
end
function InventoryServiceServer.RequestTrashSelectedSlot(self: InventoryServiceServer, player: Player, amountRaw: any)
	self:trashSelectedSlot(player, amountRaw)
end
function InventoryServiceServer.RequestUseSelectedSlot(self: InventoryServiceServer, player: Player, amountRaw: any)
	self:useSelectedSlot(player, amountRaw)
end

function InventoryServiceServer.RequestPlaceSelectedDeployable(
	self: InventoryServiceServer,
	player: Player,
	tileXRaw: any,
	tileYRaw: any
)
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return
	end
	local selectedSlot = runtime.selectedSlot
	local selectedStack = if selectedSlot ~= nil
		then InventoryServiceUtils.getStack(runtime.state, selectedSlot)
		else nil
	if selectedSlot == nil or selectedStack == nil then
		return
	end

	local itemId = sanitizeItemId(selectedStack.itemId)
	if itemId == nil or resolveDeployableConfig(itemId) == nil then
		return
	end

	self:tryPlaceSelectedDeployable(player, runtime, itemId, tileXRaw, tileYRaw)
end

function InventoryServiceServer.SetDropFromSlotHandler(self: InventoryServiceServer, handlerRaw: any)
	self.dropFromSlotHandler = if typeof(handlerRaw) == "function" then handlerRaw else nil
	self.didWarnMissingDropHandler = false
end

function InventoryServiceServer.GetState(self: InventoryServiceServer, player: Player): InventoryState
	local runtime = self.playerRuntimesByUserId[player.UserId]
	if runtime ~= nil then
		return runtime.state
	end
	return InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
end

function InventoryServiceServer.GetStateCopy(self: InventoryServiceServer, player: Player): InventoryState
	return InventoryServiceUtils.cloneState(self:getState(player))
end

function InventoryServiceServer.SetSelectedSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any
): boolean
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return false
	end
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local changed = InventoryServiceUtils.setSelectedSlot(nextState, slotIndexRaw)
	if changed then
		self:commitState(player, runtime, nextState, "set_selected_slot", nil)
	else
		self:syncSelectedTool(player, runtime, "set_selected_slot_unchanged")
	end
	return changed
end

function InventoryServiceServer.AddItem(
	self: InventoryServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any,
	optionsRaw: any
): AddItemResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptyAddItemResult()
	end
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.addItem(
		nextState,
		itemIdRaw,
		amountRaw,
		options.maxStack,
		options.metadata,
		options.stackIdPrefix
	)
	if result.changed then
		self:commitState(player, runtime, nextState, "add_item", nil)
	end
	return result
end

function InventoryServiceServer.RemoveItem(
	self: InventoryServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any,
	optionsRaw: any
): RemoveItemResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptyRemoveItemResult()
	end
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.removeItem(
		nextState,
		itemIdRaw,
		amountRaw,
		options.metadata,
		options.requireExactMetadata
	)
	if result.changed then
		self:commitState(player, runtime, nextState, "remove_item", function()
			self:suppressAndPurgePlayerTools(runtime, player, itemIdRaw, result.removed)
		end)
	end
	return result
end

function InventoryServiceServer.RemoveFromSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptySlotMutationResult()
	end
	local existingStack = InventoryServiceUtils.getStack(runtime.state, slotIndexRaw)
	local itemId = if existingStack ~= nil then existingStack.itemId else nil
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.removeFromSlot(nextState, slotIndexRaw, amountRaw)
	if result.changed then
		self:commitState(player, runtime, nextState, "remove_from_slot", function()
			if itemId ~= nil then
				self:suppressAndPurgePlayerTools(runtime, player, itemId, result.removedAmount)
			end
		end)
	end
	return result
end

function InventoryServiceServer.MoveSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptySlotMutationResult()
	end
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.moveSlot(nextState, fromSlotRaw, toSlotRaw, amountRaw)
	if result.changed then
		self:commitState(player, runtime, nextState, "move_slot", nil)
	end
	return result
end

function InventoryServiceServer.SplitSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptySlotMutationResult()
	end
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.splitSlot(nextState, fromSlotRaw, toSlotRaw, amountRaw)
	if result.changed then
		self:commitState(player, runtime, nextState, "split_slot", nil)
	end
	return result
end

function InventoryServiceServer.UseSelectedSlot(
	self: InventoryServiceServer,
	player: Player,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptySlotMutationResult()
	end
	local selectedStack = if runtime.selectedSlot ~= nil
		then InventoryServiceUtils.getStack(runtime.state, runtime.selectedSlot)
		else nil
	local itemId = if selectedStack ~= nil then selectedStack.itemId else nil
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.consumeSelected(nextState, amountRaw)
	if result.changed then
		self:commitState(player, runtime, nextState, "use_selected_slot", function()
			if itemId ~= nil then
				self:suppressAndPurgePlayerTools(runtime, player, itemId, result.removedAmount)
			end
		end)
	end
	return result
end

function InventoryServiceServer.DropFromSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
): SlotMutationResult
	local unchanged = createEmptySlotMutationResult()
	local handler = self.dropFromSlotHandler
	if handler ~= nil then
		local ok, handled = pcall(handler, player, slotIndexRaw, amountRaw, throwDirectionRaw)
		if ok and handled ~= false and handled ~= nil then
			return {
				changed = true,
				touchedSlots = {},
				fromSlot = nil,
				toSlot = nil,
				movedAmount = 0,
				removedAmount = 0,
				swapped = false,
			}
		end
		return unchanged
	end
	if self.didWarnMissingDropHandler ~= true then
		self.didWarnMissingDropHandler = true
	end
	return unchanged
end

function InventoryServiceServer.ReleaseSuppressedToolImport(
	self: InventoryServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any
): number
	local runtime = self:getRuntime(player)
	if runtime == nil then
		return 0
	end
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return 0
	end
	local amount = normalizeImportAmount(amountRaw)
	local current = runtime.suppressedToolImports[itemId] or 0
	if current <= 0 then
		return 0
	end
	local released = math.min(current, amount)
	local remaining = current - released
	runtime.suppressedToolImports[itemId] = if remaining > 0 then remaining else nil
	return released
end

function InventoryServiceServer.TrashSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptySlotMutationResult()
	end
	local existingStack = InventoryServiceUtils.getStack(runtime.state, slotIndexRaw)
	local itemId = if existingStack ~= nil then existingStack.itemId else nil
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.trashSlot(nextState, slotIndexRaw, amountRaw)
	if result.changed then
		self:commitState(player, runtime, nextState, "trash_slot", function()
			if itemId ~= nil then
				self:suppressAndPurgePlayerTools(runtime, player, itemId, result.removedAmount)
			end
		end)
	end
	return result
end

function InventoryServiceServer.TrashSelectedSlot(
	self: InventoryServiceServer,
	player: Player,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return createEmptySlotMutationResult()
	end
	local selectedStack = if runtime.selectedSlot ~= nil
		then InventoryServiceUtils.getStack(runtime.state, runtime.selectedSlot)
		else nil
	local itemId = if selectedStack ~= nil then selectedStack.itemId else nil
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local result = InventoryServiceUtils.trashSelected(nextState, amountRaw)
	if result.changed then
		self:commitState(player, runtime, nextState, "trash_selected_slot", function()
			if itemId ~= nil then
				self:suppressAndPurgePlayerTools(runtime, player, itemId, result.removedAmount)
			end
		end)
	end
	return result
end

function InventoryServiceServer.CountItem(
	self: InventoryServiceServer,
	player: Player,
	itemIdRaw: any,
	metadataRaw: any,
	requireExactMetadataRaw: any
): number
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return 0
	end
	return InventoryServiceUtils.countItem(runtime.state, itemIdRaw, metadataRaw, requireExactMetadataRaw)
end

function InventoryServiceServer.ClearInventory(self: InventoryServiceServer, player: Player): boolean
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return false
	end
	local nextState = InventoryServiceUtils.cloneState(runtime.state)
	local changed = InventoryServiceUtils.clear(nextState)
	if changed then
		self:commitState(player, runtime, nextState, "clear_inventory", nil)
	end
	return changed
end

function InventoryServiceServer.Destroy(self: InventoryServiceServer)
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
	for userId, runtime in self.playerRuntimesByUserId do
		local player = runtime.player
		if player ~= nil then
			if runtime.isDirty then
				self:stagePersistedState(player, runtime, "destroy")
			end
			self:performSave(player, runtime, runtime.saveDebounceToken, "destroy")
		end
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		runtime.toolSyncJanitor:Destroy()
		self.playerRuntimesByUserId[userId] = nil
	end
	if self.networker ~= nil then
		self.networker:destroy()
	end
end

InventoryServiceServer.logEvent = InventoryServiceServer.LogEvent
InventoryServiceServer.getInventoryDataPath = InventoryServiceServer.GetInventoryDataPath
InventoryServiceServer.getInventoryDataPathString = InventoryServiceServer.GetInventoryDataPathString
InventoryServiceServer.markRuntimeDirty = InventoryServiceServer.MarkRuntimeDirty
InventoryServiceServer.stagePersistedState = InventoryServiceServer.StagePersistedState
InventoryServiceServer.createRuntime = InventoryServiceServer.CreateRuntime
InventoryServiceServer.getRuntime = InventoryServiceServer.GetRuntime
InventoryServiceServer.getOrCreateRuntime = InventoryServiceServer.GetOrCreateRuntime
InventoryServiceServer.getLoadedRuntime = InventoryServiceServer.GetLoadedRuntime
InventoryServiceServer.replicateRuntimeState = InventoryServiceServer.ReplicateRuntimeState
InventoryServiceServer.scheduleSaveAttempt = InventoryServiceServer.ScheduleSaveAttempt
InventoryServiceServer.runQueuedSaveRerun = InventoryServiceServer.RunQueuedSaveRerun
InventoryServiceServer.canPersistRuntime = InventoryServiceServer.CanPersistRuntime
InventoryServiceServer.performSave = InventoryServiceServer.PerformSave
InventoryServiceServer.queueSave = InventoryServiceServer.QueueSave
InventoryServiceServer.commitState = InventoryServiceServer.CommitState
InventoryServiceServer.findMatchingTool = InventoryServiceServer.FindMatchingTool
InventoryServiceServer.syncSelectedTool = InventoryServiceServer.SyncSelectedTool
InventoryServiceServer.suppressAndPurgePlayerTools = InventoryServiceServer.SuppressAndPurgePlayerTools
InventoryServiceServer.flushPendingToolImports = InventoryServiceServer.FlushPendingToolImports
InventoryServiceServer.onObservedTool = InventoryServiceServer.OnObservedTool
InventoryServiceServer.observeToolContainer = InventoryServiceServer.ObserveToolContainer
InventoryServiceServer.bindCharacter = InventoryServiceServer.BindCharacter
InventoryServiceServer.bindBackpack = InventoryServiceServer.BindBackpack
InventoryServiceServer.tryPlaceDeployableFromTool = InventoryServiceServer.TryPlaceDeployableFromTool
InventoryServiceServer.tryPlaceSelectedDeployable = InventoryServiceServer.TryPlaceSelectedDeployable
InventoryServiceServer.init = InventoryServiceServer.Init
InventoryServiceServer.readInventoryDataFromPlayerData = InventoryServiceServer.ReadInventoryDataFromPlayerData
InventoryServiceServer.finalizeInitialLoad = InventoryServiceServer.FinalizeInitialLoad
InventoryServiceServer.loadPlayerInventory = InventoryServiceServer.LoadPlayerInventory
InventoryServiceServer.trackPlayer = InventoryServiceServer.TrackPlayer
InventoryServiceServer.untrackPlayer = InventoryServiceServer.UntrackPlayer
InventoryServiceServer.requestSync = InventoryServiceServer.RequestSync
InventoryServiceServer.requestSetSelectedSlot = InventoryServiceServer.RequestSetSelectedSlot
InventoryServiceServer.requestMoveSlot = InventoryServiceServer.RequestMoveSlot
InventoryServiceServer.requestSplitSlot = InventoryServiceServer.RequestSplitSlot
InventoryServiceServer.requestDropFromSlot = InventoryServiceServer.RequestDropFromSlot
InventoryServiceServer.requestTrashSlot = InventoryServiceServer.RequestTrashSlot
InventoryServiceServer.requestTrashSelectedSlot = InventoryServiceServer.RequestTrashSelectedSlot
InventoryServiceServer.requestUseSelectedSlot = InventoryServiceServer.RequestUseSelectedSlot
InventoryServiceServer.requestPlaceSelectedDeployable = InventoryServiceServer.RequestPlaceSelectedDeployable
InventoryServiceServer.setDropFromSlotHandler = InventoryServiceServer.SetDropFromSlotHandler
InventoryServiceServer.getState = InventoryServiceServer.GetState
InventoryServiceServer.getStateCopy = InventoryServiceServer.GetStateCopy
InventoryServiceServer.setSelectedSlot = InventoryServiceServer.SetSelectedSlot
InventoryServiceServer.addItem = InventoryServiceServer.AddItem
InventoryServiceServer.removeItem = InventoryServiceServer.RemoveItem
InventoryServiceServer.removeFromSlot = InventoryServiceServer.RemoveFromSlot
InventoryServiceServer.moveSlot = InventoryServiceServer.MoveSlot
InventoryServiceServer.splitSlot = InventoryServiceServer.SplitSlot
InventoryServiceServer.useSelectedSlot = InventoryServiceServer.UseSelectedSlot
InventoryServiceServer.dropFromSlot = InventoryServiceServer.DropFromSlot
InventoryServiceServer.releaseSuppressedToolImport = InventoryServiceServer.ReleaseSuppressedToolImport
InventoryServiceServer.trashSlot = InventoryServiceServer.TrashSlot
InventoryServiceServer.trashSelectedSlot = InventoryServiceServer.TrashSelectedSlot
InventoryServiceServer.countItem = InventoryServiceServer.CountItem
InventoryServiceServer.clearInventory = InventoryServiceServer.ClearInventory
InventoryServiceServer.destroy = InventoryServiceServer.Destroy

type InventoryServiceServer = typeof(InventoryServiceServer) & {
	networker: Networker.Server,
	playerDataService: PlayerDataServiceServerObject,
	persistence: InventoryProfileObject,
	playerRuntimesByUserId: { [number]: PlayerRuntime },
	dropFromSlotHandler: ((player: Player, slotIndexRaw: any, amountRaw: any, throwDirectionRaw: any) -> any)?,
	didWarnMissingDropHandler: boolean,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return InventoryServiceServer :: InventoryServiceServer

