--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseUIScaling = require(script:FindFirstAncestor("game").Shared.Modules.UI.UIScaling)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PlatformServiceUtils = require(script.Parent.PlatformServiceUtils)
local Signal = require(ReplicatedStorage.Packages.Signal)

type PlatformState = PlatformServiceUtils.PlatformState
type PlatformKind = PlatformServiceUtils.PlatformKind
type DeviceClass = PlatformServiceUtils.DeviceClass
type BaseUISnapshot = BaseUIScaling.UISnapshot

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type ChangedSignal = {
	Connect: (self: ChangedSignal, callback: (snapshot: UIScaleSnapshot) -> ()) -> SignalConnection,
	Fire: (self: ChangedSignal, snapshot: UIScaleSnapshot) -> (),
	DisconnectAll: (self: ChangedSignal) -> (),
	Destroy: (self: ChangedSignal) -> (),
}

export type DevicePreset = {
	uiScale: number,
	offsetScale: number,
	safePadding: Vector2,
	minimumTouchTarget: Vector2,
	textMin: number,
	textMax: number,
	layoutSpacingScale: number,
}

export type UIScaleSnapshot = {
	platform: PlatformKind,
	deviceClass: DeviceClass,
	viewport: Vector2,
	guiSize: Vector2,
	safeTopLeft: Vector2,
	safeBottomRight: Vector2,
	safePadding: Vector2,
	effectiveScale: number,
	minimumTouchTarget: Vector2,
	baseSnapshot: BaseUISnapshot,
}

export type UIScaleConfig = {
	platformService: any?,
	screenGui: ScreenGui?,
	scaleTarget: GuiObject?,
}

local PlatformUIScale = {}
PlatformUIScale.__index = PlatformUIScale

local DEFAULT_PRESETS: { [DeviceClass]: DevicePreset } = {
	Phone = {
		uiScale = 1.08,
		offsetScale = 1.06,
		safePadding = Vector2.new(18, 18),
		minimumTouchTarget = Vector2.new(56, 56),
		textMin = 12,
		textMax = 40,
		layoutSpacingScale = 1.1,
	},
	Tablet = {
		uiScale = 1.02,
		offsetScale = 1.02,
		safePadding = Vector2.new(22, 22),
		minimumTouchTarget = Vector2.new(52, 52),
		textMin = 12,
		textMax = 42,
		layoutSpacingScale = 1.06,
	},
	Desktop = {
		uiScale = 1,
		offsetScale = 1,
		safePadding = Vector2.new(8, 8),
		minimumTouchTarget = Vector2.new(44, 44),
		textMin = 12,
		textMax = 42,
		layoutSpacingScale = 1,
	},
	Console = {
		uiScale = 1.16,
		offsetScale = 1.04,
		safePadding = Vector2.new(28, 28),
		minimumTouchTarget = Vector2.new(60, 60),
		textMin = 14,
		textMax = 48,
		layoutSpacingScale = 1.14,
	},
}

local FALLBACK_PLATFORM_STATE: PlatformState = {
	platform = "KeyboardMouse",
	deviceClass = "Desktop",
	preferredInputName = "",
	lastInputTypeName = "",
	viewport = Vector2.new(1920, 1080),
	isTenFootInterface = false,
	touchEnabled = false,
	keyboardEnabled = true,
	mouseEnabled = true,
	gamepadEnabled = false,
	basePrimaryInputType = "KeyboardMouse",
}

local function clonePreset(preset: DevicePreset): DevicePreset
	return {
		uiScale = preset.uiScale,
		offsetScale = preset.offsetScale,
		safePadding = preset.safePadding,
		minimumTouchTarget = preset.minimumTouchTarget,
		textMin = preset.textMin,
		textMax = preset.textMax,
		layoutSpacingScale = preset.layoutSpacingScale,
	}
end

local function cloneSnapshot(snapshot: UIScaleSnapshot): UIScaleSnapshot
	return {
		platform = snapshot.platform,
		deviceClass = snapshot.deviceClass,
		viewport = snapshot.viewport,
		guiSize = snapshot.guiSize,
		safeTopLeft = snapshot.safeTopLeft,
		safeBottomRight = snapshot.safeBottomRight,
		safePadding = snapshot.safePadding,
		effectiveScale = snapshot.effectiveScale,
		minimumTouchTarget = snapshot.minimumTouchTarget,
		baseSnapshot = snapshot.baseSnapshot,
	}
end

