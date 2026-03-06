--!strict

local CameraShakeGate = {}

export type GateOptions = {
	maxTranslation: number?,
	maxRotationRadians: number?,
	frameTranslationBudget: number?,
	frameRotationBudget: number?,
}

local FRAME_BUCKET_HZ = 240
local DEFAULT_MAX_TRANSLATION = 0.65
local DEFAULT_MAX_ROTATION_RADIANS = math.rad(12)
local DEFAULT_FRAME_TRANSLATION_BUDGET = 0.78
local DEFAULT_FRAME_ROTATION_BUDGET = math.rad(14)

local activeFrameBucket = -1
local usedFrameTranslation = 0
local usedFrameRotation = 0

local function sanitizeNonNegativeNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.max(0, valueRaw)
end

local function clampVectorMagnitude(vector: Vector3, maxMagnitude: number): Vector3
	if maxMagnitude <= 0 then
		return Vector3.zero
	end

	local magnitude = vector.Magnitude
	if magnitude <= maxMagnitude then
		return vector
	end
	if magnitude <= 0 then
		return Vector3.zero
	end
	return vector * (maxMagnitude / magnitude)
end

local function getFrameBucket(now: number): number
	return math.floor(now * FRAME_BUCKET_HZ + 0.5)
end

function CameraShakeGate.gateShakeOffset(shakeOffsetRaw: any, optionsRaw: GateOptions?): CFrame
	if typeof(shakeOffsetRaw) ~= "CFrame" then
		return CFrame.new()
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else nil

	local maxTranslation =
		sanitizeNonNegativeNumber(if options ~= nil then options.maxTranslation else nil, DEFAULT_MAX_TRANSLATION)
	local maxRotation = sanitizeNonNegativeNumber(
		if options ~= nil then options.maxRotationRadians else nil,
		DEFAULT_MAX_ROTATION_RADIANS
	)
	local frameTranslationBudget = sanitizeNonNegativeNumber(
		if options ~= nil then options.frameTranslationBudget else nil,
		DEFAULT_FRAME_TRANSLATION_BUDGET
	)
	local frameRotationBudget = sanitizeNonNegativeNumber(
		if options ~= nil then options.frameRotationBudget else nil,
		DEFAULT_FRAME_ROTATION_BUDGET
	)

	local frameBucket = getFrameBucket(os.clock())
	if frameBucket ~= activeFrameBucket then
		activeFrameBucket = frameBucket
		usedFrameTranslation = 0
		usedFrameRotation = 0
	end

	local shakeOffset = shakeOffsetRaw :: CFrame
	local translation = clampVectorMagnitude(shakeOffset.Position, maxTranslation)
	local rx, ry, rz = shakeOffset:ToOrientation()
	local rotation = clampVectorMagnitude(Vector3.new(rx, ry, rz), maxRotation)

	local remainingTranslation = math.max(0, frameTranslationBudget - usedFrameTranslation)
	local remainingRotation = math.max(0, frameRotationBudget - usedFrameRotation)

	translation = clampVectorMagnitude(translation, remainingTranslation)
	rotation = clampVectorMagnitude(rotation, remainingRotation)

	usedFrameTranslation += translation.Magnitude
	usedFrameRotation += rotation.Magnitude

	if translation.Magnitude <= 0 and rotation.Magnitude <= 0 then
		return CFrame.new()
	end

	return CFrame.new(translation.X, translation.Y, translation.Z)
		* CFrame.fromOrientation(rotation.X, rotation.Y, rotation.Z)
end

function CameraShakeGate.reset()
	activeFrameBucket = -1
	usedFrameTranslation = 0
	usedFrameRotation = 0
end

return CameraShakeGate
