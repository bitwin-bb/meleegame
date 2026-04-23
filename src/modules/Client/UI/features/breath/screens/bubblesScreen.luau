--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local bubbleComponent = require(script:FindFirstAncestor("game").Client.UI.features.breath.components.bubble)
local useBubbleDeplete = require(script:FindFirstAncestor("game").Client.UI.features.breath.hooks.useBubbleDeplete)
local breathSlice = require(script:FindFirstAncestor("game").Client.UI.features.breath.state.breathSlice)
local breathThunks = require(script:FindFirstAncestor("game").Client.UI.features.breath.state.breathThunks)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioServiceUtils)
local BreathServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BreathServiceUtils)

type BreathServiceState = BreathServiceUtils.BreathServiceState

type BubbleState = {
	index: number,
	breath: number,
	maxBreath: number,
	fillAlpha: number,
	isFull: boolean,
	isEmpty: boolean,
}

type BubblesScreenProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	bubbleSize: UDim2?,
	padding: UDim?,
	bubbleValue: number?,
	useServiceState: boolean?,
	mockState: BreathServiceState?,
	mockReady: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_BUBBLE_VALUE = 1
local UI_AUDIO = (AudioRegistry :: any).UI or {}
local UI_HOVER_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Hover)

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number, maximum: number?): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	local value = valueRaw
	if value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function buildBubbles(breathRaw: any, maxBreathRaw: any, bubbleValueRaw: any): { BubbleState }
	local bubbleValue = sanitizeNumber(bubbleValueRaw, DEFAULT_BUBBLE_VALUE, 0.1, nil)
	local maxBreath = sanitizeNumber(maxBreathRaw, bubbleValue, bubbleValue, nil)
	local breath = sanitizeNumber(breathRaw, maxBreath, 0, maxBreath)

	local bubbleCount = math.max(1, math.ceil(maxBreath / bubbleValue))
	local bubbles: { BubbleState } = Sift.Array.create(bubbleCount)
	for bubbleIndex = 1, bubbleCount do
		local bubbleStart = (bubbleIndex - 1) * bubbleValue
		local maxBreathInBubble = math.clamp(maxBreath - bubbleStart, 0, bubbleValue)
		local breathInBubble = math.clamp(breath - bubbleStart, 0, maxBreathInBubble)
		local fillAlpha = if maxBreathInBubble > 0 then breathInBubble / maxBreathInBubble else 0
		bubbles[bubbleIndex] = {
			index = bubbleIndex,
			breath = breathInBubble,
			maxBreath = maxBreathInBubble,
			fillAlpha = fillAlpha,
			isFull = breathInBubble >= maxBreathInBubble,
			isEmpty = breathInBubble <= 0,
		}
	end
	return bubbles
end

return function(props: BubblesScreenProps)
	local useServiceState = props.useServiceState ~= false
	local breathState, setBreathState = React.useState(function(): BreathServiceState
		if not useServiceState and props.mockState ~= nil then
			return props.mockState
		end
		return breathSlice.breathStateAtom()
	end)
	local isBreathReady, setIsBreathReady = React.useState(function(): boolean
		if not useServiceState then
			if props.mockReady ~= nil then
				return props.mockReady
			end
			return true
		end
		return breathSlice.isBreathReady()
	end)
	local isHoveringBubbles, setIsHoveringBubbles = React.useState(false)

	local hoverId = "breath_bubbles_row"
	local hoverText = string.format("Breath: %.1f/%.1f", breathState.breath, breathState.maxBreath)

	React.useEffect(function()
		if not useServiceState then
			return
		end

		local stop = breathThunks.start()
		local unsubscribe = Charm.subscribe(breathSlice.breathStateAtom, function(nextState: BreathServiceState)
			setBreathState(nextState)
		end, {
			inclusive = true,
		})
		local readyUnsubscribe = Charm.subscribe(breathSlice.breathReadyAtom, function(nextReady: boolean)
			setIsBreathReady(nextReady)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
			readyUnsubscribe()
			stop()
		end
	end, { useServiceState })

	React.useEffect(function()
		if useServiceState then
			return
		end

		if props.mockState ~= nil then
			setBreathState(props.mockState)
		end
		if props.mockReady ~= nil then
			setIsBreathReady(props.mockReady)
		else
			setIsBreathReady(true)
		end
	end, { useServiceState, props.mockState, props.mockReady })

	React.useEffect(function()
		if isHoveringBubbles then
			infoThunks.showHover({
				id = hoverId,
				text = hoverText,
			})
		end
	end, { isHoveringBubbles, hoverText })

	React.useEffect(function()
		return function()
			infoThunks.hideHover(hoverId)
		end
	end, {})

	local zIndex = props.zIndex or 12
	local bubbleSize = props.bubbleSize or UDim2.fromOffset(30, 30)
	local bubbles = buildBubbles(breathState.breath, breathState.maxBreath, props.bubbleValue)
	local bubbleFillAlphas = Sift.Array.create(#bubbles)
	for bubbleIndex, bubbleState in ipairs(bubbles) do
		bubbleFillAlphas[bubbleIndex] = bubbleState.fillAlpha
	end
	local animatedBubbleFillAlphas = useBubbleDeplete({
		fillAlphas = bubbleFillAlphas,
	})
	local shouldShow = breathState.isUnderwater or breathState.isBreathingBlocked or breathState.isDrowning

	local bubblesRowChildren: { [string]: React.ReactNode } = {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 0),
			PaddingBottom = UDim.new(0, 0),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = props.padding or UDim.new(0, 4),
		}),
	}

	for _, bubbleState in ipairs(bubbles) do
		bubblesRowChildren[`Bubble_{bubbleState.index}`] = e(bubbleComponent, {
			index = bubbleState.index,
			fillAlpha = animatedBubbleFillAlphas[bubbleState.index] or bubbleState.fillAlpha,
			size = bubbleSize,
			zIndex = zIndex + 2,
		})
	end

	return e("Frame", {
		Size = props.size or UDim2.fromOffset(360, 56),
		Position = props.position or UDim2.new(1, 0, 0, 60),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 12,
		ZIndex = zIndex,
		Visible = props.visible ~= false and isBreathReady and shouldShow,
	}, {
		BreathValue = e("TextLabel", {
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(8, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "breath",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.55,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 3,
		}),
		BubblesRow = e("Frame", {
			Size = UDim2.fromOffset(0, bubbleSize.Y.Offset),
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, -4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = zIndex + 1,
			[React.Event.MouseEnter] = function()
				setIsHoveringBubbles(true)
				infoThunks.showHover({
					id = hoverId,
					text = hoverText,
				})

				if UI_HOVER_SOUND then
					AudioServiceClient:playUi(UI_HOVER_SOUND, {
						replaceChannel = false,
					})
				end
			end,
			[React.Event.MouseLeave] = function()
				setIsHoveringBubbles(false)
				infoThunks.hideHover(hoverId)
			end,
		}, bubblesRowChildren),
	})
end