local function snapshotsEqual(a: UIScaleSnapshot?, b: UIScaleSnapshot?): boolean
	if a == nil or b == nil then
		return false
	end
	return a.platform == b.platform
		and a.deviceClass == b.deviceClass
		and a.viewport == b.viewport
		and a.guiSize == b.guiSize
		and a.safeTopLeft == b.safeTopLeft
		and a.safeBottomRight == b.safeBottomRight
		and a.safePadding == b.safePadding
		and a.effectiveScale == b.effectiveScale
		and a.minimumTouchTarget == b.minimumTouchTarget
end

local function shouldApplyForPlatformChange(nextStateRaw: any, prevStateRaw: any): boolean
	if typeof(nextStateRaw) ~= "table" or typeof(prevStateRaw) ~= "table" then
		return true
	end
	local nextState = nextStateRaw :: { [string]: any }
	local prevState = prevStateRaw :: { [string]: any }
	return nextState.platform ~= prevState.platform
		or nextState.deviceClass ~= prevState.deviceClass
		or nextState.viewport ~= prevState.viewport
		or nextState.isTenFootInterface ~= prevState.isTenFootInterface
end

local function baseDeviceTypeFromClass(deviceClass: DeviceClass): string
	if deviceClass == "Console" then
		return "Console"
	end
	if deviceClass == "Phone" or deviceClass == "Tablet" then
		return "Mobile"
	end
	return "Desktop"
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

function PlatformUIScale.New(configRaw: UIScaleConfig?): typeof(setmetatable({} :: any, PlatformUIScale))
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		platformService = config.platformService,
		screenGui = if typeof(config.screenGui) == "Instance" and config.screenGui:IsA("ScreenGui")
			then config.screenGui
			else nil,
		scaleTarget = if typeof(config.scaleTarget) == "Instance" and config.scaleTarget:IsA("GuiObject")
			then config.scaleTarget
			else nil,
		presets = {
			Phone = clonePreset(DEFAULT_PRESETS.Phone),
			Tablet = clonePreset(DEFAULT_PRESETS.Tablet),
			Desktop = clonePreset(DEFAULT_PRESETS.Desktop),
			Console = clonePreset(DEFAULT_PRESETS.Console),
		} :: { [DeviceClass]: DevicePreset },
		baseScaler = BaseUIScaling.new({
			ignoreGuiInset = true,
		}),
		rootScale = nil :: UIScale?,
		changed = Signal.new() :: ChangedSignal,
		janitor = Janitor.new() :: JanitorClass,
		screenGuiConnection = nil :: RBXScriptConnection?,
		cameraViewportConnection = nil :: RBXScriptConnection?,
		cameraChangedConnection = nil :: RBXScriptConnection?,
		platformDisconnect = nil :: (() -> ())?,
		lastSnapshot = nil :: UIScaleSnapshot?,
		appliedBasePresetDeviceClass = nil :: DeviceClass?,
		isInitialized = false,
	}, PlatformUIScale)
	return self
end

function PlatformUIScale._getPlatformState(self: typeof(setmetatable({} :: any, PlatformUIScale))): PlatformState
	local platformService = self.platformService
	if platformService ~= nil and typeof((platformService :: any).getState) == "function" then
		local ok, state = pcall(function()
			return (platformService :: any):getState()
		end)
		if ok and typeof(state) == "table" then
			return PlatformServiceUtils.clonePlatformState(state :: PlatformState)
		end
	end
	return PlatformServiceUtils.clonePlatformState(FALLBACK_PLATFORM_STATE)
end

function PlatformUIScale._getPreset(
	self: typeof(setmetatable({} :: any, PlatformUIScale)),
	deviceClass: DeviceClass
): DevicePreset
	return clonePreset(self.presets[deviceClass] or DEFAULT_PRESETS.Desktop)
end

function PlatformUIScale._applyPresetToBaseScaler(
	self: typeof(setmetatable({} :: any, PlatformUIScale)),
	deviceClass: DeviceClass
)
	if self.appliedBasePresetDeviceClass == deviceClass then
		return
	end
	self.appliedBasePresetDeviceClass = deviceClass
	local preset = self:_getPreset(deviceClass)
	local baseDeviceType = baseDeviceTypeFromClass(deviceClass)
	self.baseScaler:setPreset(baseDeviceType, {
		uiScale = preset.uiScale,
		offsetScale = preset.offsetScale,
		safePadding = preset.safePadding,
		textMin = preset.textMin,
		textMax = preset.textMax,
		layoutSpacingScale = preset.layoutSpacingScale,
	})
end

