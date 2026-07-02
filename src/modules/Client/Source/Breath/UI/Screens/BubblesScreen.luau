local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Sift = require(ReplicatedStorage.Packages.Sift)

local BreathMeter = require("BreathMeter")
local BreathServiceUtils = require("BreathServiceUtils")
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require("useViewportScale")
local UiSound = require("UISound")
local breathSlice = require("BreathSlice")
local infoThunks = require("InfoThunks")
local useBubbleDeplete = require("useBubbleDeplete")
local useHover = require("useHover")
local useStore = require("useCoreStore")

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
	showValueLabel: boolean?,
	bubbleValue: number?,
	useServiceState: boolean?,
	mockState: BreathServiceState?,
	mockReady: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_BUBBLE_VALUE = 1
local function CoerceNumber(valueRaw: any, fallback: number, minimum: number, maximum: number?): number
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
	local bubbleValue = CoerceNumber(bubbleValueRaw, DEFAULT_BUBBLE_VALUE, 0.1, nil)
	local maxBreath = CoerceNumber(maxBreathRaw, bubbleValue, bubbleValue, nil)
	local breath = CoerceNumber(breathRaw, maxBreath, 0, maxBreath)

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
	local responsive = Responsive.useResponsiveMetrics()
	local meterTokens = responsive.tokens.meter
	local useServiceState = props.useServiceState ~= false
	local serviceBreathState =
		useStore(if useServiceState then breathSlice.breathStateAtom else nil) :: BreathServiceState?
	local serviceBreathReady = useStore(if useServiceState then breathSlice.breathReadyAtom else nil) :: boolean?
	local breathState = if useServiceState
		then (serviceBreathState or breathSlice.breathStateAtom())
		else if props.mockState ~= nil then props.mockState else breathSlice.breathStateAtom()
	local isBreathReady = if useServiceState
		then (serviceBreathReady or breathSlice.isBreathReady())
		else if props.mockReady ~= nil then props.mockReady else true

	local hoverId = "breath_bubbles_row"
	local hoverText = string.format("Breath: %.1f/%.1f", breathState.breath, breathState.maxBreath)
	local bubblesHover = useHover({
		onHoverStart = function()
			infoThunks.ShowHover({
				id = hoverId,
				text = hoverText,
			})

			UiSound.playHover()
		end,
		onHoverEnd = function()
			infoThunks.HideHover(hoverId)
		end,
	})

	React.useEffect(function()
		if not useServiceState then
			return
		end

		local breathThunks = require("BreathThunks")
		local stop = breathThunks.Start()

		return function()
			stop()
		end
	end, { useServiceState })

	React.useEffect(function()
		if not bubblesHover.hovered then
			return
		end

		infoThunks.ShowHover({
			id = hoverId,
			text = hoverText,
		})
	end, { bubblesHover.hovered, hoverText } :: { any })

	React.useEffect(function()
		return function()
			infoThunks.HideHover(hoverId)
		end
	end, {})

	local zIndex = props.zIndex or 12
	local bubbleSize = props.bubbleSize or UDim2.fromOffset(meterTokens.segmentSize, meterTokens.segmentSize)
	local bubbles = buildBubbles(breathState.breath, breathState.maxBreath, props.bubbleValue)
	local bubbleFillAlphas = Sift.Array.create(#bubbles)
	for bubbleIndex, bubbleState in ipairs(bubbles) do
		bubbleFillAlphas[bubbleIndex] = bubbleState.fillAlpha
	end
	local animatedBubbleFillAlphas = useBubbleDeplete({
		fillAlphas = bubbleFillAlphas,
	})
	local shouldShow = breathState.isUnderwater or breathState.isBreathingBlocked or breathState.isDrowning

	local children: { React.ReactNode } = {
		e(BreathMeter, {
			bubbles = bubbles,
			fillAlphas = animatedBubbleFillAlphas,
			bubbleSize = bubbleSize,
			padding = props.padding or UDim.new(0, meterTokens.segmentGap),
			zIndex = zIndex + 1,
			onMouseEnter = bubblesHover.eventHandlers[React.Event.MouseEnter],
			onMouseLeave = bubblesHover.eventHandlers[React.Event.MouseLeave],
		}),
	}

	if props.showValueLabel ~= false and not responsive.isCompactHud then
		children[#children + 1] = e("TextLabel", {
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(8, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.PatrickHand,
			Text = "breath",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.55,
			TextSize = meterTokens.labelTextSize,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 3,
		})
	end

	return e("Frame", {
		Size = props.size or UDim2.fromOffset(meterTokens.frameWidth, meterTokens.frameHeight),
		Position = props.position or UDim2.new(1, 0, 0, meterTokens.frameHeight + responsive.tokens.hud.edgePadding),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 12,
		ZIndex = zIndex,
		Visible = props.visible ~= false and isBreathReady and shouldShow,
	}, children)
end
