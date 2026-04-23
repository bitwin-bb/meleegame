--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ClientBinderSupport = require(script:FindFirstAncestor("game").Client.Binders.ClientBinderSupport)
local Lerp = require(script:FindFirstAncestor("game").Shared.Modules.Math.Lerp)
local TickSchedulerModule = require(script:FindFirstAncestor("game").Shared.Modules.Core.TickScheduler)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local WorldMutationQueue = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorldMutationQueue)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioService.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioService.AudioServiceUtils)
local LiquidServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.LiquidService.LiquidServiceUtils)
local WorldSimulationDebug = require(script:FindFirstAncestor("game").Shared.Services.WorldSimulationService.Debug)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationService.WorldGenerationServiceClient)

type LiquidServiceConfig = LiquidServiceUtils.LiquidServiceConfig
type LiquidServiceState = LiquidServiceUtils.LiquidServiceState
type LiquidChunkSnapshot = LiquidServiceUtils.LiquidChunkSnapshot
type LiquidChunkDelta = LiquidServiceUtils.LiquidChunkDelta
type LiquidStripDescriptor = LiquidServiceUtils.LiquidStripDescriptor
type CancellationToken = TickSchedulerModule.CancellationToken
type DebugObject = WorldSimulationDebug.Debug

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type ClientChunkSnapshot = LiquidChunkSnapshot

type RowVisual = {
	folder: Folder,
	parts: { [string]: BasePart },
}

type ChunkLayerVisual = {
	folder: Folder,
	rows: { [number]: RowVisual },
}

type ChunkVisual = {
	model: Model,
	frontFolder: Folder,
	backgroundFolder: Folder,
	layers: { [string]: ChunkLayerVisual },
}

type SurfaceRuntime = {
	part: BasePart,
	baseColor: Color3,
	surfaceColor: Color3,
	baseTransparency: number,
}

type LayerRenderContext = {
	layerKey: string,
	folderName: string,
	parentFolder: Folder,
	planeOffsetX: number,
	layerListIndex: number,
	backgroundLayerCount: number,
	allowSurfaceAnimation: boolean,
}

local LiquidServiceClient = {}

local LiquidMesher = LiquidServiceUtils.LiquidMesher
local LiquidColor = LiquidServiceUtils.LiquidColor
local LIQUID_TYPE = LiquidServiceUtils.LIQUID_TYPE
local WATER_SPLASH_AUDIO = (((AudioRegistry :: any).Misc or {}).Water or {})
local RANDOM = Random.new()

local VISUAL_FOLDER_NAME = "LiquidVisuals"
local FOREGROUND_LAYER_KEY = "Front"
local BACKGROUND_LAYER_KEY_PREFIX = "Background"
local WORLD_DEPENDENCY_SYNC_INTERVAL = 0.15
local BACKGROUND_DARKEN_BASE = 0.12
local BACKGROUND_DARKEN_DEPTH = 0.18
local BACKGROUND_DARKEN_MAX = 0.34
local BACKGROUND_TRANSPARENCY_BASE = 0.08
local BACKGROUND_TRANSPARENCY_DEPTH = 0.16
local BACKGROUND_TRANSPARENCY_MAX = 0.3

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function lerpColor(a: Color3, b: Color3, alpha: number): Color3
	return Lerp.color3(a, b, alpha)
end

local function darkenColor(color: Color3, amountRaw: any): Color3
	local amount = if isFiniteNumber(amountRaw) then math.clamp(amountRaw, 0, 1) else 0
	local scale = 1 - amount
	return Color3.new(color.R * scale, color.G * scale, color.B * scale)
end

local function sanitizeSourceConfig(): LiquidServiceConfig
	local source = if typeof(Configs) == "table" then (Configs :: any).liquid else nil
	return LiquidServiceUtils.sanitizeConfig(source, nil)
end

function LiquidServiceClient:CreateChunkSnapshot(snapshotRaw: any): ClientChunkSnapshot?
	if typeof(snapshotRaw) ~= "table" then
		return nil
	end
	local source = snapshotRaw :: { [string]: any }
	if typeof(source.key) ~= "string" or not isFiniteNumber(source.chunkX) or not isFiniteNumber(source.chunkY) then
		return nil
	end
	local width = if isFiniteNumber(source.width) then math.max(1, math.floor(source.width)) else self.state.chunkSize
	local height = if isFiniteNumber(source.height)
		then math.max(1, math.floor(source.height))
		else self.state.chunkSize
	local total = width * height
	local cells = Sift.Array.create(total, 0)
	local sourceCells = if typeof(source.cells) == "table" then source.cells else {}
	for index = 1, total do
		local packed = sourceCells[index]
		cells[index] = if isFiniteNumber(packed) then math.max(0, math.floor(packed)) else 0
	end
	return {
		key = source.key,
		chunkX = math.floor(source.chunkX),
		chunkY = math.floor(source.chunkY),
		tileMinX = if isFiniteNumber(source.tileMinX)
			then math.floor(source.tileMinX)
			else math.floor(source.chunkX) * width,
		tileMinY = if isFiniteNumber(source.tileMinY)
			then math.floor(source.tileMinY)
			else math.floor(source.chunkY) * height,
		width = width,
		height = height,
		cells = cells,
		revision = if isFiniteNumber(source.revision) then math.max(1, math.floor(source.revision)) else 1,
		updatedAt = os.clock(),
	}
end

function LiquidServiceClient:CreateChunkVisual(chunkKey: string): ChunkVisual
	local model = Instance.new("Model")
	model.Name = `Liquid_{chunkKey}`
	model:SetAttribute("ChunkKey", chunkKey)
	model.Parent = self.visualFolder
	TagBinder.applyTag(model, TagBinder.Tags.Liquid, CollectionService)

	local frontFolder = Instance.new("Folder")
	frontFolder.Name = "Front"
	frontFolder.Parent = model

	local backgroundFolder = Instance.new("Folder")
	backgroundFolder.Name = "BackgroundDepth"
	backgroundFolder.Parent = model

	return {
		model = model,
		frontFolder = frontFolder,
		backgroundFolder = backgroundFolder,
		layers = {},
	}
