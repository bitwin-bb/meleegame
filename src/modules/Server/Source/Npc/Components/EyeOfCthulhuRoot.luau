local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local WorldGenerationConstants = require("WorldGenerationConstants")

local Children = Fusion.Children

local EyeOfCthulhuRoot = {}

export type EyeOfCthulhuRootConfig = {
	name: string?,
	phaseModel: string?,
	size: Vector3?,
	cframe: CFrame?,
	parent: Instance?,
}

local DEFAULT_NAME = "EyeOfCthulhu"
local PLANE_DEPTH = WorldGenerationConstants.DEFAULT_TILE_DEPTH
local PHASE1_SIZE = Vector3.new(PLANE_DEPTH, 14, 14)
local PHASE2_SIZE = Vector3.new(PLANE_DEPTH, 14, 14)

local function coerceName(valueRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return DEFAULT_NAME
end

local function getDefaultSize(phaseModelRaw: any): Vector3
	if typeof(phaseModelRaw) == "string" and string.lower(phaseModelRaw) == "phase2" then
		return PHASE2_SIZE
	end
	return PHASE1_SIZE
end

local function coerceSize(valueRaw: any, fallback: Vector3): Vector3
	if typeof(valueRaw) == "Vector3" then
		return Vector3.new(PLANE_DEPTH, math.max(0.05, valueRaw.Y), math.max(0.05, valueRaw.Z))
	end
	return fallback
end

function EyeOfCthulhuRoot.CreateModel(configRaw: EyeOfCthulhuRootConfig?): Model
	local config = (if typeof(configRaw) == "table" then configRaw else {} :: any) :: EyeOfCthulhuRootConfig
	local phaseModel = if typeof(config.phaseModel) == "string" and config.phaseModel ~= ""
		then config.phaseModel
		else "Phase1"
	local scope = Fusion.scoped(Fusion)
	local rootPart = scope:New "Part" {
		Name = "RootPart",
		Size = coerceSize(config.size, getDefaultSize(phaseModel)),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = true,
		CanTouch = false,
	}

	local model = scope:New "Model" {
		Name = coerceName(config.name),
		[Children] = {
			rootPart,
		},
	} :: Model

	model:SetAttribute("BossPhaseModel", phaseModel)
	model:SetAttribute("BossSpriteRoot", true)
	model.PrimaryPart = rootPart :: BasePart
	if typeof(config.cframe) == "CFrame" then
		model:PivotTo(config.cframe :: CFrame)
	end
	if typeof(config.parent) == "Instance" then
		model.Parent = config.parent
	end

	return model
end
return EyeOfCthulhuRoot
