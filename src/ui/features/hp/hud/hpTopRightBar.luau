local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local useBeatMotion = require(ReplicatedStorage.UI.features.hp.hooks.useBeatMotion)
local hpSlice = require(ReplicatedStorage.UI.features.hp.state.hpSlice)
local hpThunks = require(ReplicatedStorage.UI.features.hp.state.hpThunks)
local infoThunks = require(ReplicatedStorage.UI.features.info.state.infoThunks)
local SoundServiceClient = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceClient)
local SoundServiceUtils = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceUtils)
local HpServiceUtils = require(ReplicatedStorage.Shared.Services.HpService.HpServiceUtils)

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

local function getBeatHeartIndexFromHearts(hearts: { HeartState }): number?
	for heartIndex = #hearts, 1, -1 do
		local heart = hearts[heartIndex]
		if heart.health > 0 then
			return heart.index
		end
	end

	return nil
end

local function getUiHoverSoundAssetId(): string?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		return nil
	end

	local soundsFolder = assetsFolder:FindFirstChild("Sounds")
	if not soundsFolder then
		return nil
	end

	local uiFolder = soundsFolder:FindFirstChild("Ui")
	if not uiFolder then
		return nil
	end

	local uiHoverSound = uiFolder:FindFirstChild("UiHover")
	if uiHoverSound and uiHoverSound:IsA("Sound") then
		return SoundServiceUtils.resolveSoundAssetId(uiHoverSound)
	end

	return nil
end

type HeartItemProps = {
	heart: HeartState,
	heartSize: UDim2,
	zIndex: number,
	isBeating: boolean,
}

local function HeartItem(props: HeartItemProps)
	local heart = props.heart
	local heartSize = props.heartSize
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
	local heartColor = if heart.isEmpty then EMPTY_HEART_COLOR else FILLED_HEART_COLOR

	return e("Frame", {
		Name = `Heart_{heart.index}`,
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
			Name = "Empty",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = ImageIds.normalHeart,
			ImageColor3 = EMPTY_HEART_COLOR,
			ImageTransparency = 0,
			ZIndex = zIndex + 1,
		}),
		Fill = e("ImageLabel", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = ImageIds.normalHeart,
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
			Size = UDim2.new(0, 0, 0, heartSize.Y.Offset),
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

				local uiHoverSound = getUiHoverSoundAssetId()
				if uiHoverSound then
					SoundServiceClient:playUi(uiHoverSound, {
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
			zIndex = zIndex + 2,
			isBeating = beatHeartIndex ~= nil and heart.index == beatHeartIndex,
		})
	end

	if props.showValueLabel ~= false then
		children.LifeValue = e("TextLabel", {
			Name = "LifeValue",
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.new(0, 8, 0, 0),
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
		Size = props.size or UDim2.new(0, 360, 0, 56),
		Position = props.position or UDim2.new(1, -12, 0, 12),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 10,
		ZIndex = zIndex,
		Visible = props.visible ~= false and isHpReady,
	}, children)
end
