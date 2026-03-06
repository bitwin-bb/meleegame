--!strict
local RunService = game:GetService("RunService")

local NotificationBus = {}
NotificationBus.__index = NotificationBus

export type NotificationConfig = {
	container: GuiObject,
	eventBus: any?,
	springAnimator: any?,
	tickScheduler: any?,
	maxVisible: number?,
	maxQueue: number?,
	maxPoolSize: number?,
	rateLimitPerSecond: number?,
	defaultDuration: number?,
	mergeWindow: number?,
	layoutDirection: "Down" | "Up"?,
	sanitizePayload: ((payload: any) -> any)?,
	formatPayload: ((key: string, payload: any, count: number) -> string)?,
	createItem: (() -> GuiObject)?,
	resetItem: ((item: GuiObject) -> ())?,
	subscriptions: { { channel: string, event: string?, map: ((payload: any) -> { key: string, payload: any, config: any? }?)? } }?,
}

export type NotificationBus = typeof(setmetatable({} :: any, NotificationBus))

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

local function safeDisconnect(connection: any?)
	if connection == nil then
		return
	end
	pcall(function()
		connection:Disconnect()
	end)
end

local function defaultCreateItem(): GuiObject
	local frame = Instance.new("Frame")
	frame.Name = "NotificationItem"
	frame.Size = UDim2.new(1, 0, 0, 28)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, -12, 1, 0)
	label.Position = UDim2.fromOffset(6, 0)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.RichText = true
	label.Text = ""
	label.Parent = frame

	return frame
end

local function defaultResetItem(item: GuiObject)
	item.Visible = false
	item.Parent = nil
	local label = item:FindFirstChild("Label")
	if label ~= nil and label:IsA("TextLabel") then
		label.Text = ""
		label.TextTransparency = 0
	end
	item.BackgroundTransparency = 0.2
end

local function defaultSanitizePayload(payload: any): any
	if typeof(payload) == "table" then
		return table.clone(payload)
	end
	return payload
end

local function defaultFormatPayload(key: string, payload: any, count: number): string
	if typeof(payload) == "string" then
		if count > 1 then
			return string.format("%s x%d", payload, count)
		end
		return payload
	end
	if typeof(payload) == "table" then
		if typeof(payload.text) == "string" then
			if count > 1 then
				return string.format("%s x%d", payload.text, count)
			end
			return payload.text
		end
		if typeof(payload.amount) == "number" then
			local amountText = tostring(payload.amount * count)
			if typeof(payload.label) == "string" then
				return string.format("+%s %s", amountText, payload.label)
			end
		end
	end
	if count > 1 then
		return string.format("%s x%d", key, count)
	end
	return key
end

local function compareQueued(a: any, b: any): boolean
	if a.priority ~= b.priority then
		return a.priority > b.priority
	end
	return a.order < b.order
end

function NotificationBus.new(configRaw: NotificationConfig): NotificationBus
	if typeof(configRaw) ~= "table" or typeof(configRaw.container) ~= "Instance" then
		error("NotificationBus.new expects config.container")
	end
	local self = setmetatable({
		container = configRaw.container,
		eventBus = configRaw.eventBus,
		springAnimator = configRaw.springAnimator,
		tickScheduler = configRaw.tickScheduler,
		maxVisible = clampInteger(configRaw.maxVisible, 6, 1, 100),
		maxQueue = clampInteger(configRaw.maxQueue, 200, 1, 10000),
		maxPoolSize = clampInteger(configRaw.maxPoolSize, 32, 1, 1000),
		rateLimitPerSecond = clampNumber(configRaw.rateLimitPerSecond, 20, 1, 500),
		defaultDuration = clampNumber(configRaw.defaultDuration, 2.5, 0.1, 30),
		mergeWindow = clampNumber(configRaw.mergeWindow, 0.6, 0, 10),
		layoutDirection = if configRaw.layoutDirection == "Up" then "Up" else "Down",
		sanitizePayload = if typeof(configRaw.sanitizePayload) == "function" then configRaw.sanitizePayload else defaultSanitizePayload,
		formatPayload = if typeof(configRaw.formatPayload) == "function" then configRaw.formatPayload else defaultFormatPayload,
		createItem = if typeof(configRaw.createItem) == "function" then configRaw.createItem else defaultCreateItem,
		resetItem = if typeof(configRaw.resetItem) == "function" then configRaw.resetItem else defaultResetItem,
		subscriptions = if typeof(configRaw.subscriptions) == "table" then configRaw.subscriptions else {},
		active = {} :: { any },
		activeByMergeKey = {} :: { [string]: any },
		queue = {} :: { any },
		pool = {} :: { GuiObject },
		pendingRelease = {} :: { any },
		recentTimestamps = {} :: { number },
		now = 0,
		orderCounter = 0,
		isInitialized = false,
		loopToken = nil,
		heartbeatConnection = nil,
		connections = {} :: { any },
	}, NotificationBus)
	return self
