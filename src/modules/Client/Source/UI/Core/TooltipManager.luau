local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DynamicTextGetter = require("DynamicTextGetter")
local MaidTaskUtils = require("MaidTaskUtils")
local RichTextFormatter = require("RichTextFormatter")
local StatStringBuilder = require("StatStringBuilder")
local String = require("String")
local TextMeasurementCache = require("TextMeasurementCache")

local TooltipManager = {}
TooltipManager.__index = TooltipManager

local function createRuntimeInstanceName(): string
	local guid = String.removePostfix(String.removePrefix(HttpService:GenerateGUID(true), "{"), "}")
	return string.format("%03d", (tonumber(string.sub(guid, 1, 8), 16) or 0) % 1000)
end

export type TooltipManagerConfig = {
	container: GuiObject,
	springAnimator: any?,
	tickScheduler: any?,
	textGetter: any?,
	richTextFormatter: any?,
	statStringBuilder: any?,
	textMeasurementCache: any?,
	createTooltipFrame: (() -> Frame)?,
	maxPoolSize: number?,
	offset: Vector2?,
	maxWidth: number?,
}

export type TooltipMetadata = {
	title: string?,
	description: string?,
	rarity: string?,
	stats: any?,
	compareStats: any?,
	statDefinitions: any?,
	statBreakdown: any?,
	extraLines: { string }?,
	context: { [string]: any }?,
	maxWidth: number?,
}

local RARITY_PRESET = {
	common = "rarityCommon",
	uncommon = "rarityUncommon",
	rare = "rarityRare",
	epic = "rarityEpic",
	legendary = "rarityLegendary",
}

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

local function safeDisconnect(connection: any?)
	if connection == nil or not MaidTaskUtils.isValidTask(connection) then
		return
	end
	pcall(function()
		MaidTaskUtils.doTask(connection)
	end)
end

local function defaultCreateTooltipFrame(): Frame
	local frame = Instance.new("Frame")
	frame.Name = createRuntimeInstanceName()
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
	frame.BackgroundTransparency = 0.15
	frame.BorderColor3 = Color3.fromRGB(50, 50, 60)
	frame.BorderSizePixel = 1
	frame.Size = UDim2.fromOffset(280, 120)
	frame.Visible = false
	frame.ZIndex = 900

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = createRuntimeInstanceName()
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromOffset(0, 0)
	label.Font = Enum.Font.PatrickHand
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.RichText = true
	label.ZIndex = 901
	label.Parent = frame

	local uiScale = Instance.new("UIScale")
	uiScale.Name = createRuntimeInstanceName()
	uiScale.Scale = 1
	uiScale.Parent = frame

	return frame
end

function TooltipManager.New(configRaw: TooltipManagerConfig): any
	if typeof(configRaw) ~= "table" or typeof(configRaw.container) ~= "Instance" then
		error("TooltipManager.New expects config.container")
	end
	local self = setmetatable({
		container = configRaw.container,
		springAnimator = configRaw.springAnimator,
		textGetter = if configRaw.textGetter ~= nil then configRaw.textGetter else DynamicTextGetter.New(),
		rich = if configRaw.richTextFormatter ~= nil then configRaw.richTextFormatter else RichTextFormatter,
		stats = if configRaw.statStringBuilder ~= nil then configRaw.statStringBuilder else StatStringBuilder.New(),
		measure = if configRaw.textMeasurementCache ~= nil
			then configRaw.textMeasurementCache
			else TextMeasurementCache.New(),
		createTooltipFrame = if typeof(configRaw.createTooltipFrame) == "function"
			then configRaw.createTooltipFrame
			else defaultCreateTooltipFrame,
		maxPoolSize = clampInteger(configRaw.maxPoolSize, 12, 1, 100),
		offset = if typeof(configRaw.offset) == "Vector2" then configRaw.offset else Vector2.new(18, 18),
		defaultMaxWidth = clampInteger(configRaw.maxWidth, 320, 80, 1200),
		pool = {} :: { Frame },
		activePrimary = nil :: Frame?,
		activeCompare = nil :: Frame?,
		tickScheduler = configRaw.tickScheduler,
		positionToken = nil,
		positionConnection = nil,
		hoverConnections = {} :: { any },
		isVisible = false,
	}, TooltipManager)
	return self
end

function TooltipManager._acquire(self: any): Frame
	local frame = table.remove(self.pool)
	if frame ~= nil then
		return frame
	end
	return self.createTooltipFrame()
end

