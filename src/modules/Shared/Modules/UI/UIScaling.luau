--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UIScaling = {}
UIScaling.__index = UIScaling

type TextGui = TextLabel | TextButton | TextBox
type LayoutInstance = UIListLayout | UIGridLayout

export type DevicePreset = {
	uiScale: number?,
	offsetScale: number?,
	safePadding: Vector2?,
	textMin: number?,
	textMax: number?,
	layoutSpacingScale: number?,
}

export type AspectRule = {
	minAspect: number?,
	maxAspect: number?,
	sizeMultiplier: Vector2?,
	positionNudge: Vector2?,
	safePadding: Vector2?,
	minSize: Vector2?,
	maxSize: Vector2?,
}

export type TextScalingConfig = {
	enabled: boolean?,
	includeDescendants: boolean?,
	minTextSize: number?,
	maxTextSize: number?,
}

export type AspectConstraintConfig = {
	enabled: boolean?,
	ratio: number?,
	aspectType: Enum.AspectType?,
	dominantAxis: Enum.DominantAxis?,
}

export type ElementConfig = {
	id: string?,
	role: string?,
	gui: GuiObject,
	anchorPoint: Vector2?,
	useSafeZone: boolean?,
	safePadding: Vector2?,
	scaleSizeOffsets: boolean?,
	scalePositionOffsets: boolean?,
	sizeFineOffset: Vector2?,
	positionFineOffset: Vector2?,
	sizeMultiplier: Vector2?,
	positionNudge: Vector2?,
	minSize: Vector2?,
	maxSize: Vector2?,
	text: TextScalingConfig?,
	aspectConstraint: AspectConstraintConfig?,
	aspectRules: { AspectRule }?,
	onApply: ((gui: GuiObject, snapshot: any) -> ())?,
}

export type LayoutConfig = {
	id: string?,
	layout: LayoutInstance,
	scalePaddingOffsets: boolean?,
	scaleCellSizeOffsets: boolean?,
	scaleCellPaddingOffsets: boolean?,
	minCellSize: Vector2?,
	maxCellSize: Vector2?,
}

export type UIScalingConfig = {
	platform: any?,
	screenGui: ScreenGui?,
	ignoreGuiInset: boolean?,
	referenceResolution: Vector2?,
	minGlobalScale: number?,
	maxGlobalScale: number?,
	presets: { [string]: DevicePreset }?,
	aspectRules: { AspectRule }?,
	eventBus: any?,
	eventChannel: string?,
	appliedEvent: string?,
}

export type UISnapshot = {
	viewport: Vector2,
	guiSize: Vector2,
	aspectRatio: number,
	scale: number,
	deviceType: string,
	safeTopLeft: Vector2,
	safeBottomRight: Vector2,
	preset: DevicePreset,
}

type TextRuleRecord = {
	enabled: boolean,
	includeDescendants: boolean,
	minTextSize: number?,
	maxTextSize: number?,
}

type AspectConstraintRecord = {
	enabled: boolean,
	ratio: number,
	aspectType: Enum.AspectType,
	dominantAxis: Enum.DominantAxis,
}

type ElementRecord = {
	id: string,
	role: string?,
	gui: GuiObject,
	baseSize: UDim2,
	basePosition: UDim2,
	anchorPoint: Vector2,
	useSafeZone: boolean,
	safePadding: Vector2,
	scaleSizeOffsets: boolean,
	scalePositionOffsets: boolean,
	sizeFineOffset: Vector2,
	positionFineOffset: Vector2,
	sizeMultiplier: Vector2,
	positionNudge: Vector2,
	minSize: Vector2?,
	maxSize: Vector2?,
	textRule: TextRuleRecord,
	aspectConstraint: AspectConstraintRecord?,
	aspectRules: { AspectRule },
	onApply: ((gui: GuiObject, snapshot: UISnapshot) -> ())?,
}

type LayoutRecord = {
	id: string,
	layout: LayoutInstance,
	basePadding: UDim?,
	baseCellSize: UDim2?,
	baseCellPadding: UDim2?,
	scalePaddingOffsets: boolean,
	scaleCellSizeOffsets: boolean,
	scaleCellPaddingOffsets: boolean,
	minCellSize: Vector2?,
	maxCellSize: Vector2?,
}

export type UIScaling = typeof(setmetatable({} :: any, UIScaling))

local DEFAULT_REFERENCE_RESOLUTION = Vector2.new(1920, 1080)
local VECTOR2_ONE = Vector2.new(1, 1)

local DEFAULT_DEVICE_PRESETS: { [string]: DevicePreset } = {
	Desktop = {
		uiScale = 1.0,
		offsetScale = 1.0,
		safePadding = Vector2.new(8, 8),
		textMin = 12,
		textMax = 42,
		layoutSpacingScale = 1.0,
	},
	Mobile = {
		uiScale = 1.08,
		offsetScale = 1.04,
		safePadding = Vector2.new(14, 14),
		textMin = 11,
		textMax = 40,
		layoutSpacingScale = 1.08,
	},
	Console = {
		uiScale = 1.03,
		offsetScale = 1.0,
		safePadding = Vector2.new(20, 20),
		textMin = 13,
		textMax = 44,
		layoutSpacingScale = 1.12,
	},
}

local DEFAULT_ASPECT_RULES: { AspectRule } = {
	{
		maxAspect = 1.45,
		sizeMultiplier = Vector2.new(1.07, 1.07),
	},
	{
		minAspect = 2.1,
		maxAspect = 2.45,
		sizeMultiplier = Vector2.new(0.95, 1.0),
	},
	{
		minAspect = 2.45,
		sizeMultiplier = Vector2.new(0.9, 1.0),
		positionNudge = Vector2.new(0, 0.01),
	},
}

