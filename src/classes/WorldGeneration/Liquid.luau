--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local LiquidServiceUtils = require(ReplicatedStorage.Shared.Services.LiquidService.LiquidServiceUtils)

type LiquidServiceConfig = LiquidServiceUtils.LiquidServiceConfig

export type ColumnProfile = {
	surfaceY: number,
	biomeId: number,
	biomeType: number,
}

export type ChunkLiquidGenerationContext = {
	seed: number,
	chunkX: number,
	chunkY: number,
	tileMinX: number,
	tileMinY: number,
	width: number,
	height: number,
	tiles: { number },
	depthBelowSurface: { number },
	biomeIds: { number },
	biomeTypes: { number },
	dominantBiomeId: number,
	dominantBiomeType: number,
	columnProfiles: { ColumnProfile },
	scanColumnProfiles: { ColumnProfile },
	scanColumnMinX: number,
}

local LiquidGeneration = {}
LiquidGeneration.__index = LiquidGeneration

export type LiquidGeneration = typeof(setmetatable({} :: any, LiquidGeneration))

local LIQUID_TYPE = LiquidServiceUtils.LIQUID_TYPE
local LiquidCell = LiquidServiceUtils.LiquidCell
local LiquidSolver = LiquidServiceUtils.LiquidSolver

local SURFACE_POOL_SALT = 173
local CAVE_POCKET_SALT = 317
local RESERVOIR_SALT = 419
local LAVA_POCKET_SALT = 563
local LAVA_RESERVOIR_SALT = 719

local function sampleUnit(seed: number, x: number, y: number, salt: number): number
	local noise = math.noise(
		(seed + salt * 1.17) * 0.017 + x * 0.157,
		(seed - salt * 0.73) * 0.013 + y * 0.131,
		(seed + salt * 2.03) * 0.009
	)
	return math.clamp((noise + 1) * 0.5, 0, 1)
end

local function computeTileIndex(localX: number, localY: number, width: number): number
	return localY * width + localX + 1
end

local function getBiomePoolChanceMultiplier(biomeId: number, biomeType: number): number
	if biomeType == 2 then
		return 0.82
	end
	if biomeId == 2 then
		return 0.5
	end
	if biomeId == 3 then
		return 0.74
	end
	if biomeId == 4 then
		return 1.12
	end
	return 1
end

function LiquidGeneration.new(configRaw: any?): LiquidGeneration
	local self = setmetatable({}, LiquidGeneration)
	self.config = LiquidServiceUtils.sanitizeConfig(configRaw, nil)
	self.maxFill = self.config.maxFill
	return self
end

function LiquidGeneration.isSolidTile(
	_self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	localX: number,
	localY: number
): boolean
	if localX < 0 or localX >= context.width or localY < 0 or localY >= context.height then
		return true
	end
	local tileId = context.tiles[computeTileIndex(localX, localY, context.width)] or 0
	return tileId ~= 0
end

function LiquidGeneration.trySetCell(
	self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	cells: { number },
	localX: number,
	localY: number,
	liquidType: number,
	fill: number
): boolean
	if localX < 0 or localX >= context.width or localY < 0 or localY >= context.height then
		return false
	end
	if self:isSolidTile(context, localX, localY) then
		return false
	end
	local index = computeTileIndex(localX, localY, context.width)
	local existingType, existingFill = LiquidCell.unpack(cells[index] or 0)
	if existingType ~= LIQUID_TYPE.NONE and existingType ~= liquidType then
		return false
	end
	local nextFill = math.clamp(math.max(existingFill, fill), 0, self.maxFill)
	if nextFill <= 0 then
		return false
	end
	if existingType == liquidType and existingFill == nextFill then
		return false
	end
	cells[index] = LiquidCell.make(liquidType, nextFill, LiquidServiceUtils.FLOW_STATE.SETTLING)
	return true
end

function LiquidGeneration.getSurfaceColumn(
	_self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	worldTileX: number
): ColumnProfile?
	local index = worldTileX - context.scanColumnMinX + 1
	local column = context.scanColumnProfiles[index]
	if column == nil then
		return nil
	end
	return column
end

