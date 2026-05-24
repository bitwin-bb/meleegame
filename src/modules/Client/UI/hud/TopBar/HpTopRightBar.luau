--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeartMeter = require(script.Parent.components.HeartMeter)
local HpServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.HpServiceUtils)
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useViewportScale)
local UiSound = require(script:FindFirstAncestor("game").Client.UI.core.utils.UiSound)
local hpSlice = require(script:FindFirstAncestor("game").Client.UI.hud.state.slice.hpSlice)
local hpThunks = require(script:FindFirstAncestor("game").Client.UI.hud.state.thunk.hpThunks)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local useHover = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useHover)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type HeartState = HpServiceUtils.HeartState
type HpServiceState = HpServiceUtils.HpServiceState

type HpTopRightBarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	heartSize: UDim2?,
	padding: UDim?,
	showValueLabel: boolean?,
	useServiceState: boolean?,
	mockState: HpServiceState?,
	mockReady: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local function getBeatHeartIndexFromHearts(hearts: { HeartState }): number?
	for heartIndex = #hearts, 1, -1 do
		local heart = hearts[heartIndex]
		if heart.health > 0 then
			return heart.index
		end
	end

	return nil
end

return function(props: HpTopRightBarProps)
	local responsive = Responsive.useResponsiveMetrics()
	local meterTokens = responsive.tokens.meter
	local useServiceState = props.useServiceState ~= false
	local serviceHpState = useStore(if useServiceState then hpSlice.hpStateAtom else nil) :: HpServiceState?
	local serviceHpReady = useStore(if useServiceState then hpSlice.hpReadyAtom else nil) :: boolean?
	local hpState = if useServiceState
		then (serviceHpState or hpSlice.hpStateAtom())
		else if props.mockState ~= nil then props.mockState else hpSlice.hpStateAtom()
	local isHpReady = if useServiceState
		then (serviceHpReady or hpSlice.isHpReady())
		else if props.mockReady ~= nil then props.mockReady else true

	local heartsHoverId = "hp_hearts_row"
	local heartsHoverText = string.format("%.0f/%.0f", hpState.health, hpState.maxHealth)
	local heartsHover = useHover({
		onHoverStart = function()
			infoThunks.showHover({
				id = heartsHoverId,
				text = heartsHoverText,
			})

			UiSound.playHover()
		end,
		onHoverEnd = function()
			infoThunks.hideHover(heartsHoverId)
		end,
	})

	React.useEffect(function()
		if not useServiceState then
			return
		end

		local stop = hpThunks.start()

		return function()
			stop()
		end
	end, { useServiceState })

	React.useEffect(function()
		if not heartsHover.hovered then
			return
		end

		infoThunks.showHover({
			id = heartsHoverId,
			text = heartsHoverText,
		})
	end, ({ heartsHover.hovered, heartsHoverText } :: { any }))

	React.useEffect(function()
		return function()
			infoThunks.hideHover(heartsHoverId)
		end
	end, {})

	local zIndex = props.zIndex or 12
	local hearts = hpState.hearts
	local heartSize = props.heartSize or UDim2.fromOffset(meterTokens.segmentSize, meterTokens.segmentSize)
	local useLifeFruitHearts = hpState.maxHealth > 400
	local beatHeartIndex = if useServiceState then hpThunks.getBeatHeartIndex() else getBeatHeartIndexFromHearts(hearts)

	local children: { React.ReactNode } = {
		e(HeartMeter, {
			hearts = hearts,
			heartSize = heartSize,
			padding = props.padding or UDim.new(0, 4),
			zIndex = zIndex + 1,
			useLifeFruitHearts = useLifeFruitHearts,
			beatHeartIndex = beatHeartIndex,
			onMouseEnter = heartsHover.eventHandlers[React.Event.MouseEnter],
			onMouseLeave = heartsHover.eventHandlers[React.Event.MouseLeave],
		}),
	}

	if props.showValueLabel ~= false and not responsive.isCompactHud then
		children[#children + 1] = e("TextLabel", {
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(8, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = string.format("Life: %.0f/%.0f", hpState.health, hpState.maxHealth),
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
		Position = props.position or UDim2.new(1, -responsive.safeArea.right, 0, responsive.safeArea.top),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 10,
		ZIndex = zIndex,
		Visible = props.visible ~= false and isHpReady,
	}, children)
end
