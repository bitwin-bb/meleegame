--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gif = require(script:FindFirstAncestor("game").Client.UI.shared.Gif)
local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local React = require(ReplicatedStorage.Packages.React)
local coinSlice = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.coinSlice)
local coinThunks = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.coinThunks)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type CoinType = coinSlice.CoinType
type CoinState = coinSlice.CoinState

type CoinScreenProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	slotSize: UDim2?,
	emergeOffset: Vector2?,
	emergeTransparency: number?,
}

type CoinItemData = {
	name: string?,
	description: string?,
	value: string?,
}

type CoinDefinition = {
	id: CoinType,
	fallbackName: string,
	spriteSheetKey: string,
	itemData: CoinItemData,
}

local e: typeof(React.createElement) = React.createElement

local COIN_HOVER_ID_PREFIX = "inventory_coin_"
local COIN_SHEET_SIZE = Vector2.new(1290, 774)
local COIN_FRAME_ROWS = 3
local COIN_FRAME_COLUMNS = 5
local COIN_FRAME_SIZE =
	Vector2.new(math.floor(COIN_SHEET_SIZE.X / COIN_FRAME_COLUMNS), math.floor(COIN_SHEET_SIZE.Y / COIN_FRAME_ROWS))
local COIN_FRAME_COUNT = COIN_FRAME_ROWS * COIN_FRAME_COLUMNS
local COIN_FPS = 12
local DEFAULT_COIN_SLOT_SIZE = 58
local COIN_ICON_SIZE = 34
local COIN_ICON_TOP_PADDING = 4
local COIN_AMOUNT_HEIGHT = 16
local COIN_AMOUNT_GAP = 1
local COIN_TEXT_STROKE_TRANSPARENCY = 0.2

local function resolveCoinItemData(itemId: string): CoinItemData
	local definition = ItemRegistry.resolveDefinition(itemId)
	if typeof(definition) ~= "table" then
		return {}
	end

	return definition :: CoinItemData
end

local COIN_RENDER_ORDER: { CoinDefinition } = {
	{
		id = "copper",
		fallbackName = "Copper Coin",
		spriteSheetKey = "copperCoin",
		itemData = resolveCoinItemData("CopperCoin"),
	},
	{
		id = "silver",
		fallbackName = "Silver Coin",
		spriteSheetKey = "silverCoin",
		itemData = resolveCoinItemData("SilverCoin"),
	},
	{
		id = "gold",
		fallbackName = "Gold Coin",
		spriteSheetKey = "goldCoin",
		itemData = resolveCoinItemData("GoldCoin"),
	},
	{
		id = "platinum",
		fallbackName = "Platinum Coin",
		spriteSheetKey = "platinumCoin",
		itemData = resolveCoinItemData("PlatinumCoin"),
	},
}

local function formatWholeNumber(valueRaw: any): string
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then math.max(0, math.floor(valueRaw)) else 0
	local text = tostring(value)
	while true do
		local nextText, replacements = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = nextText
		if replacements == 0 then
			break
		end
	end
	return text
end

local function resolveCoinAmount(state: CoinState, coinType: CoinType): number
	local amounts = state.amounts
	return if coinType == "platinum"
		then amounts.platinum
		else if coinType == "gold"
			then amounts.gold
			else if coinType == "silver" then amounts.silver else amounts.copper
end

