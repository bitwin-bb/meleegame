local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Damp = require("Damp")
local Maid = require("Maid")
local Promise = require("Promise")
local Rx = require("Rx")
local RxCharacterUtils = require("RxCharacterUtils")
local RxInstanceUtils = require("RxInstanceUtils")
local Table = require("Table")
local ValueObject = require("ValueObject")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationConstants = require("WorldGenerationConstants")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)

local PlayerMain = {}
PlayerMain.__index = PlayerMain

local SURFACE_GUI_NAME = "PlayerViewportSurface"
local SURFACE_ANCHOR_NAME = "PlayerViewportAnchor"
local VIEWPORT_FRAME_NAME = "PlayerViewport"
local WORLD_MODEL_NAME = "PlayerViewportWorld"
local CAMERA_NAME = "PlayerViewportCamera"
local SURFACE_FOLDER_NAME = "PlayerViewportSurfaces"
local WORLD_GENERATION_FOLDER_NAME = "WorldGeneration"
local DEFAULT_VIEWPORT_SIZE = Vector2.new(1280, 720)
local VIEWPORT_FRAME_POSITION = UDim2.fromScale(0, 0)
local VIEWPORT_FRAME_SIZE = UDim2.fromScale(1, 1)
local DEFAULT_SURFACE_ANCHOR_SIZE = Vector3.new(2, 8, 6)
local SURFACE_FACE = Enum.NormalId.Right
local SURFACE_PIXELS_PER_STUD = 8
local SURFACE_ANCHOR_DEPTH = WorldGenerationConstants.DEFAULT_TILE_DEPTH
local SURFACE_Z_OFFSET = 0
local ORTHOGRAPHIC_FIELD_OF_VIEW = 1
local CAMERA_PADDING_SCALE = 1.18
local CAMERA_HALF_EXTENTS_PADDING = Vector3.new(0.25, 0.75, 1)
local VIEWPORT_FRAME_SMOOTHING_RESPONSE = 30
local VIEWPORT_CENTER_SNAP_DISTANCE = 8
local DEFAULT_SMOOTHING_DELTA_TIME = 1 / 60
local MAX_SMOOTHING_DELTA_TIME = 1 / 15
local REBUILD_DEBOUNCE_SECONDS = 0.03

local AUDIO_CLASS_NAMES = table.freeze({
	AudioAnalyzer = true,
	AudioChorus = true,
	AudioCompressor = true,
	AudioDeviceInput = true,
	AudioDeviceOutput = true,
	AudioDistortion = true,
	AudioEcho = true,
	AudioEmitter = true,
	AudioEqualizer = true,
	AudioFader = true,
	AudioFlanger = true,
	AudioListener = true,
	AudioPitchShifter = true,
	AudioPlayer = true,
	AudioReverb = true,
	Wire = true,
})

local function isRenderablePart(instance: Instance): boolean
	return instance:IsA("BasePart")
end

local function isExecutableInstance(instance: Instance): boolean
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

local function isAudioInstance(instance: Instance): boolean
	return instance:IsA("Sound") or AUDIO_CLASS_NAMES[instance.ClassName] == true
end

local function destroyAudioInstance(instance: Instance)
	if instance:IsA("Sound") then
		local sound = instance :: Sound
		sound.PlayOnRemove = false
		sound.Volume = 0
		sound:Stop()
	end

	instance:Destroy()
end

local function getModelRootPart(model: Model): BasePart?
	local primaryPart = model.PrimaryPart
	if primaryPart ~= nil then
		return primaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	return nil
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getTerrainPlaneCenterX(self: any, fallbackX: number): number
	local worldFolder = rawget(self, "worldGenerationFolder")
	if worldFolder == nil or worldFolder.Parent == nil then
		worldFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(WORLD_GENERATION_FOLDER_NAME)
		self.worldGenerationFolder = worldFolder
	end
	if worldFolder == nil then
		return fallbackX
	end

	local worldOriginX = worldFolder:GetAttribute("WorldOriginX")
	local basePlaneX = worldFolder:GetAttribute("BasePlaneX")
	return (if isFiniteNumber(worldOriginX) then worldOriginX :: number else 0)
		+ (if isFiniteNumber(basePlaneX) then basePlaneX :: number else 0)
end

local function setFusionValue(valueObject: any, nextValue: any)
	if valueObject ~= nil then
		valueObject:set(nextValue)
	end
end

