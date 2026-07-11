local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AudioServiceClient = require("AudioServiceClient")
local AudioServiceUtils = require("AudioServiceUtils")
local BuildServiceClientConstants = require("BuildServiceClientConstants")
local BuildServiceUtils = require("BuildServiceUtils")
local BinderSupportClient = require("BinderSupportClient")
local CoreRuntime = require("CoreRuntime")
local GamepadPointer = require("GamepadPointer")
local GamepadTargetServiceClient = require("GamepadTargetServiceClient")
local InventoryServiceClient = require("InventoryServiceClient")
local InventoryServiceUtils = require("InventoryServiceUtils")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local BuildServicePackets = require("NetPacketsShared").BuildService

local function sendPacket(methodName: string, ...: any)
	local packet = BuildServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BuildService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = BuildServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BuildService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyState")
	bindPacket(self, "canPlaceAt")
	bindPacket(self, "getTileAt")
	bindPacket(self, "onActionResult")
	bindPacket(self, "onBreakProgress")
	bindPacket(self, "onTileFetched")
	bindPacket(self, "onTileDeltas")
	bindPacket(self, "onTreeFelled")
	bindPacket(self, "requestBreakTile")
	bindPacket(self, "requestPlaceTile")
	bindPacket(self, "requestSync")
end

local NevermoreSupport = require("NevermoreSupport")
local PlatformServiceClient = require("PlatformServiceClient")
local Ripple: any = require(ReplicatedStorage.Packages.Ripple)
local Rubble = require("Rubble")
local Signal = require("Signal")
local SnackbarNotifications = require("FeatureSnackbarNotifications")
local TagBinder = require("TagBinder")
local WorkspaceFolders = require("WorkspaceFolders")
local WorldGenerationServiceClient = require("WorldGenerationServiceClient")
local itemSlice = require("ItemSlice")

local cachedWindFoliageServiceClient = nil

local function GetWindFoliageServiceClient(): any?
	if cachedWindFoliageServiceClient ~= nil then
		return cachedWindFoliageServiceClient
	end

	local ok, moduleOrError = pcall(function()
		return require("WindFoliageServiceClient")
	end)
	if not ok then
		return nil
	end

	cachedWindFoliageServiceClient = moduleOrError
	return cachedWindFoliageServiceClient
end

type BuildServiceState = BuildServiceUtils.BuildServiceState
type PlaceableItemConfig = BuildServiceUtils.PlaceableItemConfig
type TileCoordinate = BuildServiceUtils.TileCoordinate
type TileDelta = BuildServiceUtils.TileDelta
type TreeHitResult = BuildServiceUtils.TreeHitResult
type TreeFelledPayload = BuildServiceUtils.TreeFelledPayload

local DEPLOYABLE_TILE_X_ATTRIBUTE_NAME = "DeployableTileX"
local DEPLOYABLE_TILE_Y_ATTRIBUTE_NAME = "DeployableTileY"
local TORCH_DEPLOYABLE_TAG = TagBinder.Tags.Light_Torch

local function hasTorchDeployableAtTile(tileX: number, tileY: number): boolean
	for _, tagged in TagBinder.getTagged(TORCH_DEPLOYABLE_TAG, CollectionService) do
		local taggedTileX = tagged:GetAttribute(DEPLOYABLE_TILE_X_ATTRIBUTE_NAME)
		local taggedTileY = tagged:GetAttribute(DEPLOYABLE_TILE_Y_ATTRIBUTE_NAME)
		if typeof(taggedTileX) == "number" and typeof(taggedTileY) == "number" then
			if math.floor(taggedTileX) == tileX and math.floor(taggedTileY) == tileY then
				return true
			end
		end
	end
	return false
end
type InventoryState = InventoryServiceUtils.InventoryState

type RubbleObject = {
	Spawn: (self: RubbleObject, paramsRaw: { [string]: any }?) -> BasePart?,
	Destroy: (self: RubbleObject) -> (),
}

type NumberMotion = Ripple.Motion<number>

type SignalObject = Signal.Signal<...any>

type JanitorClass = any

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

type PreviewGeometry = {
	centerPosition: Vector3,
	size: Vector3,
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

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPrimaryInput(inputObject: InputObject): boolean
	return BuildServiceClientConstants.PRIMARY_INPUT_USER_TYPES[inputObject.UserInputType] == true
end

local function CoerceInventorySlot(slotRaw: any): number?
	if typeof(slotRaw) ~= "number" or slotRaw ~= slotRaw then
		return nil
	end

	local slot = math.floor(slotRaw)
	if slot <= 0 then
		return nil
	end
	return slot
end

local function CoerceInventoryState(stateRaw: any): InventoryState
	local state = if typeof(stateRaw) == "table"
		then InventoryServiceUtils.CoerceState(
			stateRaw,
			InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
		)
		else InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	return state
end

local function GetMouseLocation(cursorModuleRaw: any): Vector2?
	if cursorModuleRaw ~= nil and typeof((cursorModuleRaw :: any).GetScreenPosition) == "function" then
		local candidate = (cursorModuleRaw :: any):GetScreenPosition()
		if typeof(candidate) == "Vector2" then
			return candidate
		end
	end

	local ok, candidate = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if ok and typeof(candidate) == "Vector2" then
		return candidate
	end

	return nil
end

local function shouldUseGamepadWorldSelection(): boolean
	return PlatformServiceClient:IsGamepad() and PlatformServiceClient:GetMachineFamily() ~= "desktop"
end

local function GetCharacterRootPart(playerRaw: any): BasePart?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local character = (playerRaw :: Player).Character
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

local function GetGamepadNav(runtimeContextRaw: any): any?
	local runtimeContext = runtimeContextRaw
	if runtimeContext == nil then
		local ok, runtimeOrError = pcall(function()
			return CoreRuntime.GetClientRuntime()
		end)
		if ok then
			runtimeContext = runtimeOrError
		end
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).Init) == "function" then
		pcall(function()
			(runtimeContext :: any):Init()
		end)
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).GetGamepadNav) == "function" then
		local ok, gamepadNavOrError = pcall(function()
			return (runtimeContext :: any):GetGamepadNav()
		end)
		if ok then
			return gamepadNavOrError
		end
	end

	if runtimeContext ~= nil then
		return (runtimeContext :: any).gamepadNav
	end

	return nil
end

local function GetGamepadScreenVector(runtimeContextRaw: any): Vector2?
	local gamepadNav = GetGamepadNav(runtimeContextRaw)
	if gamepadNav == nil or typeof((gamepadNav :: any).GetThumbstickState) ~= "function" then
		return nil
	end

	local ok, snapshotOrError = pcall(function()
		return (gamepadNav :: any):GetThumbstickState()
	end)
	if not ok or typeof(snapshotOrError) ~= "table" then
		return nil
	end

	local screenVector = GamepadPointer.GetOwnedVector(snapshotOrError)
	return if typeof(screenVector) == "Vector2" then screenVector else nil
end

local function GetIntegerAttribute(instance: Instance?, attributeName: string): number?
	if instance == nil then
		return nil
	end

	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end

	return math.floor(value)
end

local function computeFootprintBounds(
	footprintRaw: any,
	fallbackTileX: number,
	fallbackTileY: number
): (number, number, number, number)
	if typeof(footprintRaw) ~= "table" or #footprintRaw <= 0 then
		return fallbackTileX, fallbackTileX, fallbackTileY, fallbackTileY
	end

	local minTileX = math.huge
	local maxTileX = -math.huge
	local minTileY = math.huge
	local maxTileY = -math.huge
	for _, entry in footprintRaw do
		if typeof(entry) ~= "table" then
			continue
		end

		local tileX = (entry :: any).tileX
		local tileY = (entry :: any).tileY
		if typeof(tileX) == "number" and typeof(tileY) == "number" then
			minTileX = math.min(minTileX, math.floor(tileX))
			maxTileX = math.max(maxTileX, math.floor(tileX))
			minTileY = math.min(minTileY, math.floor(tileY))
			maxTileY = math.max(maxTileY, math.floor(tileY))
		end
	end

	if minTileX == math.huge then
		return fallbackTileX, fallbackTileX, fallbackTileY, fallbackTileY
	end

	return minTileX, maxTileX, minTileY, maxTileY
end

