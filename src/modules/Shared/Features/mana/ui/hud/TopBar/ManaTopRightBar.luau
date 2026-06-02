--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Sift = require(ReplicatedStorage.Packages.Sift)

local ManaMeter = require(gameRoot.Shared.Features.mana.ui.hud.TopBar.components.ManaMeter)
local ManaServiceUtils = require(gameRoot.Shared.Features.mana.ManaServiceUtils)
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require(gameRoot.Client.UI.core.hooks.useViewportScale)
local UiSound = require(gameRoot.Client.UI.core.utils.UiSound)
local infoThunks = require(gameRoot.Client.Features.info.ui.state.infoThunks)
local manaSlice = require(gameRoot.Shared.Features.mana.ui.hud.state.slice.manaSlice)
local manaThunks = require(gameRoot.Shared.Features.mana.ui.hud.state.thunk.manaThunks)
local useHover = require(gameRoot.Client.UI.core.hooks.useHover)
local useManaTransparency = require(gameRoot.Shared.Features.mana.ui.hooks.useManaTransparency)
local useStore = require(gameRoot.Client.UI.core.hooks.useStore)

type ManaServiceState = ManaServiceUtils.ManaServiceState

type ManaStarState = {
	index: number,
	mana: number,
	maxMana: number,
	fillAlpha: number,
	isFull: boolean,
	isEmpty: boolean,
}

type ManaTopRightBarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	starSize: UDim2?,
	iconSize: UDim2?,
	padding: UDim?,
	showValueLabel: boolean?,
	starValue: number?,
	useServiceState: boolean?,
	mockState: ManaServiceState?,
	mockReady: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_MANA_STAR_VALUE = 20
local function buildManaStars(manaRaw: any, maxManaRaw: any, starValueRaw: any): { ManaStarState }
	local starValue = if typeof(starValueRaw) == "number" and starValueRaw == starValueRaw
		then math.max(1, starValueRaw)
		else DEFAULT_MANA_STAR_VALUE
	local maxMana = if typeof(maxManaRaw) == "number" and maxManaRaw == maxManaRaw then maxManaRaw else starValue
	maxMana = math.max(1, maxMana)
	local mana = if typeof(manaRaw) == "number" and manaRaw == manaRaw then manaRaw else maxMana
	mana = math.clamp(mana, 0, maxMana)

	local starCount = math.max(1, math.ceil(maxMana / starValue))
	local stars: { ManaStarState } = Sift.Array.create(starCount)
	for starIndex = 1, starCount do
		local starStart = (starIndex - 1) * starValue
		local maxManaInStar = math.clamp(maxMana - starStart, 0, starValue)
		local manaInStar = math.clamp(mana - starStart, 0, maxManaInStar)
		local fillAlpha = if maxManaInStar > 0 then manaInStar / maxManaInStar else 0
		stars[starIndex] = {
			index = starIndex,
			mana = manaInStar,
			maxMana = maxManaInStar,
			fillAlpha = fillAlpha,
			isFull = manaInStar >= maxManaInStar,
			isEmpty = manaInStar <= 0,
		}
	end
	return stars
end

return function(props: ManaTopRightBarProps)
	local responsive = Responsive.useResponsiveMetrics()
	local meterTokens = responsive.tokens.meter
	local useServiceState = props.useServiceState ~= false
	local serviceManaState = useStore(if useServiceState then manaSlice.manaStateAtom else nil) :: ManaServiceState?
	local serviceManaReady = useStore(if useServiceState then manaSlice.manaReadyAtom else nil) :: boolean?
	local manaState = if useServiceState
		then (serviceManaState or manaSlice.manaStateAtom())
		else if props.mockState ~= nil then props.mockState else manaSlice.manaStateAtom()
	local isManaReady = if useServiceState
		then (serviceManaReady or manaSlice.isManaReady())
		else if props.mockReady ~= nil then props.mockReady else true

	local hoverId = "mana_stars_row"
	local hoverText = string.format("%.0f/%.0f", manaState.mana, manaState.maxMana)
	local starsHover = useHover({
		onHoverStart = function()
			infoThunks.showHover({
				id = hoverId,
				text = hoverText,
			})

			UiSound.playHover()
		end,
		onHoverEnd = function()
			infoThunks.hideHover(hoverId)
		end,
	})
	local hoverAlpha = useManaTransparency({
		enabled = starsHover.hovered,
	})

	React.useEffect(function()
		if not useServiceState then
			return
		end

		local stop = manaThunks.start()

		return function()
			stop()
		end
	end, { useServiceState })

	React.useEffect(function()
		if not starsHover.hovered then
			return
		end

		infoThunks.showHover({
			id = hoverId,
			text = hoverText,
		})
	end, { starsHover.hovered, hoverText } :: { any })

	React.useEffect(function()
		return function()
			infoThunks.hideHover(hoverId)
		end
	end, {})

	local zIndex = props.zIndex or 12
	local starSize = props.starSize
		or props.iconSize
		or UDim2.fromOffset(meterTokens.segmentSize, meterTokens.segmentSize)
	local stars = buildManaStars(manaState.mana, manaState.maxMana, props.starValue)

	local children: { React.ReactNode } = {
		e(ManaMeter, {
			stars = stars,
			starSize = starSize,
			padding = props.padding or UDim.new(0, meterTokens.segmentGap),
			zIndex = zIndex + 1,
			hoverAlpha = hoverAlpha,
			onMouseEnter = starsHover.eventHandlers[React.Event.MouseEnter],
			onMouseLeave = starsHover.eventHandlers[React.Event.MouseLeave],
		}),
	}

	if props.showValueLabel ~= false and not responsive.isCompactHud then
		children[#children + 1] = e("TextLabel", {
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(8, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "mana",
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
		Position = props.position or UDim2.fromScale(1, 0),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 11,
		ZIndex = zIndex,
		Visible = props.visible ~= false and isManaReady,
	}, children)
end
