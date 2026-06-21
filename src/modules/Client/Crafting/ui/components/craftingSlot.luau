local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local CoinSprites = require("CoinSprites")
local Gif = require("Gif")
local ImageIds = require("ImageIds")
local React = require(ReplicatedStorage.Packages.React)
local craftingSlice = require("craftingSlice")
local itemThunks = require("itemThunks")

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
local MISSING_ASSET_ERROR = "no asset found!"

return function(props: CraftingSlotProps): React.ReactNode
	local recipe = props.recipe
	local canCraft = recipe.canCraft == true
	local zIndex = props.zIndex or 30
	local preview = if typeof(recipe.preview) == "table" then recipe.preview else nil
	local previewResults = if preview ~= nil and typeof((preview :: any).results) == "table"
		then (preview :: any).results :: { [any]: any }
		else nil
	local firstResult = if previewResults ~= nil then previewResults[1] else nil
	local firstResultAmount = if typeof(firstResult) == "table" then (firstResult :: any).amount else nil
	local resultAmountPerCraft = if typeof(firstResult) == "table"
			and typeof(firstResultAmount) == "number"
			and firstResultAmount == firstResultAmount
		then math.max(1, math.floor(firstResultAmount))
		else 1
	local coinSpriteSheet = CoinSprites.resolveSpriteSheet(recipe.resultItemId)
	local resolvedIcon = itemThunks.resolveItemIconByType(nil, recipe.resultItemId)
	if typeof(resolvedIcon) ~= "string" or resolvedIcon == "" then
		error(MISSING_ASSET_ERROR, 0)
	end
	local maxDisplayAmount = if recipe.category == "Currency"
		then math.max(0, recipe.maxCraftableQuantity * resultAmountPerCraft)
		else math.max(0, recipe.maxCraftableQuantity)
	local maxCraftText = if canCraft then ("x%d"):format(math.max(1, maxDisplayAmount)) else "Missing"

	return e("ImageButton", {
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
		if coinSpriteSheet ~= nil
			then e(Gif, {
				image = coinSpriteSheet,
				frameSize = CoinSprites.frameSize,
				frameCount = CoinSprites.frameCount,
				columns = CoinSprites.columns,
				startFrameIndex = 0,
				fps = CoinSprites.fps,
				size = UDim2.fromOffset(40, 40),
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				backgroundTransparency = 1,
				imageTransparency = if canCraft then 0 else 0.25,
				zIndex = zIndex + 1,
				resampleMode = Enum.ResamplerMode.Pixelated,
			})
			else e("ImageLabel", {
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = resolvedIcon,
				ScaleType = Enum.ScaleType.Fit,
				ImageTransparency = if canCraft then 0 else 0.25,
				ZIndex = zIndex + 1,
			}),
		e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 14),
			Position = UDim2.new(1, -5, 1, -5),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = maxCraftText,
			Font = Enum.Font.PatrickHand,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = if canCraft then Color3.fromRGB(153, 243, 184) else Color3.fromRGB(245, 171, 171),
			TextStrokeTransparency = 0.45,
			ZIndex = zIndex + 1,
		}),
	})
end
