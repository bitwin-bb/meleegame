local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)

local Children = Fusion.Children

local SlimeRoot = {}

export type SlimeRootConfig = {
	name: string?,
	hp: number?,
	size: Vector3?,
	cframe: CFrame?,
	parent: Instance?,
}

local DEFAULT_NAME = "GreenSlime"
local DEFAULT_HP = 14
local DEFAULT_ROOT_SIZE = Vector3.new(4, 3, 4)

local function CoerceName(valueRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return DEFAULT_NAME
end

local function CoerceHp(valueRaw: any): number
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		return math.max(0, valueRaw)
	end
	return DEFAULT_HP
end

local function CoerceSize(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return Vector3.new(math.max(0.05, valueRaw.X), math.max(0.05, valueRaw.Y), math.max(0.05, valueRaw.Z))
	end
	return DEFAULT_ROOT_SIZE
end

function SlimeRoot.CreateModel(configRaw: SlimeRootConfig?): Model
	local config = (if typeof(configRaw) == "table" then configRaw else {} :: any) :: SlimeRootConfig
	local scope = Fusion.scoped(Fusion)
	local rootPart = scope:New "Part" {
		Name = "RootPart",
		Size = CoerceSize(config.size),
		Transparency = 1,
		Anchored = false,
		CanCollide = true,
		CanQuery = true,
		CanTouch = true,
		CustomPhysicalProperties = PhysicalProperties.new(1, 0.8, 0, 1, 1),
	}

	local hp = scope:New "NumberValue" {
		Name = "Hp",
		Value = CoerceHp(config.hp),
	}

	local model = scope:New "Model" {
		Name = CoerceName(config.name),
		[Children] = {
			hp,
			rootPart,
		},
	} :: Model

	model.PrimaryPart = rootPart :: BasePart
	if typeof(config.cframe) == "CFrame" then
		model:PivotTo(config.cframe :: CFrame)
	end
	if typeof(config.parent) == "Instance" then
		model.Parent = config.parent
	end

	return model
end
return SlimeRoot