local function GetTreeRootTileNearWorldPosition(worldPosition: Vector3, radiusStudsRaw: any): (number?, number?)
	local chunksFolder = (WorldGenerationServiceClient :: any).chunksFolder
	if typeof(chunksFolder) ~= "Instance" then
		return nil, nil
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { chunksFolder }
	overlapParams.MaxParts = 24

	local searchRadius = if typeof(radiusStudsRaw) == "number" and radiusStudsRaw == radiusStudsRaw
		then math.max(1, radiusStudsRaw)
		else 1
	local success, parts = pcall(function()
		return Workspace:GetPartBoundsInRadius(worldPosition, searchRadius, overlapParams)
	end)
	if not success or type(parts) ~= "table" then
		return nil, nil
	end

	local bestDistance = math.huge
	local bestTileX = nil :: number?
	local bestTileY = nil :: number?

	for _, part in parts do
		if not part:IsA("BasePart") then
			continue
		end

		local hitModel = part:FindFirstAncestorOfClass("Model")
		local rootTileX = GetIntegerAttribute(hitModel, BuildServiceClientConstants.BUILD_TREE_ROOT_TILE_X_ATTRIBUTE)
		local rootTileY = GetIntegerAttribute(hitModel, BuildServiceClientConstants.BUILD_TREE_ROOT_TILE_Y_ATTRIBUTE)
		if rootTileX == nil or rootTileY == nil then
			continue
		end

		local distance = (part.Position - worldPosition).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestTileX = rootTileX
			bestTileY = rootTileY
		end
	end

	return bestTileX, bestTileY
end

local function GetPlaceableSourceFromInventorySlot(state: InventoryState, slotRaw: any): ActivePlaceSource?
	local slot = CoerceInventorySlot(slotRaw)
	if slot == nil then
		return nil
	end

	local stack = InventoryServiceUtils.GetStack(state, slot)
	if stack == nil or stack.amount <= 0 then
		return nil
	end

	local config = BuildServiceUtils.GetPlaceableItemConfig(stack.itemId)
	if config == nil then
		return nil
	end

	return {
		config = config,
		sourceSlot = slot,
	}
end

local function GetSelectedPlaceableSourceFromInventoryState(stateRaw: any): ActivePlaceSource?
	local state = CoerceInventoryState(stateRaw)
	if not InventoryServiceUtils.IsLoadedState(state.loadState) then
		return nil
	end

	return GetPlaceableSourceFromInventorySlot(state, state.selectedSlot)
end

local function GetSelectedPlaceableConfigFromInventoryState(stateRaw: any): PlaceableItemConfig?
	local placeSource = GetSelectedPlaceableSourceFromInventoryState(stateRaw)
	if placeSource == nil then
		return nil
	end

	return placeSource.config
end

local function GetActivePlaceSourceFromInventoryState(stateRaw: any): ActivePlaceSource?
	local state = CoerceInventoryState(stateRaw)
	if not InventoryServiceUtils.IsLoadedState(state.loadState) then
		return nil
	end

	local dragState = itemSlice.getDragState()
	if typeof(dragState) == "table" and dragState.active == true then
		if dragState.hoveredSlot ~= nil then
			return nil
		end
		return GetPlaceableSourceFromInventorySlot(state, dragState.sourceSlot)
	end

	return GetSelectedPlaceableSourceFromInventoryState(state)
end

local function GetBreakDebrisVisual(tileId: number): (Color3, Enum.Material)
	local visual = BuildServiceClientConstants.BREAK_DEBRIS_VISUALS[tileId]
	if visual == nil then
		visual = BuildServiceClientConstants.DEFAULT_BREAK_DEBRIS_VISUAL
	end
	return visual.color, visual.material
end