function LiquidGeneration.seedSurfacePoolSpan(
	self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	cells: { number },
	centerLocalX: number,
	waterLine: number,
	radius: number
): boolean
	local didSeed = false
	local config = self.config.generation

	for offsetX = -radius, radius do
		local localX = centerLocalX + offsetX
		if localX < 0 or localX >= context.width then
			continue
		end

		local column = context.columnProfiles[localX + 1]
		if column == nil then
			continue
		end

		local columnWaterLine = math.min(waterLine, column.surfaceY + config.surfacePoolMaxDepth)
		local basinDepth = columnWaterLine - column.surfaceY
		if basinDepth < config.surfacePoolMinDepth then
			continue
		end

		for fillTileY = column.surfaceY + 1, columnWaterLine do
			local localY = fillTileY - context.tileMinY
			if localY < 0 or localY >= context.height then
				continue
			end
			local fillAlpha = if fillTileY >= columnWaterLine then config.surfacePoolFillChance else 1
			local fillAmount = math.max(1, math.floor(self.maxFill * fillAlpha))
			if self:trySetCell(context, cells, localX, localY, LIQUID_TYPE.WATER, fillAmount) then
				didSeed = true
			end
		end
	end

	return didSeed
end

function LiquidGeneration.seedSurfacePools(
	self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	cells: { number }
): boolean
	local config = self.config.generation
	local radius = math.max(2, config.depressionScanRadius)
	local didSeed = false
	local bestCandidate = nil :: { localX: number, waterLine: number, score: number }?

	for localX = 0, context.width - 1 do
		local column = context.columnProfiles[localX + 1]
		if column == nil then
			continue
		end

		local worldTileX = context.tileMinX + localX
		local surfaceY = column.surfaceY
		local leftRim = -math.huge
		local rightRim = -math.huge

		for scanOffset = 1, radius do
			local leftColumn = self:getSurfaceColumn(context, worldTileX - scanOffset)
			if leftColumn ~= nil then
				leftRim = math.max(leftRim, leftColumn.surfaceY)
			end
			local rightColumn = self:getSurfaceColumn(context, worldTileX + scanOffset)
			if rightColumn ~= nil then
				rightRim = math.max(rightRim, rightColumn.surfaceY)
			end
		end

		if leftRim == -math.huge or rightRim == -math.huge then
			continue
		end
		local waterLine = math.min(leftRim, rightRim)
		local basinDepth = waterLine - surfaceY
		if basinDepth < config.surfacePoolMinDepth then
			continue
		end
		if basinDepth > config.surfacePoolMaxDepth then
			waterLine = surfaceY + config.surfacePoolMaxDepth
			basinDepth = waterLine - surfaceY
		end
		if basinDepth < config.surfacePoolMinDepth then
			continue
		end

		local chanceMultiplier = getBiomePoolChanceMultiplier(column.biomeId, column.biomeType)
		local score = basinDepth * chanceMultiplier
		if bestCandidate == nil or score > bestCandidate.score then
			bestCandidate = {
				localX = localX,
				waterLine = waterLine,
				score = score,
			}
		end

		local roll = sampleUnit(context.seed, worldTileX, surfaceY, SURFACE_POOL_SALT)
		if roll > config.surfacePoolChance * chanceMultiplier then
			continue
		end

		if self:seedSurfacePoolSpan(context, cells, localX, waterLine, radius) then
			didSeed = true
		end
	end

	if not didSeed and bestCandidate ~= nil then
		local fallbackRoll = sampleUnit(context.seed, context.chunkX, context.chunkY, SURFACE_POOL_SALT + 977)
		if fallbackRoll < 0.6 then
			didSeed = self:seedSurfacePoolSpan(context, cells, bestCandidate.localX, bestCandidate.waterLine, radius)
				or didSeed
		end
	end

	return didSeed
end

