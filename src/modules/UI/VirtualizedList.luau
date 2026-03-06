--!strict
local VirtualizedList = {}
VirtualizedList.__index = VirtualizedList

export type VirtualizedListConfig = {
	scrollingFrame: ScrollingFrame,
	createItem: ((recycled: GuiObject?) -> GuiObject)?,
	bindItem: ((item: GuiObject, data: any, index: number) -> ())?,
	resetItem: ((item: GuiObject) -> ())?,
	getItemHeight: ((data: any, index: number, measureCache: any?) -> number)?,
	measureCache: any?,
	itemHeight: number?,
	overscan: number?,
	maxPoolSize: number?,
	paddingTop: number?,
	paddingBottom: number?,
	zIndex: number?,
}

export type VirtualizedList = typeof(setmetatable({} :: any, VirtualizedList))

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

local function safeDisconnect(connection: any?)
	if connection == nil then
		return
	end
	pcall(function()
		connection:Disconnect()
	end)
end

local function defaultCreateItem(_: GuiObject?): GuiObject
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 32)
	return frame
end

local function defaultBindItem(_: GuiObject, _: any, _: number)
end

local function defaultResetItem(item: GuiObject)
	item.Visible = false
	item.Parent = nil
end

function VirtualizedList.new(configRaw: VirtualizedListConfig): VirtualizedList
	if typeof(configRaw) ~= "table" or typeof(configRaw.scrollingFrame) ~= "Instance" then
		error("VirtualizedList.new expects a config with scrollingFrame")
	end
	local scrollingFrame = configRaw.scrollingFrame :: ScrollingFrame
	local self = setmetatable({
		scrollingFrame = scrollingFrame,
		createItem = if typeof(configRaw.createItem) == "function" then configRaw.createItem else defaultCreateItem,
		bindItem = if typeof(configRaw.bindItem) == "function" then configRaw.bindItem else defaultBindItem,
		resetItem = if typeof(configRaw.resetItem) == "function" then configRaw.resetItem else defaultResetItem,
		getItemHeight = if typeof(configRaw.getItemHeight) == "function" then configRaw.getItemHeight else nil,
		measureCache = configRaw.measureCache,
		itemHeight = clampNumber(configRaw.itemHeight, 32, 1, 10000),
		overscan = clampInteger(configRaw.overscan, 4, 0, 100),
		maxPoolSize = clampInteger(configRaw.maxPoolSize, 256, 1, 50000),
		paddingTop = clampNumber(configRaw.paddingTop, 0, 0, 10000),
		paddingBottom = clampNumber(configRaw.paddingBottom, 0, 0, 10000),
		baseZIndex = clampInteger(configRaw.zIndex, 1, 1, 10000),
		data = {} :: { any },
		itemHeights = {} :: { number },
		prefix = { 0 } :: { number },
		visibleItems = {} :: { [number]: GuiObject },
		visibleOrder = {} :: { number },
		neededMap = {} :: { [number]: boolean },
		pool = {} :: { GuiObject },
		connections = {} :: { any },
		totalHeight = 0,
	}, VirtualizedList)

	self.connections[#self.connections + 1] = scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_renderVisible()
	end)
	self.connections[#self.connections + 1] = scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_renderVisible()
	end)

	return self
end

function VirtualizedList._estimateHeight(self: VirtualizedList, data: any, index: number): number
	if self.getItemHeight ~= nil then
		local result = self.getItemHeight(data, index, self.measureCache)
		if typeof(result) == "number" then
			return clampNumber(result, self.itemHeight, 1, 10000)
		end
	end
	return self.itemHeight
end

function VirtualizedList._rebuildLayout(self: VirtualizedList)
	local data = self.data
	local count = #data
	local prefix = self.prefix
	prefix[1] = self.paddingTop
	for index = 1, count do
		local height = self:_estimateHeight(data[index], index)
		self.itemHeights[index] = height
		prefix[index + 1] = prefix[index] + height
	end
	for index = #self.itemHeights, count + 1, -1 do
		self.itemHeights[index] = nil
	end
	for index = #prefix, count + 2, -1 do
		prefix[index] = nil
	end
	self.totalHeight = prefix[count + 1] + self.paddingBottom
	self.scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(0, math.floor(self.totalHeight + 0.5)))
end

function VirtualizedList._findIndexAtOffset(self: VirtualizedList, offsetY: number): number
	local prefix = self.prefix
	local count = #self.data
	if count <= 0 then
		return 1
	end
	if offsetY <= prefix[1] then
		return 1
	end
	if offsetY >= prefix[count + 1] then
		return count
	end
	local low = 1
	local high = count
	while low <= high do
		local mid = math.floor((low + high) * 0.5)
		local minY = prefix[mid]
		local maxY = prefix[mid + 1]
		if offsetY < minY then
			high = mid - 1
		elseif offsetY >= maxY then
			low = mid + 1
		else
			return mid
		end
	end
	return math.clamp(low, 1, count)
end

function VirtualizedList._acquireItem(self: VirtualizedList): GuiObject
	local item = table.remove(self.pool)
	if item ~= nil then
		return item
	end
	return self.createItem(nil)
end

