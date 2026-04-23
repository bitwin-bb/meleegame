--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local Damp = require(script:FindFirstAncestor("game").Shared.Modules.Math.Damp)
local Vec = require(script:FindFirstAncestor("game").Shared.Modules.Math.Vec)

type BossMotionState = BossServiceUtils.BossMotionState

export type MotionTargetSnapshot = {
	position: Vector3?,
	velocity: Vector3,
}

export type ChargeLock = {
	direction: Vector3,
	speed: number,
	duration: number,
	destination: Vector3,
	targetPosition: Vector3?,
}

export type MotionRuntimeState = {
	state: string,
	stateTime: number,
	position: Vector3,
	velocity: Vector3,
	facing: Vector3,
	planeX: number?,
	sideSign: number,
	transformBaseFacing: Vector3?,
	lockedCharge: ChargeLock?,
}

export type MotionSolveResult = {
	velocity: Vector3,
	facing: Vector3,
	finished: boolean,
	nextSuggestedState: string?,
	hoverAnchor: Vector3?,
	localPresentationOffset: Vector3?,
	lockedChargeDirection: Vector3?,
	chargeTimeRemaining: number?,
	motionOwner: string,
	debug: BossMotionState,
}

local EyeOfCthulhuMotion = {}

local DEFAULT_CHARGE_DIRECTION = Vector3.new(0, -0.15, 1)
local ZERO_VECTOR = Vector3.zero

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	return BossServiceUtils.sanitizeNumber(valueRaw, fallback, minimum, maximum)
end

local function sanitizeDuration(valueRaw: any, fallback: number): number
	return sanitizeNumber(valueRaw, fallback, 0.01, 60)
end

local function safeUnit(vector: Vector3, fallbackRaw: Vector3?): Vector3
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else Vector3.zAxis
	local fallbackUnit = Vec.unit(fallback, Vector3.zAxis)
	if vector.Magnitude <= 1e-4 then
		return fallbackUnit
	end
	return Vec.unit(vector, fallbackUnit)
end

local function projectPosition(position: Vector3, planeXRaw: any): Vector3
	return BossServiceUtils.projectPositionToPlaneX(position, planeXRaw)
end

local function projectVector(vector: Vector3, planeXRaw: any): Vector3
	return BossServiceUtils.projectVectorToPlaneX(vector, planeXRaw)
end

local function resolveTargetVelocity(targetSnapshot: MotionTargetSnapshot?): Vector3
	if targetSnapshot == nil then
		return ZERO_VECTOR
	end
	return targetSnapshot.velocity
end

local function resolveFacingTowardTarget(
	currentPosition: Vector3,
	targetSnapshot: MotionTargetSnapshot?,
	fallbackRaw: Vector3?
): Vector3
	local fallback = if typeof(fallbackRaw) == "Vector3" then fallbackRaw else Vector3.zAxis
	if targetSnapshot ~= nil and targetSnapshot.position ~= nil then
		return safeUnit(targetSnapshot.position - currentPosition, fallback)
	end
	return safeUnit(fallback, Vector3.zAxis)
end

local function resolvePlaneFallback(sideSignRaw: any): Vector3
	local sideSign = if sideSignRaw == -1 then -1 else 1
	return safeUnit(Vector3.new(0, -0.15, sideSign), DEFAULT_CHARGE_DIRECTION)
end

local function dampVelocity(velocity: Vector3, dampingRaw: any, dt: number): Vector3
	local damping = sanitizeNumber(dampingRaw, 0, 0, 1000)
	if damping <= 0 then
		return velocity
	end
	return Damp.value(velocity, ZERO_VECTOR, damping, dt)
end

