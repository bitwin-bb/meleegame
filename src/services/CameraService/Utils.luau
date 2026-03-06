--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
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

function CameraServiceUtils.isCameraMode(mode: any): boolean
	return mode == "SideView" or mode == "FirstPerson" or mode == "Isometric"
end

function CameraServiceUtils.normalizeCameraMode(mode: any): CameraMode
	if mode == "SideView" and not SIDE_VIEW_ENABLED then
		return DEFAULT_CAMERA_MODE
	end

	if CameraServiceUtils.isCameraMode(mode) then
		return mode :: CameraMode
	end

	return DEFAULT_CAMERA_MODE
end

function CameraServiceUtils.sanitizeSpringOptions(
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
	local defaultCameraSpring = CameraServiceUtils.sanitizeSpringOptions((defaultConfig :: any).cameraSpring, nil)
	local defaultFovSpring = CameraServiceUtils.sanitizeSpringOptions((defaultConfig :: any).fovSpring, nil)

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
		cameraSpring = CameraServiceUtils.sanitizeSpringOptions((source :: any).cameraSpring, defaultCameraSpring),
		fovSpring = CameraServiceUtils.sanitizeSpringOptions((source :: any).fovSpring, defaultFovSpring),
	}
end

local DEFAULT_SIDE_VIEW_CONFIG: SideViewConfig =
	sanitizeSideViewConfigWithFallback(RAW_DEFAULT_SIDE_VIEW_CONFIG, RAW_DEFAULT_SIDE_VIEW_CONFIG)

CameraServiceUtils.DEFAULT_CAMERA_MODE = DEFAULT_CAMERA_MODE
CameraServiceUtils.DEFAULT_SIDE_VIEW_CONFIG = DEFAULT_SIDE_VIEW_CONFIG

function CameraServiceUtils.sanitizeSideViewConfig(config: any): SideViewConfig
	return sanitizeSideViewConfigWithFallback(config, DEFAULT_SIDE_VIEW_CONFIG)
end

function CameraServiceUtils.mergeSideViewConfig(base: SideViewConfig?, incoming: SideViewConfig?): SideViewConfig
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
	local mergedAny = merged :: any

	mergedAny.cameraSpring = CameraServiceUtils.sanitizeSpringOptions(incomingCameraSpring, baseCameraSpring)
	mergedAny.fovSpring = CameraServiceUtils.sanitizeSpringOptions(incomingFovSpring, baseFovSpring)

	return CameraServiceUtils.sanitizeSideViewConfig(merged)
end

function CameraServiceUtils.createDefaultState(): CameraState
	return {
		mode = DEFAULT_CAMERA_MODE,
		sideViewConfig = CameraServiceUtils.sanitizeSideViewConfig(DEFAULT_SIDE_VIEW_CONFIG),
	}
end

function CameraServiceUtils.createCameraState(mode: any, sideViewConfig: any): CameraState
	return {
		mode = CameraServiceUtils.normalizeCameraMode(mode),
		sideViewConfig = CameraServiceUtils.sanitizeSideViewConfig(sideViewConfig),
	}
end

function CameraServiceUtils.resolveCharacterTarget(character: Model?): BasePart?
	if not character then
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

return CameraServiceUtils
