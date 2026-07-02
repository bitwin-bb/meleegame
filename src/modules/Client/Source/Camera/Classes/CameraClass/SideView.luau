local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Cache = require("Cache")
local CameraServiceUtils = require("CameraServiceUtils")
local CatchUpPlayer = require("CatchUpPlayer")
local Configs = require("CoreConfigs")
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Predict = require("Predict")
local CameraBackendGetter = require("CameraBackendGetter")
local Ripple = require(ReplicatedStorage.Packages.Ripple)
local RoomBehavior = require("Room")
local Stack = require("CameraOverrideStack")
local State = require("CameraOverrideState")
local Target = require("Target")

local SideView = {}
SideView.__index = SideView

type Motion<T> = Ripple.Motion<T>
type SpringOptions = Ripple.SpringOptions
type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

export type SideViewConfig = {
	distance: number?,
	height: number?,
	lookHeight: number?,
	sideSign: number?,
	fieldOfView: number?,
	movementBackAmount: number?,
	movementSpeedForMaxBack: number?,
	movementBackSign: number?,
	mouseInfluenceX: number?,
	mouseInfluenceY: number?,
	cameraSpring: SpringOptions?,
	fovSpring: SpringOptions?,
	room: RoomBehavior.RoomConfig?,
	catchUpPlayer: CatchUpPlayer.CatchUpPlayerConfig?,
	predict: Predict.PredictionConfig?,
}

export type SideViewInitOptions = {
	snapToTarget: boolean?,
}

export type SideView = typeof(setmetatable(
	{} :: {
		enabled: boolean,
		target: any?,
		character: Model?,
		renderStepName: string,
		distance: number,
		height: number,
		lookHeight: number,
		sideSign: number,
		fieldOfView: number,
		movementBackAmount: number,
		movementSpeedForMaxBack: number,
		movementBackSign: number,
		mouseInfluenceX: number,
		mouseInfluenceY: number,
		cameraSpring: SpringOptions,
		fovSpring: SpringOptions,
		catchUpPlayerBehavior: CatchUpPlayer.CatchUpPlayer,
		roomBehavior: RoomBehavior.Room,
		backendCache: Cache.Cache,
		backendPredict: Predict.Predict,
		backendGetter: CameraBackendGetter.CameraBackendGetter,
		backendStack: Stack.Stack,
		backendState: State.State,
		backendTarget: Target.Target,
		cameraMotion: Motion<CFrame>,
		fovMotion: Motion<number>,
		janitor: JanitorClass,
		lastCameraType: Enum.CameraType?,
		lastFieldOfView: number?,
		lastResolution: CameraBackendGetter.ResolutionResult?,
	},
	SideView
))

local DEFAULT_CAMERA_SPRING: SpringOptions = {
	frequency = 6,
	damping = 1,
}

local DEFAULT_FOV_SPRING: SpringOptions = {
	frequency = 4,
	damping = 1,
}

local DEFAULT_SIDE_VIEW_CONFIG = (Configs.cameraData :: any) :: SideViewConfig
local SIDE_VIEW_RENDER_PRIORITY = Enum.RenderPriority.Camera.Value
local sideViewInstanceCount = 0

local function getMouseViewportNormalized(camera: Camera): Vector2
	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return Vector2.zero
	end

	local center = viewportSize * 0.5
	local mouseLocation = UserInputService:GetMouseLocation()

	return Vector2.new(
		math.clamp((mouseLocation.X - center.X) / center.X, -1, 1),
		math.clamp((mouseLocation.Y - center.Y) / center.Y, -1, 1)
	)
end

local function getBaseViewConfig(self: SideView): CameraBackendGetter.ViewConfig
	return {
		distance = self.distance,
		height = self.height,
		lookHeight = self.lookHeight,
		fieldOfView = self.fieldOfView,
	}
end