local function getViewportAspectRatio(viewportSize: Vector2): number
	if viewportSize.Y <= 0 then
		return DEFAULT_VIEWPORT_SIZE.X / DEFAULT_VIEWPORT_SIZE.Y
	end
	return math.clamp(viewportSize.X / viewportSize.Y, 0.01, 100)
end

local function getVisibleSideHeight(boundsSize: Vector3, viewportSize: Vector2, paddingScale: number?): number
	local aspectRatio = getViewportAspectRatio(viewportSize)
	local sideHeight = math.max(boundsSize.Y, boundsSize.Z / aspectRatio, 1)
	return sideHeight * math.max(1, paddingScale or CAMERA_PADDING_SCALE)
end

local function getSmoothingDeltaTime(deltaTimeRaw: any): number
	if typeof(deltaTimeRaw) ~= "number" or deltaTimeRaw ~= deltaTimeRaw then
		return DEFAULT_SMOOTHING_DELTA_TIME
	end

	return math.clamp(deltaTimeRaw, 0, MAX_SMOOTHING_DELTA_TIME)
end

local function smoothVector3(previous: Vector3?, target: Vector3, alpha: number, snapDistance: number): Vector3
	if previous == nil or (target - previous).Magnitude >= snapDistance or alpha >= 1 then
		return target
	end

	if alpha <= 0 then
		return previous
	end

	return previous:Lerp(target, alpha)
end

local function cloneCharacter(character: Model): Model?
	local previousArchivable = character.Archivable
	character.Archivable = true
	local ok, cloneOrError = pcall(function()
		return character:Clone()
	end)
	character.Archivable = previousArchivable

	if not ok or typeof(cloneOrError) ~= "Instance" or not cloneOrError:IsA("Model") then
		warn("[playermain] failed to clone character for viewport")
		return nil
	end

	local clone = cloneOrError :: Model
	clone.Name = "ViewportCharacter"
	return clone
end

local function prepareCloneForViewport(clone: Model)
	for _, descendant in clone:GetDescendants() do
		if isAudioInstance(descendant) then
			destroyAudioInstance(descendant)
		elseif isExecutableInstance(descendant) then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			descendant.PlatformStand = true
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
			descendant.AssemblyAngularVelocity = Vector3.zero
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.LocalTransparencyModifier = 0
		end
	end
end

local function mapCloneParts(source: Instance, clone: Instance, output: { [BasePart]: BasePart })
	if source:IsA("BasePart") and clone:IsA("BasePart") then
		output[source] = clone
	end

	local sourceChildren = source:GetChildren()
	local cloneChildren = clone:GetChildren()
	local usedCloneChildren = {}

	for _, sourceChild in sourceChildren do
		local cloneChild = nil
		for index, candidate in cloneChildren do
			if usedCloneChildren[index] == true then
				continue
			end

			if candidate.Name == sourceChild.Name and candidate.ClassName == sourceChild.ClassName then
				cloneChild = candidate
				usedCloneChildren[index] = true
				break
			end
		end

		if
			cloneChild ~= nil
			and cloneChild.Name == sourceChild.Name
			and cloneChild.ClassName == sourceChild.ClassName
		then
			mapCloneParts(sourceChild, cloneChild, output)
		end
	end
end

function PlayerMain.GetViewportCameraDistance(
	boundsSize: Vector3,
	viewportSize: Vector2?,
	fieldOfViewDegrees: number?,
	paddingScale: number?
): number
	local fov = math.clamp(fieldOfViewDegrees or ORTHOGRAPHIC_FIELD_OF_VIEW, 0.5, 70)
	local visibleSideHeight = getVisibleSideHeight(boundsSize, viewportSize or DEFAULT_VIEWPORT_SIZE, paddingScale)
	return visibleSideHeight / (2 * math.tan(math.rad(fov) * 0.5))
end

function PlayerMain.GetViewportCameraCFrame(boundsCFrame: CFrame, cameraDistance: number): CFrame
	local center = boundsCFrame.Position
	return CFrame.lookAt(center + Vector3.xAxis * math.max(1, cameraDistance), center, Vector3.yAxis)
end

function PlayerMain.GetSurfaceAnchorSize(boundsSize: Vector3, paddingScale: number?): Vector3
	local padding = math.max(1, paddingScale or CAMERA_PADDING_SCALE)
	return Vector3.new(SURFACE_ANCHOR_DEPTH, math.max(1, boundsSize.Y * padding), math.max(1, boundsSize.Z * padding))
end

