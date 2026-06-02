--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local HttpService = game:GetService("HttpService")

local Cache = require(gameRoot.Shared.Features.worldGeneration.simulation.SimulationCache)
local Shared = require(gameRoot.Shared.Features.worldGeneration.simulation.Shared)
local TileComponent = require(gameRoot.Shared.Features.worldGeneration.components.Tile)
local WorkspaceFolders = require(gameRoot.Shared.Core.WorkspaceFolders)

local Render = {}
Render.__index = Render

export type Render = typeof(setmetatable({} :: any, Render))

type ObjectPool<T> = Cache.ObjectPool<T>

type ChunkVisual = {
	model: Model,
	parts: { BasePart },
	revision: number,
}

local WORLD_FOLDER_NAME = "WorldSimulation"
local CHUNKS_FOLDER_NAME = "Chunks"
local MODEL_OWNER_ATTRIBUTE = "WorldSimulationRenderOwned"

local BIOME_COLORS = {
	[Shared.BIOME_ID.FOREST] = Color3.fromRGB(95, 159, 53),
	[Shared.BIOME_ID.DESERT] = Color3.fromRGB(225, 206, 136),
	[Shared.BIOME_ID.SNOW] = Color3.fromRGB(232, 240, 255),
	[Shared.BIOME_ID.JUNGLE] = Color3.fromRGB(78, 177, 95),
	[Shared.BIOME_ID.CORRUPTION] = Color3.fromRGB(128, 92, 188),
}

local function applyTileStudSurfaces(part: BasePart)
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
end

local function decodeClusterIndex(index: number, countX: number, countY: number): (number, number, number)
	local linear = index - 1
	local localX = linear % countX
	local layer = math.floor(linear / countX)
	local localY = layer % countY
	local localZ = math.floor(layer / countY)
	return localX, localY, localZ
end

