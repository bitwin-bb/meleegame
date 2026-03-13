--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ripple = require(ReplicatedStorage.Packages.Ripple)
local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local AudioRegistry = require(ReplicatedStorage.Shared.Modules.Items.Audio)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)
local Rubble = require(ReplicatedStorage.Shared.Classes.Rubble)
local BuildServiceUtils = require(ReplicatedStorage.Shared.Services.BuildService.BuildServiceUtils)
local AudioServiceClient = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceClient)
local AudioServiceUtils = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceUtils)
local InventoryServiceClient = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceClient)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local itemSlice = require(ReplicatedStorage.UI.features.item.state.itemSlice)
local WorldGenerationServiceClient =
	require(ReplicatedStorage.Shared.Services.WorldGenerationService.WorldGenerationServiceClient)

type BuildServiceState = BuildServiceUtils.BuildServiceState
type PlaceableItemConfig = BuildServiceUtils.PlaceableItemConfig
type TileCoordinate = BuildServiceUtils.TileCoordinate
type TileDelta = BuildServiceUtils.TileDelta
type TreeHitResult = BuildServiceUtils.TreeHitResult
type TreeFelledPayload = BuildServiceUtils.TreeFelledPayload
type InventoryState = InventoryServiceUtils.InventoryState

type RubbleObject = {
	Spawn: (self: RubbleObject, paramsRaw: { [string]: any }?) -> BasePart?,
	Destroy: (self: RubbleObject) -> (),
}

type NumberMotion = Ripple.Motion<number>

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type PendingAction = {
	requestId: number,
	actionType: string,
	predictedPreviousByTile: { [string]: number },
	predictedTargetByTile: { [string]: number },
	createdAt: number,
}

type ActivePlaceSource = {
	config: PlaceableItemConfig,
	sourceSlot: number?,
}

type HeldInputState = {
	isHeld: boolean,
	tileX: number?,
	tileY: number?,
	lastSentAt: number,
	lastSentTileKey: string?,
}

type TreeFallAnimation = {
	treeId: string,
	model: Model,
	parts: { BasePart },
	baseTransparency: { number },
	basePivot: CFrame,
	modelOffsetFromBase: CFrame,
	angleMotion: NumberMotion,
	opacityMotion: NumberMotion,
	startedAt: number,
	fallDuration: number,
	bounceDuration: number,
	settleDuration: number,
	fadeDuration: number,
	impactAngle: number,
	overshootAngle: number,
	bounceAngle: number,
	fallDirection: number,
	minimumFadeElapsed: number,
	groundImpactDetected: boolean,
	fadeStartedAt: number?,
	sound: Sound?,
	soundFadeStarted: boolean,
	soundLoadedConnection: RBXScriptConnection?,
	stage: string,
}

local BuildServiceClient = {}

local CLIENT_VISUALS_FOLDER_NAME = "BuildServiceClientVisuals"
local TILE_QUERY_FETCH_COOLDOWN = 0.25
local PREDICTION_TTL_SECONDS = 2
local HOVER_BREAK_TEST_MODE = false
local MAX_BREAK_DEBRIS_TILES_PER_BATCH = 16
local BREAK_DEBRIS_REASONS = {
	["break"] = true,
	cascade = true,
}
local BREAK_DEBRIS_VISUALS = {
	[BuildServiceUtils.TILE_ID.GRASS] = {
		color = Color3.fromRGB(95, 159, 53),
		material = Enum.Material.Grass,
	},
	[BuildServiceUtils.TILE_ID.JUNGLE_GRASS] = {
		color = Color3.fromRGB(113, 186, 72),
		material = Enum.Material.Grass,
	},
	[BuildServiceUtils.TILE_ID.DIRT] = {
		color = Color3.fromRGB(108, 78, 52),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.STONE] = {
		color = Color3.fromRGB(108, 113, 122),
		material = Enum.Material.Slate,
	},
	[BuildServiceUtils.TILE_ID.SAND] = {
		color = Color3.fromRGB(225, 206, 136),
		material = Enum.Material.Sand,
	},
	[BuildServiceUtils.TILE_ID.SANDSTONE] = {
		color = Color3.fromRGB(183, 154, 109),
		material = Enum.Material.Sandstone,
	},
	[BuildServiceUtils.TILE_ID.SNOW] = {
		color = Color3.fromRGB(232, 240, 255),
		material = Enum.Material.Snow,
	},
	[BuildServiceUtils.TILE_ID.ICE] = {
		color = Color3.fromRGB(178, 214, 255),
		material = Enum.Material.Glacier,
	},
	[BuildServiceUtils.TILE_ID.MUD] = {
		color = Color3.fromRGB(112, 90, 61),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.CLAY] = {
		color = Color3.fromRGB(135, 98, 73),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.COPPER_ORE] = {
		color = Color3.fromRGB(189, 118, 63),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.IRON_ORE] = {
		color = Color3.fromRGB(141, 134, 116),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.SILVER_ORE] = {
		color = Color3.fromRGB(177, 177, 185),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.GOLD_ORE] = {
		color = Color3.fromRGB(214, 186, 62),
		material = Enum.Material.Metal,
	},
	[BuildServiceUtils.TILE_ID.CORRUPT_GRASS] = {
		color = Color3.fromRGB(131, 84, 193),
		material = Enum.Material.Grass,
	},
	[BuildServiceUtils.TILE_ID.CORRUPT_SOIL] = {
		color = Color3.fromRGB(116, 84, 88),
		material = Enum.Material.Ground,
	},
	[BuildServiceUtils.TILE_ID.CORRUPT_STONE] = {
		color = Color3.fromRGB(126, 104, 160),
		material = Enum.Material.Rock,
	},
	[BuildServiceUtils.TILE_ID.WOOD] = {
		color = Color3.fromRGB(121, 91, 56),
		material = Enum.Material.Wood,
	},
}
local DEFAULT_BREAK_DEBRIS_VISUAL = BREAK_DEBRIS_VISUALS[BuildServiceUtils.TILE_ID.STONE]
local BREAK_CHUNK_ANIMATION_SKIP_SECONDS = 1.5
local PRIMARY_INPUT_USER_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}
local TREE_MODEL_MATCH_MAX_DISTANCE_TILES = 6
local TREE_FALL_DURATION_MIN = 4
local TREE_FALL_DURATION_MAX = 5
local TREE_FALL_ACCELERATION_EXPONENT = 2.2
local TREE_FALL_BASE_ANGLE = math.rad(88)
local TREE_FALL_OVERSHOOT_ANGLE = math.rad(8)
local TREE_FALL_BOUNCE_ANGLE = math.rad(6)
local TREE_BOUNCE_DURATION = 0.16
local TREE_SETTLE_DURATION = 0.24
local TREE_FADE_DURATION = 0.85
local TREE_GROUND_HIT_MIN_ANGLE = math.rad(28)
local TREE_GROUND_HIT_MIN_PROGRESS = 0.2
local TREE_GROUND_HIT_SAMPLE_COUNT = 5
local TREE_GROUND_HIT_SCAN_DEPTH_TILES = 3
local TREE_GROUND_HIT_SURFACE_PADDING_TILES = 0.2
local TREE_GROUND_HIT_FAILSAFE_SECONDS = 1.2
local TREE_FALL_SOUND_FADE_OUT_SECONDS = 0.7
local TREE_FALL_SPRING = {
	frequency = 2.7,
	damping = 0.72,
}
local TREE_BOUNCE_SPRING = {
	frequency = 4.8,
	damping = 0.58,
}
local TREE_SETTLE_SPRING = {
	frequency = 6.5,
	damping = 0.92,
}
local TREE_FADE_SPRING = {
	frequency = 7,
	damping = 1,
}
local INPUT_ACTION_PRIMARY = "BuildService.Primary"
local TREE_AUDIO = (((AudioRegistry :: any).Misc or {}).Tree or {})
local TREE_FALL_AUDIO = TREE_AUDIO.Fall or {}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPrimaryInput(inputObject: InputObject): boolean
	return PRIMARY_INPUT_USER_TYPES[inputObject.UserInputType] == true
