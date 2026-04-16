--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local Promise = require("Promise")
local ParallaxBackgrounds = require(script:FindFirstAncestor("game").Shared.Modules.Items.ParallaxBackgrounds)
local ParallaxServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.ParallaxService.ParallaxServiceUtils)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationService.WorldGenerationServiceClient)

type Catalog = ParallaxServiceUtils.Catalog
type BiomeDefinition = ParallaxServiceUtils.BiomeDefinition
type BiomeVariantDefinition = ParallaxServiceUtils.BiomeVariantDefinition
type LayerDefinition = ParallaxServiceUtils.LayerDefinition
type ServiceState = ParallaxServiceUtils.ServiceState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type SegmentRuntime = {
	part: Part,
	textures: { Texture },
	lastWidth: number,
	lastHeight: number,
	assignedStripIndex: number?,
}

type LayerRuntime = {
	definition: LayerDefinition,
	folder: Folder,
	segments: { SegmentRuntime },
}

type BiomeRuntime = {
	biomeName: string,
	variantName: string,
	definition: BiomeDefinition,
	variantDefinition: BiomeVariantDefinition,
	folder: Folder,
	layers: { LayerRuntime },
	alpha: number,
	startAlpha: number,
	targetAlpha: number,
}

local WORLD_FOLDER_NAME = "WorldGeneration"
local ROOT_PARENT_FALLBACK_NAME = "ParallaxService"
local SEGMENT_TEXTURE_OFFSET_STUDS_U = 0.3
local SEGMENT_TEXTURE_OFFSET_STUDS_V = 0.3
local MIN_SEGMENT_VERTICAL_COVERAGE_BLEED_FACTOR = 0.14
local MIN_SEGMENT_VERTICAL_COVERAGE_BLEED_STUDS = 4
local ParallaxServiceClient = {}

local function promiseTry<T...>(callback: () -> T...): Promise.Promise<T...>
	return Promise.spawn(function(resolve, reject)
		local results = table.pack(pcall(callback))
		if results[1] then
			resolve(table.unpack(results, 2, results.n))
		else
			reject(table.unpack(results, 2, results.n))
		end
	end)
end

local function asFolder(instance: Instance?): Folder?
	if instance ~= nil and instance:IsA("Folder") then
		return instance
	end
	return nil
end

local function createFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return existing
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function resolveCameraPosition(): Vector3
	local camera = getCamera()
	if camera == nil then
		return Vector3.zero
	end
	return camera.CFrame.Position
end

local function computeVisibleExtentsAtDistance(camera: Camera, distance: number): (number, number)
	local viewportSize = camera.ViewportSize
	local aspectRatio = if viewportSize.Y > 0 then viewportSize.X / viewportSize.Y else 16 / 9
	local resolvedDistance = math.max(distance, 1)
	local visibleHeight = 2 * resolvedDistance * math.tan(math.rad(camera.FieldOfView) * 0.5)
	local visibleWidth = visibleHeight * aspectRatio
	return visibleWidth, visibleHeight
end

local function computeHorizontalSegmentOverlap(segmentSize: number): number
	return math.clamp(segmentSize * 0.0015, 0.08, 0.3)
end

local function computeAlignedCenterY(
	verticalAlign: ParallaxServiceUtils.VerticalAlign,
	cameraY: number,
	visibleHeight: number,
	segmentHeight: number
): number
	if verticalAlign == "Top" then
		return cameraY + visibleHeight * 0.5 - segmentHeight * 0.5
	end
	if verticalAlign == "Center" then
		return cameraY
	end
	return cameraY - visibleHeight * 0.5 + segmentHeight * 0.5
end

local function blendToLayerTransparency(baseTransparency: number, biomeAlpha: number): number
	local clampedBaseTransparency = math.clamp(baseTransparency, 0, 1)
	local clampedBiomeAlpha = math.clamp(biomeAlpha, 0, 1)
	return 1 - (1 - clampedBaseTransparency) * clampedBiomeAlpha