end

function LiquidServiceClient:GetChunkVisual(chunkKey: string): ChunkVisual
	local visual = self.chunkVisuals[chunkKey]
	if visual ~= nil then
		return visual
	end
	visual = self:createChunkVisual(chunkKey)
	self.chunkVisuals[chunkKey] = visual
	return visual
end

function LiquidServiceClient:GetTileDepth(): number
	local worldState = (WorldGenerationServiceClient :: any).state
	if typeof(worldState) == "table" and isFiniteNumber((worldState :: any).tileDepth) then
		return math.max(0.05, (worldState :: any).tileDepth)
	end
	return math.max(0.05, self.state.tileSize)
end

function LiquidServiceClient:GetBasePlaneX(): number
	local basePlaneX = (WorldGenerationServiceClient :: any).basePlaneX
	if isFiniteNumber(basePlaneX) then
		return basePlaneX
	end
	return 0
end

function LiquidServiceClient:GetWorldChunkSnapshot(chunkKey: string): any?
	local chunkSnapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
	if typeof(chunkSnapshots) ~= "table" then
		return nil
	end
	return chunkSnapshots[chunkKey]
end

function LiquidServiceClient:GetLayerVisual(
	chunkVisual: ChunkVisual,
	layerContext: LayerRenderContext
): ChunkLayerVisual
	local layerVisual = chunkVisual.layers[layerContext.layerKey]
	if layerVisual ~= nil then
		return layerVisual
	end
	local folder = Instance.new("Folder")
	folder.Name = layerContext.folderName
	folder.Parent = layerContext.parentFolder
	layerVisual = {
		folder = folder,
		rows = {},
	}
	chunkVisual.layers[layerContext.layerKey] = layerVisual
	return layerVisual
end

function LiquidServiceClient:GetRowVisual(layerVisual: ChunkLayerVisual, rowY: number): RowVisual
	local rowVisual = layerVisual.rows[rowY]
	if rowVisual ~= nil then
		return rowVisual
	end
	local folder = Instance.new("Folder")
	folder.Name = `Row_{rowY}`
	folder.Parent = layerVisual.folder
	rowVisual = {
		folder = folder,
		parts = {},
	}
	layerVisual.rows[rowY] = rowVisual
	return rowVisual
end