end

local function sanitizeInventorySlot(slotRaw: any): number?
	if typeof(slotRaw) ~= "number" or slotRaw ~= slotRaw then
		return nil
	end

	local slot = math.floor(slotRaw)
	if slot <= 0 then
		return nil
	end
	return slot
end

local function sanitizeInventoryState(stateRaw: any): InventoryState
	local state = if typeof(stateRaw) == "table"
		then InventoryServiceUtils.sanitizeState(stateRaw, InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED))
		else InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	return state
end

local function resolvePlaceableSourceFromInventorySlot(state: InventoryState, slotRaw: any): ActivePlaceSource?
	local slot = sanitizeInventorySlot(slotRaw)
	if slot == nil then
		return nil
	end

	local stack = InventoryServiceUtils.getStack(state, slot)
	if stack == nil or stack.amount <= 0 then
		return nil
	end

	local config = BuildServiceUtils.resolvePlaceableItemConfig(stack.itemId)
	if config == nil then
		return nil
	end

	return {
		config = config,
		sourceSlot = slot,
	}
end

local function resolveSelectedPlaceableSourceFromInventoryState(stateRaw: any): ActivePlaceSource?
	local state = sanitizeInventoryState(stateRaw)
	if not InventoryServiceUtils.isLoadedState(state.loadState) then
		return nil
	end

	return resolvePlaceableSourceFromInventorySlot(state, state.selectedSlot)
end

local function resolveSelectedPlaceableConfigFromInventoryState(stateRaw: any): PlaceableItemConfig?
	local placeSource = resolveSelectedPlaceableSourceFromInventoryState(stateRaw)
	if placeSource == nil then
		return nil
	end

	return placeSource.config
end

local function resolveActivePlaceSourceFromInventoryState(stateRaw: any): ActivePlaceSource?
	local state = sanitizeInventoryState(stateRaw)
	if not InventoryServiceUtils.isLoadedState(state.loadState) then
		return nil
	end

	local dragState = itemSlice.getDragState()
	if typeof(dragState) == "table" and dragState.active == true then
		if dragState.hoveredSlot ~= nil then
			return nil
		end
		return resolvePlaceableSourceFromInventorySlot(state, dragState.sourceSlot)
	end

	return resolveSelectedPlaceableSourceFromInventoryState(state)
end

local function resolveBreakDebrisVisual(tileId: number): (Color3, Enum.Material)
	local visual = BREAK_DEBRIS_VISUALS[tileId]
	if visual == nil then
		visual = DEFAULT_BREAK_DEBRIS_VISUAL
	end
	return visual.color, visual.material
end

local function suppressChunkAnimationForBreakDelta(delta: TileDelta)
	local worldGenerationClient = WorldGenerationServiceClient :: any
	local suppressMethod = worldGenerationClient.suppressChunkAnimationForTile
	if typeof(suppressMethod) ~= "function" then
		return
	end

	pcall(function()
		worldGenerationClient:suppressChunkAnimationForTile(
			delta.tileX,
			delta.tileY,
			BREAK_CHUNK_ANIMATION_SKIP_SECONDS
		)
	end)
end

