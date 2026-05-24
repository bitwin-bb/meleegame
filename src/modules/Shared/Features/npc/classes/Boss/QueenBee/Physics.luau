--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Table = loader("Table")

local Physics = {}

local PLANE_AXES = table.freeze(Table.copy({
	depth = Vector3.xAxis,
	up = Vector3.yAxis,
	side = Vector3.zAxis,
}))

local EPSILON = 1e-5

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

local function safeUnit(vector: Vector3, fallbackRaw: Vector3?): Vector3
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else PLANE_AXES.side
	if vector.Magnitude <= EPSILON then
		if fallback.Magnitude <= EPSILON then
			return PLANE_AXES.side
		end
		return fallback.Unit
	end
	return vector.Unit
end

local function resolveRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local rootPart = model:FindFirstChild("RootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function resolveCharacter(valueRaw: any): Model?
	if typeof(valueRaw) ~= "Instance" then
		return nil
	end

	if valueRaw:IsA("Player") then
		return valueRaw.Character
	end
	if valueRaw:IsA("Model") then
		return valueRaw
	end
	if valueRaw:IsA("Humanoid") then
		local parent = valueRaw.Parent
		return if parent ~= nil and parent:IsA("Model") then parent else nil
	end
	if valueRaw:IsA("BasePart") then
		return valueRaw:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Physics.ProjectToCombatPlane(position: Vector3, arenaCFrame: CFrame?): Vector3
	if typeof(arenaCFrame) ~= "CFrame" then
		return position
	end

	local localPosition = arenaCFrame:PointToObjectSpace(position)
	return arenaCFrame:PointToWorldSpace(Vector3.new(0, localPosition.Y, localPosition.Z))
end

function Physics.ProjectVectorToCombatPlane(vector: Vector3, arenaCFrame: CFrame?): Vector3
	if typeof(arenaCFrame) ~= "CFrame" then
		return Vector3.new(0, vector.Y, vector.Z)
	end

	local localVector = arenaCFrame:VectorToObjectSpace(vector)
	return arenaCFrame:VectorToWorldSpace(Vector3.new(0, localVector.Y, localVector.Z))
end

function Physics.GetCombatSideVector(arenaCFrame: CFrame?): Vector3
	if typeof(arenaCFrame) == "CFrame" then
		return safeUnit(arenaCFrame:VectorToWorldSpace(PLANE_AXES.side), PLANE_AXES.side)
	end
	return PLANE_AXES.side
end

function Physics.GetCombatUpVector(arenaCFrame: CFrame?): Vector3
	if typeof(arenaCFrame) == "CFrame" then
		return safeUnit(arenaCFrame:VectorToWorldSpace(PLANE_AXES.up), PLANE_AXES.up)
	end
	return PLANE_AXES.up
end

function Physics.GetTargetCenter(character: any): Vector3?
	if typeof(character) == "Vector3" then
		return character
	end

	if typeof(character) == "Instance" and character:IsA("BasePart") then
		return character.Position
	end

	local model = resolveCharacter(character)
	if model == nil then
		return nil
	end

	local rootPart = resolveRootPart(model)
	if rootPart ~= nil then
		return rootPart.Position
	end

	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok then
		return pivot.Position
	end
	return nil
end

function Physics.GetTargetVelocity(character: any): Vector3
	if typeof(character) == "Instance" and character:IsA("BasePart") then
		return character.AssemblyLinearVelocity
	end

	local model = resolveCharacter(character)
	local rootPart = resolveRootPart(model)
	if rootPart == nil then
		return Vector3.zero
	end
	return rootPart.AssemblyLinearVelocity
end

function Physics.ApproachVelocity(current: Vector3, desired: Vector3, maxDeltaRaw: any): Vector3
	local maxDelta = sanitizeNumber(maxDeltaRaw, 0, 0, nil)
	local delta = desired - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance <= EPSILON then
		return desired
	end
	return current + delta.Unit * maxDelta
end

function Physics.ComputeHoverVelocity(
	currentPosition: Vector3,
	currentVelocity: Vector3,
	targetPosition: Vector3,
	speedRaw: any,
	accelerationRaw: any,
	dampingRaw: any,
	arriveRadiusRaw: any,
	dtRaw: any
): Vector3
	local dt = sanitizeNumber(dtRaw, 0, 0, 1)
	local speed = sanitizeNumber(speedRaw, 0, 0, 10 ^ 6)
	local acceleration = sanitizeNumber(accelerationRaw, 0, 0, 10 ^ 6)
	local damping = sanitizeNumber(dampingRaw, 0, 0, 1000)
	local arriveRadius = sanitizeNumber(arriveRadiusRaw, 0, 0, 10 ^ 6)
	local offset = targetPosition - currentPosition
	local distance = offset.Magnitude

	local desiredVelocity = Vector3.zero
	if distance > EPSILON and speed > 0 then
		local direction = offset.Unit
		desiredVelocity = direction * speed
	end

	local nextVelocity = Physics.ApproachVelocity(currentVelocity, desiredVelocity, acceleration * dt)
	if speed > 0 and nextVelocity.Magnitude > speed then
		nextVelocity = nextVelocity.Unit * speed
	end
	if arriveRadius > 0 and distance <= arriveRadius and damping > 0 then
		nextVelocity *= math.exp(-damping * dt)
	end

	return nextVelocity
end

function Physics.ComputeChargeVelocity(direction: Vector3, speedRaw: any): Vector3
	local speed = sanitizeNumber(speedRaw, 0, 0, 10 ^ 6)
	return safeUnit(direction, PLANE_AXES.side) * speed
end

function Physics.HasPassedTarget(
	startPosition: Vector3,
	currentPosition: Vector3,
	targetPosition: Vector3,
	direction: Vector3,
	passDistanceRaw: any
): boolean
	local passDistance = sanitizeNumber(passDistanceRaw, 0, 0, 10 ^ 6)
	local chargeDirection = safeUnit(direction, currentPosition - startPosition)
	local targetAheadFromStart = (targetPosition - startPosition):Dot(chargeDirection)
	if targetAheadFromStart < 0 then
		return true
	end

	return (currentPosition - targetPosition):Dot(chargeDirection) >= passDistance
end

function Physics.FaceTarget(root: BasePart?, targetPosition: Vector3): number
	local rootPosition = if root ~= nil then root.Position else Vector3.zero
	local delta = targetPosition - rootPosition
	local sign = if math.abs(delta.Z) > 0.001 then math.sign(delta.Z) else math.sign(delta.X)
	if sign == 0 then
		sign = 1
	end

	if root ~= nil then
		root:SetAttribute("QueenBeeFacingSign", sign)
	end
	return sign
end

function Physics.ComputeOffsetInCombatPlane(
	targetCenter: Vector3,
	sideSignRaw: any,
	sideDistanceRaw: any,
	aboveOffsetRaw: any,
	arenaCFrame: CFrame?
): Vector3
	local sideSign = if sideSignRaw == -1 then -1 else 1
	local sideDistance = sanitizeNumber(sideDistanceRaw, 0, 0, 10 ^ 6)
	local aboveOffset = sanitizeNumber(aboveOffsetRaw, 0, -10 ^ 6, 10 ^ 6)
	local sideVector = Physics.GetCombatSideVector(arenaCFrame)
	local upVector = Physics.GetCombatUpVector(arenaCFrame)
	return Physics.ProjectToCombatPlane(
		targetCenter + sideVector * sideSign * sideDistance + upVector * aboveOffset,
		arenaCFrame
	)
end

function Physics.RotateVectorInCombatPlane(vector: Vector3, degreesRaw: any, arenaCFrame: CFrame?): Vector3
	local radians = math.rad(sanitizeNumber(degreesRaw, 0, -360, 360))
	if math.abs(radians) <= EPSILON then
		return Physics.ProjectVectorToCombatPlane(vector, arenaCFrame)
	end

	local localVector = if typeof(arenaCFrame) == "CFrame" then arenaCFrame:VectorToObjectSpace(vector) else vector
	local y = localVector.Y
	local z = localVector.Z
	local cos = math.cos(radians)
	local sin = math.sin(radians)
	local rotatedLocal = Vector3.new(0, y * cos - z * sin, y * sin + z * cos)
	local rotated = if typeof(arenaCFrame) == "CFrame"
		then arenaCFrame:VectorToWorldSpace(rotatedLocal)
		else rotatedLocal
	return safeUnit(Physics.ProjectVectorToCombatPlane(rotated, arenaCFrame), vector)
end

function Physics.BuildFacingCFrame(position: Vector3, facingSignRaw: any, arenaCFrame: CFrame?): CFrame
	local sideSign = if facingSignRaw == -1 then -1 else 1
	local sideVector = Physics.GetCombatSideVector(arenaCFrame) * sideSign
	local upVector = Physics.GetCombatUpVector(arenaCFrame)
	return CFrame.lookAt(position, position + sideVector, upVector)
end

Physics.projectToCombatPlane = Physics.ProjectToCombatPlane
Physics.projectVectorToCombatPlane = Physics.ProjectVectorToCombatPlane
Physics.getCombatSideVector = Physics.GetCombatSideVector
Physics.getCombatUpVector = Physics.GetCombatUpVector
Physics.getTargetCenter = Physics.GetTargetCenter
Physics.getTargetVelocity = Physics.GetTargetVelocity
Physics.approachVelocity = Physics.ApproachVelocity
Physics.computeHoverVelocity = Physics.ComputeHoverVelocity
Physics.computeChargeVelocity = Physics.ComputeChargeVelocity
Physics.hasPassedTarget = Physics.HasPassedTarget
Physics.faceTarget = Physics.FaceTarget
Physics.computeOffsetInCombatPlane = Physics.ComputeOffsetInCombatPlane
Physics.rotateVectorInCombatPlane = Physics.RotateVectorInCombatPlane
Physics.buildFacingCFrame = Physics.BuildFacingCFrame

return Physics