end

local function createTexture(part: Part, face: Enum.NormalId, definition: LayerDefinition): Texture
	local texture = Instance.new("Texture")
	texture.Name = face.Name
	texture.Face = face
	texture.Texture = definition.image
	texture.Color3 = definition.tint
	texture.Transparency = 1
	texture.OffsetStudsU = SEGMENT_TEXTURE_OFFSET_STUDS_U
	texture.OffsetStudsV = SEGMENT_TEXTURE_OFFSET_STUDS_V
	texture.Parent = part
	return texture
end

function ParallaxServiceClient._initializeCoreState(self: ParallaxServiceClient)
	if self.localPlayer == nil then
		self.localPlayer = Players.LocalPlayer
	end
	if self.catalog == nil then
		self.catalog = ParallaxServiceUtils.normalizeCatalog(ParallaxBackgrounds)
	end
	if self.state == nil then
		self.state = ParallaxServiceUtils.createDefaultState(self.catalog)
	end
	if self.activeBiomeRuntimes == nil then
		self.activeBiomeRuntimes = {} :: { [string]: BiomeRuntime }
	end
	if self.preloadedBiomes == nil then
		self.preloadedBiomes = {} :: { [string]: boolean }
	end
	if self.preloadBiomePromises == nil then
		self.preloadBiomePromises = {} :: { [string]: any }
	end
	if self.selectedBiomeVariantNames == nil then
		self.selectedBiomeVariantNames = {} :: { [string]: string }
	end
	if self.didPreloadAllAssets == nil then
		self.didPreloadAllAssets = false
	end
	if self.preloadAllAssetsPromise == nil then
		self.preloadAllAssetsPromise = nil
	end
	if self.transitionActive == nil then
		self.transitionActive = false
	end
	if self.transitionStartedAt == nil then
		self.transitionStartedAt = 0
	end
	if self.biomeSampleAccumulator == nil then
		self.biomeSampleAccumulator = self.catalog.settings.biomeSampleIntervalSeconds
	end
end

function ParallaxServiceClient._resolveWorldFolder(self: ParallaxServiceClient): Folder?
	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if worldFolder ~= nil and worldFolder:IsA("Folder") then
		return worldFolder
	end
	return nil
end

function ParallaxServiceClient._resolveRootParent(self: ParallaxServiceClient): Instance
	local worldFolder = self:_resolveWorldFolder()
	if worldFolder ~= nil then
		return worldFolder
	end
	return WorkspaceFolders.getOrCreateFolderInGame(ROOT_PARENT_FALLBACK_NAME)
end

function ParallaxServiceClient._destroyAllBiomeRuntimes(self: ParallaxServiceClient)
	local biomeNames: { string } = {}
	for biomeName in self.activeBiomeRuntimes do
		table.insert(biomeNames, biomeName)
	end
	for _, biomeName in biomeNames do
		local runtime = self.activeBiomeRuntimes[biomeName]
		if runtime ~= nil and runtime.folder.Parent ~= nil then
			runtime.folder:Destroy()
		end
		self.activeBiomeRuntimes[biomeName] = nil
	end
end

function ParallaxServiceClient._ensureRootFolder(self: ParallaxServiceClient)
	local parent = self:_resolveRootParent()
	if self.rootFolder ~= nil and self.rootFolder.Parent == parent then
		return
	end

	self:_destroyAllBiomeRuntimes()
	if self.rootFolder ~= nil and self.rootFolder.Parent ~= nil then
		self.rootFolder:Destroy()
	end
	self.rootFolder = createFolder(parent, self.catalog.settings.folderName)
end

