--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(packageRoot)

local ContentProviderUtils = loader("ContentProviderUtils")
local Maid = loader("Maid")
local Rx = loader("Rx")
local RxSignal = loader("RxSignal")
local ValueObject = loader("ValueObject")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local ParallaxBackgrounds = require(script.Parent.Parent.modules.ParallaxBackgrounds)
local ParallaxScreen = require(script.Parent.Parent.ui.screens.ParallaxScreen)
local ParallaxServiceUtils = require(script.Parent.Parent.ParallaxServiceUtils)
local ParallaxSlice = require(script.Parent.Parent.ParallaxSlice)
local ParallaxThunks = require(script.Parent.Parent.ParallaxThunks)
local Scrolling = require(script.Parent.Parent.modules.Scrolling)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Core.WorkspaceFolders)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)

type Catalog = ParallaxServiceUtils.Catalog
type BiomeDefinition = ParallaxServiceUtils.BiomeDefinition
type BiomeVariantDefinition = ParallaxServiceUtils.BiomeVariantDefinition
type LayerDefinition = ParallaxServiceUtils.LayerDefinition
type PlaneSizing = ParallaxServiceUtils.PlaneSizing
type ServiceState = ParallaxServiceUtils.ServiceState
type ParallaxSurfaceState = ParallaxSlice.ParallaxSurfaceState

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	GivePromise: (self: MaidClass, promise: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
	[string]: any,
}

type ObservableObject = {
	Subscribe: (
		self: ObservableObject,
		fireCallback: ((...any) -> ())?,
		failCallback: ((...any) -> ())?,
		completeCallback: ((...any) -> ())?
	) -> any,
	Pipe: (self: ObservableObject, transformers: { any }) -> ObservableObject,
}

type RxSignalObject = {
	Connect: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Once: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Wait: (self: RxSignalObject) -> ...any,
}

type ValueObjectClass<T> = {
	Value: T,
	Observe: (self: ValueObjectClass<T>) -> ObservableObject,
	Destroy: (self: ValueObjectClass<T>) -> (),
}

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

local Parallax = {}
Parallax.__index = Parallax

local WORLD_FOLDER_NAME = "WorldGeneration"
local ROOT_PARENT_FALLBACK_NAME = "ParallaxService"
local ROOT_FOLDER_NAME = "ParallaxDepth"
local ANCHOR_PART_NAME = "ParallaxAnchor"
local SURFACE_BRIGHTNESS = 0.5
local SURFACE_PIXELS_PER_STUD = 8
local MAX_SURFACE_CANVAS_PIXELS = 20000
local MIN_SURFACE_CANVAS_PIXELS = 1
local SURFACE_EXTRA_TILE_COUNT = 1
local SURFACE_TILE_SCALE = 1
local SURFACE_LAYER_MIN_VIEW_HEIGHT_FACTOR = 1.06
local SURFACE_LAYER_MAX_VIEW_HEIGHT_FACTOR = 1.16
local MIN_PLANE_VERTICAL_COVERAGE_BLEED_STUDS = 4
local SURFACE_ANCHOR_VERTICAL_OVERSCAN_FACTOR = 0.14
local SURFACE_ANCHOR_HORIZONTAL_OVERSCAN_FACTOR = 0.18
local MIN_SURFACE_ANCHOR_OVERSCAN_STUDS = 8
local DEFAULT_CAMERA_FIELD_OF_VIEW = 70
local DEFAULT_CAMERA_VIEWPORT = Vector2.new(1920, 1080)

local e: typeof(React.createElement) = React.createElement

