--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ItemRegistry = require(ReplicatedStorage.Shared.Modules.Items.Registry)
local ResolveItem = require(ReplicatedStorage.Shared.Modules.Game.ResolveItem)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local PlayerDataServiceServer = require(ServerScriptService.Services.PlayerDataService.PlayerDataServiceServer)

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
	waitForData: (self: PlayerDataServiceServerObject, player: Player, timeoutSecondsRaw: any) -> any,
	getValue: (self: PlayerDataServiceServerObject, player: Player, pathRaw: any, fallback: any) -> any,
	setValue: (
		self: PlayerDataServiceServerObject,
		player: Player,
		pathRaw: any,
		value: any,
		replicateToClientRaw: any
	) -> boolean,
}

type PendingToolImport = {
	itemId: string,
	itemType: string,
	amount: number,
}

type PlayerRuntime = {
	state: InventoryState,
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
	loadToken: number,
	pendingToolImports: { [string]: PendingToolImport },
	suppressedToolImports: { [string]: number },
}

local InventoryServiceServer = {}

local DEFAULT_DATA_LOAD_TIMEOUT_SECONDS = 20
local TOOL_IMPORT_ATTRIBUTE_NAME = "itemId"
local TOOL_IMPORT_TYPE_ATTRIBUTE_NAME = "itemType"
local TOOL_IMPORT_STACK_ID_PREFIX = "tool"
local TOOL_IMPORT_METADATA_TYPE_KEY = "itemType"
local DEPLOYABLE_PLACED_ATTRIBUTE_NAME = "PlacedItemId"
local boundToolConnections = {} :: { [Tool]: { RBXScriptConnection } }
local resolveToolImportData: (tool: Tool) -> (string?, string?)
local suppressAndPurgePlayerTools: (runtime: PlayerRuntime, player: Player, itemIdRaw: any, amountRaw: any) -> ()

local function trim(textRaw: any): string
	if typeof(textRaw) ~= "string" then
		return ""
	end
	return string.match(textRaw, "^%s*(.-)%s*$") or ""
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

local function queuePendingToolImport(runtime: PlayerRuntime, itemId: string, itemType: string, amountRaw: any)
	local amount = normalizeImportAmount(amountRaw)
	local pendingKey = ("%s::%s"):format(itemId, itemType)
	local existing = runtime.pendingToolImports[pendingKey]
	if existing == nil then
		runtime.pendingToolImports[pendingKey] = {
			itemId = itemId,
			itemType = itemType,
			amount = amount,
		}
		return
	end

	existing.amount += amount
end

local function queueSuppressedToolImport(runtime: PlayerRuntime, itemIdRaw: any, amountRaw: any)
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return
	end
	local amount = normalizeImportAmount(amountRaw)
	if amount <= 0 then
		return
	end
	local current = runtime.suppressedToolImports[itemId] or 0
	runtime.suppressedToolImports[itemId] = current + amount
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
	if remaining > 0 then
		runtime.suppressedToolImports[itemId] = remaining
	else
		runtime.suppressedToolImports[itemId] = nil
	end
	return true
end

local function resolveItemIdLookup(): { [string]: string }
	return ItemRegistry.getItemIdLookup()
end

local function resolveItemTypeForStack(stackRaw: any): string?
	if typeof(stackRaw) ~= "table" then
		return nil
	end

	local stack = stackRaw :: { [string]: any }
	local metadata = if typeof(stack.metadata) == "table" then (stack.metadata :: { [string]: any }) else nil
	local metadataItemType = if metadata ~= nil then sanitizeItemId(metadata[TOOL_IMPORT_METADATA_TYPE_KEY]) else nil
	if metadataItemType ~= nil then
		return metadataItemType
	end

	local definition = ItemRegistry.resolveDefinition(stack.itemId)
	if typeof(definition) == "table" then
		local definitionTable = definition :: { [string]: any }
		local definitionItemType = sanitizeItemId(definitionTable.itemType) or sanitizeItemId(definitionTable.type)
		if definitionItemType ~= nil then
			return definitionItemType
		end
	end

	return sanitizeItemId(stack.itemId)
