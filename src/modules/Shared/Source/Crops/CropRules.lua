local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CropTypes = require("CropTypes")

local CropRules = {}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function contains(listRaw: any, value: any): boolean
	if typeof(listRaw) ~= "table" then
		return true
	end
	if (listRaw :: any)[value] == true then
		return true
	end
	for _, candidate in listRaw do
		if candidate == value then
			return true
		end
	end
	return false
end

local function isClockTimeAllowed(clockTimeRaw: any, minimumRaw: any, maximumRaw: any): boolean
	if not isFiniteNumber(minimumRaw) and not isFiniteNumber(maximumRaw) then
		return true
	end

	local clockTime = if isFiniteNumber(clockTimeRaw) then (clockTimeRaw :: number) % 24 else 0
	local minimum = if isFiniteNumber(minimumRaw) then (minimumRaw :: number) % 24 else 0
	local maximum = if isFiniteNumber(maximumRaw) then (maximumRaw :: number) % 24 else 24
	if minimum <= maximum then
		return clockTime >= minimum and clockTime <= maximum
	end
	return clockTime >= minimum or clockTime <= maximum
end

function CropRules.GetStage(definitionRaw: any, stageRaw: any): any?
	if typeof(definitionRaw) ~= "table" or typeof((definitionRaw :: any).stages) ~= "table" then
		return nil
	end
	local stage = if isFiniteNumber(stageRaw) then math.max(0, math.floor(stageRaw)) else 0
	return (definitionRaw :: any).stages[stage + 1]
end

