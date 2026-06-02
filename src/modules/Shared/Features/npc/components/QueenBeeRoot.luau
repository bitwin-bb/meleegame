--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Maid = require(quentyPackages.maid.Shared.Maid)

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

local function sanitizeName(valueRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return DEFAULT_NAME
end

local function sanitizeSize(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return Vector3.new(math.max(0.05, valueRaw.X), math.max(0.05, valueRaw.Y), math.max(0.05, valueRaw.Z))
	end
	return DEFAULT_SIZE
end

local function sanitizePhaseModel(valueRaw: any): string
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
		Size = sanitizeSize(config.size),
		CFrame = if typeof(config.cframe) == "CFrame" then config.cframe else CFrame.identity,
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = true,
		CanTouch = false,
	}
	local model = scope:New "Model" {
		Name = sanitizeName(config.name),
		Parent = if typeof(config.parent) == "Instance" then config.parent else nil,

		[Fusion.Attribute("BossPhaseModel")] = sanitizePhaseModel(config.phaseModel),
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

QueenBeeRoot.createModel = QueenBeeRoot.CreateModel

return QueenBeeRoot
