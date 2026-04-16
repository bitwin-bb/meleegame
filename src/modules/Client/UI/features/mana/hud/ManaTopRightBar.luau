--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local useManaTransparency = require(script:FindFirstAncestor("game").Client.UI.features.mana.hooks.useManaTransparency)
local manaSlice = require(script:FindFirstAncestor("game").Client.UI.features.mana.state.manaSlice)
local manaThunks = require(script:FindFirstAncestor("game").Client.UI.features.mana.state.manaThunks)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioService.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioService.AudioServiceUtils)
local ManaServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.ManaService.ManaServiceUtils)

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
	starValue: number?,
	useServiceState: boolean?,
	mockState: ManaServiceState?,
	mockReady: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_MANA_STAR_VALUE = 20
local EMPTY_STAR_COLOR = Color3.fromRGB(24, 44, 75)
local FILLED_STAR_COLOR = Color3.fromRGB(133, 189, 255)
local UI_AUDIO = (AudioRegistry :: any).UI or {}
local UI_HOVER_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Hover)

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

type ManaStarItemProps = {
	star: ManaStarState,
	starSize: UDim2,
	zIndex: number,
	hoverAlpha: number,
}

local function ManaStarItem(props: ManaStarItemProps)
	local star = props.star
	local fillAlpha = math.clamp(star.fillAlpha, 0, 1)
	local hoverAlpha = math.clamp(props.hoverAlpha, 0, 1)
	local fillTransparency = math.clamp((1 - fillAlpha) - (0.14 * hoverAlpha * fillAlpha), 0, 1)
	local scale = 1 + 0.03 * hoverAlpha

	return e("Frame", {
		Name = `ManaStar_{star.index}`,
		Size = props.starSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = star.index,
		ZIndex = props.zIndex,
	}, {
		Scale = e("UIScale", {
			Scale = scale,
		}),
		Empty = e("ImageLabel", {
			Name = "Empty",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = ImageIds.mana,
			Rotation = 0,
			ImageColor3 = EMPTY_STAR_COLOR,
			ImageTransparency = 0,
			ZIndex = props.zIndex + 1,
		}),
		Fill = e("ImageLabel", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = ImageIds.mana,
			Rotation = 0,
			ImageColor3 = FILLED_STAR_COLOR,
			ImageTransparency = fillTransparency,
			ZIndex = props.zIndex + 2,
		}),
	})
end

return function(props: ManaTopRightBarProps)
	local useServiceState = props.useServiceState ~= false
	local manaState, setManaState = React.useState(function(): ManaServiceState
		if not useServiceState and props.mockState ~= nil then
			return props.mockState
		end
		return manaSlice.manaStateAtom()
	end)
	local isManaReady, setIsManaReady = React.useState(function(): boolean
		if not useServiceState then
			if props.mockReady ~= nil then
				return props.mockReady
			end
			return true
		end
		return manaSlice.isManaReady()
	end)
	local isHoveringStars, setIsHoveringStars = React.useState(false)
	local hoverAlpha = useManaTransparency({
		enabled = isHoveringStars,
	})

	local hoverId = "mana_stars_row"
	local hoverText = string.format("%.0f/%.0f", manaState.mana, manaState.maxMana)

	React.useEffect(function()
		if not useServiceState then
			return
		end

		local stop = manaThunks.start()
		local unsubscribe = Charm.subscribe(manaSlice.manaStateAtom, function(nextState: ManaServiceState)
			setManaState(nextState)
		end, {
			inclusive = true,
		})
		local readyUnsubscribe = Charm.subscribe(manaSlice.manaReadyAtom, function(nextReady: boolean)
			setIsManaReady(nextReady)
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
			setManaState(props.mockState)
		end
		if props.mockReady ~= nil then
			setIsManaReady(props.mockReady)
		else
			setIsManaReady(true)
		end
	end, { useServiceState, props.mockState, props.mockReady })

	React.useEffect(function()
		if isHoveringStars then
			infoThunks.showHover({
				id = hoverId,
				text = hoverText,
			})
		end
	end, { isHoveringStars, hoverText })

	React.useEffect(function()
		return function()
			infoThunks.hideHover(hoverId)
		end
	end, {})

	local zIndex = props.zIndex or 12
	local starSize = props.starSize or props.iconSize or UDim2.fromOffset(30, 30)
	local stars = buildManaStars(manaState.mana, manaState.maxMana, props.starValue)
	local starsRowChildren: { [string]: React.ReactNode } = {
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

	for _, star in ipairs(stars) do
		starsRowChildren[`Star_{star.index}`] = e(ManaStarItem, {
			star = star,
			starSize = starSize,
			zIndex = zIndex + 2,
			hoverAlpha = hoverAlpha,
		})
	end

	return e("Frame", {
		Name = "ManaTopRightBar",
		Size = props.size or UDim2.new(0, 360, 0, 56),
		Position = props.position or UDim2.new(1, 0, 0, 0),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 11,
		ZIndex = zIndex,
		Visible = props.visible ~= false and isManaReady,
	}, {
		ManaValue = e("TextLabel", {
			Name = "ManaValue",
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.new(0, 8, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "mana",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.55,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 3,
		}),
		StarsRow = e("Frame", {
			Name = "StarsRow",
			Size = UDim2.new(0, 0, 0, starSize.Y.Offset),
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, -4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = zIndex + 1,
			[React.Event.MouseEnter] = function()
				setIsHoveringStars(true)
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
				setIsHoveringStars(false)
				infoThunks.hideHover(hoverId)
			end,
		}, starsRowChildren),
	})
end
