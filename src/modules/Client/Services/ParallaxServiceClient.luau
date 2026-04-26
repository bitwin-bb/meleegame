--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

local ContentProviderUtils = require("ContentProviderUtils")
local Maid = require("Maid")
local Rx = require("Rx")
local RxSignal = require("RxSignal")
local ValueObject = require("ValueObject")

local ParallaxBackgrounds = require(script:FindFirstAncestor("game").Shared.Modules.Items.ParallaxBackgrounds)
local ParallaxServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.ParallaxServiceUtils)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)

type Catalog = ParallaxServiceUtils.Catalog
type BiomeDefinition = ParallaxServiceUtils.BiomeDefinition
type BiomeVariantDefinition = ParallaxServiceUtils.BiomeVariantDefinition
type LayerDefinition = ParallaxServiceUtils.LayerDefinition
type PlaneSizing = ParallaxServiceUtils.PlaneSizing
type ServiceState = ParallaxServiceUtils.ServiceState

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

type PlaneRuntime = {
	part: Part,
	textures: { Texture },
	lastWidth: number,
	lastHeight: number,
	lastRepeatWidth: number,
}

type LayerRuntime = {
	definition: LayerDefinition,
	folder: Folder,
	plane: PlaneRuntime,
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
local BASE_TEXTURE_OFFSET_STUDS_U = 0.3
local BASE_TEXTURE_OFFSET_STUDS_V = 0.3
local PARALLAX_TEXTURE_MOTION_SCALE = 0.65
local MIN_PLANE_VERTICAL_COVERAGE_BLEED_FACTOR = 0.14
local MIN_PLANE_VERTICAL_COVERAGE_BLEED_STUDS = 4
local DEFAULT_CAMERA_FIELD_OF_VIEW = 70
local DEFAULT_CAMERA_VIEWPORT = Vector2.new(1920, 1080)

local ParallaxServiceClient = {}

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

local function computeAlignedCenterY(
	verticalAlign: ParallaxServiceUtils.VerticalAlign,
	cameraY: number,
	visibleHeight: number,
	planeHeight: number
): number
	if verticalAlign == "Top" then
		return cameraY + visibleHeight * 0.5 - planeHeight * 0.5
	end
	if verticalAlign == "Center" then
		return cameraY
	end
	return cameraY - visibleHeight * 0.5 + planeHeight * 0.5
end

local function blendToLayerTransparency(baseTransparency: number, biomeAlpha: number): number
	local clampedBaseTransparency = math.clamp(baseTransparency, 0, 1)
	local clampedBiomeAlpha = math.clamp(biomeAlpha, 0, 1)
	return 1 - (1 - clampedBaseTransparency) * clampedBiomeAlpha
end

local function wrapTextureOffsetStuds(offsetStudsRaw: number, repeatWidthRaw: number): number
	local repeatWidth = math.max(repeatWidthRaw, 0.001)
	local wrapped = offsetStudsRaw % repeatWidth
	if wrapped < 0 then
		wrapped += repeatWidth
	end
	return wrapped
end

local function cloneState(state: ServiceState): ServiceState
	return ParallaxServiceUtils.cloneState(state)
end

local function createTexture(part: Part, face: Enum.NormalId, definition: LayerDefinition): Texture
	local texture = Instance.new("Texture")
	texture.Name = face.Name
	texture.Face = face
	texture.Texture = definition.image
	texture.Color3 = definition.tint
	texture.Transparency = 1
	texture.OffsetStudsU = BASE_TEXTURE_OFFSET_STUDS_U
	texture.OffsetStudsV = BASE_TEXTURE_OFFSET_STUDS_V
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
end

function ParallaxServiceClient._resolveWorldLayoutSnapshot(
	self: ParallaxServiceClient,
	stateRaw: any?
): WorldLayoutSnapshot
	local fallbackState = ((WorldGenerationServiceClient :: any).state :: { [string]: any }?) or {}
	local state = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else fallbackState
	local tileDepth = if typeof(state.tileDepth) == "number" then math.max(state.tileDepth, 0.5) else 2
	local chunkSize = if typeof(state.chunkSize) == "number" then math.max(1, math.floor(state.chunkSize)) else 32
	local tileSize = if typeof(state.tileSize) == "number" then math.max(state.tileSize, 0.25) else 2
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

function ParallaxServiceClient._resolveCurrentLayoutSnapshot(self: ParallaxServiceClient): LayoutSnapshot
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

function ParallaxServiceClient._observeCameraSnapshot(self: ParallaxServiceClient): ObservableObject
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

function ParallaxServiceClient._observeWorldLayoutSnapshot(self: ParallaxServiceClient): ObservableObject
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

function ParallaxServiceClient._bindReactiveStreams(self: ParallaxServiceClient)
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
	self.stateValue.Value = cloneState(self.state)
end

function ParallaxServiceClient._createPlane(self: ParallaxServiceClient, layerRuntime: LayerRuntime): PlaneRuntime
	local definition = layerRuntime.definition

	local part = Instance.new("Part")
	part.Name = `{definition.id}_Plane`
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
		lastRepeatWidth = 0,
	}