function PlayerMain.GetSurfaceAnchorCFrame(boundsCFrame: CFrame, terrainPlaneCenterX: number?): CFrame
	local position = boundsCFrame.Position
	local planeCenterX = if isFiniteNumber(terrainPlaneCenterX) then terrainPlaneCenterX :: number else position.X
	return CFrame.new(planeCenterX, position.Y, position.Z)
end

function PlayerMain.GetSurfacePixelsPerStud(): number
	return SURFACE_PIXELS_PER_STUD
end

function PlayerMain.GetViewportFramePosition(): UDim2
	return VIEWPORT_FRAME_POSITION
end

function PlayerMain.GetViewportFrameSize(): UDim2
	return VIEWPORT_FRAME_SIZE
end

function PlayerMain.GetViewportFrameMeasuredSize(size: Vector2): Vector2
	return Vector2.new(math.abs(size.X), math.abs(size.Y))
end

function PlayerMain.GetStableViewportBoundsSize(previousBoundsSize: Vector3?, currentBoundsSize: Vector3): Vector3
	if previousBoundsSize == nil then
		return currentBoundsSize
	end

	return Vector3.new(
		math.max(previousBoundsSize.X, currentBoundsSize.X),
		math.max(previousBoundsSize.Y, currentBoundsSize.Y),
		math.max(previousBoundsSize.Z, currentBoundsSize.Z)
	)
end

function PlayerMain.GetStableViewportBoundsSizeFromHalfExtents(halfExtents: Vector3): Vector3
	return halfExtents * 2
end

function PlayerMain.GetStableViewportHalfExtents(
	previousHalfExtents: Vector3?,
	stableCenter: Vector3,
	boundsCFrame: CFrame,
	boundsSize: Vector3,
	padding: Vector3?
): Vector3
	local centerOffset = boundsCFrame.Position - stableCenter
	local halfSize = boundsSize * 0.5
	local currentHalfExtents = Vector3.new(
		math.abs(centerOffset.X) + halfSize.X,
		math.abs(centerOffset.Y) + halfSize.Y,
		math.abs(centerOffset.Z) + halfSize.Z
	) + (padding or Vector3.zero)

	if previousHalfExtents == nil then
		return currentHalfExtents
	end

	return Vector3.new(
		math.max(previousHalfExtents.X, currentHalfExtents.X),
		math.max(previousHalfExtents.Y, currentHalfExtents.Y),
		math.max(previousHalfExtents.Z, currentHalfExtents.Z)
	)
end

function PlayerMain.GetStableViewportCenter(
	boundsCFrame: CFrame,
	rootCFrame: CFrame?,
	previousCenterOffset: Vector3?
): (Vector3, Vector3?)
	if rootCFrame == nil then
		return boundsCFrame.Position, previousCenterOffset
	end

	local centerOffset = previousCenterOffset or boundsCFrame.Position - rootCFrame.Position
	return rootCFrame.Position + centerOffset, centerOffset
end

function PlayerMain.GetViewportSmoothingAlpha(response: number, deltaTime: number): number
	return Damp.Factor(response, getSmoothingDeltaTime(deltaTime))
end

function PlayerMain.GetViewportPartCFrame(sourceCFrame: CFrame): CFrame
	return sourceCFrame
end

function PlayerMain.ShouldRebuildForCharacterChild(child: Instance): boolean
	return child:IsA("Tool") or child:IsA("Accessory") or child:IsA("BasePart") or child:IsA("Model")
end

function PlayerMain.new(player: Player?, viewerPlayer: Player?): any
	local self = setmetatable({}, PlayerMain)
	self.localPlayer = player or Players.LocalPlayer
	self.viewerPlayer = viewerPlayer or Players.LocalPlayer
	self.maid = Maid.new()
	self.mountMaid = Maid.new()
	self.characterMaid = Maid.new()
	self.visibilityMaid = Maid.new()
	self.cloneMaid = Maid.new()
	self.rebuildMaid = Maid.new()
	self.state = ValueObject.new({
		enabled = false,
		character = nil,
		clone = nil,
		updatedAt = os.clock(),
	})
	self.scope = Fusion.scoped(Fusion)
	self.playerGuiParentValue = self.scope:Value(self.viewerPlayer:FindFirstChildOfClass("PlayerGui"))
	self.viewportSizeValue = self.scope:Value(DEFAULT_VIEWPORT_SIZE)
	self.surfaceAnchorSizeValue = self.scope:Value(DEFAULT_SURFACE_ANCHOR_SIZE)
	self.surfaceAnchorCFrameValue = self.scope:Value(CFrame.new())
	self.surfaceEnabledValue = self.scope:Value(false)
	self.cameraCFrameValue = self.scope:Value(CFrame.new())
	self.cameraFocusValue = self.scope:Value(CFrame.new())
	self.stableBoundsSize = nil
	self.stableHalfExtents = nil
	self.stableCenterOffset = nil
	self.smoothedViewportCenter = nil
	self.characterDead = false
	self.started = false
	self.rebuildRequested = false
	self.destroyed = false

	self.maid:GiveTask(self.mountMaid)
	self.maid:GiveTask(self.characterMaid)
	self.maid:GiveTask(self.visibilityMaid)
	self.maid:GiveTask(self.cloneMaid)
	self.maid:GiveTask(self.rebuildMaid)
	self.maid:GiveTask(self.state)
	self.maid:GiveTask(function()
		Fusion.doCleanup(self.scope)
	end)

	return self