local function collectModelParts(model: Model): ({ BasePart }, { number })
	local parts: { BasePart } = {}
	local baseTransparency: { number } = {}
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		parts[#parts + 1] = descendant
		baseTransparency[#baseTransparency + 1] = descendant.Transparency
	end
	return parts, baseTransparency
end

local function resolveSoundPlayableDuration(sound: Sound?): number?
	if sound == nil then
		return nil
	end
	local length = sound.TimeLength
	if not isFiniteNumber(length) or length <= 0 then
		return nil
	end
	local playbackSpeed = sound.PlaybackSpeed
	if not isFiniteNumber(playbackSpeed) or playbackSpeed <= 0 then
		playbackSpeed = 1
	end
	return length / (playbackSpeed :: number)
end

function BuildServiceClient.getTreesForChunk(self: BuildServiceClient, chunkX: number, chunkY: number): { any }?
	local chunkSnapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
	if typeof(chunkSnapshots) ~= "table" then
		return nil
	end
	local chunkKey = BuildServiceUtils.packChunkKey(chunkX, chunkY)
	local snapshot = chunkSnapshots[chunkKey]
	if typeof(snapshot) ~= "table" then
		return nil
	end
	local trees = (snapshot :: any).trees
	if typeof(trees) ~= "table" then
		return nil
	end
	return trees
end

function BuildServiceClient.resolveTreeHitAtTile(
	self: BuildServiceClient,
	tileX: number,
	tileY: number
): TreeHitResult?
	return BuildServiceUtils.resolveTreeAtTile(tileX, tileY, self.state.chunkSize, function(chunkX: number, chunkY: number): { any }?
		return self:getTreesForChunk(chunkX, chunkY)
	end)
end

function BuildServiceClient.isBreakableTarget(self: BuildServiceClient, tileX: number, tileY: number): boolean
	local tileId = self:getTileAt(tileX, tileY, false)
	if tileId ~= BuildServiceUtils.AIR_TILE_ID then
		return true
	end
	local treeHit = self:resolveTreeHitAtTile(tileX, tileY)
	return treeHit ~= nil
end

function BuildServiceClient.resolveTreeModelForFellEvent(
	self: BuildServiceClient,
	payload: TreeFelledPayload
): Model?
	local chunkVisuals = (WorldGenerationServiceClient :: any).chunkVisuals
	if typeof(chunkVisuals) ~= "table" then
		return nil
	end

	local bestModel: Model? = nil
	local bestScore = math.huge
	local distanceBudget = self.state.tileSize * TREE_MODEL_MATCH_MAX_DISTANCE_TILES
	for _, visual in chunkVisuals do
		if typeof(visual) ~= "table" then
			continue
		end
		local chunkModel = (visual :: any).model
		if typeof(chunkModel) ~= "Instance" or not chunkModel:IsA("Model") then
			continue
		end

		local treesFolder = chunkModel:FindFirstChild("Trees")
		if treesFolder == nil then
			continue
		end

		for _, treeChild in treesFolder:GetChildren() do
			if not treeChild:IsA("Model") then
				continue
			end

			if treeChild:GetAttribute("BuildTreeId") == payload.treeId then
				return treeChild
			end

			local seedAttribute = treeChild:GetAttribute("TreeSeed")
			local hasSeedMatch = isFiniteNumber(seedAttribute) and math.floor(seedAttribute :: number) == payload.seed
			local ok, modelPivot = pcall(function()
				return treeChild:GetPivot()
			end)
			if not ok then
				continue
			end
			local distance = BuildServiceUtils.worldDistance2D(modelPivot.Position, payload.pivotCFrame.Position)
			local allowedDistance = if hasSeedMatch then distanceBudget * 2 else distanceBudget
			if distance > allowedDistance then
				continue
			end

			local score = distance + (if hasSeedMatch then 0 else distanceBudget)
			if score < bestScore then
				bestScore = score
				bestModel = treeChild
			end
		end
	end

	return bestModel
end

function BuildServiceClient.refreshTreeFallSoundTemplates(self: BuildServiceClient)
	self.treeFallSoundAssetIds = AudioServiceUtils.collectSoundAssetIds(TREE_FALL_AUDIO)
end

function BuildServiceClient.pickTreeFallSoundAssetId(self: BuildServiceClient): string?
	if #self.treeFallSoundAssetIds <= 0 then
		self:refreshTreeFallSoundTemplates()
	end
	local count = #self.treeFallSoundAssetIds
	if count <= 0 then
		return nil
	end
	return self.treeFallSoundAssetIds[self.random:NextInteger(1, count)]
end

function BuildServiceClient.applyTreeFallSoundSyncDuration(
	_self: BuildServiceClient,
	animation: TreeFallAnimation,
	_durationRaw: any
)
	animation.minimumFadeElapsed = 0
end

function BuildServiceClient.playTreeFallSound(self: BuildServiceClient, animation: TreeFallAnimation)
	local soundAssetId = self:pickTreeFallSoundAssetId()
	if soundAssetId == nil then
		return
	end

	self:applyTreeFallSoundSyncDuration(animation, nil)
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	local playedSound = AudioServiceClient:playSfx(soundAssetId, {
		parent = self.visualFolder,
		replaceChannel = false,
		autoDestroy = true,
	})
	if playedSound == nil then
		return
	end
	animation.sound = playedSound
	animation.soundFadeStarted = false

	self:applyTreeFallSoundSyncDuration(animation, resolveSoundPlayableDuration(playedSound))
	if resolveSoundPlayableDuration(playedSound) ~= nil then
		return
	end

	local loadedConnection: RBXScriptConnection?
	loadedConnection = playedSound.Loaded:Connect(function()
		if loadedConnection ~= nil then
			loadedConnection:Disconnect()
			loadedConnection = nil
		end
		if self.treeFallAnimations[animation.treeId] ~= animation then
			return
		end
		self:applyTreeFallSoundSyncDuration(animation, resolveSoundPlayableDuration(playedSound))
	end)
	animation.soundLoadedConnection = loadedConnection
end

function BuildServiceClient.fadeTreeFallSoundIfPlaying(
	_self: BuildServiceClient,
	animation: TreeFallAnimation,
	fadeSecondsRaw: any?
)
	if animation.soundFadeStarted then
		return
	end
	animation.soundFadeStarted = true

	local sound = animation.sound
	animation.sound = nil
	if sound == nil or sound.Parent == nil then
		return
	end

	local fadeSeconds = if isFiniteNumber(fadeSecondsRaw)
		then math.max(0, fadeSecondsRaw)
		else TREE_FALL_SOUND_FADE_OUT_SECONDS
	AudioServiceUtils.stopAndDestroySound(sound, fadeSeconds)
end

function BuildServiceClient.stopTreeFallAnimation(self: BuildServiceClient, treeId: string, destroyModel: boolean)
	local animation = self.treeFallAnimations[treeId]
	if animation == nil then
		return
	end
	self.treeFallAnimations[treeId] = nil
	for index = #self.treeFallAnimationOrder, 1, -1 do
		if self.treeFallAnimationOrder[index] == treeId then
			table.remove(self.treeFallAnimationOrder, index)
		end
	end

	if animation.soundLoadedConnection ~= nil then
		animation.soundLoadedConnection:Disconnect()
		animation.soundLoadedConnection = nil
	end
	self:fadeTreeFallSoundIfPlaying(animation, 0)
	animation.angleMotion:destroy()
	animation.opacityMotion:destroy()
	if destroyModel and animation.model.Parent ~= nil then
		animation.model:Destroy()
	end
end

function BuildServiceClient.beginTreeFallFade(self: BuildServiceClient, animation: TreeFallAnimation, now: number)
	if animation.stage == "fade" then
		return
	end
	animation.stage = "fade"
	animation.fadeStartedAt = now
	self:fadeTreeFallSoundIfPlaying(animation, TREE_FALL_SOUND_FADE_OUT_SECONDS)
	animation.opacityMotion:spring(0, TREE_FADE_SPRING)
end

function BuildServiceClient.isGroundNearWorldPoint(self: BuildServiceClient, point: Vector3): boolean
	local tileSize = math.max(0.05, self.state.tileSize)
	local tileX, tileY = BuildServiceUtils.worldPositionToTile(point, self.state.worldOrigin, tileSize)
	local surfacePadding = tileSize * TREE_GROUND_HIT_SURFACE_PADDING_TILES

	for depth = 0, TREE_GROUND_HIT_SCAN_DEPTH_TILES do
		local scanTileY = tileY - depth
		local tileId = self:getTileAt(tileX, scanTileY, false)
		if BuildServiceUtils.isSolidTile(tileId) then
			local tileCenter = BuildServiceUtils.tileToWorldCenter(
				tileX,
				scanTileY,
				self.state.worldOrigin,
				tileSize,
				self.state.basePlaneX
			)
			local tileTop = tileCenter.Y + tileSize * 0.5
			if point.Y <= tileTop + surfacePadding then
				return true
			end
		end
	end

	return false
end

function BuildServiceClient.hasTreeGroundImpact(
	self: BuildServiceClient,
	animation: TreeFallAnimation,
	elapsed: number,
	currentAngle: number
): boolean
	if elapsed < animation.fallDuration * TREE_GROUND_HIT_MIN_PROGRESS then
		return false
	end
	if math.abs(currentAngle) < TREE_GROUND_HIT_MIN_ANGLE then
		return false
	end

	local ok, boundsCFrame, boundsSize = pcall(function()
		return animation.model:GetBoundingBox()
	end)
	if not ok or typeof(boundsCFrame) ~= "CFrame" or typeof(boundsSize) ~= "Vector3" then
		return false
	end

	local halfWidth = boundsSize.X * 0.5
	local halfHeight = boundsSize.Y * 0.5
	local halfDepth = math.max(boundsSize.Z * 0.5, self.state.tileSize * 0.2)
	local yExtent = math.abs(boundsCFrame.XVector.Y) * halfWidth
		+ math.abs(boundsCFrame.YVector.Y) * halfHeight
		+ math.abs(boundsCFrame.ZVector.Y) * halfDepth
	local bottomY = boundsCFrame.Position.Y - yExtent
	local direction = BuildServiceUtils.normalizeFallDirection(animation.fallDirection)
	local sampleCount = TREE_GROUND_HIT_SAMPLE_COUNT

	for sampleIndex = 0, sampleCount - 1 do
		local alpha = if sampleCount <= 1 then 0 else sampleIndex / (sampleCount - 1)
		local localZ = direction * halfDepth * (0.2 + 0.8 * alpha)
		local sampleWorld = (boundsCFrame * CFrame.new(0, 0, localZ)).Position
		local probePoint = Vector3.new(sampleWorld.X, bottomY, sampleWorld.Z)
		if self:isGroundNearWorldPoint(probePoint) then
			return true
		end
	end

	return false
end

function BuildServiceClient.startTreeFallAnimation(self: BuildServiceClient, payload: TreeFelledPayload)
	local treeModel = self:resolveTreeModelForFellEvent(payload)
	if treeModel == nil then
		return
	end

	self:stopTreeFallAnimation(payload.treeId, true)
	treeModel:SetAttribute("BuildTreeId", payload.treeId)
	treeModel.Parent = self.visualFolder

	local ok, modelPivot = pcall(function()
		return treeModel:GetPivot()
	end)
	if not ok then
		return
	end

	local parts, baseTransparency = collectModelParts(treeModel)
	if #parts <= 0 then
		treeModel:Destroy()
		return
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end

	local direction = BuildServiceUtils.normalizeFallDirection(payload.fallDirection)
	local configuredFallDuration = self.random:NextNumber(TREE_FALL_DURATION_MIN, TREE_FALL_DURATION_MAX)
	local impactAngle = TREE_FALL_BASE_ANGLE * direction
	local overshootAngle = impactAngle + TREE_FALL_OVERSHOOT_ANGLE * direction
	local bounceAngle = impactAngle - TREE_FALL_BOUNCE_ANGLE * direction

	local angleMotion = Ripple.createMotion(0)
	local opacityMotion = Ripple.createMotion(1)
	angleMotion:immediate(0)
	opacityMotion:immediate(1)

	local animation: TreeFallAnimation = {
		treeId = payload.treeId,
		model = treeModel,
		parts = parts,
		baseTransparency = baseTransparency,
		basePivot = payload.pivotCFrame,
		modelOffsetFromBase = payload.pivotCFrame:ToObjectSpace(modelPivot),
		angleMotion = angleMotion,
		opacityMotion = opacityMotion,
		startedAt = os.clock(),
		fallDuration = configuredFallDuration,
		bounceDuration = TREE_BOUNCE_DURATION,
		settleDuration = TREE_SETTLE_DURATION,
		fadeDuration = TREE_FADE_DURATION,
		impactAngle = impactAngle,
		overshootAngle = overshootAngle,
		bounceAngle = bounceAngle,
		fallDirection = direction,
		minimumFadeElapsed = 0,
		groundImpactDetected = false,
		fadeStartedAt = nil,
		sound = nil,
		soundFadeStarted = false,
		soundLoadedConnection = nil,
		stage = "fall",
	}
	self.treeFallAnimations[payload.treeId] = animation
	self.treeFallAnimationOrder[#self.treeFallAnimationOrder + 1] = payload.treeId
	self:playTreeFallSound(animation)
end

function BuildServiceClient.stepTreeFallAnimations(self: BuildServiceClient, deltaTime: number)
	if #self.treeFallAnimationOrder <= 0 then
		return
	end

	local now = os.clock()
	for index = #self.treeFallAnimationOrder, 1, -1 do
		local treeId = self.treeFallAnimationOrder[index]
		local animation = self.treeFallAnimations[treeId]
		if animation == nil then
			table.remove(self.treeFallAnimationOrder, index)
			continue
		end
		if animation.model.Parent == nil then
			self:stopTreeFallAnimation(treeId, false)
			continue
		end

		local elapsed = now - animation.startedAt
		local nextAngle = 0
		if animation.stage == "fall" then
			local alpha = math.clamp(elapsed / math.max(0.01, animation.fallDuration), 0, 1)
			local accelerated = alpha ^ TREE_FALL_ACCELERATION_EXPONENT
			nextAngle = animation.impactAngle * accelerated
			animation.angleMotion:immediate(nextAngle)
		elseif animation.stage == "bounce" then
			nextAngle = animation.angleMotion:step(deltaTime)
		elseif animation.stage == "settle" then
			nextAngle = animation.angleMotion:step(deltaTime)
		else
			nextAngle = animation.angleMotion:step(deltaTime)
		end

		if animation.stage == "fall" and elapsed >= animation.fallDuration then
			animation.stage = "bounce"
			animation.angleMotion:spring(animation.bounceAngle, TREE_BOUNCE_SPRING)
		elseif animation.stage == "bounce" and elapsed >= animation.fallDuration + animation.bounceDuration then
			animation.stage = "settle"
			animation.angleMotion:spring(animation.impactAngle, TREE_SETTLE_SPRING)
		end
		if not animation.groundImpactDetected and self:hasTreeGroundImpact(animation, elapsed, nextAngle) then
			animation.groundImpactDetected = true
		end
		local impactFailsafeAt = math.max(
			animation.minimumFadeElapsed,
			animation.fallDuration + animation.bounceDuration + animation.settleDuration + TREE_GROUND_HIT_FAILSAFE_SECONDS
		)
		if animation.stage ~= "fade" then
			local canFadeOnImpact = animation.groundImpactDetected
				and animation.stage ~= "fall"
				and elapsed >= animation.fallDuration
				and elapsed >= animation.minimumFadeElapsed
			if canFadeOnImpact or elapsed >= impactFailsafeAt then
				self:beginTreeFallFade(animation, now)
			end
		end
		local opacity = if animation.stage == "fade"
			then math.clamp(animation.opacityMotion:step(deltaTime), 0, 1)
			else 1
		local nextPivot = animation.basePivot * CFrame.Angles(nextAngle, 0, 0) * animation.modelOffsetFromBase
		animation.model:PivotTo(nextPivot)
		for partIndex, part in animation.parts do
			local baseValue = animation.baseTransparency[partIndex] or 0
			part.Transparency = baseValue + (1 - baseValue) * (1 - opacity)
		end

		local fadeStartedAt = animation.fadeStartedAt
		if animation.stage == "fade" and fadeStartedAt ~= nil and now - fadeStartedAt >= animation.fadeDuration then
			self:stopTreeFallAnimation(treeId, true)
		end
	end
end

function BuildServiceClient.onTreeFelled(self: BuildServiceClient, payloadRaw: any)
	local payload = BuildServiceUtils.sanitizeTreeFelledPayload(payloadRaw)
	if payload == nil then
		return
	end
	self:startTreeFallAnimation(payload)
end

function BuildServiceClient.createVisualFolder(self: BuildServiceClient): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(CLIENT_VISUALS_FOLDER_NAME)
end

function BuildServiceClient.createPreviewVisual(self: BuildServiceClient)
	self.visualFolder = self:createVisualFolder()
	for _, child in self.visualFolder:GetChildren() do
		if child.Name == "BuildPreview" then
			child:Destroy()
		end
	end
	for _, descendant in self.visualFolder:GetDescendants() do
		if descendant:IsA("BillboardGui") and descendant.Name == "BreakProgress" then
			descendant:Destroy()
		end
	end

	local previewPart = Instance.new("Part")
	previewPart.Name = "BuildPreview"
	previewPart.Anchored = true
	previewPart.CanCollide = false
	previewPart.CanQuery = false
	previewPart.CanTouch = false
	previewPart.Material = Enum.Material.SmoothPlastic
	previewPart.Color = Color3.new(1, 1, 1)
	previewPart.Transparency = 1
	previewPart.Size = Vector3.new(0.08, self.state.tileSize, self.state.tileSize)
	previewPart.CFrame = CFrame.new(0, -10000, 0)
	previewPart.Parent = self.visualFolder

	local previewHighlight = Instance.new("Highlight")
	previewHighlight.Name = "BuildHoverHighlight"
	previewHighlight.Adornee = previewPart
	previewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	previewHighlight.FillColor = Color3.new(1, 1, 1)
	previewHighlight.FillTransparency = 1
	previewHighlight.OutlineColor = Color3.new(1, 1, 1)
	previewHighlight.OutlineTransparency = 0
	previewHighlight.Enabled = false
	previewHighlight.Parent = previewPart

	self.previewPart = previewPart
	self.previewHighlight = previewHighlight
end

function BuildServiceClient.resolveCursorTile(self: BuildServiceClient): (number?, number?)
	local currentCamera = Workspace.CurrentCamera
	if currentCamera == nil then
		return nil, nil
	end
	local mouseLocation = nil :: Vector2?
	local cursorModule = self.cursorModule
	if cursorModule ~= nil and typeof((cursorModule :: any).getScreenPosition) == "function" then
		local candidate = (cursorModule :: any):getScreenPosition()
		if typeof(candidate) == "Vector2" then
			mouseLocation = candidate
		end
	end
	if mouseLocation == nil then
		local ok, candidate = pcall(function()
			return UserInputService:GetMouseLocation()
		end)
		if ok and typeof(candidate) == "Vector2" then
			mouseLocation = candidate
		end
	end
	if mouseLocation == nil then
		return nil, nil
	end
	local viewportRay = currentCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local hitOnPlane = BuildServiceUtils.raycastToBuildPlane(
		viewportRay.Origin,
		viewportRay.Direction,
		self.state.basePlaneX
	)
	if hitOnPlane == nil then
		return nil, nil
	end
	local planeTileX, planeTileY =
		BuildServiceUtils.worldPositionToTile(hitOnPlane, self.state.worldOrigin, self.state.tileSize)
	return planeTileX, planeTileY
end

function BuildServiceClient.getTileFromWorldGenerationSnapshot(
	self: BuildServiceClient,
	tileX: number,
	tileY: number
): number?
	local worldState = nil
	local getStateMethod = (WorldGenerationServiceClient :: any).getState
	if typeof(getStateMethod) == "function" then
		local ok, resultOrError = pcall(function()
			return (WorldGenerationServiceClient :: any):getState()
		end)
		if ok and typeof(resultOrError) == "table" then
			worldState = resultOrError
		end
	end
	if worldState == nil then
		worldState = (WorldGenerationServiceClient :: any).state
	end
	if typeof(worldState) ~= "table" then
		return nil
	end

	local chunkSize = if isFiniteNumber((worldState :: any).chunkSize) then math.floor((worldState :: any).chunkSize) else 32
	local chunkX = BuildServiceUtils.toChunkCoordinate(tileX, chunkSize)
	local chunkY = BuildServiceUtils.toChunkCoordinate(tileY, chunkSize)
	local chunkSnapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
	if typeof(chunkSnapshots) ~= "table" then
		return nil
	end
	local chunkKey = BuildServiceUtils.packChunkKey(chunkX, chunkY)
	local snapshot = chunkSnapshots[chunkKey]
	if typeof(snapshot) ~= "table" then
		return nil
	end

	local tileMinX = if isFiniteNumber((snapshot :: any).tileMinX) then math.floor((snapshot :: any).tileMinX) else chunkX * chunkSize
	local tileMinY = if isFiniteNumber((snapshot :: any).tileMinY) then math.floor((snapshot :: any).tileMinY) else chunkY * chunkSize
	local width = if isFiniteNumber((snapshot :: any).width) then math.max(1, math.floor((snapshot :: any).width)) else chunkSize
	local height = if isFiniteNumber((snapshot :: any).height) then math.max(1, math.floor((snapshot :: any).height)) else chunkSize
	local localX = tileX - tileMinX
	local localY = tileY - tileMinY
	if localX < 0 or localX >= width or localY < 0 or localY >= height then
		return nil
	end
	local tilesRaw = (snapshot :: any).tiles
	if typeof(tilesRaw) ~= "table" then
		return nil
	end
	local index = BuildServiceUtils.computeTileIndex(localX, localY, width)
	local tileIdRaw = tilesRaw[index]
	if not isFiniteNumber(tileIdRaw) then
		return nil
	end
	local tileId = BuildServiceUtils.sanitizeTileId(tileIdRaw)
	return tileId
end

function BuildServiceClient.getTileAt(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	allowServerFetchRaw: any?
): number
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return BuildServiceUtils.AIR_TILE_ID
	end
	local tileKey = BuildServiceUtils.packTileKey(tileX, tileY)

	local predictedTileId = self.predictedTileOverrides[tileKey]
	if predictedTileId ~= nil then
		return predictedTileId
	end
	local cachedDeltaTileId = self.authoritativeDeltaCache[tileKey]
	if cachedDeltaTileId ~= nil then
		return cachedDeltaTileId
	end
	local worldTileId = self:getTileFromWorldGenerationSnapshot(tileX, tileY)
	if worldTileId ~= nil then
		return worldTileId
	end

	local allowServerFetch = BuildServiceUtils.sanitizeBoolean(allowServerFetchRaw, false)
	if not allowServerFetch then
		return BuildServiceUtils.AIR_TILE_ID
	end
	if not self.enableServerTileFetchFallback then
		return BuildServiceUtils.AIR_TILE_ID
	end

	local now = os.clock()
	local nextAllowedAt = self.tileFetchCooldownByTileKey[tileKey] or 0
	if now < nextAllowedAt then
		return BuildServiceUtils.AIR_TILE_ID
	end
	self.tileFetchCooldownByTileKey[tileKey] = now + TILE_QUERY_FETCH_COOLDOWN

	local ok, tileIdOrError = pcall(function()
		return self.networker:fetch(BuildServiceUtils.NETWORK_METHOD_GET_TILE_AT, tileX, tileY)
	end)
	if not ok then
		return BuildServiceUtils.AIR_TILE_ID
	end
	if not isFiniteNumber(tileIdOrError) then
		return BuildServiceUtils.AIR_TILE_ID
	end
	local tileId = BuildServiceUtils.sanitizeTileId(tileIdOrError)
	if tileId == nil then
		return BuildServiceUtils.AIR_TILE_ID
	end
	self.authoritativeDeltaCache[tileKey] = tileId
	return tileId
end

function BuildServiceClient.canPlaceAt(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any
): (boolean, string, { TileCoordinate })
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	local tileId = BuildServiceUtils.sanitizeTileId(tileIdRaw)
	if tileX == nil or tileY == nil or tileId == nil then
		return false, "invalid_tile_coordinate_or_id", {}
	end
	local placementResult = BuildServiceUtils.canPlaceAt(
		tileX,
		tileY,
		tileId,
		function(scanX: number, scanY: number): number
			return self:getTileAt(scanX, scanY, false)
		end,
		nil,
		nil
	)
	return placementResult.canPlace, placementResult.reason, placementResult.footprint
end

function BuildServiceClient.cleanupPendingAction(self: BuildServiceClient, requestId: number)
	self.pendingActions[requestId] = nil
end

function BuildServiceClient.rollbackPendingAction(self: BuildServiceClient, requestId: number)
	local pending = self.pendingActions[requestId]
	if pending == nil then
		return
	end
	for tileKey, previousTileId in pending.predictedPreviousByTile do
		if previousTileId == BuildServiceUtils.AIR_TILE_ID then
			self.predictedTileOverrides[tileKey] = nil
		else
			self.predictedTileOverrides[tileKey] = previousTileId
		end
	end
	self.pendingActions[requestId] = nil
end

function BuildServiceClient.createPlacePrediction(
	self: BuildServiceClient,
	requestId: number,
	tileX: number,
	tileY: number,
	tileId: number
)
	local canPlace, _, footprint = self:canPlaceAt(tileX, tileY, tileId)
	if not canPlace then
		return
	end

	local pending: PendingAction = {
		requestId = requestId,
		actionType = BuildServiceUtils.ACTION_TYPE_PLACE,
		predictedPreviousByTile = {},
		predictedTargetByTile = {},
		createdAt = os.clock(),
	}
	for _, footprintTile in footprint do
		local tileKey = BuildServiceUtils.packTileKey(footprintTile.tileX, footprintTile.tileY)
		local previousTileId = self:getTileAt(footprintTile.tileX, footprintTile.tileY, false)
		pending.predictedPreviousByTile[tileKey] = previousTileId
		pending.predictedTargetByTile[tileKey] = tileId
		self.predictedTileOverrides[tileKey] = tileId
	end
	self.pendingActions[requestId] = pending
end

function BuildServiceClient.requestPlaceTile(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any,
	sourceSlotRaw: any?
): number
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	local tileId = BuildServiceUtils.sanitizeTileId(tileIdRaw)
	local sourceSlot = sanitizeInventorySlot(sourceSlotRaw)
	local requestId = self.nextRequestId
	self.nextRequestId += 1

	if tileX == nil or tileY == nil or tileId == nil then
		return requestId
	end
	self:createPlacePrediction(requestId, tileX, tileY, tileId)
	self.networker:fire(
		BuildServiceUtils.NETWORK_METHOD_REQUEST_PLACE_TILE,
		tileX,
		tileY,
		tileId,
		requestId,
		sourceSlot
	)
	return requestId
end

function BuildServiceClient.requestBreakTile(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	isBreakingRaw: any
): number
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	local isBreaking = BuildServiceUtils.sanitizeBoolean(isBreakingRaw, false)
	local requestId = self.nextRequestId
	self.nextRequestId += 1
	self.networker:fire(
		BuildServiceUtils.NETWORK_METHOD_REQUEST_BREAK_TILE,
		tileX,
		tileY,
		isBreaking,
		requestId
	)
	return requestId
end

function BuildServiceClient.onTileDeltas(self: BuildServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local deltasRaw = payload.deltas
	if typeof(deltasRaw) ~= "table" then
		return
	end

	local appliedDeltas: { TileDelta } = {}
	local debrisTilesSpawned = 0
	for _, deltaRaw in deltasRaw do
		local delta = BuildServiceUtils.cloneTileDelta(deltaRaw)
		if delta == nil then
			continue
		end
		local previousTileId = self:getTileAt(delta.tileX, delta.tileY, false)
		appliedDeltas[#appliedDeltas + 1] = delta
		local tileKey = BuildServiceUtils.packTileKey(delta.tileX, delta.tileY)
		self.authoritativeDeltaCache[tileKey] = delta.tileId
		local predictedTileId = self.predictedTileOverrides[tileKey]
		if predictedTileId ~= nil and predictedTileId == delta.tileId then
			self.predictedTileOverrides[tileKey] = nil
		end

		local isBreakDelta = delta.reason ~= nil and BREAK_DEBRIS_REASONS[delta.reason] == true
		if isBreakDelta then
			suppressChunkAnimationForBreakDelta(delta)
		end

		if debrisTilesSpawned < MAX_BREAK_DEBRIS_TILES_PER_BATCH then
			local shouldSpawnDebris = delta.tileId == BuildServiceUtils.AIR_TILE_ID
				and previousTileId ~= BuildServiceUtils.AIR_TILE_ID
				and isBreakDelta
			if shouldSpawnDebris then
				debrisTilesSpawned += 1
				self:spawnBreakDebris(delta.tileX, delta.tileY, previousTileId)
			end
		end
	end

	if #appliedDeltas > 0 then
		self.tileDeltasApplied:Fire(appliedDeltas)
	end
end

function BuildServiceClient.spawnBreakDebris(
	self: BuildServiceClient,
	tileX: number,
	tileY: number,
	tileId: number
)
	if self.rubble == nil then
		return
	end
	local color, material = resolveBreakDebrisVisual(tileId)
	local tileCenter = BuildServiceUtils.tileToWorldCenter(
		tileX,
		tileY,
		self.state.worldOrigin,
		self.state.tileSize,
		self.state.basePlaneX
	)
	local halfTile = self.state.tileSize * 0.5
	local shardCount = self.random:NextInteger(2, 4)
	for _ = 1, shardCount do
		local shardSize = self.state.tileSize * self.random:NextNumber(0.15, 0.34)
		local spawnOffset = Vector3.new(
			self.random:NextNumber(-0.02, 0.02),
			self.random:NextNumber(-halfTile * 0.2, halfTile * 0.2),
			self.random:NextNumber(-halfTile * 0.2, halfTile * 0.2)
		)
		local impulse = Vector3.new(
			self.random:NextNumber(-0.9, 0.9),
			self.random:NextNumber(0.35, 1.35),
			self.random:NextNumber(-1.4, 1.4)
		)
		self.rubble:Spawn({
			CFrame = CFrame.new(tileCenter + spawnOffset),
			Size = Vector3.new(shardSize, shardSize, shardSize),
			Color = color,
			Material = material,
			Transparency = 0,
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Impulse = impulse,
			EnableGravity = true,
			CanFling = false,
			FadeOut = true,
			Lifetime = self.random:NextNumber(0.5, 0.95),
			Mirror = false,
		})
	end
end

function BuildServiceClient.onActionResult(self: BuildServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local requestId = BuildServiceUtils.sanitizeRequestId(payload.requestId)
	local accepted = payload.accepted == true
	local reason = if typeof(payload.reason) == "string" then payload.reason else "unknown"

	local pending = self.pendingActions[requestId]
	if pending ~= nil then
		if not accepted then
			self:rollbackPendingAction(requestId)
		else
			self:cleanupPendingAction(requestId)
		end
	end

	if not accepted then
		self.actionRejected:Fire(payload.actionType, reason, requestId)
		return
	end

	if typeof(payload.deltas) == "table" then
		self:onTileDeltas({
			deltas = payload.deltas,
		})
	end
	self.actionAccepted:Fire(payload.actionType, reason, requestId)
end

function BuildServiceClient.onBreakProgress(self: BuildServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(payload.tileX)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(payload.tileY)
	local progressRaw = payload.progress
	local breakDurationRaw = payload.breakDuration
	local progress = if isFiniteNumber(progressRaw) then math.clamp(progressRaw, 0, 1) else 0
	local breakDuration = if isFiniteNumber(breakDurationRaw) then math.max(0, breakDurationRaw) else 0
	local isActive = payload.isActive == true and tileX ~= nil and tileY ~= nil

	if isActive then
		self.currentBreakProgress = {
			isActive = true,
			tileX = tileX,
			tileY = tileY,
			progress = progress,
			breakDuration = breakDuration,
			updatedAt = os.clock(),
		}
		self.hitFeedback:Fire(tileX, tileY, progress)
	else
		self.currentBreakProgress = nil
	end
	self.breakProgressChanged:Fire(self.currentBreakProgress)
end

function BuildServiceClient.updatePreviewVisual(
	self: BuildServiceClient,
	tileX: number?,
	tileY: number?,
	canPlace: boolean?
)
	if self.previewPart == nil then
		return
	end
	if tileX == nil or tileY == nil then
		self.previewPart.CFrame = CFrame.new(0, -10000, 0)
		if self.previewHighlight ~= nil then
			self.previewHighlight.Enabled = false
		end
		return
	end

	local center = BuildServiceUtils.tileToWorldCenter(
		tileX,
		tileY,
		self.state.worldOrigin,
		self.state.tileSize,
		self.state.basePlaneX
	)
	self.previewPart.Size = Vector3.new(0.08, self.state.tileSize, self.state.tileSize)
	self.previewPart.CFrame = CFrame.new(center)
	if self.previewHighlight ~= nil then
		if canPlace == true then
			self.previewHighlight.OutlineColor = Color3.fromRGB(122, 255, 154)
		elseif canPlace == false then
			self.previewHighlight.OutlineColor = Color3.fromRGB(255, 116, 116)
		else
			self.previewHighlight.OutlineColor = Color3.new(1, 1, 1)
		end
		self.previewHighlight.Enabled = true
	end
end

function BuildServiceClient.prunePendingPredictions(self: BuildServiceClient)
	local now = os.clock()
	for requestId, pending in self.pendingActions do
		if now - pending.createdAt <= PREDICTION_TTL_SECONDS then
			continue
		end
		self:cleanupPendingAction(requestId)
	end
end

function BuildServiceClient.updateCursorTile(self: BuildServiceClient)
	local cursorTileX, cursorTileY = self:resolveCursorTile()
	self.cursorTileX = cursorTileX
	self.cursorTileY = cursorTileY
end

function BuildServiceClient.applyHoverBreakInput(self: BuildServiceClient)
	local cursorTileX = self.cursorTileX
	local cursorTileY = self.cursorTileY
	if cursorTileX == nil or cursorTileY == nil then
		self:setBreakInput(false, nil, nil)
		return
	end
	local shouldBreak = self:isBreakableTarget(cursorTileX, cursorTileY)
	self:setBreakInput(shouldBreak, cursorTileX, cursorTileY)
end

function BuildServiceClient.flushHeldBreakInput(self: BuildServiceClient, now: number)
	local state = self.breakInput
	if not state.isHeld then
		if state.lastSentTileKey ~= nil then
			self.networker:fire(
				BuildServiceUtils.NETWORK_METHOD_REQUEST_BREAK_TILE,
				state.tileX,
				state.tileY,
				false,
				0
			)
			state.lastSentTileKey = nil
		end
		return
	end
	if state.tileX == nil or state.tileY == nil then
		return
	end

	local tileKey = BuildServiceUtils.packTileKey(state.tileX, state.tileY)
	if state.lastSentTileKey == tileKey and now - state.lastSentAt < self.state.clientBreakInputRate then
		return
	end
	state.lastSentAt = now
	state.lastSentTileKey = tileKey
	self.networker:fire(
		BuildServiceUtils.NETWORK_METHOD_REQUEST_BREAK_TILE,
		state.tileX,
		state.tileY,
		true,
		0
	)
end

function BuildServiceClient.flushHeldPlaceInput(self: BuildServiceClient, now: number)
	local state = self.placeInput
	if not state.isHeld then
		return
	end
	local activePlaceSource = self:resolveActivePlaceSource()
	if activePlaceSource == nil then
		self:setPlaceInput(false, nil, nil)
		return
	end
	if state.tileX == nil or state.tileY == nil then
		return
	end
	if now - state.lastSentAt < self.state.clientPlaceInputRate then
		return
	end

	local tileId = activePlaceSource.config.tileId
	local canPlace = self:canPlaceAt(state.tileX, state.tileY, tileId)
	if not canPlace then
		return
	end
	state.lastSentAt = now
	self:requestPlaceTile(state.tileX, state.tileY, tileId, activePlaceSource.sourceSlot)
end

function BuildServiceClient.onRenderStep(self: BuildServiceClient, _deltaTime: number)
	self:stepTreeFallAnimations(_deltaTime)
	self:updateCursorTile()

	if HOVER_BREAK_TEST_MODE then
		self:applyHoverBreakInput()
	elseif self.breakInput.isHeld then
		local hoverTileX = self.cursorTileX
		local hoverTileY = self.cursorTileY
		local targetTileX = self.breakInput.tileX
		local targetTileY = self.breakInput.tileY

		local function getHoveredBreakableTile(): (number?, number?)
			if hoverTileX == nil or hoverTileY == nil then
				return nil, nil
			end
			if not self:isBreakableTarget(hoverTileX, hoverTileY) then
				return nil, nil
			end
			return hoverTileX, hoverTileY
		end

		if targetTileX == nil or targetTileY == nil then
			local nextTileX, nextTileY = getHoveredBreakableTile()
			if nextTileX ~= nil and nextTileY ~= nil then
				self:setBreakInput(true, nextTileX, nextTileY)
			end
		else
			local currentBreakProgress = self.currentBreakProgress
			local finishedByProgress = currentBreakProgress ~= nil
				and currentBreakProgress.tileX == targetTileX
				and currentBreakProgress.tileY == targetTileY
				and currentBreakProgress.progress >= 0.99
			local targetFinished = (not self:isBreakableTarget(targetTileX, targetTileY)) or finishedByProgress

			if hoverTileX ~= targetTileX or hoverTileY ~= targetTileY then
				if targetFinished then
					local nextTileX, nextTileY = getHoveredBreakableTile()
					if nextTileX ~= nil and nextTileY ~= nil then
						self:setBreakInput(true, nextTileX, nextTileY)
					else
						self:setBreakInput(true, nil, nil)
					end
				else
					self:setBreakInput(false, nil, nil)
				end
			elseif targetFinished then
				self:setBreakInput(true, nil, nil)
			end
		end
	end
	if self.placeInput.isHeld then
		self.placeInput.tileX = self.cursorTileX
		self.placeInput.tileY = self.cursorTileY
	end

	local now = os.clock()
	self:flushHeldBreakInput(now)
	self:flushHeldPlaceInput(now)
	self:prunePendingPredictions()

	local previewTileX = self.cursorTileX
	local previewTileY = self.cursorTileY
	local previewCanPlace = nil :: boolean?
	local activePlaceSource = self:resolveActivePlaceSource()
	if activePlaceSource ~= nil then
		if previewTileX ~= nil and previewTileY ~= nil then
			previewCanPlace = self:canPlaceAt(previewTileX, previewTileY, activePlaceSource.config.tileId)
		end
	elseif previewTileX ~= nil and previewTileY ~= nil then
		local previewTileId = self:getTileAt(previewTileX, previewTileY, false)
		if previewTileId == BuildServiceUtils.AIR_TILE_ID then
			previewTileX = nil
			previewTileY = nil
		end
	end

	self:updatePreviewVisual(previewTileX, previewTileY, previewCanPlace)
end

function BuildServiceClient.onInputBegan(self: BuildServiceClient, inputObject: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if isPrimaryInput(inputObject) then
		self:handlePrimaryInput(true)
	end
end

function BuildServiceClient.onInputEnded(self: BuildServiceClient, inputObject: InputObject)
	if isPrimaryInput(inputObject) then
		self:handlePrimaryInput(false)
	end
end

function BuildServiceClient.bindInputRouter(self: BuildServiceClient): boolean
	local runtimeContext = CoreRuntime.getClientRuntime()
	if runtimeContext ~= nil and typeof((runtimeContext :: any).init) == "function" then
		local runtimeAny = runtimeContext :: any
		runtimeAny:init()
	end
	self.runtimeContext = runtimeContext
	if runtimeContext == nil then
		return false
	end
	local inputRouter = (runtimeContext :: any).input
	self.cursorModule = (runtimeContext :: any).cursor
	self.hapticsModule = (runtimeContext :: any).haptics
	if inputRouter == nil or typeof((inputRouter :: any).bindAction) ~= "function" then
		return false
	end
	if self.cursorModule ~= nil and typeof((self.cursorModule :: any).init) == "function" then
		local cursorAny = self.cursorModule :: any
		cursorAny:init()
	end

	local primaryBound = (inputRouter :: any):bindAction(INPUT_ACTION_PRIMARY, function(phase: string)
		if phase ~= "Began" and phase ~= "Ended" then
			return false
		end
		local startedAction = self:handlePrimaryInput(phase == "Began")
		if phase == "Began" and startedAction == BuildServiceUtils.ACTION_TYPE_BREAK then
			if self.hapticsModule ~= nil and typeof((self.hapticsModule :: any).impactLight) == "function" then
				local hapticsAny = self.hapticsModule :: any
				hapticsAny:impactLight()
			end
		end
		return false
	end, {
		layer = "Gameplay",
		consume = false,
		allowGameProcessed = false,
		allowWhileTyping = false,
		bindings = {
			{
				inputType = Enum.UserInputType.MouseButton1,
			},
			{
				inputType = Enum.UserInputType.Touch,
			},
		},
	})

	if primaryBound ~= true then
		local router = inputRouter :: any
		if typeof(router.unbindAction) == "function" then
			router:unbindAction(INPUT_ACTION_PRIMARY)
		end
		return false
	end

	self.janitor:GiveChore(function()
		local router = inputRouter :: any
		if typeof(router.unbindAction) == "function" then
			router:unbindAction(INPUT_ACTION_PRIMARY)
		end
	end)
	return true
end

function BuildServiceClient.applySelectedPlaceableConfig(self: BuildServiceClient, configRaw: any)
	local config = if typeof(configRaw) == "table" then (configRaw :: PlaceableItemConfig) else nil
	self.selectedPlaceableConfig = config
	if config ~= nil then
		self.selectedTileId = config.tileId
		return
	end

	if self:resolveActivePlaceSource() == nil then
		self:setPlaceInput(false, nil, nil)
	end
end

function BuildServiceClient.onInventoryStateChanged(self: BuildServiceClient, stateRaw: any)
	self.inventoryState = InventoryServiceUtils.sanitizeState(stateRaw, self.inventoryState)
	self:applySelectedPlaceableConfig(resolveSelectedPlaceableConfigFromInventoryState(self.inventoryState))
end

function BuildServiceClient.setSelectedTileId(self: BuildServiceClient, tileIdRaw: any)
	local tileId = BuildServiceUtils.sanitizeTileId(tileIdRaw)
	if tileId == nil or tileId == BuildServiceUtils.AIR_TILE_ID then
		return
	end
	self.selectedTileId = tileId
end

function BuildServiceClient.setBreakInput(
	self: BuildServiceClient,
	isHeldRaw: any,
	tileXRaw: any?,
	tileYRaw: any?
)
	local isHeld = BuildServiceUtils.sanitizeBoolean(isHeldRaw, false)
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	self.breakInput.isHeld = isHeld
	self.breakInput.tileX = tileX
	self.breakInput.tileY = tileY
	if not isHeld then
		self.currentBreakProgress = nil
	end
end

function BuildServiceClient.setPlaceInput(
	self: BuildServiceClient,
	isHeldRaw: any,
	tileXRaw: any?,
	tileYRaw: any?
)
	local isHeld = BuildServiceUtils.sanitizeBoolean(isHeldRaw, false)
	local tileX = BuildServiceUtils.sanitizeTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(tileYRaw)
	if self:resolveActivePlaceSource() == nil then
		isHeld = false
	end
	self.placeInput.isHeld = isHeld
	self.placeInput.tileX = tileX
	self.placeInput.tileY = tileY
end

function BuildServiceClient.applyState(self: BuildServiceClient, stateRaw: any)
	self.state = BuildServiceUtils.createState(stateRaw, self.state)
	if self.previewPart ~= nil then
		self.previewPart.Size = Vector3.new(0.08, self.state.tileSize, self.state.tileSize)
	end
	self.stateChanged:Fire(BuildServiceUtils.cloneState(self.state))
end

function BuildServiceClient.requestSync(self: BuildServiceClient)
	self.networker:fire(BuildServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function BuildServiceClient.init(self: BuildServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("BuildService", self)
	self.janitor = Janitor.new()
	self.state = BuildServiceUtils.createDefaultState()
	self.stateChanged = Signal.new()
	self.actionAccepted = Signal.new()
	self.actionRejected = Signal.new()
	self.breakProgressChanged = Signal.new()
	self.tileDeltasApplied = Signal.new()
	self.hitFeedback = Signal.new()
	self.runtimeContext = nil
	self.cursorModule = nil
	self.hapticsModule = nil
	self.inventoryState = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	self.selectedPlaceableConfig = nil :: PlaceableItemConfig?

	self.nextRequestId = 1
	self.selectedTileId = BuildServiceUtils.TILE_ID.DIRT
	self.enableDefaultInputBinding = true
	self.enableServerTileFetchFallback = false
	self.random = Random.new()
	self.treeFallSoundAssetIds = {} :: { string }
	self:refreshTreeFallSoundTemplates()
	self.predictedTileOverrides = {} :: { [string]: number }
	self.authoritativeDeltaCache = {} :: { [string]: number }
	self.pendingActions = {} :: { [number]: PendingAction }
	self.tileFetchCooldownByTileKey = {} :: { [string]: number }
	self.currentBreakProgress = nil :: { isActive: boolean, tileX: number, tileY: number, progress: number, breakDuration: number, updatedAt: number }?
	self.cursorTileX = nil :: number?
	self.cursorTileY = nil :: number?
	self.breakInput = {
		isHeld = false,
		tileX = nil,
		tileY = nil,
		lastSentAt = -math.huge,
		lastSentTileKey = nil,
	} :: HeldInputState
	self.placeInput = {
		isHeld = false,
		tileX = nil,
		tileY = nil,
		lastSentAt = -math.huge,
		lastSentTileKey = nil,
	} :: HeldInputState
	self.treeFallAnimations = {} :: { [string]: TreeFallAnimation }
	self.treeFallAnimationOrder = {} :: { string }

	self.rubble = Rubble.new({
		containerName = "BuildServiceRubble",
		partNamePrefix = "BuildRubble_",
		visualOnly = true,
		tuning = {
			initialPoolSize = 48,
			maxPoolSize = 320,
			maxImpulse = 90,
			maxVelocity = 18,
			defaultLifetime = 1.1,
			minLifetime = 0.3,
			maxLifetime = 3,
			defaultFadeOut = true,
			fadeDuration = 0.3,
			defaultCanCollide = false,
			defaultCanTouch = false,
			defaultCanQuery = false,
		},
	}) :: RubbleObject

	self:createPreviewVisual()

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
		self.actionAccepted:Destroy()
		self.actionRejected:Destroy()
		self.breakProgressChanged:Destroy()
		self.tileDeltasApplied:Destroy()
		self.hitFeedback:Destroy()
	end)
	self.janitor:GiveChore(function()
		if self.visualFolder ~= nil then
			self.visualFolder:Destroy()
		end
	end)
	self.janitor:GiveChore(function()
		if self.rubble ~= nil then
			self.rubble:Destroy()
			self.rubble = nil
		end
	end)
	self.janitor:GiveChore(RunService.RenderStepped:Connect(function(deltaTime: number)
		self:onRenderStep(deltaTime)
	end))
	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: InventoryState)
			self:onInventoryStateChanged(nextState)
		end))
	end

	if self.enableDefaultInputBinding and self:bindInputRouter() then
		self.enableDefaultInputBinding = false
	end

	if self.enableDefaultInputBinding then
		self.janitor:GiveChore(UserInputService.InputBegan:Connect(function(inputObject: InputObject, gameProcessed: boolean)
			self:onInputBegan(inputObject, gameProcessed)
		end))
		self.janitor:GiveChore(UserInputService.InputEnded:Connect(function(inputObject: InputObject)
			self:onInputEnded(inputObject)
		end))
	end

	self:onInventoryStateChanged(InventoryServiceClient.state)
	self:requestSync()
end

function BuildServiceClient.destroy(self: BuildServiceClient)
	self:setBreakInput(false, nil, nil)
	self:setPlaceInput(false, nil, nil)
	for treeId in self.treeFallAnimations do
		self:stopTreeFallAnimation(treeId, true)
	end
	table.clear(self.treeFallAnimationOrder)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
	table.clear(self.predictedTileOverrides)
	table.clear(self.authoritativeDeltaCache)
	table.clear(self.pendingActions)
	table.clear(self.tileFetchCooldownByTileKey)
	table.clear(self.treeFallAnimations)
end

function BuildServiceClient.resolveActivePlaceSource(self: BuildServiceClient): ActivePlaceSource?
	return resolveActivePlaceSourceFromInventoryState(self.inventoryState)
end

function BuildServiceClient.beginBreakInputFromCursor(self: BuildServiceClient): boolean
	local hoverTileX = self.cursorTileX
	local hoverTileY = self.cursorTileY
	if hoverTileX == nil or hoverTileY == nil then
		return false
	end
	if not self:isBreakableTarget(hoverTileX, hoverTileY) then
		return false
	end

	self:setBreakInput(true, hoverTileX, hoverTileY)
	return true
end

function BuildServiceClient.handlePrimaryInput(self: BuildServiceClient, isHeldRaw: any): string?
	local isHeld = BuildServiceUtils.sanitizeBoolean(isHeldRaw, false)
	if not isHeld then
		self:setPlaceInput(false, nil, nil)
		if not HOVER_BREAK_TEST_MODE then
			self:setBreakInput(false, nil, nil)
		end
		return nil
	end

	local activePlaceSource = self:resolveActivePlaceSource()
	if activePlaceSource ~= nil then
		self:setBreakInput(false, nil, nil)
		self:setPlaceInput(true, self.cursorTileX, self.cursorTileY)
		return BuildServiceUtils.ACTION_TYPE_PLACE
	end

	self:setPlaceInput(false, nil, nil)
	if HOVER_BREAK_TEST_MODE then
		return nil
	end
	if self:beginBreakInputFromCursor() then
		return BuildServiceUtils.ACTION_TYPE_BREAK
	end
	return nil
end

function BuildServiceClient.RequestPlaceTile(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any,
	sourceSlotRaw: any?
): number
	return self:requestPlaceTile(tileXRaw, tileYRaw, tileIdRaw, sourceSlotRaw)
end

function BuildServiceClient.RequestBreakTile(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	isBreakingRaw: any
): number
	return self:requestBreakTile(tileXRaw, tileYRaw, isBreakingRaw)
end

function BuildServiceClient.GetTileAt(self: BuildServiceClient, tileXRaw: any, tileYRaw: any): number
	return self:getTileAt(tileXRaw, tileYRaw, true)
end

function BuildServiceClient.CanPlaceAt(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any
): (boolean, string, { TileCoordinate })
	return self:canPlaceAt(tileXRaw, tileYRaw, tileIdRaw)
end

type BuildServiceClient = typeof(BuildServiceClient) & {
	runtimeContext: any?,
	cursorModule: any?,
	hapticsModule: any?,
	networker: Networker.Client,
	localPlayer: Player,
	janitor: JanitorClass,
	state: BuildServiceState,
	stateChanged: SignalObject,
	actionAccepted: SignalObject,
	actionRejected: SignalObject,
	breakProgressChanged: SignalObject,
	tileDeltasApplied: SignalObject,
	hitFeedback: SignalObject,
	inventoryState: InventoryState,
	nextRequestId: number,
	selectedTileId: number,
	selectedPlaceableConfig: PlaceableItemConfig?,
	enableServerTileFetchFallback: boolean,
	enableDefaultInputBinding: boolean,
	predictedTileOverrides: { [string]: number },
	authoritativeDeltaCache: { [string]: number },
	pendingActions: { [number]: PendingAction },
	tileFetchCooldownByTileKey: { [string]: number },
	currentBreakProgress: { isActive: boolean, tileX: number, tileY: number, progress: number, breakDuration: number, updatedAt: number }?,
	cursorTileX: number?,
	cursorTileY: number?,
	random: Random,
	treeFallSoundAssetIds: { string },
	breakInput: HeldInputState,
	placeInput: HeldInputState,
	treeFallAnimations: { [string]: TreeFallAnimation },
	treeFallAnimationOrder: { string },
	rubble: RubbleObject?,
	visualFolder: Folder,
	previewPart: Part,
	previewHighlight: Highlight,
}

return BuildServiceClient :: BuildServiceClient
