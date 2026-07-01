local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Maid = require("Maid")

local Children = Fusion.Children

local QueenBeeRoot = {}

export type QueenBeeRootConfig = {
	name: string?,
	phaseModel: string?,
	size: Vector3?,
	cframe: CFrame?,
	parent: Instance?,
}

local DEFAULT_NAME = "QueenBee"
local DEFAULT_SIZE = Vector3.new(6, 13.5, 18)

local function CoerceName(valueRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return DEFAULT_NAME
end

local function CoerceSize(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return Vector3.new(math.max(0.05, valueRaw.X), math.max(0.05, valueRaw.Y), math.max(0.05, valueRaw.Z))
	end
	return DEFAULT_SIZE
end

local function CoercePhaseModel(valueRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return "Phase1"
end

function QueenBeeRoot.CreateModel(configRaw: QueenBeeRootConfig?): Model
	local config = (if typeof(configRaw) == "table" then configRaw else {} :: any) :: QueenBeeRootConfig
	local scope = Fusion.scoped(Fusion)
	local maid = Maid.new()
	local rootPart = scope:New "Part" {
		Name = "RootPart",
		Size = CoerceSize(config.size),
		CFrame = if typeof(config.cframe) == "CFrame" then config.cframe else CFrame.identity,
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = true,
		CanTouch = false,
	}
	local model = scope:New "Model" {
		Name = CoerceName(config.name),
		Parent = if typeof(config.parent) == "Instance" then config.parent else nil,

		[Fusion.Attribute("BossPhaseModel")] = CoercePhaseModel(config.phaseModel),
		[Fusion.Attribute("BossSpriteRoot")] = true,

		[Children] = {
			rootPart,
		},
	} :: Model

	maid:GiveTask(function()
		Fusion.doCleanup(scope)
	end)
	maid:GiveTask(model.Destroying:Connect(function()
		maid:DoCleaning()
	end))

	return model
end
return QueenBeeRoot