function ParallaxServiceClient._refreshWorldAttributes(self: ParallaxServiceClient)
	local worldFolder = self:_resolveWorldFolder()
	if worldFolder == nil then
		self.worldOrigin = Vector3.zero
		self.basePlaneX = 0
		self.referenceGameplayPlaneDistanceX = nil
		return
	end

	local originX = worldFolder:GetAttribute("WorldOriginX")
	local originY = worldFolder:GetAttribute("WorldOriginY")
	local originZ = worldFolder:GetAttribute("WorldOriginZ")
	local basePlaneX = worldFolder:GetAttribute("BasePlaneX")

	local nextWorldOrigin = Vector3.new(
		if typeof(originX) == "number" then originX else 0,
		if typeof(originY) == "number" then originY else 0,
		if typeof(originZ) == "number" then originZ else 0
	)
	local nextBasePlaneX = if typeof(basePlaneX) == "number" then basePlaneX else 0

	if self.worldOrigin ~= nextWorldOrigin or self.basePlaneX ~= nextBasePlaneX then
		self.referenceGameplayPlaneDistanceX = nil
	end

	self.worldOrigin = nextWorldOrigin
	self.basePlaneX = nextBasePlaneX
end

function ParallaxServiceClient._resolveGameplayPlaneReferenceDistance(
	self: ParallaxServiceClient,
	cameraPositionX: number
): number
	local gameplayPlaneX = self.worldOrigin.X + self.basePlaneX
	local gameplayPlaneDistance = math.max(math.abs(cameraPositionX - gameplayPlaneX), 1)

	if self.referenceGameplayPlaneDistanceX == nil then
		self.referenceGameplayPlaneDistanceX = gameplayPlaneDistance
	else
		self.referenceGameplayPlaneDistanceX = math.min(self.referenceGameplayPlaneDistanceX, gameplayPlaneDistance)
	end

	return self.referenceGameplayPlaneDistanceX
end

function ParallaxServiceClient._resolveDisplayedBiomeName(self: ParallaxServiceClient): string
	local strongestBiome = self.state.targetBiome
	local strongestAlpha = -math.huge
	for biomeName, runtime in self.activeBiomeRuntimes do
		if runtime.alpha > strongestAlpha then
			strongestAlpha = runtime.alpha
			strongestBiome = biomeName
		end
	end
	return strongestBiome
end

function ParallaxServiceClient._resolveSelectedVariantName(
	self: ParallaxServiceClient,
	biomeDefinition: BiomeDefinition
): string
	local selectedVariantName = self.selectedBiomeVariantNames[biomeDefinition.name]
	if selectedVariantName ~= nil and biomeDefinition.variants[selectedVariantName] ~= nil then
		return selectedVariantName
	end

	local nextVariantName = ParallaxServiceUtils.resolveVariantName(biomeDefinition, biomeDefinition.defaultVariantName)
	self.selectedBiomeVariantNames[biomeDefinition.name] = nextVariantName
	return nextVariantName
end

function ParallaxServiceClient._publishState(self: ParallaxServiceClient)
	if self.state.targetBiome ~= "" then
		self.state.currentBiome = self:_resolveDisplayedBiomeName()
	end
end

function ParallaxServiceClient._createSegment(self: ParallaxServiceClient, layerRuntime: LayerRuntime): SegmentRuntime
	local definition = layerRuntime.definition

	local part = Instance.new("Part")
	part.Name = `{definition.id}_Segment`
	part.Anchored = true
	part.Locked = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.new(0, 0, 0)
	part.Transparency = 1
	part.Reflectance = 0
	part.Size = Vector3.new(self.catalog.settings.segmentThickness, 1, 1)
	part.Parent = layerRuntime.folder

	local textures = {
		createTexture(part, Enum.NormalId.Left, definition),
		createTexture(part, Enum.NormalId.Right, definition),
	}

	return {
		part = part,
		textures = textures,
		lastWidth = 0,
		lastHeight = 0,
		assignedStripIndex = nil,
	}
end