end

local function cloneToolForInventoryStack(itemIdRaw: any, stackRaw: any): Tool?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local clone = ResolveItem.cloneToolTemplate(itemId)
	if clone == nil then
		return nil
	end

	clone:SetAttribute(TOOL_IMPORT_ATTRIBUTE_NAME, itemId)
	clone:SetAttribute("ItemId", itemId)

	local itemType = resolveItemTypeForStack(stackRaw)
	if itemType ~= nil then
		clone:SetAttribute(TOOL_IMPORT_TYPE_ATTRIBUTE_NAME, itemType)
		clone:SetAttribute("ItemType", itemType)
	end

	return clone
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

	local stationTag = sanitizeItemId((deployable :: { [string]: any }).stationTag)
	if stationTag == nil then
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

		local descendantPart = instance:FindFirstChildWhichIsA("BasePart", true)
		if descendantPart ~= nil then
			instance.PrimaryPart = descendantPart
			return descendantPart
		end
	end

	return nil
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

local function cleanupBoundTool(tool: Tool)
	local connections = boundToolConnections[tool]
	if connections == nil then
		return
	end
	boundToolConnections[tool] = nil
	for _, connection in connections do
		connection:Disconnect()
	end
end

local function resolveHorizontalLookVector(rootPart: BasePart): Vector3
	local lookVector = rootPart.CFrame.LookVector
	local flattened = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flattened.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return flattened.Unit
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

	local rootPart = character.PrimaryPart
	if rootPart == nil then
		rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	if rootPart == nil then
		return nil
	end

	local lookVector = resolveHorizontalLookVector(rootPart)
	local placementDistance = sanitizeNumber(deployableConfig.placementDistance, 6, 2)
	local maxPlacementDistance = sanitizeNumber(deployableConfig.maxPlacementDistance, placementDistance + 4, placementDistance)
	local castOrigin = rootPart.Position + Vector3.new(0, 4, 0)
	local castDirection = lookVector * math.min(placementDistance, maxPlacementDistance)
	local desiredPosition = castOrigin + castDirection

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, placedInstance }

	local groundRayResult = Workspace:Raycast(desiredPosition + Vector3.new(0, 12, 0), Vector3.new(0, -32, 0), raycastParams)
	local groundPosition = if groundRayResult ~= nil then groundRayResult.Position else desiredPosition

	local boundingCFrame: CFrame
	local boundingSize: Vector3
	if placedInstance:IsA("Model") then
		boundingCFrame, boundingSize = placedInstance:GetBoundingBox()
	else
		local placedPart = placedInstance :: BasePart
		boundingCFrame = placedPart.CFrame
		boundingSize = placedPart.Size
	end
	local bottomOffset = math.max(0, boundingSize.Y * 0.5)
	local yaw = math.atan2(-lookVector.X, -lookVector.Z)
	local targetPosition = Vector3.new(groundPosition.X, groundPosition.Y + bottomOffset, groundPosition.Z)

	return CFrame.new(targetPosition) * CFrame.Angles(0, yaw, 0) * boundingCFrame.Rotation
end