function PlatformUIScale._destroyScreenGuiRootScale(self: typeof(setmetatable({} :: any, PlatformUIScale)))
	local screenGui = self.screenGui
	if screenGui == nil then
		return
	end

	local staleScale = screenGui:FindFirstChild("PlatformServiceRootScale")
	if staleScale ~= nil then
		if staleScale == self.rootScale then
			self.rootScale = nil
		end
		staleScale:Destroy()
	end
end

function PlatformUIScale._ensureRootScale(self: typeof(setmetatable({} :: any, PlatformUIScale))): UIScale?
	local target = self.scaleTarget
	if target == nil then
		return nil
	end
	local existing = self.rootScale
	if existing ~= nil and existing.Parent == target then
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end
	local existingScale = target:FindFirstChild("PlatformServiceRootScale")
	if existingScale ~= nil and existingScale:IsA("UIScale") then
		self.rootScale = existingScale
		return existingScale
	end
	if existingScale ~= nil then
		existingScale:Destroy()
	end
	local scale = Instance.new("UIScale")
	scale.Name = "PlatformServiceRootScale"
	scale.Parent = target
	self.rootScale = scale
	return scale
end

function PlatformUIScale._bindCameraViewport(self: typeof(setmetatable({} :: any, PlatformUIScale)))
	safeDisconnect(self.cameraViewportConnection)
	self.cameraViewportConnection = nil
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	self.cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:apply()
	end)
end

function PlatformUIScale._bindScreenGui(self: typeof(setmetatable({} :: any, PlatformUIScale)))
	safeDisconnect(self.screenGuiConnection)
	self.screenGuiConnection = nil
	if self.screenGui == nil then
		return
	end
	self.screenGui.IgnoreGuiInset = true
	self.baseScaler:setScreenGui(self.screenGui)
	self.screenGuiConnection = self.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:apply()
	end)
end

function PlatformUIScale._applyScaleTargetSafeArea(
	self: typeof(setmetatable({} :: any, PlatformUIScale)),
	safeTopLeft: Vector2,
	safeBottomRight: Vector2,
	safePadding: Vector2
)
	local target = self.scaleTarget
	if target == nil then
		return
	end
	local horizontalInset = safeTopLeft.X + safeBottomRight.X + safePadding.X * 2
	local verticalInset = safeTopLeft.Y + safeBottomRight.Y + safePadding.Y * 2
	local nextAnchorPoint = Vector2.new(0.5, 0.5)
	local nextPosition = UDim2.fromScale(0.5, 0.5)
	local nextSize = UDim2.new(1, -math.floor(horizontalInset + 0.5), 1, -math.floor(verticalInset + 0.5))
	if target.AnchorPoint ~= nextAnchorPoint then
		target.AnchorPoint = nextAnchorPoint
	end
	if target.Position ~= nextPosition then
		target.Position = nextPosition
	end
	if target.Size ~= nextSize then
		target.Size = nextSize
	end
end

function PlatformUIScale.Init(self: typeof(setmetatable({} :: any, PlatformUIScale)))
	if self.isInitialized then
		return
	end
	self.isInitialized = true

	self:_bindScreenGui()
	self:_bindCameraViewport()
	self.cameraChangedConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_bindCameraViewport()
		self:apply()
	end)
	self.janitor:GiveChore(function()
		safeDisconnect(self.cameraChangedConnection)
		self.cameraChangedConnection = nil
	end)

	local platformService = self.platformService
	if platformService ~= nil and typeof((platformService :: any).onPlatformChanged) == "function" then
		self.platformDisconnect = (platformService :: any):onPlatformChanged(function(nextState: any, prevState: any)
			if not shouldApplyForPlatformChange(nextState, prevState) then
				return
			end
			self:apply()
		end)
		self.janitor:GiveChore(function()
			if self.platformDisconnect ~= nil then
				self.platformDisconnect()
				self.platformDisconnect = nil
			end
		end)
	end

	self:apply()
end

