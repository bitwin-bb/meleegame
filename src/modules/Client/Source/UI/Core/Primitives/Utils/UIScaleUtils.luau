local require = require(script.Parent.loader).load(script)

export type Breakpoint = "small" | "medium" | "large"
export type DeviceClass = "mobile" | "tablet" | "desktop"

export type SafeArea = {
	top: number,
	right: number,
	bottom: number,
	left: number,
}

export type HudTokens = {
	edgePadding: number,
	railThickness: number,
	topBarHeight: number,
	bottomBarHeight: number,
	sideBarWidth: number,
	sideBarVerticalPadding: number,
	navButtonWidth: number,
	sideButtonWidth: number,
	navButtonHeight: number,
	navButtonGap: number,
	navButtonTextSize: number,
}

export type MeterTokens = {
	segmentSize: number,
	segmentGap: number,
	frameWidth: number,
	frameHeight: number,
	labelTextSize: number,
}

export type InventoryTokens = {
	slotSize: number,
	slotGap: number,
	leftPadding: number,
	keyHintTextSize: number,
}

export type CraftingTokens = {
	panelWidth: number,
	panelHeight: number,
	panelScale: number,
	panelPadding: number,
	headerHeight: number,
	searchY: number,
	categoryY: number,
	recipeGridY: number,
	recipeDetailsY: number,
	craftButtonY: number,
	craftButtonHeight: number,
	recipeSlotSize: number,
	requirementSlotSize: number,
	iconSize: number,
	textSize: number,
}

export type TextTokens = {
	tiny: number,
	small: number,
	body: number,
	button: number,
	title: number,
}

export type ResponsiveTokens = {
	hud: HudTokens,
	meter: MeterTokens,
	inventory: InventoryTokens,
	crafting: CraftingTokens,
	text: TextTokens,
}

export type ResponsiveMetrics = {
	viewport: Vector2,
	scale: number,
	breakpoint: Breakpoint,
	deviceClass: DeviceClass,
	isSmall: boolean,
	isCompactHud: boolean,
	safeArea: SafeArea,
	tokens: ResponsiveTokens,
}

local UiScaleUtils = {}

UiScaleUtils.REFERENCE_VIEWPORT = Vector2.new(1920, 1080)
UiScaleUtils.MIN_SCALE = 0.58
UiScaleUtils.MAX_SCALE = 1.12

local function snap(value: number): number
	return math.floor(value + 0.5)
end

local function scaleNumber(value: number, scale: number, minValue: number?): number
	return math.max(minValue or 0, snap(value * scale))
end

local function getTrailingInset(viewportAxis: number, trailingValue: number): number
	if trailingValue > viewportAxis * 0.5 then
		return math.max(0, viewportAxis - trailingValue)
	end
	return math.max(0, trailingValue)
end

function UiScaleUtils.snap(value: number): number
	return snap(value)
end

function UiScaleUtils.scaleNumber(value: number, scale: number, minValue: number?): number
	return scaleNumber(value, scale, minValue)
end

function UiScaleUtils.GetScale(viewport: Vector2): number
	local safeViewport = Vector2.new(math.max(1, viewport.X), math.max(1, viewport.Y))
	local rawScale =
		math.min(safeViewport.X / UiScaleUtils.REFERENCE_VIEWPORT.X, safeViewport.Y / UiScaleUtils.REFERENCE_VIEWPORT.Y)
	return math.clamp(rawScale, UiScaleUtils.MIN_SCALE, UiScaleUtils.MAX_SCALE)
end

function UiScaleUtils.GetBreakpoint(viewport: Vector2): Breakpoint
	if viewport.X < 900 or viewport.Y < 560 then
		return "small"
	end
	if viewport.X < 1280 or viewport.Y < 760 then
		return "medium"
	end
	return "large"
end

function UiScaleUtils.GetDeviceClass(viewport: Vector2): DeviceClass
	if viewport.X < 760 then
		return "mobile"
	end
	if viewport.X < 1180 then
		return "tablet"
	end
	return "desktop"
