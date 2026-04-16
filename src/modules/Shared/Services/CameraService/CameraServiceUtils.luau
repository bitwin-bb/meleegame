--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local CameraServiceUtils = {}

export type CameraMode = "SideView" | "FirstPerson" | "Isometric"

export type SideViewSpringOptions = {
	damping: number?,
	frequency: number?,
	mass: number?,
	tension: number?,
	friction: number?,
	position: number?,
	velocity: number?,
	impulse: number?,
	restingVelocity: number?,
	restingPosition: number?,
}

export type SideViewPredictConfig = {
	enabled: boolean?,
	leadTime: number?,
	maxLeadTime: number?,
	minimumSpeed: number?,
	maximumDistance: number?,
	derivedVelocityWeight: number?,
}

export type SideViewConfig = {
	distance: number?,
	height: number?,
	lookHeight: number?,
	sideSign: number?,
	fieldOfView: number?,
	movementBackAmount: number?,
	movementSpeedForMaxBack: number?,
	movementBackSign: number?,
	mouseInfluenceX: number?,
	mouseInfluenceY: number?,
	cameraSpring: SideViewSpringOptions?,
	fovSpring: SideViewSpringOptions?,
	predict: SideViewPredictConfig?,
}

export type CameraState = {
	mode: CameraMode,
	sideViewConfig: SideViewConfig,
}

local SPRING_OPTION_KEYS = {
	"damping",
	"frequency",
	"mass",
	"tension",
	"friction",
	"position",
	"velocity",
	"impulse",
	"restingVelocity",
	"restingPosition",
}

local function getCameraSettingBoolean(settingName: string, fallback: boolean): boolean
	local cameraSettings = Configs.cameraSettings
	if typeof(cameraSettings) ~= "table" then
		return fallback
	end

	local value = (cameraSettings :: any)[settingName]
	if typeof(value) == "boolean" then
		return value
	end

	return fallback
end

local SIDE_VIEW_ENABLED = getCameraSettingBoolean("sideViewEnabled", true)
local DEFAULT_CAMERA_MODE: CameraMode = if SIDE_VIEW_ENABLED then "SideView" else "FirstPerson"
local RAW_DEFAULT_SIDE_VIEW_CONFIG = Configs.cameraData