local function suppressChunkAnimationForBreakDelta(delta: TileDelta)
	local worldGenerationClient = WorldGenerationServiceClient :: any
	local suppressMethod = worldGenerationClient.SuppressChunkAnimationForTile
	if typeof(suppressMethod) ~= "function" then
		return
	end

	pcall(function()
		worldGenerationClient:SuppressChunkAnimationForTile(
			delta.tileX,
			delta.tileY,
			BuildServiceClientConstants.BREAK_CHUNK_ANIMATION_SKIP_SECONDS
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

local function GetSoundPlayableDuration(sound: Sound?): number?
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

function BuildServiceClient.GetTreesForChunk(self: BuildServiceClient, chunkX: number, chunkY: number): { any }?
	local chunkSnapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
	if typeof(chunkSnapshots) ~= "table" then
		return nil
	end
	local chunkKey = BuildServiceUtils.PackChunkKey(chunkX, chunkY)
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

function BuildServiceClient.GetTreeHitAtTile(self: BuildServiceClient, tileX: number, tileY: number): TreeHitResult?
	return BuildServiceUtils.GetTreeAtTile(
		tileX,
		tileY,
		self.state.chunkSize,
		function(chunkX: number, chunkY: number): { any }?
			return self:GetTreesForChunk(chunkX, chunkY)
		end
	)
end

function BuildServiceClient.IsBreakableTarget(self: BuildServiceClient, tileX: number, tileY: number): boolean
	local tileId = self:GetTileAt(tileX, tileY, false)
	if tileId ~= BuildServiceUtils.AIR_TILE_ID then
		return true
	end
	local treeHit = self:GetTreeHitAtTile(tileX, tileY)
	return treeHit ~= nil
end

function BuildServiceClient.GetTreeModelForFellEvent(self: BuildServiceClient, payload: TreeFelledPayload): Model?
	local chunkVisuals = (WorldGenerationServiceClient :: any).chunkVisuals
	if typeof(chunkVisuals) ~= "table" then
		return nil
	end

	local bestModel: Model? = nil
	local bestScore = math.huge
	local distanceBudget = self.state.tileSize * BuildServiceClientConstants.TREE_MODEL_MATCH_MAX_DISTANCE_TILES
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
			local distance = BuildServiceUtils.WorldDistance2D(modelPivot.Position, payload.pivotCFrame.Position)
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

function BuildServiceClient.RefreshTreeFallSoundTemplates(self: BuildServiceClient)
	self.treeFallSoundAssetIds = AudioServiceUtils.CollectSoundAssetIds(BuildServiceClientConstants.TREE_FALL_AUDIO)
end

function BuildServiceClient.RefreshTreeChopSoundTemplates(self: BuildServiceClient)
	self.treeChopSoundAssetIds = AudioServiceUtils.CollectSoundAssetIds(BuildServiceClientConstants.TREE_CHOP_AUDIO)
end

function BuildServiceClient.RefreshTileHitSoundTemplates(self: BuildServiceClient)
	self.tileHitSoundAssetIds = AudioServiceUtils.CollectSoundAssetIds(BuildServiceClientConstants.TILE_HIT_AUDIO)
end

function BuildServiceClient.RefreshTileBreakSoundTemplates(self: BuildServiceClient)
	self.tileBreakSoundAssetIds = AudioServiceUtils.CollectSoundAssetIds(BuildServiceClientConstants.TILE_BREAK_AUDIO)
end

function BuildServiceClient.PickTreeChopSoundAssetId(self: BuildServiceClient): string?
	if #self.treeChopSoundAssetIds <= 0 then
		self:RefreshTreeChopSoundTemplates()
	end
	local count = #self.treeChopSoundAssetIds
	if count <= 0 then
		return nil
	end
	return self.treeChopSoundAssetIds[self.random:NextInteger(1, count)]
end

function BuildServiceClient.PlayTreeChopSound(self: BuildServiceClient): boolean
	local soundAssetId = self:PickTreeChopSoundAssetId()
	if soundAssetId == nil then
		return false
	end
	if AudioServiceClient.categoryGroups == nil then
		return false
	end

	return AudioServiceClient:PlaySfx(soundAssetId, {
		parent = self.visualFolder,
		replaceChannel = false,
		autoDestroy = true,
	}) ~= nil
end

function BuildServiceClient.PickTileHitSoundAssetId(self: BuildServiceClient): string?
	if #self.tileHitSoundAssetIds <= 0 then
		self:RefreshTileHitSoundTemplates()
	end
	local count = #self.tileHitSoundAssetIds
	if count <= 0 then
		return nil
	end
	return self.tileHitSoundAssetIds[self.random:NextInteger(1, count)]
end

function BuildServiceClient.PlayTileHitSound(self: BuildServiceClient): boolean
	local soundAssetId = self:PickTileHitSoundAssetId()
	if soundAssetId == nil then
		return false
	end
	if AudioServiceClient.categoryGroups == nil then
		return false
	end

	return AudioServiceClient:PlaySfx(soundAssetId, {
		parent = self.visualFolder,
		replaceChannel = false,
		autoDestroy = true,
	}) ~= nil
end

function BuildServiceClient.PickTileBreakSoundAssetId(self: BuildServiceClient): string?
	if #self.tileBreakSoundAssetIds <= 0 then
		self:RefreshTileBreakSoundTemplates()
	end
	local count = #self.tileBreakSoundAssetIds
	if count <= 0 then
		return nil
	end
	return self.tileBreakSoundAssetIds[self.random:NextInteger(1, count)]
end

function BuildServiceClient.PlayTileBreakSound(self: BuildServiceClient): boolean
	local soundAssetId = self:PickTileBreakSoundAssetId()
	if soundAssetId == nil then
		return false
	end
	if AudioServiceClient.categoryGroups == nil then
		return false
	end

	return AudioServiceClient:PlaySfx(soundAssetId, {
		parent = self.visualFolder,
		replaceChannel = false,
		autoDestroy = true,
	}) ~= nil
end

function BuildServiceClient.PickTreeFallSoundAssetId(self: BuildServiceClient): string?
	if #self.treeFallSoundAssetIds <= 0 then
		self:RefreshTreeFallSoundTemplates()
	end
	local count = #self.treeFallSoundAssetIds
	if count <= 0 then
		return nil
	end
	return self.treeFallSoundAssetIds[self.random:NextInteger(1, count)]
end

function BuildServiceClient.ApplyTreeFallSoundSyncDuration(
	_self: BuildServiceClient,
	animation: TreeFallAnimation,
	_durationRaw: any
)
	animation.minimumFadeElapsed = 0
end

function BuildServiceClient.PlayTreeFallSound(self: BuildServiceClient, animation: TreeFallAnimation)
	local soundAssetId = self:PickTreeFallSoundAssetId()
	if soundAssetId == nil then
		return
	end

	self:ApplyTreeFallSoundSyncDuration(animation, nil)
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	local playedSound = AudioServiceClient:PlaySfx(soundAssetId, {
		parent = self.visualFolder,
		replaceChannel = false,
		autoDestroy = true,
	})
	if playedSound == nil then
		return
	end
	animation.sound = playedSound
	animation.soundFadeStarted = false

	self:ApplyTreeFallSoundSyncDuration(animation, GetSoundPlayableDuration(playedSound))
	if GetSoundPlayableDuration(playedSound) ~= nil then
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
		self:ApplyTreeFallSoundSyncDuration(animation, GetSoundPlayableDuration(playedSound))
	end)
	animation.soundLoadedConnection = loadedConnection
end

function BuildServiceClient.FadeTreeFallSoundIfPlaying(
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
		then math.max(0, fadeSecondsRaw :: number)
		else BuildServiceClientConstants.TREE_FALL_SOUND_FADE_OUT_SECONDS
	AudioServiceUtils.StopAndDestroySound(sound, fadeSeconds)
end

function BuildServiceClient.StopTreeFallAnimation(self: BuildServiceClient, treeId: string, destroyModel: boolean)
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
	self:FadeTreeFallSoundIfPlaying(animation, 0)
	animation.angleMotion:destroy()
	animation.opacityMotion:destroy()
	if destroyModel and animation.model.Parent ~= nil then
		animation.model:Destroy()
	end
end

function BuildServiceClient.BeginTreeFallFade(self: BuildServiceClient, animation: TreeFallAnimation, now: number)
	if animation.stage == "fade" then
		return
	end
	animation.stage = "fade"
	animation.fadeStartedAt = now
	self:FadeTreeFallSoundIfPlaying(animation, BuildServiceClientConstants.TREE_FALL_SOUND_FADE_OUT_SECONDS)
	animation.opacityMotion:spring(0, BuildServiceClientConstants.TREE_FADE_SPRING)
end

function BuildServiceClient.IsGroundNearWorldPoint(self: BuildServiceClient, point: Vector3): boolean
	local tileSize = math.max(0.05, self.state.tileSize)
	local tileX, tileY = BuildServiceUtils.WorldPositionToTile(point, self.state.worldOrigin, tileSize)
	local surfacePadding = tileSize * BuildServiceClientConstants.TREE_GROUND_HIT_SURFACE_PADDING_TILES

	for depth = 0, BuildServiceClientConstants.TREE_GROUND_HIT_SCAN_DEPTH_TILES do
		local scanTileY = tileY - depth
		local tileId = self:GetTileAt(tileX, scanTileY, false)
		if BuildServiceUtils.IsSolidTile(tileId) then
			local tileCenter = BuildServiceUtils.TileToWorldCenter(
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

function BuildServiceClient.HasTreeGroundImpact(
	self: BuildServiceClient,
	animation: TreeFallAnimation,
	elapsed: number,
	currentAngle: number
): boolean
	if elapsed < animation.fallDuration * BuildServiceClientConstants.TREE_GROUND_HIT_MIN_PROGRESS then
		return false
	end
	if math.abs(currentAngle) < BuildServiceClientConstants.TREE_GROUND_HIT_MIN_ANGLE then
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
	local direction = BuildServiceUtils.NormalizeFallDirection(animation.fallDirection)
	local sampleCount = BuildServiceClientConstants.TREE_GROUND_HIT_SAMPLE_COUNT

	for sampleIndex = 0, sampleCount - 1 do
		local alpha = if sampleCount <= 1 then 0 else sampleIndex / (sampleCount - 1)
		local localZ = direction * halfDepth * (0.2 + 0.8 * alpha)
		local sampleWorld = (boundsCFrame * CFrame.new(0, 0, localZ)).Position
		local probePoint = Vector3.new(sampleWorld.X, bottomY, sampleWorld.Z)
		if self:IsGroundNearWorldPoint(probePoint) then
			return true
		end
	end

	return false
end

function BuildServiceClient.SetFallenTreeCollision(_self: BuildServiceClient, treeModel: Model)
	for _, descendant in treeModel:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local nodeType = descendant:GetAttribute(BuildServiceClientConstants.TREE_NODE_TYPE_ATTRIBUTE)
		local shouldCollide = nodeType == "Trunk" or nodeType == "Branch" or nodeType == "Leaf"
		descendant.CanCollide = shouldCollide
		descendant.CanTouch = shouldCollide
		descendant.CanQuery = shouldCollide
	end
end

function BuildServiceClient.DisableFallingTreeWindFoliage(_self: BuildServiceClient, treeModel: Model)
	treeModel:SetAttribute(BuildServiceClientConstants.WIND_FOLIAGE_ENABLED_ATTRIBUTE, false)
	for _, descendant in treeModel:GetDescendants() do
		descendant:SetAttribute(BuildServiceClientConstants.WIND_FOLIAGE_ENABLED_ATTRIBUTE, false)
	end

	local windFoliageServiceClient = GetWindFoliageServiceClient()
	if windFoliageServiceClient == nil then
		return
	end

	pcall(function()
		windFoliageServiceClient:UnregisterFoliage(treeModel)
	end)
	for _, descendant in treeModel:GetDescendants() do
		pcall(function()
			windFoliageServiceClient:UnregisterFoliage(descendant)
		end)
	end
end

function BuildServiceClient.StartTreeFallAnimation(self: BuildServiceClient, payload: TreeFelledPayload)
	local treeModel = self:GetTreeModelForFellEvent(payload)
	if treeModel == nil then
		return
	end

	self:StopTreeFallAnimation(payload.treeId, true)
	self:DisableFallingTreeWindFoliage(treeModel)
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
	self:SetFallenTreeCollision(treeModel)

	local direction = BuildServiceUtils.NormalizeFallDirection(payload.fallDirection)
	local configuredFallDuration = self.random:NextNumber(
		BuildServiceClientConstants.TREE_FALL_DURATION_MIN,
		BuildServiceClientConstants.TREE_FALL_DURATION_MAX
	)
	local impactAngle = BuildServiceClientConstants.TREE_FALL_BASE_ANGLE * direction
	local overshootAngle = impactAngle + BuildServiceClientConstants.TREE_FALL_OVERSHOOT_ANGLE * direction
	local bounceAngle = impactAngle - BuildServiceClientConstants.TREE_FALL_BOUNCE_ANGLE * direction

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
		bounceDuration = BuildServiceClientConstants.TREE_BOUNCE_DURATION,
		settleDuration = BuildServiceClientConstants.TREE_SETTLE_DURATION,
		fadeDuration = BuildServiceClientConstants.TREE_FADE_DURATION,
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
	self:PlayTreeFallSound(animation)
end

function BuildServiceClient.StepTreeFallAnimations(self: BuildServiceClient, deltaTime: number)
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
			self:StopTreeFallAnimation(treeId, false)
			continue
		end

		local elapsed = now - animation.startedAt
		local nextAngle = 0
		if animation.stage == "fall" then
			local alpha = math.clamp(elapsed / math.max(0.01, animation.fallDuration), 0, 1)
			local accelerated = alpha ^ BuildServiceClientConstants.TREE_FALL_ACCELERATION_EXPONENT
			nextAngle = animation.impactAngle * accelerated
			animation.angleMotion:immediate(nextAngle)
		else
			nextAngle = animation.angleMotion:step(deltaTime)
		end

		if animation.stage == "fall" and elapsed >= animation.fallDuration then
			animation.stage = "bounce"
			animation.angleMotion:spring(animation.bounceAngle, BuildServiceClientConstants.TREE_BOUNCE_SPRING)
		elseif animation.stage == "bounce" and elapsed >= animation.fallDuration + animation.bounceDuration then
			animation.stage = "settle"
			animation.angleMotion:spring(animation.impactAngle, BuildServiceClientConstants.TREE_SETTLE_SPRING)
		end
		if not animation.groundImpactDetected and self:HasTreeGroundImpact(animation, elapsed, nextAngle) then
			animation.groundImpactDetected = true
		end
		local impactFailsafeAt = math.max(
			animation.minimumFadeElapsed,
			animation.fallDuration
				+ animation.bounceDuration
				+ animation.settleDuration
				+ BuildServiceClientConstants.TREE_GROUND_HIT_FAILSAFE_SECONDS
		)
		if animation.stage ~= "fade" then
			local canFadeOnImpact = animation.groundImpactDetected
				and animation.stage ~= "fall"
				and elapsed >= animation.fallDuration
				and elapsed >= animation.minimumFadeElapsed
			if canFadeOnImpact or elapsed >= impactFailsafeAt then
				self:BeginTreeFallFade(animation, now)
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
			self:StopTreeFallAnimation(treeId, true)
		end
	end
end

function BuildServiceClient.OnTreeFelled(self: BuildServiceClient, payloadRaw: any)
	local payload = BuildServiceUtils.CoerceTreeFelledPayload(payloadRaw)
	if payload == nil then
		return
	end
	self:StartTreeFallAnimation(payload)
end

function BuildServiceClient.CreateVisualFolder(self: BuildServiceClient): Folder
	return WorkspaceFolders.GetOrCreateFolderInGame(CLIENT_VISUALS_FOLDER_NAME)
end

function BuildServiceClient.CreatePreviewVisual(self: BuildServiceClient)
	self.visualFolder = self:CreateVisualFolder()
	for _, child in self.visualFolder:GetChildren() do
		if
			child.Name == "BuildPreview"
			or child.Name == "BuildPreviewBinder"
			or child.Name == "BuildHoverHighlight"
			or child:GetAttribute(BuildServiceClientConstants.BUILD_PREVIEW_RUNTIME_ATTRIBUTE) == true
		then
			child:Destroy()
		end
	end
	for _, descendant in self.visualFolder:GetDescendants() do
		if
			(descendant:IsA("BillboardGui") and descendant.Name == "BreakProgress")
			or (descendant:IsA("Highlight") and descendant.Name == "BuildHoverHighlight")
		then
			descendant:Destroy()
		end
	end

	local previewPart = Instance.new("Part")
	previewPart.Name = HttpService:GenerateGUID(false)
	previewPart.Anchored = true
	previewPart.CanCollide = false
	previewPart.CanTouch = false
	previewPart.CanQuery = false
	previewPart.Material = Enum.Material.ForceField
	previewPart.CastShadow = false
	previewPart.Transparency = 1
	previewPart.Size = Vector3.new(0.1, 0.1, 0.1)
	previewPart:SetAttribute(BuildServiceClientConstants.BUILD_PREVIEW_RUNTIME_ATTRIBUTE, true)
	previewPart.Parent = self.visualFolder
	TagBinder.applyTag(previewPart, TagBinder.Tags.Preview, CollectionService)
end

function BuildServiceClient.GetGamepadWorldPosition(self: BuildServiceClient): (Vector3?, Vector2?)
	local screenVector = GetGamepadScreenVector(self.runtimeContext)
	if screenVector == nil then
		return nil, nil
	end

	local rootPart = GetCharacterRootPart(self.localPlayer)
	if rootPart == nil then
		return nil, screenVector
	end

	local worldOffset = GamepadPointer.GetWorldOffsetForScreenVector(screenVector, self.state.tileSize, rootPart)
	if worldOffset == nil then
		return nil, screenVector
	end

	return rootPart.Position + worldOffset, screenVector
end

function BuildServiceClient.GetPreviewGeometry(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	footprintRaw: any?
): PreviewGeometry?
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return nil
	end

	local tileSize = math.max(0.25, self.state.tileSize)
	local minTileX, maxTileX, minTileY, maxTileY = computeFootprintBounds(footprintRaw, tileX, tileY)
	local width = maxTileX - minTileX + 1
	local height = maxTileY - minTileY + 1
	local thickness = math.max(0.12, tileSize * 0.12)
	local centerPosition = Vector3.new(
		self.state.basePlaneX + thickness * 0.5,
		self.state.worldOrigin.Y + (minTileY + height * 0.5) * tileSize,
		self.state.worldOrigin.Z + (minTileX + width * 0.5) * tileSize
	)

	return {
		centerPosition = centerPosition,
		size = Vector3.new(thickness, math.max(0.1, height * tileSize * 0.92), math.max(0.1, width * tileSize * 0.92)),
	}
end

function BuildServiceClient.GetCursorTile(self: BuildServiceClient): (number?, number?)
	if shouldUseGamepadWorldSelection() then
		local worldPosition, screenVector = self:GetGamepadWorldPosition()
		self.cursorScreenVector = screenVector
		if worldPosition ~= nil then
			local rootTileX, rootTileY =
				GetTreeRootTileNearWorldPosition(worldPosition, math.max(1, self.state.tileSize * 0.8))
			if rootTileX ~= nil and rootTileY ~= nil then
				return rootTileX, rootTileY
			end

			return BuildServiceUtils.WorldPositionToTile(worldPosition, self.state.worldOrigin, self.state.tileSize)
		end

		return nil, nil
	end

	self.cursorScreenVector = nil

	local currentCamera = Workspace.CurrentCamera
	if currentCamera == nil then
		return nil, nil
	end
	local mouseLocation = GetMouseLocation(self.cursorModule)
	if mouseLocation == nil then
		return nil, nil
	end

	local viewportRay = currentCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local chunksFolder = (WorldGenerationServiceClient :: any).chunksFolder
	if typeof(chunksFolder) == "Instance" then
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = { chunksFolder }
		raycastParams.IgnoreWater = true

		local raycastResult = Workspace:Raycast(
			viewportRay.Origin,
			viewportRay.Direction * BuildServiceClientConstants.CURSOR_VISUAL_RAYCAST_DISTANCE_STUDS,
			raycastParams
		)
		if raycastResult ~= nil then
			local hitModel = raycastResult.Instance:FindFirstAncestorOfClass("Model")
			local rootTileX = GetIntegerAttribute(hitModel, BuildServiceClientConstants.BUILD_TREE_ROOT_TILE_X_ATTRIBUTE)
			local rootTileY = GetIntegerAttribute(hitModel, BuildServiceClientConstants.BUILD_TREE_ROOT_TILE_Y_ATTRIBUTE)
			if rootTileX ~= nil and rootTileY ~= nil then
				return rootTileX, rootTileY
			end

			return BuildServiceUtils.WorldPositionToTile(
				raycastResult.Position,
				self.state.worldOrigin,
				self.state.tileSize
			)
		end
	end

	local hitOnPlane =
		BuildServiceUtils.RaycastToBuildPlane(viewportRay.Origin, viewportRay.Direction, self.state.basePlaneX)
	if hitOnPlane == nil then
		return nil, nil
	end
	local planeTileX, planeTileY =
		BuildServiceUtils.WorldPositionToTile(hitOnPlane, self.state.worldOrigin, self.state.tileSize)
	return planeTileX, planeTileY
end

function BuildServiceClient.GetTerrainHoverTile(
	self: BuildServiceClient,
	tileX: number?,
	tileY: number?
): (number?, number?)
	if tileX == nil or tileY == nil then
		return nil, nil
	end

	for depth = 0, BuildServiceClientConstants.TERRAIN_HOVER_SCAN_DEPTH_TILES do
		local scanTileY = tileY - depth
		local tileId = self:GetTileAt(tileX, scanTileY, false)
		if tileId == BuildServiceUtils.AIR_TILE_ID then
			continue
		end
		if not BuildServiceUtils.IsSolidTile(tileId) then
			continue
		end
		return tileX, scanTileY
	end

	return nil, nil
end

function BuildServiceClient.GetTileFromWorldGenerationSnapshot(
	self: BuildServiceClient,
	tileX: number,
	tileY: number
): number?
	local worldState = nil
	local getStateMethod = (WorldGenerationServiceClient :: any).GetState
	if typeof(getStateMethod) == "function" then
		local ok, resultOrError = pcall(function()
			return (WorldGenerationServiceClient :: any):GetState()
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

	local chunkSize = if isFiniteNumber((worldState :: any).chunkSize)
		then math.floor((worldState :: any).chunkSize)
		else 32
	local chunkX = BuildServiceUtils.ToChunkCoordinate(tileX, chunkSize)
	local chunkY = BuildServiceUtils.ToChunkCoordinate(tileY, chunkSize)
	local chunkSnapshots = (WorldGenerationServiceClient :: any).chunkSnapshots
	if typeof(chunkSnapshots) ~= "table" then
		return nil
	end
	local chunkKey = BuildServiceUtils.PackChunkKey(chunkX, chunkY)
	local snapshot = chunkSnapshots[chunkKey]
	if typeof(snapshot) ~= "table" then
		return nil
	end

	local tileMinX = if isFiniteNumber((snapshot :: any).tileMinX)
		then math.floor((snapshot :: any).tileMinX)
		else chunkX * chunkSize
	local tileMinY = if isFiniteNumber((snapshot :: any).tileMinY)
		then math.floor((snapshot :: any).tileMinY)
		else chunkY * chunkSize
	local width = if isFiniteNumber((snapshot :: any).width)
		then math.max(1, math.floor((snapshot :: any).width))
		else chunkSize
	local height = if isFiniteNumber((snapshot :: any).height)
		then math.max(1, math.floor((snapshot :: any).height))
		else chunkSize
	local localX = tileX - tileMinX
	local localY = tileY - tileMinY
	if localX < 0 or localX >= width or localY < 0 or localY >= height then
		return nil
	end
	local tilesRaw = (snapshot :: any).tiles
	if typeof(tilesRaw) ~= "table" then
		return nil
	end
	local index = BuildServiceUtils.ComputeTileIndex(localX, localY, width)
	local tileIdRaw = tilesRaw[index]
	if not isFiniteNumber(tileIdRaw) then
		return nil
	end
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	return tileId
end

function BuildServiceClient.GetTileAt(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	allowServerFetchRaw: any?
): number
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if tileX == nil or tileY == nil then
		return BuildServiceUtils.AIR_TILE_ID
	end
	local tileKey = BuildServiceUtils.PackTileKey(tileX, tileY)

	local predictedTileId = self.predictedTileOverrides[tileKey]
	if predictedTileId ~= nil then
		return predictedTileId
	end
	local cachedDeltaTileId = self.authoritativeDeltaCache[tileKey]
	if cachedDeltaTileId ~= nil then
		return cachedDeltaTileId
	end
	local worldTileId = self:GetTileFromWorldGenerationSnapshot(tileX, tileY)
	if worldTileId ~= nil then
		return worldTileId
	end

	local allowServerFetch = BuildServiceUtils.CoerceBoolean(allowServerFetchRaw, false)
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
	self.tileFetchCooldownByTileKey[tileKey] = now + BuildServiceClientConstants.TILE_QUERY_FETCH_COOLDOWN

	sendPacket(BuildServiceUtils.NETWORK_METHOD_GET_TILE_AT, tileX, tileY)
	return BuildServiceUtils.AIR_TILE_ID
end

function BuildServiceClient.OnTileFetched(self: BuildServiceClient, tileXRaw: any, tileYRaw: any, tileIdRaw: any)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileX == nil or tileY == nil or tileId == nil then
		return
	end

	self.authoritativeDeltaCache[BuildServiceUtils.PackTileKey(tileX, tileY)] = tileId
end

function BuildServiceClient.CanPlaceAt(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any
): (boolean, string, { TileCoordinate })
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileX == nil or tileY == nil or tileId == nil then
		return false, "invalid_tile_coordinate_or_id", {}
	end
	local placementResult = BuildServiceUtils.CanPlaceAt(
		tileX,
		tileY,
		tileId,
		function(scanX: number, scanY: number): number
			return self:GetTileAt(scanX, scanY, false)
		end,
		nil,
		nil
	)
	if placementResult.canPlace then
		for _, footprintTile in placementResult.footprint do
			if hasTorchDeployableAtTile(footprintTile.tileX, footprintTile.tileY) then
				return false, "occupied", placementResult.footprint
			end
		end
	end
	return placementResult.canPlace, placementResult.reason, placementResult.footprint
end

function BuildServiceClient.CleanupPendingAction(self: BuildServiceClient, requestId: number)
	self.pendingActions[requestId] = nil
end

function BuildServiceClient.RollbackPendingAction(self: BuildServiceClient, requestId: number)
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

function BuildServiceClient.CreatePlacePrediction(
	self: BuildServiceClient,
	requestId: number,
	tileX: number,
	tileY: number,
	tileId: number
)
	local canPlace, _, footprint = self:CanPlaceAt(tileX, tileY, tileId)
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
		local tileKey = BuildServiceUtils.PackTileKey(footprintTile.tileX, footprintTile.tileY)
		local previousTileId = self:GetTileAt(footprintTile.tileX, footprintTile.tileY, false)
		pending.predictedPreviousByTile[tileKey] = previousTileId
		pending.predictedTargetByTile[tileKey] = tileId
		self.predictedTileOverrides[tileKey] = tileId
	end
	self.pendingActions[requestId] = pending
end

function BuildServiceClient.RequestPlaceTile(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	tileIdRaw: any,
	sourceSlotRaw: any?
): number
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	local sourceSlot = CoerceInventorySlot(sourceSlotRaw)
	local requestId = self.nextRequestId
	self.nextRequestId += 1

	if tileX == nil or tileY == nil or tileId == nil then
		return requestId
	end
	self:CreatePlacePrediction(requestId, tileX, tileY, tileId)
	sendPacket(BuildServiceUtils.NETWORK_METHOD_REQUEST_PLACE_TILE, tileX, tileY, tileId, requestId, sourceSlot)
	return requestId
end

function BuildServiceClient.RequestBreakTile(
	self: BuildServiceClient,
	tileXRaw: any,
	tileYRaw: any,
	isBreakingRaw: any,
	registerHitRaw: any?
): number
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	local isBreaking = BuildServiceUtils.CoerceBoolean(isBreakingRaw, false)
	local registerHit = BuildServiceUtils.CoerceBoolean(registerHitRaw, false)
	local requestId = self.nextRequestId
	self.nextRequestId += 1
	sendPacket(BuildServiceUtils.NETWORK_METHOD_REQUEST_BREAK_TILE, tileX, tileY, isBreaking, requestId, registerHit)
	return requestId
end

function BuildServiceClient.OnTileDeltas(self: BuildServiceClient, payloadRaw: any)
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
	local playedTileBreakSound = false
	for _, deltaRaw in deltasRaw do
		local delta = BuildServiceUtils.CloneTileDelta(deltaRaw)
		if delta == nil then
			continue
		end
		local previousTileId = self:GetTileAt(delta.tileX, delta.tileY, false)
		appliedDeltas[#appliedDeltas + 1] = delta
		local tileKey = BuildServiceUtils.PackTileKey(delta.tileX, delta.tileY)
		self.authoritativeDeltaCache[tileKey] = delta.tileId
		local predictedTileId = self.predictedTileOverrides[tileKey]
		if predictedTileId ~= nil and predictedTileId == delta.tileId then
			self.predictedTileOverrides[tileKey] = nil
		end

		local isBreakDelta = delta.reason ~= nil and BuildServiceClientConstants.BREAK_DEBRIS_REASONS[delta.reason] == true
		if isBreakDelta then
			suppressChunkAnimationForBreakDelta(delta)
		end

		local shouldSpawnDebris = delta.tileId == BuildServiceUtils.AIR_TILE_ID
			and previousTileId ~= BuildServiceUtils.AIR_TILE_ID
			and isBreakDelta
		if shouldSpawnDebris then
			local isLocalBreakTarget = (
				self.breakInput.isHeld
				and self.breakInput.tileX == delta.tileX
				and self.breakInput.tileY == delta.tileY
			)
				or (
					self.currentBreakProgress ~= nil
					and self.currentBreakProgress.tileX == delta.tileX
					and self.currentBreakProgress.tileY == delta.tileY
				)
				or (self.cursorTileX == delta.tileX and self.cursorTileY == delta.tileY)
			if isLocalBreakTarget and not playedTileBreakSound then
				playedTileBreakSound = self:PlayTileBreakSound()
			end
			if debrisTilesSpawned < BuildServiceClientConstants.MAX_BREAK_DEBRIS_TILES_PER_BATCH then
				debrisTilesSpawned += 1
				self:SpawnBreakDebris(delta.tileX, delta.tileY, previousTileId)
			end
		end
	end

	if #appliedDeltas > 0 then
		self.tileDeltasApplied:Fire(appliedDeltas)
	end
end

local function spawnDebrisBurst(
	self,
	tileX: number,
	tileY: number,
	tileId: number,
	shardCountMin: number,
	shardCountMax: number,
	shardScaleMin: number,
	shardScaleMax: number,
	horizontalImpulseMax: number,
	verticalImpulseMin: number,
	verticalImpulseMax: number,
	depthImpulseMax: number,
	lifetimeMin: number,
	lifetimeMax: number
)
	if self.rubble == nil then
		return
	end
	local color, material = GetBreakDebrisVisual(tileId)
	local tileCenter = BuildServiceUtils.TileToWorldCenter(
		tileX,
		tileY,
		self.state.worldOrigin,
		self.state.tileSize,
		self.state.basePlaneX
	)
	local halfTile = self.state.tileSize * 0.5
	local shardCount = self.random:NextInteger(shardCountMin, shardCountMax)
	for _ = 1, shardCount do
		local shardSize = self.state.tileSize * self.random:NextNumber(shardScaleMin, shardScaleMax)
		local spawnOffset = Vector3.new(
			self.random:NextNumber(-0.02, 0.02),
			self.random:NextNumber(-halfTile * 0.2, halfTile * 0.2),
			self.random:NextNumber(-halfTile * 0.2, halfTile * 0.2)
		)
		local impulse = Vector3.new(
			self.random:NextNumber(-horizontalImpulseMax, horizontalImpulseMax),
			self.random:NextNumber(verticalImpulseMin, verticalImpulseMax),
			self.random:NextNumber(-depthImpulseMax, depthImpulseMax)
		)
		self.rubble:Spawn({
			CFrame = CFrame.new(tileCenter + spawnOffset),
			Size = Vector3.new(shardSize, shardSize, shardSize),
			Color = color,
			Material = material,
			Transparency = 0,
			Anchored = false,
			CanCollide = true,
			CanTouch = false,
			CanQuery = false,
			Impulse = impulse,
			EnableGravity = true,
			CanFling = false,
			FadeOut = true,
			Lifetime = self.random:NextNumber(lifetimeMin, lifetimeMax),
			Mirror = false,
		})
	end
end

function BuildServiceClient.SpawnHitDebris(self: BuildServiceClient, tileX: number, tileY: number, tileId: number)
	spawnDebrisBurst(self :: any, tileX, tileY, tileId, 1, 2, 0.12, 0.24, 0.55, 0.18, 0.7, 0.85, 0.3, 0.55)
end

function BuildServiceClient.SpawnBreakDebris(self: BuildServiceClient, tileX: number, tileY: number, tileId: number)
	spawnDebrisBurst(self :: any, tileX, tileY, tileId, 4, 7, 0.18, 0.4, 1.15, 0.45, 1.55, 1.7, 0.55, 1.05)
end

function BuildServiceClient.PlayHoveredTileBreakFeedback(self: BuildServiceClient): boolean
	if not self.breakInput.isHeld then
		return false
	end

	local targetTileX = self.breakInput.tileX
	local targetTileY = self.breakInput.tileY
	if targetTileX == nil or targetTileY == nil then
		return false
	end
	if self.cursorTileX ~= targetTileX or self.cursorTileY ~= targetTileY then
		return false
	end

	local tileId = self:GetTileAt(targetTileX, targetTileY, false)
	if tileId == BuildServiceUtils.AIR_TILE_ID then
		return false
	end

	self:PlayTileHitSound()
	self:SpawnHitDebris(targetTileX, targetTileY, tileId)
	self:RequestBreakTile(targetTileX, targetTileY, true, true)
	return true
end

function BuildServiceClient.PlayHoveredTreeChopFeedback(self: BuildServiceClient): boolean
	if not self.breakInput.isHeld then
		return false
	end

	local targetTileX = self.breakInput.tileX
	local targetTileY = self.breakInput.tileY
	if targetTileX == nil or targetTileY == nil then
		return false
	end
	if self.cursorTileX ~= targetTileX or self.cursorTileY ~= targetTileY then
		return false
	end

	local treeHit = self:GetTreeHitAtTile(targetTileX, targetTileY)
	if treeHit == nil then
		return false
	end

	self:PlayTreeChopSound()
	self:SpawnHitDebris(targetTileX, targetTileY, BuildServiceUtils.TILE_ID.WOOD)
	self:RequestBreakTile(targetTileX, targetTileY, true, true)
	return true
end

function BuildServiceClient.OnActionResult(self: BuildServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local requestId = BuildServiceUtils.CoerceRequestId(payload.requestId)
	local accepted = payload.accepted == true
	local reason = if typeof(payload.reason) == "string" then payload.reason else "unknown"

	local pending = self.pendingActions[requestId]
	if pending ~= nil then
		if not accepted then
			self:RollbackPendingAction(requestId)
		else
			self:CleanupPendingAction(requestId)
		end
	end

	if not accepted then
		SnackbarNotifications.ShowBuildActionRejected(payload.actionType, reason)
		self.actionRejected:Fire(payload.actionType, reason, requestId)
		return
	end

	if typeof(payload.deltas) == "table" then
		self:OnTileDeltas({
			deltas = payload.deltas,
		})
	end
	self.actionAccepted:Fire(payload.actionType, reason, requestId)
end

function BuildServiceClient.OnBreakProgress(self: BuildServiceClient, payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		return
	end
	local payload = payloadRaw :: { [string]: any }
	local tileX = BuildServiceUtils.CoerceTileCoordinate(payload.tileX)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(payload.tileY)
	local progressRaw = payload.progress
	local breakDurationRaw = payload.breakDuration
	local progressModeRaw = payload.progressMode
	local progressUnitsRaw = payload.progressUnits
	local progressTotalRaw = payload.progressTotal
	local targetKindRaw = payload.targetKind
	local progress = if isFiniteNumber(progressRaw) then math.clamp(progressRaw, 0, 1) else 0
	local breakDuration = if isFiniteNumber(breakDurationRaw) then math.max(0, breakDurationRaw) else 0
	local progressMode = if typeof(progressModeRaw) == "string" then progressModeRaw else nil
	local progressUnits = if isFiniteNumber(progressUnitsRaw) then math.max(0, progressUnitsRaw) else nil
	local progressTotal = if isFiniteNumber(progressTotalRaw) then math.max(0, progressTotalRaw) else nil
	local targetKind = if typeof(targetKindRaw) == "string" then targetKindRaw else nil
	local isActive = payload.isActive == true and tileX ~= nil and tileY ~= nil

	if isActive then
		self.currentBreakProgress = {
			isActive = true,
			tileX = tileX :: number,
			tileY = tileY :: number,
			progress = progress,
			breakDuration = breakDuration,
			progressMode = progressMode,
			progressUnits = progressUnits,
			progressTotal = progressTotal,
			targetKind = targetKind,
			updatedAt = os.clock(),
		}
		self.hitFeedback:Fire(tileX, tileY, progress)
	else
		self.currentBreakProgress = nil
	end
	self.breakProgressChanged:Fire(self.currentBreakProgress)
end

function BuildServiceClient.UpdatePreviewVisual(
	self: BuildServiceClient,
	tileX: number?,
	tileY: number?,
	_canPlace: boolean?,
	footprintRaw: any?
)
	local setHoveredTerrainTile = (WorldGenerationServiceClient :: any).SetHoveredTerrainTile
	if typeof(setHoveredTerrainTile) == "function" then
		(WorldGenerationServiceClient :: any):SetHoveredTerrainTile(tileX, tileY)
	end

	if not shouldUseGamepadWorldSelection() then
		GamepadTargetServiceClient.SetTarget(nil, nil)
		return
	end

	local previewGeometry = self:GetPreviewGeometry(tileX, tileY, footprintRaw)
	local targetWorldPosition = if previewGeometry ~= nil then previewGeometry.centerPosition else nil
	GamepadTargetServiceClient.SetTarget(targetWorldPosition, self.cursorScreenVector)
end

function BuildServiceClient.PrunePendingPredictions(self: BuildServiceClient)
	local now = os.clock()
	for requestId, pending in self.pendingActions do
		if now - pending.createdAt <= BuildServiceClientConstants.PREDICTION_TTL_SECONDS then
			continue
		end
		self:CleanupPendingAction(requestId)
	end
end

function BuildServiceClient.UpdateCursorTile(self: BuildServiceClient)
	local cursorTileX, cursorTileY = self:GetCursorTile()
	self.cursorTileX = cursorTileX
	self.cursorTileY = cursorTileY
end

function BuildServiceClient.ApplyHoverBreakInput(self: BuildServiceClient)
	local cursorTileX = self.cursorTileX
	local cursorTileY = self.cursorTileY
	if cursorTileX == nil or cursorTileY == nil then
		self:SetBreakInput(false, nil, nil)
		return
	end
	local shouldBreak = self:IsBreakableTarget(cursorTileX, cursorTileY)
	self:SetBreakInput(shouldBreak, cursorTileX, cursorTileY)
end

function BuildServiceClient.FlushHeldBreakInput(self: BuildServiceClient, now: number)
	local state = self.breakInput
	if not state.isHeld then
		if state.lastSentTileKey ~= nil then
			sendPacket(BuildServiceUtils.NETWORK_METHOD_REQUEST_BREAK_TILE, state.tileX, state.tileY, false, 0, false)
			state.lastSentTileKey = nil
		end
		return
	end
	if state.tileX == nil or state.tileY == nil then
		return
	end

	local tileKey = BuildServiceUtils.PackTileKey(state.tileX, state.tileY)
	if state.lastSentTileKey == tileKey and now - state.lastSentAt < self.state.clientBreakInputRate then
		return
	end
	state.lastSentAt = now
	state.lastSentTileKey = tileKey
	sendPacket(BuildServiceUtils.NETWORK_METHOD_REQUEST_BREAK_TILE, state.tileX, state.tileY, true, 0, false)
end

function BuildServiceClient.FlushHeldPlaceInput(self: BuildServiceClient, now: number)
	local state = self.placeInput
	if not state.isHeld then
		return
	end
	local activePlaceSource = self:GetActivePlaceSource()
	if activePlaceSource == nil then
		self:SetPlaceInput(false, nil, nil)
		return
	end
	if state.tileX == nil or state.tileY == nil then
		return
	end
	if now - state.lastSentAt < self.state.clientPlaceInputRate then
		return
	end

	local tileId = activePlaceSource.config.tileId
	local canPlace = self:CanPlaceAt(state.tileX, state.tileY, tileId)
	if not canPlace then
		return
	end
	state.lastSentAt = now
	self:RequestPlaceTile(state.tileX, state.tileY, tileId, activePlaceSource.sourceSlot)
end

function BuildServiceClient.OnRenderStep(self: BuildServiceClient, _deltaTime: number)
	self:StepTreeFallAnimations(_deltaTime)
	self:UpdateCursorTile()

	if BuildServiceClientConstants.HOVER_BREAK_TEST_MODE then
		self:ApplyHoverBreakInput()
	elseif self.breakInput.isHeld then
		local hoverTileX = self.cursorTileX
		local hoverTileY = self.cursorTileY
		local targetTileX = self.breakInput.tileX
		local targetTileY = self.breakInput.tileY

		local function getHoveredBreakableTile(): (number?, number?)
			if hoverTileX == nil or hoverTileY == nil then
				return nil, nil
			end
			if not self:IsBreakableTarget(hoverTileX, hoverTileY) then
				return nil, nil
			end
			return hoverTileX, hoverTileY
		end

		if targetTileX == nil or targetTileY == nil then
			local nextTileX, nextTileY = getHoveredBreakableTile()
			if nextTileX ~= nil and nextTileY ~= nil then
				self:SetBreakInput(true, nextTileX, nextTileY)
			end
		else
			local currentBreakProgress = self.currentBreakProgress
			local finishedByProgress = currentBreakProgress ~= nil
				and currentBreakProgress.tileX == targetTileX
				and currentBreakProgress.tileY == targetTileY
				and currentBreakProgress.progress >= 0.99
			local targetFinished = (not self:IsBreakableTarget(targetTileX, targetTileY)) or finishedByProgress

			if hoverTileX ~= targetTileX or hoverTileY ~= targetTileY then
				if targetFinished then
					local nextTileX, nextTileY = getHoveredBreakableTile()
					if nextTileX ~= nil and nextTileY ~= nil then
						self:SetBreakInput(true, nextTileX, nextTileY)
					else
						self:SetBreakInput(true, nil, nil)
					end
				else
					self:SetBreakInput(false, nil, nil)
				end
			elseif targetFinished then
				self:SetBreakInput(true, nil, nil)
			end
		end
	end
	if self.placeInput.isHeld then
		self.placeInput.tileX = self.cursorTileX
		self.placeInput.tileY = self.cursorTileY
	end

	local now = os.clock()
	self:FlushHeldBreakInput(now)
	self:FlushHeldPlaceInput(now)
	self:PrunePendingPredictions()

	local previewTileX = self.cursorTileX
	local previewTileY = self.cursorTileY
	local previewCanPlace = nil :: boolean?
	local previewFootprint = {} :: { TileCoordinate }
	local activePlaceSource = self:GetActivePlaceSource()
	if activePlaceSource ~= nil then
		previewTileX, previewTileY = self:GetTerrainHoverTile(previewTileX, previewTileY)
		if previewTileX ~= nil and previewTileY ~= nil then
			local canPlace, _, GotFootprint =
				self:CanPlaceAt(previewTileX, previewTileY, activePlaceSource.config.tileId)
			previewCanPlace = canPlace
			previewFootprint = GotFootprint
		end
	elseif previewTileX ~= nil and previewTileY ~= nil then
		local previewTileId = self:GetTileAt(previewTileX, previewTileY, false)
		if previewTileId == BuildServiceUtils.AIR_TILE_ID then
			previewTileX = nil
			previewTileY = nil
		end
	end

	self:UpdatePreviewVisual(previewTileX, previewTileY, previewCanPlace, previewFootprint)
end

function BuildServiceClient.OnInputBegan(self: BuildServiceClient, inputObject: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if isPrimaryInput(inputObject) then
		self:HandlePrimaryInput(true)
	end
end

function BuildServiceClient.OnInputEnded(self: BuildServiceClient, inputObject: InputObject)
	if isPrimaryInput(inputObject) then
		self:HandlePrimaryInput(false)
	end
end

function BuildServiceClient.BindInputRouter(self: BuildServiceClient): boolean
	local runtimeContext = CoreRuntime.GetClientRuntime()
	if runtimeContext ~= nil and typeof((runtimeContext :: any).Init) == "function" then
		local runtimeAny = runtimeContext :: any
		runtimeAny:Init()
	end
	self.runtimeContext = runtimeContext
	if runtimeContext == nil then
		return false
	end
	self.cursorModule = (runtimeContext :: any).cursor
	self.hapticsModule = (runtimeContext :: any).haptics
	if not PlatformServiceClient:IsReady() then
		PlatformServiceClient:Init()
	end
	if self.cursorModule ~= nil and typeof((self.cursorModule :: any).Init) == "function" then
		local cursorAny = self.cursorModule :: any
		cursorAny:Init()
	end

	local disconnect = PlatformServiceClient:BindAction(
		BuildServiceClientConstants.INPUT_ACTION_PRIMARY,
		function(phase: string)
			if phase ~= "Began" and phase ~= "Ended" then
				return false
			end
			local startedAction = self:HandlePrimaryInput(phase == "Began")
			if phase == "Began" and startedAction == BuildServiceUtils.ACTION_TYPE_BREAK then
				if self.hapticsModule ~= nil and typeof((self.hapticsModule :: any).ImpactLight) == "function" then
					local hapticsAny = self.hapticsModule :: any
					hapticsAny:ImpactLight()
				end
			end
			return false
		end
	)

	if disconnect == nil then
		return false
	end

	self.janitor:GiveChore(disconnect)
	return true
end

function BuildServiceClient.ApplySelectedPlaceableConfig(self: BuildServiceClient, configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw :: PlaceableItemConfig else nil
	self.selectedPlaceableConfig = config
	if config ~= nil then
		self.selectedTileId = config.tileId
		return
	end

	if self:GetActivePlaceSource() == nil then
		self:SetPlaceInput(false, nil, nil)
	end
end

function BuildServiceClient.OnInventoryStateChanged(self: BuildServiceClient, stateRaw: any)
	self.inventoryState = InventoryServiceUtils.CoerceState(stateRaw, self.inventoryState)
	self:ApplySelectedPlaceableConfig(GetSelectedPlaceableConfigFromInventoryState(self.inventoryState))
end

function BuildServiceClient.SetSelectedTileId(self: BuildServiceClient, tileIdRaw: any)
	local tileId = BuildServiceUtils.CoerceTileId(tileIdRaw)
	if tileId == nil or tileId == BuildServiceUtils.AIR_TILE_ID then
		return
	end
	self.selectedTileId = tileId
end

function BuildServiceClient.SetBreakInput(self: BuildServiceClient, isHeldRaw: any, tileXRaw: any?, tileYRaw: any?)
	local isHeld = BuildServiceUtils.CoerceBoolean(isHeldRaw, false)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	self.breakInput.isHeld = isHeld
	self.breakInput.tileX = tileX
	self.breakInput.tileY = tileY
	if not isHeld then
		self.currentBreakProgress = nil
	end
end

function BuildServiceClient.SetPlaceInput(self: BuildServiceClient, isHeldRaw: any, tileXRaw: any?, tileYRaw: any?)
	local isHeld = BuildServiceUtils.CoerceBoolean(isHeldRaw, false)
	local tileX = BuildServiceUtils.CoerceTileCoordinate(tileXRaw)
	local tileY = BuildServiceUtils.CoerceTileCoordinate(tileYRaw)
	if self:GetActivePlaceSource() == nil then
		isHeld = false
	end
	self.placeInput.isHeld = isHeld
	self.placeInput.tileX = tileX
	self.placeInput.tileY = tileY
end

function BuildServiceClient.ApplyState(self: BuildServiceClient, stateRaw: any)
	self.state = BuildServiceUtils.CreateState(stateRaw, self.state)
	self.stateChanged:Fire(BuildServiceUtils.CloneState(self.state))
end

function BuildServiceClient.RequestSync(self: BuildServiceClient)
	sendPacket(BuildServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function BuildServiceClient.Init(self: BuildServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.state = BuildServiceUtils.CreateDefaultState()
	self.stateChanged = Signal.new()
	self.actionAccepted = Signal.new()
	self.actionRejected = Signal.new()
	self.breakProgressChanged = Signal.new()
	self.tileDeltasApplied = Signal.new()
	self.hitFeedback = Signal.new()
	self.runtimeContext = nil
	self.cursorModule = nil
	self.hapticsModule = nil
	self.inventoryState = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED)
	self.selectedPlaceableConfig = nil :: PlaceableItemConfig?

	self.nextRequestId = 1
	self.selectedTileId = BuildServiceUtils.TILE_ID.DIRT
	self.enableDefaultInputBinding = true
	self.enableServerTileFetchFallback = false
	self.random = Random.new()
	self.treeChopSoundAssetIds = {} :: { string }
	self:RefreshTreeChopSoundTemplates()
	self.treeFallSoundAssetIds = {} :: { string }
	self:RefreshTreeFallSoundTemplates()
	self.tileHitSoundAssetIds = {} :: { string }
	self:RefreshTileHitSoundTemplates()
	self.tileBreakSoundAssetIds = {} :: { string }
	self:RefreshTileBreakSoundTemplates()
	self.predictedTileOverrides = {} :: { [string]: number }
	self.authoritativeDeltaCache = {} :: { [string]: number }
	self.pendingActions = {} :: { [number]: PendingAction }
	self.tileFetchCooldownByTileKey = {} :: { [string]: number }
	self.currentBreakProgress = nil :: {
		isActive: boolean,
		tileX: number,
		tileY: number,
		progress: number,
		breakDuration: number,
		progressMode: string?,
		progressUnits: number?,
		progressTotal: number?,
		targetKind: string?,
		updatedAt: number,
	}?
	self.cursorTileX = nil :: number?
	self.cursorTileY = nil :: number?
	self.cursorScreenVector = nil :: Vector2?
	GamepadTargetServiceClient.ClearTarget()
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

	self.rubble = Rubble.New({
		containerName = "BuildServiceRubble",
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
			defaultCanCollide = true,
			defaultCanTouch = false,
			defaultCanQuery = false,
		},
	}) :: RubbleObject

	self.binders = NevermoreSupport.GetService(BinderSupportClient)
	self:CreatePreviewVisual()
	local clearHoveredTerrainTile = (WorldGenerationServiceClient :: any).ClearHoveredTerrainTile
	if typeof(clearHoveredTerrainTile) == "function" then
		(WorldGenerationServiceClient :: any):ClearHoveredTerrainTile()
	end

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
		self:OnRenderStep(deltaTime)
	end))
	if InventoryServiceClient.stateChanged ~= nil then
		self.janitor:GiveChore(InventoryServiceClient.stateChanged:Connect(function(nextState: InventoryState)
			self:OnInventoryStateChanged(nextState)
		end))
	end

	if self.enableDefaultInputBinding and self:BindInputRouter() then
		self.enableDefaultInputBinding = false
	end

	if self.enableDefaultInputBinding then
		self.janitor:GiveChore(
			UserInputService.InputBegan:Connect(function(inputObject: InputObject, gameProcessed: boolean)
				self:OnInputBegan(inputObject, gameProcessed)
			end)
		)
		self.janitor:GiveChore(UserInputService.InputEnded:Connect(function(inputObject: InputObject)
			self:OnInputEnded(inputObject)
		end))
	end

	self:OnInventoryStateChanged(InventoryServiceClient.state)
	self:RequestSync()
end

function BuildServiceClient.Destroy(self: BuildServiceClient)
	self:SetBreakInput(false, nil, nil)
	self:SetPlaceInput(false, nil, nil)
	GamepadTargetServiceClient.ClearTarget()
	local clearHoveredTerrainTile = (WorldGenerationServiceClient :: any).ClearHoveredTerrainTile
	if typeof(clearHoveredTerrainTile) == "function" then
		(WorldGenerationServiceClient :: any):ClearHoveredTerrainTile()
	end
	for treeId in pairs(self.treeFallAnimations :: { [string]: TreeFallAnimation }) do
		self:StopTreeFallAnimation(treeId, true)
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

function BuildServiceClient.GetActivePlaceSource(self: BuildServiceClient): ActivePlaceSource?
	return GetActivePlaceSourceFromInventoryState(self.inventoryState)
end

function BuildServiceClient.BeginBreakInputFromCursor(self: BuildServiceClient): boolean
	local hoverTileX = self.cursorTileX
	local hoverTileY = self.cursorTileY
	if hoverTileX == nil or hoverTileY == nil then
		return false
	end
	if not self:IsBreakableTarget(hoverTileX, hoverTileY) then
		return false
	end

	self:SetBreakInput(true, hoverTileX, hoverTileY)
	return true
end

function BuildServiceClient.HandlePrimaryInput(self: BuildServiceClient, isHeldRaw: any): string?
	local isHeld = BuildServiceUtils.CoerceBoolean(isHeldRaw, false)
	if not isHeld then
		self:SetPlaceInput(false, nil, nil)
		if not BuildServiceClientConstants.HOVER_BREAK_TEST_MODE then
			self:SetBreakInput(false, nil, nil)
		end
		return nil
	end

	local activePlaceSource = self:GetActivePlaceSource()
	if activePlaceSource ~= nil then
		self:SetBreakInput(false, nil, nil)
		self:SetPlaceInput(true, self.cursorTileX, self.cursorTileY)
		return BuildServiceUtils.ACTION_TYPE_PLACE
	end

	self:SetPlaceInput(false, nil, nil)
	if BuildServiceClientConstants.HOVER_BREAK_TEST_MODE then
		return nil
	end
	if self:BeginBreakInputFromCursor() then
		return BuildServiceUtils.ACTION_TYPE_BREAK
	end
	return nil
end
type BuildServiceClient = any

return BuildServiceClient :: BuildServiceClient
