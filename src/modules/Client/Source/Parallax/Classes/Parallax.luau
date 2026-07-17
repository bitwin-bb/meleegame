local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CharacterUtils = require("CharacterUtils")
local ContentProviderUtils = require("ContentProviderUtils")
local FieldOfViewUtils = require("FieldOfViewUtils")
local Maid = require("Maid")
local Rx: any = require("Rx")
local RxSignal: any = require("RxSignal")
local ValueObject: any = require("ValueObject")

local React: any = require(ReplicatedStorage.Packages.React)
local ReactRoblox: any = require(ReplicatedStorage.Packages.ReactRoblox)

local Biome = require("ParallaxBiomeGetter")
local Horizon = require("ParallaxHorizonGetter")
local Math = require("ParallaxMath")
local ParallaxBackgrounds = require("ParallaxBackgrounds")
local ParallaxConstants = require("ParallaxConstants")
local ParallaxRoot = require("ParallaxRoot")
local ParallaxRuntimeConstants = require("ParallaxRuntimeConstants")
local ParallaxServiceUtils = require("ParallaxServiceUtils")
local ParallaxSlice = require("ParallaxSlice")
local ParallaxThunks = require("ParallaxThunks")
local Profile = require("ParallaxProfiles")
local Scrolling = require("Scrolling")
local State = require("ParallaxState")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationConstants = require("WorldGenerationConstants")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

type Catalog = ParallaxServiceUtils.Catalog
type BiomeDefinition = ParallaxServiceUtils.BiomeDefinition
type BiomeVariantDefinition = ParallaxServiceUtils.BiomeVariantDefinition
type LayerDefinition = ParallaxServiceUtils.LayerDefinition
type PlaneSizing = ParallaxServiceUtils.PlaneSizing
type ServiceState = ParallaxServiceUtils.ServiceState
type ParallaxSurfaceState = ParallaxSlice.ParallaxSurfaceState
type HorizonSample = Horizon.HorizonSample
type LayerProfile = Profile.LayerProfile

type MaidClass = any

type ObservableObject = any

type RxSignalObject = any

type ValueObjectClass<T> = any

type CameraSnapshot = {
	fieldOfView: number,
	viewportSize: Vector2,
}

type WorldLayoutSnapshot = {
	tileDepth: number,
	chunkSize: number,
	tileSize: number,
	renderDistanceChunks: number,
	horizontalVisionStuds: number,
}

type LayoutSnapshot = CameraSnapshot & WorldLayoutSnapshot

type LayerRuntime = {
	definition: LayerDefinition,
	layerIndex: number,
}

type BiomeRuntime = {
	biomeName: string,
	variantName: string,
	definition: BiomeDefinition,
	variantDefinition: BiomeVariantDefinition,
	layers: { LayerRuntime },
	alpha: number,
	startAlpha: number,
	targetAlpha: number,
}

type SurfaceRuntime = {
	anchorPart: Part,
	reactRoot: any,
}

type LayerMetric = {
	id: string,
	image: string,
	tint: Color3,
	transparency: number,
	centerY: number,
	maximumCenterY: number,
	centerZ: number,
	width: number,
	height: number,
	textureRepeatWidth: number,
	textureRepeatHeight: number,
	textureOffsetU: number,
	textureOffsetV: number,
	planeDepthBlocks: number,
	zIndex: number,
}

type ParallaxWorldSample = {
	worldPosition: Vector3,
	biomeId: any?,
	biomeType: any?,
	biomeName: string?,
	depthLayer: any?,
	isNearWorldEdge: boolean?,
	sandTileCount: number?,
	shroomTileCount: number?,
	[string]: any,
}

local Parallax = {}
Parallax.__index = Parallax

local WORLD_FOLDER_NAME = "WorldGeneration"
local ROOT_PARENT_FALLBACK_NAME = "ParallaxService"
local ROOT_FOLDER_NAME = "ParallaxDepth"
local ANCHOR_PART_NAME = "ParallaxAnchor"

local e: typeof(React.createElement) = React.createElement

local function callWorldGenerationMethod(methodName: string, ...: any): any?
	local method = (WorldGenerationServiceClient :: any)[methodName]
	if typeof(method) ~= "function" then
		return nil
	end

	local ok, result = pcall(method, WorldGenerationServiceClient, ...)
	if not ok then
		return nil
	end
	return result
end

local function createFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return WorkspaceFolders.ManageFolder(existing, parent) or existing
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return WorkspaceFolders.ManageFolder(folder, parent) or folder
end

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function getCharacterRootPosition(player: Player?): Vector3?
	if player == nil then
		return nil
	end

	local rootPart = CharacterUtils.getPlayerRootPart(player)
	if rootPart ~= nil then
		return rootPart.Position
	end

	return nil
end

local function getCameraSnapshot(camera: Camera?): CameraSnapshot
	if camera == nil then
		return {
			fieldOfView = ParallaxRuntimeConstants.DEFAULT_CAMERA_FIELD_OF_VIEW,
			viewportSize = ParallaxRuntimeConstants.DEFAULT_CAMERA_VIEWPORT,
		}
	end

	local viewportSize = camera.ViewportSize
	return {
		fieldOfView = math.clamp(camera.FieldOfView, 1, 120),
		viewportSize = Vector2.new(math.max(1, viewportSize.X), math.max(1, viewportSize.Y)),
	}
end

local function computeVisibleExtentsAtDistance(
	fieldOfViewDegrees: number,
	viewportSize: Vector2,
	distance: number
): (number, number)
	local aspectRatio = if viewportSize.Y > 0 then viewportSize.X / viewportSize.Y else 16 / 9
	local distanceValue = math.max(distance, 1)
	local visibleHeight = distanceValue * FieldOfViewUtils.fovToHeight(fieldOfViewDegrees)
	local visibleWidth = visibleHeight * aspectRatio
	return visibleWidth, visibleHeight
end

local function computeTextureRepeatWidthFromHeight(definition: LayerDefinition, textureRepeatHeight: number): number
	return math.max(1, (textureRepeatHeight / math.max(definition.heightScale, 0.05)) * definition.imageAspectRatio)
end

local function blendToLayerTransparency(baseTransparency: number, biomeAlpha: number): number
	local clampedBaseTransparency = math.clamp(baseTransparency, 0, 1)
	local clampedBiomeAlpha = math.clamp(biomeAlpha, 0, 1)
	return 1 - (1 - clampedBaseTransparency) * clampedBiomeAlpha
end

local function blendToParallaxLayerTransparency(
	baseTransparency: number,
	styleAlpha: number,
	surfaceAlpha: number
): number
	local clampedBaseTransparency = math.clamp(baseTransparency, 0, 1)
	local clampedStyleAlpha = math.clamp(styleAlpha, 0, 1)
	local clampedSurfaceAlpha = math.clamp(surfaceAlpha, 0, 1)
	return 1 - ((1 - clampedBaseTransparency) * clampedStyleAlpha * clampedSurfaceAlpha)
end

local function formatAlphaValues(values: { [number]: number }): string
	local parts: { string } = {}
	for index, value in values do
		table.insert(parts, `{index}:{string.format("%.2f", value)}`)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function cloneState(state: ServiceState): ServiceState
	return ParallaxServiceUtils.CloneState(state)
end

local function getSurfacePixelsPerStud(widthStuds: number, heightStuds: number): number
	local largestAxis = math.max(widthStuds, heightStuds, 1)
	return math.max(
		1,
		math.min(
			ParallaxRuntimeConstants.SURFACE_PIXELS_PER_STUD,
			ParallaxRuntimeConstants.MAX_SURFACE_CANVAS_PIXELS / largestAxis
		)
	)
end

local function toCanvasPixels(studs: number, pixelsPerStud: number): number
	return math.clamp(
		math.ceil(math.max(studs, 0) * pixelsPerStud),
		ParallaxRuntimeConstants.MIN_SURFACE_CANVAS_PIXELS,
		ParallaxRuntimeConstants.MAX_SURFACE_CANVAS_PIXELS
	)
end

local function getLayerRenderId(biomeRuntime: BiomeRuntime, layerRuntime: LayerRuntime): string
	local layerId = layerRuntime.definition.id
	if layerId == "" then
		layerId = `Layer{layerRuntime.layerIndex}`
	end
	return `{biomeRuntime.biomeName}_{biomeRuntime.variantName}_{layerId}`
end

