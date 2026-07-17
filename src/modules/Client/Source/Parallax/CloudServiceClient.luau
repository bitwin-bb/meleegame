local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ServiceBag = require("ServiceBag")
local ContentProviderUtils = require("ContentProviderUtils")
local Maid = require("Maid")
local RandomUtils = require("RandomUtils")
local Rx: any = require("Rx")

local React: any = require(ReplicatedStorage.Packages.React)
local ReactRoblox: any = require(ReplicatedStorage.Packages.ReactRoblox)

local Cloud = require("Cloud")
local CloudConstants = require("CloudConstants")
local CloudServiceUtils = require("CloudServiceUtils")
local Clouds = require("Clouds")
local ParallaxRoot = require("ParallaxRoot")
local ParallaxServiceUtils = require("ParallaxServiceUtils")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationConstants = require("WorldGenerationConstants")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")

type CloudAssetDefinition = CloudServiceUtils.CloudAssetDefinition
type CloudSurfaceState = CloudServiceUtils.CloudSurfaceState
type CloudView = CloudServiceUtils.CloudView
type MaidClass = any

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

type CloudSpawnSide = "Fill" | "Left" | "Right"

local CloudServiceClient = {}
CloudServiceClient.ServiceName = "CloudServiceClient"

local e: typeof(React.createElement) = React.createElement

local assets: { CloudAssetDefinition } = CloudServiceUtils.NormalizeAssetDefinitions(Clouds)
local random = Random.new()
local maid: MaidClass? = nil
local rootFolder: Folder? = nil
local surfaceRuntime: SurfaceRuntime? = nil
local activeClouds: { Cloud.Cloud } = {}
local pooledClouds: { Cloud.Cloud } = {}
local nextCloudId = 0
local referenceGameplayPlaneDistanceX: number? = nil
local previousCameraZ: number? = nil
local worldOrigin = Vector3.zero
local basePlaneX = 0
local initialized = false

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