end

function UiScaleUtils.GetSafeArea(
	viewport: Vector2,
	safeInsetTopLeft: Vector2?,
	safeInsetBottomRight: Vector2?,
	scale: number
): SafeArea
	local topLeft = safeInsetTopLeft or Vector2.zero
	local bottomRight = safeInsetBottomRight or Vector2.zero
	local basePadding = scaleNumber(12, scale, 8)

	return {
		top = math.max(basePadding, snap(topLeft.Y)),
		left = math.max(basePadding, snap(topLeft.X)),
		right = math.max(basePadding, snap(getTrailingInset(viewport.X, bottomRight.X))),
		bottom = math.max(basePadding, snap(getTrailingInset(viewport.Y, bottomRight.Y))),
	}
end

local function getInventorySlotSize(viewport: Vector2, safeArea: SafeArea, scale: number, compact: boolean): number
	local desiredSlot = scaleNumber(if compact then 50 else 58, scale, if compact then 38 else 46)
	local desiredGap = scaleNumber(if compact then 5 else 6, scale, 4)
	local availableWidth = math.max(220, viewport.X - safeArea.left - safeArea.right - scaleNumber(24, scale, 12))
	local maxSlotByWidth = math.floor((availableWidth - desiredGap * 8) / 9)

	return math.clamp(math.min(desiredSlot, maxSlotByWidth), 34, 64)
end

function UiScaleUtils.GetTokens(metrics: {
	viewport: Vector2,
	scale: number,
	breakpoint: Breakpoint,
	deviceClass: DeviceClass,
	isCompactHud: boolean,
	safeArea: SafeArea,
}): ResponsiveTokens
	local viewport = metrics.viewport
	local scale = metrics.scale
	local compact = metrics.isCompactHud
	local safeArea = metrics.safeArea
	local edgePadding = scaleNumber(if compact then 8 else 12, scale, 6)
	local railThickness = scaleNumber(if compact then 48 else 56, scale, 44)
	local navButtonWidth = scaleNumber(if compact then 132 else 170, scale, 112)
	local sideButtonWidth = scaleNumber(if compact then 132 else 190, scale, 112)
	local navButtonHeight = scaleNumber(if compact then 34 else 40, scale, 30)
	local segmentSize = scaleNumber(if compact then 24 else 30, scale, 20)
	local slotSize = getInventorySlotSize(viewport, safeArea, scale, compact)
	local slotGap = scaleNumber(if compact then 5 else 6, scale, 4)
	local craftingAvailableWidth = math.max(220, viewport.X - safeArea.left - safeArea.right - edgePadding * 2)
	local craftingAvailableHeight = math.max(260, viewport.Y - safeArea.top - safeArea.bottom - edgePadding * 2)
	local craftingFitScale = math.min(craftingAvailableWidth / 336, craftingAvailableHeight / 458)
	local craftingScale = math.clamp(math.min(scale, craftingFitScale), 0.68, 1)

	return {
		hud = {
			edgePadding = edgePadding,
			railThickness = railThickness,
			topBarHeight = railThickness,
			bottomBarHeight = railThickness,
			sideBarWidth = railThickness,
			sideBarVerticalPadding = scaleNumber(if compact then 48 else 72, scale, 42),
			navButtonWidth = navButtonWidth,
			sideButtonWidth = sideButtonWidth,
			navButtonHeight = navButtonHeight,
			navButtonGap = scaleNumber(if compact then 6 else 8, scale, 4),
			navButtonTextSize = scaleNumber(if compact then 13 else 14, scale, 11),
		},
		meter = {
			segmentSize = segmentSize,
			segmentGap = scaleNumber(if compact then 2 else 4, scale, 2),
			frameWidth = scaleNumber(if compact then 260 else 360, scale, 220),
			frameHeight = scaleNumber(if compact then 44 else 56, scale, 40),
			labelTextSize = scaleNumber(if compact then 12 else 14, scale, 10),
		},
		inventory = {
			slotSize = slotSize,
			slotGap = slotGap,
			leftPadding = scaleNumber(if compact then 10 else 16, scale, 8),
			keyHintTextSize = scaleNumber(if compact then 9 else 11, scale, 8),
		},
		crafting = {
			panelWidth = 336,
			panelHeight = 458,
			panelScale = craftingScale,
			panelPadding = 10,
			headerHeight = 24,
			searchY = 38,
			categoryY = 72,
			recipeGridY = 104,
			recipeDetailsY = 348,
			craftButtonY = 416,
			craftButtonHeight = 32,
			recipeSlotSize = 80,
			requirementSlotSize = 60,
			iconSize = 30,
			textSize = 12,
		},
		text = {
			tiny = scaleNumber(10, scale, 9),
			small = scaleNumber(12, scale, 10),
			body = scaleNumber(14, scale, 11),
			button = scaleNumber(14, scale, 11),
			title = scaleNumber(18, scale, 14),
		},
	}