function InventoryServiceServer.tryPlaceDeployableFromTool(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	tool: Tool
): boolean
	local itemId = sanitizeItemId(tool:GetAttribute(TOOL_IMPORT_ATTRIBUTE_NAME))
	if itemId == nil then
		itemId = sanitizeItemId(tool:GetAttribute("ItemId"))
	end
	if itemId == nil then
		return false
	end

	local deployableConfig = resolveDeployableConfig(itemId)
	if deployableConfig == nil then
		return false
	end

	local selectedSlot = runtime.state.selectedSlot
	local selectedStack = if selectedSlot ~= nil then InventoryServiceUtils.getStack(runtime.state, selectedSlot) else nil
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

	local placementCFrame = resolveDeployablePlacementCFrame(player, deployableConfig, placedInstance)
	if placementCFrame == nil then
		placedInstance:Destroy()
		return false
	end

	local mutation = InventoryServiceUtils.removeFromSlot(runtime.state, selectedSlot, 1)
	if not mutation.changed or mutation.removedAmount <= 0 then
		placedInstance:Destroy()
		return false
	end

	setModelAnchored(placedInstance, true)
	if placedInstance:IsA("Model") then
		placedInstance:PivotTo(placementCFrame)
	else
		(placedInstance :: BasePart).CFrame = placementCFrame
	end

	local stationTag = sanitizeItemId(deployableConfig.stationTag)
	if stationTag ~= nil then
		CollectionService:AddTag(placedInstance, stationTag)
	end
	placedInstance:SetAttribute(DEPLOYABLE_PLACED_ATTRIBUTE_NAME, itemId)
	placedInstance.Parent = Workspace

	suppressAndPurgePlayerTools(runtime, player, itemId, mutation.removedAmount)
	self:pushAndPersistState(player, runtime)
	return true
end

function InventoryServiceServer.bindToolInteractions(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	tool: Tool
)
	if boundToolConnections[tool] ~= nil then
		return
	end

	local itemId = resolveToolImportData(tool)
	if resolveDeployableConfig(itemId) == nil then
		return
	end

	local connections = {} :: { RBXScriptConnection }
	boundToolConnections[tool] = connections
	connections[#connections + 1] = tool.Activated:Connect(function()
		self:tryPlaceDeployableFromTool(player, runtime, tool)
	end)
	connections[#connections + 1] = tool.Destroying:Connect(function()
		cleanupBoundTool(tool)
	end)
end

resolveToolImportData = function(tool: Tool): (string?, string?)
	local itemId = sanitizeItemId(tool:GetAttribute(TOOL_IMPORT_ATTRIBUTE_NAME))
	local itemType = sanitizeItemId(tool:GetAttribute(TOOL_IMPORT_TYPE_ATTRIBUTE_NAME))

	if itemId == nil then
		itemId = sanitizeItemId(tool:GetAttribute("ItemId"))
	end
	if itemId == nil then
		itemId = sanitizeItemId(tool:GetAttribute("ittemId"))
	end
	if itemType == nil then
		itemType = sanitizeItemId(tool:GetAttribute("ItemType"))
	end

	if itemId == nil then
		itemId = sanitizeItemId(tool.Name)
	end
	if itemType == nil then
		itemType = sanitizeItemId(tool.Name)
	end

	if itemId == nil then
		return nil, nil
	end
	if itemType == nil then
		return nil, nil
	end

	local itemIdLookup = resolveItemIdLookup()
	local canonicalItemId = itemIdLookup[itemId]
	if canonicalItemId == nil then
		canonicalItemId = itemIdLookup[string.lower(itemId)]
	end
	if canonicalItemId == nil then
		return nil, nil
	end

	return canonicalItemId, itemType
end

local function destroyMatchingToolsInContainer(container: Instance?, itemId: string, maxDestroyRaw: any): number
	if container == nil then
		return 0
	end
	if maxDestroyRaw == nil then
		return 0
	end
	if typeof(maxDestroyRaw) ~= "number" or maxDestroyRaw ~= maxDestroyRaw then
		return 0
	end

	local remaining = math.max(0, math.floor(maxDestroyRaw))
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
		local toolItemId = resolveToolImportData(child)
		if toolItemId ~= itemId then
			continue
		end
		child:Destroy()
		destroyed += 1
	end

	return destroyed
end