local function solveAnchoredVelocity(
	currentPosition: Vector3,
	currentVelocity: Vector3,
	targetAnchor: Vector3,
	planeXRaw: any,
	maxSpeedRaw: any,
	accelerationRaw: any,
	dampingRaw: any,
	dt: number
): (Vector3, number)
	local maxSpeed = sanitizeNumber(maxSpeedRaw, 0, 0, 10 ^ 5)
	local acceleration = sanitizeNumber(accelerationRaw, 0, 0, 10 ^ 5)
	local anchor = projectPosition(targetAnchor, planeXRaw)
	local offset = projectVector(anchor - currentPosition, planeXRaw)
	local distance = offset.Magnitude

	local desiredVelocity = ZERO_VECTOR
	if distance > 1e-4 and maxSpeed > 0 then
		local arrivalGain = math.max(1.25, acceleration / math.max(maxSpeed, 1))
		local desiredSpeed = math.min(maxSpeed, distance * arrivalGain)
		desiredVelocity = offset.Unit * desiredSpeed
	end

	local nextVelocity = BossServiceUtils.moveTowardsVector(currentVelocity, desiredVelocity, acceleration * dt)
	nextVelocity = dampVelocity(projectVector(nextVelocity, planeXRaw), dampingRaw, dt)
	if nextVelocity.Magnitude > maxSpeed and maxSpeed > 0 then
		nextVelocity = nextVelocity.Unit * maxSpeed
	end

	return nextVelocity, distance
end

local function buildDebugState(
	context: MotionRuntimeState,
	owner: string,
	velocity: Vector3,
	hoverAnchor: Vector3?,
	distanceToAnchor: number?,
	lockedChargeDirection: Vector3?,
	chargeTimeRemaining: number?,
	localPresentationOffset: Vector3?
): BossMotionState
	return {
		state = context.state,
		position = context.position,
		velocity = velocity,
		hoverAnchor = hoverAnchor,
		distanceToAnchor = distanceToAnchor,
		lockedChargeDirection = lockedChargeDirection,
		chargeTimeRemaining = chargeTimeRemaining,
		motionOwner = owner,
		localPresentationOffset = localPresentationOffset,
	}
end

local function createResult(
	context: MotionRuntimeState,
	owner: string,
	velocity: Vector3,
	facing: Vector3,
	finished: boolean,
	nextSuggestedState: string?,
	hoverAnchor: Vector3?,
	distanceToAnchor: number?,
	lockedChargeDirection: Vector3?,
	chargeTimeRemaining: number?,
	localPresentationOffset: Vector3?
): MotionSolveResult
	return {
		velocity = velocity,
		facing = facing,
		finished = finished,
		nextSuggestedState = nextSuggestedState,
		hoverAnchor = hoverAnchor,
		localPresentationOffset = localPresentationOffset,
		lockedChargeDirection = lockedChargeDirection,
		chargeTimeRemaining = chargeTimeRemaining,
		motionOwner = owner,
		debug = buildDebugState(
			context,
			owner,
			velocity,
			hoverAnchor,
			distanceToAnchor,
			lockedChargeDirection,
			chargeTimeRemaining,
			localPresentationOffset
		),
	}
end

local function computeHoverAnchor(
	targetPosition: Vector3,
	targetVelocity: Vector3,
	planeXRaw: any,
	sideSignRaw: any,
	heightRaw: any,
	sideOffsetRaw: any,
	leadMultiplierRaw: any,
	bobAmplitudeRaw: any,
	bobSpeedRaw: any,
	timeRaw: any,
	lateralBobScaleRaw: any?
): Vector3
	local sideSign = if sideSignRaw == -1 then -1 else 1
	local height = sanitizeNumber(heightRaw, 24, 0, 512)
	local sideOffset = sanitizeNumber(sideOffsetRaw, 14, 0, 256)
	local leadMultiplier = sanitizeNumber(leadMultiplierRaw, 0.32, 0, 4)
	local bobAmplitude = sanitizeNumber(bobAmplitudeRaw, 3, 0, 64)
	local bobSpeed = sanitizeNumber(bobSpeedRaw, 4, 0, 50)
	local time = sanitizeNumber(timeRaw, 0, 0, 10 ^ 6)
	local lateralBobScale = sanitizeNumber(lateralBobScaleRaw, 0.22, 0, 2)
	local maxLead = math.max(6, sideOffset * 1.15)
	local leadZ = math.clamp(targetVelocity.Z * leadMultiplier, -maxLead, maxLead)
	local bob = Vector3.new(
		0,
		math.sin(time * bobSpeed) * bobAmplitude,
		math.cos(time * bobSpeed * 0.5) * bobAmplitude * lateralBobScale
	)

	return projectPosition(targetPosition + Vector3.new(0, height, sideOffset * sideSign + leadZ) + bob, planeXRaw)
