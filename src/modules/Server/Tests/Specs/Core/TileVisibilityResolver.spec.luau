--!strict
local TileVisibilityResolver = require(script:FindFirstAncestor("game").Shared.Modules.Core.TileVisibilityResolver)

local function createChunk(chunkX: number, chunkY: number, width: number, height: number, tileId: number)
	return {
		chunkX = chunkX,
		chunkY = chunkY,
		tileMinX = chunkX * width,
		tileMinY = chunkY * height,
		width = width,
		height = height,
		tiles = table.create(width * height, tileId),
	}
end

local function setTile(chunk: any, localX: number, localY: number, tileId: number)
	chunk.tiles[TileVisibilityResolver.ComputeTileIndex(localX, localY, chunk.width)] = tileId
end

return function()
	describe("TileVisibilityResolver", function()
		it("resolves solid neighbors across chunk borders without creating seam exposure", function()
			local chunks = {
				["0:0"] = createChunk(0, 0, 3, 3, 1),
				["1:0"] = createChunk(1, 0, 3, 3, 1),
			}
			local leftChunk = chunks["0:0"]

			expect(TileVisibilityResolver.ResolveNeighborTile(chunks, leftChunk, 2, 1, 1, 0, 3)).to.equal(1)
			expect(TileVisibilityResolver.ShouldRenderTile(1, 2, 1, {
				airTileId = 0,
				getTileAtWorldCell = function(worldX: number, worldY: number): number?
					return TileVisibilityResolver.GetTileAtWorldCell(chunks, worldX, worldY, 3)
				end,
			})).to.equal(false)
		end)

		it("reveals cross-chunk boundary tiles when an adjacent edge tile becomes air", function()
			local chunks = {
				["0:0"] = createChunk(0, 0, 3, 3, 1),
				["1:0"] = createChunk(1, 0, 3, 3, 1),
			}
			setTile(chunks["0:0"], 2, 1, 0)

			expect(TileVisibilityResolver.ShouldRenderTile(1, 3, 1, {
				airTileId = 0,
				getTileAtWorldCell = function(worldX: number, worldY: number): number?
					return TileVisibilityResolver.GetTileAtWorldCell(chunks, worldX, worldY, 3)
				end,
			})).to.equal(true)
		end)

		it("uses newly loaded neighbor metadata to remove temporary border exposure", function()
			local liveChunks = {
				["0:0"] = createChunk(0, 0, 3, 3, 1),
			}
			local options = {
				airTileId = 0,
				getTileAtWorldCell = function(worldX: number, worldY: number): number?
					return TileVisibilityResolver.GetTileAtWorldCell(liveChunks, worldX, worldY, 3)
				end,
			}

			expect(TileVisibilityResolver.ShouldRenderTile(1, 2, 1, options)).to.equal(true)
			liveChunks["1:0"] = createChunk(1, 0, 3, 3, 1)
			expect(TileVisibilityResolver.ShouldRenderTile(1, 2, 1, options)).to.equal(false)
		end)

		it("can preserve border occlusion from cached neighbor metadata after unload", function()
			local liveChunks = {
				["0:0"] = createChunk(0, 0, 3, 3, 1),
			}
			local cachedChunks = {
				["1:0"] = createChunk(1, 0, 3, 3, 1),
			}

			expect(TileVisibilityResolver.ShouldRenderTile(1, 2, 1, {
				airTileId = 0,
				getTileAtWorldCell = function(worldX: number, worldY: number): number?
					local liveTile = TileVisibilityResolver.GetTileAtWorldCell(liveChunks, worldX, worldY, 3)
					if liveTile ~= nil then
						return liveTile
					end
					return TileVisibilityResolver.GetTileAtWorldCell(cachedChunks, worldX, worldY, 3)
				end,
			})).to.equal(false)
		end)

		it("marks only the changed tile and immediate neighbors dirty by default", function()
			local cells = TileVisibilityResolver.CollectVisibilityDirtyWorldCells(10, 20, false)
			expect(#cells).to.equal(5)

			local bounds = TileVisibilityResolver.ComputeDirtyBounds(10, 20, false)
			expect(bounds.minTileX).to.equal(9)
			expect(bounds.maxTileX).to.equal(11)
			expect(bounds.minTileY).to.equal(19)
			expect(bounds.maxTileY).to.equal(21)
		end)

		it("keeps hidden tile metadata available and reveals it when mined into", function()
			local chunk = createChunk(0, 0, 3, 3, 1)
			setTile(chunk, 1, 1, 7)
			local chunks = {
				["0:0"] = chunk,
				["-1:0"] = createChunk(-1, 0, 3, 3, 1),
				["1:0"] = createChunk(1, 0, 3, 3, 1),
				["0:-1"] = createChunk(0, -1, 3, 3, 1),
				["0:1"] = createChunk(0, 1, 3, 3, 1),
			}

			local function lookup(worldX: number, worldY: number): number?
				return TileVisibilityResolver.GetTileAtWorldCell(chunks, worldX, worldY, 3)
			end

			local hiddenValues = TileVisibilityResolver.BuildVisibleTileValues(chunk.tiles, chunk.width, chunk.height, {
				airTileId = 0,
				tileMinX = chunk.tileMinX,
				tileMinY = chunk.tileMinY,
				getTileAtWorldCell = lookup,
			})
			expect(hiddenValues[TileVisibilityResolver.ComputeTileIndex(1, 1, chunk.width)]).to.equal(0)
			expect(chunk.tiles[TileVisibilityResolver.ComputeTileIndex(1, 1, chunk.width)]).to.equal(7)

			setTile(chunk, 0, 1, 0)
			local revealedValues = TileVisibilityResolver.BuildVisibleTileValues(chunk.tiles, chunk.width, chunk.height, {
				airTileId = 0,
				tileMinX = chunk.tileMinX,
				tileMinY = chunk.tileMinY,
				getTileAtWorldCell = lookup,
			})
			expect(revealedValues[TileVisibilityResolver.ComputeTileIndex(1, 1, chunk.width)]).to.equal(7)
		end)
	end)
end
