local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

local Configs = require(script:FindFirstAncestor("game").Shared:WaitForChild("QueenBeeConfigs"))
local Physics = require("Physics")

local Render = {}

export type RenderContext = {
	model: Model?,
	rootPart: BasePart?,
	state: Configs.QueenBeeState,
	phase: number,
	enraged: boolean,
	stateTime: number,
	velocity: Vector3,
	facingSign: number,
	targetPosition: Vector3?,
	hoverPoint: Vector3?,
	chargeDirection: Vector3?,
	config: Configs.QueenBeeConfig,
}

local function setAttribute(instance: Instance?, name: string, value: any)
	if instance == nil then
		return
	end
	instance:SetAttribute(name, value)
end

local function GetFacingSign(context: RenderContext): number
	if context.velocity.Magnitude > 0.5 then
		local sign = if math.abs(context.velocity.Z) > 0.001 then math.sign(context.velocity.Z) else 0
		if sign ~= 0 then
			return sign
		end
	end

	local rootPart = context.rootPart
	local targetPosition = context.targetPosition
	if rootPart ~= nil and targetPosition ~= nil then
		return Physics.FaceTarget(nil, targetPosition - rootPart.Position)
	end

	local sign = math.sign(context.facingSign)
	if sign == 0 then
		return 1
	end
	return sign
end

local function GetWingSpeed(context: RenderContext): number
	local phaseBoost = 1 + math.max(0, context.phase - 1) * 0.34
	local stateBoost = if context.state == Configs.States.Charge
			or context.state == Configs.States.ChargeWindup
		then 1.35
		else 1
	local enrageBoost = if context.enraged then 1.25 else 1
	return phaseBoost * stateBoost * enrageBoost
end

local function GetChargeAnticipation(context: RenderContext): number
	if context.state == Configs.States.Charge then
		return 1
	end
	if context.state ~= Configs.States.ChargeWindup then
		return 0
	end

	local windup = context.config.ChargeWindupByPhase[context.phase] or context.config.ChargeWindupByPhase[1]
	if windup <= 0 then
		return 1
	end
	return math.clamp(context.stateTime / windup, 0, 1)
end

local function updateWingAttributes(model: Model?, wingSpeed: number, anticipation: number)
	if model == nil then
		return
	end

	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local lowerName = string.lower(descendant.Name)
		if string.find(lowerName, "wing", 1, true) == nil then
			continue
		end

		descendant:SetAttribute("QueenBeeWingSpeed", wingSpeed)
		descendant:SetAttribute("QueenBeeChargeAnticipation", anticipation)
	end
end

function Render.Apply(context: RenderContext)
	local model = context.model
	local rootPart = context.rootPart
	local facingSign = GetFacingSign(context)
	local wingSpeed = GetWingSpeed(context)
	local anticipation = GetChargeAnticipation(context)

	setAttribute(model, "QueenBeeRenderFacingSign", facingSign)
	setAttribute(model, "QueenBeeWingSpeed", wingSpeed)
	setAttribute(model, "QueenBeeChargeAnticipation", anticipation)
	setAttribute(model, "QueenBeeRenderVelocity", context.velocity)
	setAttribute(rootPart, "QueenBeeRenderFacingSign", facingSign)
	setAttribute(rootPart, "QueenBeeWingSpeed", wingSpeed)
	setAttribute(rootPart, "QueenBeeChargeAnticipation", anticipation)
	setAttribute(rootPart, "QueenBeeRenderVelocity", context.velocity)

	if context.config.Debug then
		setAttribute(model, "QueenBeeDebugHoverPoint", context.hoverPoint)
		setAttribute(model, "QueenBeeDebugChargeDirection", context.chargeDirection)
		setAttribute(model, "QueenBeeDebugState", context.state)
		setAttribute(rootPart, "QueenBeeDebugHoverPoint", context.hoverPoint)
		setAttribute(rootPart, "QueenBeeDebugChargeDirection", context.chargeDirection)
		setAttribute(rootPart, "QueenBeeDebugState", context.state)
	end

	updateWingAttributes(model, wingSpeed, anticipation)
end

function Render.CreateMaid(): any
	return Maid.new()
end
return Render