function LiquidGeneration.fillFloodPocket(
	self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	cells: { number },
	centerX: number,
	centerY: number,
	liquidType: number,
	radius: number,
	waterLevelY: number
): boolean
	local queue = {
		{ x = centerX, y = centerY },
	}
	local queueHead = 1
	local visited: { [string]: boolean } = {}
	local radiusSquared = math.max(1, radius * radius)
	local didSeed = false

	while queueHead <= #queue do
		local current = queue[queueHead]
		queueHead += 1

		local x = current.x
		local y = current.y
		local key = `{x}:{y}`
		if visited[key] then
			continue
		end
		visited[key] = true

		if x < 0 or x >= context.width or y < 0 or y >= context.height then
			continue
		end
		if y > waterLevelY then
			continue
		end
		if self:isSolidTile(context, x, y) then
			continue
		end

		local dx = x - centerX
		local dy = y - centerY
		if dx * dx + (dy * dy) * 0.45 > radiusSquared * 1.2 then
			continue
		end

		local fillAmount = if y >= waterLevelY then math.floor(self.maxFill * 0.78) else self.maxFill
		if self:trySetCell(context, cells, x, y, liquidType, fillAmount) then
			didSeed = true
		end

		for _, offset in
			{
				{ 1, 0 },
				{ -1, 0 },
				{ 0, 1 },
				{ 0, -1 },
			}
		do
			local nextX = x + offset[1]
			local nextY = y + offset[2]
			if
				nextX >= centerX - radius - 1
				and nextX <= centerX + radius + 1
				and nextY >= centerY - 1
				and nextY <= waterLevelY + 1
			then
				queue[#queue + 1] = {
					x = nextX,
					y = nextY,
				}
			end
		end
	end

	return didSeed
end

function LiquidGeneration.seedUndergroundPockets(
	self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	cells: { number }
): boolean
	local config = self.config.generation
	local didSeed = false
	local bestCandidate = nil :: { localX: number, localY: number, radius: number, waterLevelY: number, score: number }?

	for localY = 0, context.height - 1 do
		for localX = 0, context.width - 1 do
			if self:isSolidTile(context, localX, localY) then
				continue
			end

			local index = computeTileIndex(localX, localY, context.width)
			local depth = context.depthBelowSurface[index] or -1
			if depth < 0 then
				continue
			end

			local hasSolidFloor = self:isSolidTile(context, localX, localY - 1)
			local sideWalls = 0
			if self:isSolidTile(context, localX - 1, localY) then
				sideWalls += 1
			end
			if self:isSolidTile(context, localX + 1, localY) then
				sideWalls += 1
			end
			if not hasSolidFloor or sideWalls <= 0 then
				continue
			end

			local worldTileX = context.tileMinX + localX
			local worldTileY = context.tileMinY + localY
			local biomeId = context.biomeIds[index] or context.dominantBiomeId
			local biomeType = context.biomeTypes[index] or context.dominantBiomeType

			if depth >= config.cavePocketMinDepth and depth <= config.cavePocketMaxDepth then
				local radiusAlpha = sampleUnit(context.seed, worldTileX, worldTileY, RESERVOIR_SALT)
				local radius = math.max(
					config.cavePocketMinRadius,
					math.floor(
						config.cavePocketMinRadius
							+ (config.cavePocketMaxRadius - config.cavePocketMinRadius) * radiusAlpha
					)
				)
				local waterLevelY = localY + math.max(1, math.floor(radius * 0.55))
				local score = depth + sideWalls * 8 + radius * 6
				if bestCandidate == nil or score > bestCandidate.score then
					bestCandidate = {
						localX = localX,
						localY = localY,
						radius = radius,
						waterLevelY = waterLevelY,
						score = score,
					}
				end

				local caveChance = config.cavePocketChance * getBiomePoolChanceMultiplier(biomeId, biomeType)
				local caveRoll = sampleUnit(context.seed, worldTileX, worldTileY, CAVE_POCKET_SALT)
				if caveRoll < caveChance then
					if self:fillFloodPocket(context, cells, localX, localY, LIQUID_TYPE.WATER, radius, waterLevelY) then
						didSeed = true
					end
				end
			end

			if depth >= config.reservoirMinDepth and depth <= config.reservoirMaxDepth and sideWalls >= 2 then
				local radiusAlpha = sampleUnit(context.seed, worldTileX, worldTileY, SURFACE_POOL_SALT)
				local radius = math.max(
					config.reservoirMinRadius,
					math.floor(
						config.reservoirMinRadius
							+ (config.reservoirMaxRadius - config.reservoirMinRadius) * radiusAlpha
					)
				)
				local waterLevelY = localY + math.max(2, math.floor(radius * 0.7))
				local score = depth + sideWalls * 14 + radius * 10
				if bestCandidate == nil or score > bestCandidate.score then
					bestCandidate = {
						localX = localX,
						localY = localY,
						radius = radius,
						waterLevelY = waterLevelY,
						score = score,
					}
				end

				local reservoirRoll = sampleUnit(context.seed, worldTileX, worldTileY, RESERVOIR_SALT)
				if reservoirRoll < config.reservoirChance then
					if self:fillFloodPocket(context, cells, localX, localY, LIQUID_TYPE.WATER, radius, waterLevelY) then
						didSeed = true
					end
				end
			end
		end
	end

	if not didSeed and bestCandidate ~= nil then
		local fallbackRoll = sampleUnit(context.seed, context.chunkX, context.chunkY, RESERVOIR_SALT + 991)
		if fallbackRoll < 0.7 then
			didSeed = self:fillFloodPocket(
				context,
				cells,
				bestCandidate.localX,
				bestCandidate.localY,
				LIQUID_TYPE.WATER,
				bestCandidate.radius,
				bestCandidate.waterLevelY
			) or didSeed
		end
	end

	return didSeed