local function createFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return WorkspaceFolders.manageFolder(existing, parent) or existing
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return WorkspaceFolders.manageFolder(folder, parent) or folder
end

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function resolveCameraSnapshot(camera: Camera?): CameraSnapshot
	if camera == nil then
		return {
			fieldOfView = DEFAULT_CAMERA_FIELD_OF_VIEW,
			viewportSize = DEFAULT_CAMERA_VIEWPORT,
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
	local resolvedDistance = math.max(distance, 1)
	local visibleHeight = 2 * resolvedDistance * math.tan(math.rad(fieldOfViewDegrees) * 0.5)
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

local function cloneState(state: ServiceState): ServiceState
	return ParallaxServiceUtils.cloneState(state)
end

local function resolveSurfacePixelsPerStud(widthStuds: number, heightStuds: number): number
	local largestAxis = math.max(widthStuds, heightStuds, 1)
	return math.max(1, math.min(SURFACE_PIXELS_PER_STUD, MAX_SURFACE_CANVAS_PIXELS / largestAxis))
end

local function toCanvasPixels(studs: number, pixelsPerStud: number): number
	return math.clamp(
		math.ceil(math.max(studs, 0) * pixelsPerStud),
		MIN_SURFACE_CANVAS_PIXELS,
		MAX_SURFACE_CANVAS_PIXELS
	)
end

local function resolveLayerRenderId(biomeRuntime: BiomeRuntime, layerRuntime: LayerRuntime): string
	local layerId = layerRuntime.definition.id
	if layerId == "" then
		layerId = `Layer{layerRuntime.layerIndex}`
	end
	return `{biomeRuntime.biomeName}_{biomeRuntime.variantName}_{layerId}`
end

function Parallax.new(): Parallax
	local self = setmetatable({}, Parallax)
	self.localPlayer = Players.LocalPlayer
	self.catalog = ParallaxServiceUtils.normalizeCatalog(ParallaxBackgrounds)
	self.state = ParallaxServiceUtils.createDefaultState(self.catalog)
	self.activeBiomeRuntimes = {}
	self.preloadedBiomes = {}
	self.preloadBiomePromises = {}
	self.selectedBiomeVariantNames = {}
	self.didPreloadAllAssets = false
	self.preloadAllAssetsPromise = nil
	self.referenceGameplayPlaneDistanceX = nil
	self.transitionActive = false
	self.transitionStartedAt = 0
	self.rootFolder = nil
	self.surfaceRuntime = nil
	self.worldOrigin = Vector3.zero
	self.basePlaneX = 0
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
		self.layoutStateValue = ValueObject.new(self:_resolveCurrentLayoutSnapshot(), "table") :: any
	end
end

function Parallax._resolveWorldLayoutSnapshot(_self: Parallax, stateRaw: any?): WorldLayoutSnapshot
	local fallbackState = ((WorldGenerationServiceClient :: any).state :: { [string]: any }?) or {}
	local state = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else fallbackState
	local tileDepth = if typeof(state.tileDepth) == "number" then math.max(state.tileDepth, 0.5) else 4
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
		horizontalVisionStuds = ParallaxServiceUtils.computeHorizontalVisionStuds(
			chunkSize,
			tileSize,
			renderDistanceChunks
		),
	}
end

function Parallax._resolveCurrentLayoutSnapshot(self: Parallax): LayoutSnapshot
	local cameraSnapshot = resolveCameraSnapshot(getCamera())
	local worldSnapshot = self:_resolveWorldLayoutSnapshot()
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
				return Rx.of(resolveCameraSnapshot(nil)) :: any
			end

			return Rx.merge({
				Rx.of(true),
				Rx.fromSignal(camera:GetPropertyChangedSignal("FieldOfView")),
				Rx.fromSignal(camera:GetPropertyChangedSignal("ViewportSize")),
			}):Pipe({
				Rx.map(function()
					return resolveCameraSnapshot(camera)
				end),
			}) :: any
		end),
		Rx.throttleDefer(),
	}) :: ObservableObject
end

