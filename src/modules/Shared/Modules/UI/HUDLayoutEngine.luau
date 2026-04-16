--!strict
local GuiService = game:GetService("GuiService")

local HUDLayoutEngine = {}
HUDLayoutEngine.__index = HUDLayoutEngine

export type LayoutDefinition = {
	id: string,
	frame: GuiObject,
	dock: string?,
	order: number?,
	offset: Vector2?,
	spacing: number?,
	visible: boolean?,
	baseSize: Vector2?,
	sizeScale: boolean?,
	constraints: {
		avoid: { string }?,
		pushDirection: "down" | "up" | "left" | "right"?,
	}?,
}

export type EngineConfig = {
	referenceHeight: number?,
	baseSpacing: number?,
	gamepadSpacingMultiplier: number?,
}

export type HUDLayoutEngine = typeof(setmetatable({} :: any, HUDLayoutEngine))

local PRESET_ANCHOR = {
	TopLeft = Vector2.new(0, 0),
	TopCenter = Vector2.new(0.5, 0),
	TopRight = Vector2.new(1, 0),
	LeftCenter = Vector2.new(0, 0.5),
	Center = Vector2.new(0.5, 0.5),
	RightCenter = Vector2.new(1, 0.5),
	BottomLeft = Vector2.new(0, 1),
	BottomCenter = Vector2.new(0.5, 1),
	BottomRight = Vector2.new(1, 1),
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

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function estimateSize(frame: GuiObject, viewport: Vector2): Vector2
	local absSize = frame.AbsoluteSize
	if absSize.X > 0 and absSize.Y > 0 then
		return absSize
	end
	local size = frame.Size
	local x = size.X.Offset + size.X.Scale * viewport.X
	local y = size.Y.Offset + size.Y.Scale * viewport.Y
	return Vector2.new(math.max(1, x), math.max(1, y))
end

local function computeRect(position: Vector2, anchor: Vector2, size: Vector2): { minX: number, minY: number, maxX: number, maxY: number }
	local minX = position.X - anchor.X * size.X
	local minY = position.Y - anchor.Y * size.Y
	return {
		minX = minX,
		minY = minY,
		maxX = minX + size.X,
		maxY = minY + size.Y,
	}
end

local function overlaps(a: any, b: any): boolean
	if a.maxX <= b.minX then
		return false
	end
	if b.maxX <= a.minX then
		return false
	end
	if a.maxY <= b.minY then
		return false
	end
	if b.maxY <= a.minY then
		return false
	end
	return true
end

local function sortDefinitions(a: any, b: any): boolean
	local orderA = a.order or 0
	local orderB = b.order or 0
	if orderA ~= orderB then
		return orderA < orderB
	end
	return a.id < b.id
end

function HUDLayoutEngine.New(configRaw: EngineConfig?): HUDLayoutEngine
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		definitions = {} :: { [string]: any },
		dockBuckets = {} :: { [string]: { any } },
		ordered = {} :: { any },
		placedRects = {} :: { [string]: any },
		viewport = Vector2.new(1920, 1080),
		safeTopLeft = Vector2.zero,
		safeBottomRight = Vector2.zero,
		referenceHeight = clampNumber(config.referenceHeight, 1080, 1, 10000),
		baseSpacing = clampNumber(config.baseSpacing, 10, 0, 500),
		gamepadSpacingMultiplier = clampNumber(config.gamepadSpacingMultiplier, 1.2, 1, 3),
		gamepadMode = false,
	}, HUDLayoutEngine)
	self:updateSafeZone()
	return self
end

function HUDLayoutEngine.UpdateSafeZone(self: HUDLayoutEngine)
	local topLeft, bottomRight = GuiService:GetGuiInset()
	self.safeTopLeft = topLeft
	self.safeBottomRight = bottomRight
end

function HUDLayoutEngine.SetViewport(self: HUDLayoutEngine, viewportRaw: any)
	if typeof(viewportRaw) == "Vector2" then
		self.viewport = Vector2.new(math.max(1, viewportRaw.X), math.max(1, viewportRaw.Y))
	end
end

function HUDLayoutEngine.SetGamepadMode(self: HUDLayoutEngine, enabledRaw: any)
	self.gamepadMode = enabledRaw == true
end