function Parallax.new(): Parallax
	local self = setmetatable({}, Parallax)
	self.localPlayer = Players.LocalPlayer
	self.catalog = ParallaxServiceUtils.NormalizeCatalog(ParallaxBackgrounds)
	self.state = ParallaxServiceUtils.CreateDefaultState(self.catalog)
	self.activeBiomeRuntimes = {}
	self.preloadedBiomes = {}
	self.preloadBiomePromises = {}
	self.selectedBiomeVariantNames = {}
	self.didPreloadAllAssets = false
	self.preloadAllAssetsPromise = nil
	self.referenceGameplayPlaneDistanceX = nil
	self.referenceFieldOfView = nil
	self.scrollAnchorZ = nil
	self.scrollTravelZ = 0
	self.transitionActive = false
	self.transitionStartedAt = 0
	self.rootFolder = nil
	self.surfaceRuntime = nil
	self.worldOrigin = Vector3.zero
	self.worldTopY = 0
	self.worldBottomY = 0
	self.worldSurfaceY = 0
	self.seaLevelY = 0
	self.maxTilesY = ParallaxRuntimeConstants.DEFAULT_MAX_TILES_Y
	self.basePlaneX = 0
	self.smoothedParallaxHorizonY = nil
	self.parallaxState = State.new()
	self.parallaxEnabled = true
	self.enableParallaxBottomGuard = false
	self.debugParallax = false
	self.surfaceBackgroundFadeDistance = ParallaxRuntimeConstants.DEFAULT_SURFACE_BACKGROUND_FADE_DISTANCE
	self.currentParallaxSample = nil
	self.manualBgStyle = nil
	self.lastParallaxHorizon = nil
	self.lastParallaxDebugPrintAt = 0
	self.lastParallaxUpdateAt = nil
	self.renderStepName = nil
	self.initialized = false
	return (self :: any) :: Parallax
end

function Parallax._initializeCoreState(self: Parallax)
	if self.stateValue == nil then
		self.stateValue = ValueObject.new(cloneState(self.state), "table") :: any
	end
	if self.stateChangedSignal == nil then
		self.stateChangedSignal = RxSignal.new(function(): ObservableObject
			return self:ObserveState()
		end) :: RxSignalObject
	end
	if self.layoutStateValue == nil then
		self.layoutStateValue = ValueObject.new(self:_GetCurrentLayoutSnapshot(), "table") :: any
	end
end

function Parallax._GetWorldLayoutSnapshot(_self: Parallax, stateRaw: any?): WorldLayoutSnapshot
	local fallbackState = ((WorldGenerationServiceClient :: any).state :: { [string]: any }?) or ({} :: any)
	local state = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else fallbackState
	local tileDepth = if typeof(state.tileDepth) == "number"
		then math.max(state.tileDepth, 0.5)
		else WorldGenerationConstants.DEFAULT_TILE_DEPTH
	local chunkSize = if typeof(state.chunkSize) == "number" then math.max(1, math.floor(state.chunkSize)) else 32
	local tileSize = if typeof(state.tileSize) == "number" then math.max(state.tileSize, 0.25) else 4
	local renderDistanceChunks = if typeof(state.renderDistanceChunks) == "number"
		then math.max(1, math.floor(state.renderDistanceChunks))
		else 4

	return {
		tileDepth = tileDepth,
		chunkSize = chunkSize,
		tileSize = tileSize,
		renderDistanceChunks = renderDistanceChunks,
		horizontalVisionStuds = ParallaxServiceUtils.ComputeHorizontalVisionStuds(
			chunkSize,
			tileSize,
			renderDistanceChunks
		),
	}
end

function Parallax._GetCurrentLayoutSnapshot(self: Parallax): LayoutSnapshot
	local cameraSnapshot = getCameraSnapshot(getCamera())
	local worldSnapshot = self:_GetWorldLayoutSnapshot()
	return {
		fieldOfView = cameraSnapshot.fieldOfView,
		viewportSize = cameraSnapshot.viewportSize,
		tileDepth = worldSnapshot.tileDepth,
		chunkSize = worldSnapshot.chunkSize,
		tileSize = worldSnapshot.tileSize,
		renderDistanceChunks = worldSnapshot.renderDistanceChunks,
		horizontalVisionStuds = worldSnapshot.horizontalVisionStuds,
	}
end

function Parallax._observeCameraSnapshot(_self: Parallax): ObservableObject
	return Rx.fromSignal(Workspace:GetPropertyChangedSignal("CurrentCamera")):Pipe({
		Rx.start(function()
			return getCamera()
		end),
		Rx.map(function()
			return getCamera()
		end),
		Rx.switchMap(function(camera: Camera?): ObservableObject
			if camera == nil then
				return Rx.of(getCameraSnapshot(nil)) :: any
			end

			return Rx.merge({
				Rx.of(true),
				Rx.fromSignal(camera:GetPropertyChangedSignal("FieldOfView")),
				Rx.fromSignal(camera:GetPropertyChangedSignal("ViewportSize")),
			}):Pipe({
				Rx.map(function()
					return getCameraSnapshot(camera)
				end),
			}) :: any
		end),
		Rx.throttleDefer(),
	}) :: ObservableObject
end

function Parallax._observeWorldLayoutSnapshot(self: Parallax): ObservableObject
	local worldStateSignal = (WorldGenerationServiceClient :: any).stateChanged
	if worldStateSignal == nil then
		return Rx.of(self:_GetWorldLayoutSnapshot()) :: any
	end

	return Rx.fromSignal(worldStateSignal):Pipe({
		Rx.start(function()
			return WorldGenerationServiceClient:GetState()
		end),
		Rx.map(function(worldState: any)
			return self:_GetWorldLayoutSnapshot(worldState)
		end),
		Rx.throttleDefer(),
	}) :: ObservableObject
end

function Parallax._bindReactiveStreams(self: Parallax)
	if self.reactiveStreamsMaid == nil then
		return
	end

	self.reactiveStreamsMaid:DoCleaning()
	self.reactiveStreamsMaid:GiveTask(Rx.combineLatest({
		camera = self:_observeCameraSnapshot(),
		world = self:_observeWorldLayoutSnapshot(),
	})
		:Pipe({
			Rx.throttleDefer(),
		})
		:Subscribe(function(snapshot: { camera: CameraSnapshot, world: WorldLayoutSnapshot })
			self.layoutStateValue.Value = {
				fieldOfView = snapshot.camera.fieldOfView,
				viewportSize = snapshot.camera.viewportSize,
				tileDepth = snapshot.world.tileDepth,
				chunkSize = snapshot.world.chunkSize,
				tileSize = snapshot.world.tileSize,
				renderDistanceChunks = snapshot.world.renderDistanceChunks,
				horizontalVisionStuds = snapshot.world.horizontalVisionStuds,
			}
			if self.initialized then
				if self.parallaxEnabled then
					local sample = self:_GetCurrentParallaxSample()
					local sampledStyle = Biome.GetBgStyle(sample, self.catalog)
					self.state.targetBiome = Profile.GetStyleName(sampledStyle)
					self:_publishState()
				else
					local sampledBiome = self:_GetCurrentWorldBiome()
					if sampledBiome ~= self.state.targetBiome then
						self:SetBiome(sampledBiome)
					end
				end
			end
		end))

	self.reactiveStreamsMaid:GiveTask(
		Rx.timer(self.catalog.settings.biomeSampleIntervalSeconds, self.catalog.settings.biomeSampleIntervalSeconds)
			:Subscribe(function()
				if not self.initialized then
					return
				end

				if self.parallaxEnabled then
					local sample = self:_GetCurrentParallaxSample()
					local sampledStyle = Biome.GetBgStyle(sample, self.catalog)
					self.state.targetBiome = Profile.GetStyleName(sampledStyle)
					self:_publishState()
				else
					local sampledBiome = self:_GetCurrentWorldBiome()
					if sampledBiome ~= self.state.targetBiome then
						self:SetBiome(sampledBiome)
					end
				end
			end)
	)

	local chunkSnapshotsChanged = (WorldGenerationServiceClient :: any).chunkSnapshotsChanged
	if chunkSnapshotsChanged ~= nil then
		self.reactiveStreamsMaid:GiveTask(chunkSnapshotsChanged:Connect(function()
			if not self.initialized then
				return
			end

			if self.parallaxEnabled then
				local sample = self:_GetCurrentParallaxSample()
				local sampledStyle = Biome.GetBgStyle(sample, self.catalog)
				self.state.targetBiome = Profile.GetStyleName(sampledStyle)
				self:_publishState()
			else
				local sampledBiome = self:_GetCurrentWorldBiome()
				if sampledBiome ~= self.state.targetBiome then
					self:SetBiome(sampledBiome)
				end
			end
		end))
	end
