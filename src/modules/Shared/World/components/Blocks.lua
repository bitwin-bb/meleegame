local require = require(script.Parent.loader).load(script)

local TileItem = require("TileItem")

local Blocks = {}

local TILE_ITEM_IDS = {
	"Wood",
	"Dirt",
	"Stone",
	"Snow",
	"Ice",
	"Mud",
	"RichMahogany",
	"EbonStone",
}

local function createTileBuilder(itemId: string)
	return function(scope)
		return TileItem.new(scope):newTile(itemId)
	end
end

for _, itemId in TILE_ITEM_IDS do
	Blocks[itemId] = createTileBuilder(itemId)
end

Blocks.CorruptStone = Blocks.EbonStone

return Blocks
