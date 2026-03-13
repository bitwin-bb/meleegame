--!strict

local Workspace = game:GetService("Workspace")

local LODController = {}
LODController.__index = LODController

export type TierState = {
	name: string,
	updateInterval: number,
	lodState: {
		level: string,
		windScale: number,
		detailScale: number,
		disturbanceScale: number,
	},
	priority: number,
	frozen: boolean,
	canopyOnly: boolean,
}

export type LODController = typeof(setmetatable({} :: any, LODController))

local function clampNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

local function buildTier(
	name: string,
	updateIntervalRaw: any,
	defaultInterval: number,
	windScaleRaw: any,
	defaultWindScale: number,
	detailScaleRaw: any,
	defaultDetailScale: number,
	disturbanceScaleRaw: any,
	defaultDisturbanceScale: number,
	priority: number,
	frozen: boolean,
	canopyOnly: boolean
): TierState
	return {
		name = name,
		updateInterval = clampNumber(updateIntervalRaw, defaultInterval, 1 / 240, 10),
		lodState = {
			level = name,
			windScale = clampNumber(windScaleRaw, defaultWindScale, 0, 4),
			detailScale = clampNumber(detailScaleRaw, defaultDetailScale, 0, 4),
			disturbanceScale = clampNumber(disturbanceScaleRaw, defaultDisturbanceScale, 0, 4),
		},
		priority = priority,
		frozen = frozen,
		canopyOnly = canopyOnly,
	}
end

function LODController.new(configRaw: any?): LODController
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local runtime = if typeof(config.runtime) == "table" then config.runtime else {}
	local lod = if typeof(config.lod) == "table" then config.lod else {}

	local nearFallback = clampNumber(lod.nearDistance, 54, 0, 5000)
	local nearDistance = clampNumber(runtime.nearDistance, nearFallback, 0, 5000)
	local midFallback = clampNumber(lod.midDistance, 118, nearDistance, 5000)
	local midDistance = clampNumber(runtime.midDistance, midFallback, nearDistance, 5000)
	local farFallback = clampNumber(lod.farDistance, 190, midDistance, 10000)
	local farDistance = clampNumber(runtime.farDistance, farFallback, midDistance, 10000)
	local cullFallback = clampNumber(lod.cullDistance, 280, farDistance, 20000)
	local cullDistance = clampNumber(runtime.cullDistance, cullFallback, farDistance, 20000)

	local self = setmetatable({
		nearDistanceSquared = nearDistance * nearDistance,
		midDistanceSquared = midDistance * midDistance,
		farDistanceSquared = farDistance * farDistance,
		cullDistanceSquared = cullDistance * cullDistance,
		viewDotCull = clampNumber(runtime.viewDotCull, -0.35, -1, 1),
		enableVisibilityCull = runtime.enableVisibilityCull ~= false,
		tierNear = buildTier(
			"Near",
			runtime.nearUpdateInterval or lod.nearUpdateInterval,
			1 / 60,
			runtime.nearWindScale,
			1,
			runtime.nearDetailScale,
			1,
			runtime.nearDisturbanceScale,
			1,
			3,
			false,
			false
		),
		tierMid = buildTier(
			"Mid",
			runtime.midUpdateInterval or lod.midUpdateInterval,
			0.12,
			runtime.midWindScale,
			0.82,
			runtime.midDetailScale,
			0.42,
			runtime.midDisturbanceScale,
			0.42,
			2,
			false,
			false
		),
		tierFar = buildTier(
			"Far",
			runtime.farUpdateInterval or lod.farUpdateInterval,
			0.32,
			runtime.farWindScale,
			0.56,
			runtime.farDetailScale,
			0.1,
			runtime.farDisturbanceScale,
			0,
			1,
			false,
			runtime.enableCanopyOnlyFar == true
		),
		tierFrozen = buildTier(
			"Frozen",
			runtime.frozenUpdateInterval,
			0.75,
			0,
			0,
			0,
			0,
			0,
			0,
			0,
			true,
			false
		),
	}, LODController)

	return self
end

function LODController.isVisible(self: LODController, worldPosition: Vector3, boundingRadius: number): boolean
	if not self.enableVisibilityCull then
		return true
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return true
	end

	local cameraPosition = camera.CFrame.Position
	local toTree = worldPosition - cameraPosition
	local distance = toTree.Magnitude
	if distance <= math.max(4, boundingRadius) then
		return true
	end
	if distance <= 1e-4 then
		return true
	end

	local dot = camera.CFrame.LookVector:Dot(toTree / distance)
	return dot >= self.viewDotCull
end

function LODController.resolve(self: LODController, distanceSquared: number, worldPosition: Vector3, boundingRadius: number): TierState?
	if distanceSquared > self.cullDistanceSquared then
		return nil
	end

	if distanceSquared <= self.nearDistanceSquared then
		return self.tierNear
	end

	if not self:isVisible(worldPosition, boundingRadius) then
		return self.tierFrozen
	end

	if distanceSquared <= self.midDistanceSquared then
		return self.tierMid
	end
	if distanceSquared <= self.farDistanceSquared then
		return self.tierFar
	end
	return self.tierFrozen
end

function LODController.degrade(self: LODController, tier: TierState): TierState
	if tier.name == "Near" then
		return self.tierMid
	end
	if tier.name == "Mid" then
		return self.tierFar
	end
	return self.tierFrozen
end

return LODController