end

local function rotateFacingOnPlane(baseFacingRaw: any, sideSignRaw: any, angleRadians: number): Vector3
	local sideSign = if sideSignRaw == -1 then -1 else 1
	local baseFacing = if typeof(baseFacingRaw) == "Vector3" then baseFacingRaw else Vector3.new(0, 0, sideSign)
	local yzMagnitude = math.sqrt(baseFacing.Y * baseFacing.Y + baseFacing.Z * baseFacing.Z)
	local normalizedY = 0
	local normalizedZ = sideSign
	if yzMagnitude > 1e-4 then
		normalizedY = baseFacing.Y / yzMagnitude
		normalizedZ = baseFacing.Z / yzMagnitude
	end

	local cosine = math.cos(angleRadians)
	local sine = math.sin(angleRadians)
	return safeUnit(
		Vector3.new(0, normalizedY * cosine - normalizedZ * sine, normalizedY * sine + normalizedZ * cosine),
		Vector3.new(0, 0, sideSign)
	)
end

local function solveHoverMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	heightRaw: any,
	sideOffsetRaw: any,
	leadMultiplierRaw: any,
	bobAmplitudeRaw: any,
	bobSpeedRaw: any,
	maxSpeedRaw: any,
	accelerationRaw: any,
	dampingRaw: any,
	dt: number,
	owner: string,
	lateralBobScaleRaw: any?
): MotionSolveResult
	local targetPosition = if targetSnapshot ~= nil then targetSnapshot.position else nil
	if targetPosition == nil then
		return createResult(
			context,
			owner,
			dampVelocity(context.velocity, dampingRaw, dt),
			context.facing,
			false,
			nil,
			nil,
			nil,
			nil,
			nil,
			nil
		)
	end

	local hoverAnchor = computeHoverAnchor(
		targetPosition,
		resolveTargetVelocity(targetSnapshot),
		context.planeX,
		context.sideSign,
		heightRaw,
		sideOffsetRaw,
		leadMultiplierRaw,
		bobAmplitudeRaw,
		bobSpeedRaw,
		context.stateTime,
		lateralBobScaleRaw
	)
	local velocity, distanceToAnchor = solveAnchoredVelocity(
		context.position,
		context.velocity,
		hoverAnchor,
		context.planeX,
		maxSpeedRaw,
		accelerationRaw,
		dampingRaw,
		dt
	)
	local facing = resolveFacingTowardTarget(context.position, targetSnapshot, context.facing)
	local localPresentationOffset = Vector3.new(0, math.sin(context.stateTime * 2.8) * 0.12, 0)

	return createResult(
		context,
		owner,
		velocity,
		facing,
		false,
		nil,
		hoverAnchor,
		distanceToAnchor,
		nil,
		nil,
		localPresentationOffset
	)
end

local function solveLockedChargeMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	owner: string
): MotionSolveResult
	local chargeLock = context.lockedCharge
	local fallbackDirection = resolvePlaneFallback(context.sideSign)
	local lockedDirection = if chargeLock ~= nil then chargeLock.direction else fallbackDirection
	local lockedSpeed = if chargeLock ~= nil then chargeLock.speed else 0
	local lockedDuration = if chargeLock ~= nil then chargeLock.duration else 0
	local chargeTimeRemaining = math.max(0, lockedDuration - context.stateTime)
	local velocity = projectVector(lockedDirection * lockedSpeed, context.planeX)
	local facing =
		safeUnit(lockedDirection, resolveFacingTowardTarget(context.position, targetSnapshot, fallbackDirection))

	return createResult(
		context,
		owner,
		velocity,
		facing,
		context.stateTime >= lockedDuration,
		nil,
		nil,
		nil,
		lockedDirection,
		chargeTimeRemaining,
		nil
	)
