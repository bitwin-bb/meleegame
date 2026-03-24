--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local BuildServiceUtils = require(ReplicatedStorage.Shared.Services.BuildService.BuildServiceUtils)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local PlayerServiceServer = require(ServerScriptService.Services.PlayerService.PlayerServiceServer)
local WorldGenerationServiceServer =
	require(ServerScriptService.Services.WorldGenerationService.WorldGenerationServiceServer)
local InventoryServiceServer = require(ServerScriptService.Services.InventoryService.InventoryServiceServer)
local LootServiceServer = require(ServerScriptService.Services.LootService.LootServiceServer)

type BuildServiceConfig = BuildServiceUtils.BuildServiceConfig
type BuildServiceState = BuildServiceUtils.BuildServiceState
type PlaceableItemConfig = BuildServiceUtils.PlaceableItemConfig
type TileCoordinate = BuildServiceUtils.TileCoordinate
type TileDelta = BuildServiceUtils.TileDelta
type TreeState = BuildServiceUtils.TreeState
type TreeSnapshot = BuildServiceUtils.TreeSnapshot
type TreeFootprint = BuildServiceUtils.TreeFootprint
type TreeHitResult = BuildServiceUtils.TreeHitResult
type TreeBreakProfile = BuildServiceUtils.TreeBreakProfile
type InventoryState = InventoryServiceUtils.InventoryState
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack
type SlotMutationResult = InventoryServiceUtils.SlotMutationResult

type WorldGenerationServiceServerObject = {
	getWorld: (self: WorldGenerationServiceServerObject) -> any,
	setTileAt: (self: WorldGenerationServiceServerObject, tileXRaw: any, tileYRaw: any, tileIdRaw: any) -> (boolean, number, number),
}

type LootServiceServerObject = {
	spawnLootRuntime: (
		self: LootServiceServerObject,
		itemIdRaw: any,
		amountRaw: any,
		positionRaw: any,
		optionsRaw: any
	) -> any,
}

type InventoryServiceServerObject = {
	getState: (self: InventoryServiceServerObject, player: Player) -> InventoryState,
	removeFromSlot: (
		self: InventoryServiceServerObject,
		player: Player,
		slotIndexRaw: any,
		amountRaw: any
	) -> SlotMutationResult,
	addItem: (
		self: InventoryServiceServerObject,
		player: Player,
		itemIdRaw: any,
		amountRaw: any,
		optionsRaw: any
	) -> any,
}

type PlayerBreakIntent = {
	isBreaking: boolean,
	tileX: number?,
	tileY: number?,
	lastInputAt: number,
	lastProgressPushAt: number,
	requestId: number,
	toolPower: number,
	toolType: string,
	breakTargetKind: string?,
	targetTreeId: string?,
	targetTreeRootTileX: number?,
	targetTreeRootTileY: number?,
	targetTreeSeed: number?,
	targetTreeHeight: number?,
	lastTreeHitDirection: number,
}

type TileDamageRuntime = {
	damage: number,
	updatedAt: number,
}

type MultiTileAnchorRuntime = {
	tileId: number,
	originTileX: number,
	originTileY: number,
	members: { TileCoordinate },
}

local BuildServiceServer = {}

local function shouldReplicateToPlayer(player: Player): boolean
	return PlayerServiceServer:isGameplayActiveForPlayer(player)
end

local DEFAULT_DAMAGE_RETENTION_SECONDS = 30
local DAMAGE_PRUNE_INTERVAL = 2
local MAX_CASCADE_PASSES_PER_TICK = 8
local TREE_DROP_SOURCE_TYPE = "TreeFell"

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInventorySlot(slotRaw: any): number?
	if typeof(slotRaw) ~= "number" or slotRaw ~= slotRaw then
		return nil
	end

	local slot = math.floor(slotRaw)
	if slot <= 0 then
		return nil
	end
	return slot
end

local function resolveBuildConfigSource(): any
	if typeof(Configs) ~= "table" then
		return nil
	end
	return (Configs :: any).buildService
end

local function resolvePlayerRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local rootCandidate = character:FindFirstChild("HumanoidRootPart")
	if rootCandidate ~= nil and rootCandidate:IsA("BasePart") then
		return rootCandidate
	end
	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function resolvePlayerToolPower(player: Player, fallback: number): number
	local character = player.Character
	if character ~= nil then
		for _, child in character:GetChildren() do
			if not child:IsA("Tool") then
				continue
			end
			local attr = child:GetAttribute("MiningPower")
			if not isFiniteNumber(attr) then
				attr = child:GetAttribute("ToolPower")
			end
			if not isFiniteNumber(attr) then
				attr = child:GetAttribute("PickaxePower")
			end
			if isFiniteNumber(attr) then
				return math.max(0, attr :: number)
			end
		end
	end
	return fallback
end

local function resolvePlayerToolType(player: Player, fallback: string): string
	local character = player.Character
	if character ~= nil then
		for _, child in character:GetChildren() do
			if not child:IsA("Tool") then
				continue
			end

			local attr = child:GetAttribute("ToolType")
			if typeof(attr) ~= "string" or attr == "" then
				attr = child:GetAttribute("HarvestType")
			end
			if typeof(attr) ~= "string" or attr == "" then
				attr = child:GetAttribute("WeaponType")
			end
			if typeof(attr) == "string" and attr ~= "" then
				return attr
			end

			local lowerName = string.lower(child.Name)
			if string.find(lowerName, "axe", 1, true) ~= nil then
				return "Axe"
			end
			if string.find(lowerName, "pick", 1, true) ~= nil then
				return "Pickaxe"
			end
		end
	end
	return fallback
end

local function resolvePlaceableFromInventory(
	inventoryService: InventoryServiceServerObject?,
	player: Player,
	sourceSlotRaw: any?
): (number?, InventoryItemStack?, PlaceableItemConfig?, string?)
	if inventoryService == nil then
		return nil, nil, nil, nil
	end

	local inventoryState = inventoryService:getState(player)
	if not InventoryServiceUtils.isLoadedState(inventoryState.loadState) then
		return nil, nil, nil, nil
	end

	local sourceSlot = nil :: number?
	if sourceSlotRaw ~= nil then
		sourceSlot = sanitizeInventorySlot(sourceSlotRaw)
		if sourceSlot == nil then
			return nil, nil, nil, "invalid_source_slot"
		end
	else
		sourceSlot = inventoryState.selectedSlot
	end
	if sourceSlot == nil then
		return nil, nil, nil, nil
	end

	local stack = InventoryServiceUtils.getStack(inventoryState, sourceSlot)
	if stack == nil or stack.amount <= 0 then
		return sourceSlot, nil, nil, nil
	end

	return sourceSlot, stack, BuildServiceUtils.resolvePlaceableItemConfig(stack.itemId), nil