function SideView.New(config: SideViewConfig?): SideView
	local camera = Workspace.CurrentCamera
	local startCFrame = if camera then camera.CFrame else CFrame.new()
	local startFov = if camera then camera.FieldOfView else 40
	sideViewInstanceCount += 1

	local backendCache = Cache.New()
	local backendPredict = Predict.New(if config then (config :: any).predict else nil)
	local backendStack = Stack.New()
	local backendState = State.New()
	local backendTarget = Target.New({
		GetCharacterTarget = CameraServiceUtils.GetCharacterTarget,
	})
	local backendGetter = CameraBackendGetter.new({
		cache = backendCache,
		predictor = backendPredict,
		stack = backendStack,
		state = backendState,
		target = backendTarget,
	})

	local self = setmetatable({
		enabled = false,
		target = nil,
		character = nil,
		renderStepName = ("SideViewCameraUpdate_%d"):format(sideViewInstanceCount),
		distance = if config and config.distance then config.distance else DEFAULT_SIDE_VIEW_CONFIG.distance :: number,
		height = if config and config.height then config.height else DEFAULT_SIDE_VIEW_CONFIG.height :: number,
		lookHeight = if config and config.lookHeight
			then config.lookHeight
			else DEFAULT_SIDE_VIEW_CONFIG.lookHeight :: number,
		sideSign = if config and config.sideSign
			then math.sign(config.sideSign)
			else math.sign(DEFAULT_SIDE_VIEW_CONFIG.sideSign :: number),
		fieldOfView = if config and config.fieldOfView
			then config.fieldOfView
			else DEFAULT_SIDE_VIEW_CONFIG.fieldOfView :: number,
		movementBackAmount = if config and config.movementBackAmount
			then config.movementBackAmount
			else DEFAULT_SIDE_VIEW_CONFIG.movementBackAmount :: number,
		movementSpeedForMaxBack = if config and config.movementSpeedForMaxBack
			then config.movementSpeedForMaxBack
			else DEFAULT_SIDE_VIEW_CONFIG.movementSpeedForMaxBack :: number,
		movementBackSign = if config and config.movementBackSign
			then math.sign(config.movementBackSign)
			else math.sign(DEFAULT_SIDE_VIEW_CONFIG.movementBackSign :: number),
		mouseInfluenceX = if config and config.mouseInfluenceX
			then config.mouseInfluenceX
			else DEFAULT_SIDE_VIEW_CONFIG.mouseInfluenceX :: number,
		mouseInfluenceY = if config and config.mouseInfluenceY
			then config.mouseInfluenceY
			else DEFAULT_SIDE_VIEW_CONFIG.mouseInfluenceY :: number,
		cameraSpring = if config and config.cameraSpring
			then config.cameraSpring
			else (DEFAULT_SIDE_VIEW_CONFIG.cameraSpring or DEFAULT_CAMERA_SPRING),
		fovSpring = if config and config.fovSpring
			then config.fovSpring
			else (DEFAULT_SIDE_VIEW_CONFIG.fovSpring or DEFAULT_FOV_SPRING),
		catchUpPlayerBehavior = CatchUpPlayer.New(if config then (config :: any).catchUpPlayer else nil),
		roomBehavior = RoomBehavior.New(if config then (config :: any).room else nil),
		backendCache = backendCache,
		backendPredict = backendPredict,
		backendGetter = backendGetter,
		backendStack = backendStack,
		backendState = backendState,
		backendTarget = backendTarget,
		cameraMotion = Ripple.createMotion(startCFrame),
		fovMotion = Ripple.createMotion(startFov),
		janitor = Janitor.new(),
		lastCameraType = nil,
		lastFieldOfView = nil,
		lastResolution = nil,
	}, SideView)

	if self.sideSign == 0 then
		self.sideSign = 1
	end
	if self.movementBackSign == 0 then
		self.movementBackSign = 1
	end

	return self
end

