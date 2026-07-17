local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local CoinRow = require("CoinRow")
local ImageIds = require("ImageIds")
local ItemRegistry = require("ItemRegistry")
local React: any = require(ReplicatedStorage.Packages.React)
local coinSlice = require("CoinSlice")
local coinThunks = require("CoinThunks")
local formatNumber = require("FormatNumber")
local infoThunks = require("InfoThunks")
local useStore = require("useCoreStore")

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
local DEFAULT_COIN_SLOT_SIZE = 58
local COIN_ICON_SIZE = 34
local COIN_ICON_TOP_PADDING = 4
local COIN_AMOUNT_HEIGHT = 16
local COIN_AMOUNT_GAP = 1

local function getCoinItemData(itemId: string): CoinItemData
	local definition = ItemRegistry.GetDefinition(itemId)
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
		itemData = getCoinItemData("CopperCoin"),
	},
	{
		id = "silver",
		fallbackName = "Silver Coin",
		spriteSheetKey = "silverCoin",
		itemData = getCoinItemData("SilverCoin"),
	},
	{
		id = "gold",
		fallbackName = "Gold Coin",
		spriteSheetKey = "goldCoin",
		itemData = getCoinItemData("GoldCoin"),
	},
	{
		id = "platinum",
		fallbackName = "Platinum Coin",
		spriteSheetKey = "platinumCoin",
		itemData = getCoinItemData("PlatinumCoin"),
	},
}

local function getCoinAmount(state: CoinState, coinType: CoinType): number
	local amounts = state.amounts
	return if coinType == "platinum"
		then amounts.platinum
		else if coinType == "gold"
			then amounts.gold
			else if coinType == "silver" then amounts.silver else amounts.copper
end

local function getItemField(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end

	local trimmed = string.match(valueRaw, "^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return fallback
	end
	return trimmed
end

local function getHoverText(coinDefinition: CoinDefinition, amount: number): string
	local itemData = coinDefinition.itemData
	local itemName = getItemField(itemData.name, coinDefinition.fallbackName)
	local itemDescription = getItemField(itemData.description, "No description.")
	local itemValue = getItemField(itemData.value, "Unknown value")

	return ("%s\n%s\nValue: %s\nOwned: %s"):format(itemName, itemDescription, itemValue, formatNumber(amount))
end

local function getEmergeOffset(offsetRaw: any): Vector2
	if typeof(offsetRaw) ~= "Vector2" then
		return Vector2.zero
	end
	if offsetRaw.X ~= offsetRaw.X or offsetRaw.Y ~= offsetRaw.Y then
		return Vector2.zero
	end
	return offsetRaw
end

local function getTransparency(valueRaw: any): number
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
		local stop = coinThunks.Start()

		return function()
			stop()
			infoThunks.HideHover(nil)
		end
	end, {})

	if props.visible == false then
		return nil
	end

	local zIndex = props.zIndex or 40
	local emergeOffset = getEmergeOffset(props.emergeOffset)
	local emergeTransparency = getTransparency(props.emergeTransparency)
	local slotWidth = if props.slotSize ~= nil
		then math.max(1, math.floor(props.slotSize.X.Offset + 0.5))
		else DEFAULT_COIN_SLOT_SIZE
	local slotHeight = if props.slotSize ~= nil
		then math.max(1, math.floor(props.slotSize.Y.Offset + 0.5))
		else DEFAULT_COIN_SLOT_SIZE
	local iconTop = math.max(0, COIN_ICON_TOP_PADDING)
	local amountTop = iconTop + COIN_ICON_SIZE + COIN_AMOUNT_GAP
	local spriteSheets = if typeof(ImageIds.spriteSheets) == "table" then ImageIds.spriteSheets else {} :: any
	local renderedCoinCount = 0
	local coinRowItems: { any } = {}

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
		local coinAmount = getCoinAmount(coinState, coinDefinition.id)
		local coinLayoutOrder = renderedCoinCount
		local hoverId = COIN_HOVER_ID_PREFIX .. coinDefinition.id

		coinRowItems[#coinRowItems + 1] = {
			id = coinDefinition.id,
			amount = coinAmount,
			spriteSheetImage = spriteSheetImage,
			hoverId = hoverId,
			hoverText = getHoverText(coinDefinition, coinAmount),
			layoutOrder = coinLayoutOrder,
		}
	end

	if renderedCoinCount <= 0 then
		return nil
	end

	return e("Frame", {
		Size = UDim2.fromOffset(slotWidth * renderedCoinCount, slotHeight),
		Position = applyOffset(props.position or UDim2.fromScale(1, 1), emergeOffset),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 1,
		ZIndex = zIndex,
		Visible = props.visible ~= false,
	}, {
		e(CoinRow, {
			coins = coinRowItems,
			slotWidth = slotWidth,
			slotHeight = slotHeight,
			iconTop = iconTop,
			iconSize = COIN_ICON_SIZE,
			amountTop = amountTop,
			amountHeight = COIN_AMOUNT_HEIGHT,
			emergeTransparency = emergeTransparency,
			zIndex = zIndex,
			onHoverStart = function(coin)
				if emergeTransparency >= 0.98 then
					return
				end
				infoThunks.ShowHover({
					id = coin.hoverId,
					text = coin.hoverText,
				})
			end,
			onHoverEnd = function(coin)
				infoThunks.HideHover(coin.hoverId)
			end,
		}),
	})
end