function LiquidServiceClient:MarkAllRowsDirtyForChunk(chunkKey: string)
	local snapshot = self.chunkSnapshots[chunkKey]
	if snapshot == nil then
		return
	end
	local allRows = Sift.Array.create(snapshot.height)
	for rowY = 0, snapshot.height - 1 do
		allRows[#allRows + 1] = rowY
	end
	self:markRowsDirty(chunkKey, allRows)
end

function LiquidServiceClient:MarkAllChunksDirty()
	for chunkKey in self.chunkSnapshots do
		self:markAllRowsDirtyForChunk(chunkKey)
	end
end

function LiquidServiceClient:ComputeWorldDependencySignature(chunkKey: string): string
	local basePlaneX = math.round(self:getBasePlaneX() * 1000) / 1000
	local tileDepth = math.round(self:getTileDepth() * 1000) / 1000
	local worldSnapshot = self:getWorldChunkSnapshot(chunkKey)
	if typeof(worldSnapshot) ~= "table" then
		return `missing:{basePlaneX}:{tileDepth}`
	end
	local revision = if isFiniteNumber((worldSnapshot :: any).revision)
		then math.floor((worldSnapshot :: any).revision)
		else 0
	local backgroundLayers = if typeof((worldSnapshot :: any).backgroundLayers) == "table"
		then (worldSnapshot :: any).backgroundLayers :: { any }
		else {}
	return `{revision}:{#backgroundLayers}:{basePlaneX}:{tileDepth}`
end

function LiquidServiceClient:SyncWorldChunkDependencies()
	for chunkKey in self.chunkSnapshots do
		local signature = self:computeWorldDependencySignature(chunkKey)
		if self.worldDependencySignatureByChunk[chunkKey] == signature then
			continue
		end
		self.worldDependencySignatureByChunk[chunkKey] = signature
		self:markAllRowsDirtyForChunk(chunkKey)
	end
	local staleChunkKeys = {} :: { string }
	for chunkKey in self.worldDependencySignatureByChunk do
		if self.chunkSnapshots[chunkKey] ~= nil then
			continue
		end
		staleChunkKeys[#staleChunkKeys + 1] = chunkKey
	end
	for _, chunkKey in staleChunkKeys do
		self.worldDependencySignatureByChunk[chunkKey] = nil
	end
end

function LiquidServiceClient:UpdateChunkVisualDebug(chunkKey: string, extraRaw: any?)
	local chunkVisual = self:getChunkVisual(chunkKey)
	local snapshot = self.chunkSnapshots[chunkKey]
	local worldSnapshot = self:getWorldChunkSnapshot(chunkKey)
	local extra = if typeof(extraRaw) == "table" then extraRaw :: { [string]: any } else {}
	chunkVisual.model:SetAttribute("ChunkKey", chunkKey)
	if snapshot ~= nil then
		chunkVisual.model:SetAttribute("AuthoritativeRevision", snapshot.revision)
		chunkVisual.model:SetAttribute("AuthoritativeUpdatedAt", snapshot.updatedAt)
		chunkVisual.model:SetAttribute("PendingDirtyRows", self.queuedRowCountsByChunk[chunkKey] or 0)
	end
	chunkVisual.model:SetAttribute(
		"WorldChunkRevision",
		if typeof(worldSnapshot) == "table" and isFiniteNumber((worldSnapshot :: any).revision)
			then math.floor((worldSnapshot :: any).revision)
			else 0
	)
	chunkVisual.model:SetAttribute(
		"BackgroundLiquidLayerCount",
		if typeof(worldSnapshot) == "table" and typeof((worldSnapshot :: any).backgroundLayers) == "table"
			then #((worldSnapshot :: any).backgroundLayers :: { any })
			else 0
	)
	if typeof(self.worldDependencySignatureByChunk[chunkKey]) == "string" then
		chunkVisual.model:SetAttribute("WorldDependencySignature", self.worldDependencySignatureByChunk[chunkKey])
	end
	if isFiniteNumber(extra.LastDeltaCells) then
		chunkVisual.model:SetAttribute("LastDeltaCells", math.floor(extra.LastDeltaCells))
	end
	if typeof(extra.LastUpdateKind) == "string" then
		chunkVisual.model:SetAttribute("LastUpdateKind", extra.LastUpdateKind)
	end
	if isFiniteNumber(extra.LastServerUpdatedAt) then
		chunkVisual.model:SetAttribute("LastServerUpdatedAt", extra.LastServerUpdatedAt)
	end
end

function LiquidServiceClient:UpdateClientDebugStats()
	if self.visualFolder == nil then
		return
	end
	local queuedRows = if self.rebuildQueue ~= nil then self.rebuildQueue:getPendingCount() else 0
	local visualChunkCount = 0
	local worldChunkSnapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
	if typeof(worldChunkSnapshots) == "table" then
		for _ in worldChunkSnapshots do
			visualChunkCount += 1
		end
	end
	local liquidChunkCount = 0
	for _ in self.chunkSnapshots do
		liquidChunkCount += 1
	end
	self.visualFolder:SetAttribute("QueuedRows", queuedRows)
	self.visualFolder:SetAttribute("QueuedChunks", self.queuedChunkCount)
	self.visualFolder:SetAttribute("VisualChunksLoaded", visualChunkCount)
	self.visualFolder:SetAttribute("LiquidChunksLoaded", liquidChunkCount)
	if self.debug ~= nil then
		local counters = self.debug:getCounters()
		self.visualFolder:SetAttribute(
			"TimeClientRebuildMs",
			math.round(((counters.time_liquid_client_rebuild or 0) * 1000) * 100) / 100
		)
		self.visualFolder:SetAttribute(
			"TimeClientSurfaceMs",
			math.round(((counters.time_liquid_client_surface or 0) * 1000) * 100) / 100
		)
	end
end

function LiquidServiceClient:ClearQueuedRowsForChunk(chunkKey: string)
	local prefix = `{chunkKey}:`
	for rowKey in self.queuedRowLookup do
		if string.sub(rowKey, 1, #prefix) ~= prefix then
			continue
		end
		self.queuedRowLookup[rowKey] = nil
	end
	if self.queuedRowCountsByChunk[chunkKey] ~= nil then
		self.queuedRowCountsByChunk[chunkKey] = nil
		if self.queuedChunkCount > 0 then
			self.queuedChunkCount -= 1
		end
	end
end

function LiquidServiceClient:MarkRowsDirty(chunkKey: string, rows: { number })
	local snapshot = self.chunkSnapshots[chunkKey]
	if snapshot == nil then
		return
	end
	local queuedCount = 0
	for _, rowY in rows do
		local rowKey = `{chunkKey}:{rowY}`
		if self.queuedRowLookup[rowKey] then
			continue
		end
		self.queuedRowLookup[rowKey] = true
		if self.queuedRowCountsByChunk[chunkKey] == nil or self.queuedRowCountsByChunk[chunkKey] <= 0 then
			self.queuedChunkCount += 1
		end
		self.queuedRowCountsByChunk[chunkKey] = (self.queuedRowCountsByChunk[chunkKey] or 0) + 1
		self.rebuildQueue:enqueue({
			x = snapshot.tileMinX,
			y = snapshot.tileMinY + rowY,
			z = 0,
			tileId = snapshot.revision,
			metadata = {
				chunkKey = chunkKey,
				rowY = rowY,
			},
		})
		queuedCount += 1
	end
	if self.debug ~= nil and queuedCount > 0 then
		self.debug:incrementCounter("liquid_client_rebuild_requests", queuedCount)
	end
	self:updateChunkVisualDebug(chunkKey)
	self:updateClientDebugStats()
end

function LiquidServiceClient:GetBiomeAtTile(tileX: number, tileY: number): (number, number)
	local chunkSnapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
	local chunkSize = math.max(1, self.state.chunkSize)
	local chunkX = LiquidServiceUtils.toChunkCoordinate(tileX, chunkSize)
	local chunkY = LiquidServiceUtils.toChunkCoordinate(tileY, chunkSize)
	local chunkKey = LiquidServiceUtils.packChunkKey(chunkX, chunkY)
	local snapshot = if typeof(chunkSnapshots) == "table" then chunkSnapshots[chunkKey] else nil
	if typeof(snapshot) ~= "table" then
		return 1, 1
	end

	local localX = tileX - snapshot.tileMinX
	local localY = tileY - snapshot.tileMinY
	if localX < 0 or localX >= snapshot.width or localY < 0 or localY >= snapshot.height then
		return snapshot.dominantBiomeId or 1, snapshot.dominantBiomeType or 1
	end

	local index = LiquidServiceUtils.computeTileIndex(localX, localY, snapshot.width)
	local biomeIds = snapshot.biomeIds
	local biomeTypes = snapshot.biomeTypes
	local biomeId = if typeof(biomeIds) == "table" and isFiniteNumber(biomeIds[index])
		then math.floor(biomeIds[index])
		else 1
	local biomeType = if typeof(biomeTypes) == "table" and isFiniteNumber(biomeTypes[index])
		then math.floor(biomeTypes[index])
		else 1
	return biomeId, biomeType
end

function LiquidServiceClient:CreateLayerRenderContext(
	chunkVisual: ChunkVisual,
	layerListIndex: number,
	backgroundLayerCount: number
): LayerRenderContext
	if layerListIndex <= 0 then
		return {
			layerKey = FOREGROUND_LAYER_KEY,
			folderName = "Volume",
			parentFolder = chunkVisual.frontFolder,
			planeOffsetX = 0,
			layerListIndex = 0,
			backgroundLayerCount = backgroundLayerCount,
			allowSurfaceAnimation = true,
		}
	end

	local tileDepth = self:getTileDepth()
	return {
		layerKey = `{BACKGROUND_LAYER_KEY_PREFIX}_{layerListIndex}`,
		folderName = `Layer_{layerListIndex}`,
		parentFolder = chunkVisual.backgroundFolder,
		planeOffsetX = -(layerListIndex * tileDepth),
		layerListIndex = layerListIndex,
		backgroundLayerCount = backgroundLayerCount,
		allowSurfaceAnimation = false,
	}
end

function LiquidServiceClient:ApplyPartDescriptor(
	part: BasePart,
	snapshot: ClientChunkSnapshot,
	descriptor: LiquidStripDescriptor,
	layerContext: LayerRenderContext
)
	local definition = self.config.definitions[descriptor.typeId]
	if definition == nil then
		return
	end
	local tileSize = self.state.tileSize
	local tileDepth = self:getTileDepth()
	local worldOrigin = self.state.worldOrigin
	local centerTileX = snapshot.tileMinX + descriptor.startX + descriptor.widthTiles * 0.5
	local worldZ = worldOrigin.Z + centerTileX * tileSize
	local bottomY = worldOrigin.Y + (snapshot.tileMinY + descriptor.rowY) * tileSize
	local heightStuds = if descriptor.isSurface
		then math.max(tileSize * 0.04, descriptor.fillAlpha * tileSize)
		else tileSize
	local centerY = bottomY + heightStuds * 0.5
	local worldX = worldOrigin.X + self:getBasePlaneX() + layerContext.planeOffsetX
	local targetCFrame = CFrame.new(worldX, centerY, worldZ)
	local targetSize = Vector3.new(tileDepth, heightStuds, descriptor.widthTiles * tileSize)
	local samplePosition = Vector3.new(worldX, centerY, worldZ)
	local biomeId, biomeType =
		self:getBiomeAtTile(snapshot.tileMinX + descriptor.startX, snapshot.tileMinY + descriptor.rowY)
	local baseColor = if descriptor.typeId == LIQUID_TYPE.WATER
		then LiquidColor.sampleWaterColorAtWorldPosition(
			self.config,
			samplePosition,
			tileSize,
			worldOrigin,
			function(tileX: number, tileY: number): (number, number)
				return self:getBiomeAtTile(tileX, tileY)
			end
		)
		else LiquidColor.resolveLiquidColor(self.config, descriptor.typeId, biomeId, biomeType)
	local surfaceBlendAlpha = if layerContext.layerListIndex > 0 then 0.28 else 0.42
	local surfaceColor = lerpColor(baseColor, definition.surfaceColor, surfaceBlendAlpha)
	local targetColor = if descriptor.isSurface then surfaceColor else baseColor
	local targetTransparency = if descriptor.isSurface
		then definition.surfaceTransparency
		else definition.interiorTransparency
	if layerContext.layerListIndex > 0 then
		local depthAlpha = if layerContext.backgroundLayerCount > 0
			then math.clamp(layerContext.layerListIndex / layerContext.backgroundLayerCount, 0, 1)
			else 1
		local darkenAlpha =
			math.min(BACKGROUND_DARKEN_MAX, BACKGROUND_DARKEN_BASE + depthAlpha * BACKGROUND_DARKEN_DEPTH)
		local extraTransparency = math.min(
			BACKGROUND_TRANSPARENCY_MAX,
			BACKGROUND_TRANSPARENCY_BASE + depthAlpha * BACKGROUND_TRANSPARENCY_DEPTH
		)
		targetColor = darkenColor(targetColor, darkenAlpha)
		targetTransparency = math.clamp(targetTransparency + extraTransparency, 0, 0.95)
	end

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = definition.material
	part.Size = targetSize
	part.CFrame = targetCFrame
	part.Color = targetColor
	part.Transparency = targetTransparency

	if descriptor.isSurface and layerContext.allowSurfaceAnimation then
		self.surfaceParts[part] = {
			part = part,
			baseColor = targetColor,
			surfaceColor = definition.surfaceColor,
			baseTransparency = targetTransparency,
		}
	else
		self.surfaceParts[part] = nil
	end
end

function LiquidServiceClient:FadeAndDestroyPart(part: BasePart)
	self.surfaceParts[part] = nil
	if part.Parent ~= nil then
		part:Destroy()
	end
end

function LiquidServiceClient:RebuildLayerRow(
	chunkVisual: ChunkVisual,
	snapshot: ClientChunkSnapshot,
	rowY: number,
	cells: { number },
	layerContext: LayerRenderContext
)
	local descriptors = LiquidMesher.buildRowDescriptors(self.config, cells, snapshot.width, snapshot.height, rowY)
	local existingLayerVisual = chunkVisual.layers[layerContext.layerKey]
	local existingRowVisual = if existingLayerVisual ~= nil then existingLayerVisual.rows[rowY] else nil
	if #descriptors <= 0 and existingRowVisual == nil then
		return
	end

	local layerVisual = existingLayerVisual
	if layerVisual == nil then
		layerVisual = self:getLayerVisual(chunkVisual, layerContext)
	end
	local rowVisual = existingRowVisual
	if rowVisual == nil then
		rowVisual = self:getRowVisual(layerVisual, rowY)
	end
	local nextKeys: { [string]: boolean } = {}

	for _, descriptor in descriptors do
		nextKeys[descriptor.key] = true
		local part = rowVisual.parts[descriptor.key]
		if part == nil or part.Parent == nil then
			part = Instance.new("Part")
			part.Name = descriptor.key
			part.Size =
				Vector3.new(self:getTileDepth(), 0.02, math.max(0.02, descriptor.widthTiles * self.state.tileSize))
			part.Transparency = 1
			part.Parent = rowVisual.folder
			rowVisual.parts[descriptor.key] = part
		end
		self:applyPartDescriptor(part, snapshot, descriptor, layerContext)
	end

	for key, part in rowVisual.parts do
		if nextKeys[key] then
			continue
		end
		rowVisual.parts[key] = nil
		self:fadeAndDestroyPart(part)
	end
end

function LiquidServiceClient:ClearInactiveLayerRows(
	chunkVisual: ChunkVisual,
	rowY: number,
	activeLayerKeys: { [string]: boolean }
)
	for layerKey, layerVisual in chunkVisual.layers do
		if activeLayerKeys[layerKey] then
			continue
		end
		local rowVisual = layerVisual.rows[rowY]
		if rowVisual == nil then
			continue
		end
		for key, part in rowVisual.parts do
			rowVisual.parts[key] = nil
			self:fadeAndDestroyPart(part)
		end
	end
end

function LiquidServiceClient:RebuildRow(chunkKey: string, rowY: number)
	local snapshot = self.chunkSnapshots[chunkKey]
	if snapshot == nil then
		return
	end
	local chunkVisual = self:getChunkVisual(chunkKey)
	local worldSnapshot = self:getWorldChunkSnapshot(chunkKey)
	local activeLayerKeys: { [string]: boolean } = {}
	local backgroundLayers: { any } = if typeof(worldSnapshot) == "table"
			and typeof((worldSnapshot :: any).backgroundLayers) == "table"
		then (worldSnapshot :: any).backgroundLayers :: { any }
		else {}

	local frontLayerContext = self:createLayerRenderContext(chunkVisual, 0, #backgroundLayers)
	activeLayerKeys[frontLayerContext.layerKey] = true
	self:rebuildLayerRow(chunkVisual, snapshot, rowY, snapshot.cells, frontLayerContext)

	local sourceCells = snapshot.cells
	for layerListIndex, layerData in backgroundLayers do
		local derivedCells = LiquidMesher.buildBackgroundVisualCells(
			self.config,
			sourceCells,
			snapshot.tileMinX,
			snapshot.tileMinY,
			snapshot.width,
			snapshot.height,
			layerData,
			layerListIndex
		)
		local layerContext = self:createLayerRenderContext(chunkVisual, layerListIndex, #backgroundLayers)
		activeLayerKeys[layerContext.layerKey] = true
		self:rebuildLayerRow(chunkVisual, snapshot, rowY, derivedCells, layerContext)
		sourceCells = derivedCells
	end

	self:clearInactiveLayerRows(chunkVisual, rowY, activeLayerKeys)
end

function LiquidServiceClient:ProcessDirtyRows(deltaTimeRaw: any?)
	if self.debug ~= nil then
		self.debug:resetFrameCounters()
	end
	local token = if self.debug ~= nil then self.debug:beginFrameScope("liquid_client_rebuild") else nil
	local deltaTime = if isFiniteNumber(deltaTimeRaw) and deltaTimeRaw > 0
		then deltaTimeRaw
		else self.config.render.rebuildFlushInterval
	local batches = self.rebuildQueue:update(deltaTime)
	for _, batch in batches do
		for _, chunkBatch in batch.chunks do
			for _, mutation in chunkBatch.mutations do
				if typeof(mutation) ~= "table" then
					continue
				end
				local metadata = if typeof(mutation.metadata) == "table" then mutation.metadata else nil
				local chunkKey = if metadata ~= nil and typeof(metadata.chunkKey) == "string"
					then metadata.chunkKey
					else LiquidServiceUtils.packChunkKey(chunkBatch.chunkX, chunkBatch.chunkY)
				local rowY = if metadata ~= nil and isFiniteNumber(metadata.rowY)
					then math.floor(metadata.rowY)
					else nil
				if rowY == nil then
					continue
				end
				local rowKey = `{chunkKey}:{rowY}`
				if self.queuedRowLookup[rowKey] then
					self.queuedRowLookup[rowKey] = nil
					local nextCount = math.max(0, (self.queuedRowCountsByChunk[chunkKey] or 0) - 1)
					if nextCount <= 0 then
						self.queuedRowCountsByChunk[chunkKey] = nil
						if self.queuedChunkCount > 0 then
							self.queuedChunkCount -= 1
						end
					else
						self.queuedRowCountsByChunk[chunkKey] = nextCount
					end
				end
				self:rebuildRow(chunkKey, rowY)
				self:updateChunkVisualDebug(chunkKey)
				if self.debug ~= nil then
					self.debug:incrementCounter("liquid_client_rows_rebuilt")
				end
			end
		end
	end
	if self.debug ~= nil then
		self.debug:setCounter(
			"liquid_client_queued_rows",
			if self.rebuildQueue ~= nil then self.rebuildQueue:getPendingCount() else 0
		)
		self.debug:setCounter("liquid_client_queued_chunks", self.queuedChunkCount)
		self.debug:endFrameScope("liquid_client_rebuild", token)
	end
	self:updateClientDebugStats()
end

function LiquidServiceClient:OnChunkSnapshot(snapshotRaw: any)
	local snapshot = self:createChunkSnapshot(snapshotRaw)
	if snapshot == nil then
		return
	end
	self.chunkSnapshots[snapshot.key] = snapshot
	self.worldDependencySignatureByChunk[snapshot.key] = self:computeWorldDependencySignature(snapshot.key)
	self:updateChunkVisualDebug(snapshot.key, {
		LastUpdateKind = "snapshot",
		LastServerUpdatedAt = if typeof(snapshotRaw) == "table" and isFiniteNumber((snapshotRaw :: any).updatedAt)
			then (snapshotRaw :: any).updatedAt
			else nil,
	})
	self:markAllRowsDirtyForChunk(snapshot.key)
	self:updateClientDebugStats()
end

function LiquidServiceClient:OnChunkDelta(deltaRaw: any)
	if typeof(deltaRaw) ~= "table" then
		return
	end
	local source = deltaRaw :: { [string]: any }
	if typeof(source.key) ~= "string" then
		return
	end
	local snapshot = self.chunkSnapshots[source.key]
	if snapshot == nil then
		self:requestSync()
		return
	end

	local changedIndices: { number } = {}
	local changes = if typeof(source.changes) == "table" then source.changes else {}
	for _, changeRaw in changes do
		if typeof(changeRaw) ~= "table" then
			continue
		end
		local index = if isFiniteNumber(changeRaw.index) then math.floor(changeRaw.index) else nil
		if index == nil or index < 1 or index > #snapshot.cells then
			continue
		end
		local packedCell = if isFiniteNumber(changeRaw.cell) then math.max(0, math.floor(changeRaw.cell)) else 0
		snapshot.cells[index] = packedCell
		table.insert(changedIndices, index)
	end
	if #changedIndices <= 0 then
		return
	end
	snapshot.revision = if isFiniteNumber(source.revision)
		then math.max(snapshot.revision, math.floor(source.revision))
		else snapshot.revision
	snapshot.updatedAt = os.clock()
	self:updateChunkVisualDebug(source.key, {
		LastDeltaCells = #changedIndices,
		LastUpdateKind = "delta",
		LastServerUpdatedAt = if isFiniteNumber(source.updatedAt) then source.updatedAt else nil,
	})
	self:markRowsDirty(
		source.key,
		LiquidMesher.getAffectedRowsForChanges(snapshot.width, snapshot.height, changedIndices)
	)
	self:updateClientDebugStats()
end

function LiquidServiceClient:DestroyChunkVisual(chunkKey: string)
	local visual = self.chunkVisuals[chunkKey]
	if visual == nil then
		return
	end
	for _, layerVisual in visual.layers do
		for _, rowVisual in layerVisual.rows do
			for _, part in rowVisual.parts do
				self.surfaceParts[part] = nil
			end
		end
	end
	visual.model:Destroy()
	self.chunkVisuals[chunkKey] = nil
end

function LiquidServiceClient:OnChunkUnloaded(chunkKeyRaw: any)
	if typeof(chunkKeyRaw) ~= "string" then
		return
	end
	self.chunkSnapshots[chunkKeyRaw] = nil
	self.worldDependencySignatureByChunk[chunkKeyRaw] = nil
	self:clearQueuedRowsForChunk(chunkKeyRaw)
	self:destroyChunkVisual(chunkKeyRaw)
	self:updateClientDebugStats()
end

function LiquidServiceClient:GetBurnAttachment(): Attachment?
	local character = self.localPlayer.Character
	if character == nil then
		return nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return nil
	end
	local attachment = rootPart:FindFirstChild("LiquidBurnAttachment")
	if attachment ~= nil and attachment:IsA("Attachment") then
		return attachment
	end
	attachment = Instance.new("Attachment")
	attachment.Name = "LiquidBurnAttachment"
	attachment.Parent = rootPart
	return attachment
end

function LiquidServiceClient:SetBurningVisualEnabled(enabled: boolean)
	local attachment = self:getBurnAttachment()
	if attachment == nil then
		return
	end
	if self.burnEmitter == nil or self.burnEmitter.Parent ~= attachment then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "LiquidBurnEmitter"
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 176, 74), Color3.fromRGB(255, 77, 18))
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Lifetime = NumberRange.new(0.2, 0.45)
		emitter.Rate = 0
		emitter.Speed = NumberRange.new(0.8, 1.6)
		emitter.SpreadAngle = Vector2.new(18, 18)
		emitter.Parent = attachment
		self.burnEmitter = emitter
	end
	self.burnEmitter.Enabled = enabled
	self.burnEmitter.Rate = if enabled then 26 else 0
end

function LiquidServiceClient:RefreshWaterSplashSoundAssetIds()
	self.waterSplashSoundAssetIds = AudioServiceUtils.collectSoundAssetIds(WATER_SPLASH_AUDIO)
end

function LiquidServiceClient:PickWaterSplashSoundAssetId(): string?
	if #self.waterSplashSoundAssetIds <= 0 then
		self:refreshWaterSplashSoundAssetIds()
	end
	local count = #self.waterSplashSoundAssetIds
	if count <= 0 then
		return nil
	end
	return self.waterSplashSoundAssetIds[RANDOM:NextInteger(1, count)]
end

function LiquidServiceClient:PlayWaterSplashSound()
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	local character = self.localPlayer.Character
	if character == nil then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local soundAssetId = self:pickWaterSplashSoundAssetId()
	if soundAssetId == nil then
		return
	end

	AudioServiceClient:playSfx(soundAssetId, {
		parent = rootPart,
		volume = 0.68,
		playbackSpeed = RANDOM:NextNumber(0.94, 1.08),
		rollOffMaxDistance = 96,
		emitterSize = 8,
	})
end

function LiquidServiceClient:EmitSplash(liquidTypeRaw: any)
	local character = self.localPlayer.Character
	if character == nil then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "LiquidSplashAttachment"
	attachment.Parent = rootPart
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(2.5, 4.8)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Drag = 2
	local liquidType = if isFiniteNumber(liquidTypeRaw) then math.floor(liquidTypeRaw) else 0
	if liquidType == LIQUID_TYPE.LAVA then
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 187, 76), Color3.fromRGB(255, 89, 34))
		emitter.Size = NumberSequence.new(0.22)
	else
		emitter.Color = ColorSequence.new(Color3.fromRGB(168, 232, 255), Color3.fromRGB(74, 174, 225))
		emitter.Size = NumberSequence.new(0.18)
	end
	emitter.Parent = attachment
	emitter:Emit(16)
	task.delay(1, function()
		attachment:Destroy()
	end)
end

function LiquidServiceClient:OnEffectEvent(payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local eventType = if typeof(payload.eventType) == "string" then payload.eventType else ""
	local liquidType = if isFiniteNumber(payload.liquidType) then math.floor(payload.liquidType) else 0
	if eventType == LiquidServiceUtils.EFFECT_EVENT.ENTER or eventType == LiquidServiceUtils.EFFECT_EVENT.EXIT then
		self:emitSplash(liquidType)
	end
	if eventType == LiquidServiceUtils.EFFECT_EVENT.ENTER and liquidType == LIQUID_TYPE.WATER then
		self:playWaterSplashSound()
	end
	if eventType == LiquidServiceUtils.EFFECT_EVENT.BURN_START then
		self:setBurningVisualEnabled(true)
	elseif eventType == LiquidServiceUtils.EFFECT_EVENT.BURN_END then
		self:setBurningVisualEnabled(false)
	end
	self.effectEvent:Fire(payload)
end

function LiquidServiceClient:StepSurfaceAnimation(now: number)
	for part, runtime in self.surfaceParts do
		if part.Parent == nil then
			self.surfaceParts[part] = nil
			continue
		end
		local wave = (
			math.noise(
				now * self.config.render.surfaceWaveSpeed,
				part.Position.Z * self.config.render.surfaceWaveScale,
				0
			) + 1
		) * 0.5
		part.Color = lerpColor(runtime.baseColor, runtime.surfaceColor, wave * 0.22)
		part.Transparency = math.clamp(runtime.baseTransparency - wave * 0.04, 0, 1)
	end
end

function LiquidServiceClient:OnRenderStep(_deltaTime: number)
	local token = if self.debug ~= nil then self.debug:beginFrameScope("liquid_client_surface") else nil
	self.dependencySyncAccumulator += if isFiniteNumber(_deltaTime) then math.max(0, _deltaTime) else 0
	if self.dependencySyncAccumulator >= WORLD_DEPENDENCY_SYNC_INTERVAL then
		self.dependencySyncAccumulator = 0
		self:syncWorldChunkDependencies()
	end
	if self.rebuildToken == nil then
		self:processDirtyRows(_deltaTime)
	end
	self:stepSurfaceAnimation(os.clock())
	if self.debug ~= nil then
		self.debug:endFrameScope("liquid_client_surface", token)
	end
	self:updateClientDebugStats()
end

function LiquidServiceClient:RecreateRebuildQueue()
	if self.rebuildQueue ~= nil then
		self.rebuildQueue:destroy()
	end
	if self.queuedRowLookup ~= nil then
		table.clear(self.queuedRowLookup)
	end
	if self.queuedRowCountsByChunk ~= nil then
		table.clear(self.queuedRowCountsByChunk)
	end
	self.queuedChunkCount = 0
	self.rebuildQueue = WorldMutationQueue.new({
		chunkSize = math.max(1, self.state.chunkSize),
		flushInterval = self.config.render.rebuildFlushInterval,
		maxMutationsPerFlush = self.config.render.rebuildRowsPerFrame,
	})
end

function LiquidServiceClient:ApplyState(stateRaw: any)
	local previousState = self.state
	local previousChunkSize = if self.state ~= nil then self.state.chunkSize else nil
	self.state = LiquidServiceUtils.createState(stateRaw, self.state)
	if previousChunkSize == nil or previousChunkSize ~= self.state.chunkSize then
		self:recreateRebuildQueue()
	end
	local geometryChanged = previousState == nil
		or previousState.tileSize ~= self.state.tileSize
		or previousState.worldOrigin ~= self.state.worldOrigin
		or previousState.maxFill ~= self.state.maxFill
		or previousState.interpolationTime ~= self.state.interpolationTime
	if geometryChanged then
		self:markAllChunksDirty()
	end
	self.stateChanged:Fire(LiquidServiceUtils.cloneState(self.state))
end

function LiquidServiceClient:RequestSync()
	self.networker:fire(LiquidServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function LiquidServiceClient:Init()
	self.localPlayer = Players.LocalPlayer
	self.runtimeContext = CoreRuntime.getClientRuntime()
	if self.runtimeContext ~= nil and typeof((self.runtimeContext :: any).init) == "function" then
		local runtimeAny = self.runtimeContext :: any
		runtimeAny:init()
	end
	self.config = sanitizeSourceConfig()
	self.state = LiquidServiceUtils.createDefaultState()
	self.debug = WorldSimulationDebug.new({
		enabled = self.config.debug.enabled,
		profilingEnabled = self.config.debug.enabled,
	})
	self.networker = Networker.client.new("LiquidService", self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.effectEvent = Signal.new()
	self.chunkSnapshots = {} :: { [string]: ClientChunkSnapshot }
	self.chunkVisuals = {} :: { [string]: ChunkVisual }
	self.surfaceParts = {} :: { [BasePart]: SurfaceRuntime }
	self.waterSplashSoundAssetIds = {} :: { string }
	self.queuedRowLookup = {} :: { [string]: boolean }
	self.queuedRowCountsByChunk = {} :: { [string]: number }
	self.queuedChunkCount = 0
	self.worldDependencySignatureByChunk = {} :: { [string]: string }
	self.dependencySyncAccumulator = WORLD_DEPENDENCY_SYNC_INTERVAL
	self.visualFolder = WorkspaceFolders.getOrCreateFolderInGame(VISUAL_FOLDER_NAME)
	self.burnEmitter = nil :: ParticleEmitter?
	self.binders = NevermoreSupport.getService(ClientBinderSupport)
	self:refreshWaterSplashSoundAssetIds()
	self:recreateRebuildQueue()

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
		self.effectEvent:Destroy()
	end)
	local worldStateChanged = (WorldGenerationServiceClient :: any).stateChanged
	if worldStateChanged ~= nil and typeof((worldStateChanged :: any).Connect) == "function" then
		self.janitor:GiveChore((worldStateChanged :: any):Connect(function()
			self:markAllChunksDirty()
		end))
	end
	self.janitor:GiveChore(RunService.RenderStepped:Connect(function(deltaTime: number)
		self:onRenderStep(deltaTime)
	end))
	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function()
		self:setBurningVisualEnabled(false)
	end))
	local tickScheduler = if self.runtimeContext ~= nil then (self.runtimeContext :: any).tickScheduler else nil
	if tickScheduler ~= nil and typeof((tickScheduler :: any).scheduleEvery) == "function" then
		self.rebuildToken = (tickScheduler :: any):scheduleEvery(
			function(deltaTime: number)
				self:processDirtyRows(deltaTime)
			end,
			self.config.render.rebuildFlushInterval,
			{
				group = "service.liquid.client",
				priority = TickSchedulerModule.Priority.NORMAL,
				catchUp = false,
			}
		)
		self.janitor:GiveChore(function()
			if self.rebuildToken ~= nil and typeof(self.rebuildToken.cancel) == "function" then
				self.rebuildToken:cancel()
				self.rebuildToken = nil
			end
		end)
	end

	self:requestSync()
end

function LiquidServiceClient:Destroy()
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
	for chunkKey in self.chunkVisuals do
		self:destroyChunkVisual(chunkKey)
	end
	table.clear(self.chunkSnapshots)
	table.clear(self.surfaceParts)
	table.clear(self.queuedRowLookup)
	table.clear(self.queuedRowCountsByChunk)
	table.clear(self.worldDependencySignatureByChunk)
	if self.rebuildQueue ~= nil then
		self.rebuildQueue:destroy()
	end
	if self.debug ~= nil then
		self.debug:destroy()
	end
	if self.visualFolder ~= nil then
		self.visualFolder:Destroy()
	end
	if self.burnEmitter ~= nil and self.burnEmitter.Parent ~= nil then
		self.burnEmitter:Destroy()
	end
end

LiquidServiceClient.createChunkSnapshot = LiquidServiceClient.CreateChunkSnapshot
LiquidServiceClient.createChunkVisual = LiquidServiceClient.CreateChunkVisual
LiquidServiceClient.getChunkVisual = LiquidServiceClient.GetChunkVisual
LiquidServiceClient.getTileDepth = LiquidServiceClient.GetTileDepth
LiquidServiceClient.getBasePlaneX = LiquidServiceClient.GetBasePlaneX
LiquidServiceClient.getWorldChunkSnapshot = LiquidServiceClient.GetWorldChunkSnapshot
LiquidServiceClient.getLayerVisual = LiquidServiceClient.GetLayerVisual
LiquidServiceClient.getRowVisual = LiquidServiceClient.GetRowVisual
LiquidServiceClient.markAllRowsDirtyForChunk = LiquidServiceClient.MarkAllRowsDirtyForChunk
LiquidServiceClient.markAllChunksDirty = LiquidServiceClient.MarkAllChunksDirty
LiquidServiceClient.computeWorldDependencySignature = LiquidServiceClient.ComputeWorldDependencySignature
LiquidServiceClient.syncWorldChunkDependencies = LiquidServiceClient.SyncWorldChunkDependencies
LiquidServiceClient.updateChunkVisualDebug = LiquidServiceClient.UpdateChunkVisualDebug
LiquidServiceClient.updateClientDebugStats = LiquidServiceClient.UpdateClientDebugStats
LiquidServiceClient.clearQueuedRowsForChunk = LiquidServiceClient.ClearQueuedRowsForChunk
LiquidServiceClient.markRowsDirty = LiquidServiceClient.MarkRowsDirty
LiquidServiceClient.getBiomeAtTile = LiquidServiceClient.GetBiomeAtTile
LiquidServiceClient.createLayerRenderContext = LiquidServiceClient.CreateLayerRenderContext
LiquidServiceClient.applyPartDescriptor = LiquidServiceClient.ApplyPartDescriptor
LiquidServiceClient.fadeAndDestroyPart = LiquidServiceClient.FadeAndDestroyPart
LiquidServiceClient.rebuildLayerRow = LiquidServiceClient.RebuildLayerRow
LiquidServiceClient.clearInactiveLayerRows = LiquidServiceClient.ClearInactiveLayerRows
LiquidServiceClient.rebuildRow = LiquidServiceClient.RebuildRow
LiquidServiceClient.processDirtyRows = LiquidServiceClient.ProcessDirtyRows
LiquidServiceClient.onChunkSnapshot = LiquidServiceClient.OnChunkSnapshot
LiquidServiceClient.onChunkDelta = LiquidServiceClient.OnChunkDelta
LiquidServiceClient.destroyChunkVisual = LiquidServiceClient.DestroyChunkVisual
LiquidServiceClient.onChunkUnloaded = LiquidServiceClient.OnChunkUnloaded
LiquidServiceClient.getBurnAttachment = LiquidServiceClient.GetBurnAttachment
LiquidServiceClient.setBurningVisualEnabled = LiquidServiceClient.SetBurningVisualEnabled
LiquidServiceClient.refreshWaterSplashSoundAssetIds = LiquidServiceClient.RefreshWaterSplashSoundAssetIds
LiquidServiceClient.pickWaterSplashSoundAssetId = LiquidServiceClient.PickWaterSplashSoundAssetId
LiquidServiceClient.playWaterSplashSound = LiquidServiceClient.PlayWaterSplashSound
LiquidServiceClient.emitSplash = LiquidServiceClient.EmitSplash
LiquidServiceClient.onEffectEvent = LiquidServiceClient.OnEffectEvent
LiquidServiceClient.stepSurfaceAnimation = LiquidServiceClient.StepSurfaceAnimation
LiquidServiceClient.onRenderStep = LiquidServiceClient.OnRenderStep
LiquidServiceClient.recreateRebuildQueue = LiquidServiceClient.RecreateRebuildQueue
LiquidServiceClient.applyState = LiquidServiceClient.ApplyState
LiquidServiceClient.requestSync = LiquidServiceClient.RequestSync
LiquidServiceClient.init = LiquidServiceClient.Init
LiquidServiceClient.destroy = LiquidServiceClient.Destroy

type LiquidServiceClient = typeof(LiquidServiceClient) & {
	runtimeContext: any?,
	localPlayer: Player,
	config: LiquidServiceConfig,
	state: LiquidServiceState,
	debug: DebugObject?,
	networker: Networker.Client,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	effectEvent: SignalObject,
	chunkSnapshots: { [string]: ClientChunkSnapshot },
	chunkVisuals: { [string]: ChunkVisual },
	surfaceParts: { [BasePart]: SurfaceRuntime },
	rebuildQueue: any,
	rebuildToken: CancellationToken?,
	queuedRowLookup: { [string]: boolean },
	queuedRowCountsByChunk: { [string]: number },
	queuedChunkCount: number,
	worldDependencySignatureByChunk: { [string]: string },
	waterSplashSoundAssetIds: { string },
	dependencySyncAccumulator: number,
	visualFolder: Folder,
	burnEmitter: ParticleEmitter?,
}

return LiquidServiceClient :: LiquidServiceClient