suppressAndPurgePlayerTools = function(runtime: PlayerRuntime, player: Player, itemIdRaw: any, amountRaw: any)
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return
	end
	if typeof(amountRaw) ~= "number" or amountRaw ~= amountRaw then
		return
	end

	local remainingToSuppress = math.max(0, math.floor(amountRaw))
	if remainingToSuppress <= 0 then
		return
	end

	local character = player.Character
	if character ~= nil then
		remainingToSuppress -= destroyMatchingToolsInContainer(character, itemId, remainingToSuppress)
	end

	if remainingToSuppress > 0 then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack ~= nil then
			remainingToSuppress -= destroyMatchingToolsInContainer(backpack, itemId, remainingToSuppress)
		end
	end

	if remainingToSuppress > 0 then
		queueSuppressedToolImport(runtime, itemId, remainingToSuppress)
	end
end

local function findMatchingToolInContainer(container: Instance?, itemIdRaw: any): Tool?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end
	if container == nil then
		return nil
	end

	for _, child in container:GetChildren() do
		if not child:IsA("Tool") then
			continue
		end
		local toolItemId = resolveToolImportData(child)
		if toolItemId == itemId then
			return child
		end
	end

	return nil
end

function InventoryServiceServer.init(self: InventoryServiceServer)
	self.networker = Networker.server.new("InventoryService", self, {
		self.requestSync,
		self.requestSetSelectedSlot,
		self.requestMoveSlot,
		self.requestSplitSlot,
		self.requestDropFromSlot,
		self.requestTrashSlot,
		self.requestTrashSelectedSlot,
		self.requestUseSelectedSlot,
	})
	self.playerRuntimes = {}
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.dataPath = InventoryServiceUtils.getDefaultDataPath()
	self.dataLoadTimeoutSeconds = DEFAULT_DATA_LOAD_TIMEOUT_SECONDS
	self.dropFromSlotHandler = nil
	self.didWarnMissingDropHandler = false

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

function InventoryServiceServer.setDropFromSlotHandler(self: InventoryServiceServer, handlerRaw: any)
	if typeof(handlerRaw) == "function" then
		self.dropFromSlotHandler = handlerRaw
		return
	end
	self.dropFromSlotHandler = nil
	self.didWarnMissingDropHandler = false
end

function InventoryServiceServer.createRuntime(self: InventoryServiceServer): PlayerRuntime
	return {
		state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED),
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		loadToken = 0,
		pendingToolImports = {},
		suppressedToolImports = {},
	}
end