end

local function cloneTileDeltaList(source: { TileDelta }): { TileDelta }
	local output: { TileDelta } = table.create(#source)
	for index, delta in source do
		output[index] = {
			tileX = delta.tileX,
			tileY = delta.tileY,
			tileId = delta.tileId,
			reason = delta.reason,
		}
	end
	return output
end

function BuildServiceServer.createStateSnapshot(self: BuildServiceServer): BuildServiceState
	local world = self.world
	local tileSize = if world ~= nil and isFiniteNumber((world :: any).tileSize) then (world :: any).tileSize else 2
	local chunkSize = if world ~= nil and isFiniteNumber((world :: any).chunkSize) then math.floor((world :: any).chunkSize) else 32
	local worldOrigin = if world ~= nil and typeof((world :: any).worldOrigin) == "Vector3"
		then (world :: any).worldOrigin
		else Vector3.zero
	local basePlaneX = if world ~= nil and isFiniteNumber((world :: any).basePlaneX) then (world :: any).basePlaneX else 0
	return BuildServiceUtils.createState({
		ready = world ~= nil,
		tileSize = tileSize,
		chunkSize = chunkSize,
		worldOrigin = worldOrigin,
		basePlaneX = basePlaneX,
		maxInteractionDistanceTiles = self.config.maxInteractionDistanceTiles,
		clientBreakInputRate = self.config.clientBreakInputRate,
		clientPlaceInputRate = self.config.clientPlaceInputRate,
	}, self.state)
end

function BuildServiceServer.pushState(self: BuildServiceServer, player: Player)
	self.state = self:createStateSnapshot()
	self.networker:fire(player, BuildServiceUtils.CLIENT_METHOD_APPLY_STATE, BuildServiceUtils.cloneState(self.state))
end

function BuildServiceServer.createBreakIntent(self: BuildServiceServer): PlayerBreakIntent
	return {
		isBreaking = false,
		tileX = nil,
		tileY = nil,
		lastInputAt = 0,
		lastProgressPushAt = 0,
		requestId = 0,
		toolPower = self.config.defaultToolPower,
		toolType = "",
		breakTargetKind = nil,
		targetTreeId = nil,
		targetTreeRootTileX = nil,
		targetTreeRootTileY = nil,
		targetTreeSeed = nil,
		targetTreeHeight = nil,
		lastTreeHitDirection = 0,
	}
end

function BuildServiceServer.getBreakIntent(self: BuildServiceServer, player: Player): PlayerBreakIntent
	local existing = self.playerBreakIntents[player]
	if existing ~= nil then
		return existing
	end
	local created = self:createBreakIntent()
	self.playerBreakIntents[player] = created
	return created
end

function BuildServiceServer.getTileBoundsY(self: BuildServiceServer): (number, number)
	local world = self.world
	local minTileY = if world ~= nil and isFiniteNumber((world :: any).minTileY) then math.floor((world :: any).minTileY) else -4096
	local maxTileY = if world ~= nil and isFiniteNumber((world :: any).maxTileY) then math.floor((world :: any).maxTileY) else 4096
	return minTileY, maxTileY
end

function BuildServiceServer.isTileWithinBounds(self: BuildServiceServer, tileY: number): boolean
	local minTileY, maxTileY = self:getTileBoundsY()
	return tileY >= minTileY and tileY <= maxTileY
end

function BuildServiceServer.getTileAtInternal(self: BuildServiceServer, tileX: number, tileY: number): number
	if self.world == nil then
		return BuildServiceUtils.AIR_TILE_ID
	end
	local tileId = (self.world :: any):getTileAt(tileX, tileY)
	if isFiniteNumber(tileId) then
		local sanitized = BuildServiceUtils.sanitizeTileId(tileId)
		if sanitized ~= nil then
			return sanitized
		end
	end
	return BuildServiceUtils.AIR_TILE_ID
end

function BuildServiceServer.getTileAt(self: BuildServiceServer, _player: Player, tileXRaw: any, tileYRaw: any): number
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return BuildServiceUtils.AIR_TILE_ID
	end
	return self:getTileAtInternal(tileX, tileY)
end

function BuildServiceServer.getTreesForChunk(self: BuildServiceServer, chunkX: number, chunkY: number): { any }?
	if self.world == nil then
		return nil
	end
	local getChunkDataMethod = (self.world :: any).getChunkData
	if typeof(getChunkDataMethod) ~= "function" then
		return nil
	end
	local chunkData = getChunkDataMethod(self.world, chunkX, chunkY)
	if typeof(chunkData) ~= "table" then
		return nil
	end
	local trees = (chunkData :: any).trees
	if typeof(trees) ~= "table" then
		return nil
	end
	return trees
end

function BuildServiceServer.resolveTreeHitAt(self: BuildServiceServer, tileX: number, tileY: number): TreeHitResult?
	return BuildServiceUtils.resolveTreeAtTile(tileX, tileY, self.state.chunkSize, function(chunkX: number, chunkY: number): { any }?
		return self:getTreesForChunk(chunkX, chunkY)
	end)
end

function BuildServiceServer.resolvePlayerTileX(self: BuildServiceServer, player: Player, fallbackTileX: number): number
	local rootPart = resolvePlayerRootPart(player)
	if rootPart == nil then
		return fallbackTileX
	end
	local tileX, _ = BuildServiceUtils.worldPositionToTile(rootPart.Position, self.state.worldOrigin, self.state.tileSize)
	return tileX
end

function BuildServiceServer.touchChunkForTreeMutation(self: BuildServiceServer, chunkKey: string)
	if self.world == nil then
		return
	end

	local bumpRevisionMethod = (self.world :: any).bumpChunkRevisionByKey
	if typeof(bumpRevisionMethod) == "function" then
		bumpRevisionMethod(self.world, chunkKey)
	end

	local markDirtyMethod = (self.world :: any).markChunkDirtyByKey
	if typeof(markDirtyMethod) == "function" then
		markDirtyMethod(self.world, chunkKey)
	end

	local cachedChunkVisuals = (self.world :: any).cachedChunkVisuals
	local releaseChunkVisualMethod = (self.world :: any).releaseChunkVisual
	if typeof(cachedChunkVisuals) == "table" and typeof(releaseChunkVisualMethod) == "function" then
		local cachedVisual = cachedChunkVisuals[chunkKey]
		if cachedVisual ~= nil then
			cachedChunkVisuals[chunkKey] = nil
			local cachedCountRaw = (self.world :: any).cachedChunkVisualCount
			local cachedCount = if isFiniteNumber(cachedCountRaw) then cachedCountRaw else 0
			(self.world :: any).cachedChunkVisualCount = math.max(0, cachedCount - 1)
			releaseChunkVisualMethod(self.world, cachedVisual)
		end
	end

	local enqueueChunkMethod = (self.worldGenerationService :: any).enqueueChunkForWorldSimulation
	if typeof(enqueueChunkMethod) == "function" then
		pcall(function()
			enqueueChunkMethod(self.worldGenerationService, chunkKey, nil)
		end)
	end
end

function BuildServiceServer.removeTreeFromWorld(self: BuildServiceServer, tree: TreeSnapshot): boolean
	if self.world == nil then
		return false
	end
	local getChunkDataMethod = (self.world :: any).getChunkData
	if typeof(getChunkDataMethod) ~= "function" then
		return false
	end
	local chunkData = getChunkDataMethod(self.world, tree.chunkX, tree.chunkY)
	if typeof(chunkData) ~= "table" then
		return false
	end
	local trees = (chunkData :: any).trees
	if typeof(trees) ~= "table" then
		return false
	end

	local removed = false
	for index = #trees, 1, -1 do
		local snapshot = BuildServiceUtils.createTreeSnapshot(tree.chunkX, tree.chunkY, trees[index])
		if snapshot == nil or snapshot.treeId ~= tree.treeId then
			continue
		end
		table.remove(trees, index)
		removed = true
	end

	if removed then
		self:touchChunkForTreeMutation(tree.chunkKey)
	end
	return removed
end

function BuildServiceServer.spawnTreeDropsAtImpact(
	self: BuildServiceServer,
	tree: TreeSnapshot,
	heightTiles: number,
	fallDirection: number,
	impactPosition: Vector3
)
	if self.lootService == nil then
		return
	end

	local drops = BuildServiceUtils.rollTreeDrops({
		seed = tree.seed,
		variantIndex = tree.variantIndex,
		biomeType = tree.biomeType,
		biomeId = tree.biomeId,
		heightTiles = heightTiles,
	})
	if #drops <= 0 then
		return
	end

	local scatterStep = math.max(0.2, self.state.tileSize * 0.24)
	local throwDirection = BuildServiceUtils.computeTreeFallVector2D(fallDirection)
	for dropIndex, drop in drops do
		local offsetAlongFall = (dropIndex - (#drops + 1) * 0.5) * scatterStep
		local spawnPosition = impactPosition
			+ Vector3.new(0, self.state.tileSize * 0.55, 0)
			+ throwDirection * offsetAlongFall
		pcall(function()
			local lootServiceAny = self.lootService :: any
			lootServiceAny:spawnLootRuntime(drop.itemId, drop.amount, spawnPosition, {
				sourceType = TREE_DROP_SOURCE_TYPE,
				throwDirection = throwDirection,
			})
		end)
	end
end

function BuildServiceServer.isWithinInteractionRange(
	self: BuildServiceServer,
	player: Player,
	tileX: number,
	tileY: number
): boolean
	local rootPart = resolvePlayerRootPart(player)
	if rootPart == nil then
		return false
	end
	local targetPosition = BuildServiceUtils.tileToWorldCenter(
		tileX,
		tileY,
		self.state.worldOrigin,
		self.state.tileSize,
		self.state.basePlaneX
	)
	local maxDistanceStuds = self.config.maxInteractionDistanceTiles * self.state.tileSize
	return BuildServiceUtils.worldDistance2D(rootPart.Position, targetPosition) <= maxDistanceStuds + self.state.tileSize
end

function BuildServiceServer.isBreakTargetWithinInteractionRange(
	self: BuildServiceServer,
	player: Player,
	tileX: number,
	tileY: number
): boolean
	if self:isWithinInteractionRange(player, tileX, tileY) then
		return true
	end

	local treeHit = self:resolveTreeHitAt(tileX, tileY)
	if treeHit == nil then
		return false
	end

	local rootTileX = treeHit.tree.rootTileX
	local rootTileY = treeHit.tree.rootTileY + 1
	return self:isWithinInteractionRange(player, rootTileX, rootTileY)
end

function BuildServiceServer.pushBreakProgress(
	self: BuildServiceServer,
	player: Player,
	isActive: boolean,
	tileX: number?,
	tileY: number?,
	progress: number,
	breakDuration: number,
	toolPower: number
)
	self.networker:fire(player, BuildServiceUtils.CLIENT_METHOD_ON_BREAK_PROGRESS, {
		isActive = isActive,
		tileX = tileX,
		tileY = tileY,
		progress = math.clamp(progress, 0, 1),
		breakDuration = breakDuration,
		toolPower = toolPower,
		updatedAt = os.clock(),
	})
end

function BuildServiceServer.sendActionResult(
	self: BuildServiceServer,
	player: Player,
	requestIdRaw: any,
	actionType: string,
	accepted: boolean,
	reason: string,
	deltasRaw: { TileDelta }?
)
	local requestId = BuildServiceUtils.sanitizeRequestId(requestIdRaw)
	if requestId <= 0 then
		return
	end
	local deltas = if deltasRaw ~= nil then cloneTileDeltaList(deltasRaw) else {}
	self.networker:fire(player, BuildServiceUtils.CLIENT_METHOD_ON_ACTION_RESULT, {
		requestId = requestId,
		actionType = actionType,
		accepted = accepted,
		reason = reason,
		deltas = deltas,
		updatedAt = os.clock(),
	})
end

function BuildServiceServer.trackPlayer(self: BuildServiceServer, player: Player)
	self.playerBreakIntents[player] = self:createBreakIntent()
	self:pushState(player)
end

function BuildServiceServer.untrackPlayer(self: BuildServiceServer, player: Player)
	self.playerBreakIntents[player] = nil
end

function BuildServiceServer.requestSync(self: BuildServiceServer, player: Player)
	if self.playerBreakIntents[player] == nil then
		self:trackPlayer(player)
	end
	local nextWorld = (self.worldGenerationService :: any):getWorld()
	if nextWorld ~= self.world then
		self.world = nextWorld
		table.clear(self.pendingTileDeltas)
		table.clear(self.pendingTileDeltaLookup)
		table.clear(self.tileDamage)
		table.clear(self.treeDamage)
		table.clear(self.treeStates)
		table.clear(self.multiTileAnchors)
		table.clear(self.multiTileMembers)
	end
	self:pushState(player)
end

function BuildServiceServer.queueTileDelta(
	self: BuildServiceServer,
	tileX: number,
	tileY: number,
	tileId: number,
	reason: string
): TileDelta
	local key = BuildServiceUtils.packTileKey(tileX, tileY)
	local existingIndex = self.pendingTileDeltaLookup[key]
	if existingIndex ~= nil then
		local existing = self.pendingTileDeltas[existingIndex]
		existing.tileId = tileId
		existing.reason = reason
		return existing
	end

	local delta: TileDelta = {
		tileX = tileX,
		tileY = tileY,
		tileId = tileId,
		reason = reason,
	}
	self.pendingTileDeltas[#self.pendingTileDeltas + 1] = delta
	self.pendingTileDeltaLookup[key] = #self.pendingTileDeltas
	return delta
end

function BuildServiceServer.clearMultiTileAnchor(self: BuildServiceServer, anchorKey: string)
	local anchor = self.multiTileAnchors[anchorKey]
	if anchor == nil then
		return
	end
	for _, member in anchor.members do
		self.multiTileMembers[BuildServiceUtils.packTileKey(member.tileX, member.tileY)] = nil
	end
	self.multiTileAnchors[anchorKey] = nil
end

function BuildServiceServer.clearMultiTileMembershipAt(self: BuildServiceServer, tileX: number, tileY: number)
	local tileKey = BuildServiceUtils.packTileKey(tileX, tileY)
	local anchorKey = self.multiTileMembers[tileKey]
	if anchorKey == nil then
		return
	end
	self:clearMultiTileAnchor(anchorKey)
end

function BuildServiceServer.registerMultiTilePlacement(
	self: BuildServiceServer,
	tileId: number,
	footprint: { TileCoordinate }
)
	local tileRule = BuildServiceUtils.getTileRule(tileId)
	if tileRule.multiTileSizeX <= 1 and tileRule.multiTileSizeY <= 1 then
		return
	end
	if #footprint <= 0 then
		return
	end

	local originTileX = math.huge
	local originTileY = math.huge
	for _, tile in footprint do
		originTileX = math.min(originTileX, tile.tileX)
		originTileY = math.min(originTileY, tile.tileY)
	end
	local anchorKey = BuildServiceUtils.packTileKey(originTileX, originTileY)
	local members = table.create(#footprint)
	for index, tile in footprint do
		members[index] = {
			tileX = tile.tileX,
			tileY = tile.tileY,
		}
		self.multiTileMembers[BuildServiceUtils.packTileKey(tile.tileX, tile.tileY)] = anchorKey
	end
	self.multiTileAnchors[anchorKey] = {
		tileId = tileId,
		originTileX = originTileX,
		originTileY = originTileY,
		members = members,
	}
end

function BuildServiceServer.setTileAtAuthoritative(
	self: BuildServiceServer,
	tileX: number,
	tileY: number,
	tileId: number,
	reason: string
): (boolean, number, number)
	self:clearMultiTileMembershipAt(tileX, tileY)
	local worldGenerationServiceAny = self.worldGenerationService :: any
	local changed, previousTileIdRaw, nextTileIdRaw =
		worldGenerationServiceAny:setTileAt(tileX, tileY, tileId)
	local previousTileId = if isFiniteNumber(previousTileIdRaw)
		then math.floor(previousTileIdRaw)
		else BuildServiceUtils.AIR_TILE_ID
	local nextTileId = if isFiniteNumber(nextTileIdRaw) then math.floor(nextTileIdRaw) else previousTileId
	if not changed then
		return false, previousTileId, nextTileId
	end
	local tileKey = BuildServiceUtils.packTileKey(tileX, tileY)
	self.tileDamage[tileKey] = nil
	self:queueTileDelta(tileX, tileY, nextTileId, reason)
	return true, previousTileId, nextTileId
end

function BuildServiceServer.resolveBreakFootprint(
	self: BuildServiceServer,
	tileX: number,
	tileY: number
): { TileCoordinate }
	local tileKey = BuildServiceUtils.packTileKey(tileX, tileY)
	local anchorKey = self.multiTileMembers[tileKey]
	if anchorKey ~= nil then
		local anchor = self.multiTileAnchors[anchorKey]
		if anchor ~= nil then
			local footprint = table.create(#anchor.members)
			for index, member in anchor.members do
				footprint[index] = {
					tileX = member.tileX,
					tileY = member.tileY,
				}
			end
			return footprint
		end
	end
	return {
		{
			tileX = tileX,
			tileY = tileY,
		},
	}
end

function BuildServiceServer.resolveUnsupportedCascadeAround(
	self: BuildServiceServer,
	changedTiles: { TileCoordinate }
): { TileDelta }
	local queue: { TileCoordinate } = {}
	local queuedLookup: { [string]: boolean } = {}
	local processedLookup: { [string]: boolean } = {}
	local cascadeDeltas: { TileDelta } = {}

	local function enqueue(tileX: number, tileY: number)
		if not self:isTileWithinBounds(tileY) then
			return
		end
		local key = BuildServiceUtils.packTileKey(tileX, tileY)
		if queuedLookup[key] then
			return
		end
		queuedLookup[key] = true
		queue[#queue + 1] = {
			tileX = tileX,
			tileY = tileY,
		}
	end

	for _, changedTile in changedTiles do
		enqueue(changedTile.tileX, changedTile.tileY)
		local neighbors = BuildServiceUtils.getCardinalNeighbors(changedTile.tileX, changedTile.tileY)
		for _, neighbor in neighbors do
			enqueue(neighbor.tileX, neighbor.tileY)
		end
	end

	local queueHead = 1
	local passes = 0
	while queueHead <= #queue and passes < MAX_CASCADE_PASSES_PER_TICK do
		local current = queue[queueHead]
		queue[queueHead] = nil :: any
		queueHead += 1
		passes += 1

		local key = BuildServiceUtils.packTileKey(current.tileX, current.tileY)
		if processedLookup[key] then
			continue
		end
		processedLookup[key] = true

		local tileId = self:getTileAtInternal(current.tileX, current.tileY)
		if tileId == BuildServiceUtils.AIR_TILE_ID then
			continue
		end
		local tileRule = BuildServiceUtils.getTileRule(tileId)
		if not tileRule.requiresSupport and not tileRule.fallWhenUnsupported then
			continue
		end
		if BuildServiceUtils.hasSupportAt(current.tileX, current.tileY, tileRule.supportMode, function(scanX: number, scanY: number): number
			return self:getTileAtInternal(scanX, scanY)
		end) then
			continue
		end

		local supportComponent, hasSupport, truncated = BuildServiceUtils.floodFillSupportComponent(
			current.tileX,
			current.tileY,
			function(scanX: number, scanY: number): number
				return self:getTileAtInternal(scanX, scanY)
			end,
			self.config.breakSupportFloodLimit
		)
		if hasSupport then
			continue
		end

		for _, unsupportedTile in supportComponent do
			local didChange, _, nextTileId = self:setTileAtAuthoritative(
				unsupportedTile.tileX,
				unsupportedTile.tileY,
				BuildServiceUtils.AIR_TILE_ID,
				"cascade"
			)
			if didChange then
				cascadeDeltas[#cascadeDeltas + 1] = {
					tileX = unsupportedTile.tileX,
					tileY = unsupportedTile.tileY,
					tileId = nextTileId,
					reason = "cascade",
				}
				local unsupportedNeighbors = BuildServiceUtils.getCardinalNeighbors(
					unsupportedTile.tileX,
					unsupportedTile.tileY
				)
				for _, neighbor in unsupportedNeighbors do
					enqueue(neighbor.tileX, neighbor.tileY)
				end
			end
		end

		if truncated then
			break
		end
	end

	return cascadeDeltas
end

function BuildServiceServer.flushTileDeltas(self: BuildServiceServer)
	local count = #self.pendingTileDeltas
	if count <= 0 then
		return
	end
	if self.networker == nil then
		table.clear(self.pendingTileDeltas)
		table.clear(self.pendingTileDeltaLookup)
		return
	end

	local batchMax = math.max(1, self.config.deltaBatchMax)
	local startIndex = 1
	while startIndex <= count do
		local stopIndex = math.min(count, startIndex + batchMax - 1)
		local batch = table.create(stopIndex - startIndex + 1)
		local cursor = 1
		for index = startIndex, stopIndex do
			local delta = self.pendingTileDeltas[index]
			batch[cursor] = {
				tileX = delta.tileX,
				tileY = delta.tileY,
				tileId = delta.tileId,
				reason = delta.reason,
			}
			cursor += 1
		end
		for _, player in Players:GetPlayers() do
			if shouldReplicateToPlayer(player) then
				self.networker:fire(player, BuildServiceUtils.CLIENT_METHOD_ON_TILE_DELTAS, {
					deltas = batch,
					updatedAt = os.clock(),
				})
			end
		end
		startIndex += batchMax
	end

	table.clear(self.pendingTileDeltas)
	table.clear(self.pendingTileDeltaLookup)
end

function BuildServiceServer.canPlaceAt(
	self: BuildServiceServer,
	player: Player,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any
): (boolean, string)
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	local requestedTileId = BuildServiceUtils.sanitizeTileId(tileIdRaw)
	if tileX == nil or tileY == nil or requestedTileId == nil then
		return false, "invalid_tile_coordinate_or_id"
	end
	local _, _, selectedPlaceableConfig = resolvePlaceableFromInventory(self.inventoryService, player, nil)
	if selectedPlaceableConfig == nil then
		return false, "selected_item_not_placeable"
	end
	local tileId = selectedPlaceableConfig.tileId
	if requestedTileId ~= tileId then
		return false, "selected_item_tile_mismatch"
	end
	if not self:isTileWithinBounds(tileY) then
		return false, "tile_out_of_bounds"
	end
	if not self:isWithinInteractionRange(player, tileX, tileY) then
		return false, "out_of_range"
	end

	local minTileY, maxTileY = self:getTileBoundsY()
	local placementResult = BuildServiceUtils.canPlaceAt(
		tileX,
		tileY,
		tileId,
		function(scanX: number, scanY: number): number
			return self:getTileAtInternal(scanX, scanY)
		end,
		minTileY,
		maxTileY
	)
	return placementResult.canPlace, placementResult.reason
end

function BuildServiceServer.requestPlaceTile(
	self: BuildServiceServer,
	player: Player,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any,
	requestIdRaw: any?,
	sourceSlotRaw: any?
)
	local requestId = BuildServiceUtils.sanitizeRequestId(requestIdRaw)
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	local requestedTileId = BuildServiceUtils.sanitizeTileId(tileIdRaw)
	if tileX == nil or tileY == nil or requestedTileId == nil then
		self:sendActionResult(
			player,
			requestId,
			BuildServiceUtils.ACTION_TYPE_PLACE,
			false,
			"invalid_tile_coordinate_or_id",
			nil
		)
		return
	end
	local sourceSlot, sourceStack, sourcePlaceableConfig, sourceError =
		resolvePlaceableFromInventory(self.inventoryService, player, sourceSlotRaw)
	if sourceError ~= nil then
		self:sendActionResult(
			player,
			requestId,
			BuildServiceUtils.ACTION_TYPE_PLACE,
			false,
			sourceError,
			nil
		)
		return
	end
	if sourceSlot == nil or sourceStack == nil or sourcePlaceableConfig == nil then
		self:sendActionResult(
			player,
			requestId,
			BuildServiceUtils.ACTION_TYPE_PLACE,
			false,
			"selected_item_not_placeable",
			nil
		)
		return
	end
	local tileId = sourcePlaceableConfig.tileId
	if requestedTileId ~= tileId then
		self:sendActionResult(
			player,
			requestId,
			BuildServiceUtils.ACTION_TYPE_PLACE,
			false,
			"selected_item_tile_mismatch",
			nil
		)
		return
	end
	if not self:isTileWithinBounds(tileY) then
		self:sendActionResult(player, requestId, BuildServiceUtils.ACTION_TYPE_PLACE, false, "tile_out_of_bounds", nil)
		return
	end
	if not self:isWithinInteractionRange(player, tileX, tileY) then
		self:sendActionResult(player, requestId, BuildServiceUtils.ACTION_TYPE_PLACE, false, "out_of_range", nil)
		return
	end

	local minTileY, maxTileY = self:getTileBoundsY()
	local placementResult = BuildServiceUtils.canPlaceAt(
		tileX,
		tileY,
		tileId,
		function(scanX: number, scanY: number): number
			return self:getTileAtInternal(scanX, scanY)
		end,
		minTileY,
		maxTileY
	)
	if not placementResult.canPlace then
		self:sendActionResult(
			player,
			requestId,
			BuildServiceUtils.ACTION_TYPE_PLACE,
			false,
			placementResult.reason,
			nil
		)
		return
	end
	local requiredAmount = if sourcePlaceableConfig.consumesOnPlace then #placementResult.footprint else 0
	if sourceStack.amount < requiredAmount then
		self:sendActionResult(
			player,
			requestId,
			BuildServiceUtils.ACTION_TYPE_PLACE,
			false,
			"insufficient_items",
			nil
		)
		return
	end

	local stackSnapshot = nil :: InventoryItemStack?
	if requiredAmount > 0 then
		stackSnapshot = {
			stackId = sourceStack.stackId,
			itemId = sourceStack.itemId,
			amount = sourceStack.amount,
			maxStack = sourceStack.maxStack,
			metadata = InventoryServiceUtils.cloneDeep(sourceStack.metadata),
		}
		local consumeResult = self.inventoryService:removeFromSlot(player, sourceSlot, requiredAmount)
		if consumeResult.removedAmount < requiredAmount then
			if consumeResult.removedAmount > 0 and stackSnapshot ~= nil then
				self.inventoryService:addItem(player, stackSnapshot.itemId, consumeResult.removedAmount, {
					maxStack = stackSnapshot.maxStack,
					metadata = stackSnapshot.metadata,
					stackIdPrefix = "buildRollback",
				})
			end
			self:sendActionResult(
				player,
				requestId,
				BuildServiceUtils.ACTION_TYPE_PLACE,
				false,
				"insufficient_items",
				nil
			)
			return
		end
	end

	local changedTiles: { TileCoordinate } = {}
	local changedDeltas: { TileDelta } = {}
	for _, footprintTile in placementResult.footprint do
		local didChange, _, nextTileId = self:setTileAtAuthoritative(
			footprintTile.tileX,
			footprintTile.tileY,
			tileId,
			"place"
		)
		if didChange then
			changedTiles[#changedTiles + 1] = {
				tileX = footprintTile.tileX,
				tileY = footprintTile.tileY,
			}
			changedDeltas[#changedDeltas + 1] = {
				tileX = footprintTile.tileX,
				tileY = footprintTile.tileY,
				tileId = nextTileId,
				reason = "place",
			}
		end
	end

	if #changedTiles <= 0 then
		if requiredAmount > 0 and stackSnapshot ~= nil then
			self.inventoryService:addItem(player, stackSnapshot.itemId, requiredAmount, {
				maxStack = stackSnapshot.maxStack,
				metadata = stackSnapshot.metadata,
				stackIdPrefix = "buildRollback",
			})
		end
		self:sendActionResult(player, requestId, BuildServiceUtils.ACTION_TYPE_PLACE, false, "no_change", nil)
		return
	end

	if requiredAmount > 0 and stackSnapshot ~= nil and #changedTiles < requiredAmount then
		self.inventoryService:addItem(player, stackSnapshot.itemId, requiredAmount - #changedTiles, {
			maxStack = stackSnapshot.maxStack,
			metadata = stackSnapshot.metadata,
			stackIdPrefix = "buildRollback",
		})
	end

	self:registerMultiTilePlacement(tileId, changedTiles)
	self:sendActionResult(
		player,
		requestId,
		BuildServiceUtils.ACTION_TYPE_PLACE,
		true,
		"ok",
		changedDeltas
	)
end

function BuildServiceServer.processBreakCompletion(
	self: BuildServiceServer,
	player: Player,
	intent: PlayerBreakIntent,
	tileX: number,
	tileY: number
)
	local breakFootprint = self:resolveBreakFootprint(tileX, tileY)
	if #breakFootprint <= 0 then
		self:sendActionResult(player, intent.requestId, BuildServiceUtils.ACTION_TYPE_BREAK, false, "no_footprint", nil)
		return
	end

	local changedTiles: { TileCoordinate } = {}
	local breakDeltas: { TileDelta } = {}
	for _, breakTile in breakFootprint do
		local currentTileId = self:getTileAtInternal(breakTile.tileX, breakTile.tileY)
		if currentTileId == BuildServiceUtils.AIR_TILE_ID then
			continue
		end
		local didChange, _, nextTileId = self:setTileAtAuthoritative(
			breakTile.tileX,
			breakTile.tileY,
			BuildServiceUtils.AIR_TILE_ID,
			"break"
		)
		if didChange then
			changedTiles[#changedTiles + 1] = {
				tileX = breakTile.tileX,
				tileY = breakTile.tileY,
			}
			breakDeltas[#breakDeltas + 1] = {
				tileX = breakTile.tileX,
				tileY = breakTile.tileY,
				tileId = nextTileId,
				reason = "break",
			}
		end
	end

	if #changedTiles <= 0 then
		self:sendActionResult(player, intent.requestId, BuildServiceUtils.ACTION_TYPE_BREAK, false, "no_change", nil)
		return
	end

	local cascadeDeltas = self:resolveUnsupportedCascadeAround(changedTiles)
	for _, delta in cascadeDeltas do
		breakDeltas[#breakDeltas + 1] = delta
	end
	self:sendActionResult(player, intent.requestId, BuildServiceUtils.ACTION_TYPE_BREAK, true, "ok", breakDeltas)
end

function BuildServiceServer.processTreeBreakCompletion(
	self: BuildServiceServer,
	player: Player,
	intent: PlayerBreakIntent,
	treeHit: TreeHitResult,
	treeBreakProfile: TreeBreakProfile
)
	local tree = treeHit.tree
	local treeId = tree.treeId
	if self.treeStates[treeId] == BuildServiceUtils.TREE_STATE_FELLED then
		self:sendActionResult(
			player,
			intent.requestId,
			BuildServiceUtils.ACTION_TYPE_BREAK,
			false,
			"tree_already_felled",
			nil
		)
		return
	end

	self.treeStates[treeId] = BuildServiceUtils.TREE_STATE_FELLED
	self.treeDamage[treeId] = nil
	local removed = self:removeTreeFromWorld(tree)
	if not removed then
		self.treeStates[treeId] = nil
		self:sendActionResult(
			player,
			intent.requestId,
			BuildServiceUtils.ACTION_TYPE_BREAK,
			false,
			"tree_missing",
			nil
		)
		return
	end

	local playerTileX = self:resolvePlayerTileX(player, tree.rootTileX)
	local fallDirection = BuildServiceUtils.computeTreeFallDirection(
		tree.rootTileX,
		playerTileX,
		intent.lastTreeHitDirection
	)
	local heightTiles = treeHit.footprint.heightTiles
	local pivotCFrame = BuildServiceUtils.computeTreePivotCFrame(
		tree.rootTileX,
		tree.rootTileY,
		self.state.worldOrigin,
		self.state.tileSize,
		self.state.basePlaneX
	)
	local payload = {
		treeId = treeId,
		pivotCFrame = pivotCFrame,
		fallDirection = fallDirection,
		height = heightTiles,
		seed = tree.seed,
		fallDuration = treeBreakProfile.fallDuration,
	}
	if self.networker ~= nil then
		for _, listedPlayer in Players:GetPlayers() do
			if shouldReplicateToPlayer(listedPlayer) then
				self.networker:fire(listedPlayer, BuildServiceUtils.CLIENT_METHOD_ON_TREE_FELLED, payload)
			end
		end
	end

	self:sendActionResult(player, intent.requestId, BuildServiceUtils.ACTION_TYPE_BREAK, true, "tree_felled", {})

	task.delay(treeBreakProfile.fallDuration, function()
		local impactPosition = BuildServiceUtils.computeTreeImpactPosition(
			pivotCFrame,
			fallDirection,
			heightTiles,
			self.state.tileSize
		)
		self:spawnTreeDropsAtImpact(tree, heightTiles, fallDirection, impactPosition)
	end)
end

function BuildServiceServer.stopBreaking(
	self: BuildServiceServer,
	player: Player,
	intent: PlayerBreakIntent,
	reason: string
)
	if reason ~= "broken" and intent.tileX ~= nil and intent.tileY ~= nil then
		if intent.breakTargetKind == "tile" then
			local tileKey = BuildServiceUtils.packTileKey(intent.tileX, intent.tileY)
			self.tileDamage[tileKey] = nil
		end
	end
	intent.isBreaking = false
	intent.tileX = nil
	intent.tileY = nil
	intent.lastInputAt = 0
	intent.breakTargetKind = nil
	intent.targetTreeId = nil
	intent.targetTreeRootTileX = nil
	intent.targetTreeRootTileY = nil
	intent.targetTreeSeed = nil
	intent.targetTreeHeight = nil
	intent.lastTreeHitDirection = 0
	self:pushBreakProgress(player, false, nil, nil, 0, 0, intent.toolPower)
	if reason ~= "client_released" and reason ~= "broken" then
		self:sendActionResult(player, intent.requestId, BuildServiceUtils.ACTION_TYPE_BREAK, false, reason, nil)
	end
end

function BuildServiceServer.requestBreakTile(
	self: BuildServiceServer,
	player: Player,
	tileXRaw: any,
	tileYRaw: any,
	isBreakingRaw: any,
	requestIdRaw: any?
)
	local intent = self:getBreakIntent(player)
	local isBreaking = BuildServiceUtils.sanitizeBoolean(isBreakingRaw, false)
	intent.requestId = BuildServiceUtils.sanitizeRequestId(requestIdRaw)
	intent.lastInputAt = os.clock()
	intent.toolPower = resolvePlayerToolPower(player, self.config.defaultToolPower)
	intent.toolType = resolvePlayerToolType(player, "")

	if not isBreaking then
		self:stopBreaking(player, intent, "client_released")
		return
	end

	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		self:stopBreaking(player, intent, "invalid_tile_coordinate")
		return
	end
	if not self:isTileWithinBounds(tileY) then
		self:stopBreaking(player, intent, "tile_out_of_bounds")
		return
	end
	if not self:isBreakTargetWithinInteractionRange(player, tileX, tileY) then
		self:stopBreaking(player, intent, "out_of_range")
		return
	end

	intent.isBreaking = true
	if intent.tileX ~= tileX or intent.tileY ~= tileY then
		intent.breakTargetKind = nil
		intent.targetTreeId = nil
		intent.targetTreeRootTileX = nil
		intent.targetTreeRootTileY = nil
		intent.targetTreeSeed = nil
		intent.targetTreeHeight = nil
		intent.lastTreeHitDirection = 0
	end
	intent.tileX = tileX
	intent.tileY = tileY
end

function BuildServiceServer.processBreakIntents(self: BuildServiceServer, deltaTime: number)
	local now = os.clock()
	for player, intent in self.playerBreakIntents do
		if not intent.isBreaking then
			continue
		end
		if now - intent.lastInputAt > self.config.breakInputTimeout then
			self:stopBreaking(player, intent, "input_timeout")
			continue
		end
		local tileX = intent.tileX
		local tileY = intent.tileY
		if tileX == nil or tileY == nil then
			self:stopBreaking(player, intent, "invalid_target")
			continue
		end
		if not self:isTileWithinBounds(tileY) then
			self:stopBreaking(player, intent, "tile_out_of_bounds")
			continue
		end
		if not self:isBreakTargetWithinInteractionRange(player, tileX, tileY) then
			self:stopBreaking(player, intent, "out_of_range")
			continue
		end

		local tileId = self:getTileAtInternal(tileX, tileY)
		if tileId ~= BuildServiceUtils.AIR_TILE_ID then
			intent.breakTargetKind = "tile"
			intent.targetTreeId = nil
			intent.targetTreeRootTileX = nil
			intent.targetTreeRootTileY = nil
			intent.targetTreeSeed = nil
			intent.targetTreeHeight = nil
			intent.lastTreeHitDirection = 0

			local canBreak, reason, breakDuration = BuildServiceUtils.canBreakTile(tileId, intent.toolPower)
			if not canBreak then
				self:stopBreaking(player, intent, reason)
				continue
			end

			local tileKey = BuildServiceUtils.packTileKey(tileX, tileY)
			local damageRuntime = self.tileDamage[tileKey]
			if damageRuntime == nil then
				damageRuntime = {
					damage = 0,
					updatedAt = now,
				}
				self.tileDamage[tileKey] = damageRuntime
			end

			damageRuntime.damage += deltaTime / math.max(0.05, breakDuration)
			damageRuntime.updatedAt = now
			local progress = math.clamp(damageRuntime.damage, 0, 1)
			if now - intent.lastProgressPushAt >= self.config.breakProgressPushInterval then
				intent.lastProgressPushAt = now
				self:pushBreakProgress(player, true, tileX, tileY, progress, breakDuration, intent.toolPower)
			end

			if progress >= 1 then
				self.tileDamage[tileKey] = nil
				self:processBreakCompletion(player, intent, tileX, tileY)
				self:stopBreaking(player, intent, "broken")
			end
			continue
		end

		local treeHit = self:resolveTreeHitAt(tileX, tileY)
		if treeHit == nil then
			self:stopBreaking(player, intent, "air")
			continue
		end
		if self.treeStates[treeHit.tree.treeId] == BuildServiceUtils.TREE_STATE_FELLED then
			self:stopBreaking(player, intent, "tree_already_felled")
			continue
		end

		intent.breakTargetKind = "tree"
		intent.targetTreeId = treeHit.tree.treeId
		intent.targetTreeRootTileX = treeHit.tree.rootTileX
		intent.targetTreeRootTileY = treeHit.tree.rootTileY
		intent.targetTreeSeed = treeHit.tree.seed
		intent.targetTreeHeight = treeHit.footprint.heightTiles

		local playerTileX = self:resolvePlayerTileX(player, treeHit.tree.rootTileX)
		intent.lastTreeHitDirection = BuildServiceUtils.computeTreeFallDirection(
			treeHit.tree.rootTileX,
			playerTileX,
			tileX - treeHit.tree.rootTileX
		)

		local canBreakTree, treeReason, treeBreakDuration, treeBreakProfile =
			BuildServiceUtils.canBreakTree({
				seed = treeHit.tree.seed,
				variantIndex = treeHit.tree.variantIndex,
				biomeType = treeHit.tree.biomeType,
				biomeId = treeHit.tree.biomeId,
				heightTiles = treeHit.footprint.heightTiles,
			}, intent.toolType, intent.toolPower)
		if not canBreakTree then
			self:stopBreaking(player, intent, treeReason)
			continue
		end

		local healthPoolKey = BuildServiceUtils.getTreeHealthPoolKey(treeHit.tree.treeId)
		local treeDamageRuntime = self.treeDamage[healthPoolKey]
		if treeDamageRuntime == nil then
			treeDamageRuntime = {
				damage = 0,
				updatedAt = now,
			}
			self.treeDamage[healthPoolKey] = treeDamageRuntime
		end

		treeDamageRuntime.damage += deltaTime / math.max(0.05, treeBreakDuration)
		treeDamageRuntime.updatedAt = now
		local treeProgress = math.clamp(treeDamageRuntime.damage, 0, 1)
		if now - intent.lastProgressPushAt >= self.config.breakProgressPushInterval then
			intent.lastProgressPushAt = now
			self:pushBreakProgress(player, true, tileX, tileY, treeProgress, treeBreakDuration, intent.toolPower)
		end

		if treeProgress >= 1 then
			self.treeDamage[healthPoolKey] = nil
			self:processTreeBreakCompletion(player, intent, treeHit, treeBreakProfile)
			self:stopBreaking(player, intent, "broken")
		end
	end
end

function BuildServiceServer.pruneTileDamage(self: BuildServiceServer, deltaTime: number)
	self.damagePruneAccumulator += deltaTime
	if self.damagePruneAccumulator < DAMAGE_PRUNE_INTERVAL then
		return
	end
	self.damagePruneAccumulator = 0
	local now = os.clock()
	for tileKey, damageRuntime in self.tileDamage do
		if now - damageRuntime.updatedAt <= DEFAULT_DAMAGE_RETENTION_SECONDS then
			continue
		end
		self.tileDamage[tileKey] = nil
	end
	for treeKey, damageRuntime in self.treeDamage do
		if now - damageRuntime.updatedAt <= DEFAULT_DAMAGE_RETENTION_SECONDS then
			continue
		end
		self.treeDamage[treeKey] = nil
	end
end

function BuildServiceServer.onHeartbeat(self: BuildServiceServer, deltaTime: number)
	local nextWorld = (self.worldGenerationService :: any):getWorld()
	if nextWorld ~= self.world then
		self.world = nextWorld
		table.clear(self.pendingTileDeltas)
		table.clear(self.pendingTileDeltaLookup)
		table.clear(self.tileDamage)
		table.clear(self.treeDamage)
		table.clear(self.treeStates)
		table.clear(self.multiTileAnchors)
		table.clear(self.multiTileMembers)
	end
	if self.world == nil then
		return
	end
	self:processBreakIntents(deltaTime)
	self:pruneTileDamage(deltaTime)
	self:flushTileDeltas()
end

function BuildServiceServer.init(self: BuildServiceServer)
	local worldGenerationService = WorldGenerationServiceServer :: WorldGenerationServiceServerObject
	self.worldGenerationService = worldGenerationService
	self.inventoryService = InventoryServiceServer :: InventoryServiceServerObject
	self.lootService = LootServiceServer :: LootServiceServerObject
	self.world = worldGenerationService:getWorld()
	self.config = BuildServiceUtils.sanitizeConfig(resolveBuildConfigSource(), nil)
	self.state = BuildServiceUtils.createDefaultState()
	self.pendingTileDeltas = {} :: { TileDelta }
	self.pendingTileDeltaLookup = {} :: { [string]: number }
	self.tileDamage = {} :: { [string]: TileDamageRuntime }
	self.treeDamage = {} :: { [string]: TileDamageRuntime }
	self.treeStates = {} :: { [string]: TreeState }
	self.playerBreakIntents = {} :: { [Player]: PlayerBreakIntent }
	self.multiTileAnchors = {} :: { [string]: MultiTileAnchorRuntime }
	self.multiTileMembers = {} :: { [string]: string }
	self.damagePruneAccumulator = 0

	self.networker = Networker.server.new("BuildService", self, {
		self.requestSync,
		self.requestPlaceTile,
		self.requestBreakTile,
		self.getTileAt,
		self.canPlaceAt,
	})

	for _, player in Players:GetPlayers() do
		if shouldReplicateToPlayer(player) then
			self:trackPlayer(player)
		end
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if shouldReplicateToPlayer(player) then
			self:trackPlayer(player)
		end
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:onHeartbeat(deltaTime)
	end)
end

function BuildServiceServer.destroy(self: BuildServiceServer)
	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	table.clear(self.pendingTileDeltas)
	table.clear(self.pendingTileDeltaLookup)
	table.clear(self.tileDamage)
	table.clear(self.treeDamage)
	table.clear(self.treeStates)
	table.clear(self.playerBreakIntents)
	table.clear(self.multiTileAnchors)
	table.clear(self.multiTileMembers)

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

type BuildServiceServer = typeof(BuildServiceServer) & {
	networker: Networker.Server,
	config: BuildServiceConfig,
	state: BuildServiceState,
	worldGenerationService: WorldGenerationServiceServerObject,
	inventoryService: InventoryServiceServerObject?,
	lootService: LootServiceServerObject?,
	world: any,
	pendingTileDeltas: { TileDelta },
	pendingTileDeltaLookup: { [string]: number },
	tileDamage: { [string]: TileDamageRuntime },
	treeDamage: { [string]: TileDamageRuntime },
	treeStates: { [string]: TreeState },
	playerBreakIntents: { [Player]: PlayerBreakIntent },
	multiTileAnchors: { [string]: MultiTileAnchorRuntime },
	multiTileMembers: { [string]: string },
	damagePruneAccumulator: number,
	heartbeatConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return BuildServiceServer :: BuildServiceServer