end

function Parallax._GetWorldFolder(_self: Parallax): Folder?
	local worldFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if worldFolder ~= nil and worldFolder:IsA("Folder") then
		return worldFolder
	end
	return nil
end

function Parallax._GetRootParent(self: Parallax): Instance
	local worldFolder = self:_GetWorldFolder()
	if worldFolder ~= nil then
		return worldFolder
	end
	return WorkspaceFolders.GetOrCreateFolderInGame(ROOT_PARENT_FALLBACK_NAME)
end

function Parallax._destroySurfaceRuntime(self: Parallax)
	local surfaceRuntime = self.surfaceRuntime
	if surfaceRuntime == nil then
		return
	end
	surfaceRuntime.reactRoot:unmount()
	if surfaceRuntime.anchorPart.Parent ~= nil then
		surfaceRuntime.anchorPart:Destroy()
	end
	self.surfaceRuntime = nil
	ParallaxThunks.ClearSurfaceState()
end

function Parallax._destroyAllBiomeRuntimes(self: Parallax)
	table.clear(self.activeBiomeRuntimes)
	if self.rootFolder ~= nil and self.rootFolder.Parent ~= nil and #self.rootFolder:GetChildren() <= 0 then
		self.rootFolder:Destroy()
		self.rootFolder = nil
	end
end

function Parallax._ensureRootFolder(self: Parallax)
	local parent = self:_GetRootParent()
	if self.rootFolder ~= nil and self.rootFolder.Parent == parent then
		return
	end

	self:_destroySurfaceRuntime()
	if self.rootFolder ~= nil and self.rootFolder.Parent ~= nil then
		self.rootFolder:Destroy()
	end
	self.rootFolder = createFolder(
		parent,
		self.catalog.settings.folderName ~= "" and self.catalog.settings.folderName or ROOT_FOLDER_NAME
	)
end

function Parallax._ensureSurfaceRuntime(self: Parallax): SurfaceRuntime?
	self:_ensureRootFolder()
	local rootFolder = self.rootFolder
	if rootFolder == nil then
		return nil
	end

	local current = self.surfaceRuntime
	if current ~= nil and current.anchorPart.Parent == rootFolder then
		return current
	end

	self:_destroySurfaceRuntime()
	for _, child in rootFolder:GetChildren() do
		child:Destroy()
	end

	local anchorPart = Instance.new("Part")
	anchorPart.Name = ANCHOR_PART_NAME
	anchorPart.Anchored = true
	anchorPart.Locked = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.CastShadow = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(WorldGenerationConstants.DEFAULT_TILE_DEPTH, 1, 1)
	anchorPart.Parent = rootFolder

	local root = ReactRoblox.createRoot(anchorPart)
	root:render(e(ParallaxRoot, {
		cloudsVisible = false,
	}))

	local runtime: SurfaceRuntime = {
		anchorPart = anchorPart,
		reactRoot = root,
	}
	self.surfaceRuntime = runtime
	return runtime
end

function Parallax._refreshWorldAttributes(self: Parallax)
	local worldFolder = self:_GetWorldFolder()
	if worldFolder == nil then
		self.worldOrigin = Vector3.zero
		self.worldTopY = ParallaxRuntimeConstants.DEFAULT_MAX_TILES_Y * 4 * 0.15
		self.worldBottomY = -ParallaxRuntimeConstants.DEFAULT_MAX_TILES_Y * 4 * 0.85
		self.worldSurfaceY = 0
		self.seaLevelY = 0
		self.maxTilesY = ParallaxRuntimeConstants.DEFAULT_MAX_TILES_Y
		self.basePlaneX = 0
		self.referenceGameplayPlaneDistanceX = nil
		self.scrollAnchorZ = nil
		self.scrollTravelZ = 0
		return
	end

	local originX = worldFolder:GetAttribute("WorldOriginX")
	local originY = worldFolder:GetAttribute("WorldOriginY")
	local originZ = worldFolder:GetAttribute("WorldOriginZ")
	local basePlaneX = worldFolder:GetAttribute("BasePlaneX")
	local worldTopY = worldFolder:GetAttribute("WorldTopY")
	local worldBottomY = worldFolder:GetAttribute("WorldBottomY")
	local worldSurfaceY = worldFolder:GetAttribute("WorldSurfaceY")
	local seaLevelY = worldFolder:GetAttribute("SeaLevelY")
	local maxTilesY = worldFolder:GetAttribute("MaxTilesY")
	local layoutSnapshot = self.layoutStateValue and self.layoutStateValue.Value
	local tileSize = if typeof(layoutSnapshot) == "table" and typeof(layoutSnapshot.tileSize) == "number"
		then math.max(layoutSnapshot.tileSize, 0.25)
		else 4

	local nextWorldOrigin = Vector3.new(
		if typeof(originX) == "number" then originX else 0,
		if typeof(originY) == "number" then originY else 0,
		if typeof(originZ) == "number" then originZ else 0
	)
	local nextBasePlaneX = if typeof(basePlaneX) == "number" then basePlaneX else 0
	local nextSeaLevelY = if typeof(seaLevelY) == "number" then seaLevelY else nextWorldOrigin.Y
	local nextWorldSurfaceY = if typeof(worldSurfaceY) == "number" then worldSurfaceY else nextSeaLevelY
	local nextMaxTilesY = if typeof(maxTilesY) == "number"
		then math.max(maxTilesY, 1)
		else ParallaxRuntimeConstants.DEFAULT_MAX_TILES_Y
	local fallbackWorldTopDepth = nextMaxTilesY * tileSize * ParallaxRuntimeConstants.PARALLAX_WORLD_TOP_DEPTH_FACTOR
	local minimumWorldTopDepth = math.max(
		tileSize * ParallaxRuntimeConstants.MIN_PARALLAX_WORLD_TOP_DEPTH_TILES,
		fallbackWorldTopDepth * ParallaxRuntimeConstants.MIN_PARALLAX_WORLD_TOP_DEPTH_FACTOR
	)
	local nextWorldTopY = if typeof(worldTopY) == "number"
			and worldTopY >= nextWorldSurfaceY + minimumWorldTopDepth
		then worldTopY
		else nextWorldSurfaceY + fallbackWorldTopDepth
	local nextWorldBottomY = if typeof(worldBottomY) == "number"
		then worldBottomY
		else nextWorldSurfaceY - nextMaxTilesY * tileSize * 0.85

	if self.worldOrigin ~= nextWorldOrigin or self.basePlaneX ~= nextBasePlaneX then
		self.referenceGameplayPlaneDistanceX = nil
		self.smoothedParallaxHorizonY = nil
		self.scrollAnchorZ = nil
		self.scrollTravelZ = 0
	end

	self.worldOrigin = nextWorldOrigin
	self.worldTopY = math.max(nextWorldTopY, nextWorldSurfaceY + tileSize)
	self.worldBottomY = math.min(nextWorldBottomY, nextWorldSurfaceY - tileSize)
	self.worldSurfaceY = nextWorldSurfaceY
	self.seaLevelY = nextSeaLevelY
	self.maxTilesY = nextMaxTilesY
	self.basePlaneX = nextBasePlaneX
end

function Parallax._GetGameplayPlaneReferenceDistance(self: Parallax, cameraPositionX: number): number
	if self.referenceGameplayPlaneDistanceX == nil then
		self.referenceGameplayPlaneDistanceX = ParallaxServiceUtils.GetStableGameplayPlaneDistance(
			nil,
			cameraPositionX,
			self.worldOrigin.X,
			self.basePlaneX
		)
	end

	return self.referenceGameplayPlaneDistanceX :: number
end

function Parallax._GetReferenceFieldOfView(self: Parallax, fieldOfView: number): number
	local referenceFieldOfView = self.referenceFieldOfView
	if referenceFieldOfView ~= nil then
		return referenceFieldOfView
	end

	local nextReferenceFieldOfView = math.clamp(fieldOfView, 1, 120)
	self.referenceFieldOfView = nextReferenceFieldOfView
	return nextReferenceFieldOfView
end

