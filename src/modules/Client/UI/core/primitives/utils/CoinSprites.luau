
local require = require(script.Parent.loader).load(script)

local ImageIds = require("ImageIds")

local CoinSprites = {} :: any

CoinSprites.sheetSize = Vector2.new(1290, 774)
CoinSprites.rows = 3
CoinSprites.columns = 5
CoinSprites.frameSize = Vector2.new(
	math.floor(CoinSprites.sheetSize.X / CoinSprites.columns),
	math.floor(CoinSprites.sheetSize.Y / CoinSprites.rows)
)
CoinSprites.frameCount = CoinSprites.rows * CoinSprites.columns
CoinSprites.fps = 12

CoinSprites.spriteSheetKeyByItemId = {
	CopperCoin = "copperCoin",
	SilverCoin = "silverCoin",
	GoldCoin = "goldCoin",
	PlatinumCoin = "platinumCoin",
}

function CoinSprites.resolveSpriteSheet(itemIdRaw: any): string?
	local itemId = if typeof(itemIdRaw) == "string" then itemIdRaw else nil
	if itemId == nil then
		return nil
	end

	local spriteSheetKey = CoinSprites.spriteSheetKeyByItemId[itemId]
	if spriteSheetKey == nil then
		return nil
	end

	local spriteSheets = if typeof(ImageIds.spriteSheets) == "table"
		then ImageIds.spriteSheets :: { [string]: any }
		else nil
	if spriteSheets == nil then
		return nil
	end

	local spriteSheet = spriteSheets[spriteSheetKey]
	if typeof(spriteSheet) ~= "string" or spriteSheet == "" then
		return nil
	end

	return spriteSheet
end

return CoinSprites