function InventoryServiceServer.getRuntime(self: InventoryServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end

	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function InventoryServiceServer.getLoadedRuntime(self: InventoryServiceServer, player: Player): PlayerRuntime?
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return nil
	end
	if not InventoryServiceUtils.isLoadedState(runtime.state.loadState) then
		return nil
	end
	return runtime
end

function InventoryServiceServer.pushState(self: InventoryServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	local stateToPush = if runtime ~= nil
		then runtime.state
		else InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	self.networker:fire(player, "applyState", InventoryServiceUtils.cloneState(stateToPush))
end

function InventoryServiceServer.persistRuntime(self: InventoryServiceServer, player: Player, runtime: PlayerRuntime): boolean
	if not InventoryServiceUtils.isLoadedState(runtime.state.loadState) then
		return false
	end
	if self.playerDataService == nil then
		return false
	end

	local serializedState = InventoryServiceUtils.serializeStateForData(runtime.state)
	local success, didSet = pcall(function()
		return self.playerDataService:setValue(player, self.dataPath, serializedState, false)
	end)
	if not success then
		warn(("[InventoryService] Failed to persist inventory for %s (%d)"):format(player.Name, player.UserId))
		return false
	end
	return didSet == true
end

function InventoryServiceServer.pushAndPersistState(self: InventoryServiceServer, player: Player, runtime: PlayerRuntime)
	self:persistRuntime(player, runtime)
	self:syncSelectedTool(player, runtime)
	self:pushState(player)
end

function InventoryServiceServer.syncSelectedTool(self: InventoryServiceServer, player: Player, runtime: PlayerRuntime)
	if not InventoryServiceUtils.isLoadedState(runtime.state.loadState) then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	local selectedSlot = runtime.state.selectedSlot
	local selectedStack = if selectedSlot ~= nil then InventoryServiceUtils.getStack(runtime.state, selectedSlot) else nil
	local desiredItemId = if selectedStack ~= nil then sanitizeItemId(selectedStack.itemId) else nil
	local equippedTool = character:FindFirstChildOfClass("Tool")
	local equippedItemId = if equippedTool ~= nil then resolveToolImportData(equippedTool) else nil

	if desiredItemId == nil then
		if equippedTool ~= nil then
			pcall(function()
				humanoid:UnequipTools()
			end)
		end
		return
	end

	if equippedItemId == desiredItemId then
		if equippedTool ~= nil then
			self:bindToolInteractions(player, runtime, equippedTool)
		end
		return
	end

	local desiredTool = findMatchingToolInContainer(character, desiredItemId)
	if desiredTool == nil then
		local backpack = player:FindFirstChildOfClass("Backpack")
		desiredTool = findMatchingToolInContainer(backpack, desiredItemId)
		if desiredTool == nil and selectedStack ~= nil then
			local clonedTool = cloneToolForInventoryStack(desiredItemId, selectedStack)
			if clonedTool ~= nil then
				clonedTool.Parent = if backpack ~= nil then backpack else character
				desiredTool = clonedTool
			end
		end
	end

	if desiredTool == nil then
		if equippedTool ~= nil then
			pcall(function()
				humanoid:UnequipTools()
			end)
		end
		return
	end

	self:bindToolInteractions(player, runtime, desiredTool)

	pcall(function()
		humanoid:EquipTool(desiredTool :: Tool)
	end)
end

function InventoryServiceServer.importToolItemIntoState(
	self: InventoryServiceServer,
	runtime: PlayerRuntime,
	itemIdRaw: any,
	itemTypeRaw: any,
	amountRaw: any
): boolean
	local itemId = sanitizeItemId(itemIdRaw)
	local itemType = sanitizeItemId(itemTypeRaw)
	if itemId == nil then
		return false
	end
	if itemType == nil then
		return false
	end

	local amount = normalizeImportAmount(amountRaw)
	if amount <= 0 then
		return false
	end

	if InventoryServiceUtils.countItem(runtime.state, itemId, nil, false) > 0 then
		return false
	end

	local addResult = InventoryServiceUtils.addItem(
		runtime.state,
		itemId,
		amount,
		1,
		{
			[TOOL_IMPORT_METADATA_TYPE_KEY] = itemType,
		},
		TOOL_IMPORT_STACK_ID_PREFIX
	)
	return addResult.changed
end

function InventoryServiceServer.flushPendingToolImports(self: InventoryServiceServer, runtime: PlayerRuntime): boolean
	if not InventoryServiceUtils.isLoadedState(runtime.state.loadState) then
		return false
	end

	local changed = false
	for pendingKey, pendingImport in runtime.pendingToolImports do
		if self:importToolItemIntoState(runtime, pendingImport.itemId, pendingImport.itemType, pendingImport.amount) then
			changed = true
		end
		runtime.pendingToolImports[pendingKey] = nil
	end
	return changed
end

function InventoryServiceServer.consumeToolInstance(self: InventoryServiceServer, player: Player, runtime: PlayerRuntime, tool: Tool)
	local itemId, itemType = resolveToolImportData(tool)
	if itemId ~= nil and itemType ~= nil then
		if consumeSuppressedToolImport(runtime, itemId, 1) then
			cleanupBoundTool(tool)
			tool:Destroy()
			return
		end

		if InventoryServiceUtils.isLoadedState(runtime.state.loadState) then
			local changed = self:importToolItemIntoState(runtime, itemId, itemType, 1)
			if changed then
				self:pushAndPersistState(player, runtime)
			else
				self:syncSelectedTool(player, runtime)
			end
		else
			queuePendingToolImport(runtime, itemId, itemType, 1)
		end
	else
		warn(("[InventoryService] Ignoring Tool '%s' for %s (%d): missing/invalid '%s' or '%s'."):format(
			tool.Name,
			player.Name,
			player.UserId,
			TOOL_IMPORT_ATTRIBUTE_NAME,
			TOOL_IMPORT_TYPE_ATTRIBUTE_NAME
		))
	end
end

function InventoryServiceServer.enforceContainerToolRules(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	janitor: JanitorClass,
	container: Instance
)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			self:consumeToolInstance(player, runtime, child)
		end
	end

	janitor:GiveChore(container.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:consumeToolInstance(player, runtime, child)
		end
	end))
end

function InventoryServiceServer.bindCharacter(
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

	self:enforceContainerToolRules(player, runtime, runtime.characterJanitor, character)
	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			child:UnequipTools()
			self:syncSelectedTool(player, runtime)
		end
	end))
	self:syncSelectedTool(player, runtime)