end

function PlayerMain.ObserveState(self: any): any
	return self.state:Observe()
end

function PlayerMain.Start(self: any)
	if self.started == true then
		return
	end

	self.started = true
	self:Mount()
	self:ObserveLocalCharacter()

	local function refreshPlayerGuiParent()
		setFusionValue(self.playerGuiParentValue, self.viewerPlayer:FindFirstChildOfClass("PlayerGui"))
	end
	self.maid:GiveTask(self.viewerPlayer.ChildAdded:Connect(function(child: Instance)
		if child:IsA("PlayerGui") then
			refreshPlayerGuiParent()
		end
	end))
	self.maid:GiveTask(self.viewerPlayer.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("PlayerGui") then
			refreshPlayerGuiParent()
		end
	end))

	self.maid:GiveTask(Rx.fromSignal(RunService.RenderStepped):Subscribe(function(deltaTime: number)
		self:SyncViewport(deltaTime)
	end))
end

function PlayerMain.ObserveLocalCharacter(self: any)
	self.maid:GiveTask(RxCharacterUtils.observeCharacter(self.localPlayer):Subscribe(function(character: Model?)
		self:SetCharacter(character)
	end))
end

function PlayerMain.Mount(self: any, _playerGui: Instance?)
	self.mountMaid:DoCleaning()

	local mountScope = Fusion.deriveScope(self.scope)
	self.mountMaid:GiveTask(function()
		Fusion.doCleanup(mountScope)
	end)
	self.mountMaid:GiveTask(function()
		self.camera = nil
		self.worldModel = nil
		self.surfaceAnchor = nil
		self.surfaceGui = nil
		self.surfaceFolder = nil
	end)

	self.camera = mountScope:New "Camera" {
		Name = CAMERA_NAME,
		FieldOfView = ORTHOGRAPHIC_FIELD_OF_VIEW,
		CFrame = self.cameraCFrameValue,
		Focus = self.cameraFocusValue,
	}

	self.worldModel = mountScope:New "WorldModel" {
		Name = WORLD_MODEL_NAME,
	}

	self.surfaceAnchor = mountScope:New "Part" {
		Name = SURFACE_ANCHOR_NAME,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		CFrame = self.surfaceAnchorCFrameValue,
		Size = self.surfaceAnchorSizeValue,
		Transparency = 1,
		Parent = Workspace,
	}
	self.surfaceFolder = mountScope:New "ScreenGui" {
		Name = SURFACE_FOLDER_NAME,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Parent = self.playerGuiParentValue,
	}

	self.surfaceGui = mountScope:New "SurfaceGui" {
		Name = SURFACE_GUI_NAME,
		Adornee = self.surfaceAnchor,
		AlwaysOnTop = true,
		Brightness = 1,
		Enabled = self.surfaceEnabledValue,
		Face = SURFACE_FACE,
		LightInfluence = 0,
		MaxDistance = 100000,
		PixelsPerStud = PlayerMain.GetSurfacePixelsPerStud(),
		ResetOnSpawn = false,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		ZOffset = SURFACE_Z_OFFSET,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = self.surfaceFolder,

		[Fusion.Children] = {
			mountScope:New "ViewportFrame" {
				Name = VIEWPORT_FRAME_NAME,
				Active = false,
				Ambient = Color3.fromRGB(180, 188, 210),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CurrentCamera = self.camera,
				LightColor = Color3.fromRGB(255, 248, 232),
				LightDirection = Vector3.new(-0.35, -0.7, -0.55),
				Position = PlayerMain.GetViewportFramePosition(),
				Size = PlayerMain.GetViewportFrameSize(),

				[Fusion.OnChange("AbsoluteSize")] = function(size: Vector2)
					setFusionValue(self.viewportSizeValue, PlayerMain.GetViewportFrameMeasuredSize(size))
					self:RefreshCamera()
				end,

				[Fusion.Children] = {
					self.worldModel,
					self.camera,
				},
			},
		},
	}