end

function EyeOfCthulhuMotion.ComputeIntroSpawnPosition(
	targetPosition: Vector3,
	planeXRaw: any,
	sideSignRaw: any,
	heightRaw: any,
	distanceRaw: any
): Vector3
	local sideSign = if sideSignRaw == -1 then -1 else 1
	local height = sanitizeNumber(heightRaw, 50, 0, 512)
	local distance = sanitizeNumber(distanceRaw, 70, 8, 512)

	return projectPosition(targetPosition + Vector3.new(0, height, distance * sideSign), planeXRaw)
end

function EyeOfCthulhuMotion.CreateChargeLock(
	fromPosition: Vector3,
	targetPosition: Vector3?,
	targetVelocity: Vector3,
	planeXRaw: any,
	predictionTimeRaw: any,
	verticalBiasRaw: any,
	speedRaw: any,
	durationRaw: any,
	fallbackDirectionRaw: any?
): ChargeLock
	local fallbackDirection =
		resolvePlaneFallback(if typeof(fallbackDirectionRaw) == "number" then fallbackDirectionRaw else 1)
	local predictionTime = sanitizeNumber(predictionTimeRaw, 0.16, 0, 4)
	local verticalBias = sanitizeNumber(verticalBiasRaw, 0, -128, 128)
	local speed = sanitizeNumber(speedRaw, 0, 0, 10 ^ 5)
	local duration = sanitizeDuration(durationRaw, 0.5)

	local predictedPosition = nil :: Vector3?
	if targetPosition ~= nil then
		predictedPosition = projectPosition(
			targetPosition + targetVelocity * predictionTime + Vector3.new(0, verticalBias, 0),
			planeXRaw
		)
	end

	local direction = if predictedPosition ~= nil
		then safeUnit(projectVector(predictedPosition - fromPosition, planeXRaw), fallbackDirection)
		else fallbackDirection
	local destination = projectPosition(fromPosition + direction * speed * duration, planeXRaw)

	return {
		direction = direction,
		speed = speed,
		duration = duration,
		destination = destination,
		targetPosition = predictedPosition,
	}
end

function EyeOfCthulhuMotion.SolveSpawnIntroMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	local targetPosition = if targetSnapshot ~= nil then targetSnapshot.position else nil
	if targetPosition == nil then
		return createResult(
			context,
			"SpawnIntro",
			dampVelocity(context.velocity, config.phase1HoverDamping, dt),
			context.facing,
			true,
			nil,
			nil,
			nil,
			nil,
			nil,
			nil
		)
	end

	local introDuration = sanitizeDuration(config.introDuration, 2.4)
	local introProgress = math.clamp(context.stateTime / introDuration, 0, 1)
	local descentAlpha = 1 - (1 - introProgress) ^ 3
	local highAnchor = projectPosition(
		targetPosition + Vector3.new(0, config.introHeight * 0.82, config.introDistance * context.sideSign * 0.38),
		context.planeX
	)
	local hoverAnchor = computeHoverAnchor(
		targetPosition,
		resolveTargetVelocity(targetSnapshot),
		context.planeX,
		context.sideSign,
		config.phase1HoverHeight,
		config.phase1SideOffset,
		config.phase1LeadMultiplier,
		config.phase1BobAmplitude * 0.45,
		config.phase1BobSpeed * 0.72,
		context.stateTime,
		0.18
	)
	local desiredAnchor = highAnchor:Lerp(hoverAnchor, descentAlpha)
	local velocity, distanceToAnchor = solveAnchoredVelocity(
		context.position,
		context.velocity,
		desiredAnchor,
		context.planeX,
		config.phase1HoverSpeed * 1.05,
		config.phase1HoverAcceleration,
		config.phase1HoverDamping,
		dt
	)
	local facing = resolveFacingTowardTarget(context.position, targetSnapshot, context.facing)
	local localPresentationOffset = Vector3.new(0, (1 - descentAlpha) * 0.9, 0)

	return createResult(
		context,
		"SpawnIntro",
		velocity,
		facing,
		context.stateTime >= introDuration,
		"Phase1Hover",
		desiredAnchor,
		distanceToAnchor,
		nil,
		nil,
		localPresentationOffset
	)