local ROLE_PRESETS: { [string]: any } = {
	Hotbar = {
		anchorPoint = Vector2.new(0.5, 1),
		useSafeZone = true,
		text = {
			enabled = true,
			includeDescendants = true,
			minTextSize = 11,
			maxTextSize = 28,
		},
		aspectRules = {
			{
				maxAspect = 1.4,
				sizeMultiplier = Vector2.new(1.08, 1.1),
				positionNudge = Vector2.new(0, -0.02),
			},
			{
				minAspect = 2.2,
				sizeMultiplier = Vector2.new(0.93, 1.0),
				positionNudge = Vector2.new(0, 0.01),
			},
		},
	},
	HealthBar = {
		anchorPoint = Vector2.new(0, 0),
		useSafeZone = true,
		text = {
			enabled = true,
			includeDescendants = true,
			minTextSize = 12,
			maxTextSize = 32,
		},
	},
	InventoryGrid = {
		anchorPoint = Vector2.new(0.5, 0.5),
		useSafeZone = true,
		aspectRules = {
			{
				maxAspect = 1.5,
				sizeMultiplier = Vector2.new(1.04, 1.04),
			},
			{
				minAspect = 2.1,
				sizeMultiplier = Vector2.new(0.92, 0.92),
			},
		},
	},
	Tooltip = {
		anchorPoint = Vector2.new(0, 0),
		useSafeZone = true,
		text = {
			enabled = true,
			includeDescendants = true,
			minTextSize = 12,
			maxTextSize = 34,
		},
	},
}

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