function Parallax._observeWorldLayoutSnapshot(self: Parallax): ObservableObject
	local worldStateSignal = (WorldGenerationServiceClient :: any).stateChanged
	if worldStateSignal == nil then
		return Rx.of(self:_resolveWorldLayoutSnapshot()) :: any
	end

	return Rx.fromSignal(worldStateSignal):Pipe({
		Rx.start(function()
			return WorldGenerationServiceClient:getState()
		end),
		Rx.map(function(worldState: any)
			return self:_resolveWorldLayoutSnapshot(worldState)
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
				local sampledBiome = self:_resolveCurrentWorldBiome()
				if sampledBiome ~= self.state.targetBiome then
					self:SetBiome(sampledBiome)
				end
			end
		end))

	self.reactiveStreamsMaid:GiveTask(
		Rx.timer(self.catalog.settings.biomeSampleIntervalSeconds, self.catalog.settings.biomeSampleIntervalSeconds)
			:Subscribe(function()
				if not self.initialized then
					return
				end

				local sampledBiome = self:_resolveCurrentWorldBiome()
				if sampledBiome ~= self.state.targetBiome then
					self:SetBiome(sampledBiome)
				end
			end)
	)

	local chunkSnapshotsChanged = (WorldGenerationServiceClient :: any).chunkSnapshotsChanged
	if chunkSnapshotsChanged ~= nil then
		self.reactiveStreamsMaid:GiveTask(chunkSnapshotsChanged:Connect(function()
			if not self.initialized then
				return
			end

			local sampledBiome = self:_resolveCurrentWorldBiome()
			if sampledBiome ~= self.state.targetBiome then
				self:SetBiome(sampledBiome)
			end
		end))
	end
end

function Parallax._resolveWorldFolder(_self: Parallax): Folder?
	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if worldFolder ~= nil and worldFolder:IsA("Folder") then
		return worldFolder
	end
	return nil
end

function Parallax._resolveRootParent(self: Parallax): Instance
	local worldFolder = self:_resolveWorldFolder()
	if worldFolder ~= nil then
		return worldFolder
	end
	return WorkspaceFolders.getOrCreateFolderInGame(ROOT_PARENT_FALLBACK_NAME)
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
	ParallaxThunks.clearSurfaceState()
end

function Parallax._destroyAllBiomeRuntimes(self: Parallax)
	table.clear(self.activeBiomeRuntimes)
	if self.rootFolder ~= nil and self.rootFolder.Parent ~= nil and #self.rootFolder:GetChildren() <= 0 then
		self.rootFolder:Destroy()
		self.rootFolder = nil
	end
end

function Parallax._ensureRootFolder(self: Parallax)
	local parent = self:_resolveRootParent()
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
	anchorPart.Size = Vector3.new(self.catalog.settings.segmentThickness, 1, 1)
	anchorPart.Parent = rootFolder

	local root = ReactRoblox.createRoot(anchorPart)
	root:render(e(ParallaxScreen))

	local runtime: SurfaceRuntime = {
		anchorPart = anchorPart,
		reactRoot = root,
	}
	self.surfaceRuntime = runtime
	return runtime
end

function Parallax._refreshWorldAttributes(self: Parallax)
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

function Parallax._resolveGameplayPlaneReferenceDistance(self: Parallax, cameraPositionX: number): number
	local gameplayPlaneX = self.worldOrigin.X + self.basePlaneX
	local gameplayPlaneDistance = math.max(math.abs(cameraPositionX - gameplayPlaneX), 1)

	if self.referenceGameplayPlaneDistanceX == nil then
		self.referenceGameplayPlaneDistanceX = gameplayPlaneDistance
	else
		self.referenceGameplayPlaneDistanceX = math.min(self.referenceGameplayPlaneDistanceX, gameplayPlaneDistance)
	end

	return self.referenceGameplayPlaneDistanceX
end

function Parallax._resolveDisplayedBiomeName(self: Parallax): string
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

function Parallax._resolveSelectedVariantName(self: Parallax, biomeDefinition: BiomeDefinition): string
	local selectedVariantName = self.selectedBiomeVariantNames[biomeDefinition.name]
	if selectedVariantName ~= nil and biomeDefinition.variants[selectedVariantName] ~= nil then
		return selectedVariantName
	end

	local nextVariantName = ParallaxServiceUtils.resolveVariantName(biomeDefinition, biomeDefinition.defaultVariantName)
	self.selectedBiomeVariantNames[biomeDefinition.name] = nextVariantName
	return nextVariantName
end

function Parallax._publishState(self: Parallax)
	if self.state.targetBiome ~= "" then
		self.state.currentBiome = self:_resolveDisplayedBiomeName()
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
	local definition = ParallaxServiceUtils.resolveBiomeDefinition(self.catalog, biomeName)
	local variantName = self:_resolveSelectedVariantName(definition)
	local variantDefinition = ParallaxServiceUtils.resolveVariantDefinition(self.catalog, definition.name, variantName)
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
	local biomeName = ParallaxServiceUtils.resolveBiomeName(self.catalog, biomeNameRaw)
	if self.preloadedBiomes[biomeName] then
		return self.preloadBiomePromises[biomeName]
	end
	self.preloadedBiomes[biomeName] = true

	local assetIds = ParallaxServiceUtils.collectAssetIds(self.catalog, { biomeName })
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

	local assetIds = ParallaxServiceUtils.collectAssetIds(self.catalog, nil)
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

function Parallax._resolveCurrentWorldBiome(self: Parallax): string
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

function Parallax._syncBiomeFromWorldSampleNow(self: Parallax): string
	local sampledBiome = self:_resolveCurrentWorldBiome()
	self.state.currentBiome = sampledBiome
	self.state.targetBiome = sampledBiome
	self.stateValue.Value = cloneState(self.state)
	return sampledBiome
end

function Parallax._resolveLayerMetric(
	self: Parallax,
	biomeRuntime: BiomeRuntime,
	layerRuntime: LayerRuntime,
	cameraPosition: Vector3,
	_now: number
): LayerMetric?
	local definition = layerRuntime.definition
	local layoutSnapshot = self.layoutStateValue.Value
	if layoutSnapshot == nil then
		layoutSnapshot = self:_resolveCurrentLayoutSnapshot()
		self.layoutStateValue.Value = layoutSnapshot
	end

	local planeX = self.worldOrigin.X + self.basePlaneX - definition.planeDepthBlocks * layoutSnapshot.tileDepth
	local gameplayReferenceDistance = self:_resolveGameplayPlaneReferenceDistance(cameraPosition.X)
	local coverageReferenceDistance = gameplayReferenceDistance
		+ math.abs((self.worldOrigin.X + self.basePlaneX) - planeX)
	local visibleWidth, visibleHeight = computeVisibleExtentsAtDistance(
		layoutSnapshot.fieldOfView,
		layoutSnapshot.viewportSize,
		coverageReferenceDistance
	)
	local sizeReferenceWidth = select(
		1,
		computeVisibleExtentsAtDistance(
			layoutSnapshot.fieldOfView,
			layoutSnapshot.viewportSize,
			gameplayReferenceDistance
		)
	)
	local planeSizing: PlaneSizing = ParallaxServiceUtils.resolveDeterministicPlaneSizing(
		visibleWidth,
		sizeReferenceWidth,
		layoutSnapshot.horizontalVisionStuds,
		definition.imageAspectRatio,
		definition.heightScale,
		definition.segmentWidthScale,
		definition.textureStudsPerTileU
	)
	local textureRepeatHeight = planeSizing.textureRepeatHeight
	local visibleBottomY = cameraPosition.Y - visibleHeight * 0.5
	local horizonY = self.worldOrigin.Y
	local verticalCameraDelta = cameraPosition.Y - horizonY
	local horizonCenterY = horizonY
		+ visibleHeight * definition.baseYOffset
		+ definition.verticalOffsetStuds
		+ verticalCameraDelta * definition.verticalParallax

	local minimumViewHeight = visibleHeight * SURFACE_LAYER_MIN_VIEW_HEIGHT_FACTOR
	local maximumViewHeight = visibleHeight * SURFACE_LAYER_MAX_VIEW_HEIGHT_FACTOR
	textureRepeatHeight = math.clamp(textureRepeatHeight, minimumViewHeight, maximumViewHeight)
	local textureRepeatWidth = computeTextureRepeatWidthFromHeight(definition, textureRepeatHeight)
	local planeWidth = math.max(planeSizing.planeWidth, textureRepeatWidth)
	local planeHeight = textureRepeatHeight
	local bottomBleed = math.max(visibleHeight * definition.bottomOverscan, MIN_PLANE_VERTICAL_COVERAGE_BLEED_STUDS)
	local highestHiddenBottomCenterY = visibleBottomY - bottomBleed + planeHeight * 0.5
	local centerY = math.min(horizonCenterY, highestHiddenBottomCenterY)
	local transparency = blendToLayerTransparency(definition.transparency, biomeRuntime.alpha)
	if transparency >= 0.999 then
		return nil
	end

	return {
		id = resolveLayerRenderId(biomeRuntime, layerRuntime),
		image = definition.image,
		tint = definition.tint,
		transparency = transparency,
		centerY = centerY,
		centerZ = cameraPosition.Z,
		width = planeWidth,
		height = planeHeight,
		textureRepeatWidth = textureRepeatWidth,
		textureRepeatHeight = textureRepeatHeight,
		textureOffsetU = Scrolling.computeHorizontalOffsetStuds(
			cameraPosition.Z,
			definition.depth,
			definition.scrollSpeed,
			textureRepeatWidth,
			_now
		),
		textureOffsetV = Scrolling.computeVerticalOffsetStuds(textureRepeatHeight),
		planeDepthBlocks = definition.planeDepthBlocks,
		zIndex = 1000 - layerRuntime.layerIndex,
	}
end

function Parallax._collectLayerMetrics(self: Parallax, cameraPosition: Vector3, now: number): { LayerMetric }
	local metrics: { LayerMetric } = {}
	for _, biomeRuntime in self.activeBiomeRuntimes do
		for _, layerRuntime in biomeRuntime.layers do
			local metric = self:_resolveLayerMetric(biomeRuntime, layerRuntime, cameraPosition, now)
			if metric ~= nil then
				table.insert(metrics, metric)
			end
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

function Parallax._publishSurfaceState(self: Parallax, metrics: { LayerMetric }, cameraPosition: Vector3)
	local surfaceRuntime = self:_ensureSurfaceRuntime()
	if surfaceRuntime == nil or #metrics <= 0 then
		ParallaxThunks.clearSurfaceState()
		return
	end

	local minY = math.huge
	local maxY = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	local minPlaneDepthBlocks = math.huge
	for _, metric in metrics do
		minY = math.min(minY, metric.centerY - metric.height * 0.5)
		maxY = math.max(maxY, metric.centerY + metric.height * 0.5)
		minZ = math.min(minZ, metric.centerZ - metric.width * 0.5)
		maxZ = math.max(maxZ, metric.centerZ + metric.width * 0.5)
		minPlaneDepthBlocks = math.min(minPlaneDepthBlocks, metric.planeDepthBlocks)
	end
	local rawAnchorHeightStuds = math.max(maxY - minY, 1)
	local rawAnchorWidthStuds = math.max(maxZ - minZ, 1)
	local verticalOverscan =
		math.max(rawAnchorHeightStuds * SURFACE_ANCHOR_VERTICAL_OVERSCAN_FACTOR, MIN_SURFACE_ANCHOR_OVERSCAN_STUDS)
	local horizontalOverscan =
		math.max(rawAnchorWidthStuds * SURFACE_ANCHOR_HORIZONTAL_OVERSCAN_FACTOR, MIN_SURFACE_ANCHOR_OVERSCAN_STUDS)
	minY -= verticalOverscan
	maxY += verticalOverscan
	minZ -= horizontalOverscan
	maxZ += horizontalOverscan

	local anchorHeightStuds = math.max(maxY - minY, 1)
	local anchorWidthStuds = math.max(maxZ - minZ, 1)
	local anchorCenterY = (minY + maxY) * 0.5
	local anchorCenterZ = (minZ + maxZ) * 0.5
	local anchorPlaneX = self.worldOrigin.X
		+ self.basePlaneX
		- minPlaneDepthBlocks * self.layoutStateValue.Value.tileDepth
	local pixelsPerStud = resolveSurfacePixelsPerStud(anchorWidthStuds, anchorHeightStuds)
	local canvasWidth = toCanvasPixels(anchorWidthStuds, pixelsPerStud)
	local canvasHeight = toCanvasPixels(anchorHeightStuds, pixelsPerStud)

	surfaceRuntime.anchorPart.Size =
		Vector3.new(self.catalog.settings.segmentThickness, anchorHeightStuds, anchorWidthStuds)
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
		local tileWidth = math.max(metric.textureRepeatWidth * pixelsPerStud * SURFACE_TILE_SCALE, 1)
		local tileHeight = math.max(metric.textureRepeatHeight * pixelsPerStud * SURFACE_TILE_SCALE, 1)
		local imageOffsetX = Scrolling.computeOffsetPixels(metric.textureOffsetU, metric.textureRepeatWidth, tileWidth)
		local imageOffsetY =
			Scrolling.computeOffsetPixels(metric.textureOffsetV, metric.textureRepeatHeight, tileHeight)
		local extraWidth = tileWidth * SURFACE_EXTRA_TILE_COUNT
		local extraHeight = tileHeight * SURFACE_EXTRA_TILE_COUNT

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

	ParallaxThunks.publishSurfaceState({
		visible = true,
		adornee = surfaceRuntime.anchorPart,
		face = surfaceFace,
		brightness = SURFACE_BRIGHTNESS,
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
	self:_stepTransition(now)

	local camera = getCamera()
	if camera == nil then
		ParallaxThunks.clearSurfaceState()
		return
	end

	local cameraPosition = camera.CFrame.Position
	local metrics = self:_collectLayerMetrics(cameraPosition, now)
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

function Parallax.ForceRefresh(self: Parallax)
	self.catalog = ParallaxServiceUtils.normalizeCatalog(ParallaxBackgrounds)
	self.preloadedBiomes = {}
	self.preloadBiomePromises = {}
	self.selectedBiomeVariantNames = {}
	self.didPreloadAllAssets = false
	self.preloadAllAssetsPromise = nil
	self.referenceGameplayPlaneDistanceX = nil
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
	self.initialized = false
end

Parallax.init = Parallax.Init
Parallax.setBiome = Parallax.SetBiome
Parallax.forceRefresh = Parallax.ForceRefresh
Parallax.observeState = Parallax.ObserveState
Parallax.getStateChangedSignal = Parallax.GetStateChangedSignal
Parallax.getState = Parallax.GetState
Parallax.getCurrentBiome = Parallax.GetCurrentBiome
Parallax.destroy = Parallax.Destroy

export type Parallax = typeof(setmetatable(
	{} :: {
		localPlayer: Player,
		maid: MaidClass?,
		reactiveStreamsMaid: MaidClass?,
		catalog: Catalog,
		state: ServiceState,
		stateValue: ValueObjectClass<ServiceState>?,
		stateObservable: ObservableObject?,
		stateChangedSignal: RxSignalObject?,
		layoutStateValue: ValueObjectClass<LayoutSnapshot>?,
		activeBiomeRuntimes: { [string]: BiomeRuntime },
		preloadedBiomes: { [string]: boolean },
		preloadBiomePromises: { [string]: any },
		selectedBiomeVariantNames: { [string]: string },
		didPreloadAllAssets: boolean,
		preloadAllAssetsPromise: any?,
		referenceGameplayPlaneDistanceX: number?,
		transitionActive: boolean,
		transitionStartedAt: number,
		rootFolder: Folder?,
		surfaceRuntime: SurfaceRuntime?,
		worldOrigin: Vector3,
		basePlaneX: number,
		renderStepName: string?,
		initialized: boolean,
	},
	{} :: typeof({ __index = Parallax })
))

return Parallax
