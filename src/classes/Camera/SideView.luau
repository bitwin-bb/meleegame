local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ripple = require(ReplicatedStorage.Packages.Ripple)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local CatchUpPlayer = require(script.Parent.Behavior.catchUpPlayer)
local RoomBehavior = require(script.Parent.Behavior.room)

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
}

export type SideViewInitOptions = {
	snapToTarget: boolean?,
}

export type SideView = typeof(setmetatable(
	{} :: {
		enabled: boolean,
		target: BasePart?,
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
		cameraMotion: Motion<CFrame>,
		fovMotion: Motion<number>,
		janitor: JanitorClass,
		lastCameraType: Enum.CameraType?,
		lastFieldOfView: number?,
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

local DEFAULT_SIDE_VIEW_CONFIG = Configs.cameraData :: SideViewConfig
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

function SideView.new(config: SideViewConfig?): SideView
	local camera = Workspace.CurrentCamera
	local startCFrame = if camera then camera.CFrame else CFrame.new()
	local startFov = if camera then camera.FieldOfView else 40
	sideViewInstanceCount += 1

	local self = setmetatable({
		enabled = false,
		target = nil,
		renderStepName = ("SideViewCameraUpdate_%d"):format(sideViewInstanceCount),
		distance = if config and config.distance then config.distance else (DEFAULT_SIDE_VIEW_CONFIG.distance :: number),
		height = if config and config.height then config.height else (DEFAULT_SIDE_VIEW_CONFIG.height :: number),
		lookHeight = if config and config.lookHeight
			then config.lookHeight
			else (DEFAULT_SIDE_VIEW_CONFIG.lookHeight :: number),
		sideSign = if config and config.sideSign
			then math.sign(config.sideSign)
			else math.sign(DEFAULT_SIDE_VIEW_CONFIG.sideSign :: number),
		fieldOfView = if config and config.fieldOfView
			then config.fieldOfView
			else (DEFAULT_SIDE_VIEW_CONFIG.fieldOfView :: number),
		movementBackAmount = if config and config.movementBackAmount
			then config.movementBackAmount
			else (DEFAULT_SIDE_VIEW_CONFIG.movementBackAmount :: number),
		movementSpeedForMaxBack = if config and config.movementSpeedForMaxBack
			then config.movementSpeedForMaxBack
			else (DEFAULT_SIDE_VIEW_CONFIG.movementSpeedForMaxBack :: number),
		movementBackSign = if config and config.movementBackSign
			then math.sign(config.movementBackSign)
			else math.sign(DEFAULT_SIDE_VIEW_CONFIG.movementBackSign :: number),
		mouseInfluenceX = if config and config.mouseInfluenceX
			then config.mouseInfluenceX
			else (DEFAULT_SIDE_VIEW_CONFIG.mouseInfluenceX :: number),
		mouseInfluenceY = if config and config.mouseInfluenceY
			then config.mouseInfluenceY
			else (DEFAULT_SIDE_VIEW_CONFIG.mouseInfluenceY :: number),
		cameraSpring = if config and config.cameraSpring
			then config.cameraSpring
			else (DEFAULT_SIDE_VIEW_CONFIG.cameraSpring or DEFAULT_CAMERA_SPRING),
		fovSpring = if config and config.fovSpring
			then config.fovSpring
			else (DEFAULT_SIDE_VIEW_CONFIG.fovSpring or DEFAULT_FOV_SPRING),
		catchUpPlayerBehavior = CatchUpPlayer.new(if config then (config :: any).catchUpPlayer else nil),
		roomBehavior = RoomBehavior.new(if config then (config :: any).room else nil),
		cameraMotion = Ripple.createMotion(startCFrame),
		fovMotion = Ripple.createMotion(startFov),
		janitor = Janitor.new(),
		lastCameraType = nil,
		lastFieldOfView = nil,
	}, SideView)

	if self.sideSign == 0 then
		self.sideSign = 1
	end
	if self.movementBackSign == 0 then
		self.movementBackSign = 1
	end

	return self
end

function SideView.resolveDynamicViewConfig(self: SideView): RoomBehavior.ViewConfig
	local baseViewConfig: RoomBehavior.ViewConfig = {
		distance = self.distance,
		height = self.height,
		lookHeight = self.lookHeight,
		fieldOfView = self.fieldOfView,
	}

	local target = self.target
	if target == nil then
		return baseViewConfig
	end

	return self.roomBehavior:resolveViewConfig(baseViewConfig, target.Position)
end

function SideView.getTargetCFrame(self: SideView, camera: Camera, viewConfig: RoomBehavior.ViewConfig): CFrame
	local target = self.target :: BasePart
	local targetPosition = target.Position
	local sidewaysSpeed = math.abs(target.AssemblyLinearVelocity.Z)
	local speedAlpha = if self.movementSpeedForMaxBack > 0
		then math.clamp(sidewaysSpeed / self.movementSpeedForMaxBack, 0, 1)
		else 0
	local movementBackOffset = self.movementBackAmount * speedAlpha * self.movementBackSign

	local baseCameraPosition = targetPosition + Vector3.new(viewConfig.distance * self.sideSign, viewConfig.height, 0)
	local baseLookPosition = targetPosition + Vector3.new(0, viewConfig.lookHeight, 0)
	local cameraToLook = baseCameraPosition - baseLookPosition
	local backDirection = if cameraToLook.Magnitude > 0 then cameraToLook.Unit else Vector3.new(self.sideSign, 0, 0)
	local cameraPositionWithMovementBack = baseCameraPosition + (backDirection * movementBackOffset)
	local baseCFrame = CFrame.lookAt(baseCameraPosition, baseLookPosition)

	local mouseNormalized = getMouseViewportNormalized(camera)
	local mouseOffset = (baseCFrame.RightVector * (mouseNormalized.X * self.mouseInfluenceX))
		+ (baseCFrame.UpVector * (-mouseNormalized.Y * self.mouseInfluenceY))

	local cameraPosition = cameraPositionWithMovementBack + mouseOffset
	local lookPosition = baseLookPosition + mouseOffset
	return CFrame.lookAt(cameraPosition, lookPosition)
end

function SideView.setTarget(self: SideView, target: BasePart)
	self.target = target
	self.catchUpPlayerBehavior:reset()
	self.roomBehavior:reset()
end

function SideView.snapToTarget(self: SideView)
	local target = self.target
	local camera = Workspace.CurrentCamera
	if not target or not target.Parent or not camera then
		return
	end

	local resolvedViewConfig = self:resolveDynamicViewConfig()
	local targetCFrame = self:getTargetCFrame(camera, resolvedViewConfig)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = targetCFrame
	camera.FieldOfView = resolvedViewConfig.fieldOfView
	self.cameraMotion:immediate(targetCFrame)
	self.fovMotion:immediate(resolvedViewConfig.fieldOfView)
	self.catchUpPlayerBehavior:reset()
	self.roomBehavior:reset()
end

function SideView.enable(self: SideView)
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
	self.catchUpPlayerBehavior:reset()
	self.roomBehavior:reset()

	self.enabled = true
	RunService:BindToRenderStep(self.renderStepName, SIDE_VIEW_RENDER_PRIORITY, function(deltaTime)
		self:update(deltaTime)
	end)
	self.janitor:GiveChore(function()
		RunService:UnbindFromRenderStep(self.renderStepName)
	end)
end

function SideView.disable(self: SideView)
	if not self.enabled then
		return
	end

	self.enabled = false
	self.janitor:Clean()
	self.catchUpPlayerBehavior:reset()
	self.roomBehavior:reset()

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

function SideView.update(self: SideView, deltaTime: number?)
	if not self.enabled or not self.target then
		return
	end
	if not self.target.Parent then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local resolvedViewConfig = self:resolveDynamicViewConfig()
	local targetCFrame = self:getTargetCFrame(camera, resolvedViewConfig)
	local currentCFrame = self.cameraMotion:get()
	local resolvedCameraSpring =
		self.catchUpPlayerBehavior:resolveSpring(self.cameraSpring, currentCFrame, targetCFrame, deltaTime)

	self.cameraMotion:spring(targetCFrame, resolvedCameraSpring)
	self.fovMotion:spring(resolvedViewConfig.fieldOfView, self.fovSpring)

	local dt = deltaTime or (1 / 60)
	camera.CFrame = self.cameraMotion:step(dt)
	camera.FieldOfView = self.fovMotion:step(dt)
end

function SideView.applyConfig(self: SideView, config: SideViewConfig)
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
		self.roomBehavior:applyConfig((config :: any).room)
	end

	local catchUpPlayerConfig = (config :: any).catchUpPlayer
	if catchUpPlayerConfig ~= nil then
		self.catchUpPlayerBehavior:applyConfig(catchUpPlayerConfig)
	end
	self.roomBehavior:reset()
end

function SideView.init(self: SideView, target: BasePart, config: SideViewConfig?, options: SideViewInitOptions?)
	self:setTarget(target)

	if config then
		self:applyConfig(config)
	end

	local snapToTarget = if options and options.snapToTarget ~= nil then options.snapToTarget else false
	if snapToTarget then
		self:snapToTarget()
	end

	self:enable()
	if not snapToTarget then
		self:update(1 / 60)
	end
end

function SideView.destroy(self: SideView)
	self:disable()
	self.cameraMotion:destroy()
	self.fovMotion:destroy()
	self.janitor:Destroy()
end

return SideView