local function clampInteger(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then math.floor(valueRaw) else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function round(value: number): number
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection == nil then
		return
	end
	connection:Disconnect()
end

local function normalizeEventName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function vector2Or(valueRaw: any, fallback: Vector2): Vector2
	if typeof(valueRaw) == "Vector2" then
		return valueRaw
	end
	return fallback
end

local function detectDeviceType(platform: any?): string
	if platform ~= nil and typeof((platform :: any).getPrimaryInputType) == "function" then
		local primaryInput = (platform :: any):getPrimaryInputType()
		if primaryInput == "Touch" then
			return "Mobile"
		end
		if primaryInput == "Gamepad" then
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

local function isTextGui(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function addVector2(a: Vector2, b: Vector2): Vector2
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end

local function multiplyVector2(a: Vector2, b: Vector2): Vector2
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end

local function copyAspectRules(rulesRaw: any): { AspectRule }
	if typeof(rulesRaw) ~= "table" then
		return {}
	end
	local copied = {}
	for index = 1, #rulesRaw do
		local rule = rulesRaw[index]
		if typeof(rule) == "table" then
			copied[#copied + 1] = {
				minAspect = if typeof(rule.minAspect) == "number" then rule.minAspect else nil,
				maxAspect = if typeof(rule.maxAspect) == "number" then rule.maxAspect else nil,
				sizeMultiplier = if typeof(rule.sizeMultiplier) == "Vector2" then rule.sizeMultiplier else nil,
				positionNudge = if typeof(rule.positionNudge) == "Vector2" then rule.positionNudge else nil,
				safePadding = if typeof(rule.safePadding) == "Vector2" then rule.safePadding else nil,
				minSize = if typeof(rule.minSize) == "Vector2" then rule.minSize else nil,
				maxSize = if typeof(rule.maxSize) == "Vector2" then rule.maxSize else nil,
			}
		end
	end
	return copied
end

local function getParentGuiSize(gui: GuiObject, fallback: Vector2): Vector2
	local parent = gui.Parent
	while parent ~= nil do
		if parent:IsA("GuiObject") then
			local abs = parent.AbsoluteSize
			if abs.X > 0 and abs.Y > 0 then
				return Vector2.new(abs.X, abs.Y)
			end
		elseif parent:IsA("ScreenGui") then
			local abs = parent.AbsoluteSize
			if abs.X > 0 and abs.Y > 0 then
				return Vector2.new(abs.X, abs.Y)
			end
		end
		parent = parent.Parent
	end
	return fallback
end

local function getLayoutParentSize(layout: LayoutInstance, fallback: Vector2): Vector2
	local parent = layout.Parent
	while parent ~= nil do
		if parent:IsA("GuiObject") then
			local abs = parent.AbsoluteSize
			if abs.X > 0 and abs.Y > 0 then
				return Vector2.new(abs.X, abs.Y)
			end
		elseif parent:IsA("ScreenGui") then
			local abs = parent.AbsoluteSize
			if abs.X > 0 and abs.Y > 0 then
				return Vector2.new(abs.X, abs.Y)
			end
		end
		parent = parent.Parent
	end
	return fallback
end

local function normalizeUDim(base: UDim, parentAxis: number, convertOffsetToScale: boolean): UDim
	if convertOffsetToScale and parentAxis > 0 then
		return UDim.new(base.Scale + (base.Offset / parentAxis), 0)
	end
	return base
end

local function normalizeUDim2(base: UDim2, parentSize: Vector2, convertOffsetToScale: boolean): UDim2
	local x = normalizeUDim(base.X, parentSize.X, convertOffsetToScale)
	local y = normalizeUDim(base.Y, parentSize.Y, convertOffsetToScale)
	return UDim2.new(x.Scale, x.Offset, y.Scale, y.Offset)
end

local function pickAspectRule(rules: { AspectRule }, aspectRatio: number): AspectRule?
	for index = 1, #rules do
		local rule = rules[index]
		local minAspect = if typeof(rule.minAspect) == "number" then rule.minAspect else -math.huge
		local maxAspect = if typeof(rule.maxAspect) == "number" then rule.maxAspect else math.huge
		if aspectRatio >= minAspect and aspectRatio <= maxAspect then
			return rule
		end
	end
	return nil
end

local function deriveSafeZoneShift(anchor: number, leading: number, trailing: number): number
	if anchor < 0.5 then
		return leading
	end
	if anchor > 0.5 then
		return -trailing
	end
	return (leading - trailing) * 0.5
end

local function findScreenGui(instance: Instance?): ScreenGui?
	local cursor = instance
	while cursor ~= nil do
		if cursor:IsA("ScreenGui") then
			return cursor
		end
		cursor = cursor.Parent
	end
	return nil
end

local function buildTextRule(roleRuleRaw: any, configRuleRaw: any): TextRuleRecord
	local enabled = true
	local includeDescendants = true
	local minTextSize = nil :: number?
	local maxTextSize = nil :: number?

	if typeof(roleRuleRaw) == "table" then
		if roleRuleRaw.enabled ~= nil then
			enabled = roleRuleRaw.enabled == true
		end
		if roleRuleRaw.includeDescendants ~= nil then
			includeDescendants = roleRuleRaw.includeDescendants == true
		end
		if typeof(roleRuleRaw.minTextSize) == "number" then
			minTextSize = roleRuleRaw.minTextSize
		end
		if typeof(roleRuleRaw.maxTextSize) == "number" then
			maxTextSize = roleRuleRaw.maxTextSize
		end
	end

	if typeof(configRuleRaw) == "table" then
		if configRuleRaw.enabled ~= nil then
			enabled = configRuleRaw.enabled == true
		end
		if configRuleRaw.includeDescendants ~= nil then
			includeDescendants = configRuleRaw.includeDescendants == true
		end
		if typeof(configRuleRaw.minTextSize) == "number" then
			minTextSize = configRuleRaw.minTextSize
		end
		if typeof(configRuleRaw.maxTextSize) == "number" then
			maxTextSize = configRuleRaw.maxTextSize
		end
	end

	return {
		enabled = enabled,
		includeDescendants = includeDescendants,
		minTextSize = minTextSize,
		maxTextSize = maxTextSize,
	}
end

local function buildAspectConstraint(roleRaw: any, configRaw: any): AspectConstraintRecord?
	local source = nil
	if typeof(roleRaw) == "table" then
		source = roleRaw
	end
	if typeof(configRaw) == "table" then
		source = configRaw
	end
	if source == nil then
		return nil
	end
	local enabled = if source.enabled == nil then true else source.enabled == true
	if not enabled then
		return {
			enabled = false,
			ratio = 1,
			aspectType = Enum.AspectType.ScaleWithParentSize,
			dominantAxis = Enum.DominantAxis.Width,
		}
	end
	local aspectType = Enum.AspectType.ScaleWithParentSize
	if source.aspectType == Enum.AspectType.ScaleWithParentSize or source.aspectType == Enum.AspectType.FitWithinMaxSize then
		aspectType = source.aspectType
	end
	local dominantAxis = Enum.DominantAxis.Width
	if source.dominantAxis == Enum.DominantAxis.Width or source.dominantAxis == Enum.DominantAxis.Height then
		dominantAxis = source.dominantAxis
	end
	return {
		enabled = true,
		ratio = clampNumber(source.ratio, 1, 0.05, 100),
		aspectType = aspectType,
		dominantAxis = dominantAxis,
	}
end

function UIScaling.New(configRaw: UIScalingConfig?): UIScaling
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local referenceResolution = vector2Or(config.referenceResolution, DEFAULT_REFERENCE_RESOLUTION)

	local self = setmetatable({
		platform = config.platform,
		screenGui = if typeof(config.screenGui) == "Instance" and config.screenGui:IsA("ScreenGui") then config.screenGui else nil,
		ignoreGuiInset = if config.ignoreGuiInset == nil then true else config.ignoreGuiInset == true,
		referenceResolution = Vector2.new(math.max(1, referenceResolution.X), math.max(1, referenceResolution.Y)),
		minGlobalScale = clampNumber(config.minGlobalScale, 0.78, 0.1, 10),
		maxGlobalScale = clampNumber(config.maxGlobalScale, 1.45, 0.1, 10),
		presets = {
			Desktop = Sift.Dictionary.copy(DEFAULT_DEVICE_PRESETS.Desktop),
			Mobile = Sift.Dictionary.copy(DEFAULT_DEVICE_PRESETS.Mobile),
			Console = Sift.Dictionary.copy(DEFAULT_DEVICE_PRESETS.Console),
		} :: { [string]: DevicePreset },
		aspectRules = copyAspectRules(DEFAULT_ASPECT_RULES),
		elements = {} :: { [string]: ElementRecord },
		elementOrder = {} :: { string },
		layouts = {} :: { [string]: LayoutRecord },
		layoutOrder = {} :: { string },
		nextElementId = 0,
		nextLayoutId = 0,
		lastSnapshot = nil :: UISnapshot?,
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "ui.scaling"),
		appliedEvent = normalizeEventName(config.appliedEvent, "applied"),
		isInitialized = false,
		screenGuiConnection = nil :: RBXScriptConnection?,
		cameraChangedConnection = nil :: RBXScriptConnection?,
		cameraViewportConnection = nil :: RBXScriptConnection?,
		platformDisconnect = nil :: (() -> ())?,
	}, UIScaling)

	if typeof(config.presets) == "table" then
		for key, presetRaw in config.presets do
			if typeof(key) == "string" and typeof(presetRaw) == "table" then
				self.presets[key] = {
					uiScale = if typeof(presetRaw.uiScale) == "number" then presetRaw.uiScale else nil,
					offsetScale = if typeof(presetRaw.offsetScale) == "number" then presetRaw.offsetScale else nil,
					safePadding = if typeof(presetRaw.safePadding) == "Vector2" then presetRaw.safePadding else nil,
					textMin = if typeof(presetRaw.textMin) == "number" then presetRaw.textMin else nil,
					textMax = if typeof(presetRaw.textMax) == "number" then presetRaw.textMax else nil,
					layoutSpacingScale = if typeof(presetRaw.layoutSpacingScale) == "number" then presetRaw.layoutSpacingScale else nil,
				}
			end
		end
	end

	if typeof(config.aspectRules) == "table" then
		self.aspectRules = copyAspectRules(config.aspectRules)
	end

	return self
end

function UIScaling._bindCameraViewportConnection(self: UIScaling)
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

function UIScaling._bindScreenGuiConnection(self: UIScaling)
	safeDisconnect(self.screenGuiConnection)
	self.screenGuiConnection = nil
	if self.screenGui == nil then
		return
	end
	self.screenGuiConnection = self.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:apply()
	end)