end

function ParallaxServiceClient._createLayerRuntime(
	self: ParallaxServiceClient,
	biomeRuntime: BiomeRuntime,
	definition: LayerDefinition
): LayerRuntime
	local folder = createFolder(biomeRuntime.folder, definition.id)
	local runtime: LayerRuntime = {
		definition = definition,
		folder = folder,
		plane = nil :: any,
	}
	runtime.plane = self:_createPlane(runtime)
	return runtime
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

function ParallaxServiceClient._preloadBiomeAssets(self: ParallaxServiceClient, biomeNameRaw: any)
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

function ParallaxServiceClient._preloadAllAssets(self: ParallaxServiceClient)
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
	self.stateValue.Value = cloneState(self.state)
	return sampledBiome
end

function ParallaxServiceClient._updateLayerRuntime(
	self: ParallaxServiceClient,
	layerRuntime: LayerRuntime,
	biomeAlpha: number,
	cameraPosition: Vector3,
	now: number
)
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
	local minimumPlaneHeight = planeSizing.textureRepeatHeight
	local centerShift = definition.verticalOffsetStuds
		- (cameraPosition.Y - self.worldOrigin.Y) * definition.verticalDepth
	local candidateCenterY = computeAlignedCenterY(
		definition.verticalAlign,
		cameraPosition.Y,
		visibleHeight,
		minimumPlaneHeight
	) + centerShift
	local visibleTopY = cameraPosition.Y + visibleHeight * 0.5
	local visibleBottomY = cameraPosition.Y - visibleHeight * 0.5
	local requiredHalfHeight = math.max(candidateCenterY - visibleBottomY, visibleTopY - candidateCenterY)
		+ math.max(visibleHeight * MIN_PLANE_VERTICAL_COVERAGE_BLEED_FACTOR, MIN_PLANE_VERTICAL_COVERAGE_BLEED_STUDS)
	local planeHeight = math.max(minimumPlaneHeight, requiredHalfHeight * 2)
	planeSizing = ParallaxServiceUtils.resolveDeterministicPlaneSizing(
		visibleWidth,
		sizeReferenceWidth,
		layoutSnapshot.horizontalVisionStuds,
		definition.imageAspectRatio,
		definition.heightScale,
		definition.segmentWidthScale,
		definition.textureStudsPerTileU,
		planeHeight
	)
	local textureRepeatWidth = planeSizing.textureRepeatWidth
	local textureRepeatHeight = planeSizing.textureRepeatHeight
	local centerY = computeAlignedCenterY(definition.verticalAlign, cameraPosition.Y, visibleHeight, planeHeight)
		+ centerShift
	local targetTextureTransparency = blendToLayerTransparency(definition.transparency, biomeAlpha)
	local textureOffsetU = wrapTextureOffsetStuds(
		BASE_TEXTURE_OFFSET_STUDS_U
			+ cameraPosition.Z * definition.depth * PARALLAX_TEXTURE_MOTION_SCALE
			- now * definition.scrollSpeed * PARALLAX_TEXTURE_MOTION_SCALE,
		textureRepeatWidth
	)
	local planeRuntime = layerRuntime.plane

	planeRuntime.part.Size = Vector3.new(self.catalog.settings.segmentThickness, planeHeight, planeSizing.planeWidth)
	planeRuntime.part.CFrame = CFrame.new(planeX, centerY, cameraPosition.Z)
	for _, texture in planeRuntime.textures do
		texture.Texture = definition.image
		texture.Color3 = definition.tint
		texture.Transparency = targetTextureTransparency
		texture.StudsPerTileU = textureRepeatWidth
		texture.StudsPerTileV = textureRepeatHeight
		texture.OffsetStudsU = textureOffsetU
		texture.OffsetStudsV = BASE_TEXTURE_OFFSET_STUDS_V
	end
	planeRuntime.lastWidth = planeSizing.planeWidth
	planeRuntime.lastHeight = planeHeight
	planeRuntime.lastRepeatWidth = textureRepeatWidth