end

function UiScaleUtils.GetMetrics(
	viewportRaw: Vector2?,
	safeInsetTopLeft: Vector2?,
	safeInsetBottomRight: Vector2?
): ResponsiveMetrics
	local viewport = viewportRaw or UiScaleUtils.REFERENCE_VIEWPORT
	viewport = Vector2.new(math.max(1, viewport.X), math.max(1, viewport.Y))
	local scale = UiScaleUtils.GetScale(viewport)
	local breakpoint: Breakpoint = UiScaleUtils.GetBreakpoint(viewport)
	local deviceClass: DeviceClass = UiScaleUtils.GetDeviceClass(viewport)
	local compactHud = breakpoint == "small" or viewport.X < 980 or viewport.Y < 620
	local safeArea = UiScaleUtils.GetSafeArea(viewport, safeInsetTopLeft, safeInsetBottomRight, scale)

	local metricInput: {
		viewport: Vector2,
		scale: number,
		breakpoint: Breakpoint,
		deviceClass: DeviceClass,
		isCompactHud: boolean,
		safeArea: SafeArea,
	} =
		{
			viewport = viewport,
			scale = scale,
			breakpoint = breakpoint,
			deviceClass = deviceClass,
			isCompactHud = compactHud,
			safeArea = safeArea,
		}

	return {
		viewport = viewport,
		scale = scale,
		breakpoint = breakpoint,
		deviceClass = deviceClass,
		isSmall = breakpoint == "small",
		isCompactHud = compactHud,
		safeArea = safeArea,
		tokens = UiScaleUtils.GetTokens(metricInput),
	}
end

function UiScaleUtils.clampCenteredPanelOffset(
	offset: Vector2,
	panelSize: Vector2,
	panelScale: number,
	metrics: ResponsiveMetrics
): Vector2
	local visibleSize = panelSize * panelScale
	local safeArea = metrics.safeArea
	local minCenterX = safeArea.left + visibleSize.X * 0.5
	local maxCenterX = metrics.viewport.X - safeArea.right - visibleSize.X * 0.5
	local minCenterY = safeArea.top + visibleSize.Y * 0.5
	local maxCenterY = metrics.viewport.Y - safeArea.bottom - visibleSize.Y * 0.5
	local viewportCenter = metrics.viewport * 0.5

	if minCenterX > maxCenterX then
		minCenterX = viewportCenter.X
		maxCenterX = viewportCenter.X
	end
	if minCenterY > maxCenterY then
		minCenterY = viewportCenter.Y
		maxCenterY = viewportCenter.Y
	end

	local unclampedCenter = viewportCenter + offset
	local clampedCenter = Vector2.new(
		math.clamp(unclampedCenter.X, minCenterX, maxCenterX),
		math.clamp(unclampedCenter.Y, minCenterY, maxCenterY)
	)

	return clampedCenter - viewportCenter
end

return UiScaleUtils
