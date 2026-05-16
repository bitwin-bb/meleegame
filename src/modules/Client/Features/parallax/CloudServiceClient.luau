--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(packageRoot)

local ContentProviderUtils = loader("ContentProviderUtils")
local Maid = loader("Maid")
local Rx = loader("Rx")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local Cloud = require(script.Parent.classes.Cloud)
local CloudScreen = require(script.Parent.ui.screens.CloudScreen)
local CloudServiceUtils = require(script.Parent.CloudServiceUtils)
local Clouds = require(script.Parent.modules.Clouds)
local ParallaxBackgrounds = require(script.Parent.modules.ParallaxBackgrounds)
local ParallaxServiceUtils = require(script.Parent.ParallaxServiceUtils)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)

type CloudAssetDefinition = CloudServiceUtils.CloudAssetDefinition
type CloudSurfaceState = CloudServiceUtils.CloudSurfaceState
type CloudView = CloudServiceUtils.CloudView
type Catalog = ParallaxServiceUtils.Catalog

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	GivePromise: (self: MaidClass, promise: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
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

type SurfaceRuntime = {
	anchorPart: Part,
	reactRoot: any,
}

type CloudSizing = {
	width: number,
	height: number,
}

local CloudServiceClient = {}
CloudServiceClient.ServiceName = "CloudServiceClient"

local WORLD_FOLDER_NAME = "WorldGeneration"
local ROOT_PARENT_FALLBACK_NAME = "ParallaxService"
local ROOT_FOLDER_NAME = "CloudDepth"
local ANCHOR_PART_NAME = "CloudAnchor"
local SURFACE_BRIGHTNESS = 0.5
local SURFACE_PIXELS_PER_STUD = 8
local MAX_SURFACE_CANVAS_PIXELS = 20000
local MIN_SURFACE_CANVAS_PIXELS = 1
local DEFAULT_CAMERA_FIELD_OF_VIEW = 70
local DEFAULT_CAMERA_VIEWPORT = Vector2.new(1920, 1080)
local CLOUD_PLANE_DEPTH_BLOCKS = 40
local CLOUD_SURFACE_WIDTH_FACTOR = 2.65
local CLOUD_SURFACE_HEIGHT_FACTOR = 0.68
local CLOUD_HORIZON_CENTER_OFFSET_FACTOR = 0.78
local CLOUD_SPAWN_LEFT_MIN_FACTOR = 0.9
local CLOUD_SPAWN_LEFT_MAX_FACTOR = 0.66
local CLOUD_OFFSCREEN_MARGIN_FACTOR = 0.35
local CLOUD_MIN_SCALE = 0.95
local CLOUD_MAX_SCALE = 1.9
local CLOUD_MIN_DEPTH_FACTOR = 0.06
local CLOUD_MAX_DEPTH_FACTOR = 0.36
local CLOUD_MIN_HEIGHT_FACTOR = 0.15
local CLOUD_MAX_HEIGHT_FACTOR = 0.3
local CLOUD_MIN_VERTICAL_ALPHA = 0.02
local CLOUD_MAX_VERTICAL_ALPHA = 0.34
local CLOUD_MIN_WIND_SPEED_STUDS_PER_SECOND = 2.5
local CLOUD_MAX_WIND_SPEED_STUDS_PER_SECOND = 6.5
local CLOUD_FADE_SECONDS = 0.9
local CLOUD_MIN_COUNT = 5
local CLOUD_MAX_COUNT = 10
local CLOUD_TARGET_VIEWPORT_PIXELS = 320

local e: typeof(React.createElement) = React.createElement

local catalog: Catalog = ParallaxServiceUtils.normalizeCatalog(ParallaxBackgrounds)
local assets: { CloudAssetDefinition } = CloudServiceUtils.normalizeAssetDefinitions(Clouds)
local random = Random.new()
local maid: MaidClass? = nil
local rootFolder: Folder? = nil
local surfaceRuntime: SurfaceRuntime? = nil
local activeClouds: { Cloud.Cloud } = {}
local pooledClouds: { Cloud.Cloud } = {}
local nextCloudId = 0
local referenceGameplayPlaneDistanceX: number? = nil
local worldOrigin = Vector3.zero
local basePlaneX = 0
local initialized = false

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

local function resolveWorldFolder(): Folder?
	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if worldFolder ~= nil and worldFolder:IsA("Folder") then
		return worldFolder
	end
	return nil
end

local function resolveRootParent(): Instance
	local worldFolder = resolveWorldFolder()
	if worldFolder ~= nil then
		return worldFolder
	end
	return WorkspaceFolders.getOrCreateFolderInGame(ROOT_PARENT_FALLBACK_NAME)
end

local function destroySurfaceRuntime()
	local current = surfaceRuntime
	if current == nil then
		return
	end
	current.reactRoot:unmount()
	if current.anchorPart.Parent ~= nil then
		current.anchorPart:Destroy()
	end
	surfaceRuntime = nil
	CloudServiceUtils.clearSurfaceState()
end

local function ensureRootFolder()
	local parent = resolveRootParent()
	if rootFolder ~= nil and rootFolder.Parent == parent then
		return
	end

	destroySurfaceRuntime()
	if rootFolder ~= nil and rootFolder.Parent ~= nil then
		rootFolder:Destroy()
	end
	rootFolder = createFolder(parent, ROOT_FOLDER_NAME)
end

local function ensureSurfaceRuntime(): SurfaceRuntime?
	ensureRootFolder()
	if rootFolder == nil then
		return nil
	end

	local current = surfaceRuntime
	if current ~= nil and current.anchorPart.Parent == rootFolder then
		return current
	end

	destroySurfaceRuntime()
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
	anchorPart.Size = Vector3.new(catalog.settings.segmentThickness, 1, 1)
	anchorPart.Parent = rootFolder

	local reactRoot = ReactRoblox.createRoot(anchorPart)
	reactRoot:render(e(CloudScreen))

	local runtime: SurfaceRuntime = {
		anchorPart = anchorPart,
		reactRoot = reactRoot,
	}
	surfaceRuntime = runtime
	return runtime
end

local function resolveWorldLayoutSnapshot(stateRaw: any?): WorldLayoutSnapshot
	local fallbackState = ((WorldGenerationServiceClient :: any).state :: { [string]: any }?) or {} :: { [string]: any }
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

local function resolveCurrentLayoutSnapshot(): LayoutSnapshot
	local cameraSnapshot = resolveCameraSnapshot(getCamera())
	local worldSnapshot = resolveWorldLayoutSnapshot(nil)
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

local function refreshWorldAttributes()
	local worldFolder = resolveWorldFolder()
	if worldFolder == nil then
		worldOrigin = Vector3.zero
		basePlaneX = 0
		referenceGameplayPlaneDistanceX = nil
		return
	end

	local originX = worldFolder:GetAttribute("WorldOriginX")
	local originY = worldFolder:GetAttribute("WorldOriginY")
	local originZ = worldFolder:GetAttribute("WorldOriginZ")
	local nextBasePlaneX = worldFolder:GetAttribute("BasePlaneX")

	local nextWorldOrigin = Vector3.new(
		if typeof(originX) == "number" then originX else 0,
		if typeof(originY) == "number" then originY else 0,
		if typeof(originZ) == "number" then originZ else 0
	)
	local resolvedBasePlaneX = if typeof(nextBasePlaneX) == "number" then nextBasePlaneX else 0

	if worldOrigin ~= nextWorldOrigin or basePlaneX ~= resolvedBasePlaneX then
		referenceGameplayPlaneDistanceX = nil
	end

	worldOrigin = nextWorldOrigin
	basePlaneX = resolvedBasePlaneX
end

local function resolveGameplayPlaneReferenceDistance(cameraPositionX: number): number
	local gameplayPlaneX = worldOrigin.X + basePlaneX
	local gameplayPlaneDistance = math.max(math.abs(cameraPositionX - gameplayPlaneX), 1)

	if referenceGameplayPlaneDistanceX == nil then
		referenceGameplayPlaneDistanceX = gameplayPlaneDistance
	else
		referenceGameplayPlaneDistanceX = math.min(referenceGameplayPlaneDistanceX :: number, gameplayPlaneDistance)
	end

	return referenceGameplayPlaneDistanceX :: number
end

local function resolveCloudSizing(visibleHeight: number, cloud: Cloud.Cloud): CloudSizing
	local scaleAlpha = math.clamp((cloud.scale - CLOUD_MIN_SCALE) / (CLOUD_MAX_SCALE - CLOUD_MIN_SCALE), 0, 1)
	local heightFactor = CLOUD_MIN_HEIGHT_FACTOR + (CLOUD_MAX_HEIGHT_FACTOR - CLOUD_MIN_HEIGHT_FACTOR) * scaleAlpha
	local height = math.max(visibleHeight * heightFactor, 1)
	local asset = cloud.asset
	local aspectRatio = if asset ~= nil then asset.imageAspectRatio else 2.75
	return {
		width = math.max(height * aspectRatio, 1),
		height = height,
	}
end

local function resolveTargetCloudCount(viewportSize: Vector2): number
	local target = math.floor(viewportSize.X / CLOUD_TARGET_VIEWPORT_PIXELS + 0.5)
	return math.clamp(target, CLOUD_MIN_COUNT, CLOUD_MAX_COUNT)
end

local function borrowCloud(): Cloud.Cloud
	local pooled = table.remove(pooledClouds)
	if pooled ~= nil then
		return pooled
	end
	return Cloud.new()
end

local function releaseCloud(cloud: Cloud.Cloud)
	table.insert(pooledClouds, cloud)
end

local function resolveRandomAsset(): CloudAssetDefinition?
	if #assets <= 0 then
		return nil
	end
	return assets[random:NextInteger(1, #assets)]
end

local function spawnCloud(cameraZ: number, visibleWidth: number)
	local asset = resolveRandomAsset()
	if asset == nil then
		return
	end

	nextCloudId += 1
	local cloud = borrowCloud()
	local spawnMinOffsetZ = -visibleWidth * CLOUD_SPAWN_LEFT_MIN_FACTOR
	local spawnMaxOffsetZ = -visibleWidth * CLOUD_SPAWN_LEFT_MAX_FACTOR
	local scale = random:NextNumber(CLOUD_MIN_SCALE, CLOUD_MAX_SCALE)
	cloud:reset({
		id = tostring(nextCloudId),
		asset = asset,
		scale = scale,
		baseOffsetZ = random:NextNumber(spawnMinOffsetZ, spawnMaxOffsetZ),
		verticalAlpha = random:NextNumber(CLOUD_MIN_VERTICAL_ALPHA, CLOUD_MAX_VERTICAL_ALPHA),
		spawnCameraZ = cameraZ,
		windSpeed = random:NextNumber(CLOUD_MIN_WIND_SPEED_STUDS_PER_SECOND, CLOUD_MAX_WIND_SPEED_STUDS_PER_SECOND),
		fadeSeconds = CLOUD_FADE_SECONDS,
		minScale = CLOUD_MIN_SCALE,
		maxScale = CLOUD_MAX_SCALE,
		minDepthFactor = CLOUD_MIN_DEPTH_FACTOR,
		maxDepthFactor = CLOUD_MAX_DEPTH_FACTOR,
	}, os.clock())
	table.insert(activeClouds, cloud)
end

local function removeInactiveClouds()
	for index = #activeClouds, 1, -1 do
		local cloud = activeClouds[index]
		if not cloud:isActive() then
			table.remove(activeClouds, index)
			releaseCloud(cloud)
		end
	end
end

local function updateCloudPool(targetCount: number, cameraZ: number, visibleWidth: number)
	local liveCount = 0
	for _, cloud in activeClouds do
		if not cloud:isRetiring() then
			liveCount += 1
		end
	end

	while liveCount < targetCount do
		spawnCloud(cameraZ, visibleWidth)
		liveCount += 1
	end
end

local function publishServiceState()
	CloudServiceUtils.setServiceState({
		initialized = initialized,
		activeCloudCount = #activeClouds,
		pooledCloudCount = #pooledClouds,
	})
end

local function preloadAssets()
	local activeMaid = maid
	if activeMaid == nil then
		return
	end

	local assetIds = CloudServiceUtils.collectAssetIds(assets)
	if #assetIds <= 0 then
		return
	end

	activeMaid:GivePromise(ContentProviderUtils.promisePreload(assetIds):Catch(function()
		return false
	end))
end

local function render()
	if not initialized then
		return
	end

	refreshWorldAttributes()
	local currentSurfaceRuntime = ensureSurfaceRuntime()
	local camera = getCamera()
	if currentSurfaceRuntime == nil or camera == nil or #assets <= 0 then
		CloudServiceUtils.clearSurfaceState()
		return
	end

	local layoutSnapshot = resolveCurrentLayoutSnapshot()
	local cameraPosition = camera.CFrame.Position
	local planeX = worldOrigin.X + basePlaneX - CLOUD_PLANE_DEPTH_BLOCKS * layoutSnapshot.tileDepth
	local gameplayReferenceDistance = resolveGameplayPlaneReferenceDistance(cameraPosition.X)
	local coverageDistance = gameplayReferenceDistance + math.abs((worldOrigin.X + basePlaneX) - planeX)
	local visibleWidth, visibleHeight =
		computeVisibleExtentsAtDistance(layoutSnapshot.fieldOfView, layoutSnapshot.viewportSize, coverageDistance)
	local surfaceWidth = math.max(visibleWidth * CLOUD_SURFACE_WIDTH_FACTOR, 1)
	local surfaceHeight = math.max(visibleHeight * CLOUD_SURFACE_HEIGHT_FACTOR, 1)
	local surfaceHalfWidth = surfaceWidth * 0.5
	local retireHalfWidth = visibleWidth * 0.5
	local offscreenMargin = visibleWidth * CLOUD_OFFSCREEN_MARGIN_FACTOR

	updateCloudPool(resolveTargetCloudCount(layoutSnapshot.viewportSize), cameraPosition.Z, visibleWidth)

	local now = os.clock()
	for _, cloud in activeClouds do
		local sizing = resolveCloudSizing(visibleHeight, cloud)
		cloud:step(now, cameraPosition.Z, sizing.width, retireHalfWidth, offscreenMargin)
	end
	removeInactiveClouds()

	local anchorCenterY = worldOrigin.Y + visibleHeight * CLOUD_HORIZON_CENTER_OFFSET_FACTOR
	local anchorCenterZ = cameraPosition.Z
	local pixelsPerStud = resolveSurfacePixelsPerStud(surfaceWidth, surfaceHeight)
	local canvasWidth = toCanvasPixels(surfaceWidth, pixelsPerStud)
	local canvasHeight = toCanvasPixels(surfaceHeight, pixelsPerStud)
	currentSurfaceRuntime.anchorPart.Size = Vector3.new(catalog.settings.segmentThickness, surfaceHeight, surfaceWidth)
	currentSurfaceRuntime.anchorPart.CFrame = CFrame.new(planeX, anchorCenterY, anchorCenterZ)
	local surfaceFace = if cameraPosition.X >= planeX then Enum.NormalId.Right else Enum.NormalId.Left

	local cloudViews: { CloudView } = {}
	for _, cloud in activeClouds do
		local asset = cloud.asset
		if asset == nil or cloud.alpha <= 0.001 then
			continue
		end

		local sizing = resolveCloudSizing(visibleHeight, cloud)
		local cloudCenterY = sizing.height * 0.5 + cloud.verticalAlpha * math.max(surfaceHeight - sizing.height, 0)
		table.insert(cloudViews, {
			id = cloud.id,
			image = asset.image,
			imageColor = asset.tint,
			imageTransparency = 1 - math.clamp(cloud.alpha, 0, 1),
			position = UDim2.fromOffset(
				(surfaceHalfWidth + cloud.currentOffsetZ) * pixelsPerStud,
				cloudCenterY * pixelsPerStud
			),
			size = UDim2.fromOffset(sizing.width * pixelsPerStud, sizing.height * pixelsPerStud),
			zIndex = 1000 + math.floor(cloud.scale * 1000),
		})
	end
	table.sort(cloudViews, function(left: CloudView, right: CloudView): boolean
		if left.zIndex == right.zIndex then
			return left.id < right.id
		end
		return left.zIndex < right.zIndex
	end)

	CloudServiceUtils.setSurfaceState({
		visible = true,
		adornee = currentSurfaceRuntime.anchorPart,
		face = surfaceFace,
		brightness = SURFACE_BRIGHTNESS,
		canvasSize = Vector2.new(canvasWidth, canvasHeight),
		clouds = cloudViews,
	} :: CloudSurfaceState)
	publishServiceState()
end

local function bindReactiveStreams()
	local activeMaid = maid
	if activeMaid == nil then
		return
	end

	activeMaid:GiveTask(Rx.fromSignal(RunService.RenderStepped):Subscribe(function(_deltaTime: number)
		render()
	end))

	activeMaid:GiveTask(Rx.fromSignal(Workspace:GetPropertyChangedSignal("CurrentCamera")):Subscribe(function()
		referenceGameplayPlaneDistanceX = nil
	end))
end

function CloudServiceClient.Init(_self: any, _container: Instance?)
	if maid == nil then
		local activeMaid = Maid.new()
		maid = activeMaid
		activeMaid:GiveTask(function()
			destroySurfaceRuntime()
			if rootFolder ~= nil and rootFolder.Parent ~= nil then
				rootFolder:Destroy()
			end
			rootFolder = nil
			for _, cloud in activeClouds do
				cloud:destroy()
			end
			for _, cloud in pooledClouds do
				cloud:destroy()
			end
			table.clear(activeClouds)
			table.clear(pooledClouds)
			initialized = false
			CloudServiceUtils.clearServiceState()
		end)
	end

	if initialized then
		return
	end

	ensureRootFolder()
	ensureSurfaceRuntime()
	refreshWorldAttributes()
	preloadAssets()
	initialized = true
	publishServiceState()
	bindReactiveStreams()
end

function CloudServiceClient.ForceRefresh(_self: any)
	for _, cloud in activeClouds do
		cloud:beginFadeOut(os.clock())
	end
end

function CloudServiceClient.GetState(_self: any): CloudServiceUtils.ServiceState
	return CloudServiceUtils.getServiceState()
end

function CloudServiceClient.Destroy(_self: any)
	if maid == nil then
		return
	end
	maid:DoCleaning()
	maid = nil
end

CloudServiceClient.init = CloudServiceClient.Init
CloudServiceClient.forceRefresh = CloudServiceClient.ForceRefresh
CloudServiceClient.getState = CloudServiceClient.GetState
CloudServiceClient.destroy = CloudServiceClient.Destroy

return CloudServiceClient