end

function PlayerMain.SetCharacter(self: any, character: Model?)
	if rawget(self, "character") == character then
		return
	end

	self.character = character
	self.characterMaid:DoCleaning()
	self.visibilityMaid:DoCleaning()
	self.rebuildMaid:DoCleaning()
	self.partMap = nil
	self.stableBoundsSize = nil
	self.stableHalfExtents = nil
	self.stableCenterOffset = nil
	self.smoothedViewportCenter = nil
	self.characterDead = false
	local activeClone = rawget(self, "characterClone")
	local hasActiveClone = activeClone ~= nil and activeClone.Parent ~= nil
	setFusionValue(self.surfaceEnabledValue, hasActiveClone)

	self.state.Value = {
		enabled = hasActiveClone,
		character = character,
		clone = activeClone,
		updatedAt = os.clock(),
	}

	if character == nil then
		return
	end

	self:BindCharacterChangeSignals(character)
	self:RequestRebuildCharacterClone()
end

function PlayerMain.BindCharacterLocalVisibility(self: any, character: Model)
	self.visibilityMaid:DoCleaning()
	self.visibilityMaid:GiveTask(
		RxInstanceUtils.observeDescendantsAndSelfBrio(character, isRenderablePart):Subscribe(function(brio: any)
			if brio:IsDead() then
				return
			end

			local partMaid, part = brio:ToMaidAndValue()
			local previousModifier = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
			partMaid:GiveTask(function()
				if part.Parent ~= nil then
					part.LocalTransparencyModifier = previousModifier
				end
			end)
		end)
	)
end

function PlayerMain.BindCharacterChangeSignals(self: any, character: Model)
	local function bindHumanoid(humanoid: Humanoid)
		self.characterMaid.HumanoidDied = humanoid.Died:Connect(function()
			if rawget(self, "character") == character then
				self.characterDead = true
			end
		end)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		bindHumanoid(humanoid)
	end

	self.characterMaid:GiveTask(Rx.fromSignal(character.ChildAdded):Subscribe(function(child: Instance)
		if child:IsA("Humanoid") then
			bindHumanoid(child)
		end
		if PlayerMain.ShouldRebuildForCharacterChild(child) then
			self:RequestRebuildCharacterClone()
		end
	end))
	self.characterMaid:GiveTask(Rx.fromSignal(character.ChildRemoved):Subscribe(function(child: Instance)
		if child:IsA("Humanoid") then
			self.characterMaid.HumanoidDied = nil
		end
		if PlayerMain.ShouldRebuildForCharacterChild(child) then
			self:RequestRebuildCharacterClone()
		end
	end))
end

function PlayerMain.RequestRebuildCharacterClone(self: any)
	if self.rebuildRequested or self.destroyed then
		return
	end

	self.rebuildRequested = true
	task.delay(REBUILD_DEBOUNCE_SECONDS, function()
		if self.destroyed then
			return
		end

		self.rebuildRequested = false
		self:RebuildCharacterClone()
	end)
end

function PlayerMain.RebuildCharacterClone(self: any)
	local character = rawget(self, "character")
	local worldModel = rawget(self, "worldModel")
	if self.characterDead or character == nil or character.Parent == nil or worldModel == nil then
		return
	end

	self.rebuildMaid:DoCleaning()

	local clonePromise = Promise.defer(function(resolve, reject)
		local clone = cloneCharacter(character)
		if clone == nil then
			reject("[playermain] character clone unavailable")
			return
		end

		prepareCloneForViewport(clone)
		resolve(clone)
	end)

	self.rebuildMaid:GivePromise(clonePromise:Then(function(clone: Model)
		local currentWorldModel = rawget(self, "worldModel")
		if
			self.destroyed
			or self.characterDead
			or rawget(self, "character") ~= character
			or currentWorldModel == nil
		then
			clone:Destroy()
			return
		end

		local partMap = {}
		mapCloneParts(character, clone, partMap)

		self.cloneMaid:DoCleaning()
		self.visibilityMaid:DoCleaning()
		local cloneScope = Fusion.deriveScope(self.scope)
		self.cloneMaid:GiveTask(function()
			Fusion.doCleanup(cloneScope)
		end)
		self.cloneMaid:GiveTask(clone)
		cloneScope:Hydrate(clone) {
			Parent = currentWorldModel,
		}

		self.characterClone = clone
		self.partMap = partMap
		self.state.Value = {
			enabled = true,
			character = character,
			clone = clone,
			updatedAt = os.clock(),
		}
		self:SyncViewport()
		self:BindCharacterLocalVisibility(character)
	end, function(message: any)
		warn(message)
	end))