function Parallax._GetPlayerTravelZ(self: Parallax, subjectPosition: Vector3?): number
	local travelZ, anchorZ =
		ParallaxServiceUtils.GetPlayerTravelZ(self.scrollAnchorZ, self.scrollTravelZ, subjectPosition)
	self.scrollTravelZ = travelZ
	self.scrollAnchorZ = anchorZ
	return travelZ
end

function Parallax._GetDisplayedBiomeName(self: Parallax): string
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

function Parallax._GetSelectedVariantName(self: Parallax, biomeDefinition: BiomeDefinition): string
	local selectedVariantName = self.selectedBiomeVariantNames[biomeDefinition.name]
	if selectedVariantName ~= nil and biomeDefinition.variants[selectedVariantName] ~= nil then
		return selectedVariantName
	end

	local nextVariantName = ParallaxServiceUtils.GetVariantName(biomeDefinition, biomeDefinition.defaultVariantName)
	self.selectedBiomeVariantNames[biomeDefinition.name] = nextVariantName
	return nextVariantName
end

function Parallax._publishState(self: Parallax)
	if self.parallaxEnabled then
		self.stateValue.Value = cloneState(self.state)
		return
	end

	if self.state.targetBiome ~= "" then
		self.state.currentBiome = self:_GetDisplayedBiomeName()
	end
	self.stateValue.Value = cloneState(self.state)
end

function Parallax._createLayerRuntime(_self: Parallax, definition: LayerDefinition, layerIndex: number): LayerRuntime
	return {
		definition = definition,
		layerIndex = layerIndex,
	}
end

function Parallax._createBiomeRuntime(self: Parallax, biomeName: string): BiomeRuntime
	local definition = ParallaxServiceUtils.GetBiomeDefinition(self.catalog, biomeName)
	local variantName = self:_GetSelectedVariantName(definition)
	local variantDefinition = ParallaxServiceUtils.GetVariantDefinition(self.catalog, definition.name, variantName)
	local runtime: BiomeRuntime = {
		biomeName = definition.name,
		variantName = variantName,
		definition = definition,
		variantDefinition = variantDefinition,
		layers = {},
		alpha = 0,
		startAlpha = 0,
		targetAlpha = 0,
	}

	for layerIndex, layerDefinition in variantDefinition.layers do
		table.insert(runtime.layers, self:_createLayerRuntime(layerDefinition, layerIndex))
	end

	self.activeBiomeRuntimes[definition.name] = runtime
	return runtime
end

function Parallax._destroyBiomeRuntime(self: Parallax, biomeName: string)
	self.activeBiomeRuntimes[biomeName] = nil
end

function Parallax._cleanupInactiveBiomeRuntimes(self: Parallax)
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

function Parallax._setBiomeAlpha(_self: Parallax, biomeRuntime: BiomeRuntime, alphaRaw: number)
	biomeRuntime.alpha = math.clamp(alphaRaw, 0, 1)
end

function Parallax._stepTransition(self: Parallax, now: number)
	if not self.transitionActive then
		return
	end

	local duration = math.max(0.001, self.catalog.settings.transitionSeconds)
	local rawProgress = math.clamp((now - self.transitionStartedAt) / duration, 0, 1)
	for _, runtime in self.activeBiomeRuntimes do
		local nextAlpha = runtime.startAlpha + (runtime.targetAlpha - runtime.startAlpha) * rawProgress
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

function Parallax._preloadBiomeAssets(self: Parallax, biomeNameRaw: any)
	local biomeName = ParallaxServiceUtils.GetBiomeName(self.catalog, biomeNameRaw)
	if self.preloadedBiomes[biomeName] then
		return self.preloadBiomePromises[biomeName]
	end
	self.preloadedBiomes[biomeName] = true

	local assetIds = ParallaxServiceUtils.CollectAssetIds(self.catalog, { biomeName })
	if #assetIds <= 0 then
		local emptyPromise = Rx.toPromise(Rx.of(true))
		self.preloadBiomePromises[biomeName] = emptyPromise
		return emptyPromise
	end

	local preloadPromise = ContentProviderUtils.promisePreload(assetIds)
		:Then(function()
			return true
		end)
		:Catch(function()
			return false
		end)
	self.preloadBiomePromises[biomeName] = preloadPromise
	if self.maid ~= nil then
		self.maid:GivePromise(preloadPromise)
	end
	return preloadPromise
end

function Parallax._preloadAllAssets(self: Parallax)
	if self.didPreloadAllAssets then
		return self.preloadAllAssetsPromise
	end
	self.didPreloadAllAssets = true

	local assetIds = ParallaxServiceUtils.CollectAssetIds(self.catalog, nil)
	if #assetIds <= 0 then
		self.preloadAllAssetsPromise = Rx.toPromise(Rx.of(true))
		return self.preloadAllAssetsPromise
	end

	self.preloadAllAssetsPromise = ContentProviderUtils.promisePreload(assetIds)
		:Then(function()
			return true
		end)
		:Catch(function()
			return false
		end)
	if self.maid ~= nil then
		self.maid:GivePromise(self.preloadAllAssetsPromise)
	end
	return self.preloadAllAssetsPromise
end

function Parallax._GetCurrentWorldBiome(self: Parallax): string
	if self.parallaxEnabled then
		local sample = self:_GetCurrentParallaxSample()
		local style = Biome.GetBgStyle(sample, self.catalog)
		return Profile.GetStyleName(style)
	end

	local rawState = (WorldGenerationServiceClient :: any).state
	if typeof(rawState) ~= "table" or (rawState :: any).ready ~= true then
		return self.catalog.settings.defaultBiome
	end

	local camera = getCamera()
	if camera == nil then
		return self.catalog.settings.defaultBiome
	end

	local worldPosition = camera.CFrame.Position
	local biomeId = WorldGenerationServiceClient:GetBiomeIdAtWorldPosition(worldPosition)
	local biomeType = WorldGenerationServiceClient:GetBiomeTypeAtWorldPosition(worldPosition)
	local depthLayer = WorldGenerationServiceClient:GetDepthLayerAtWorldPosition(worldPosition)
	return ParallaxServiceUtils.GetBiomeNameFromWorldSample(self.catalog, biomeId, biomeType, depthLayer)
end

function Parallax._GetCurrentParallaxSample(self: Parallax): ParallaxWorldSample
	local camera = getCamera()
	local worldPosition = if camera ~= nil then camera.CFrame.Position else self.worldOrigin
	local rawState = (WorldGenerationServiceClient :: any).state
	if typeof(rawState) ~= "table" or (rawState :: any).ready ~= true then
		return {
			worldPosition = worldPosition,
			biomeName = self.catalog.settings.defaultBiome,
			depthLayer = ParallaxServiceUtils.DEPTH_LAYER_SKY,
		}
	end

	local richSample = callWorldGenerationMethod("GetParallaxSampleAtWorldPosition", worldPosition)
	if typeof(richSample) == "table" then
		local sample = richSample :: ParallaxWorldSample
		sample.worldPosition = worldPosition
		return sample
	end

	local biomeId = callWorldGenerationMethod("GetBiomeIdAtWorldPosition", worldPosition)
	local biomeType = callWorldGenerationMethod("GetBiomeTypeAtWorldPosition", worldPosition)
	local depthLayer = callWorldGenerationMethod("GetDepthLayerAtWorldPosition", worldPosition)
	local isNearWorldEdge = callWorldGenerationMethod("IsNearWorldEdge", worldPosition)
	local sandTileCount = callWorldGenerationMethod("GetSandTileCountNearWorldPosition", worldPosition)
	local shroomTileCount = callWorldGenerationMethod("GetShroomTileCountNearWorldPosition", worldPosition)
	local biomeName = ParallaxServiceUtils.GetBiomeNameFromWorldSample(self.catalog, biomeId, biomeType, depthLayer)

	return {
		worldPosition = worldPosition,
		biomeId = biomeId,
		biomeType = biomeType,
		biomeName = biomeName,
		depthLayer = depthLayer,
		isNearWorldEdge = if typeof(isNearWorldEdge) == "boolean" then isNearWorldEdge else nil,
		sandTileCount = if typeof(sandTileCount) == "number" then sandTileCount else nil,
		shroomTileCount = if typeof(shroomTileCount) == "number" then shroomTileCount else nil,
	}
end