end

function EyeOfCthulhuMotion.SolvePhase1HoverMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	return solveHoverMotion(
		context,
		targetSnapshot,
		config.phase1HoverHeight,
		config.phase1SideOffset,
		config.phase1LeadMultiplier,
		config.phase1BobAmplitude,
		config.phase1BobSpeed,
		config.phase1HoverSpeed,
		config.phase1HoverAcceleration,
		config.phase1HoverDamping,
		dt,
		"Phase1Hover",
		0.18
	)
end

function EyeOfCthulhuMotion.SolveServantBurstMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	return solveHoverMotion(
		context,
		targetSnapshot,
		config.phase1HoverHeight,
		config.phase1SideOffset * 0.92,
		config.phase1LeadMultiplier * 0.6,
		config.phase1BobAmplitude * 0.35,
		config.phase1BobSpeed * 0.75,
		config.phase1HoverSpeed * 0.6,
		config.phase1HoverAcceleration * 0.72,
		config.phase1HoverDamping + 0.65,
		dt,
		"Phase1ServantBurst",
		0.08
	)
end

function EyeOfCthulhuMotion.SolveChargeWindupMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	local chargeLock = context.lockedCharge
	local lockedDirection = if chargeLock ~= nil then chargeLock.direction else resolvePlaneFallback(context.sideSign)
	local velocity = BossServiceUtils.moveTowardsVector(
		context.velocity,
		ZERO_VECTOR,
		sanitizeNumber(config.brakeAcceleration, 160, 0, 10 ^ 5) * dt
	)
	velocity = dampVelocity(velocity, config.brakeDamping, dt)
	local facing = resolveFacingTowardTarget(context.position, targetSnapshot, lockedDirection)
	local windupDuration = sanitizeDuration(config.duration, 0.35)
	local anticipationAlpha = math.clamp(context.stateTime / windupDuration, 0, 1)
	local localPresentationOffset = lockedDirection * (-0.65 * anticipationAlpha)

	return createResult(
		context,
		"ChargeWindup",
		velocity,
		facing,
		context.stateTime >= windupDuration,
		if context.state == "Phase2ChargeWindup" then "Phase2Charge" else "Phase1Charge",
		nil,
		nil,
		lockedDirection,
		if chargeLock ~= nil then chargeLock.duration else nil,
		localPresentationOffset
	)
end

function EyeOfCthulhuMotion.SolveCommittedChargeMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	_config: any,
	_dt: number
): MotionSolveResult
	return solveLockedChargeMotion(context, targetSnapshot, "CommittedCharge")
end

function EyeOfCthulhuMotion.SolveRecoveryMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	local chargeLock = context.lockedCharge
	local recoverySpeed = sanitizeNumber(config.speed, 0, 0, 10 ^ 5)
	local recoveryAcceleration = sanitizeNumber(config.acceleration, 0, 0, 10 ^ 5)
	local recoveryDamping = sanitizeNumber(config.damping, 0.9, 0, 50)
	local lockedDirection = if chargeLock ~= nil then chargeLock.direction else resolvePlaneFallback(context.sideSign)
	local desiredVelocity = lockedDirection * recoverySpeed
	local velocity = BossServiceUtils.moveTowardsVector(context.velocity, desiredVelocity, recoveryAcceleration * dt)
	velocity = dampVelocity(velocity, recoveryDamping, dt)
	local facing = resolveFacingTowardTarget(context.position, targetSnapshot, lockedDirection)
	local recoveryDuration = sanitizeDuration(config.duration, 0.2)
	local localPresentationOffset = lockedDirection * math.max(0, 0.28 - context.stateTime * 0.4)

	return createResult(
		context,
		"Recovery",
		velocity,
		facing,
		context.stateTime >= recoveryDuration,
		nil,
		nil,
		nil,
		if chargeLock ~= nil then chargeLock.direction else nil,
		nil,
		localPresentationOffset
	)
