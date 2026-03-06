--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local HUDScaler = {}
HUDScaler.__index = HUDScaler

export type ScalePreset = {
	scale: number?,
	offsetScale: number?,
	safePadding: Vector2?,
}

export type ElementConfig = {
	id: string?,
	gui: GuiObject,
	scaleSizeOffsets: boolean?,
	scalePositionOffsets: boolean?,
	minScale: number?,
	maxScale: number?,
	onApply: ((gui: GuiObject, scale: number, deviceType: string) -> ())?,
}

export type HUDScalerConfig = {
	platform: any?,
	layoutEngine: any?,
	eventBus: any?,
	eventChannel: string?,
	scaleEvent: string?,
	referenceHeight: number?,
	minScale: number?,
	maxScale: number?,
	presets: { [string]: ScalePreset }?,
}

type ElementRecord = {
	id: string,
	gui: GuiObject,
	baseSize: UDim2,
	basePosition: UDim2,
	scaleSizeOffsets: boolean,
	scalePositionOffsets: boolean,
	minScale: number,
	maxScale: number,
	onApply: ((gui: GuiObject, scale: number, deviceType: string) -> ())?,
}

export type HUDScaler = typeof(setmetatable({} :: any, HUDScaler))

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function normalizeEventName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

local function round(value: number): number
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

local function detectDeviceType(platform: any?): string
	if platform ~= nil and typeof(platform.getPrimaryInputType) == "function" then
		local primaryInputType = platform:getPrimaryInputType()
		if primaryInputType == "Touch" then
			return "Mobile"
		end
		if primaryInputType == "Gamepad" then
			return "Console"
		end
		return "Desktop"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Mobile"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Console"
	end
	return "Desktop"
end

function HUDScaler.new(configRaw: HUDScalerConfig?): HUDScaler
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		platform = config.platform,
		layoutEngine = config.layoutEngine,
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "hud.scaler"),
		scaleEvent = normalizeEventName(config.scaleEvent, "applied"),
		referenceHeight = clampNumber(config.referenceHeight, 1080, 100, 10000),
		minScale = clampNumber(config.minScale, 0.75, 0.1, 5),
		maxScale = clampNumber(config.maxScale, 1.5, 0.1, 5),
		presets = {
			Desktop = {
				scale = 1,
				offsetScale = 1,
				safePadding = Vector2.new(8, 8),
			},
			Mobile = {
				scale = 1.12,
				offsetScale = 1.08,
				safePadding = Vector2.new(12, 12),
			},
			Console = {
				scale = 1.04,
				offsetScale = 1,
				safePadding = Vector2.new(16, 16),
			},
		} :: { [string]: ScalePreset },
		elements = {} :: { [string]: ElementRecord },
		orderedIds = {} :: { string },
		nextElementId = 0,
		connections = {} :: { RBXScriptConnection? },
		platformDisconnect = nil :: (() -> ())?,
		isInitialized = false,
		lastScale = 1,
		lastDeviceType = "Desktop",
		lastViewport = Vector2.zero,
	}, HUDScaler)

	if typeof(config.presets) == "table" then
		for key, value in config.presets do
			if typeof(key) == "string" and typeof(value) == "table" then
				self.presets[key] = value
			end
		end
	end

	return self
end

function HUDScaler._getViewport(self: HUDScaler): Vector2
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Vector2.new(1920, 1080)
	end
	local size = camera.ViewportSize
	return Vector2.new(math.max(1, size.X), math.max(1, size.Y))
end

function HUDScaler._computeScale(self: HUDScaler): (number, string, ScalePreset, Vector2, Vector2)
	local viewport = self:_getViewport()
	local deviceType = detectDeviceType(self.platform)
	local preset = self.presets[deviceType] or self.presets.Desktop
	local baseScale = viewport.Y / self.referenceHeight
	local presetScale = clampNumber(preset.scale, 1, 0.1, 10)
	local scale = clampNumber(baseScale * presetScale, 1, self.minScale, self.maxScale)
	local safeTopLeft, safeBottomRight = GuiService:GetGuiInset()
	return scale, deviceType, preset, safeTopLeft, safeBottomRight
end

function HUDScaler._applyRecord(self: HUDScaler, record: ElementRecord, scale: number, preset: ScalePreset, safeTopLeft: Vector2, safeBottomRight: Vector2, viewport: Vector2)
	local gui = record.gui
	if gui.Parent == nil then
		return
	end

	local offsetScale = clampNumber(preset.offsetScale, 1, 0.1, 10)
	local finalScale = clampNumber(scale, scale, record.minScale, record.maxScale)
	local safePadding = if typeof(preset.safePadding) == "Vector2" then preset.safePadding else Vector2.new(0, 0)

	local size = record.baseSize
	if record.scaleSizeOffsets then
		size = UDim2.new(
			size.X.Scale,
			round(size.X.Offset * finalScale),
			size.Y.Scale,
			round(size.Y.Offset * finalScale)
		)
	end
	gui.Size = size

	local position = record.basePosition
	if record.scalePositionOffsets then
		position = UDim2.new(
			position.X.Scale,
			round(position.X.Offset * finalScale * offsetScale),
			position.Y.Scale,
			round(position.Y.Offset * finalScale * offsetScale)
		)
	end

	local anchor = gui.AnchorPoint
	local safeOffsetX = 0
	local safeOffsetY = 0
	if anchor.X <= 0.5 then
		safeOffsetX = safeTopLeft.X + safePadding.X
	else
		safeOffsetX = -(safeBottomRight.X + safePadding.X)
	end
	if anchor.Y <= 0.5 then
		safeOffsetY = safeTopLeft.Y + safePadding.Y
	else
		safeOffsetY = -(safeBottomRight.Y + safePadding.Y)
	end

	gui.Position = UDim2.new(
		position.X.Scale,
		position.X.Offset + safeOffsetX,
		position.Y.Scale,
		position.Y.Offset + safeOffsetY
	)

	if record.onApply ~= nil then
		record.onApply(gui, finalScale, self.lastDeviceType)
	end