function ParallaxServiceClient._ensureSegmentPool(self: ParallaxServiceClient, layerRuntime: LayerRuntime, neededCount: number)
	while #layerRuntime.segments < neededCount do
		table.insert(layerRuntime.segments, self:_createSegment(layerRuntime))
	end
end

function ParallaxServiceClient._createLayerRuntime(
	self: ParallaxServiceClient,
	biomeRuntime: BiomeRuntime,
	definition: LayerDefinition
): LayerRuntime
	local folder = createFolder(biomeRuntime.folder, definition.id)
	return {
		definition = definition,
		folder = folder,
		segments = {},
	}
end

function ParallaxServiceClient._createBiomeRuntime(self: ParallaxServiceClient, biomeName: string): BiomeRuntime
	self:_ensureRootFolder()

	local definition = ParallaxServiceUtils.resolveBiomeDefinition(self.catalog, biomeName)
	local variantName = self:_resolveSelectedVariantName(definition)
	local variantDefinition = ParallaxServiceUtils.resolveVariantDefinition(self.catalog, definition.name, variantName)
	local folder = createFolder(self.rootFolder, `{definition.name}_{variantName}`)
	local runtime: BiomeRuntime = {
		biomeName = definition.name,
		variantName = variantName,
		definition = definition,
		variantDefinition = variantDefinition,
		folder = folder,
		layers = {},
		alpha = 0,
		startAlpha = 0,
		targetAlpha = 0,
	}

	for _, layerDefinition in variantDefinition.layers do
		table.insert(runtime.layers, self:_createLayerRuntime(runtime, layerDefinition))
	end

	self.activeBiomeRuntimes[definition.name] = runtime
	return runtime
end

function ParallaxServiceClient._destroyBiomeRuntime(self: ParallaxServiceClient, biomeName: string)
	local runtime = self.activeBiomeRuntimes[biomeName]
	if runtime == nil then
		return
	end
	if runtime.folder.Parent ~= nil then
		runtime.folder:Destroy()
	end
	self.activeBiomeRuntimes[biomeName] = nil
end

function ParallaxServiceClient._cleanupInactiveBiomeRuntimes(self: ParallaxServiceClient)
	local toDestroy: { string } = {}
	for biomeName, runtime in self.activeBiomeRuntimes do
		if biomeName ~= self.state.targetBiome and runtime.alpha <= 0.001 then
			table.insert(toDestroy, biomeName)
		end
	end
	for _, biomeName in toDestroy do
		self:_destroyBiomeRuntime(biomeName)
	end
end

function ParallaxServiceClient._setBiomeAlpha(self: ParallaxServiceClient, biomeRuntime: BiomeRuntime, alphaRaw: number)
	biomeRuntime.alpha = math.clamp(alphaRaw, 0, 1)
end