end

function EyeOfCthulhuMotion.SolveTransformMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	_dt: number
): MotionSolveResult
	local transformDuration = sanitizeDuration(config.transformDuration, 2.25)
	local progress = math.clamp(context.stateTime / transformDuration, 0, 1)
	local spinAngle = progress * math.pi * 2 * sanitizeNumber(config.transformSpinTurns, 8, 0, 64)
	local facing = rotateFacingOnPlane(context.transformBaseFacing, context.sideSign, spinAngle)
	local localPresentationOffset =
		Vector3.new(0, math.sin(progress * math.pi) * sanitizeNumber(config.transformPauseLift, 8, 0, 128) * 0.35, 0)

	if targetSnapshot ~= nil and targetSnapshot.position ~= nil and progress <= 0.08 then
		facing = resolveFacingTowardTarget(context.position, targetSnapshot, facing)
	end

	return createResult(
		context,
		"Transform",
		ZERO_VECTOR,
		facing,
		context.stateTime >= transformDuration,
		"Phase2HoverIdle",
		nil,
		nil,
		nil,
		nil,
		localPresentationOffset
	)
end

function EyeOfCthulhuMotion.SolvePhase2HoverIdleMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	return solveHoverMotion(
		context,
		targetSnapshot,
		config.phase2HoverHeight,
		config.phase2SideOffset,
		config.phase2LeadMultiplier,
		config.phase2BobAmplitude,
		config.phase2BobSpeed,
		config.phase2HoverSpeed,
		config.phase2HoverAcceleration,
		config.phase2HoverDamping,
		dt,
		"Phase2HoverIdle",
		0.12
	)
end

function EyeOfCthulhuMotion.SolvePhase2HoverMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	return EyeOfCthulhuMotion.SolvePhase2HoverIdleMotion(context, targetSnapshot, config, dt)
end

function EyeOfCthulhuMotion.SolvePhase2ChargeMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	_config: any,
	_dt: number
): MotionSolveResult
	return solveLockedChargeMotion(context, targetSnapshot, "Phase2Charge")
end

function EyeOfCthulhuMotion.SolveDespawnMotion(
	context: MotionRuntimeState,
	targetSnapshot: MotionTargetSnapshot?,
	config: any,
	dt: number
): MotionSolveResult
	local riseSpeed = sanitizeNumber(config.despawnRiseSpeed, 120, 0, 10 ^ 5)
	local forwardSpeed = sanitizeNumber(config.despawnForwardSpeed, 42, 0, 10 ^ 5)
	local acceleration = sanitizeNumber(config.despawnAcceleration, 240, 0, 10 ^ 5)
	local awayDirection = Vector3.new(0, 0, if context.sideSign >= 0 then 1 else -1)
	if targetSnapshot ~= nil and targetSnapshot.position ~= nil then
		local planarAway = projectVector(context.position - targetSnapshot.position, context.planeX)
		awayDirection = safeUnit(Vector3.new(0, 0, planarAway.Z), awayDirection)
	end

	local desiredVelocity = Vector3.new(0, riseSpeed, awayDirection.Z * forwardSpeed)
	local velocity = BossServiceUtils.moveTowardsVector(context.velocity, desiredVelocity, acceleration * dt)
	local facing = safeUnit(if velocity.Magnitude > 1e-4 then velocity else desiredVelocity, awayDirection)

	return createResult(
		context,
		"Despawn",
		velocity,
		facing,
		context.stateTime >= 2.8,
		nil,
		nil,
		nil,
		nil,
		nil,
		Vector3.new(0, math.min(context.stateTime * 0.35, 1.5), 0)
	)
end

function EyeOfCthulhuMotion.ComputeRapidChainSpeed(healthRatioRaw: any, baseSpeedRaw: any, topSpeedRaw: any): number
	local healthRatio = math.clamp(sanitizeNumber(healthRatioRaw, 1, 0, 1), 0, 1)
	local baseSpeed = sanitizeNumber(baseSpeedRaw, 110, 0, 10 ^ 5)
	local topSpeed = sanitizeNumber(topSpeedRaw, 154, baseSpeed, 10 ^ 5)
	local pressureAlpha = 1 - healthRatio
	return baseSpeed + (topSpeed - baseSpeed) * pressureAlpha