end

function InventoryServiceServer.bindBackpack(
	self: InventoryServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	backpack: Backpack
)
	self:enforceContainerToolRules(player, runtime, runtime.playerJanitor, backpack)
	self:syncSelectedTool(player, runtime)
end

function InventoryServiceServer.loadPlayerInventory(self: InventoryServiceServer, player: Player, loadToken: number)
	local runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	local playerDataService = self.playerDataService
	if playerDataService == nil then
		InventoryServiceUtils.setLoadState(runtime.state, InventoryServiceUtils.LOAD_STATE_FAILED)
		self:pushState(player)
		return
	end

	local waitSuccess, playerData = pcall(function()
		return playerDataService:waitForData(player, self.dataLoadTimeoutSeconds)
	end)
	runtime = self.playerRuntimes[player]
	if runtime == nil or runtime.loadToken ~= loadToken then
		return
	end

	if (not waitSuccess) or playerData == nil then
		if not waitSuccess then
			warn(("[InventoryService] Failed to load inventory data for %s (%d)"):format(player.Name, player.UserId))
		end
		InventoryServiceUtils.setLoadState(runtime.state, InventoryServiceUtils.LOAD_STATE_FAILED)
		self:pushState(player)
		return
	end

	local getValueSuccess, storedInventoryRaw = pcall(function()
		return playerDataService:getValue(player, self.dataPath, nil)
	end)
	if not getValueSuccess then
		warn(("[InventoryService] Failed to read persisted inventory for %s (%d)"):format(player.Name, player.UserId))
		InventoryServiceUtils.setLoadState(runtime.state, InventoryServiceUtils.LOAD_STATE_FAILED)
		self:pushState(player)
		return
	end

	runtime.state = InventoryServiceUtils.createStateFromData(
		storedInventoryRaw,
		runtime.state,
		InventoryServiceUtils.LOAD_STATE_LOADED
	)
	self:flushPendingToolImports(runtime)
	self:pushAndPersistState(player, runtime)
end

function InventoryServiceServer.trackPlayer(self: InventoryServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.loadToken += 1
	runtime.playerJanitor:Clean()
	runtime.characterJanitor:Clean()
	runtime.pendingToolImports = {}
	runtime.suppressedToolImports = {}
	runtime.state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADING)
	self:pushState(player)

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
		self:loadPlayerInventory(player, loadToken)
	end)
end

function InventoryServiceServer.untrackPlayer(self: InventoryServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:persistRuntime(player, runtime)

	runtime.loadToken += 1
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function InventoryServiceServer.requestSync(self: InventoryServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		self:trackPlayer(player)
		return
	end

	if runtime.state.loadState == InventoryServiceUtils.LOAD_STATE_FAILED then
		self:trackPlayer(player)
		return
	end

	self:pushState(player)
end

function InventoryServiceServer.requestSetSelectedSlot(self: InventoryServiceServer, player: Player, slotIndexRaw: any)
	self:setSelectedSlot(player, slotIndexRaw)
end

function InventoryServiceServer.requestMoveSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
)
	self:moveSlot(player, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceServer.requestSplitSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
)
	self:splitSlot(player, fromSlotRaw, toSlotRaw, amountRaw)
end

function InventoryServiceServer.requestDropFromSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	self:dropFromSlot(player, slotIndexRaw, amountRaw, throwDirectionRaw)
end

function InventoryServiceServer.requestUseSelectedSlot(self: InventoryServiceServer, player: Player, amountRaw: any)
	self:useSelectedSlot(player, amountRaw)
end

function InventoryServiceServer.requestTrashSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any
)
	self:trashSlot(player, slotIndexRaw, amountRaw)