function PlatformUIScale.Apply(self: typeof(setmetatable({} :: any, PlatformUIScale)))
	local platformState = self:_getPlatformState()
	self:_applyPresetToBaseScaler(platformState.deviceClass)
	if self.screenGui ~= nil then
		self.baseScaler:setScreenGui(self.screenGui)
	end
	self.baseScaler:apply()
	local baseSnapshot = self.baseScaler:getSnapshot()
	local preset = self:_getPreset(platformState.deviceClass)
	local effectiveScale = baseSnapshot.scale * preset.uiScale
	local rootScale = self:_ensureRootScale()
	if rootScale ~= nil then
		if rootScale.Scale ~= effectiveScale then
			rootScale.Scale = effectiveScale
		end
	end
	self:_applyScaleTargetSafeArea(baseSnapshot.safeTopLeft, baseSnapshot.safeBottomRight, preset.safePadding)

	local snapshot: UIScaleSnapshot = {
		platform = platformState.platform,
		deviceClass = platformState.deviceClass,
		viewport = baseSnapshot.viewport,
		guiSize = baseSnapshot.guiSize,
		safeTopLeft = baseSnapshot.safeTopLeft,
		safeBottomRight = baseSnapshot.safeBottomRight,
		safePadding = preset.safePadding,
		effectiveScale = effectiveScale,
		minimumTouchTarget = preset.minimumTouchTarget,
		baseSnapshot = baseSnapshot,
	}
	if snapshotsEqual(self.lastSnapshot, snapshot) then
		return
	end
	self.lastSnapshot = snapshot
	self.changed:Fire(cloneSnapshot(snapshot))
end

function PlatformUIScale.SetScreenGui(
	self: typeof(setmetatable({} :: any, PlatformUIScale)),
	screenGuiRaw: any
): boolean
	if typeof(screenGuiRaw) ~= "Instance" or not screenGuiRaw:IsA("ScreenGui") then
		return false
	end
	self.screenGui = screenGuiRaw
	self:_destroyScreenGuiRootScale()
	self:_bindScreenGui()
	if self.isInitialized then
		self:apply()
	end
	return true
end

function PlatformUIScale.SetScaleTarget(self: typeof(setmetatable({} :: any, PlatformUIScale)), targetRaw: any): boolean
	if typeof(targetRaw) ~= "Instance" or not targetRaw:IsA("GuiObject") then
		return false
	end
	self.scaleTarget = targetRaw
	self:_ensureRootScale()
	if self.isInitialized then
		self:apply()
	end
	return true
end

function PlatformUIScale.GetSnapshot(self: typeof(setmetatable({} :: any, PlatformUIScale))): UIScaleSnapshot?
	if self.lastSnapshot == nil then
		self:apply()
	end
	if self.lastSnapshot == nil then
		return nil
	end
	return cloneSnapshot(self.lastSnapshot :: UIScaleSnapshot)
end

function PlatformUIScale.OnChanged(self: typeof(setmetatable({} :: any, PlatformUIScale)), callbackRaw: any): () -> ()
	if typeof(callbackRaw) ~= "function" then
		return function() end
	end
	local connection = self.changed:Connect(callbackRaw)
	return function()
		connection:Disconnect()
	end
end

function PlatformUIScale.Destroy(self: typeof(setmetatable({} :: any, PlatformUIScale)))
	self.janitor:Destroy()
	safeDisconnect(self.screenGuiConnection)
	safeDisconnect(self.cameraViewportConnection)
	self.screenGuiConnection = nil
	self.cameraViewportConnection = nil
	if self.rootScale ~= nil then
		self.rootScale:Destroy()
		self.rootScale = nil
	end
	self.baseScaler:destroy()
	self.changed:DisconnectAll()
	self.changed:Destroy()
	self.lastSnapshot = nil
	self.appliedBasePresetDeviceClass = nil
	self.isInitialized = false
end

PlatformUIScale.New = PlatformUIScale.New
PlatformUIScale.Init = PlatformUIScale.Init
PlatformUIScale.Apply = PlatformUIScale.Apply
PlatformUIScale.SetScreenGui = PlatformUIScale.SetScreenGui
PlatformUIScale.SetScaleTarget = PlatformUIScale.SetScaleTarget
PlatformUIScale.GetSnapshot = PlatformUIScale.GetSnapshot
PlatformUIScale.OnChanged = PlatformUIScale.OnChanged
PlatformUIScale.Destroy = PlatformUIScale.Destroy

PlatformUIScale.new = PlatformUIScale.New
PlatformUIScale.init = PlatformUIScale.Init
PlatformUIScale.apply = PlatformUIScale.Apply
PlatformUIScale.setScreenGui = PlatformUIScale.SetScreenGui
PlatformUIScale.setScaleTarget = PlatformUIScale.SetScaleTarget
PlatformUIScale.getSnapshot = PlatformUIScale.GetSnapshot
PlatformUIScale.onChanged = PlatformUIScale.OnChanged
PlatformUIScale.destroy = PlatformUIScale.Destroy

return PlatformUIScale