local function getCameraSnapshot(camera: Camera?): CameraSnapshot
	if camera == nil then
		return {
			fieldOfView = CloudConstants.DEFAULT_CAMERA_FIELD_OF_VIEW,
			viewportSize = CloudConstants.DEFAULT_CAMERA_VIEWPORT,
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
	local visibleHeight = 2 * distanceValue * math.tan(math.rad(fieldOfViewDegrees) * 0.5)
	local visibleWidth = visibleHeight * aspectRatio
	return visibleWidth, visibleHeight
end

local function getSurfacePixelsPerStud(widthStuds: number, heightStuds: number): number
	local largestAxis = math.max(widthStuds, heightStuds, 1)
	return math.max(
		1,
		math.min(CloudConstants.SURFACE_PIXELS_PER_STUD, CloudConstants.MAX_SURFACE_CANVAS_PIXELS / largestAxis)
	)
end

local function toCanvasPixels(studs: number, pixelsPerStud: number): number
	return math.clamp(
		math.ceil(math.max(studs, 0) * pixelsPerStud),
		CloudConstants.MIN_SURFACE_CANVAS_PIXELS,
		CloudConstants.MAX_SURFACE_CANVAS_PIXELS
	)
end

local function getCanvasPositionXStuds(
	worldPositionZ: number,
	anchorMinZ: number,
	anchorMaxZ: number,
	surfaceFace: Enum.NormalId
): number
	if surfaceFace == Enum.NormalId.Right then
		return anchorMaxZ - worldPositionZ
	end
	return worldPositionZ - anchorMinZ
end

local function getWorldFolder(): Folder?
	local worldFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(CloudConstants.WORLD_FOLDER_NAME)
	if worldFolder ~= nil and worldFolder:IsA("Folder") then
		return worldFolder
	end
	return nil
end

local function getRootParent(): Instance
	local worldFolder = getWorldFolder()
	if worldFolder ~= nil then
		return worldFolder
	end
	return WorkspaceFolders.GetOrCreateFolderInGame(CloudConstants.ROOT_PARENT_FALLBACK_NAME)
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
	CloudServiceUtils.ClearSurfaceState()
end

local function ensureRootFolder()
	local parent = getRootParent()
	if rootFolder ~= nil and rootFolder.Parent == parent then
		return
	end

	destroySurfaceRuntime()
	if rootFolder ~= nil and rootFolder.Parent ~= nil then
		rootFolder:Destroy()
	end
	rootFolder = createFolder(parent, CloudConstants.ROOT_FOLDER_NAME)
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
	anchorPart.Name = CloudConstants.ANCHOR_PART_NAME
	anchorPart.Anchored = true
	anchorPart.Locked = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.CastShadow = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(WorldGenerationConstants.DEFAULT_TILE_DEPTH, 1, 1)
	anchorPart.Parent = rootFolder

	local reactRoot = ReactRoblox.createRoot(anchorPart)
	reactRoot:render(e(ParallaxRoot, {
		parallaxVisible = false,
	}))

	local runtime: SurfaceRuntime = {
		anchorPart = anchorPart,
		reactRoot = reactRoot,
	}
	surfaceRuntime = runtime
	return runtime
end

local function getWorldLayoutSnapshot(stateRaw: any?): WorldLayoutSnapshot
	local fallbackState = ((WorldGenerationServiceClient :: any).state :: { [string]: any }?) or {} :: { [string]: any }
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

local function getCurrentLayoutSnapshot(): LayoutSnapshot
	local cameraSnapshot = getCameraSnapshot(getCamera())
	local worldSnapshot = getWorldLayoutSnapshot(nil)
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
	local worldFolder = getWorldFolder()
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

local function getGameplayPlaneReferenceDistance(cameraPositionX: number): number
	referenceGameplayPlaneDistanceX = ParallaxServiceUtils.GetStableGameplayPlaneDistance(
		referenceGameplayPlaneDistanceX,
		cameraPositionX,
		worldOrigin.X,
		basePlaneX
	)

	return referenceGameplayPlaneDistanceX :: number
end

local function getCloudSizing(visibleHeight: number, cloud: Cloud.Cloud): CloudSizing
	local height = math.max(visibleHeight * CloudConstants.CLOUD_HEIGHT_FACTOR, 1)
	local asset = cloud.asset
	local aspectRatio = if asset ~= nil then asset.imageAspectRatio else 1
	return {
		width = math.max(height * aspectRatio, 1),
		height = height,
	}
end

local function getTargetCloudCount(viewportSize: Vector2): number
	local target = math.floor(viewportSize.X / CloudConstants.CLOUD_TARGET_VIEWPORT_PIXELS + 0.5)
	return math.clamp(target, CloudConstants.CLOUD_MIN_COUNT, CloudConstants.CLOUD_MAX_COUNT)
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

local function getRandomAsset(): CloudAssetDefinition?
	return RandomUtils.choice(assets, random)
end

local function getSpawnOffsetZ(visibleWidth: number, spawnSide: CloudSpawnSide, fillAlpha: number?): number
	if spawnSide == "Fill" then
		local alpha = math.clamp(fillAlpha or random:NextNumber(), 0, 1)
		return (alpha * 2 - 1) * visibleWidth * CloudConstants.CLOUD_VIEWPORT_FILL_HALF_WIDTH_FACTOR
	end

	local nearOffsetZ = visibleWidth * CloudConstants.CLOUD_SPAWN_LEFT_MAX_FACTOR
	local farOffsetZ = visibleWidth * CloudConstants.CLOUD_SPAWN_LEFT_MIN_FACTOR
	local offsetZ = random:NextNumber(nearOffsetZ, farOffsetZ)
	return if spawnSide == "Right" then offsetZ else -offsetZ
end

local function spawnCloud(cameraZ: number, visibleWidth: number, cameraVelocityZ: number, fillAlpha: number?)
	local asset = getRandomAsset()
	if asset == nil then
		return
	end

	nextCloudId += 1
	local cloud = borrowCloud()
	local windSpeed = random:NextNumber(
		CloudConstants.CLOUD_MIN_WIND_SPEED_STUDS_PER_SECOND,
		CloudConstants.CLOUD_MAX_WIND_SPEED_STUDS_PER_SECOND
	)
	local spawnSide: CloudSpawnSide = if fillAlpha ~= nil
		then "Fill"
		elseif windSpeed >= cameraVelocityZ then "Left"
		else "Right"
	cloud:Reset({
		id = tostring(nextCloudId),
		asset = asset,
		scale = CloudConstants.CLOUD_SCALE,
		baseOffsetZ = getSpawnOffsetZ(visibleWidth, spawnSide, fillAlpha),
		verticalAlpha = random:NextNumber(
			CloudConstants.CLOUD_MIN_VERTICAL_ALPHA,
			CloudConstants.CLOUD_MAX_VERTICAL_ALPHA
		),
		spawnCameraZ = cameraZ,
		windSpeed = windSpeed,
		fadeSeconds = CloudConstants.CLOUD_FADE_SECONDS,
		minScale = CloudConstants.CLOUD_MIN_SCALE,
		maxScale = CloudConstants.CLOUD_MAX_SCALE,
		minDepthFactor = CloudConstants.CLOUD_MIN_DEPTH_FACTOR,
		maxDepthFactor = CloudConstants.CLOUD_MAX_DEPTH_FACTOR,
	}, os.clock())
	table.insert(activeClouds, cloud)
end

local function removeInactiveClouds()
	for index = #activeClouds, 1, -1 do
		local cloud = activeClouds[index]
		if not cloud:IsActive() then
			table.remove(activeClouds, index)
			releaseCloud(cloud)
		end
	end
end

local function updateCloudPool(targetCount: number, cameraZ: number, visibleWidth: number, cameraVelocityZ: number)
	local liveCount = 0
	for _, cloud in activeClouds do
		if not cloud:IsRetiring() then
			liveCount += 1
		end
	end

	local missingCount = targetCount - liveCount
	local fillViewport = liveCount < math.ceil(targetCount * 0.5)
	for index = 1, missingCount do
		local fillAlpha = if fillViewport then (index - 0.5) / missingCount else nil
		spawnCloud(cameraZ, visibleWidth, cameraVelocityZ, fillAlpha)
	end
end

local function getCameraVelocityZ(cameraDeltaZ: number, deltaTime: number): number
	if deltaTime <= 0 then
		return 0
	end
	return cameraDeltaZ / deltaTime
end

local function publishServiceState()
	CloudServiceUtils.SetServiceState({
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

	local assetIds = CloudServiceUtils.CollectAssetIds(assets)
	if #assetIds <= 0 then
		return
	end

	activeMaid:GivePromise(ContentProviderUtils.promisePreload(assetIds):Catch(function()
		return false
	end))
end

local function render(deltaTime: number)
	if not initialized then
		return
	end

	refreshWorldAttributes()
	local currentSurfaceRuntime = ensureSurfaceRuntime()
	local camera = getCamera()
	if currentSurfaceRuntime == nil or camera == nil or #assets <= 0 then
		CloudServiceUtils.ClearSurfaceState()
		return
	end

	local layoutSnapshot = getCurrentLayoutSnapshot()
	local cameraPosition = camera.CFrame.Position
	local planeX = worldOrigin.X + basePlaneX - CloudConstants.CLOUD_PLANE_DEPTH_BLOCKS * layoutSnapshot.tileDepth
	local gameplayReferenceDistance = getGameplayPlaneReferenceDistance(cameraPosition.X)
	local coverageDistance = gameplayReferenceDistance + math.abs((worldOrigin.X + basePlaneX) - planeX)
	local visibleWidth, visibleHeight =
		computeVisibleExtentsAtDistance(layoutSnapshot.fieldOfView, layoutSnapshot.viewportSize, coverageDistance)
	local surfaceWidth = math.max(visibleWidth * CloudConstants.CLOUD_SURFACE_WIDTH_FACTOR, 1)
	local surfaceHeight = math.max(visibleHeight * CloudConstants.CLOUD_SURFACE_HEIGHT_FACTOR, 1)
	local surfaceHalfWidth = surfaceWidth * 0.5
	local retireHalfWidth = visibleWidth * 0.5
	local offscreenMargin = visibleWidth * CloudConstants.CLOUD_OFFSCREEN_MARGIN_FACTOR
	local cameraDeltaZ = if previousCameraZ ~= nil then cameraPosition.Z - previousCameraZ else 0
	previousCameraZ = cameraPosition.Z

	local now = os.clock()
	for _, cloud in activeClouds do
		local sizing = getCloudSizing(visibleHeight, cloud)
		cloud:Step(now, cameraPosition.Z, sizing.width, retireHalfWidth, offscreenMargin)
	end
	removeInactiveClouds()
	updateCloudPool(
		getTargetCloudCount(layoutSnapshot.viewportSize),
		cameraPosition.Z,
		visibleWidth,
		getCameraVelocityZ(cameraDeltaZ, deltaTime)
	)

	local minZ = cameraPosition.Z - surfaceHalfWidth
	local maxZ = cameraPosition.Z + surfaceHalfWidth
	for _, cloud in activeClouds do
		local asset = cloud.asset
		if asset == nil or cloud.alpha <= 0.001 then
			continue
		end

		local sizing = getCloudSizing(visibleHeight, cloud)
		minZ = math.min(minZ, cameraPosition.Z + cloud.currentOffsetZ - sizing.width * 0.5)
		maxZ = math.max(maxZ, cameraPosition.Z + cloud.currentOffsetZ + sizing.width * 0.5)
	end

	local rawAnchorWidthStuds = math.max(maxZ - minZ, surfaceWidth, 1)
	local rawAnchorCenterZ = (minZ + maxZ) * 0.5
	minZ = rawAnchorCenterZ - rawAnchorWidthStuds * 0.5
	maxZ = rawAnchorCenterZ + rawAnchorWidthStuds * 0.5

	local horizontalOverscan = math.max(
		rawAnchorWidthStuds * CloudConstants.SURFACE_ANCHOR_HORIZONTAL_OVERSCAN_FACTOR,
		CloudConstants.MIN_SURFACE_ANCHOR_OVERSCAN_STUDS
	)
	minZ -= horizontalOverscan
	maxZ += horizontalOverscan

	local anchorWidthStuds = math.max(maxZ - minZ, 1)
	local anchorCenterY = ParallaxServiceUtils.GetWorldHorizonCenterY(
		worldOrigin.Y,
		visibleHeight,
		CloudConstants.CLOUD_HORIZON_CENTER_OFFSET_FACTOR,
		0
	)
	local anchorCenterZ = (minZ + maxZ) * 0.5
	local pixelsPerStud = getSurfacePixelsPerStud(anchorWidthStuds, surfaceHeight)
	local canvasWidth = toCanvasPixels(anchorWidthStuds, pixelsPerStud)
	local canvasHeight = toCanvasPixels(surfaceHeight, pixelsPerStud)
	currentSurfaceRuntime.anchorPart.Size =
		Vector3.new(WorldGenerationConstants.DEFAULT_TILE_DEPTH, surfaceHeight, anchorWidthStuds)
	currentSurfaceRuntime.anchorPart.CFrame = CFrame.new(planeX, anchorCenterY, anchorCenterZ)
	local surfaceFace = if cameraPosition.X >= planeX then Enum.NormalId.Right else Enum.NormalId.Left

	local cloudViews: { CloudView } = {}
	local anchorMinZ = anchorCenterZ - anchorWidthStuds * 0.5
	local anchorMaxZ = anchorCenterZ + anchorWidthStuds * 0.5
	for _, cloud in activeClouds do
		local asset = cloud.asset
		if asset == nil or cloud.alpha <= 0.001 then
			continue
		end

		local sizing = getCloudSizing(visibleHeight, cloud)
		local cloudCenterY = sizing.height * 0.5 + cloud.verticalAlpha * math.max(surfaceHeight - sizing.height, 0)
		local cloudWorldZ = cameraPosition.Z + cloud.currentOffsetZ
		table.insert(cloudViews, {
			id = cloud.id,
			image = asset.image,
			imageColor = asset.tint,
			imageTransparency = 1 - math.clamp(cloud.alpha, 0, 1),
			position = UDim2.fromOffset(
				getCanvasPositionXStuds(cloudWorldZ, anchorMinZ, anchorMaxZ, surfaceFace) * pixelsPerStud,
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

	CloudServiceUtils.SetSurfaceState({
		visible = true,
		adornee = currentSurfaceRuntime.anchorPart,
		face = surfaceFace,
		brightness = CloudConstants.SURFACE_BRIGHTNESS,
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

	activeMaid:GiveTask(Rx.fromSignal(RunService.RenderStepped):Subscribe(function(deltaTime: number)
		render(deltaTime)
	end))

	activeMaid:GiveTask(Rx.fromSignal(Workspace:GetPropertyChangedSignal("CurrentCamera")):Subscribe(function()
		referenceGameplayPlaneDistanceX = nil
		previousCameraZ = nil
	end))
end

function CloudServiceClient.Init(
	self: any,
	containerOrServiceBag: Instance | ServiceBag.ServiceBag?
)
	if ServiceBag.isServiceBag(containerOrServiceBag) then
		self._serviceBag = containerOrServiceBag :: ServiceBag.ServiceBag
	end
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
				cloud:Destroy()
			end
			for _, cloud in pooledClouds do
				cloud:Destroy()
			end
			table.clear(activeClouds)
			table.clear(pooledClouds)
			previousCameraZ = nil
			initialized = false
			CloudServiceUtils.ClearServiceState()
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
		cloud:BeginFadeOut(os.clock())
	end
end

function CloudServiceClient.GetState(_self: any): CloudServiceUtils.ServiceState
	return CloudServiceUtils.GetServiceState()
end

function CloudServiceClient.Destroy(self: any)
	self._serviceBag = nil
	if maid == nil then
		return
	end
	maid:DoCleaning()
	maid = nil
end
return CloudServiceClient
