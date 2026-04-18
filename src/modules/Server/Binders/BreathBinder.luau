--!strict

local LiquidServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.LiquidService.LiquidServiceUtils)
local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local BreathBinder = {}
BreathBinder.__index = BreathBinder
setmetatable(BreathBinder, ModelBinder)

local ACTIVE_BINDERS = {} :: { [BreathBinder]: boolean }

local function containsPointInPart(part: BasePart, worldPosition: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

function BreathBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, BreathBinder)
	self.rootPart = self:GetRootPart()
	self.model = self:GetModel()
	self.breathType = if self:HasTag(TagBinder.Tags.Breath_Air) then "Air" else "Water"
	ACTIVE_BINDERS[self] = true
	self.instance:SetAttribute("BreathTagged", true)
	self.instance:SetAttribute("BreathKind", self.breathType)
	return self
end

function BreathBinder.containsCharacter(self: any, character: Model): boolean
	local head = character:FindFirstChild("Head")
	if head ~= nil and head:IsA("BasePart") then
		if self.rootPart ~= nil and containsPointInPart(self.rootPart, head.Position) then
			return true
		end
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") and self.rootPart ~= nil then
		return containsPointInPart(self.rootPart, rootPart.Position)
	end

	if self.model ~= nil then
		local ok, boundingCFrame, boundingSize = pcall(function()
			return self.model:GetBoundingBox()
		end)
		if ok and rootPart ~= nil and rootPart:IsA("BasePart") then
			local localPosition = boundingCFrame:PointToObjectSpace(rootPart.Position)
			local halfSize = boundingSize * 0.5
			return math.abs(localPosition.X) <= halfSize.X
				and math.abs(localPosition.Y) <= halfSize.Y
				and math.abs(localPosition.Z) <= halfSize.Z
		end
	end

	return false
end

function BreathBinder.Cleanup(self: any)
	ACTIVE_BINDERS[self] = nil
end

function BreathBinder.QueryCharacterOverride(character: Model?): { [string]: any }?
	if character == nil then
		return nil
	end

	local inAir = false
	local inWater = false
	for binder in ACTIVE_BINDERS do
		if binder:containsCharacter(character) then
			if binder.breathType == "Air" then
				inAir = true
			else
				inWater = true
			end
		end
	end

	if inAir then
		return {
			inLiquid = false,
			dominantType = LiquidServiceUtils.LIQUID_TYPE.NONE,
			breathingLiquidType = LiquidServiceUtils.LIQUID_TYPE.NONE,
			submersionRatio = 0,
			breathingSubmerged = false,
			meaningfulSubmersion = false,
			typeWeights = {},
		}
	end
	if not inWater then
		return nil
	end

	return {
		inLiquid = true,
		dominantType = LiquidServiceUtils.LIQUID_TYPE.WATER,
		breathingLiquidType = LiquidServiceUtils.LIQUID_TYPE.WATER,
		submersionRatio = 1,
		breathingSubmerged = true,
		meaningfulSubmersion = true,
		typeWeights = {
			[LiquidServiceUtils.LIQUID_TYPE.WATER] = 1,
		},
	}
end

BreathBinder.queryCharacterOverride = BreathBinder.QueryCharacterOverride

return BreathBinder