function SideView.GetGoal(self: SideView, camera: Camera?, deltaTime: number?): CameraBackendGetter.ResolutionResult
	local resolution = self.backendGetter:Get({
		now = os.clock(),
		deltaTime = deltaTime,
		character = self.character,
		distance = self.distance,
		height = self.height,
		lookHeight = self.lookHeight,
		sideSign = self.sideSign,
		fieldOfView = self.fieldOfView,
		movementBackAmount = self.movementBackAmount,
		movementSpeedForMaxBack = self.movementSpeedForMaxBack,
		movementBackSign = self.movementBackSign,
		mouseInfluenceX = self.mouseInfluenceX,
		mouseInfluenceY = self.mouseInfluenceY,
		roomBehavior = self.roomBehavior,
		mouseNormalized = if camera ~= nil then getMouseViewportNormalized(camera) else Vector2.zero,
	})
	self.lastResolution = resolution
	return resolution
end

function SideView.GetDynamicViewConfig(self: SideView): RoomBehavior.ViewConfig
	local subject = self.backendTarget:Get({
		character = self.character,
	})
	local baseViewConfig = getBaseViewConfig(self)
	if subject == nil then
		return baseViewConfig
	end

	return self.roomBehavior:GetViewConfig(baseViewConfig, subject.position)
end

function SideView.GetTargetCFrame(self: SideView, camera: Camera, _viewConfig: RoomBehavior.ViewConfig): CFrame
	local resolution = self:GetGoal(camera, 1 / 60)
	return if resolution.cameraCFrame ~= nil then resolution.cameraCFrame else camera.CFrame
end

function SideView.SetTarget(self: SideView, target: any?)
	self.target = target
	self.backendTarget:SetExplicitTarget(target)
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
end

function SideView.SetCharacter(self: SideView, character: Model?)
	self.character = character
	self.backendTarget:SetCharacter(character)
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
end

function SideView.PushOverride(self: SideView, overrideRaw: any): number
	local id = self.backendStack:Push(overrideRaw)
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
	return id
end

function SideView.UpdateOverride(self: SideView, idRaw: any, patchRaw: any): boolean
	local didUpdate = self.backendStack:Update(idRaw, patchRaw)
	if didUpdate then
		self.catchUpPlayerBehavior:Reset()
		self.roomBehavior:Reset()
	end
	return didUpdate
end

function SideView.RemoveOverride(self: SideView, idRaw: any): boolean
	local didRemove = self.backendStack:Remove(idRaw)
	if didRemove then
		self.catchUpPlayerBehavior:Reset()
		self.roomBehavior:Reset()
	end
	return didRemove
end

function SideView.ClearOverrides(self: SideView)
	self.backendStack:Clear()
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
end

function SideView.SetTemporaryTargetOverride(self: SideView, targetRaw: any?, durationSecondsRaw: any?)
	self.backendTarget:SetTemporaryOverride(targetRaw, durationSecondsRaw)
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
end

function SideView.ClearTemporaryTargetOverride(self: SideView)
	self.backendTarget:ClearTemporaryOverride()
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
end

function SideView.GetBackendState(self: SideView): { [string]: any }
	local stateSnapshot = self.backendState:GetSnapshot()
	local cacheSnapshot = self.backendCache:GetDebugState()
	local overrideEntries = self.backendStack:GetEntries(os.clock())
	local targetSnapshot = self.backendTarget:Get({
		character = self.character,
	})

	return {
		state = stateSnapshot,
		cache = cacheSnapshot,
		overrides = overrideEntries,
		target = targetSnapshot,
		lastResolution = self.lastResolution,
	}
end

function SideView.SnapToTarget(self: SideView)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local resolution = self:GetGoal(camera, 0)
	if resolution.cameraCFrame == nil then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = resolution.cameraCFrame
	camera.FieldOfView = resolution.fieldOfView
	self.cameraMotion:immediate(resolution.cameraCFrame)
	self.fovMotion:immediate(resolution.fieldOfView)
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
end

function SideView.Enable(self: SideView)
	if self.enabled then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera then
		self.lastCameraType = camera.CameraType
		self.lastFieldOfView = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		self.cameraMotion:immediate(camera.CFrame)
		self.fovMotion:immediate(camera.FieldOfView)
	end
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
	self.backendState:SetEnabled(true)

	self.enabled = true
	RunService:BindToRenderStep(self.renderStepName, SIDE_VIEW_RENDER_PRIORITY, function(deltaTime)
		self:Update(deltaTime)
	end)
	self.janitor:GiveChore(function()
		RunService:UnbindFromRenderStep(self.renderStepName)
	end)