function Parallax._computeSurfaceBackgroundAlpha(self: Parallax, cameraY: number): number
	local fadeDistance = math.max(self.surfaceBackgroundFadeDistance, 1)
	local horizon = self.lastParallaxHorizon
	local surfaceY = if horizon ~= nil then horizon.horizonY else self.worldSurfaceY
	local surfaceAlpha = math.clamp((cameraY - (surfaceY - fadeDistance)) / fadeDistance, 0, 1)
	local sample = self.currentParallaxSample
	if sample ~= nil and sample.depthLayer == ParallaxServiceUtils.DEPTH_LAYER_UNDERGROUND then
		return surfaceAlpha
	end
	return surfaceAlpha
end

function Parallax._publishParallaxDebugAttributes(
	self: Parallax,
	activeLayerIds: { string },
	bgTopValues: { string },
	layerSizeValues: { string },
	horizon: HorizonSample
)
	local rootFolder = self.rootFolder
	if rootFolder == nil then
		return
	end

	local parallaxState = self.parallaxState
	rootFolder:SetAttribute("ParallaxBgStyle", parallaxState.bgStyle)
	rootFolder:SetAttribute("ParallaxTargetBgStyle", parallaxState.targetBgStyle)
	rootFolder:SetAttribute("ParallaxBgAlpha", formatAlphaValues(parallaxState.bgAlpha))
	rootFolder:SetAttribute("ParallaxBgAlpha2", formatAlphaValues(parallaxState.bgAlpha2))
	rootFolder:SetAttribute("ParallaxWorldTopY", horizon.worldTopY)
	rootFolder:SetAttribute("ParallaxWorldSurfaceY", horizon.globalSurfaceY)
	rootFolder:SetAttribute("ParallaxWorldBottomY", self.worldBottomY)
	rootFolder:SetAttribute("ParallaxActiveProfileLayerIds", table.concat(activeLayerIds, ","))
	rootFolder:SetAttribute("ParallaxBgTopPx", table.concat(bgTopValues, ","))
	rootFolder:SetAttribute("ParallaxLayerWorldSize", table.concat(layerSizeValues, ","))
	rootFolder:SetAttribute("ParallaxhorizonY", horizon.horizonY)
	rootFolder:SetAttribute("ParallaxLocalSurfaceY", horizon.localSurfaceY)
	rootFolder:SetAttribute("ParallaxCameraDepthFromTop", horizon.cameraDepthFromTop)
	rootFolder:SetAttribute("ParallaxSurfaceDepthFromTop", horizon.surfaceDepthFromTop)
end

function Parallax._debugParallax(self: Parallax, message: string, payload: { [string]: any })
	if not self.debugParallax then
		return
	end

	local now = os.clock()
	if now - self.lastParallaxDebugPrintAt < ParallaxRuntimeConstants.PARALLAX_DEBUG_PRINT_INTERVAL then
		return
	end
	self.lastParallaxDebugPrintAt = now
	print(message, payload)
end

function Parallax._syncBiomeFromWorldSampleNow(self: Parallax): string
	local sampledBiome = self:_GetCurrentWorldBiome()
	self.state.currentBiome = sampledBiome
	self.state.targetBiome = sampledBiome
	self.stateValue.Value = cloneState(self.state)
	return sampledBiome
end

function Parallax._GetLayerMetric(
	self: Parallax,
	biomeRuntime: BiomeRuntime,
	layerRuntime: LayerRuntime,
	cameraPosition: Vector3,
	subjectPosition: Vector3?,
	scrollTravelZ: number,
	_now: number
): LayerMetric?
	local definition = layerRuntime.definition
	local layoutSnapshot = self.layoutStateValue.Value
	if layoutSnapshot == nil then
		layoutSnapshot = self:_GetCurrentLayoutSnapshot()
		self.layoutStateValue.Value = layoutSnapshot
	end

	local planeX = self.worldOrigin.X + self.basePlaneX - definition.planeDepthBlocks * layoutSnapshot.tileDepth
	local gameplayReferenceDistance = self:_GetGameplayPlaneReferenceDistance(cameraPosition.X)
	local coverageReferenceDistance = gameplayReferenceDistance
		+ math.abs((self.worldOrigin.X + self.basePlaneX) - planeX)
	local visibleWidth, visibleHeight = computeVisibleExtentsAtDistance(
		layoutSnapshot.fieldOfView,
		layoutSnapshot.viewportSize,
		coverageReferenceDistance
	)
	local referenceFieldOfView = self:_GetReferenceFieldOfView(layoutSnapshot.fieldOfView)
	local referenceVisibleWidth, referenceVisibleHeight =
		computeVisibleExtentsAtDistance(referenceFieldOfView, layoutSnapshot.viewportSize, coverageReferenceDistance)
	local sizeReferenceWidth = select(
		1,
		computeVisibleExtentsAtDistance(
			layoutSnapshot.fieldOfView,
			layoutSnapshot.viewportSize,
			gameplayReferenceDistance
		)
	)
	local referenceSizeWidth = select(
		1,
		computeVisibleExtentsAtDistance(referenceFieldOfView, layoutSnapshot.viewportSize, gameplayReferenceDistance)
	)
	local planeSizing: PlaneSizing = ParallaxServiceUtils.GetDeterministicPlaneSizing(
		visibleWidth,
		sizeReferenceWidth,
		layoutSnapshot.horizontalVisionStuds,
		definition.imageAspectRatio,
		definition.heightScale,
		definition.segmentWidthScale,
		definition.textureStudsPerTileU
	)
	local referencePlaneSizing: PlaneSizing = ParallaxServiceUtils.GetDeterministicPlaneSizing(
		referenceVisibleWidth,
		referenceSizeWidth,
		layoutSnapshot.horizontalVisionStuds,
		definition.imageAspectRatio,
		definition.heightScale,
		definition.segmentWidthScale,
		definition.textureStudsPerTileU
	)
	local textureRepeatHeight = planeSizing.textureRepeatHeight
	local referenceTextureRepeatHeight = referencePlaneSizing.textureRepeatHeight
	local visibleBottomY = cameraPosition.Y - visibleHeight * 0.5
	local horizonCenterY = ParallaxServiceUtils.GetWorldHorizonParallaxCenterY(
		self.worldOrigin.Y,
		cameraPosition.Y,
		visibleHeight,
		definition.baseYOffset,
		definition.verticalOffsetStuds,
		definition.verticalParallax,
		subjectPosition
	)

	local minimumViewHeight = visibleHeight * ParallaxRuntimeConstants.SURFACE_LAYER_MIN_VIEW_HEIGHT_FACTOR
	local maximumViewHeight = visibleHeight * ParallaxRuntimeConstants.SURFACE_LAYER_MAX_VIEW_HEIGHT_FACTOR
	textureRepeatHeight = math.clamp(textureRepeatHeight, minimumViewHeight, maximumViewHeight)
	referenceTextureRepeatHeight = math.clamp(
		referenceTextureRepeatHeight,
		referenceVisibleHeight * ParallaxRuntimeConstants.SURFACE_LAYER_MIN_VIEW_HEIGHT_FACTOR,
		referenceVisibleHeight * ParallaxRuntimeConstants.SURFACE_LAYER_MAX_VIEW_HEIGHT_FACTOR
	)
	local textureRepeatWidth = computeTextureRepeatWidthFromHeight(definition, textureRepeatHeight)
	local referenceTextureRepeatWidth = computeTextureRepeatWidthFromHeight(definition, referenceTextureRepeatHeight)
	local planeWidth = math.max(planeSizing.planeWidth, textureRepeatWidth)
	local planeHeight = textureRepeatHeight
	local bottomBleed = math.max(
		visibleHeight * definition.bottomOverscan,
		ParallaxRuntimeConstants.MIN_PLANE_VERTICAL_COVERAGE_BLEED_STUDS
	)
	local highestHiddenBottomCenterY = visibleBottomY - bottomBleed + planeHeight * 0.5
	local transparency = blendToLayerTransparency(definition.transparency, biomeRuntime.alpha)
	if transparency >= 0.999 then
		return nil
	end

	return {
		id = getLayerRenderId(biomeRuntime, layerRuntime),
		image = definition.image,
		tint = definition.tint,
		transparency = transparency,
		centerY = horizonCenterY,
		maximumCenterY = highestHiddenBottomCenterY,
		centerZ = cameraPosition.Z,
		width = planeWidth,
		height = planeHeight,
		textureRepeatWidth = textureRepeatWidth,
		textureRepeatHeight = textureRepeatHeight,
		textureOffsetU = Math.RescaleWrappedOffset(
			Scrolling.ComputeHorizontalOffsetStuds(
				scrollTravelZ,
				definition.depth,
				definition.scrollSpeed,
				referenceTextureRepeatWidth,
				_now
			),
			referenceTextureRepeatWidth,
			textureRepeatWidth
		),
		textureOffsetV = Math.RescaleWrappedOffset(
			Scrolling.ComputeVerticalOffsetStuds(referenceTextureRepeatHeight),
			referenceTextureRepeatHeight,
			textureRepeatHeight
		),
		planeDepthBlocks = definition.planeDepthBlocks,
		zIndex = 1000 - layerRuntime.layerIndex,
	}