end

function UIScaling._applyScreenGuiSettings(self: UIScaling)
	if self.screenGui == nil then
		return
	end
	self.screenGui.IgnoreGuiInset = self.ignoreGuiInset
end

function UIScaling._setScreenGui(self: UIScaling, screenGui: ScreenGui?)
	if self.screenGui == screenGui then
		return
	end
	self.screenGui = screenGui
	self:_applyScreenGuiSettings()
	if self.isInitialized then
		self:_bindScreenGuiConnection()
	end
end

function UIScaling._adoptScreenGuiFrom(self: UIScaling, instance: Instance?)
	if self.screenGui ~= nil then
		return
	end
	local adopted = findScreenGui(instance)
	if adopted ~= nil then
		self:_setScreenGui(adopted)
	end
end

function UIScaling._getViewport(self: UIScaling): Vector2
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Vector2.new(1920, 1080)
	end
	local viewport = camera.ViewportSize
	return Vector2.new(math.max(1, viewport.X), math.max(1, viewport.Y))
end

function UIScaling._getRootSize(self: UIScaling, viewport: Vector2): Vector2
	if self.screenGui == nil then
		return viewport
	end
	local absolute = self.screenGui.AbsoluteSize
	if absolute.X <= 0 or absolute.Y <= 0 then
		return viewport
	end
	return Vector2.new(absolute.X, absolute.Y)
end

function UIScaling._computeSnapshot(self: UIScaling): UISnapshot
	local viewport = self:_getViewport()
	local guiSize = self:_getRootSize(viewport)
	local deviceType = detectDeviceType(self.platform)
	local preset = self.presets[deviceType] or self.presets.Desktop or Sift.Dictionary.copy(DEFAULT_DEVICE_PRESETS.Desktop)
	local globalScale = clampNumber(guiSize.Y / self.referenceResolution.Y, 1, self.minGlobalScale, self.maxGlobalScale)

	local safeTopLeft = Vector2.zero
	local safeBottomRight = Vector2.zero
	if self.ignoreGuiInset then
		local insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
		safeTopLeft = insetTopLeft
		safeBottomRight = insetBottomRight
	end

	return {
		viewport = viewport,
		guiSize = guiSize,
		aspectRatio = guiSize.X / guiSize.Y,
		scale = globalScale,
		deviceType = deviceType,
		safeTopLeft = safeTopLeft,
		safeBottomRight = safeBottomRight,
		preset = preset,
	}
end