end

function InventoryServiceServer.requestTrashSelectedSlot(self: InventoryServiceServer, player: Player, amountRaw: any)
	self:trashSelectedSlot(player, amountRaw)
end

function InventoryServiceServer.getState(self: InventoryServiceServer, player: Player): InventoryState
	local runtime = self:getRuntime(player)
	return runtime.state
end

function InventoryServiceServer.getStateCopy(self: InventoryServiceServer, player: Player): InventoryState
	return InventoryServiceUtils.cloneState(self:getState(player))
end

function InventoryServiceServer.setSelectedSlot(self: InventoryServiceServer, player: Player, slotIndexRaw: any): boolean
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return false
	end

	local changed = InventoryServiceUtils.setSelectedSlot(runtime.state, slotIndexRaw)
	if changed then
		self:pushAndPersistState(player, runtime)
	else
		self:syncSelectedTool(player, runtime)
	end
	return changed
end

function InventoryServiceServer.addItem(
	self: InventoryServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any,
	optionsRaw: any
): AddItemResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return {
			requested = 0,
			added = 0,
			leftover = 0,
			changed = false,
			touchedSlots = {},
		}
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local result = InventoryServiceUtils.addItem(
		runtime.state,
		itemIdRaw,
		amountRaw,
		(options :: any).maxStack,
		(options :: any).metadata,
		(options :: any).stackIdPrefix
	)
	if result.changed then
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.removeItem(
	self: InventoryServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any,
	optionsRaw: any
): RemoveItemResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return {
			requested = 0,
			removed = 0,
			leftover = 0,
			changed = false,
			touchedSlots = {},
		}
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local result = InventoryServiceUtils.removeItem(
		runtime.state,
		itemIdRaw,
		amountRaw,
		(options :: any).metadata,
		(options :: any).requireExactMetadata
	)
	if result.changed then
		suppressAndPurgePlayerTools(runtime, player, itemIdRaw, result.removed)
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.removeFromSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
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

	local existingStack = InventoryServiceUtils.getStack(runtime.state, slotIndexRaw)
	local removedItemId = if existingStack ~= nil then existingStack.itemId else nil

	local result = InventoryServiceUtils.removeFromSlot(runtime.state, slotIndexRaw, amountRaw)
	if result.changed then
		if removedItemId ~= nil then
			suppressAndPurgePlayerTools(runtime, player, removedItemId, result.removedAmount)
		end
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.moveSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
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

	local result = InventoryServiceUtils.moveSlot(runtime.state, fromSlotRaw, toSlotRaw, amountRaw)
	if result.changed then
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.splitSlot(
	self: InventoryServiceServer,
	player: Player,
	fromSlotRaw: any,
	toSlotRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
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

	local result = InventoryServiceUtils.splitSlot(runtime.state, fromSlotRaw, toSlotRaw, amountRaw)
	if result.changed then
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.useSelectedSlot(
	self: InventoryServiceServer,
	player: Player,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
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

	local selectedSlot = runtime.state.selectedSlot
	local selectedStack = if selectedSlot ~= nil then InventoryServiceUtils.getStack(runtime.state, selectedSlot) else nil
	local selectedItemId = if selectedStack ~= nil then selectedStack.itemId else nil

	local result = InventoryServiceUtils.consumeSelected(runtime.state, amountRaw)
	if result.changed then
		if selectedItemId ~= nil then
			suppressAndPurgePlayerTools(runtime, player, selectedItemId, result.removedAmount)
		end
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.dropFromSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
): SlotMutationResult
	local unchangedResult: SlotMutationResult = {
		changed = false,
		touchedSlots = {},
		fromSlot = nil,
		toSlot = nil,
		movedAmount = 0,
		removedAmount = 0,
		swapped = false,
	}

	local dropHandler = self.dropFromSlotHandler
	if dropHandler ~= nil then
		local success, handledResult = pcall(dropHandler, player, slotIndexRaw, amountRaw, throwDirectionRaw)
		if success and handledResult ~= false and handledResult ~= nil then
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
		if not success then
			warn(("[InventoryService] Drop handler failed for %s (%d). Ignoring drop request."):format(
				player.Name,
				player.UserId
			))
			return unchangedResult
		end
		return unchangedResult
	end

	if self.didWarnMissingDropHandler ~= true then
		self.didWarnMissingDropHandler = true
		warn("[InventoryService] Drop request ignored because LootService drop handler is not registered.")
	end
	return unchangedResult
end

function InventoryServiceServer.releaseSuppressedToolImport(
	self: InventoryServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any
): number
	local runtime = self.playerRuntimes[player]
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
	if remaining > 0 then
		runtime.suppressedToolImports[itemId] = remaining
	else
		runtime.suppressedToolImports[itemId] = nil
	end
	return released
end

function InventoryServiceServer.trashSlot(
	self: InventoryServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
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

	local existingStack = InventoryServiceUtils.getStack(runtime.state, slotIndexRaw)
	local removedItemId = if existingStack ~= nil then existingStack.itemId else nil

	local result = InventoryServiceUtils.trashSlot(runtime.state, slotIndexRaw, amountRaw)
	if result.changed then
		if removedItemId ~= nil then
			suppressAndPurgePlayerTools(runtime, player, removedItemId, result.removedAmount)
		end
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.trashSelectedSlot(
	self: InventoryServiceServer,
	player: Player,
	amountRaw: any
): SlotMutationResult
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
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

	local selectedSlot = runtime.state.selectedSlot
	local selectedStack = if selectedSlot ~= nil then InventoryServiceUtils.getStack(runtime.state, selectedSlot) else nil
	local selectedItemId = if selectedStack ~= nil then selectedStack.itemId else nil

	local result = InventoryServiceUtils.trashSelected(runtime.state, amountRaw)
	if result.changed then
		if selectedItemId ~= nil then
			suppressAndPurgePlayerTools(runtime, player, selectedItemId, result.removedAmount)
		end
		self:pushAndPersistState(player, runtime)
	end
	return result
end

function InventoryServiceServer.countItem(
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

function InventoryServiceServer.clearInventory(self: InventoryServiceServer, player: Player): boolean
	local runtime = self:getLoadedRuntime(player)
	if runtime == nil then
		return false
	end

	local changed = InventoryServiceUtils.clear(runtime.state)
	if changed then
		self:pushAndPersistState(player, runtime)
	end
	return changed
end

function InventoryServiceServer.destroy(self: InventoryServiceServer)
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	for player, runtime in self.playerRuntimes do
		self:persistRuntime(player, runtime)
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
	end
	self.dropFromSlotHandler = nil

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

type InventoryServiceServer = typeof(InventoryServiceServer) & {
	networker: Networker.Server,
	playerRuntimes: { [Player]: PlayerRuntime },
	playerDataService: PlayerDataServiceServerObject,
	dataPath: { string },
	dataLoadTimeoutSeconds: number,
	dropFromSlotHandler: ((player: Player, slotIndexRaw: any, amountRaw: any, throwDirectionRaw: any) -> any)?,
	releaseSuppressedToolImport: (
		self: InventoryServiceServer,
		player: Player,
		itemIdRaw: any,
		amountRaw: any
	) -> number,
	didWarnMissingDropHandler: boolean,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return InventoryServiceServer :: InventoryServiceServer