end

function NotificationBus._ensureLoop(self: NotificationBus)
	if self.loopToken ~= nil or self.heartbeatConnection ~= nil then
		return
	end
	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).scheduleEvery) == "function" then
		self.loopToken = (self.tickScheduler :: any):scheduleEvery(function(dt: number)
			self:update(dt)
		end, 1 / 30, {
			group = "ui.notifications",
			priority = 100,
			catchUp = false,
		})
		return
	end
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		self:update(dt)
	end)
end

function NotificationBus._acquireItem(self: NotificationBus): GuiObject
	local item = table.remove(self.pool)
	if item ~= nil then
		return item
	end
	return self.createItem()
end

function NotificationBus._releaseItem(self: NotificationBus, item: GuiObject)
	self.resetItem(item)
	self.pool[#self.pool + 1] = item
	if #self.pool > self.maxPoolSize then
		local old = table.remove(self.pool, 1)
		if old ~= nil then
			old:Destroy()
		end
	end
end

function NotificationBus._setItemText(self: NotificationBus, item: GuiObject, text: string)
	local label = item:FindFirstChild("Label")
	if label ~= nil and label:IsA("TextLabel") then
		label.Text = text
	end
end

function NotificationBus._animateIn(self: NotificationBus, entry: any)
	local item = entry.item
	item.Visible = true
	item.Parent = self.container
	item.BackgroundTransparency = 1
	local label = item:FindFirstChild("Label")
	if label ~= nil and label:IsA("TextLabel") then
		label.TextTransparency = 1
	end
	if self.springAnimator ~= nil and typeof((self.springAnimator :: any).animate) == "function" then
		local springAnimatorAny = self.springAnimator :: any
		springAnimatorAny:animate(item, "BackgroundTransparency", 0.2, {
			frequency = 7,
			dampingRatio = 1,
		})
		if label ~= nil and label:IsA("TextLabel") then
			springAnimatorAny:animate(label, "TextTransparency", 0, {
				frequency = 7,
				dampingRatio = 1,
			})
		end
	else
		item.BackgroundTransparency = 0.2
		if label ~= nil and label:IsA("TextLabel") then
			label.TextTransparency = 0
		end
	end
end

function NotificationBus._animateOut(self: NotificationBus, entry: any)
	local item = entry.item
	local label = item:FindFirstChild("Label")
	if self.springAnimator ~= nil and typeof((self.springAnimator :: any).animate) == "function" then
		local springAnimatorAny = self.springAnimator :: any
		springAnimatorAny:animate(item, "BackgroundTransparency", 1, {
			frequency = 7,
			dampingRatio = 1,
		})
		if label ~= nil and label:IsA("TextLabel") then
			springAnimatorAny:animate(label, "TextTransparency", 1, {
				frequency = 7,
				dampingRatio = 1,
			})
		end
	else
		item.BackgroundTransparency = 1
		if label ~= nil and label:IsA("TextLabel") then
			label.TextTransparency = 1
		end
	end
	self.pendingRelease[#self.pendingRelease + 1] = {
		item = item,
		releaseAt = self.now + 0.25,
	}
end

function NotificationBus._layout(self: NotificationBus)
	local count = #self.active
	for index = 1, count do
		local entry = self.active[index]
		if self.layoutDirection == "Up" then
			entry.item.LayoutOrder = count - index + 1
		else
			entry.item.LayoutOrder = index
		end
	end
end

function NotificationBus._consumeRateSlots(self: NotificationBus)
	local cutoff = self.now - 1
	for index = #self.recentTimestamps, 1, -1 do
		if self.recentTimestamps[index] >= cutoff then
			continue
		end
		table.remove(self.recentTimestamps, index)
	end
end

function NotificationBus._canEmitNow(self: NotificationBus): boolean
	self:_consumeRateSlots()
	return #self.recentTimestamps < self.rateLimitPerSecond
end

function NotificationBus._emitFromQueue(self: NotificationBus)
	if #self.queue == 0 then
		return
	end
	if not self:_canEmitNow() then
		return
	end
	local entry = table.remove(self.queue, 1)
	if entry == nil then
		return
	end
	entry.item = self:_acquireItem()
	entry.expireAt = self.now + entry.duration
	entry.isHiding = false
	self:_setItemText(entry.item, entry.text)
	self.active[#self.active + 1] = entry
	self.activeByMergeKey[entry.mergeKey] = entry
	self.recentTimestamps[#self.recentTimestamps + 1] = self.now
	self:_animateIn(entry)
	self:_layout()

	while #self.active > self.maxVisible do
		self:_beginHide(self.active[1])
	end
end

function NotificationBus._beginHide(self: NotificationBus, entry: any)
	if entry == nil or entry.isHiding then
		return
	end
	entry.isHiding = true
	self.activeByMergeKey[entry.mergeKey] = nil
	for index = #self.active, 1, -1 do
		if self.active[index] == entry then
			table.remove(self.active, index)
			break
		end
	end
	self:_animateOut(entry)
	self:_layout()
end

function NotificationBus._findMergeCandidate(self: NotificationBus, mergeKey: string): any
	local active = self.activeByMergeKey[mergeKey]
	if active ~= nil and (self.now - active.lastUpdatedAt) <= self.mergeWindow then
		return active
	end
	for _, queued in self.queue do
		if queued.mergeKey == mergeKey and (self.now - queued.lastUpdatedAt) <= self.mergeWindow then
			return queued
		end
	end
	return nil
end

function NotificationBus.notify(self: NotificationBus, keyRaw: any, payloadRaw: any, configRaw: any?): boolean
	if typeof(keyRaw) ~= "string" or keyRaw == "" then
		return false
	end
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local payload = self.sanitizePayload(payloadRaw)
	local priority = clampInteger(config.priority, 0, -1000000, 1000000)
	local duration = clampNumber(config.duration, self.defaultDuration, 0.1, 60)
	local mergeKey = if typeof(config.mergeKey) == "string" and config.mergeKey ~= "" then config.mergeKey else keyRaw

	local candidate = self:_findMergeCandidate(mergeKey)
	if candidate ~= nil then
		candidate.count += if typeof(config.incrementBy) == "number" then math.max(1, math.floor(config.incrementBy)) else 1
		candidate.payload = payload
		candidate.lastUpdatedAt = self.now
		candidate.expireAt = self.now + duration
		candidate.text = self.formatPayload(keyRaw, payload, candidate.count)
		if candidate.item ~= nil then
			self:_setItemText(candidate.item, candidate.text)
		end
		return true
	end

	self.orderCounter += 1
	local entry = {
		key = keyRaw,
		mergeKey = mergeKey,
		payload = payload,
		priority = priority,
		duration = duration,
		count = 1,
		text = self.formatPayload(keyRaw, payload, 1),
		order = self.orderCounter,
		receivedAt = self.now,
		lastUpdatedAt = self.now,
		item = nil,
		isHiding = false,
	}

	self.queue[#self.queue + 1] = entry
	table.sort(self.queue, compareQueued)
	while #self.queue > self.maxQueue do
		table.remove(self.queue)
	end
	return true
end

function NotificationBus.notifyDamageResult(self: NotificationBus, resultRaw: any, configRaw: any?): boolean
	if typeof(resultRaw) ~= "table" then
		return false
	end
	local damageValue = if typeof(resultRaw.finalDamage) == "number" then resultRaw.finalDamage else if typeof(resultRaw.damage) == "number" then resultRaw.damage else nil
	if damageValue == nil then
		return false
	end
	local rounded = math.floor(math.max(0, damageValue) + 0.5)
	local text = string.format("-%d HP", rounded)
	if resultRaw.wasCrit == true then
		text = string.format("<b>%s</b> <font color=\"#FFD35A\">CRIT</font>", text)
	end
	local payload = {
		text = text,
	}
	local key = "damage"
	if typeof(configRaw) == "table" and typeof(configRaw.key) == "string" and configRaw.key ~= "" then
		key = configRaw.key
	end
	return self:notify(key, payload, configRaw)
end

function NotificationBus.update(self: NotificationBus, dtRaw: any)
	local dt = clampNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end
	self.now += dt

	for index = #self.active, 1, -1 do
		local entry = self.active[index]
		if self.now >= entry.expireAt then
			self:_beginHide(entry)
		end
	end

	for index = #self.pendingRelease, 1, -1 do
		local pending = self.pendingRelease[index]
		if self.now < pending.releaseAt then
			continue
		end
		self:_releaseItem(pending.item)
		table.remove(self.pendingRelease, index)
	end

	self:_emitFromQueue()
end

function NotificationBus.init(self: NotificationBus)
	if self.isInitialized then
		return
	end
	self.isInitialized = true
	self:_ensureLoop()

	if self.eventBus ~= nil and typeof((self.eventBus :: any).subscribe) == "function" then
		for _, sub in self.subscriptions do
			if typeof(sub) ~= "table" or typeof(sub.channel) ~= "string" then
				continue
			end
			local eventName = if typeof(sub.event) == "string" then sub.event else "*"
			local disconnect = (self.eventBus :: any):subscribe(sub.channel, eventName, function(payload: any)
				local mapped = nil
				if typeof(sub.map) == "function" then
					mapped = sub.map(payload)
				end
				if mapped ~= nil and typeof(mapped) == "table" and typeof(mapped.key) == "string" then
					self:notify(mapped.key, mapped.payload, mapped.config)
					return
				end
				self:notify(eventName, payload, nil)
			end)
			self.connections[#self.connections + 1] = {
				disconnect = disconnect,
			}
		end
	end
end

function NotificationBus.destroy(self: NotificationBus)
	if self.loopToken ~= nil then
		if typeof(self.loopToken.cancel) == "function" then
			self.loopToken:cancel()
		elseif self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).cancel) == "function" then
			local schedulerAny = self.tickScheduler :: any
			schedulerAny:cancel(self.loopToken)
		end
		self.loopToken = nil
	end
	if self.heartbeatConnection ~= nil then
		safeDisconnect(self.heartbeatConnection)
		self.heartbeatConnection = nil
	end

	for index = #self.connections, 1, -1 do
		local connection = self.connections[index]
		if typeof(connection) == "table" and typeof(connection.disconnect) == "function" then
			connection.disconnect()
		end
		self.connections[index] = nil
	end

	for index = #self.active, 1, -1 do
		local entry = self.active[index]
		if entry.item ~= nil then
			self:_releaseItem(entry.item)
		end
		self.active[index] = nil
	end
	for index = #self.pendingRelease, 1, -1 do
		self:_releaseItem(self.pendingRelease[index].item)
		self.pendingRelease[index] = nil
	end
	for index = #self.pool, 1, -1 do
		self.pool[index]:Destroy()
		self.pool[index] = nil
	end
	table.clear(self.activeByMergeKey)
	table.clear(self.queue)
	table.clear(self.recentTimestamps)
	self.isInitialized = false
end

NotificationBus.Notify = NotificationBus.notify
NotificationBus.NotifyDamageResult = NotificationBus.notifyDamageResult
NotificationBus.Init = NotificationBus.init
NotificationBus.Update = NotificationBus.update

return NotificationBus