function TooltipManager._release(self: any, frame: Frame?)
	if frame == nil then
		return
	end
	frame.Visible = false
	frame.Parent = nil
	if #self.pool < self.maxPoolSize then
		self.pool[#self.pool + 1] = frame
		return
	end
	frame:Destroy()
end

function TooltipManager._animateShow(self: any, frame: Frame)
	local label = frame:FindFirstChild("Body")
	local scale = frame:FindFirstChild("Scale")
	frame.Visible = true
	frame.BackgroundTransparency = 1
	if label ~= nil and label:IsA("TextLabel") then
		label.TextTransparency = 1
	end
	if scale ~= nil and scale:IsA("UIScale") then
		scale.Scale = 0.96
	end
	if self.springAnimator ~= nil and typeof((self.springAnimator :: any).animate) == "function" then
		local springAnimatorAny = self.springAnimator :: any
		springAnimatorAny:Animate(frame, "BackgroundTransparency", 0.15, { frequency = 9, dampingRatio = 1 })
		if label ~= nil and label:IsA("TextLabel") then
			springAnimatorAny:Animate(label, "TextTransparency", 0, { frequency = 9, dampingRatio = 1 })
		end
		if scale ~= nil and scale:IsA("UIScale") then
			springAnimatorAny:Animate(scale, "Scale", 1, { frequency = 8, dampingRatio = 1 })
		end
	else
		frame.BackgroundTransparency = 0.15
		if label ~= nil and label:IsA("TextLabel") then
			label.TextTransparency = 0
		end
		if scale ~= nil and scale:IsA("UIScale") then
			scale.Scale = 1
		end
	end
end

function TooltipManager._animateHide(self: any, frame: Frame)
	local label = frame:FindFirstChild("Body")
	local scale = frame:FindFirstChild("Scale")
	if self.springAnimator ~= nil and typeof((self.springAnimator :: any).animate) == "function" then
		local springAnimatorAny = self.springAnimator :: any
		springAnimatorAny:Animate(frame, "BackgroundTransparency", 1, { frequency = 10, dampingRatio = 1 })
		if label ~= nil and label:IsA("TextLabel") then
			springAnimatorAny:Animate(label, "TextTransparency", 1, { frequency = 10, dampingRatio = 1 })
		end
		if scale ~= nil and scale:IsA("UIScale") then
			springAnimatorAny:Animate(scale, "Scale", 0.96, { frequency = 10, dampingRatio = 1 })
		end
		task.delay(0.22, function()
			self:_release(frame)
		end)
	else
		self:_release(frame)
	end
end

function TooltipManager._composeText(
	self: any,
	metadataRaw: TooltipMetadata,
	compareMetadataRaw: TooltipMetadata?
): string
	local metadata = if typeof(metadataRaw) == "table" then metadataRaw else {} :: any
	local context = if typeof(metadata.context) == "table" then metadata.context else {} :: any
	local builder = self.rich.new()

	if typeof(metadata.title) == "string" and metadata.title ~= "" then
		local title = self.textGetter:Get(metadata.title, context)
		local rarity = string.lower(if typeof(metadata.rarity) == "string" then metadata.rarity else "")
		local preset = RARITY_PRESET[rarity]
		if preset ~= nil then
			builder:Preset(preset, title)
		else
			builder:Bold(title)
		end
		builder:Line()
	end

	if typeof(metadata.description) == "string" and metadata.description ~= "" then
		builder:Append(self.textGetter:Get(metadata.description, context))
		builder:Line()
	end

	if metadata.stats ~= nil then
		local statsText = self.stats:BuildRichText(
			metadata.stats,
			if compareMetadataRaw ~= nil then compareMetadataRaw.stats else metadata.compareStats,
			metadata.statDefinitions,
			metadata.statBreakdown,
			{ showUnchanged = false }
		)
		if statsText ~= "" then
			builder:Raw(statsText)
			builder:Line()
		end
	end

	if typeof(metadata.extraLines) == "table" then
		for _, line in metadata.extraLines do
			if typeof(line) == "string" and line ~= "" then
				builder:Append(self.textGetter:Get(line, context))
				builder:Line()
			end
		end
	end

	return builder:ToString()
end

function TooltipManager._applyContent(self: any, frame: Frame, text: string, maxWidthRaw: any)
	local label = frame:FindFirstChild("Body")
	if label == nil or not label:IsA("TextLabel") then
		return
	end
	local maxWidth = clampInteger(maxWidthRaw, self.defaultMaxWidth, 80, 1200)
	label.Text = text
	local measureText = string.gsub(text, "<.->", "")
	local measured = self.measure:Measure(measureText, label.TextSize, label.Font, Vector2.new(maxWidth, 2000))
	local width = math.min(maxWidth, math.max(120, math.floor(measured.X + 24)))
	local height = math.max(36, math.floor(measured.Y + 18))
	frame.Size = UDim2.fromOffset(width, height)
end

function TooltipManager._clampPosition(self: any, frame: Frame, preferred: Vector2): Vector2
	local parentSize = self.container.AbsoluteSize
	local size = frame.AbsoluteSize
	local x = preferred.X
	local y = preferred.Y
	if x + size.X > parentSize.X then
		x = parentSize.X - size.X - 4
	end
	if y + size.Y > parentSize.Y then
		y = parentSize.Y - size.Y - 4
	end
	x = math.max(0, x)
	y = math.max(0, y)
	return Vector2.new(x, y)
end

function TooltipManager._updatePosition(self: any)
	if not self.isVisible then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	if self.activePrimary ~= nil then
		local target = self:_clampPosition(self.activePrimary, mouse + self.offset)
		self.activePrimary.Position = UDim2.fromOffset(target.X, target.Y)
		if self.activeCompare ~= nil then
			local compareOffset = Vector2.new(self.activePrimary.AbsoluteSize.X + 12, 0)
			local compareTarget = self:_clampPosition(self.activeCompare, target + compareOffset)
			self.activeCompare.Position = UDim2.fromOffset(compareTarget.X, compareTarget.Y)
		end
	end
end

function TooltipManager.Show(self: any, metadataRaw: TooltipMetadata, compareMetadataRaw: TooltipMetadata?)
	self:Hide()
	local metadata = if typeof(metadataRaw) == "table" then metadataRaw else {} :: any
	local compareMetadata = if typeof(compareMetadataRaw) == "table" then compareMetadataRaw else nil
	local primary = self:_acquire()
	local primaryText = self:_composeText(metadata, compareMetadata)
	self:_applyContent(primary, primaryText, metadata.maxWidth)
	primary.Parent = self.container
	self.activePrimary = primary
	self:_animateShow(primary)

	if compareMetadata ~= nil then
		local compare = self:_acquire()
		local compareText = self:_composeText(compareMetadata, metadata)
		self:_applyContent(compare, compareText, compareMetadata.maxWidth)
		compare.Parent = self.container
		self.activeCompare = compare
		self:_animateShow(compare)
	end

	self.isVisible = true
	self:_updatePosition()
	if
		self.positionToken == nil
		and self.tickScheduler ~= nil
		and typeof((self.tickScheduler :: any).ScheduleEvery) == "function"
	then
		self.positionToken = (self.tickScheduler :: any):ScheduleEvery(
			function()
				self:_updatePosition()
			end,
			1 / 60,
			{
				group = "ui.tooltips",
				priority = 250,
				catchUp = false,
			}
		)
	elseif self.positionConnection == nil then
		self.positionConnection = RunService.RenderStepped:Connect(function()
			self:_updatePosition()
		end)
	end
end

function TooltipManager.Hide(self: any)
	if self.activePrimary ~= nil then
		self:_animateHide(self.activePrimary)
		self.activePrimary = nil
	end
	if self.activeCompare ~= nil then
		self:_animateHide(self.activeCompare)
		self.activeCompare = nil
	end
	self.isVisible = false
	if self.positionToken ~= nil then
		if typeof(self.positionToken.Cancel) == "function" then
			self.positionToken:Cancel()
		elseif self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).Cancel) == "function" then
			local schedulerAny = self.tickScheduler :: any
			schedulerAny:Cancel(self.positionToken)
		end
		self.positionToken = nil
	end
	if self.positionConnection ~= nil then
		safeDisconnect(self.positionConnection)
		self.positionConnection = nil
	end