function ParallaxServiceClient._stepTransition(self: ParallaxServiceClient, now: number)
	if not self.transitionActive then
		return
	end

	local duration = math.max(0.001, self.catalog.settings.transitionSeconds)
	local rawProgress = math.clamp((now - self.transitionStartedAt) / duration, 0, 1)
	local easedProgress = TweenService:GetValue(rawProgress, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	for _, runtime in self.activeBiomeRuntimes do
		local nextAlpha = runtime.startAlpha + (runtime.targetAlpha - runtime.startAlpha) * easedProgress
		self:_setBiomeAlpha(runtime, nextAlpha)
	end

	if rawProgress >= 1 then
		self.transitionActive = false
		self.state.transitionState = "Idle"
		local targetRuntime = self.activeBiomeRuntimes[self.state.targetBiome]
		if targetRuntime ~= nil then
			self:_setBiomeAlpha(targetRuntime, 1)
		end
		self:_cleanupInactiveBiomeRuntimes()
	end

	self:_publishState()
end

function ParallaxServiceClient._preloadBiomeAssets(self: ParallaxServiceClient, biomeNameRaw: any)
	local biomeName = ParallaxServiceUtils.resolveBiomeName(self.catalog, biomeNameRaw)
	if self.preloadedBiomes[biomeName] then
		return self.preloadBiomePromises[biomeName]
	end
	self.preloadedBiomes[biomeName] = true

	local assetIds = ParallaxServiceUtils.collectAssetIds(self.catalog, { biomeName })
	if #assetIds <= 0 then
		local emptyPromise = Promise.resolved(true)
		self.preloadBiomePromises[biomeName] = emptyPromise
		return emptyPromise
	end

	local preloadPromise = promiseTry(function()
			ContentProvider:PreloadAsync(assetIds)
			return true
		end)
		:Catch(function(_err: any)
			return false
		end)
	self.preloadBiomePromises[biomeName] = preloadPromise
	return preloadPromise
end

function ParallaxServiceClient._preloadAllAssets(self: ParallaxServiceClient)
	if self.didPreloadAllAssets then
		return self.preloadAllAssetsPromise
	end
	self.didPreloadAllAssets = true

	local assetIds = ParallaxServiceUtils.collectAssetIds(self.catalog, nil)
	if #assetIds <= 0 then
		self.preloadAllAssetsPromise = Promise.resolved(true)
		return self.preloadAllAssetsPromise
	end

	self.preloadAllAssetsPromise = promiseTry(function()
			ContentProvider:PreloadAsync(assetIds)
			return true
		end)
		:Catch(function(_err: any)
			return false
		end)
	return self.preloadAllAssetsPromise
end

function ParallaxServiceClient._resolveCurrentWorldBiome(self: ParallaxServiceClient): string
	local rawState = (WorldGenerationServiceClient :: any).state
	if typeof(rawState) ~= "table" or (rawState :: any).ready ~= true then
		return self.catalog.settings.defaultBiome
	end

	local camera = getCamera()
	if camera == nil then
		return self.catalog.settings.defaultBiome
	end

	local worldPosition = camera.CFrame.Position
	local biomeId = WorldGenerationServiceClient:getBiomeIdAtWorldPosition(worldPosition)
	local biomeType = WorldGenerationServiceClient:getBiomeTypeAtWorldPosition(worldPosition)
	local depthLayer = WorldGenerationServiceClient:getDepthLayerAtWorldPosition(worldPosition)
	return ParallaxServiceUtils.resolveBiomeNameFromWorldSample(self.catalog, biomeId, biomeType, depthLayer)
end

function ParallaxServiceClient._syncBiomeFromWorldSampleNow(self: ParallaxServiceClient): string
	local sampledBiome = self:_resolveCurrentWorldBiome()
	self.state.currentBiome = sampledBiome
	self.state.targetBiome = sampledBiome
	return sampledBiome
end

function ParallaxServiceClient._updateLayerRuntime(
	self: ParallaxServiceClient,
	layerRuntime: LayerRuntime,
	biomeAlpha: number,
	camera: Camera,
	cameraPosition: Vector3,
	now: number
)
	local definition = layerRuntime.definition
	local tileDepth = if typeof((WorldGenerationServiceClient :: any).state) == "table"
		then ((WorldGenerationServiceClient :: any).state :: any).tileDepth or 2
		else 2

	local planeX = self.worldOrigin.X + self.basePlaneX - definition.planeDepthBlocks * tileDepth
	local gameplayReferenceDistance = self:_resolveGameplayPlaneReferenceDistance(cameraPosition.X)
	local coverageReferenceDistance = gameplayReferenceDistance + math.abs((self.worldOrigin.X + self.basePlaneX) - planeX)
	local visibleWidth, visibleHeight = computeVisibleExtentsAtDistance(camera, coverageReferenceDistance)
	local sizeReferenceWidth = select(1, computeVisibleExtentsAtDistance(camera, gameplayReferenceDistance))
	local minimumSegmentWidth = math.max(definition.textureStudsPerTileU * 0.25, 12)
	local aspectRatio = math.max(definition.imageAspectRatio, 0.05)
	local resolvedHeightScale = math.max(definition.heightScale, 0.05)
	local candidateSegmentWidth = math.max(sizeReferenceWidth * definition.segmentWidthScale, minimumSegmentWidth)
	local candidateSegmentHeight = math.max(1, (candidateSegmentWidth / aspectRatio) * resolvedHeightScale)
	local centerShift = definition.verticalOffsetStuds - (cameraPosition.Y - self.worldOrigin.Y) * definition.verticalDepth
	local candidateCenterY = computeAlignedCenterY(
		definition.verticalAlign,
		cameraPosition.Y,
		visibleHeight,
		candidateSegmentHeight
	) + centerShift
	local visibleTopY = cameraPosition.Y + visibleHeight * 0.5
	local visibleBottomY = cameraPosition.Y - visibleHeight * 0.5
	local requiredHalfHeight = math.max(candidateCenterY - visibleBottomY, visibleTopY - candidateCenterY)
		+ math.max(visibleHeight * MIN_SEGMENT_VERTICAL_COVERAGE_BLEED_FACTOR, MIN_SEGMENT_VERTICAL_COVERAGE_BLEED_STUDS)
	local requiredSegmentHeight = requiredHalfHeight * 2
	local segmentHeight = math.max(candidateSegmentHeight, requiredSegmentHeight)
	local segmentWidth = math.max(candidateSegmentWidth, (segmentHeight / resolvedHeightScale) * aspectRatio)
	local overscanSegments = math.max(definition.overscanSegments, 2)
	local horizontalOverlap = computeHorizontalSegmentOverlap(segmentWidth)
	local stripLeftEdgeZ = cameraPosition.Z * (1 - definition.depth) + now * definition.scrollSpeed
	local visibleMinZ = cameraPosition.Z - visibleWidth * 0.5 - segmentWidth * overscanSegments
	local visibleMaxZ = cameraPosition.Z + visibleWidth * 0.5 + segmentWidth * overscanSegments
	local firstVisibleStripIndex = math.floor((visibleMinZ - stripLeftEdgeZ) / segmentWidth)
	local lastVisibleStripIndex = math.ceil((visibleMaxZ - stripLeftEdgeZ) / segmentWidth) - 1
	local requiredSegmentCount = math.max(1, lastVisibleStripIndex - firstVisibleStripIndex + 1)
	local segmentCount = math.max(definition.minSegments, requiredSegmentCount)
	local firstStripIndex = firstVisibleStripIndex

	self:_ensureSegmentPool(layerRuntime, segmentCount)

	local centerY = computeAlignedCenterY(definition.verticalAlign, cameraPosition.Y, visibleHeight, segmentHeight)
	centerY += centerShift

	local targetTextureTransparency = blendToLayerTransparency(definition.transparency, biomeAlpha)
	for segmentIndex = 1, segmentCount do
		local segmentRuntime = layerRuntime.segments[segmentIndex]
		local stripIndex = firstStripIndex + (segmentIndex - 1)
		local centerZ = stripLeftEdgeZ + (stripIndex + 0.5) * segmentWidth

		segmentRuntime.part.Size =
			Vector3.new(self.catalog.settings.segmentThickness, segmentHeight, segmentWidth + horizontalOverlap)
		segmentRuntime.part.CFrame = CFrame.new(planeX, centerY, centerZ)
		for _, texture in segmentRuntime.textures do
			texture.Texture = definition.image
			texture.Color3 = definition.tint
			texture.Transparency = targetTextureTransparency
			texture.StudsPerTileU = segmentWidth
			texture.StudsPerTileV = segmentHeight
			texture.OffsetStudsU = SEGMENT_TEXTURE_OFFSET_STUDS_U
			texture.OffsetStudsV = SEGMENT_TEXTURE_OFFSET_STUDS_V
		end
		segmentRuntime.assignedStripIndex = stripIndex
		segmentRuntime.lastWidth = segmentWidth
		segmentRuntime.lastHeight = segmentHeight
	end

	for segmentIndex = segmentCount + 1, #layerRuntime.segments do
		local segmentRuntime = layerRuntime.segments[segmentIndex]
		segmentRuntime.part.CFrame = CFrame.new(planeX, -100000, 0)
		for _, texture in segmentRuntime.textures do
			texture.Transparency = 1
		end
		segmentRuntime.assignedStripIndex = nil
	end
end

function ParallaxServiceClient._updateBiomeRuntime(
	self: ParallaxServiceClient,
	biomeRuntime: BiomeRuntime,
	camera: Camera,
	cameraPosition: Vector3,
	now: number
)
	for _, layerRuntime in biomeRuntime.layers do
		self:_updateLayerRuntime(layerRuntime, biomeRuntime.alpha, camera, cameraPosition, now)
	end
end

function ParallaxServiceClient._render(self: ParallaxServiceClient, deltaTime: number)
	if not self.initialized then
		return
	end

	self:_ensureRootFolder()
	self:_refreshWorldAttributes()

	local now = os.clock()
	self:_stepTransition(now)

	self.biomeSampleAccumulator += deltaTime
	if self.biomeSampleAccumulator >= self.catalog.settings.biomeSampleIntervalSeconds then
		self.biomeSampleAccumulator = 0
		local sampledBiome = self:_resolveCurrentWorldBiome()
		if sampledBiome ~= self.state.targetBiome then
			self:SetBiome(sampledBiome)
		end
	end

	local camera = getCamera()
	if camera == nil then
		return
	end

	local cameraPosition = resolveCameraPosition()
	for _, biomeRuntime in self.activeBiomeRuntimes do
		self:_updateBiomeRuntime(biomeRuntime, camera, cameraPosition, now)
	end
end

function ParallaxServiceClient.Init(self: ParallaxServiceClient, _container: Instance?)
	self:_initializeCoreState()

	if self.janitor == nil then
		self.janitor = Janitor.new()
		self.janitor:GiveChore(function()
			if self.renderStepName ~= nil then
				RunService:UnbindFromRenderStep(self.renderStepName)
				self.renderStepName = nil
			end
			self:_destroyAllBiomeRuntimes()
			if self.rootFolder ~= nil and self.rootFolder.Parent ~= nil then
				self.rootFolder:Destroy()
			end
			self.rootFolder = nil
		end)
	end

	if self.initialized then
		return
	end

	self:_ensureRootFolder()
	self:_refreshWorldAttributes()
	self.initialized = true
	self.state.initialized = true
	local activeBiomeName = self:_syncBiomeFromWorldSampleNow()

	self:_preloadAllAssets()
	self:_preloadBiomeAssets(activeBiomeName)
	local runtime = self:_createBiomeRuntime(activeBiomeName)
	runtime.startAlpha = 1
	runtime.targetAlpha = 1
	self:_setBiomeAlpha(runtime, 1)
	self:_publishState()

	self.renderStepName = ("ParallaxServiceRender_%d"):format(math.floor(os.clock() * 1000))
	RunService:BindToRenderStep(self.renderStepName, Enum.RenderPriority.Camera.Value + 5, function(deltaTime: number)
		self:_render(deltaTime)
	end)
end

function ParallaxServiceClient.SetBiome(self: ParallaxServiceClient, biomeNameRaw: any)
	if not self.initialized then
		self:Init(nil)
	end

	local biomeName = ParallaxServiceUtils.resolveBiomeName(self.catalog, biomeNameRaw)
	self:_preloadBiomeAssets(biomeName)

	local now = os.clock()
	self:_stepTransition(now)

	local targetRuntime = self.activeBiomeRuntimes[biomeName]
	if targetRuntime == nil then
		targetRuntime = self:_createBiomeRuntime(biomeName)
		self:_setBiomeAlpha(targetRuntime, 0)
	end

	local hasOtherVisibleBiome = false
	for activeBiomeName, runtime in self.activeBiomeRuntimes do
		runtime.startAlpha = runtime.alpha
		if activeBiomeName == biomeName then
			runtime.targetAlpha = 1
		else
			runtime.targetAlpha = 0
			if runtime.alpha > 0.001 then
				hasOtherVisibleBiome = true
			end
		end
	end

	self.state.targetBiome = biomeName
	if targetRuntime.alpha >= 0.999 and not hasOtherVisibleBiome then
		self.transitionActive = false
		self.state.transitionState = "Idle"
		self:_setBiomeAlpha(targetRuntime, 1)
		self:_cleanupInactiveBiomeRuntimes()
		self:_publishState()
		return
	end

	self.transitionStartedAt = now
	self.transitionActive = true
	self.state.transitionState = if hasOtherVisibleBiome then "Interrupting" else "Blending"
	self:_publishState()
end

function ParallaxServiceClient.ForceRefresh(self: ParallaxServiceClient)
	self.catalog = ParallaxServiceUtils.normalizeCatalog(ParallaxBackgrounds)
	self.preloadedBiomes = {}
	self.preloadBiomePromises = {}
	self.selectedBiomeVariantNames = {}
	self.didPreloadAllAssets = false
	self.preloadAllAssetsPromise = nil
	self.referenceGameplayPlaneDistanceX = nil
	self:_destroyAllBiomeRuntimes()
	self:_ensureRootFolder()
	self:_refreshWorldAttributes()
	local activeBiomeName = self:_syncBiomeFromWorldSampleNow()
	self:_preloadAllAssets()
	self:_preloadBiomeAssets(activeBiomeName)

	local runtime = self:_createBiomeRuntime(activeBiomeName)
	runtime.startAlpha = 1
	runtime.targetAlpha = 1
	self:_setBiomeAlpha(runtime, 1)
	self.transitionActive = false
	self.state.transitionState = "Idle"
	self:_publishState()
end

function ParallaxServiceClient.GetCurrentBiome(self: ParallaxServiceClient): string
	return self.state.currentBiome
end

function ParallaxServiceClient.Destroy(self: ParallaxServiceClient)
	if self.preloadBiomePromises ~= nil then
		for biomeName, preloadPromise in self.preloadBiomePromises do
			if preloadPromise ~= nil then
				preloadPromise:Destroy()
			end
			self.preloadBiomePromises[biomeName] = nil
		end
	end
	if self.preloadAllAssetsPromise ~= nil then
		self.preloadAllAssetsPromise:Destroy()
		self.preloadAllAssetsPromise = nil
	end
	if self.janitor ~= nil then
		self.janitor:Destroy()
		self.janitor = nil
	end
end

ParallaxServiceClient.init = ParallaxServiceClient.Init
ParallaxServiceClient.getCurrentBiome = ParallaxServiceClient.GetCurrentBiome
ParallaxServiceClient.destroy = ParallaxServiceClient.Destroy

type ParallaxServiceClient = typeof(ParallaxServiceClient) & {
	localPlayer: Player,
	janitor: JanitorClass?,
	catalog: Catalog,
	state: ServiceState,
	activeBiomeRuntimes: { [string]: BiomeRuntime },
	preloadedBiomes: { [string]: boolean },
	preloadBiomePromises: { [string]: any },
	selectedBiomeVariantNames: { [string]: string },
	didPreloadAllAssets: boolean,
	preloadAllAssetsPromise: any?,
	referenceGameplayPlaneDistanceX: number?,
	transitionActive: boolean,
	transitionStartedAt: number,
	biomeSampleAccumulator: number,
	rootFolder: Folder?,
	worldOrigin: Vector3,
	basePlaneX: number,
	renderStepName: string?,
	initialized: boolean,
}

return ParallaxServiceClient :: ParallaxServiceClient