end

function SideView.Disable(self: SideView)
	if not self.enabled then
		return
	end

	self.enabled = false
	self.backendState:SetEnabled(false)
	self.janitor:Clean()
	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()

	local camera = Workspace.CurrentCamera
	if camera then
		if self.lastCameraType then
			camera.CameraType = self.lastCameraType
		end
		if self.lastFieldOfView then
			camera.FieldOfView = self.lastFieldOfView
		end
	end
end

function SideView.Update(self: SideView, deltaTime: number?)
	if not self.enabled then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local resolution = self:GetGoal(camera, deltaTime)
	if resolution.cameraCFrame == nil then
		return
	end

	local currentCFrame = self.cameraMotion:get()
	local GotCameraSpring =
		self.catchUpPlayerBehavior:GetSpring(self.cameraSpring, currentCFrame, resolution.cameraCFrame, deltaTime)

	self.cameraMotion:spring(resolution.cameraCFrame, GotCameraSpring)
	self.fovMotion:spring(resolution.fieldOfView, self.fovSpring)

	local dt = deltaTime or (1 / 60)
	camera.CFrame = self.cameraMotion:step(dt)
	camera.FieldOfView = self.fovMotion:step(dt)
end

function SideView.ApplyConfig(self: SideView, config: SideViewConfig)
	if config.distance then
		self.distance = config.distance
	end
	if config.height then
		self.height = config.height
	end
	if config.lookHeight then
		self.lookHeight = config.lookHeight
	end
	if config.sideSign then
		self.sideSign = math.sign(config.sideSign)
		if self.sideSign == 0 then
			self.sideSign = 1
		end
	end
	if config.fieldOfView then
		self.fieldOfView = config.fieldOfView
	end
	if config.movementBackAmount ~= nil then
		self.movementBackAmount = math.max(config.movementBackAmount, 0)
	end
	if config.movementSpeedForMaxBack ~= nil then
		self.movementSpeedForMaxBack = math.max(config.movementSpeedForMaxBack, 0.01)
	end
	if config.movementBackSign ~= nil then
		self.movementBackSign = math.sign(config.movementBackSign)
		if self.movementBackSign == 0 then
			self.movementBackSign = 1
		end
	end
	if config.mouseInfluenceX ~= nil then
		self.mouseInfluenceX = math.max(config.mouseInfluenceX, 0)
	end
	if config.mouseInfluenceY ~= nil then
		self.mouseInfluenceY = math.max(config.mouseInfluenceY, 0)
	end
	if config.cameraSpring then
		self.cameraSpring = config.cameraSpring
	end
	if config.fovSpring then
		self.fovSpring = config.fovSpring
	end
	if (config :: any).room ~= nil then
		self.roomBehavior:ApplyConfig((config :: any).room)
	end

	local catchUpPlayerConfig = (config :: any).catchUpPlayer
	if catchUpPlayerConfig ~= nil then
		self.catchUpPlayerBehavior:ApplyConfig(catchUpPlayerConfig)
	end

	local predictConfig = (config :: any).predict
	if predictConfig ~= nil then
		self.backendPredict:ApplyConfig(predictConfig)
	end

	self.catchUpPlayerBehavior:Reset()
	self.roomBehavior:Reset()
end

function SideView.Init(self: SideView, target: any?, config: SideViewConfig?, options: SideViewInitOptions?)
	self:SetTarget(target)

	if config then
		self:ApplyConfig(config)
	end

	local snapToTarget = if options and options.snapToTarget ~= nil then options.snapToTarget else false
	if snapToTarget then
		self:SnapToTarget()
	end

	self:Enable()
	if not snapToTarget then
		self:Update(1 / 60)
	end
end

function SideView.Destroy(self: SideView)
	self:Disable()
	self:ClearOverrides()
	self:ClearTemporaryTargetOverride()
	self.cameraMotion:destroy()
	self.fovMotion:destroy()
	self.janitor:Destroy()
end
return SideView