function CropRules.GetFinalStage(definitionRaw: any): number
	if typeof(definitionRaw) ~= "table" or typeof((definitionRaw :: any).stages) ~= "table" then
		return 0
	end
	return math.max(0, #(definitionRaw :: any).stages - 1)
end

function CropRules.IsMature(definitionRaw: any, stateRaw: any): boolean
	if typeof(stateRaw) ~= "table" then
		return false
	end
	local stage = if isFiniteNumber((stateRaw :: any).stage)
		then math.max(0, math.floor((stateRaw :: any).stage))
		else 0
	return stage >= CropRules.GetFinalStage(definitionRaw)
end

function CropRules.CheckRequirements(requirementsRaw: any, environmentRaw: any): (boolean, string)
	if typeof(requirementsRaw) ~= "table" then
		return true, "ok"
	end
	if typeof(environmentRaw) ~= "table" then
		return false, "missing_environment"
	end

	local requirements = requirementsRaw :: any
	local environment = environmentRaw :: any
	if not contains(requirements.soilTileIds, environment.soilTileId) then
		return false, "invalid_soil"
	end
	if not contains(requirements.biomeIds, environment.biomeId) then
		return false, "invalid_biome"
	end
	if not contains(requirements.biomeTypes, environment.biomeType) then
		return false, "invalid_biome_type"
	end
	if not contains(requirements.dayParts, environment.dayPart) then
		return false, "invalid_time"
	end
	if not contains(requirements.weatherTypes, environment.weatherType) then
		return false, "invalid_weather"
	end
	if not isClockTimeAllowed(environment.clockTime, requirements.minClockTime, requirements.maxClockTime) then
		return false, "invalid_time"
	end

	local light = if isFiniteNumber(environment.light) then environment.light else 0
	if isFiniteNumber(requirements.minLight) and light < requirements.minLight then
		return false, "not_enough_light"
	end
	if isFiniteNumber(requirements.maxLight) and light > requirements.maxLight then
		return false, "too_much_light"
	end

	local water = if isFiniteNumber(environment.water) then environment.water else 0
	if isFiniteNumber(requirements.minWater) and water < requirements.minWater then
		return false, "not_enough_water"
	end
	if isFiniteNumber(requirements.maxWater) and water > requirements.maxWater then
		return false, "too_much_water"
	end

	local rain = if isFiniteNumber(environment.rain) then environment.rain else 0
	if isFiniteNumber(requirements.minRain) and rain < requirements.minRain then
		return false, "not_enough_rain"
	end
	local openAbove = if isFiniteNumber(environment.openAbove) then environment.openAbove else 0
	local openLeft = if isFiniteNumber(environment.openLeft) then environment.openLeft else 0
	local openRight = if isFiniteNumber(environment.openRight) then environment.openRight else 0
	if isFiniteNumber(requirements.clearanceAbove) and openAbove < requirements.clearanceAbove then
		return false, "blocked_above"
	end
	if isFiniteNumber(requirements.clearanceLeft) and openLeft < requirements.clearanceLeft then
		return false, "blocked_left"
	end
	if isFiniteNumber(requirements.clearanceRight) and openRight < requirements.clearanceRight then
		return false, "blocked_right"
	end

	return true, "ok"
end

function CropRules.CanPlant(definitionRaw: any, environmentRaw: any): (boolean, string)
	if typeof(definitionRaw) ~= "table" or typeof(environmentRaw) ~= "table" then
		return false, "invalid_definition_or_environment"
	end

	local definition = definitionRaw :: any
	local environment = environmentRaw :: any
	local placement = definition.placement
	if typeof(placement) ~= "table" then
		return false, "not_plantable"
	end

	if placement.mode == CropTypes.PlacementMode.ReplaceSoil then
		if not contains(placement.targetTileIds, environment.targetTileId) then
			return false, "invalid_target_tile"
		end
		if placement.requireOpenAbove == true and environment.openAbove < 1 then
			return false, "blocked_above"
		end
	elseif placement.mode == CropTypes.PlacementMode.AboveSoil then
		if environment.targetOpen ~= true then
			return false, "target_occupied"
		end
		if not contains(placement.soilTileIds, environment.soilTileId) then
			return false, "invalid_soil"
		end
	else
		return false, "invalid_placement_mode"
	end

	return CropRules.CheckRequirements(definition.plantRequirements, environment)
end

function CropRules.CanGrow(definitionRaw: any, stateRaw: any, environmentRaw: any): (boolean, string)
	if CropRules.IsMature(definitionRaw, stateRaw) then
		return false, "already_mature"
	end

	local commonPassed, commonReason = CropRules.CheckRequirements(
		if typeof(definitionRaw) == "table" then (definitionRaw :: any).growthRequirements else nil,
		environmentRaw
	)
	if not commonPassed then
		return false, commonReason
	end

	local stage = CropRules.GetStage(definitionRaw, if typeof(stateRaw) == "table" then (stateRaw :: any).stage else 0)
	if stage == nil then
		return false, "invalid_stage"
	end
	return CropRules.CheckRequirements((stage :: any).requirements, environmentRaw)
end

function CropRules.CanHarvest(definitionRaw: any, stateRaw: any, environmentRaw: any): (boolean, string)
	if not CropRules.IsMature(definitionRaw, stateRaw) then
		return false, "not_mature"
	end

	local finalStage = CropRules.GetStage(definitionRaw, CropRules.GetFinalStage(definitionRaw))
	local stagePassed, stageReason =
		CropRules.CheckRequirements(if finalStage ~= nil then (finalStage :: any).requirements else nil, environmentRaw)
	if not stagePassed then
		return false, stageReason
	end

	return CropRules.CheckRequirements(
		if typeof(definitionRaw) == "table" then (definitionRaw :: any).harvestRequirements else nil,
		environmentRaw
	)
end

function CropRules.CanSpread(definitionRaw: any, stateRaw: any?, environmentRaw: any): (boolean, string)
	if typeof(definitionRaw) ~= "table" or typeof((definitionRaw :: any).spread) ~= "table" then
		return false, "cannot_spread"
	end

	local spread = (definitionRaw :: any).spread
	if spread.matureOnly == true and stateRaw ~= nil and not CropRules.IsMature(definitionRaw, stateRaw) then
		return false, "not_mature"
	end
	return CropRules.CheckRequirements(spread.requirements, environmentRaw)
end

return Table.readonly(CropRules)
