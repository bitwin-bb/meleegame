local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local WorldGenerationConstants = require("WorldGenerationConstants")

local Children = Fusion.Children

local EyeOfCthulhuServantRoot = {}

export type EyeOfCthulhuServantRootConfig = {
	name: string?,
	size: Vector3?,
	cframe: CFrame?,
	parent: Instance?,
}

local DEFAULT_NAME = "ServantOfCthulhu"
local PLANE_DEPTH = WorldGenerationConstants.DEFAULT_TILE_DEPTH
local DEFAULT_ROOT_SIZE = Vector3.new(PLANE_DEPTH, 2.6, 2.6)

local function coerceName(valueRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return DEFAULT_NAME
end

local function coerceSize(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return Vector3.new(PLANE_DEPTH, math.max(0.05, valueRaw.Y), math.max(0.05, valueRaw.Z))
	end
	return DEFAULT_ROOT_SIZE
end

function EyeOfCthulhuServantRoot.CreateModel(configRaw: EyeOfCthulhuServantRootConfig?): Model
	local config = (if typeof(configRaw) == "table" then configRaw else {} :: any) :: EyeOfCthulhuServantRootConfig
	local scope = Fusion.scoped(Fusion)
	local rootPart = scope:New "Part" {
		Name = "RootPart",
		Size = coerceSize(config.size),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}

	local model = scope:New "Model" {
		Name = coerceName(config.name),
		[Children] = {
			rootPart,
		},
	} :: Model

	model:SetAttribute("BossServantSpriteRoot", true)
	model.PrimaryPart = rootPart :: BasePart
	if typeof(config.cframe) == "CFrame" then
		model:PivotTo(config.cframe :: CFrame)
	end
	if typeof(config.parent) == "Instance" then
		model.Parent = config.parent
	end

	return model
end
return EyeOfCthulhuServantRoot