end

function TooltipManager.BindHover(self: any, targetRaw: any, metadataProviderRaw: any): () -> ()
	if typeof(targetRaw) ~= "Instance" or not targetRaw:IsA("GuiObject") then
		return function() end
	end
	if typeof(metadataProviderRaw) ~= "function" then
		return function() end
	end
	local target = targetRaw :: GuiObject
	local enterConnection = target.MouseEnter:Connect(function()
		local metadata, compare = metadataProviderRaw(target)
		if metadata ~= nil then
			self:Show(metadata, compare)
		end
	end)
	local leaveConnection = target.MouseLeave:Connect(function()
		self:Hide()
	end)
	local destroyConnection = nil
	if typeof((target :: any).Destroying) == "RBXScriptSignal" then
		destroyConnection = (target :: any).Destroying:Connect(function()
			self:Hide()
			safeDisconnect(enterConnection)
			safeDisconnect(leaveConnection)
		end)
	end
	local slot = {
		enter = enterConnection,
		leave = leaveConnection,
		destroy = destroyConnection,
	}
	self.hoverConnections[#self.hoverConnections + 1] = slot
	return function()
		safeDisconnect(slot.enter)
		safeDisconnect(slot.leave)
		safeDisconnect(slot.destroy)
	end
end

function TooltipManager.Destroy(self: any)
	self:Hide()
	for index = #self.hoverConnections, 1, -1 do
		local slot = self.hoverConnections[index]
		safeDisconnect(slot.enter)
		safeDisconnect(slot.leave)
		safeDisconnect(slot.destroy)
		self.hoverConnections[index] = nil
	end
	for index = #self.pool, 1, -1 do
		self.pool[index]:Destroy()
		self.pool[index] = nil
	end
end

return TooltipManager