end

function Parallax._collectLayerMetrics(self: Parallax, cameraPosition: Vector3, now: number): { LayerMetric }
	local metrics: { LayerMetric } = {}
	local subjectPosition = getCharacterRootPosition(self.localPlayer)
	local scrollTravelZ = self:_GetPlayerTravelZ(subjectPosition)
	for _, biomeRuntime in self.activeBiomeRuntimes do
		for _, layerRuntime in biomeRuntime.layers do
			local metric =
				self:_GetLayerMetric(biomeRuntime, layerRuntime, cameraPosition, subjectPosition, scrollTravelZ, now)
			if metric ~= nil then
				table.insert(metrics, metric)
			end
		end
	end
	local sharedVerticalShift = ParallaxServiceUtils.GetSharedHorizonVerticalShift(metrics)
	if sharedVerticalShift ~= 0 then
		for _, metric in metrics do
			metric.centerY += sharedVerticalShift
		end
	end
	table.sort(metrics, function(left: LayerMetric, right: LayerMetric): boolean
		if left.zIndex == right.zIndex then
			return left.id < right.id
		end
		return left.zIndex < right.zIndex
	end)
	return metrics
end

function Parallax._collectParallaxLayerMetrics(
	self: Parallax,
	cameraPosition: Vector3,
	now: number,
	dt: number
): { LayerMetric }
	local metrics: { LayerMetric } = {}
	local activeLayerIds: { string } = {}
	local bgTopValues: { string } = {}
	local layerSizeValues: { string } = {}
	local subjectPosition = getCharacterRootPosition(self.localPlayer)
	local layoutSnapshot = self.layoutStateValue.Value
	if layoutSnapshot == nil then
		layoutSnapshot = self:_GetCurrentLayoutSnapshot()
		self.layoutStateValue.Value = layoutSnapshot
	end

	local gameplayReferenceDistance = self:_GetGameplayPlaneReferenceDistance(cameraPosition.X)
	local screenHeight = math.max(layoutSnapshot.viewportSize.Y, 1)
	local parallaxUiScale = Math.ComputeUiScale(screenHeight)
	local referenceFieldOfView = self:_GetReferenceFieldOfView(layoutSnapshot.fieldOfView)
	local stylesByProfile = Profile.ByStyle
	local horizon = Horizon.GetHorizon(self, cameraPosition, subjectPosition, dt)
	self.lastParallaxHorizon = horizon
	local scrollTravelZ = self:_GetPlayerTravelZ(subjectPosition)
	local screenTopDepthPx =
		Math.ComputeScreenTopDepthPx(horizon.cameraDepthFromTop, screenHeight, layoutSnapshot.tileSize)
	local surfaceDepthPx = Math.ComputeDepthWorldToTerrariaPixels(horizon.surfaceDepthFromTop, layoutSnapshot.tileSize)
	local surfaceAlpha = self:_computeSurfaceBackgroundAlpha(cameraPosition.Y)
	local debugPayload = nil :: { [string]: any }?

	for style, profiles in stylesByProfile do
		for layerIndex, profile in profiles :: { LayerProfile } do
			local styleAlpha = self.parallaxState:GetStyleAlpha(profile.bgStyle)
			if profile.alphaGroup == "bgAlpha2" then
				styleAlpha *= self.parallaxState:GetFarAlpha(profile.bgStyle)
			end
			if styleAlpha <= 0.001 or surfaceAlpha <= 0.001 then
				continue
			end

			local planeDepthBlocks = profile.planeDepthBlocks or 40
			local planeX = self.worldOrigin.X + self.basePlaneX - planeDepthBlocks * layoutSnapshot.tileDepth
			local coverageReferenceDistance = gameplayReferenceDistance
				+ math.abs((self.worldOrigin.X + self.basePlaneX) - planeX)
			local visibleWidth, visibleHeight = computeVisibleExtentsAtDistance(
				layoutSnapshot.fieldOfView,
				layoutSnapshot.viewportSize,
				coverageReferenceDistance
			)
			local _, referenceVisibleHeight = computeVisibleExtentsAtDistance(
				referenceFieldOfView,
				layoutSnapshot.viewportSize,
				coverageReferenceDistance
			)
			local textureRepeatWidth, textureRepeatHeight = Math.ComputeTextureSizeWorld(
				profile.imageWidth or 1024,
				profile.imageHeight or 600,
				profile.bgScale,
				visibleHeight,
				screenHeight,
				parallaxUiScale,
				ParallaxConstants.TERRARIA_PARALLAX_LAYER_SIZE_SCALE
			)
			local referenceTextureRepeatWidth, referenceTextureRepeatHeight = Math.ComputeTextureSizeWorld(
				profile.imageWidth or 1024,
				profile.imageHeight or 600,
				profile.bgScale,
				referenceVisibleHeight,
				screenHeight,
				parallaxUiScale,
				ParallaxConstants.TERRARIA_PARALLAX_LAYER_SIZE_SCALE
			)
			local scAdj = Math.ComputeScreenAdjustment(screenTopDepthPx, screenHeight, surfaceDepthPx, self.maxTilesY)
			local bgTopPx = Math.ComputeBgTopPx(
				screenTopDepthPx,
				screenHeight,
				surfaceDepthPx,
				profile.verticalStrength,
				profile.baseScreenY,
				scAdj,
				profile.offsetY
			) + ParallaxConstants.TERRARIA_PARALLAX_ART_TOP_PADDING_PX
			local centerY = Math.ScreenTopPxToWorldCenterY(
				bgTopPx,
				screenHeight,
				cameraPosition.Y,
				visibleHeight,
				textureRepeatHeight,
				parallaxUiScale
			)
			local horizontalBleed = math.max(
				visibleWidth * ParallaxConstants.HORIZONTAL_PLANE_BLEED_FACTOR,
				ParallaxConstants.MINIMUM_HORIZONTAL_PLANE_BLEED_STUDS
			)
			local planeWidth = math.max(
				textureRepeatWidth,
				visibleWidth + horizontalBleed,
				layoutSnapshot.horizontalVisionStuds + horizontalBleed
			)
			local visibleBottomY = cameraPosition.Y - visibleHeight * 0.5
			local bottomBleed = math.max(
				visibleHeight * ParallaxRuntimeConstants.PARALLAX_SURFACE_BOTTOM_OVERSCAN,
				ParallaxRuntimeConstants.MIN_PLANE_VERTICAL_COVERAGE_BLEED_STUDS
			)
			local highestHiddenBottomCenterY = visibleBottomY - bottomBleed + textureRepeatHeight * 0.5
			local transparency = blendToParallaxLayerTransparency(profile.transparency or 0, styleAlpha, surfaceAlpha)
			if transparency >= 0.999 then
				continue
			end

			if debugPayload == nil then
				debugPayload = {
					worldTopY = horizon.worldTopY,
					worldSurfaceY = horizon.globalSurfaceY,
					horizonY = horizon.horizonY,
					cameraY = cameraPosition.Y,
					cameraDepthFromTop = horizon.cameraDepthFromTop,
					surfaceDepthFromTop = horizon.surfaceDepthFromTop,
					screenTopDepthPx = screenTopDepthPx,
					surfaceDepthPx = surfaceDepthPx,
					bgTopPx = bgTopPx,
					visibleHeight = visibleHeight,
					layerHeightWorld = textureRepeatHeight,
					centerY = centerY,
					uiScale = parallaxUiScale,
					artTopPaddingPx = ParallaxConstants.TERRARIA_PARALLAX_ART_TOP_PADDING_PX,
					activeLayerIds = activeLayerIds,
					parallaxX = profile.parallaxX,
					bgScale = profile.bgScale,
					baseScreenY = profile.baseScreenY,
					verticalStrength = profile.verticalStrength,
				}
			end

			table.insert(activeLayerIds, profile.id)
			table.insert(bgTopValues, `{profile.id}:{string.format("%.1f", bgTopPx)}`)
			table.insert(
				layerSizeValues,
				`{profile.id}:{string.format("%.1f", textureRepeatWidth)}x{string.format("%.1f", textureRepeatHeight)}`
			)
			table.insert(metrics, {
				id = `{Profile.GetStyleName(style)}_{profile.id}`,
				image = profile.image,
				tint = profile.tint or Color3.new(1, 1, 1),
				transparency = transparency,
				centerY = centerY,
				maximumCenterY = highestHiddenBottomCenterY,
				centerZ = cameraPosition.Z,
				width = planeWidth,
				height = textureRepeatHeight,
				textureRepeatWidth = textureRepeatWidth,
				textureRepeatHeight = textureRepeatHeight,
				textureOffsetU = Math.RescaleWrappedOffset(
					Math.ComputeHorizontalTextureOffsetWorld(
						scrollTravelZ + (profile.offsetX or 0),
						profile.parallaxX,
						referenceTextureRepeatWidth,
						0,
						now
					),
					referenceTextureRepeatWidth,
					textureRepeatWidth
				),
				textureOffsetV = Math.RescaleWrappedOffset(
					Scrolling.ComputeVerticalOffsetStuds(referenceTextureRepeatHeight),
					referenceTextureRepeatHeight,
					textureRepeatHeight
				),
				planeDepthBlocks = planeDepthBlocks,
				zIndex = profile.zIndex or (1000 - layerIndex),
			})
		end
	end

	if self.enableParallaxBottomGuard then
		local sharedVerticalShift = ParallaxServiceUtils.GetSharedHorizonVerticalShift(metrics)
		if sharedVerticalShift ~= 0 then
			for _, metric in metrics do
				metric.centerY += sharedVerticalShift
			end
		end
	end
	table.sort(metrics, function(left: LayerMetric, right: LayerMetric): boolean
		if left.zIndex == right.zIndex then
			return left.id < right.id
		end
		return left.zIndex < right.zIndex
	end)
	if debugPayload ~= nil then
		self:_debugParallax("Parallax", debugPayload)
	end
	self:_publishParallaxDebugAttributes(activeLayerIds, bgTopValues, layerSizeValues, horizon)
	return metrics
