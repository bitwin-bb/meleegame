local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local Cave = require("Cave")
local DirectionBits = require("DirectionBits")
local WallAtlas = require("WallAtlas")
local WallAutotileRegistry = require("WallAutotileRegistry")
local WallAutotileResolver = require("WallAutotileResolver")
local WallServiceUtils = require("WallServiceUtils")

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local EXPECTED_STYLE_CELLS = Table.deepReadonly({
	[0] = { Vector2.new(9, 3), Vector2.new(10, 3), Vector2.new(11, 3) },
	[1] = { Vector2.new(6, 3), Vector2.new(7, 3), Vector2.new(8, 3) },
	[2] = { Vector2.new(12, 0), Vector2.new(12, 1), Vector2.new(12, 2) },
	[3] = { Vector2.new(1, 4), Vector2.new(3, 4), Vector2.new(5, 4) },
	[4] = { Vector2.new(9, 0), Vector2.new(9, 1), Vector2.new(9, 2) },
	[5] = { Vector2.new(0, 4), Vector2.new(2, 4), Vector2.new(4, 4) },
	[6] = { Vector2.new(6, 4), Vector2.new(7, 4), Vector2.new(8, 4) },
	[7] = { Vector2.new(1, 2), Vector2.new(2, 2), Vector2.new(3, 2) },
	[8] = { Vector2.new(6, 0), Vector2.new(7, 0), Vector2.new(8, 0) },
	[9] = { Vector2.new(5, 0), Vector2.new(5, 1), Vector2.new(5, 2) },
	[10] = { Vector2.new(1, 3), Vector2.new(3, 3), Vector2.new(5, 3) },
	[11] = { Vector2.new(4, 0), Vector2.new(4, 1), Vector2.new(4, 2) },
	[12] = { Vector2.new(0, 3), Vector2.new(2, 3), Vector2.new(4, 3) },
	[13] = { Vector2.new(0, 0), Vector2.new(0, 1), Vector2.new(0, 2) },
	[14] = { Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(3, 0) },
	[15] = { Vector2.new(1, 1), Vector2.new(2, 1), Vector2.new(3, 1) },
	[16] = { Vector2.new(6, 1), Vector2.new(7, 1), Vector2.new(8, 1) },
	[17] = { Vector2.new(6, 2), Vector2.new(7, 2), Vector2.new(8, 2) },
	[18] = { Vector2.new(10, 0), Vector2.new(10, 1), Vector2.new(10, 2) },
	[19] = { Vector2.new(11, 0), Vector2.new(11, 1), Vector2.new(11, 2) },
})

return function()
	describe("Terraria wall autotiling", function()
		it("maps every Terraria wall style and variation to the canonical 13 by 5 atlas", function()
			for style, cells in EXPECTED_STYLE_CELLS do
				for frameNumber, expectedCell in cells do
					expect(WallAtlas.GetCell(style, frameNumber - 1)).to.equal(expectedCell)
				end
			end

			local definition = assert(WallAutotileRegistry.GetDefinition(WallServiceUtils.WALL_ID.DIRT))
			local resolved = assert(WallAtlas.Resolve(definition, 0, Vector2.zero, 17))
			expect(resolved.ImageRectSize).to.equal(Vector2.new(32, 32))
			expect(resolved.ImageRectOffset.Y).to.equal(108)
			expect(resolved.ImageRectOffset.X >= 324 and resolved.ImageRectOffset.X <= 396).to.equal(true)
		end)

		it("uses the coordinate pattern for fully surrounded wall centers", function()
			local expectedStyles = {
				{ 17, 15, 15 },
				{ 15, 16, 18 },
				{ 15, 19, 15 },
			}
			for y = 0, 2 do
				for x = 0, 2 do
					expect(WallAtlas.GetStyle(DirectionBits.CardinalMask, Vector2.new(x, y))).to.equal(
						expectedStyles[y + 1][x + 1]
					)
				end
			end
		end)

		it("connects cardinally to every non-empty wall type", function()
			local walls = {
				["0:0"] = { WallId = WallServiceUtils.WALL_ID.DIRT },
				["1:0"] = { WallId = WallServiceUtils.WALL_ID.STONE },
				["0:-1"] = { WallId = WallServiceUtils.WALL_ID.MUD },
			}
			local function getWall(tileX: number, tileY: number): any?
				return walls[`{tileX}:{tileY}`]
			end

			local worldMask = WallAutotileResolver.ResolveMask(getWall, Vector2.zero)
			expect(worldMask).to.equal(DirectionBits.E + DirectionBits.S)

			local definition = assert(WallAutotileRegistry.GetDefinition(WallServiceUtils.WALL_ID.DIRT))
			local resolved = assert(WallAutotileResolver.Resolve(definition, getWall, Vector2.zero, 29))
			expect(resolved.WorldMask).to.equal(DirectionBits.E + DirectionBits.S)
			expect(resolved.WallStyleMask).to.equal(WallAtlas.StyleBits.Left + WallAtlas.StyleBits.Down)
		end)

		it("reserves wall destruction for positive-power hammers", function()
			local dirtWall = WallServiceUtils.WALL_ID.DIRT
			local pickaxeAllowed, pickaxeReason = WallServiceUtils.CanBreakWall(dirtWall, "pickaxe", 100)
			expect(pickaxeAllowed).to.equal(false)
			expect(pickaxeReason).to.equal(WallServiceUtils.BreakReasons.RequiresHammer)

			local hammerAllowed = WallServiceUtils.CanBreakWall(dirtWall, " HAMMER ", 1)
			expect(hammerAllowed).to.equal(true)
			expect(WallServiceUtils.CanBreakWall(dirtWall, "hammer", 0)).to.equal(false)
			expect(WallServiceUtils.CanBreakWall(WallServiceUtils.WALL_ID.NONE, "hammer", 100)).to.equal(false)
		end)

		it("generates biome walls independently behind underground foreground tiles", function()
			local cave = Cave.New({
				seed = 101,
				tileId = { AIR = 0 },
				wallId = WallServiceUtils.WALL_ID,
				biomeId = {
					FOREST = 1,
					DESERT = 2,
					SNOW = 3,
					JUNGLE = 4,
				},
			})

			expect(cave:GetWall(0, 1, "Sky", -1)).to.equal(WallServiceUtils.WALL_ID.NONE)
			expect(cave:GetWall(0, 2, "Surface", 2)).to.equal(WallServiceUtils.WALL_ID.NONE)
			expect(cave:GetWall(0, 2, "Underground", 20)).to.equal(WallServiceUtils.WALL_ID.SANDSTONE)
			expect(cave:GetWall(3, 1, "Cavern", 100)).to.equal(WallServiceUtils.WALL_ID.STONE)
		end)
	end)
end