end

function HUDScaler._syncLayoutEngine(self: HUDScaler, viewport: Vector2, deviceType: string)
	local layoutEngine = self.layoutEngine
	if layoutEngine == nil then
		return
	end
	local layoutEngineAny = layoutEngine :: any
	if typeof((layoutEngine :: any).setViewport) == "function" then
		layoutEngineAny:setViewport(viewport)
	end
	if typeof((layoutEngine :: any).setGamepadMode) == "function" then
		layoutEngineAny:setGamepadMode(deviceType == "Console")
	end
	if typeof((layoutEngine :: any).reflow) == "function" then
		layoutEngineAny:reflow()
	end
end

function HUDScaler.apply(self: HUDScaler)
	local scale, deviceType, preset, safeTopLeft, safeBottomRight = self:_computeScale()
	local viewport = self:_getViewport()
	self.lastScale = scale
	self.lastDeviceType = deviceType
	self.lastViewport = viewport

	for index = 1, #self.orderedIds do
		local id = self.orderedIds[index]
		local record = self.elements[id]
		if record ~= nil then
			self:_applyRecord(record, scale, preset, safeTopLeft, safeBottomRight, viewport)
		end
	end

	self:_syncLayoutEngine(viewport, deviceType)

	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.scaleEvent, {
			scale = scale,
			deviceType = deviceType,
			viewport = viewport,
		})
	end
end

function HUDScaler.init(self: HUDScaler)
	if self.isInitialized then
		return
	end
	self.isInitialized = true

	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		self.connections[#self.connections + 1] = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:apply()
		end)
	end
	self.connections[#self.connections + 1] = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:apply()
	end)

	if self.platform ~= nil and typeof((self.platform :: any).onChanged) == "function" then
		self.platformDisconnect = (self.platform :: any):onChanged(function()
			self:apply()
		end)
	end

	self:apply()
end

function HUDScaler.register(self: HUDScaler, configRaw: ElementConfig): string?
	if typeof(configRaw) ~= "table" then
		return nil
	end
	if typeof(configRaw.gui) ~= "Instance" or not configRaw.gui:IsA("GuiObject") then
		return nil
	end
	local gui = configRaw.gui :: GuiObject
	local id = if typeof(configRaw.id) == "string" and configRaw.id ~= "" then configRaw.id else nil
	if id == nil then
		self.nextElementId += 1
		id = string.format("element_%d", self.nextElementId)
	end

	local record: ElementRecord = {
		id = id,
		gui = gui,
		baseSize = gui.Size,
		basePosition = gui.Position,
		scaleSizeOffsets = if configRaw.scaleSizeOffsets == nil then true else configRaw.scaleSizeOffsets == true,
		scalePositionOffsets = if configRaw.scalePositionOffsets == nil then true else configRaw.scalePositionOffsets == true,
		minScale = clampNumber(configRaw.minScale, self.minScale, 0.1, 5),
		maxScale = clampNumber(configRaw.maxScale, self.maxScale, 0.1, 5),
		onApply = if typeof(configRaw.onApply) == "function" then configRaw.onApply else nil,
	}

	if self.elements[id] == nil then
		self.orderedIds[#self.orderedIds + 1] = id
	end
	self.elements[id] = record
	return id
end

function HUDScaler.unregister(self: HUDScaler, idRaw: any): boolean
	if typeof(idRaw) ~= "string" then
		return false
	end
	if self.elements[idRaw] == nil then
		return false
	end
	self.elements[idRaw] = nil
	for index = #self.orderedIds, 1, -1 do
		if self.orderedIds[index] == idRaw then
			table.remove(self.orderedIds, index)
			break
		end
	end
	return true
end

function HUDScaler.setPreset(self: HUDScaler, deviceTypeRaw: any, presetRaw: any): boolean
	if typeof(deviceTypeRaw) ~= "string" or deviceTypeRaw == "" then
		return false
	end
	if typeof(presetRaw) ~= "table" then
		return false
	end
	self.presets[deviceTypeRaw] = presetRaw
	return true
end

function HUDScaler.getScale(self: HUDScaler): number
	return self.lastScale
end

function HUDScaler.getDeviceType(self: HUDScaler): string
	return self.lastDeviceType
end

function HUDScaler.destroy(self: HUDScaler)
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	if self.platformDisconnect ~= nil then
		self.platformDisconnect()
		self.platformDisconnect = nil
	end
	table.clear(self.elements)
	table.clear(self.orderedIds)
	self.isInitialized = false
end

HUDScaler.Register = HUDScaler.register
HUDScaler.Unregister = HUDScaler.unregister
HUDScaler.SetPreset = HUDScaler.setPreset
HUDScaler.GetScale = HUDScaler.getScale
HUDScaler.GetDeviceType = HUDScaler.getDeviceType
HUDScaler.Apply = HUDScaler.apply
HUDScaler.Init = HUDScaler.init
HUDScaler.Destroy = HUDScaler.destroy

return HUDScaler