function HUDLayoutEngine.Register(self: HUDLayoutEngine, definitionRaw: any): boolean
	if typeof(definitionRaw) ~= "table" then
		return false
	end
	if typeof(definitionRaw.id) ~= "string" or definitionRaw.id == "" then
		return false
	end
	if typeof(definitionRaw.frame) ~= "Instance" or not definitionRaw.frame:IsA("GuiObject") then
		return false
	end
	local id = definitionRaw.id
	self.definitions[id] = {
		id = id,
		frame = definitionRaw.frame,
		dock = if typeof(definitionRaw.dock) == "string" and PRESET_ANCHOR[definitionRaw.dock] ~= nil then definitionRaw.dock else "TopLeft",
		order = if typeof(definitionRaw.order) == "number" then definitionRaw.order else 0,
		offset = if typeof(definitionRaw.offset) == "Vector2" then definitionRaw.offset else Vector2.zero,
		spacing = if typeof(definitionRaw.spacing) == "number" then definitionRaw.spacing else nil,
		visible = if definitionRaw.visible == nil then true else definitionRaw.visible == true,
		baseSize = if typeof(definitionRaw.baseSize) == "Vector2" then definitionRaw.baseSize else nil,
		sizeScale = definitionRaw.sizeScale == true,
		constraints = if typeof(definitionRaw.constraints) == "table" then definitionRaw.constraints else {},
	}
	return true
end

function HUDLayoutEngine.Unregister(self: HUDLayoutEngine, idRaw: any)
	if typeof(idRaw) ~= "string" then
		return
	end
	self.definitions[idRaw] = nil
	self.placedRects[idRaw] = nil
end

function HUDLayoutEngine.SetVisible(self: HUDLayoutEngine, idRaw: any, visibleRaw: any)
	if typeof(idRaw) ~= "string" then
		return
	end
	local definition = self.definitions[idRaw]
	if definition == nil then
		return
	end
	definition.visible = visibleRaw == true
	pcall(function()
		definition.frame.Visible = definition.visible
	end)
end

function HUDLayoutEngine.SetOrder(self: HUDLayoutEngine, idRaw: any, orderRaw: any)
	if typeof(idRaw) ~= "string" then
		return
	end
	local definition = self.definitions[idRaw]
	if definition == nil then
		return
	end
	if typeof(orderRaw) == "number" then
		definition.order = orderRaw
	end
end