end

function PlayerMain.SyncViewport(self: any, deltaTimeRaw: number?)
	local deltaTime = getSmoothingDeltaTime(deltaTimeRaw)

	local partMap = rawget(self, "partMap")
	if partMap ~= nil then
		for sourcePart, clonePart in partMap do
			if sourcePart.Parent == nil or clonePart.Parent == nil then
				if not self.characterDead then
					self:RequestRebuildCharacterClone()
				end
				continue
			end

			clonePart.CFrame = PlayerMain.GetViewportPartCFrame(sourcePart.CFrame)
			clonePart.Size = sourcePart.Size
			clonePart.Color = sourcePart.Color
			clonePart.Material = sourcePart.Material
			clonePart.Transparency = sourcePart.Transparency
			clonePart.Reflectance = sourcePart.Reflectance
			clonePart.AssemblyAngularVelocity = Vector3.zero
			clonePart.AssemblyLinearVelocity = Vector3.zero
		end
	end

	self:RefreshCamera(deltaTime)
end

function PlayerMain.RefreshCamera(self: any, deltaTimeRaw: number?)
	local characterClone = rawget(self, "characterClone")
	if characterClone == nil or characterClone.Parent == nil then
		return
	end

	local boundsCFrame, boundsSize = characterClone:GetBoundingBox()
	local rootPart = getModelRootPart(characterClone)
	local stableCenter, stableCenterOffset = PlayerMain.GetStableViewportCenter(
		boundsCFrame,
		if rootPart ~= nil then rootPart.CFrame else nil,
		rawget(self, "stableCenterOffset")
	)
	local stableHalfExtents = PlayerMain.GetStableViewportHalfExtents(
		rawget(self, "stableHalfExtents"),
		stableCenter,
		boundsCFrame,
		boundsSize,
		CAMERA_HALF_EXTENTS_PADDING
	)
	local stableBoundsSize = PlayerMain.GetStableViewportBoundsSizeFromHalfExtents(stableHalfExtents)
	self.stableCenterOffset = stableCenterOffset
	self.stableHalfExtents = stableHalfExtents
	self.stableBoundsSize = stableBoundsSize

	local viewportSize = Fusion.peek(self.viewportSizeValue)
	local frameAlpha =
		PlayerMain.GetViewportSmoothingAlpha(VIEWPORT_FRAME_SMOOTHING_RESPONSE, getSmoothingDeltaTime(deltaTimeRaw))
	local smoothedCenter =
		smoothVector3(rawget(self, "smoothedViewportCenter"), stableCenter, frameAlpha, VIEWPORT_CENTER_SNAP_DISTANCE)
	local terrainPlaneCenterX =
		getTerrainPlaneCenterX(self, if rootPart ~= nil then rootPart.CFrame.Position.X else smoothedCenter.X)
	setFusionValue(self.surfaceAnchorSizeValue, PlayerMain.GetSurfaceAnchorSize(stableBoundsSize, CAMERA_PADDING_SCALE))
	setFusionValue(
		self.surfaceAnchorCFrameValue,
		PlayerMain.GetSurfaceAnchorCFrame(CFrame.new(smoothedCenter), terrainPlaneCenterX)
	)
	setFusionValue(self.surfaceEnabledValue, true)

	local distance = PlayerMain.GetViewportCameraDistance(
		stableBoundsSize,
		viewportSize,
		ORTHOGRAPHIC_FIELD_OF_VIEW,
		CAMERA_PADDING_SCALE
	)
	self.smoothedViewportCenter = smoothedCenter

	local cameraCFrame = PlayerMain.GetViewportCameraCFrame(CFrame.new(smoothedCenter), distance)
	setFusionValue(self.cameraCFrameValue, cameraCFrame)
	setFusionValue(self.cameraFocusValue, CFrame.new(smoothedCenter))
end

function PlayerMain.Destroy(self: any)
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.maid:Destroy()
end

return Table.readonly(PlayerMain)