end

function ParallaxServiceClient._updateBiomeRuntime(
	self: ParallaxServiceClient,
	biomeRuntime: BiomeRuntime,
	cameraPosition: Vector3,
	now: number
)
	for _, layerRuntime in biomeRuntime.layers do
		self:_updateLayerRuntime(layerRuntime, biomeRuntime.alpha, cameraPosition, now)
	end
end

function ParallaxServiceClient._render(self: ParallaxServiceClient)
	if not self.initialized then
		return
	end

	self:_ensureRootFolder()
	self:_refreshWorldAttributes()

	local now = os.clock()
	self:_stepTransition(now)

	local camera = getCamera()
	if camera == nil then
		return
	end

	local cameraPosition = resolveCameraPosition()
	for _, biomeRuntime in self.activeBiomeRuntimes do
		self:_updateBiomeRuntime(biomeRuntime, cameraPosition, now)
	end
end

function ParallaxServiceClient.Init(self: ParallaxServiceClient, _container: Instance?)
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
	RunService:BindToRenderStep(self.renderStepName, Enum.RenderPriority.Camera.Value + 5, function()
		self:_render()
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

function ParallaxServiceClient.ObserveState(self: ParallaxServiceClient): ObservableObject
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

function ParallaxServiceClient.GetStateChangedSignal(self: ParallaxServiceClient): RxSignalObject
	self:_initializeCoreState()
	return self.stateChangedSignal
end

function ParallaxServiceClient.GetState(self: ParallaxServiceClient): ServiceState
	self:_initializeCoreState()
	return cloneState(self.state)
end

function ParallaxServiceClient.GetCurrentBiome(self: ParallaxServiceClient): string
	return self:GetState().currentBiome
end

function ParallaxServiceClient.Destroy(self: ParallaxServiceClient)
	if self.preloadBiomePromises ~= nil then
		table.clear(self.preloadBiomePromises)
	end
	if self.preloadedBiomes ~= nil then
		table.clear(self.preloadedBiomes)
	end
	if self.selectedBiomeVariantNames ~= nil then
		table.clear(self.selectedBiomeVariantNames)
	end
	if self.activeBiomeRuntimes ~= nil then
		table.clear(self.activeBiomeRuntimes)
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

ParallaxServiceClient.init = ParallaxServiceClient.Init
ParallaxServiceClient.setBiome = ParallaxServiceClient.SetBiome
ParallaxServiceClient.forceRefresh = ParallaxServiceClient.ForceRefresh
ParallaxServiceClient.observeState = ParallaxServiceClient.ObserveState
ParallaxServiceClient.getStateChangedSignal = ParallaxServiceClient.GetStateChangedSignal
ParallaxServiceClient.getState = ParallaxServiceClient.GetState
ParallaxServiceClient.getCurrentBiome = ParallaxServiceClient.GetCurrentBiome
ParallaxServiceClient.destroy = ParallaxServiceClient.Destroy

type ParallaxServiceClient = typeof(ParallaxServiceClient) & {
	localPlayer: Player,
	maid: MaidClass?,
	reactiveStreamsMaid: MaidClass?,
	catalog: Catalog,
	state: ServiceState,
	stateValue: ValueObjectClass<ServiceState>,
	stateObservable: ObservableObject?,
	stateChangedSignal: RxSignalObject,
	layoutStateValue: ValueObjectClass<LayoutSnapshot>,
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
	worldOrigin: Vector3,
	basePlaneX: number,
	renderStepName: string?,
	initialized: boolean,
}

return ParallaxServiceClient :: ParallaxServiceClient