end

function EyeOfCthulhuMotion.ComputePupilOffset(
	rootPosition: Vector3,
	targetPosition: Vector3?,
	maxOffsetStudsRaw: any
): Vector3
	local maxOffsetStuds = sanitizeNumber(maxOffsetStudsRaw, 0.85, 0, 8)
	if targetPosition == nil then
		return ZERO_VECTOR
	end

	local lookDelta = targetPosition - rootPosition
	local planar = Vector3.new(0, lookDelta.Y, lookDelta.Z)
	if planar.Magnitude <= 1e-4 then
		return ZERO_VECTOR
	end

	local lookUnit = planar.Unit
	return Vector3.new(0, lookUnit.Y * maxOffsetStuds, lookUnit.Z * maxOffsetStuds)
end

function EyeOfCthulhuMotion.ResolveAggressiveDuration(durationRaw: any, aggressivenessRaw: any): number
	local duration = sanitizeDuration(durationRaw, 0.5)
	local aggressiveness = sanitizeNumber(aggressivenessRaw, 1, 0.1, 3)
	return duration / aggressiveness
end

function EyeOfCthulhuMotion.ResolveAggressiveSpeed(speedRaw: any, aggressivenessRaw: any): number
	local speed = sanitizeNumber(speedRaw, 0, 0, 10 ^ 5)
	local aggressiveness = sanitizeNumber(aggressivenessRaw, 1, 0.1, 3)
	return speed * aggressiveness
end

EyeOfCthulhuMotion.computeIntroSpawnPosition = EyeOfCthulhuMotion.ComputeIntroSpawnPosition
EyeOfCthulhuMotion.createChargeLock = EyeOfCthulhuMotion.CreateChargeLock
EyeOfCthulhuMotion.solveSpawnIntroMotion = EyeOfCthulhuMotion.SolveSpawnIntroMotion
EyeOfCthulhuMotion.solvePhase1HoverMotion = EyeOfCthulhuMotion.SolvePhase1HoverMotion
EyeOfCthulhuMotion.solveServantBurstMotion = EyeOfCthulhuMotion.SolveServantBurstMotion
EyeOfCthulhuMotion.solveChargeWindupMotion = EyeOfCthulhuMotion.SolveChargeWindupMotion
EyeOfCthulhuMotion.solveCommittedChargeMotion = EyeOfCthulhuMotion.SolveCommittedChargeMotion
EyeOfCthulhuMotion.solveRecoveryMotion = EyeOfCthulhuMotion.SolveRecoveryMotion
EyeOfCthulhuMotion.solveTransformMotion = EyeOfCthulhuMotion.SolveTransformMotion
EyeOfCthulhuMotion.solvePhase2HoverIdleMotion = EyeOfCthulhuMotion.SolvePhase2HoverIdleMotion
EyeOfCthulhuMotion.solvePhase2HoverMotion = EyeOfCthulhuMotion.SolvePhase2HoverMotion
EyeOfCthulhuMotion.solvePhase2ChargeMotion = EyeOfCthulhuMotion.SolvePhase2ChargeMotion
EyeOfCthulhuMotion.solveDespawnMotion = EyeOfCthulhuMotion.SolveDespawnMotion
EyeOfCthulhuMotion.computeRapidChainSpeed = EyeOfCthulhuMotion.ComputeRapidChainSpeed
EyeOfCthulhuMotion.computePupilOffset = EyeOfCthulhuMotion.ComputePupilOffset
EyeOfCthulhuMotion.resolveAggressiveDuration = EyeOfCthulhuMotion.ResolveAggressiveDuration
EyeOfCthulhuMotion.resolveAggressiveSpeed = EyeOfCthulhuMotion.ResolveAggressiveSpeed

return EyeOfCthulhuMotion