function VirtualizedList._releaseItem(self: VirtualizedList, item: GuiObject)
	self.resetItem(item)
	if #self.pool < self.maxPoolSize then
		self.pool[#self.pool + 1] = item
		return
	end
	item:Destroy()
end

function VirtualizedList._renderVisible(self: VirtualizedList)
	local count = #self.data
	if count <= 0 then
		for index = #self.visibleOrder, 1, -1 do
			local itemIndex = self.visibleOrder[index]
			local item = self.visibleItems[itemIndex]
			if item ~= nil then
				self.visibleItems[itemIndex] = nil
				self:_releaseItem(item)
			end
		end
		clearArray(self.visibleOrder)
		return
	end

	local viewportHeight = self.scrollingFrame.AbsoluteWindowSize.Y
	if viewportHeight <= 0 then
		viewportHeight = self.scrollingFrame.AbsoluteSize.Y
	end
	local topY = self.scrollingFrame.CanvasPosition.Y
	local bottomY = topY + math.max(1, viewportHeight)

	local startIndex = self:_findIndexAtOffset(topY)
	local endIndex = self:_findIndexAtOffset(bottomY)
	startIndex = math.max(1, startIndex - self.overscan)
	endIndex = math.min(count, endIndex + self.overscan)

	local needed = self.neededMap
	table.clear(needed)
	for index = startIndex, endIndex do
		needed[index] = true
	end

	for index = #self.visibleOrder, 1, -1 do
		local itemIndex = self.visibleOrder[index]
		if needed[itemIndex] then
			continue
		end
		local item = self.visibleItems[itemIndex]
		if item ~= nil then
			self.visibleItems[itemIndex] = nil
			self:_releaseItem(item)
		end
		table.remove(self.visibleOrder, index)
	end

	for index = startIndex, endIndex do
		local item = self.visibleItems[index]
		if item == nil then
			item = self:_acquireItem()
			item.Visible = true
			item.Parent = self.scrollingFrame
			item.ZIndex = self.baseZIndex
			self.visibleItems[index] = item
			self.visibleOrder[#self.visibleOrder + 1] = index
		end
		local y = self.prefix[index]
		local height = self.itemHeights[index]
		item.Size = UDim2.new(1, 0, 0, math.floor(height + 0.5))
		item.Position = UDim2.fromOffset(0, math.floor(y + 0.5))
		item.LayoutOrder = index
		self.bindItem(item, self.data[index], index)
	end
	table.sort(self.visibleOrder)
end

function VirtualizedList.setData(self: VirtualizedList, dataRaw: any)
	if typeof(dataRaw) ~= "table" then
		self.data = {}
	else
		self.data = table.clone(dataRaw)
	end

	local oldTopIndex = self:_findIndexAtOffset(self.scrollingFrame.CanvasPosition.Y)
	local oldTopOffset = self.scrollingFrame.CanvasPosition.Y - self.prefix[oldTopIndex]

	self:_rebuildLayout()

	if #self.data > 0 then
		local targetIndex = math.clamp(oldTopIndex, 1, #self.data)
		local newOffset = self.prefix[targetIndex] + oldTopOffset
		self.scrollingFrame.CanvasPosition = Vector2.new(self.scrollingFrame.CanvasPosition.X, math.max(0, newOffset))
	else
		self.scrollingFrame.CanvasPosition = Vector2.new(self.scrollingFrame.CanvasPosition.X, 0)
	end

	self:_renderVisible()
end

function VirtualizedList.refresh(self: VirtualizedList)
	self:_rebuildLayout()
	self:_renderVisible()
end

function VirtualizedList.scrollToIndex(self: VirtualizedList, indexRaw: any, alignRaw: any?)
	local count = #self.data
	if count <= 0 then
		return
	end
	local index = clampInteger(indexRaw, 1, 1, count)
	local align = if alignRaw == "center" or alignRaw == "end" then alignRaw else "start"
	local top = self.prefix[index]
	local height = self.itemHeights[index]
	local viewportHeight = self.scrollingFrame.AbsoluteWindowSize.Y
	if viewportHeight <= 0 then
		viewportHeight = self.scrollingFrame.AbsoluteSize.Y
	end

	local targetY = top
	if align == "center" then
		targetY = top - (viewportHeight - height) * 0.5
	elseif align == "end" then
		targetY = top - (viewportHeight - height)
	end

	self.scrollingFrame.CanvasPosition = Vector2.new(self.scrollingFrame.CanvasPosition.X, math.max(0, math.floor(targetY + 0.5)))
	self:_renderVisible()
end

function VirtualizedList.getVisibleRange(self: VirtualizedList): (number, number)
	if #self.visibleOrder == 0 then
		return 0, 0
	end
	return self.visibleOrder[1], self.visibleOrder[#self.visibleOrder]
end

function VirtualizedList.destroy(self: VirtualizedList)
	for index = #self.connections, 1, -1 do
		safeDisconnect(self.connections[index])
		self.connections[index] = nil
	end
	for index = #self.visibleOrder, 1, -1 do
		local itemIndex = self.visibleOrder[index]
		local item = self.visibleItems[itemIndex]
		if item ~= nil then
			self.visibleItems[itemIndex] = nil
			self:_releaseItem(item)
		end
	end
	clearArray(self.visibleOrder)
	table.clear(self.neededMap)
	for index = #self.pool, 1, -1 do
		self.pool[index]:Destroy()
		self.pool[index] = nil
	end
	clearArray(self.data)
	clearArray(self.itemHeights)
	clearArray(self.prefix)
	self.prefix[1] = 0
end

VirtualizedList.SetData = VirtualizedList.setData
VirtualizedList.ScrollToIndex = VirtualizedList.scrollToIndex
VirtualizedList.Refresh = VirtualizedList.refresh

return VirtualizedList