function UIScaling._collectTextTargets(self: UIScaling, root: GuiObject, includeDescendants: boolean): { TextGui }
	local targets = {}
	if isTextGui(root) then
		targets[#targets + 1] = root :: TextGui
	end
	if includeDescendants then
		for _, descendant in root:GetDescendants() do
			if isTextGui(descendant) then
				targets[#targets + 1] = descendant :: TextGui
			end
		end
	end
	return targets
end

function UIScaling._applyTextRule(self: UIScaling, gui: GuiObject, textRule: TextRuleRecord, preset: DevicePreset)
	if not textRule.enabled then
		return
	end

	local minText = clampInteger(textRule.minTextSize, clampInteger(preset.textMin, 12, 1, 400), 1, 400)
	local maxText = clampInteger(textRule.maxTextSize, clampInteger(preset.textMax, 42, minText, 400), minText, 400)
	local targets = self:_collectTextTargets(gui, textRule.includeDescendants)
	for index = 1, #targets do
		local textGui = targets[index]
		textGui.TextScaled = true
		local constraint = textGui:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint?
		if constraint == nil then
			constraint = Instance.new("UITextSizeConstraint")
			constraint.Parent = textGui
		end
		local textConstraint = constraint :: UITextSizeConstraint
		textConstraint.MinTextSize = minText
		textConstraint.MaxTextSize = maxText
	end
end

function UIScaling._applyAspectConstraint(self: UIScaling, gui: GuiObject, aspectConstraint: AspectConstraintRecord?)
	if aspectConstraint == nil or not aspectConstraint.enabled then
		return
	end
	local constraint = gui:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint?
	if constraint == nil then
		constraint = Instance.new("UIAspectRatioConstraint")
		constraint.Parent = gui
	end
	local ratioConstraint = constraint :: UIAspectRatioConstraint
	ratioConstraint.AspectRatio = aspectConstraint.ratio
	ratioConstraint.AspectType = aspectConstraint.aspectType
	ratioConstraint.DominantAxis = aspectConstraint.dominantAxis
end

function UIScaling._resolveSizeBounds(self: UIScaling, record: ElementRecord, globalAspectRule: AspectRule?, elementAspectRule: AspectRule?): (Vector2?, Vector2?)
	local minSize = record.minSize
	local maxSize = record.maxSize

	if globalAspectRule ~= nil then
		if typeof(globalAspectRule.minSize) == "Vector2" then
			minSize = globalAspectRule.minSize
		end
		if typeof(globalAspectRule.maxSize) == "Vector2" then
			maxSize = globalAspectRule.maxSize
		end
	end
	if elementAspectRule ~= nil then
		if typeof(elementAspectRule.minSize) == "Vector2" then
			minSize = elementAspectRule.minSize
		end
		if typeof(elementAspectRule.maxSize) == "Vector2" then
			maxSize = elementAspectRule.maxSize
		end
	end

	return minSize, maxSize
end

function UIScaling._applyElement(self: UIScaling, record: ElementRecord, snapshot: UISnapshot)
	local gui = record.gui
	if gui.Parent == nil then
		return
	end

	local parentSize = getParentGuiSize(gui, snapshot.guiSize)
	local preset = snapshot.preset
	local offsetScale = clampNumber(preset.offsetScale, 1, 0.1, 10)
	local uiScale = clampNumber(preset.uiScale, 1, 0.1, 10)

	local baseSize = normalizeUDim2(record.baseSize, parentSize, record.scaleSizeOffsets)
	local basePosition = normalizeUDim2(record.basePosition, parentSize, record.scalePositionOffsets)

	local globalAspectRule = pickAspectRule(self.aspectRules, snapshot.aspectRatio)
	local elementAspectRule = pickAspectRule(record.aspectRules, snapshot.aspectRatio)

	local sizeMultiplier = record.sizeMultiplier
	local positionNudge = record.positionNudge
	local safePadding = addVector2(vector2Or(preset.safePadding, Vector2.zero), record.safePadding)
	if globalAspectRule ~= nil then
		if typeof(globalAspectRule.sizeMultiplier) == "Vector2" then
			sizeMultiplier = multiplyVector2(sizeMultiplier, globalAspectRule.sizeMultiplier)
		end
		if typeof(globalAspectRule.positionNudge) == "Vector2" then
			positionNudge = addVector2(positionNudge, globalAspectRule.positionNudge)
		end
		if typeof(globalAspectRule.safePadding) == "Vector2" then
			safePadding = addVector2(safePadding, globalAspectRule.safePadding)
		end
	end
	if elementAspectRule ~= nil then
		if typeof(elementAspectRule.sizeMultiplier) == "Vector2" then
			sizeMultiplier = multiplyVector2(sizeMultiplier, elementAspectRule.sizeMultiplier)
		end
		if typeof(elementAspectRule.positionNudge) == "Vector2" then
			positionNudge = addVector2(positionNudge, elementAspectRule.positionNudge)
		end
		if typeof(elementAspectRule.safePadding) == "Vector2" then
			safePadding = addVector2(safePadding, elementAspectRule.safePadding)
		end
	end

	local sizeScaleFactor = snapshot.scale * uiScale
	local sizeScaleX = baseSize.X.Scale * sizeScaleFactor * sizeMultiplier.X
	local sizeScaleY = baseSize.Y.Scale * sizeScaleFactor * sizeMultiplier.Y

	local sizeOffsetX = round((baseSize.X.Offset + record.sizeFineOffset.X) * snapshot.scale * offsetScale)
	local sizeOffsetY = round((baseSize.Y.Offset + record.sizeFineOffset.Y) * snapshot.scale * offsetScale)

	local absoluteWidth = sizeScaleX * parentSize.X + sizeOffsetX
	local absoluteHeight = sizeScaleY * parentSize.Y + sizeOffsetY

	local minSize, maxSize = self:_resolveSizeBounds(record, globalAspectRule, elementAspectRule)
	if minSize ~= nil then
		absoluteWidth = math.max(absoluteWidth, minSize.X)
		absoluteHeight = math.max(absoluteHeight, minSize.Y)
	end
	if maxSize ~= nil then
		absoluteWidth = math.min(absoluteWidth, maxSize.X)
		absoluteHeight = math.min(absoluteHeight, maxSize.Y)
	end

	sizeScaleX = absoluteWidth / math.max(1, parentSize.X)
	sizeScaleY = absoluteHeight / math.max(1, parentSize.Y)

	local positionScaleX = basePosition.X.Scale + positionNudge.X
	local positionScaleY = basePosition.Y.Scale + positionNudge.Y
	local positionOffsetX = round((basePosition.X.Offset + record.positionFineOffset.X) * snapshot.scale * offsetScale)
	local positionOffsetY = round((basePosition.Y.Offset + record.positionFineOffset.Y) * snapshot.scale * offsetScale)

	if record.useSafeZone then
		local safeLeft = (snapshot.safeTopLeft.X + safePadding.X) / math.max(1, snapshot.guiSize.X)
		local safeRight = (snapshot.safeBottomRight.X + safePadding.X) / math.max(1, snapshot.guiSize.X)
		local safeTop = (snapshot.safeTopLeft.Y + safePadding.Y) / math.max(1, snapshot.guiSize.Y)
		local safeBottom = (snapshot.safeBottomRight.Y + safePadding.Y) / math.max(1, snapshot.guiSize.Y)

		positionScaleX += deriveSafeZoneShift(record.anchorPoint.X, safeLeft, safeRight)
		positionScaleY += deriveSafeZoneShift(record.anchorPoint.Y, safeTop, safeBottom)
	end

	gui.AnchorPoint = record.anchorPoint
	gui.Size = UDim2.new(sizeScaleX, 0, sizeScaleY, 0)
	gui.Position = UDim2.new(positionScaleX, positionOffsetX, positionScaleY, positionOffsetY)

	self:_applyAspectConstraint(gui, record.aspectConstraint)
	self:_applyTextRule(gui, record.textRule, preset)

	if record.onApply ~= nil then
		record.onApply(gui, snapshot)
	end
end

function UIScaling._applyLayout(self: UIScaling, record: LayoutRecord, snapshot: UISnapshot)
	local layout = record.layout
	if layout.Parent == nil then
		return
	end

	local parentSize = getLayoutParentSize(layout, snapshot.guiSize)
	local preset = snapshot.preset
	local uiScale = snapshot.scale * clampNumber(preset.uiScale, 1, 0.1, 10)
	local spacingScale = snapshot.scale * clampNumber(preset.layoutSpacingScale, 1, 0.1, 10)
	local offsetScale = clampNumber(preset.offsetScale, 1, 0.1, 10)

	if layout:IsA("UIListLayout") then
		local basePadding = record.basePadding or layout.Padding
		local axisSize = if layout.FillDirection == Enum.FillDirection.Horizontal then parentSize.X else parentSize.Y
		local normalizedPadding = normalizeUDim(basePadding, axisSize, record.scalePaddingOffsets)
		local paddingScaleValue = normalizedPadding.Scale * spacingScale
		local paddingOffsetValue = if record.scalePaddingOffsets then 0 else round(normalizedPadding.Offset * spacingScale * offsetScale)
		layout.Padding = UDim.new(paddingScaleValue, paddingOffsetValue)
		return
	end

	if layout:IsA("UIGridLayout") then
		local baseCellSize = record.baseCellSize or layout.CellSize
		local baseCellPadding = record.baseCellPadding or layout.CellPadding

		local normalizedCellSize = normalizeUDim2(baseCellSize, parentSize, record.scaleCellSizeOffsets)
		local normalizedCellPadding = normalizeUDim2(baseCellPadding, parentSize, record.scaleCellPaddingOffsets)

		local cellScaleX = normalizedCellSize.X.Scale * uiScale
		local cellScaleY = normalizedCellSize.Y.Scale * uiScale
		local cellOffsetX = if record.scaleCellSizeOffsets then 0 else round(normalizedCellSize.X.Offset * uiScale * offsetScale)
		local cellOffsetY = if record.scaleCellSizeOffsets then 0 else round(normalizedCellSize.Y.Offset * uiScale * offsetScale)

		local absoluteCellX = cellScaleX * parentSize.X + cellOffsetX
		local absoluteCellY = cellScaleY * parentSize.Y + cellOffsetY

		if record.minCellSize ~= nil then
			absoluteCellX = math.max(absoluteCellX, record.minCellSize.X)
			absoluteCellY = math.max(absoluteCellY, record.minCellSize.Y)
		end
		if record.maxCellSize ~= nil then
			absoluteCellX = math.min(absoluteCellX, record.maxCellSize.X)
			absoluteCellY = math.min(absoluteCellY, record.maxCellSize.Y)
		end

		cellScaleX = absoluteCellX / math.max(1, parentSize.X)
		cellScaleY = absoluteCellY / math.max(1, parentSize.Y)

		layout.CellSize = UDim2.new(cellScaleX, 0, cellScaleY, 0)
		layout.CellPadding = UDim2.new(
			normalizedCellPadding.X.Scale * spacingScale,
			if record.scaleCellPaddingOffsets then 0 else round(normalizedCellPadding.X.Offset * spacingScale * offsetScale),
			normalizedCellPadding.Y.Scale * spacingScale,
			if record.scaleCellPaddingOffsets then 0 else round(normalizedCellPadding.Y.Offset * spacingScale * offsetScale)
		)
	end
end

function UIScaling.Init(self: UIScaling)
	if self.isInitialized then
		return
	end
	self.isInitialized = true

	self:_applyScreenGuiSettings()
	self:_bindCameraViewportConnection()
	self:_bindScreenGuiConnection()

	self.cameraChangedConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_bindCameraViewportConnection()
		self:apply()
	end)

	if self.platform ~= nil and typeof((self.platform :: any).onChanged) == "function" then
		self.platformDisconnect = (self.platform :: any):onChanged(function()
			self:apply()
		end)
	end

	self:apply()
end

function UIScaling.Apply(self: UIScaling)
	if self.screenGui == nil then
		for index = 1, #self.elementOrder do
			local record = self.elements[self.elementOrder[index]]
			if record ~= nil then
				self:_adoptScreenGuiFrom(record.gui)
				if self.screenGui ~= nil then
					break
				end
			end
		end
	end

	self:_applyScreenGuiSettings()
	local snapshot = self:_computeSnapshot()
	self.lastSnapshot = snapshot

	for index = 1, #self.elementOrder do
		local id = self.elementOrder[index]
		local record = self.elements[id]
		if record ~= nil then
			self:_applyElement(record, snapshot)
		end
	end

	for index = 1, #self.layoutOrder do
		local id = self.layoutOrder[index]
		local record = self.layouts[id]
		if record ~= nil then
			self:_applyLayout(record, snapshot)
		end
	end

	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, self.appliedEvent, snapshot)
	end