local function clampNumber(value: any, min: number, max: number, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	if value ~= value then
		return fallback
	end

	return math.clamp(value, min, max)
end

local function cloneSpringOptions(options: SideViewSpringOptions?): SideViewSpringOptions?
	if not options then
		return nil
	end

	local clone: SideViewSpringOptions = {}
	for _, key in SPRING_OPTION_KEYS do
		local value = (options :: any)[key]
		if typeof(value) == "number" then
			(clone :: any)[key] = value
		end
	end

	if next(clone) == nil then
		return nil
	end

	return clone
end

local function clonePredictConfig(config: SideViewPredictConfig?): SideViewPredictConfig?
	if not config then
		return nil
	end

	return {
		enabled = config.enabled,
		leadTime = config.leadTime,
		maxLeadTime = config.maxLeadTime,
		minimumSpeed = config.minimumSpeed,
		maximumDistance = config.maximumDistance,
		derivedVelocityWeight = config.derivedVelocityWeight,
	}
end

function CameraServiceUtils.IsCameraMode(mode: any): boolean
	return mode == "SideView" or mode == "FirstPerson" or mode == "Isometric"
end

function CameraServiceUtils.NormalizeCameraMode(mode: any): CameraMode
	if mode == "SideView" and not SIDE_VIEW_ENABLED then
		return DEFAULT_CAMERA_MODE
	end

	if CameraServiceUtils.IsCameraMode(mode) then
		return mode :: CameraMode
	end

	return DEFAULT_CAMERA_MODE
end

function CameraServiceUtils.SanitizeSpringOptions(
	options: any,
	fallback: SideViewSpringOptions?
): SideViewSpringOptions?
	local defaultSpring = cloneSpringOptions(fallback)
	if typeof(options) ~= "table" then
		return defaultSpring
	end

	local source = options :: SideViewSpringOptions
	local spring: SideViewSpringOptions = defaultSpring or {}

	for _, key in SPRING_OPTION_KEYS do
		local value = (source :: any)[key]
		if typeof(value) == "number" then
			(spring :: any)[key] = value
		end
	end

	if next(spring) == nil then
		return nil
	end

	return spring
end

function CameraServiceUtils.SanitizePredictConfig(
	configRaw: any,
	fallbackRaw: SideViewPredictConfig?
): SideViewPredictConfig?
	local fallback = clonePredictConfig(fallbackRaw) or clonePredictConfig((RAW_DEFAULT_SIDE_VIEW_CONFIG :: any).predict)
	local source = if typeof(configRaw) == "table" then configRaw else {}
	if fallback == nil and typeof(configRaw) ~= "table" then
		return nil
	end

	local defaultEnabled = if fallback ~= nil and typeof(fallback.enabled) == "boolean" then fallback.enabled else false
	local defaultLeadTime = if fallback ~= nil then clampNumber(fallback.leadTime, 0, 1, 0.08) else 0.08
	local leadTime = clampNumber((source :: any).leadTime, 0, 1, defaultLeadTime)
	local defaultMaxLeadTime = if fallback ~= nil then clampNumber(fallback.maxLeadTime, leadTime, 1, 0.18) else 0.18
	local maxLeadTime = clampNumber((source :: any).maxLeadTime, leadTime, 1, defaultMaxLeadTime)

	return {
		enabled = if typeof((source :: any).enabled) == "boolean" then (source :: any).enabled else defaultEnabled,
		leadTime = leadTime,
		maxLeadTime = maxLeadTime,
		minimumSpeed = if fallback ~= nil
			then clampNumber((source :: any).minimumSpeed, 0, 1024, clampNumber(fallback.minimumSpeed, 0, 1024, 2))
			else clampNumber((source :: any).minimumSpeed, 0, 1024, 2),
		maximumDistance = if fallback ~= nil
			then clampNumber(
				(source :: any).maximumDistance,
				0,
				4096,
				clampNumber(fallback.maximumDistance, 0, 4096, 18)
			)
			else clampNumber((source :: any).maximumDistance, 0, 4096, 18),
		derivedVelocityWeight = if fallback ~= nil
			then clampNumber(
				(source :: any).derivedVelocityWeight,
				0,
				1,
				clampNumber(fallback.derivedVelocityWeight, 0, 1, 0.35)
			)
			else clampNumber((source :: any).derivedVelocityWeight, 0, 1, 0.35),
	}
end

local function sanitizeSideViewConfigWithFallback(config: any, fallbackConfig: any): SideViewConfig
	local source = if typeof(config) == "table" then config else {}
	local defaultConfig = if typeof(fallbackConfig) == "table" then fallbackConfig else {}
	local defaultDistance = clampNumber((defaultConfig :: any).distance, 4, 200, 38)
	local defaultHeight = clampNumber((defaultConfig :: any).height, -100, 100, 8)
	local defaultLookHeight = clampNumber((defaultConfig :: any).lookHeight, -100, 100, 3)
	local defaultSideSign = math.sign(clampNumber((defaultConfig :: any).sideSign, -1, 1, 1))
	if defaultSideSign == 0 then
		defaultSideSign = 1
	end
	local defaultFieldOfView = clampNumber((defaultConfig :: any).fieldOfView, 20, 100, 60)
	local defaultMovementBackAmount = clampNumber((defaultConfig :: any).movementBackAmount, 0, 30, 8)
	local defaultMovementSpeedForMaxBack = clampNumber((defaultConfig :: any).movementSpeedForMaxBack, 0.1, 200, 16)
	local defaultMovementBackSign = math.sign(clampNumber((defaultConfig :: any).movementBackSign, -1, 1, 1))
	if defaultMovementBackSign == 0 then
		defaultMovementBackSign = 1
	end
	local defaultMouseInfluenceX = clampNumber((defaultConfig :: any).mouseInfluenceX, 0, 25, 1.4)
	local defaultMouseInfluenceY = clampNumber((defaultConfig :: any).mouseInfluenceY, 0, 25, 1.4)
	local defaultCameraSpring = CameraServiceUtils.SanitizeSpringOptions((defaultConfig :: any).cameraSpring, nil)
	local defaultFovSpring = CameraServiceUtils.SanitizeSpringOptions((defaultConfig :: any).fovSpring, nil)
	local defaultPredict = CameraServiceUtils.SanitizePredictConfig((defaultConfig :: any).predict, nil)

	local sideSign = math.sign(clampNumber((source :: any).sideSign, -1, 1, defaultSideSign))
	if sideSign == 0 then
		sideSign = 1
	end
	local movementBackSign = math.sign(clampNumber((source :: any).movementBackSign, -1, 1, defaultMovementBackSign))
	if movementBackSign == 0 then
		movementBackSign = 1
	end

	return {
		distance = clampNumber((source :: any).distance, 4, 200, defaultDistance),
		height = clampNumber((source :: any).height, -100, 100, defaultHeight),
		lookHeight = clampNumber((source :: any).lookHeight, -100, 100, defaultLookHeight),
		sideSign = sideSign,
		fieldOfView = clampNumber((source :: any).fieldOfView, 20, 100, defaultFieldOfView),
		movementBackAmount = clampNumber((source :: any).movementBackAmount, 0, 30, defaultMovementBackAmount),
		movementSpeedForMaxBack = clampNumber(
			(source :: any).movementSpeedForMaxBack,
			0.1,
			200,
			defaultMovementSpeedForMaxBack
		),
		movementBackSign = movementBackSign,
		mouseInfluenceX = clampNumber((source :: any).mouseInfluenceX, 0, 25, defaultMouseInfluenceX),
		mouseInfluenceY = clampNumber((source :: any).mouseInfluenceY, 0, 25, defaultMouseInfluenceY),
		cameraSpring = CameraServiceUtils.SanitizeSpringOptions((source :: any).cameraSpring, defaultCameraSpring),
		fovSpring = CameraServiceUtils.SanitizeSpringOptions((source :: any).fovSpring, defaultFovSpring),
		predict = CameraServiceUtils.SanitizePredictConfig((source :: any).predict, defaultPredict),
	}
end

local DEFAULT_SIDE_VIEW_CONFIG: SideViewConfig =
	sanitizeSideViewConfigWithFallback(RAW_DEFAULT_SIDE_VIEW_CONFIG, RAW_DEFAULT_SIDE_VIEW_CONFIG)

CameraServiceUtils.DEFAULT_CAMERA_MODE = DEFAULT_CAMERA_MODE
CameraServiceUtils.DEFAULT_SIDE_VIEW_CONFIG = DEFAULT_SIDE_VIEW_CONFIG

function CameraServiceUtils.SanitizeSideViewConfig(config: any): SideViewConfig
	return sanitizeSideViewConfigWithFallback(config, DEFAULT_SIDE_VIEW_CONFIG)
end

function CameraServiceUtils.MergeSideViewConfig(base: SideViewConfig?, incoming: SideViewConfig?): SideViewConfig
	local merged = {}

	if base then
		for key, value in base do
			(merged :: any)[key] = value
		end
	end

	if incoming then
		for key, value in incoming do
			(merged :: any)[key] = value
		end
	end

	local baseCameraSpring = if base then base.cameraSpring else nil
	local incomingCameraSpring = if incoming then incoming.cameraSpring else nil
	local baseFovSpring = if base then base.fovSpring else nil
	local incomingFovSpring = if incoming then incoming.fovSpring else nil
	local basePredict = if base then base.predict else nil
	local incomingPredict = if incoming then incoming.predict else nil
	local mergedAny = merged :: any

	mergedAny.cameraSpring = CameraServiceUtils.SanitizeSpringOptions(incomingCameraSpring, baseCameraSpring)
	mergedAny.fovSpring = CameraServiceUtils.SanitizeSpringOptions(incomingFovSpring, baseFovSpring)
	mergedAny.predict = CameraServiceUtils.SanitizePredictConfig(incomingPredict, basePredict)

	return CameraServiceUtils.SanitizeSideViewConfig(merged)
end

function CameraServiceUtils.CreateDefaultState(): CameraState
	return {
		mode = DEFAULT_CAMERA_MODE,
		sideViewConfig = CameraServiceUtils.SanitizeSideViewConfig(DEFAULT_SIDE_VIEW_CONFIG),
	}
end

function CameraServiceUtils.CreateCameraState(mode: any, sideViewConfig: any): CameraState
	return {
		mode = CameraServiceUtils.NormalizeCameraMode(mode),
		sideViewConfig = CameraServiceUtils.SanitizeSideViewConfig(sideViewConfig),
	}
end

function CameraServiceUtils.ResolveCharacterTarget(character: Model?): BasePart?
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

CameraServiceUtils.isCameraMode = CameraServiceUtils.IsCameraMode
CameraServiceUtils.normalizeCameraMode = CameraServiceUtils.NormalizeCameraMode
CameraServiceUtils.sanitizeSpringOptions = CameraServiceUtils.SanitizeSpringOptions
CameraServiceUtils.sanitizePredictConfig = CameraServiceUtils.SanitizePredictConfig
CameraServiceUtils.sanitizeSideViewConfig = CameraServiceUtils.SanitizeSideViewConfig
CameraServiceUtils.mergeSideViewConfig = CameraServiceUtils.MergeSideViewConfig
CameraServiceUtils.createDefaultState = CameraServiceUtils.CreateDefaultState
CameraServiceUtils.createCameraState = CameraServiceUtils.CreateCameraState
CameraServiceUtils.resolveCharacterTarget = CameraServiceUtils.ResolveCharacterTarget

return CameraServiceUtils
