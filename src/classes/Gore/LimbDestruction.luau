--!strict
local LimbDestruction = {}
LimbDestruction.__index = LimbDestruction

export type LimbDestructionConfig = {
	entity: Model?,
	model: Model?,
	destroyedTransparency: number?,
}

export type DestroyResult = {
	limb: BasePart,
	limbName: string,
	originCFrame: CFrame,
	originPosition: Vector3,
	gibSource: BasePart,
	bloodColor: Color3,
}

type MotorStateMap = { [Motor6D]: boolean }

type DestroyedLimbRecord = {
	part: BasePart,
	transparency: number,
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean,
	massless: boolean,
	motorStates: MotorStateMap,
}

export type LimbDestruction = typeof(setmetatable(
	{} :: {
		entityModel: Model?,
		destroyedTransparency: number,
		destroyedByPart: { [BasePart]: DestroyedLimbRecord },
	},
	LimbDestruction
))

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function normalizeToken(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.lower(string.gsub(string.match(valueRaw, "^%s*(.-)%s*$") or "", "[%s_%-%.]", ""))
end

local function resolveEntityModel(configRaw: LimbDestructionConfig?): Model?
	if configRaw == nil then
		return nil
	end

	local model = configRaw.model
	if model ~= nil then
		return model
	end

	local entity = configRaw.entity
	if entity ~= nil then
		return entity
	end

	return nil
end

local function cloneLimbForGib(limb: BasePart): BasePart
	local clone = limb:Clone()
	clone.Name = limb.Name .. "_Gib"
	clone.Anchored = true
	clone.AssemblyLinearVelocity = Vector3.zero
	clone.AssemblyAngularVelocity = Vector3.zero

	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("Constraint") or descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end

	return clone
end

local function resolveLimbFromString(entityModel: Model?, tokenRaw: string): BasePart?
	if entityModel == nil then
		return nil
	end

	local token = normalizeToken(tokenRaw)
	if token == "" then
		return nil
	end

	for _, descendant in entityModel:GetDescendants() do
		if descendant:IsA("BasePart") and normalizeToken(descendant.Name) == token then
			return descendant
		end
	end

	return nil
end

local function resolveBloodColor(limb: BasePart, fallbackRaw: any): Color3
	if typeof(fallbackRaw) == "Color3" then
		return fallbackRaw
	end

	local attributeValue = limb:GetAttribute("BloodColor")
	if typeof(attributeValue) == "Color3" then
		return attributeValue
	end

	return limb.Color
end

function LimbDestruction.new(configRaw: LimbDestructionConfig?): LimbDestruction
	local config = if typeof(configRaw) == "table" then configRaw else nil
	local self = setmetatable({
		entityModel = resolveEntityModel(config),
		destroyedTransparency = sanitizeNumber(config and config.destroyedTransparency, 1, 0, 1),
		destroyedByPart = {} :: { [BasePart]: DestroyedLimbRecord },
	}, LimbDestruction)

	return self
end

function LimbDestruction.setEntityModel(self: LimbDestruction, modelRaw: any)
	if typeof(modelRaw) == "Instance" and modelRaw:IsA("Model") then
		self.entityModel = modelRaw
		return
	end
	self.entityModel = nil
end

function LimbDestruction.resolveLimb(self: LimbDestruction, limbRaw: any): BasePart?
	if typeof(limbRaw) == "Instance" and limbRaw:IsA("BasePart") then
		local model = self.entityModel
		if model == nil then
			return limbRaw
		end
		if limbRaw:IsDescendantOf(model) then
			return limbRaw
		end
		return nil
	end

	if typeof(limbRaw) == "string" then
		return resolveLimbFromString(self.entityModel, limbRaw)
	end

	return nil
end

function LimbDestruction.isDestroyed(self: LimbDestruction, limbRaw: any): boolean
	local limb = self:resolveLimb(limbRaw)
	if limb == nil then
		return false
	end
	return self.destroyedByPart[limb] ~= nil
end

function LimbDestruction._disableLimbMotors(self: LimbDestruction, limb: BasePart): MotorStateMap
	local motorStates = {} :: MotorStateMap
	local model = self.entityModel
	if model == nil then
		return motorStates
	end

	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("Motor6D") then
			continue
		end
		if descendant.Part0 ~= limb and descendant.Part1 ~= limb then
			continue
		end

		motorStates[descendant] = descendant.Enabled
		descendant.Enabled = false
	end

	return motorStates
end

function LimbDestruction.destroyLimb(self: LimbDestruction, limbRaw: any, optionsRaw: any): DestroyResult?
	local limb = self:resolveLimb(limbRaw)
	if limb == nil then
		return nil
	end
	if self.destroyedByPart[limb] ~= nil then
		return nil
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local destroyedTransparency = sanitizeNumber(options.destroyedTransparency, self.destroyedTransparency, 0, 1)
	local record: DestroyedLimbRecord = {
		part = limb,
		transparency = limb.Transparency,
		canCollide = limb.CanCollide,
		canTouch = limb.CanTouch,
		canQuery = limb.CanQuery,
		massless = limb.Massless,
		motorStates = self:_disableLimbMotors(limb),
	}
	self.destroyedByPart[limb] = record

	limb.Transparency = destroyedTransparency
	limb.CanCollide = false
	limb.CanTouch = false
	limb.CanQuery = false
	limb.Massless = true

	local gibSource = cloneLimbForGib(limb)
	local bloodColor = resolveBloodColor(limb, options.bloodColor)
	return {
		limb = limb,
		limbName = limb.Name,
		originCFrame = limb.CFrame,
		originPosition = limb.Position,
		gibSource = gibSource,
		bloodColor = bloodColor,
	}
end

function LimbDestruction.restoreLimb(self: LimbDestruction, limbRaw: any): boolean
	local limb = self:resolveLimb(limbRaw)
	if limb == nil then
		return false
	end

	local record = self.destroyedByPart[limb]
	if record == nil then
		return false
	end

	limb.Transparency = record.transparency
	limb.CanCollide = record.canCollide
	limb.CanTouch = record.canTouch
	limb.CanQuery = record.canQuery
	limb.Massless = record.massless

	for motor, wasEnabled in record.motorStates do
		if motor.Parent ~= nil then
			motor.Enabled = wasEnabled
		end
	end

	self.destroyedByPart[limb] = nil
	return true
end

function LimbDestruction.restoreAll(self: LimbDestruction)
	for limb in self.destroyedByPart do
		self:restoreLimb(limb)
	end
end

function LimbDestruction.destroy(self: LimbDestruction)
	self:restoreAll()
	table.clear(self.destroyedByPart)
	self.entityModel = nil
end

return LimbDestruction