function HUDLayoutEngine._buildBuckets(self: HUDLayoutEngine)
	table.clear(self.dockBuckets)
	clearArray(self.ordered)
	for _, definition in self.definitions do
		if definition.visible then
			local bucket = self.dockBuckets[definition.dock]
			if bucket == nil then
				bucket = {}
				self.dockBuckets[definition.dock] = bucket
			end
			bucket[#bucket + 1] = definition
			self.ordered[#self.ordered + 1] = definition
		end
	end
	for _, bucket in self.dockBuckets do
		table.sort(bucket, sortDefinitions)
	end
	table.sort(self.ordered, sortDefinitions)
end

function HUDLayoutEngine._basePosition(self: HUDLayoutEngine, dock: string): Vector2
	local viewport = self.viewport
	local safeTL = self.safeTopLeft
	local safeBR = self.safeBottomRight
	local left = safeTL.X
	local top = safeTL.Y
	local right = viewport.X - safeBR.X
	local bottom = viewport.Y - safeBR.Y
	if dock == "TopLeft" then
		return Vector2.new(left, top)
	end
	if dock == "TopCenter" then
		return Vector2.new((left + right) * 0.5, top)
	end
	if dock == "TopRight" then
		return Vector2.new(right, top)
	end
	if dock == "BottomLeft" then
		return Vector2.new(left, bottom)
	end
	if dock == "BottomCenter" then
		return Vector2.new((left + right) * 0.5, bottom)
	end
	if dock == "BottomRight" then
		return Vector2.new(right, bottom)
	end
	if dock == "LeftCenter" then
		return Vector2.new(left, (top + bottom) * 0.5)
	end
	if dock == "RightCenter" then
		return Vector2.new(right, (top + bottom) * 0.5)
	end
	return Vector2.new((left + right) * 0.5, (top + bottom) * 0.5)
end

function HUDLayoutEngine._flowDirection(self: HUDLayoutEngine, dock: string): Vector2
	if dock == "BottomLeft" or dock == "BottomCenter" or dock == "BottomRight" then
		return Vector2.new(0, -1)
	end
	if dock == "LeftCenter" then
		return Vector2.new(0, 1)
	end
	if dock == "RightCenter" then
		return Vector2.new(0, 1)
	end
	if dock == "Center" then
		return Vector2.new(0, 1)
	end
	return Vector2.new(0, 1)
end

function HUDLayoutEngine._resolveConstraint(self: HUDLayoutEngine, definition: any, position: Vector2, anchor: Vector2, size: Vector2, spacing: number): Vector2
	local constraints = definition.constraints
	if typeof(constraints) ~= "table" then
		return position
	end
	local avoid = constraints.avoid
	if typeof(avoid) ~= "table" or #avoid == 0 then
		return position
	end

	local direction = if constraints.pushDirection == "up" then Vector2.new(0, -1) elseif constraints.pushDirection == "left" then Vector2.new(-1, 0) elseif constraints.pushDirection == "right" then Vector2.new(1, 0) else Vector2.new(0, 1)
	local rect = computeRect(position, anchor, size)
	for _, avoidId in avoid do
		local otherRect = self.placedRects[avoidId]
		if otherRect ~= nil and overlaps(rect, otherRect) then
			if direction.Y ~= 0 then
				if direction.Y > 0 then
					position = Vector2.new(position.X, otherRect.maxY + spacing + anchor.Y * size.Y)
				else
					position = Vector2.new(position.X, otherRect.minY - spacing - (1 - anchor.Y) * size.Y)
				end
			else
				if direction.X > 0 then
					position = Vector2.new(otherRect.maxX + spacing + anchor.X * size.X, position.Y)
				else
					position = Vector2.new(otherRect.minX - spacing - (1 - anchor.X) * size.X, position.Y)
				end
			end
			rect = computeRect(position, anchor, size)
		end
	end

	return position
end

function HUDLayoutEngine.Reflow(self: HUDLayoutEngine)
	self:updateSafeZone()
	self:_buildBuckets()
	table.clear(self.placedRects)

	local scale = self.viewport.Y / self.referenceHeight
	local spacingScale = if self.gamepadMode then self.gamepadSpacingMultiplier else 1

	for dock, bucket in self.dockBuckets do
		local cursor = self:_basePosition(dock)
		local direction = self:_flowDirection(dock)
		local anchor = PRESET_ANCHOR[dock] or Vector2.zero
		for index = 1, #bucket do
			local definition = bucket[index]
			local frame = definition.frame :: GuiObject
			local spacing = (if definition.spacing ~= nil then definition.spacing else self.baseSpacing) * scale * spacingScale
			if definition.baseSize ~= nil and definition.sizeScale then
				local size = definition.baseSize
				frame.Size = UDim2.fromOffset(math.floor(size.X * scale + 0.5), math.floor(size.Y * scale + 0.5))
			end

			local size = estimateSize(frame, self.viewport)
			local position = cursor + definition.offset * scale
			position = self:_resolveConstraint(definition, position, anchor, size, spacing)
			frame.AnchorPoint = anchor
			frame.Position = UDim2.fromOffset(math.floor(position.X + 0.5), math.floor(position.Y + 0.5))

			self.placedRects[definition.id] = computeRect(position, anchor, size)
			cursor = cursor + Vector2.new(direction.X * (size.X + spacing), direction.Y * (size.Y + spacing))
		end
	end
end

function HUDLayoutEngine.GetDefinition(self: HUDLayoutEngine, idRaw: any): LayoutDefinition?
	if typeof(idRaw) ~= "string" then
		return nil
	end
	return self.definitions[idRaw]
end

function HUDLayoutEngine.Destroy(self: HUDLayoutEngine)
	table.clear(self.definitions)
	table.clear(self.dockBuckets)
	table.clear(self.placedRects)
	clearArray(self.ordered)
end

HUDLayoutEngine.new = HUDLayoutEngine.New
HUDLayoutEngine.updateSafeZone = HUDLayoutEngine.UpdateSafeZone
HUDLayoutEngine.setViewport = HUDLayoutEngine.SetViewport
HUDLayoutEngine.setGamepadMode = HUDLayoutEngine.SetGamepadMode
HUDLayoutEngine.register = HUDLayoutEngine.Register
HUDLayoutEngine.unregister = HUDLayoutEngine.Unregister
HUDLayoutEngine.setVisible = HUDLayoutEngine.SetVisible
HUDLayoutEngine.setOrder = HUDLayoutEngine.SetOrder
HUDLayoutEngine.reflow = HUDLayoutEngine.Reflow
HUDLayoutEngine.getDefinition = HUDLayoutEngine.GetDefinition
HUDLayoutEngine.destroy = HUDLayoutEngine.Destroy

return HUDLayoutEngine
