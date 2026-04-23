--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local useBeatMotion = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useBeatMotion)
local hpSlice = require(script:FindFirstAncestor("game").Client.UI.hud.state.slice.hpSlice)
local hpThunks = require(script:FindFirstAncestor("game").Client.UI.hud.state.thunk.hpThunks)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioServiceUtils)
local HpServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.HpServiceUtils)

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

local EMPTY_HEART_COLOR = Color3.fromRGB(59, 25, 29)
local FILLED_HEART_COLOR = Color3.fromRGB(255, 90, 118)
local EMPTY_LIFE_FRUIT_HEART_COLOR = Color3.fromRGB(52, 78, 28)
local FILLED_LIFE_FRUIT_HEART_COLOR = Color3.fromRGB(255, 255, 255)
local UI_AUDIO = (AudioRegistry :: any).UI or {}
local UI_HOVER_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Hover)

local function getBeatHeartIndexFromHearts(hearts: { HeartState }): number?
	for heartIndex = #hearts, 1, -1 do
		local heart = hearts[heartIndex]
		if heart.health > 0 then
			return heart.index
		end
	end

	return nil
end

type HeartItemProps = {
	heart: HeartState,
	heartSize: UDim2,
	heartImage: string,
	emptyColor: Color3,
	filledColor: Color3,
	zIndex: number,
	isBeating: boolean,
}

local function HeartItem(props: HeartItemProps)
	local heart = props.heart
	local heartSize = props.heartSize
	local heartImage = props.heartImage
	local emptyColor = props.emptyColor
	local filledColor = props.filledColor
	local zIndex = props.zIndex
	local beatMotion = useBeatMotion({
		enabled = props.isBeating,
		auto = true,
		bpm = 72,
		baseScale = 1,
		primaryScale = 1.08,
		secondaryScale = 1.04,
	})

	local fillAlpha = math.clamp(heart.fillAlpha, 0, 1)
	local heartColor = if heart.isEmpty then emptyColor else filledColor

	return e("Frame", {
		Size = heartSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = heart.index,
		ZIndex = zIndex,
	}, {
		Scale = e("UIScale", {
			Scale = beatMotion.scale,
		}),
		Empty = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = heartImage,
			ImageColor3 = emptyColor,
			ImageTransparency = 0,
			ZIndex = zIndex + 1,
		}),
		Fill = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = heartImage,
			ImageColor3 = heartColor,
			ImageTransparency = 1 - fillAlpha,
			ZIndex = zIndex + 2,
		}),
	})
end

return function(props: HpTopRightBarProps)
	local useServiceState = props.useServiceState ~= false
	local hpState, setHpState = React.useState(function(): HpServiceState
		if not useServiceState and props.mockState ~= nil then
			return props.mockState
		end
		return hpSlice.hpStateAtom()
	end)
	local isHpReady, setIsHpReady = React.useState(function(): boolean
		if not useServiceState then
			if props.mockReady ~= nil then
				return props.mockReady
			end
			return true
		end
		return hpSlice.isHpReady()
	end)
	local isHoveringHearts, setIsHoveringHearts = React.useState(false)

	local heartsHoverId = "hp_hearts_row"
	local heartsHoverText = string.format("%.0f/%.0f", hpState.health, hpState.maxHealth)

	React.useEffect(function()
		if not useServiceState then
			return
		end

		local stop = hpThunks.start()
		local unsubscribe = Charm.subscribe(hpSlice.hpStateAtom, function(nextState: HpServiceState)
			setHpState(nextState)
		end, {
			inclusive = true,
		})
		local readyUnsubscribe = Charm.subscribe(hpSlice.hpReadyAtom, function(nextReady: boolean)
			setIsHpReady(nextReady)
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
			setHpState(props.mockState)
		end
		if props.mockReady ~= nil then
			setIsHpReady(props.mockReady)
		else
			setIsHpReady(true)
		end
	end, { useServiceState, props.mockState, props.mockReady })

	React.useEffect(function()
		if isHoveringHearts then
			infoThunks.showHover({
				id = heartsHoverId,
				text = heartsHoverText,
			})
		end
	end, { isHoveringHearts, heartsHoverText })

	React.useEffect(function()
		return function()
			infoThunks.hideHover(heartsHoverId)
		end
	end, {})

	local zIndex = props.zIndex or 12
	local hearts = hpState.hearts
	local heartSize = props.heartSize or UDim2.fromOffset(30, 30)
	local useLifeFruitHearts = hpState.maxHealth > 400
	local heartImage = if useLifeFruitHearts
		then if typeof((ImageIds :: any).lifeFruitHeart) == "string" and (ImageIds :: any).lifeFruitHeart ~= ""
			then (ImageIds :: any).lifeFruitHeart
			else ImageIds.heartLifeFruit
		else ImageIds.normalHeart
	local emptyHeartColor = if useLifeFruitHearts then EMPTY_LIFE_FRUIT_HEART_COLOR else EMPTY_HEART_COLOR
	local filledHeartColor = if useLifeFruitHearts then FILLED_LIFE_FRUIT_HEART_COLOR else FILLED_HEART_COLOR
	local beatHeartIndex = if useServiceState then hpThunks.getBeatHeartIndex() else getBeatHeartIndexFromHearts(hearts)

	local heartsRowChildren: { [string]: React.ReactNode } = {
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

	local children: { [string]: React.ReactNode } = {
		HeartsRow = e("Frame", {
			Name = "HeartsRow",
			Size = UDim2.fromOffset(0, heartSize.Y.Offset),
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, -4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = zIndex + 1,
			[React.Event.MouseEnter] = function()
				setIsHoveringHearts(true)
				infoThunks.showHover({
					id = heartsHoverId,
					text = heartsHoverText,
				})

				if UI_HOVER_SOUND then
					AudioServiceClient:playUi(UI_HOVER_SOUND, {
						replaceChannel = false,
					})
				end
			end,
			[React.Event.MouseLeave] = function()
				setIsHoveringHearts(false)
				infoThunks.hideHover(heartsHoverId)
			end,
		}, heartsRowChildren),
	}

	for _, heart in ipairs(hearts) do
		heartsRowChildren[`Heart_{heart.index}`] = e(HeartItem, {
			heart = heart,
			heartSize = heartSize,
			heartImage = heartImage,
			emptyColor = emptyHeartColor,
			filledColor = filledHeartColor,
			zIndex = zIndex + 2,
			isBeating = beatHeartIndex ~= nil and heart.index == beatHeartIndex,
		})
	end

	if props.showValueLabel ~= false then
		children.LifeValue = e("TextLabel", {
			Name = "LifeValue",
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.fromOffset(8, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = string.format("Life: %.0f/%.0f", hpState.health, hpState.maxHealth),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.55,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 3,
		})
	end

	return e("Frame", {
		Name = "HpTopRightBar",
		Size = props.size or UDim2.fromOffset(360, 56),
		Position = props.position or UDim2.new(1, -12, 0, 12),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 10,
		ZIndex = zIndex,
		Visible = props.visible ~= false and isHpReady,
	}, children)
end