end

function UIScaling.RegisterElement(self: UIScaling, configRaw: ElementConfig): string?
	if typeof(configRaw) ~= "table" then
		return nil
	end
	if typeof(configRaw.gui) ~= "Instance" or not configRaw.gui:IsA("GuiObject") then
		return nil
	end

	local gui = configRaw.gui :: GuiObject
	local role = if typeof(configRaw.role) == "string" and configRaw.role ~= "" then configRaw.role else nil
	local rolePreset = if role ~= nil then ROLE_PRESETS[role] else nil

	local id = if typeof(configRaw.id) == "string" and configRaw.id ~= "" then configRaw.id else nil
	if id == nil then
		self.nextElementId += 1
		id = string.format("ui_%d", self.nextElementId)
	end

	local anchorPoint = if typeof(configRaw.anchorPoint) == "Vector2" then configRaw.anchorPoint else if typeof(rolePreset) == "table" and typeof(rolePreset.anchorPoint) == "Vector2" then rolePreset.anchorPoint else gui.AnchorPoint
	local useSafeZone = if configRaw.useSafeZone == nil then if typeof(rolePreset) == "table" and rolePreset.useSafeZone ~= nil then rolePreset.useSafeZone == true else true else configRaw.useSafeZone == true
	local safePadding = if typeof(configRaw.safePadding) == "Vector2" then configRaw.safePadding else Vector2.zero
	local sizeMultiplier = if typeof(configRaw.sizeMultiplier) == "Vector2" then configRaw.sizeMultiplier else VECTOR2_ONE
	local positionNudge = if typeof(configRaw.positionNudge) == "Vector2" then configRaw.positionNudge else Vector2.zero
	local aspectRules = if typeof(configRaw.aspectRules) == "table" then copyAspectRules(configRaw.aspectRules) else if typeof(rolePreset) == "table" and typeof(rolePreset.aspectRules) == "table" then copyAspectRules(rolePreset.aspectRules) else {}
	local textRule = buildTextRule(if typeof(rolePreset) == "table" then rolePreset.text else nil, configRaw.text)
	local aspectConstraint = buildAspectConstraint(if typeof(rolePreset) == "table" then rolePreset.aspectConstraint else nil, configRaw.aspectConstraint)
	local onApply = if typeof(configRaw.onApply) == "function" then configRaw.onApply else nil

	local record: ElementRecord = {
		id = id,
		role = role,
		gui = gui,
		baseSize = gui.Size,
		basePosition = gui.Position,
		anchorPoint = anchorPoint,
		useSafeZone = useSafeZone,
		safePadding = safePadding,
		scaleSizeOffsets = if configRaw.scaleSizeOffsets == nil then true else configRaw.scaleSizeOffsets == true,
		scalePositionOffsets = if configRaw.scalePositionOffsets == nil then true else configRaw.scalePositionOffsets == true,
		sizeFineOffset = vector2Or(configRaw.sizeFineOffset, Vector2.zero),
		positionFineOffset = vector2Or(configRaw.positionFineOffset, Vector2.zero),
		sizeMultiplier = sizeMultiplier,
		positionNudge = positionNudge,
		minSize = if typeof(configRaw.minSize) == "Vector2" then configRaw.minSize else nil,
		maxSize = if typeof(configRaw.maxSize) == "Vector2" then configRaw.maxSize else nil,
		textRule = textRule,
		aspectConstraint = aspectConstraint,
		aspectRules = aspectRules,
		onApply = onApply,
	}

	if self.elements[id] == nil then
		self.elementOrder[#self.elementOrder + 1] = id
	end
	self.elements[id] = record
	self:_adoptScreenGuiFrom(gui)

	if self.isInitialized then
		self:apply()
	end
	return id
end

function UIScaling.UnregisterElement(self: UIScaling, idRaw: any): boolean
	if typeof(idRaw) ~= "string" then
		return false
	end
	if self.elements[idRaw] == nil then
		return false
	end
	self.elements[idRaw] = nil
	for index = #self.elementOrder, 1, -1 do
		if self.elementOrder[index] == idRaw then
			table.remove(self.elementOrder, index)
			break
		end
	end
	return true
end

function UIScaling.RegisterLayout(self: UIScaling, configRaw: LayoutConfig): string?
	if typeof(configRaw) ~= "table" then
		return nil
	end
	if typeof(configRaw.layout) ~= "Instance" then
		return nil
	end
	local layoutInstance = configRaw.layout
	if not layoutInstance:IsA("UIListLayout") and not layoutInstance:IsA("UIGridLayout") then
		return nil
	end

	local id = if typeof(configRaw.id) == "string" and configRaw.id ~= "" then configRaw.id else nil
	if id == nil then
		self.nextLayoutId += 1
		id = string.format("layout_%d", self.nextLayoutId)
	end

	local record: LayoutRecord = {
		id = id,
		layout = layoutInstance,
		basePadding = if layoutInstance:IsA("UIListLayout") then layoutInstance.Padding else nil,
		baseCellSize = if layoutInstance:IsA("UIGridLayout") then layoutInstance.CellSize else nil,
		baseCellPadding = if layoutInstance:IsA("UIGridLayout") then layoutInstance.CellPadding else nil,
		scalePaddingOffsets = if configRaw.scalePaddingOffsets == nil then true else configRaw.scalePaddingOffsets == true,
		scaleCellSizeOffsets = if configRaw.scaleCellSizeOffsets == nil then true else configRaw.scaleCellSizeOffsets == true,
		scaleCellPaddingOffsets = if configRaw.scaleCellPaddingOffsets == nil then true else configRaw.scaleCellPaddingOffsets == true,
		minCellSize = if typeof(configRaw.minCellSize) == "Vector2" then configRaw.minCellSize else nil,
		maxCellSize = if typeof(configRaw.maxCellSize) == "Vector2" then configRaw.maxCellSize else nil,
	}

	if self.layouts[id] == nil then
		self.layoutOrder[#self.layoutOrder + 1] = id
	end
	self.layouts[id] = record
	self:_adoptScreenGuiFrom(layoutInstance.Parent)

	if self.isInitialized then
		self:apply()
	end
	return id
end

function UIScaling.UnregisterLayout(self: UIScaling, idRaw: any): boolean
	if typeof(idRaw) ~= "string" then
		return false
	end
	if self.layouts[idRaw] == nil then
		return false
	end
	self.layouts[idRaw] = nil
	for index = #self.layoutOrder, 1, -1 do
		if self.layoutOrder[index] == idRaw then
			table.remove(self.layoutOrder, index)
			break
		end
	end
	return true
end

function UIScaling.SetPreset(self: UIScaling, deviceTypeRaw: any, presetRaw: any): boolean
	if typeof(deviceTypeRaw) ~= "string" or deviceTypeRaw == "" then
		return false
	end
	if typeof(presetRaw) ~= "table" then
		return false
	end
	self.presets[deviceTypeRaw] = {
		uiScale = if typeof(presetRaw.uiScale) == "number" then presetRaw.uiScale else nil,
		offsetScale = if typeof(presetRaw.offsetScale) == "number" then presetRaw.offsetScale else nil,
		safePadding = if typeof(presetRaw.safePadding) == "Vector2" then presetRaw.safePadding else nil,
		textMin = if typeof(presetRaw.textMin) == "number" then presetRaw.textMin else nil,
		textMax = if typeof(presetRaw.textMax) == "number" then presetRaw.textMax else nil,
		layoutSpacingScale = if typeof(presetRaw.layoutSpacingScale) == "number" then presetRaw.layoutSpacingScale else nil,
	}
	if self.isInitialized then
		self:apply()
	end
	return true
end

function UIScaling.SetScreenGui(self: UIScaling, screenGuiRaw: any): boolean
	if typeof(screenGuiRaw) ~= "Instance" or not screenGuiRaw:IsA("ScreenGui") then
		return false
	end
	self:_setScreenGui(screenGuiRaw)
	if self.isInitialized then
		self:apply()
	end
	return true
end

function UIScaling.SetIgnoreGuiInset(self: UIScaling, ignoreRaw: any)
	self.ignoreGuiInset = ignoreRaw == true
	self:_applyScreenGuiSettings()
	if self.isInitialized then
		self:apply()
	end
end

function UIScaling.GetSnapshot(self: UIScaling): UISnapshot
	if self.lastSnapshot == nil then
		self.lastSnapshot = self:_computeSnapshot()
	end
	return self.lastSnapshot :: UISnapshot
end

function UIScaling.Destroy(self: UIScaling)
	safeDisconnect(self.screenGuiConnection)
	safeDisconnect(self.cameraViewportConnection)
	safeDisconnect(self.cameraChangedConnection)
	self.screenGuiConnection = nil
	self.cameraViewportConnection = nil
	self.cameraChangedConnection = nil
	if self.platformDisconnect ~= nil then
		self.platformDisconnect()
		self.platformDisconnect = nil
	end
	table.clear(self.elements)
	table.clear(self.layouts)
	table.clear(self.elementOrder)
	table.clear(self.layoutOrder)
	self.lastSnapshot = nil
	self.isInitialized = false
end

UIScaling.RegisterElement = UIScaling.RegisterElement
UIScaling.UnregisterElement = UIScaling.UnregisterElement
UIScaling.Register = UIScaling.RegisterElement
UIScaling.Unregister = UIScaling.UnregisterElement
UIScaling.RegisterLayout = UIScaling.RegisterLayout
UIScaling.UnregisterLayout = UIScaling.UnregisterLayout
UIScaling.SetPreset = UIScaling.SetPreset
UIScaling.SetScreenGui = UIScaling.SetScreenGui
UIScaling.SetIgnoreGuiInset = UIScaling.SetIgnoreGuiInset
UIScaling.GetSnapshot = UIScaling.GetSnapshot
UIScaling.Apply = UIScaling.Apply
UIScaling.Init = UIScaling.Init
UIScaling.Destroy = UIScaling.Destroy

UIScaling.new = UIScaling.New
UIScaling.init = UIScaling.Init
UIScaling.apply = UIScaling.Apply
UIScaling.registerElement = UIScaling.RegisterElement
UIScaling.unregisterElement = UIScaling.UnregisterElement
UIScaling.registerLayout = UIScaling.RegisterLayout
UIScaling.unregisterLayout = UIScaling.UnregisterLayout
UIScaling.setPreset = UIScaling.SetPreset
UIScaling.setScreenGui = UIScaling.SetScreenGui
UIScaling.setIgnoreGuiInset = UIScaling.SetIgnoreGuiInset
UIScaling.getSnapshot = UIScaling.GetSnapshot
UIScaling.destroy = UIScaling.Destroy

return UIScaling