end

function Parallax._publishSurfaceState(self: Parallax, metrics: { LayerMetric }, cameraPosition: Vector3)
	local surfaceRuntime = self:_ensureSurfaceRuntime()
	if surfaceRuntime == nil or #metrics <= 0 then
		ParallaxThunks.ClearSurfaceState()
		return
	end

	local minPlaneDepthBlocks = math.huge
	for _, metric in metrics do
		minPlaneDepthBlocks = math.min(minPlaneDepthBlocks, metric.planeDepthBlocks)
	end

	local layoutSnapshot = self.layoutStateValue.Value
	if layoutSnapshot == nil then
		layoutSnapshot = self:_GetCurrentLayoutSnapshot()
		self.layoutStateValue.Value = layoutSnapshot
	end
	local anchorPlaneX = self.worldOrigin.X + self.basePlaneX - minPlaneDepthBlocks * layoutSnapshot.tileDepth
	local referenceAnchorDistance = self:_GetGameplayPlaneReferenceDistance(cameraPosition.X)
		+ math.abs((self.worldOrigin.X + self.basePlaneX) - anchorPlaneX)
	local _, referenceAnchorVisibleHeight = computeVisibleExtentsAtDistance(
		layoutSnapshot.fieldOfView,
		layoutSnapshot.viewportSize,
		referenceAnchorDistance
	)
	local _, anchorVisibleHeight = computeVisibleExtentsAtDistance(
		layoutSnapshot.fieldOfView,
		layoutSnapshot.viewportSize,
		math.abs(cameraPosition.X - anchorPlaneX)
	)
	local projectionScale = Math.ComputeProjectionScale(referenceAnchorVisibleHeight, anchorVisibleHeight)

	local minY = math.huge
	local maxY = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	for _, metric in metrics do
		metric.centerY = cameraPosition.Y + (metric.centerY - cameraPosition.Y) * projectionScale
		metric.centerZ = cameraPosition.Z + (metric.centerZ - cameraPosition.Z) * projectionScale
		metric.width *= projectionScale
		metric.height *= projectionScale
		metric.textureRepeatWidth *= projectionScale
		metric.textureRepeatHeight *= projectionScale
		metric.textureOffsetU *= projectionScale
		metric.textureOffsetV *= projectionScale

		minY = math.min(minY, metric.centerY - metric.height * 0.5)
		maxY = math.max(maxY, metric.centerY + metric.height * 0.5)
		minZ = math.min(minZ, metric.centerZ - metric.width * 0.5)
		maxZ = math.max(maxZ, metric.centerZ + metric.width * 0.5)
	end
	local rawAnchorHeightStuds = math.max(maxY - minY, 1)
	local rawAnchorWidthStuds = math.max(maxZ - minZ, 1)
	local verticalOverscan = math.max(
		rawAnchorHeightStuds * ParallaxRuntimeConstants.SURFACE_ANCHOR_VERTICAL_OVERSCAN_FACTOR,
		ParallaxRuntimeConstants.MIN_SURFACE_ANCHOR_OVERSCAN_STUDS
	)
	local horizontalOverscan = math.max(
		rawAnchorWidthStuds * ParallaxRuntimeConstants.SURFACE_ANCHOR_HORIZONTAL_OVERSCAN_FACTOR,
		ParallaxRuntimeConstants.MIN_SURFACE_ANCHOR_OVERSCAN_STUDS
	)
	minY -= verticalOverscan
	maxY += verticalOverscan
	minZ -= horizontalOverscan
	maxZ += horizontalOverscan

	local anchorHeightStuds = math.max(maxY - minY, 1)
	local anchorWidthStuds = math.max(maxZ - minZ, 1)
	local anchorCenterY = (minY + maxY) * 0.5
	local anchorCenterZ = (minZ + maxZ) * 0.5
	local pixelsPerStud = getSurfacePixelsPerStud(anchorWidthStuds, anchorHeightStuds)
	local canvasWidth = toCanvasPixels(anchorWidthStuds, pixelsPerStud)
	local canvasHeight = toCanvasPixels(anchorHeightStuds, pixelsPerStud)

	surfaceRuntime.anchorPart.Size =
		Vector3.new(WorldGenerationConstants.DEFAULT_TILE_DEPTH, anchorHeightStuds, anchorWidthStuds)
	surfaceRuntime.anchorPart.CFrame = CFrame.new(anchorPlaneX, anchorCenterY, anchorCenterZ)
	local surfaceFace = if cameraPosition.X >= anchorPlaneX then Enum.NormalId.Right else Enum.NormalId.Left

	local layers = table.create(#metrics)
	local anchorMinZ = anchorCenterZ - anchorWidthStuds * 0.5
	local anchorMaxY = anchorCenterY + anchorHeightStuds * 0.5
	for index, metric in metrics do
		local frameWidth = math.max(metric.width * pixelsPerStud, 1)
		local frameHeight = math.max(metric.height * pixelsPerStud, 1)
		local frameCenterX = (metric.centerZ - anchorMinZ) * pixelsPerStud
		local frameCenterY = (anchorMaxY - metric.centerY) * pixelsPerStud
		local tileWidth =
			math.max(metric.textureRepeatWidth * pixelsPerStud * ParallaxRuntimeConstants.SURFACE_TILE_SCALE, 1)
		local tileHeight =
			math.max(metric.textureRepeatHeight * pixelsPerStud * ParallaxRuntimeConstants.SURFACE_TILE_SCALE, 1)
		local imageOffsetX = Scrolling.ComputeOffsetPixels(metric.textureOffsetU, metric.textureRepeatWidth, tileWidth)
		local imageOffsetY =
			Scrolling.ComputeOffsetPixels(metric.textureOffsetV, metric.textureRepeatHeight, tileHeight)
		local extraWidth = tileWidth * ParallaxRuntimeConstants.SURFACE_EXTRA_TILE_COUNT
		local extraHeight = tileHeight * ParallaxRuntimeConstants.SURFACE_EXTRA_TILE_COUNT

		layers[index] = {
			id = metric.id,
			image = metric.image,
			imageColor = metric.tint,
			imageTransparency = metric.transparency,
			framePosition = UDim2.fromOffset(frameCenterX, frameCenterY),
			frameSize = UDim2.fromOffset(frameWidth, frameHeight),
			imagePosition = UDim2.fromOffset(-imageOffsetX, -imageOffsetY),
			imageSize = UDim2.fromOffset(frameWidth + extraWidth, frameHeight + extraHeight),
			tileSize = UDim2.fromOffset(tileWidth, tileHeight),
			zIndex = metric.zIndex,
		}
	end

	ParallaxThunks.PublishSurfaceState({
		visible = true,
		adornee = surfaceRuntime.anchorPart,
		face = surfaceFace,
		brightness = ParallaxRuntimeConstants.SURFACE_BRIGHTNESS,
		canvasSize = Vector2.new(canvasWidth, canvasHeight),
		layers = layers,
	} :: ParallaxSurfaceState)
end

function Parallax._render(self: Parallax)
	if not self.initialized then
		return
	end

	self:_refreshWorldAttributes()
	local surfaceRuntime = self:_ensureSurfaceRuntime()
	if surfaceRuntime == nil then
		return
	end

	local now = os.clock()

	local camera = getCamera()
	if camera == nil then
		ParallaxThunks.ClearSurfaceState()
		return
	end

	local cameraPosition = camera.CFrame.Position
	local metrics
	if self.parallaxEnabled then
		local dt = if self.lastParallaxUpdateAt ~= nil
			then math.clamp(now - self.lastParallaxUpdateAt, 0, 0.25)
			else 1 / 60
		self.lastParallaxUpdateAt = now
		local sample = self:_GetCurrentParallaxSample()
		self.currentParallaxSample = sample
		local targetBgStyle = self.manualBgStyle or Biome.GetBgStyle(sample, self.catalog)
		self.parallaxState:Update(targetBgStyle, dt)
		self.state.targetBiome = Profile.GetStyleName(targetBgStyle)
		self.state.currentBiome = Profile.GetStyleName(self.parallaxState.bgStyle)
		self.state.transitionState = if self.parallaxState.bgStyle == targetBgStyle then "Idle" else "Blending"
		self:_publishState()
		metrics = self:_collectParallaxLayerMetrics(cameraPosition, now, dt)
	else
		self:_stepTransition(now)
		metrics = self:_collectLayerMetrics(cameraPosition, now)
	end
	self:_publishSurfaceState(metrics, cameraPosition)
end

function Parallax.Init(self: Parallax, _container: Instance?)
	self:_initializeCoreState()

	if self.maid == nil then
		self.maid = Maid.new()
		self.reactiveStreamsMaid = Maid.new()
		self.maid:GiveTask(self.stateValue)
		self.maid:GiveTask(self.layoutStateValue)
		self.maid:GiveTask(self.reactiveStreamsMaid)
		self.maid:GiveTask(function()
			if self.renderStepName ~= nil then
				RunService:UnbindFromRenderStep(self.renderStepName)
				self.renderStepName = nil
			end
			self:_destroySurfaceRuntime()
			self:_destroyAllBiomeRuntimes()
			if self.rootFolder ~= nil and self.rootFolder.Parent ~= nil then
				self.rootFolder:Destroy()
			end
			self.rootFolder = nil
		end)
		self:_bindReactiveStreams()
	end

	if self.initialized then
		return
	end

	self:_ensureRootFolder()
	self:_ensureSurfaceRuntime()
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

	self.renderStepName = ("ParallaxFeatureRender_%d"):format(math.floor(os.clock() * 1000))
	RunService:BindToRenderStep(self.renderStepName, Enum.RenderPriority.Camera.Value + 5, function()
		self:_render()
	end)
end

function Parallax.SetBiome(self: Parallax, biomeNameRaw: any)
	if not self.initialized then
		self:Init(nil)
	end

	if self.parallaxEnabled then
		self.manualBgStyle = Profile.GetStyleFromBiomeName(biomeNameRaw)
	end

	local biomeName = ParallaxServiceUtils.GetBiomeName(self.catalog, biomeNameRaw)
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

function Parallax.ForceRefresh(self: Parallax)
	self.catalog = ParallaxServiceUtils.NormalizeCatalog(ParallaxBackgrounds)
	self.preloadedBiomes = {}
	self.preloadBiomePromises = {}
	self.selectedBiomeVariantNames = {}
	self.didPreloadAllAssets = false
	self.preloadAllAssetsPromise = nil
	self.referenceGameplayPlaneDistanceX = nil
	self.referenceFieldOfView = nil
	self.smoothedParallaxHorizonY = nil
	self.parallaxState = State.new()
	self.currentParallaxSample = nil
	self.manualBgStyle = nil
	self.lastParallaxHorizon = nil
	self.lastParallaxDebugPrintAt = 0
	self.lastParallaxUpdateAt = nil
	self:_destroyAllBiomeRuntimes()
	self:_ensureRootFolder()
	self:_ensureSurfaceRuntime()
	self:_refreshWorldAttributes()
	self:_bindReactiveStreams()

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

function Parallax.ObserveState(self: Parallax): ObservableObject
	self:_initializeCoreState()

	if self.stateObservable == nil then
		self.stateObservable = self.stateValue:Observe():Pipe({
			Rx.map(function(state: ServiceState)
				return cloneState(state)
			end),
		}) :: ObservableObject
	end

	return self.stateObservable
end

function Parallax.GetStateChangedSignal(self: Parallax): RxSignalObject
	self:_initializeCoreState()
	return self.stateChangedSignal
end

function Parallax.GetState(self: Parallax): ServiceState
	self:_initializeCoreState()
	return cloneState(self.state)
end

function Parallax.GetCurrentBiome(self: Parallax): string
	return self:GetState().currentBiome
end

function Parallax.Destroy(self: Parallax)
	if self.activeBiomeRuntimes ~= nil then
		self:_destroyAllBiomeRuntimes()
	end
	if self.preloadBiomePromises ~= nil then
		table.clear(self.preloadBiomePromises)
	end
	if self.preloadedBiomes ~= nil then
		table.clear(self.preloadedBiomes)
	end
	if self.selectedBiomeVariantNames ~= nil then
		table.clear(self.selectedBiomeVariantNames)
	end
	if self.maid ~= nil then
		self.maid:Destroy()
		self.maid = nil
	end
	self.reactiveStreamsMaid = nil
	self.stateObservable = nil
	self.stateChangedSignal = nil
	self.stateValue = nil
	self.layoutStateValue = nil
	self.preloadAllAssetsPromise = nil
	self.referenceGameplayPlaneDistanceX = nil
	self.referenceFieldOfView = nil
	self.scrollAnchorZ = nil
	self.scrollTravelZ = 0
	self.initialized = false
end
export type Parallax = typeof(setmetatable(
	{} :: {
		localPlayer: Player,
		maid: any,
		reactiveStreamsMaid: any,
		catalog: Catalog,
		state: ServiceState,
		stateValue: any,
		stateObservable: any,
		stateChangedSignal: any,
		layoutStateValue: any,
		activeBiomeRuntimes: { [string]: BiomeRuntime },
		preloadedBiomes: { [string]: boolean },
		preloadBiomePromises: { [string]: any },
		selectedBiomeVariantNames: { [string]: string },
		didPreloadAllAssets: boolean,
		preloadAllAssetsPromise: any?,
		referenceGameplayPlaneDistanceX: number?,
		referenceFieldOfView: number?,
		scrollAnchorZ: number?,
		scrollTravelZ: number,
		transitionActive: boolean,
		transitionStartedAt: number,
		rootFolder: Folder?,
		surfaceRuntime: SurfaceRuntime?,
		worldOrigin: Vector3,
		worldTopY: number,
		worldBottomY: number,
		worldSurfaceY: number,
		seaLevelY: number,
		maxTilesY: number,
		basePlaneX: number,
		smoothedParallaxHorizonY: number?,
		parallaxState: any,
		parallaxEnabled: boolean,
		enableParallaxBottomGuard: boolean,
		debugParallax: boolean,
		surfaceBackgroundFadeDistance: number,
		currentParallaxSample: ParallaxWorldSample?,
		manualBgStyle: number?,
		lastParallaxHorizon: HorizonSample?,
		lastParallaxDebugPrintAt: number,
		lastParallaxUpdateAt: number?,
		renderStepName: string?,
		initialized: boolean,
	},
	{} :: typeof({ __index = Parallax })
))

return Parallax