local function resolveItemField(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end

	local trimmed = string.match(valueRaw, "^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return fallback
	end
	return trimmed
end

local function resolveHoverText(coinDefinition: CoinDefinition, amount: number): string
	local itemData = coinDefinition.itemData
	local itemName = resolveItemField(itemData.name, coinDefinition.fallbackName)
	local itemDescription = resolveItemField(itemData.description, "No description.")
	local itemValue = resolveItemField(itemData.value, "Unknown value")

	return ("%s\n\n%s\n\nValue: %s\n\nOwned: %s"):format(
		itemName,
		itemDescription,
		itemValue,
		formatWholeNumber(amount)
	)
end

local function resolveEmergeOffset(offsetRaw: any): Vector2
	if typeof(offsetRaw) ~= "Vector2" then
		return Vector2.zero
	end
	if offsetRaw.X ~= offsetRaw.X or offsetRaw.Y ~= offsetRaw.Y then
		return Vector2.zero
	end
	return offsetRaw
end

local function resolveTransparency(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.clamp(valueRaw, 0, 1)
end

local function applyOffset(base: UDim2, offset: Vector2): UDim2
	return UDim2.new(base.X.Scale, base.X.Offset + offset.X, base.Y.Scale, base.Y.Offset + offset.Y)
end

return function(props: CoinScreenProps): React.ReactNode
	local coinState = (useStore(coinSlice.coinStateAtom) :: CoinState?) or coinSlice.coinStateAtom()

	React.useEffect(function()
		local stop = coinThunks.start()

		return function()
			stop()
			infoThunks.hideHover(nil)
		end
	end, {})

	if props.visible == false then
		return nil
	end

	local zIndex = props.zIndex or 40
	local emergeOffset = resolveEmergeOffset(props.emergeOffset)
	local emergeTransparency = resolveTransparency(props.emergeTransparency)
	local slotWidth = if props.slotSize ~= nil
		then math.max(1, math.floor(props.slotSize.X.Offset + 0.5))
		else DEFAULT_COIN_SLOT_SIZE
	local slotHeight = if props.slotSize ~= nil
		then math.max(1, math.floor(props.slotSize.Y.Offset + 0.5))
		else DEFAULT_COIN_SLOT_SIZE
	local iconTop = math.max(0, COIN_ICON_TOP_PADDING)
	local amountTop = iconTop + COIN_ICON_SIZE + COIN_AMOUNT_GAP
	local spriteSheets = if typeof(ImageIds.spriteSheets) == "table" then ImageIds.spriteSheets else {}
	local renderedCoinCount = 0
	local rootChildren: { [string]: React.ReactNode } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 0),
		}),
	}

	for _, coinDefinition in COIN_RENDER_ORDER do
		local spriteSheetImage = (spriteSheets :: { [string]: any })[coinDefinition.spriteSheetKey]
		if typeof(spriteSheetImage) ~= "string" then
			if coinDefinition.id == "silver" then
				spriteSheetImage = (spriteSheets :: { [string]: any }).silverCoin
			end
		end

		if typeof(spriteSheetImage) ~= "string" then
			continue
		end

		renderedCoinCount += 1
		local coinAmount = resolveCoinAmount(coinState, coinDefinition.id)
		local coinLayoutOrder = renderedCoinCount
		local hoverId = COIN_HOVER_ID_PREFIX .. coinDefinition.id

		rootChildren["Coin_" .. coinDefinition.id] = e("ImageButton", {
			Size = UDim2.fromOffset(slotWidth, slotHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			ImageTransparency = 1,
			LayoutOrder = coinLayoutOrder,
			ZIndex = zIndex + 1,
			[React.Event.MouseEnter] = function()
				if emergeTransparency >= 0.98 then
					return
				end
				infoThunks.showHover({
					id = hoverId,
					text = resolveHoverText(coinDefinition, coinAmount),
				})
			end,
			[React.Event.MouseLeave] = function()
				infoThunks.hideHover(hoverId)
			end,
		}, {
			CoinAnimation = e(Gif, {
				image = spriteSheetImage,
				frameSize = COIN_FRAME_SIZE,
				frameCount = COIN_FRAME_COUNT,
				columns = COIN_FRAME_COLUMNS,
				startFrameIndex = 0,
				fps = COIN_FPS,
				size = UDim2.fromOffset(COIN_ICON_SIZE, COIN_ICON_SIZE),
				position = UDim2.new(0.5, 0, 0, iconTop),
				anchorPoint = Vector2.new(0.5, 0),
				backgroundTransparency = 1,
				imageTransparency = emergeTransparency,
				zIndex = zIndex + 2,
				resampleMode = Enum.ResamplerMode.Pixelated,
			}),
			Amount = e("TextLabel", {
				Size = UDim2.fromOffset(slotWidth, COIN_AMOUNT_HEIGHT),
				Position = UDim2.new(0.5, 0, 0, amountTop),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Text = formatWholeNumber(coinAmount),
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(248, 253, 255),
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				TextTransparency = emergeTransparency,
				TextStrokeTransparency = math.clamp(
					COIN_TEXT_STROKE_TRANSPARENCY + emergeTransparency * (1 - COIN_TEXT_STROKE_TRANSPARENCY),
					0,
					1
				),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = zIndex + 3,
			}),
		})
	end

	if renderedCoinCount <= 0 then
		return nil
	end

	return e("Frame", {
		Size = UDim2.fromOffset(slotWidth * renderedCoinCount, slotHeight),
		Position = applyOffset(props.position or UDim2.new(1, 0, 1, 0), emergeOffset),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 1,
		ZIndex = zIndex,
		Visible = props.visible ~= false,
	}, rootChildren)
end
