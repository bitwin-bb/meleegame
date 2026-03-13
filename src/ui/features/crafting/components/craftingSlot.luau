--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local Gif = require(ReplicatedStorage.UI.shared.Gif)
local craftingSlice = require(ReplicatedStorage.UI.features.crafting.state.craftingSlice)
local itemThunks = require(ReplicatedStorage.UI.features.item.state.itemThunks)

type CraftingRecipeEntry = craftingSlice.CraftingRecipeEntry

type CraftingSlotProps = {
	layoutOrder: number?,
	zIndex: number?,
	size: UDim2?,
	recipe: CraftingRecipeEntry,
	selected: boolean?,
	onActivated: ((recipeId: string) -> ())?,
}

local e: typeof(React.createElement) = React.createElement

local COIN_SPRITE_SHEET_KEY_BY_ITEM_ID = {
	CopperCoin = "copperCoin",
	SilverCoin = "silverCoin",
	GoldCoin = "goldCoin",
	PlatinumCoin = "platinumCoin",
}
local COIN_SHEET_SIZE = Vector2.new(1290, 774)
local COIN_FRAME_ROWS = 3
local COIN_FRAME_COLUMNS = 5
local COIN_FRAME_SIZE = Vector2.new(
	math.floor(COIN_SHEET_SIZE.X / COIN_FRAME_COLUMNS),
	math.floor(COIN_SHEET_SIZE.Y / COIN_FRAME_ROWS)
)
local COIN_FRAME_COUNT = COIN_FRAME_ROWS * COIN_FRAME_COLUMNS
local COIN_FPS = 12

local function resolveCoinSpriteSheet(itemIdRaw: any): string?
	local itemId = if typeof(itemIdRaw) == "string" then itemIdRaw else nil
	if itemId == nil then
		return nil
	end
	local spriteSheetKey = COIN_SPRITE_SHEET_KEY_BY_ITEM_ID[itemId]
	if spriteSheetKey == nil then
		return nil
	end
	local spriteSheets = if typeof(ImageIds.spriteSheets) == "table" then (ImageIds.spriteSheets :: { [string]: any }) else nil
	if spriteSheets == nil then
		return nil
	end
	local spriteSheet = spriteSheets[spriteSheetKey]
	if typeof(spriteSheet) ~= "string" or spriteSheet == "" then
		return nil
	end
	return spriteSheet
end

return function(props: CraftingSlotProps): React.ReactNode
	local recipe = props.recipe
	local canCraft = recipe.canCraft == true
	local zIndex = props.zIndex or 30
	local preview = if typeof(recipe.preview) == "table" then recipe.preview else nil
	local previewResults = if preview ~= nil and typeof((preview :: any).results) == "table"
		then ((preview :: any).results :: { [any]: any })
		else nil
	local firstResult = if previewResults ~= nil then previewResults[1] else nil
	local firstResultAmount = if typeof(firstResult) == "table" then (firstResult :: any).amount else nil
	local resultAmountPerCraft = if typeof(firstResult) == "table"
			and typeof(firstResultAmount) == "number"
			and firstResultAmount == firstResultAmount
		then math.max(1, math.floor(firstResultAmount))
		else 1
	local coinSpriteSheet = resolveCoinSpriteSheet(recipe.resultItemId)
	local resolvedIcon = itemThunks.resolveItemIconByType(nil, recipe.resultItemId)
	local icon = if typeof(resolvedIcon) == "string" and resolvedIcon ~= "" then resolvedIcon else ImageIds.questionMark
	local maxDisplayAmount = if recipe.category == "Currency"
		then math.max(0, recipe.maxCraftableQuantity * resultAmountPerCraft)
		else math.max(0, recipe.maxCraftableQuantity)
	local maxCraftText = if canCraft
		then ("x%d"):format(math.max(1, maxDisplayAmount))
		else "Missing"

	return e("ImageButton", {
		Name = "CraftingSlot_" .. recipe.recipeId,
		Size = props.size or UDim2.fromOffset(64, 64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = ImageIds.craftItemSlot,
		ImageTransparency = if canCraft then 0 else 0.2,
		ImageColor3 = if canCraft then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(190, 190, 190),
		LayoutOrder = props.layoutOrder,
		ZIndex = zIndex,
		AutoButtonColor = false,
		[React.Event.Activated] = function()
			if props.onActivated ~= nil then
				props.onActivated(recipe.recipeId)
			end
		end,
	}, {
		Icon = if coinSpriteSheet ~= nil
			then e(Gif, {
				name = "Icon",
				image = coinSpriteSheet,
				frameSize = COIN_FRAME_SIZE,
				frameCount = COIN_FRAME_COUNT,
				columns = COIN_FRAME_COLUMNS,
				startFrameIndex = 0,
				fps = COIN_FPS,
				size = UDim2.fromOffset(40, 40),
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				backgroundTransparency = 1,
				imageTransparency = if canCraft then 0 else 0.25,
				zIndex = zIndex + 1,
				resampleMode = Enum.ResamplerMode.Pixelated,
			})
			else e("ImageLabel", {
				Name = "Icon",
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = if typeof(icon) == "string" then icon else ImageIds.questionMark,
				ScaleType = Enum.ScaleType.Fit,
				ImageTransparency = if canCraft then 0 else 0.25,
				ZIndex = zIndex + 1,
			}),
		MaxCraft = e("TextLabel", {
			Name = "MaxCraft",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 14),
			Position = UDim2.new(1, -5, 1, -5),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = maxCraftText,
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = if canCraft then Color3.fromRGB(153, 243, 184) else Color3.fromRGB(245, 171, 171),
			TextStrokeTransparency = 0.45,
			ZIndex = zIndex + 1,
		}),
	})
end