end

function LiquidGeneration.seedLavaPockets(
	self: LiquidGeneration,
	context: ChunkLiquidGenerationContext,
	cells: { number }
)
	local config = self.config.generation

	for localY = 0, context.height - 1 do
		for localX = 0, context.width - 1 do
			if self:isSolidTile(context, localX, localY) then
				continue
			end

			local index = computeTileIndex(localX, localY, context.width)
			local depth = context.depthBelowSurface[index] or -1
			if depth < config.lavaStartDepth then
				continue
			end

			local hasSolidFloor = self:isSolidTile(context, localX, localY - 1)
			local sideWalls = 0
			if self:isSolidTile(context, localX - 1, localY) then
				sideWalls += 1
			end
			if self:isSolidTile(context, localX + 1, localY) then
				sideWalls += 1
			end
			if not hasSolidFloor or sideWalls <= 0 then
				continue
			end

			local worldTileX = context.tileMinX + localX
			local worldTileY = context.tileMinY + localY
			local depthAlpha = math.clamp(
				(depth - config.lavaStartDepth) / math.max(1, config.lavaCommonDepth - config.lavaStartDepth),
				0,
				1
			)
			local pocketChance = config.lavaPocketChance * (0.45 + depthAlpha * 1.35)
			local reservoirChance = config.lavaReservoirChance * (0.35 + depthAlpha * 1.5)

			local pocketRoll = sampleUnit(context.seed, worldTileX, worldTileY, LAVA_POCKET_SALT)
			if pocketRoll < pocketChance then
				local radiusAlpha = sampleUnit(context.seed, worldTileX, worldTileY, LAVA_RESERVOIR_SALT)
				local radius = math.max(
					config.lavaPocketMinRadius,
					math.floor(
						config.lavaPocketMinRadius
							+ (config.lavaPocketMaxRadius - config.lavaPocketMinRadius) * radiusAlpha
					)
				)
				self:fillFloodPocket(
					context,
					cells,
					localX,
					localY,
					LIQUID_TYPE.LAVA,
					radius,
					localY + math.max(1, math.floor(radius * 0.5))
				)
				continue
			end

			if sideWalls >= 2 then
				local reservoirRoll = sampleUnit(context.seed, worldTileX, worldTileY, LAVA_RESERVOIR_SALT)
				if reservoirRoll < reservoirChance then
					local radiusAlpha = sampleUnit(context.seed, worldTileX, worldTileY, CAVE_POCKET_SALT)
					local radius = math.max(
						config.lavaPocketMinRadius + 1,
						math.floor(
							config.lavaPocketMinRadius
								+ 1
								+ (config.lavaPocketMaxRadius - config.lavaPocketMinRadius) * radiusAlpha
						)
					)
					self:fillFloodPocket(
						context,
						cells,
						localX,
						localY,
						LIQUID_TYPE.LAVA,
						radius,
						localY + math.max(2, math.floor(radius * 0.65))
					)
				end
			end
		end
	end
end

function LiquidGeneration.generateChunkLiquids(
	self: LiquidGeneration,
	contextRaw: ChunkLiquidGenerationContext
): { number }
	local context = contextRaw
	local cells = Sift.Array.create(context.width * context.height, 0)

	self:seedSurfacePools(context, cells)
	self:seedUndergroundPockets(context, cells)
	self:seedLavaPockets(context, cells)

	local settled = LiquidSolver.settleGrid(
		self.config,
		cells,
		context.width,
		context.height,
		function(localX: number, localY: number): boolean
			return self:isSolidTile(context, localX, localY)
		end,
		self.config.simulation.generationSettlePasses
	)

	return settled
end

return LiquidGeneration