function Render.New(configRaw: any, cacheRaw: any, debugRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {} :: any
	local cache = if cacheRaw ~= nil then cacheRaw else Cache.new(nil)
	local self = setmetatable({
		config = config,
		cache = cache,
		debug = debugRaw,
		worldFolder = nil :: Folder?,
		chunksFolder = nil :: Folder?,
		chunkVisuals = {} :: { [string]: ChunkVisual },
		partPool = nil :: ObjectPool<BasePart>?,
		streamingTickActive = false,
		chunkFolderGuardConnection = nil :: RBXScriptConnection?,
	}, Render)

	self.partPool = cache:createObjectPool(function()
		local part = TileComponent.CreatePart({
			name = HttpService:GenerateGUID(false),
			anchored = true,
			locked = true,
			canCollide = false,
			canQuery = false,
			canTouch = false,
		})
		applyTileStudSurfaces(part)
		return part
	end, function(part: BasePart)
		part.Parent = nil
		part.Transparency = 0
	end, (config.maxPartPoolSize or 8000))

	return self
end

function Render.BindChunkFolderGuard(self: Render, chunksFolder: Folder)
	if self.chunkFolderGuardConnection ~= nil then
		return
	end

	self.chunkFolderGuardConnection = chunksFolder.ChildAdded:Connect(function(child: Instance)
		if not child:IsA("Model") then
			return
		end
		local ownedByRender = child:GetAttribute(MODEL_OWNER_ATTRIBUTE) == true
		if ownedByRender then
			return
		end
		error(`[WorldSimulationService] Chunk Model created outside Render:SpawnChunkModel ({child:GetFullName()})`)
	end)
end

function Render.GetExistingChunksFolder(self: Render): Folder?
	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if worldFolder == nil or not worldFolder:IsA("Folder") then
		return nil
	end
	local chunksFolder = worldFolder:FindFirstChild(CHUNKS_FOLDER_NAME)
	if chunksFolder == nil or not chunksFolder:IsA("Folder") then
		return nil
	end
	return chunksFolder
end

function Render.BindExistingChunkFolderGuard(self: Render)
	local chunksFolder = self:getExistingChunksFolder()
	if chunksFolder == nil then
		return
	end
	self.worldFolder = chunksFolder.Parent :: Folder
	self.chunksFolder = chunksFolder
	self:bindChunkFolderGuard(chunksFolder)
end

function Render.EnsureFolders(self: Render, parentRaw: any): Folder?
	local parent = if typeof(parentRaw) == "Instance" then parentRaw else WorkspaceFolders.getOrCreateGameFolder()
	if self.worldFolder ~= nil and self.worldFolder.Parent ~= nil then
		if self.chunksFolder ~= nil and self.chunksFolder.Parent ~= nil then
			return self.chunksFolder
		end
	end

	local worldFolder = parent:FindFirstChild(WORLD_FOLDER_NAME)
	if worldFolder == nil or not worldFolder:IsA("Folder") then
		worldFolder = TileComponent.CreateFolder({
			name = WORLD_FOLDER_NAME,
			parent = parent,
		} :: any) :: any
	end
	local resolvedWorldFolder = worldFolder :: Folder

	local chunksFolder = resolvedWorldFolder:FindFirstChild(CHUNKS_FOLDER_NAME)
	if chunksFolder == nil or not chunksFolder:IsA("Folder") then
		chunksFolder = TileComponent.CreateFolder({
			name = CHUNKS_FOLDER_NAME,
			parent = resolvedWorldFolder,
		} :: any) :: any
	end
	local resolvedChunksFolder = chunksFolder :: Folder

	self.worldFolder = resolvedWorldFolder
	self.chunksFolder = resolvedChunksFolder
	self:bindChunkFolderGuard(resolvedChunksFolder)
	return resolvedChunksFolder
end

function Render.ReleaseChunkVisual(self: Render, chunkKey: string)
	local visual = self.chunkVisuals[chunkKey]
	if visual == nil then
		return
	end
	self.chunkVisuals[chunkKey] = nil

	if self.partPool ~= nil then
		for _, part in visual.parts do
			self.partPool:release(part)
		end
	end
	visual.model:Destroy()
end

function Render.SpawnChunkModel(self: Render, coordRaw: any, chunkDataRaw: any): ChunkVisual?
	if typeof(coordRaw) ~= "table" or typeof(chunkDataRaw) ~= "table" then
		return nil
	end
	if not self.streamingTickActive then
		error("[WorldSimulationService] Render:SpawnChunkModel called outside streaming tick")
	end
	local coord = coordRaw :: { [string]: any }
	local snapshot = chunkDataRaw :: { [string]: any }
	local key = snapshot.key
	if typeof(key) ~= "string" or key == "" then
		return nil
	end

	local chunksFolder = self:ensureFolders(nil)
	if chunksFolder == nil then
		return nil
	end

	local clusterCountX = math.max(1, math.floor(snapshot.clusterCountX or 1))
	local clusterCountY = math.max(1, math.floor(snapshot.clusterCountY or 1))
	local clusterCountZ = math.max(1, math.floor(snapshot.clusterCountZ or 1))
	local expectedCount = clusterCountX * clusterCountY * clusterCountZ
	if #snapshot.clusterSolidMask < expectedCount or #snapshot.clusterChosenBiomeIds < expectedCount then
		return nil
	end

	local model = TileComponent.CreateModel({
		name = HttpService:GenerateGUID(false),
		parent = chunksFolder,
		attributes = {
			ChunkKey = key,
			Revision = snapshot.revision,
			[MODEL_OWNER_ATTRIBUTE] = true,
		},
	})

	local parts = {}
	local clusterSize = math.max(1, self.config.clusterSize or Shared.CLUSTER_SIZE)
	local tileSize = math.max(0.001, self.config.tileSize or 4)
	local clusterWorldSize = clusterSize * tileSize
	local baseTileX = coord.chunkX * (self.config.chunkSize or 32)
	local baseTileY = coord.chunkY * (self.config.chunkHeight or 32)
	local baseTileZ = coord.chunkZ * (self.config.chunkDepth or 32)

	for clusterIndex = 1, expectedCount do
		if snapshot.clusterSolidMask[clusterIndex] == 0 then
			continue
		end
		local part = if self.partPool ~= nil then self.partPool:acquire() else TileComponent.CreatePart()
		local biomeId = snapshot.clusterChosenBiomeIds[clusterIndex]
		local color = BIOME_COLORS[biomeId] or BIOME_COLORS[Shared.BIOME_ID.FOREST]

		local localClusterX, localClusterY, localClusterZ =
			decodeClusterIndex(clusterIndex, clusterCountX, clusterCountY)
		local worldTileX = baseTileX + localClusterX * clusterSize + clusterSize * 0.5
		local worldTileY = baseTileY + localClusterY * clusterSize + clusterSize * 0.5
		local worldTileZ = baseTileZ + localClusterZ * clusterSize + clusterSize * 0.5

		part.Size = Vector3.new(clusterWorldSize, clusterWorldSize, clusterWorldSize)
		part.CFrame = CFrame.new(worldTileX * tileSize, worldTileY * tileSize, worldTileZ * tileSize)
		part.Color = color
		part.Material = Enum.Material.Plastic
		part.Transparency = 0
		part.Parent = model
		parts[#parts + 1] = part
	end

	local visual: ChunkVisual = {
		model = model,
		parts = parts,
		revision = snapshot.revision,
	}

	if self.debug ~= nil and self.debug.drawChunkBox then
		local chunkSizeX = (self.config.chunkSize or 32) * tileSize
		local chunkSizeY = (self.config.chunkHeight or 32) * tileSize
		local chunkSizeZ = (self.config.chunkDepth or 32) * tileSize
		self.debug:drawChunkBox(
			key,
			Vector3.new(
				(baseTileX + (self.config.chunkSize or 32) * 0.5) * tileSize,
				(baseTileY + (self.config.chunkHeight or 32) * 0.5) * tileSize,
				(baseTileZ + (self.config.chunkDepth or 32) * 0.5) * tileSize
			),
			Vector3.new(chunkSizeX, chunkSizeY, chunkSizeZ),
			nil
		)
	end

	return visual
end

function Render.ApplyChunkSnapshot(self: Render, snapshotRaw: any): boolean
	if typeof(snapshotRaw) ~= "table" then
		return false
	end
	local snapshot = snapshotRaw :: { [string]: any }
	if typeof(snapshot.key) ~= "string" or snapshot.key == "" then
		return false
	end
	if typeof(snapshot.clusterSolidMask) ~= "table" or typeof(snapshot.clusterChosenBiomeIds) ~= "table" then
		return false
	end

	local existing = self.chunkVisuals[snapshot.key]
	if existing ~= nil and existing.revision == snapshot.revision then
		return true
	end
	if existing ~= nil then
		self:releaseChunkVisual(snapshot.key)
	end

	local visual = self:SpawnChunkModel({
		chunkX = snapshot.chunkX,
		chunkY = snapshot.chunkY,
		chunkZ = snapshot.chunkZ,
	}, snapshot)
	if visual == nil then
		return false
	end
	self.chunkVisuals[snapshot.key] = visual

	return true
end

function Render.UnloadChunk(self: Render, chunkKeyRaw: any)
	if typeof(chunkKeyRaw) ~= "string" or chunkKeyRaw == "" then
		return
	end
	self:releaseChunkVisual(chunkKeyRaw)
	if self.debug ~= nil and self.debug.clearChunkBox then
		self.debug:clearChunkBox(chunkKeyRaw)
	end
end

function Render.Destroy(self: Render)
	for chunkKey in self.chunkVisuals do
		self:releaseChunkVisual(chunkKey)
	end
	if self.chunkFolderGuardConnection ~= nil then
		self.chunkFolderGuardConnection:Disconnect()
		self.chunkFolderGuardConnection = nil
	end
	if self.partPool ~= nil then
		self.partPool:destroy()
		self.partPool = nil
	end
	if self.worldFolder ~= nil then
		self.worldFolder:Destroy()
		self.worldFolder = nil
		self.chunksFolder = nil
	end
end

function Render.GetActiveChunkCount(self: Render): number
	local count = 0
	for _ in self.chunkVisuals do
		count += 1
	end
	return count
end

function Render.GetChunkFolderModelCount(self: Render): number
	local chunksFolder = self:getExistingChunksFolder()
	if chunksFolder == nil then
		return 0
	end
	local count = 0
	for _, child in chunksFolder:GetChildren() do
		if child:IsA("Model") then
			count += 1
		end
	end
	return count
end

function Render.BeginStreamingTick(self: Render)
	self.streamingTickActive = true
end

function Render.EndStreamingTick(self: Render)
	self.streamingTickActive = false
end

Render.new = Render.New
Render.bindChunkFolderGuard = Render.BindChunkFolderGuard
Render.getExistingChunksFolder = Render.GetExistingChunksFolder
Render.bindExistingChunkFolderGuard = Render.BindExistingChunkFolderGuard
Render.ensureFolders = Render.EnsureFolders
Render.releaseChunkVisual = Render.ReleaseChunkVisual
Render.applyChunkSnapshot = Render.ApplyChunkSnapshot
Render.unloadChunk = Render.UnloadChunk
Render.destroy = Render.Destroy
Render.getActiveChunkCount = Render.GetActiveChunkCount
Render.getChunkFolderModelCount = Render.GetChunkFolderModelCount
Render.beginStreamingTick = Render.BeginStreamingTick
Render.endStreamingTick = Render.EndStreamingTick

return Render
