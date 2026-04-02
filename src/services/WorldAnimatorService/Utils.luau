--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local Ease = require(ReplicatedStorage.Shared.Modules.Math.Ease)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)

local WorldAnimatorServiceUtils = {}

export type ChunkAnimationType = "rise" | "fall" | "fade" | "riseFade" | "fallFade"
export type ChunkAnimationEasing = "linear" | "sine" | "quadratic"

export type ChunkAnimatorSettings = {
	enabled: boolean,
	duration: number,
	animationType: ChunkAnimationType,
	easing: ChunkAnimationEasing,
	verticalOffset: number,
	transparencyRelativeToChunkPosition: boolean,
	minPlayerDistanceToAnimate: number,
	maxConcurrentAnimations: number,
	animateExistingChunks: boolean,
	maxAnimatedPartsPerChunk: number,
}

local DEFAULT_SETTINGS: ChunkAnimatorSettings = {
	enabled = true,
	duration = 0.55,
	animationType = "riseFade",
	easing = "sine",
	verticalOffset = 14,
	transparencyRelativeToChunkPosition = false,
	minPlayerDistanceToAnimate = 16,
	maxConcurrentAnimations = 8,
	animateExistingChunks = true,
	maxAnimatedPartsPerChunk = 100000,
}

local WORLD_FOLDER_NAME = "WorldGeneration"
local CHUNKS_FOLDER_NAME = "Chunks"

WorldAnimatorServiceUtils.DEFAULT_SETTINGS = DEFAULT_SETTINGS
WorldAnimatorServiceUtils.WORLD_FOLDER_NAME = WORLD_FOLDER_NAME
WorldAnimatorServiceUtils.CHUNKS_FOLDER_NAME = CHUNKS_FOLDER_NAME

local function clampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function clampInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	return math.floor(clampNumber(valueRaw, minimum, maximum, fallback))
end

function WorldAnimatorServiceUtils.normalizeAnimationType(valueRaw: any, fallback: ChunkAnimationType?): ChunkAnimationType
	if valueRaw == "rise" or valueRaw == "fall" or valueRaw == "fade" or valueRaw == "riseFade" or valueRaw == "fallFade" then
		return valueRaw
	end
	return (fallback or DEFAULT_SETTINGS.animationType) :: ChunkAnimationType
end

function WorldAnimatorServiceUtils.normalizeEasing(valueRaw: any, fallback: ChunkAnimationEasing?): ChunkAnimationEasing
	if valueRaw == "linear" or valueRaw == "sine" or valueRaw == "quadratic" then
		return valueRaw
	end
	return (fallback or DEFAULT_SETTINGS.easing) :: ChunkAnimationEasing
end

function WorldAnimatorServiceUtils.sanitizeSettings(
	settingsRaw: any,
	fallbackRaw: ChunkAnimatorSettings?
): ChunkAnimatorSettings
	local fallback = fallbackRaw or DEFAULT_SETTINGS
	local settings = if typeof(settingsRaw) == "table" then settingsRaw else {}

	return {
		enabled = if typeof((settings :: any).enabled) == "boolean" then (settings :: any).enabled else fallback.enabled,
		duration = clampNumber((settings :: any).duration, 0.05, 8, fallback.duration),
		animationType = WorldAnimatorServiceUtils.normalizeAnimationType((settings :: any).animationType, fallback.animationType),
		easing = WorldAnimatorServiceUtils.normalizeEasing((settings :: any).easing, fallback.easing),
		verticalOffset = clampNumber((settings :: any).verticalOffset, 0, 256, fallback.verticalOffset),
		transparencyRelativeToChunkPosition = if typeof((settings :: any).transparencyRelativeToChunkPosition) == "boolean"
			then (settings :: any).transparencyRelativeToChunkPosition
			else fallback.transparencyRelativeToChunkPosition,
		minPlayerDistanceToAnimate = clampNumber(
			(settings :: any).minPlayerDistanceToAnimate,
			0,
			2048,
			fallback.minPlayerDistanceToAnimate
		),
		maxConcurrentAnimations = clampInteger(
			(settings :: any).maxConcurrentAnimations,
			1,
			256,
			fallback.maxConcurrentAnimations
		),
		animateExistingChunks = if typeof((settings :: any).animateExistingChunks) == "boolean"
			then (settings :: any).animateExistingChunks
			else fallback.animateExistingChunks,
		maxAnimatedPartsPerChunk = clampInteger(
			(settings :: any).maxAnimatedPartsPerChunk,
			50,
			100000,
			fallback.maxAnimatedPartsPerChunk
		),
	}
end

function WorldAnimatorServiceUtils.createSettingsFromConfigs(configsRaw: any?): ChunkAnimatorSettings
	local configSource = if typeof(configsRaw) == "table" then configsRaw else Configs
	local worldAnimatorSettings =
		if typeof(configSource) == "table" then (configSource :: any).worldAnimatorSettings else nil
	return WorldAnimatorServiceUtils.sanitizeSettings(worldAnimatorSettings, nil)
end

function WorldAnimatorServiceUtils.applyEasing(easing: ChunkAnimationEasing, alphaRaw: any): number
	local alpha = clampNumber(alphaRaw, 0, 1, 0)

	if easing == "sine" then
		return Ease.outSine(alpha)
	end
	if easing == "quadratic" then
		return Ease.outQuad(alpha)
	end
	return alpha
end

function WorldAnimatorServiceUtils.doesAnimationUseFade(animationType: ChunkAnimationType): boolean
	return animationType == "fade" or animationType == "riseFade" or animationType == "fallFade"
end

function WorldAnimatorServiceUtils.computeAnimationOffset(
	animationType: ChunkAnimationType,
	verticalOffsetRaw: any
): Vector3
	local verticalOffset = clampNumber(verticalOffsetRaw, 0, 2048, DEFAULT_SETTINGS.verticalOffset)
	if animationType == "rise" or animationType == "riseFade" then
		return Vector3.new(0, -verticalOffset, 0)
	end
	if animationType == "fall" or animationType == "fallFade" then
		return Vector3.new(0, verticalOffset, 0)
	end
	return Vector3.zero
end

function WorldAnimatorServiceUtils.resolveLocalPlayerRootPart(): BasePart?
	local player = Players.LocalPlayer
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

function WorldAnimatorServiceUtils.getLocalPlayerDistanceFromPosition(worldPosition: Vector3): number?
	local rootPart = WorldAnimatorServiceUtils.resolveLocalPlayerRootPart()
	if rootPart == nil then
		return nil
	end
	return (rootPart.Position - worldPosition).Magnitude
end

function WorldAnimatorServiceUtils.isChunkModel(instance: Instance?): boolean
	if instance == nil or not instance:IsA("Model") then
		return false
	end

	local chunkX = instance:GetAttribute("ChunkX")
	local chunkY = instance:GetAttribute("ChunkY")
	if typeof(chunkX) == "number" and typeof(chunkY) == "number" then
		return true
	end

	return string.match(instance.Name, "^Chunk_") ~= nil
end

function WorldAnimatorServiceUtils.findWorldGenerationFolder(): Folder?
	return WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
end

function WorldAnimatorServiceUtils.findChunksFolder(worldFolder: Instance?): Folder?
	if worldFolder == nil then
		return nil
	end
	local chunksFolder = worldFolder:FindFirstChild(CHUNKS_FOLDER_NAME)
	if chunksFolder ~= nil and chunksFolder:IsA("Folder") then
		return chunksFolder
	end
	return nil
end

return WorldAnimatorServiceUtils
