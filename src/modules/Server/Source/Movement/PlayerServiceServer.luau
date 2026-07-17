local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataTemplate = require("DataTemplate")
local GoreServiceServer = require("GoreServiceServer")
local HumanoidTeleportUtils = require("HumanoidTeleportUtils")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local PlayerServicePackets = require("NetPacketsShared").PlayerService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = PlayerServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = PlayerServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for PlayerService`)
		return
	end

	packet.listen(function(payload: any, player: Player?)
		if player == nil then
			return
		end

		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, player, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "requestState")
	bindPacket(self, "setFacing")
	bindPacket(self, "setWorldReadyForMovement")
end

local PlayerServiceUtils = require("PlayerServiceUtils")
local PlayerSpawnCooldown = require("PlayerSpawnCooldown")
local BinderSupportServer = require("BinderSupportServer")
local TagBinder = require("TagBinder")

type FacingSign = PlayerServiceUtils.FacingSign
type InvincibilityFramesConfig = PlayerServiceUtils.InvincibilityFramesConfig

type PlayerState = {
	facingSign: FacingSign,
	nextSpawnHealth: number?,
	movementLocked: boolean,
	spawnWorldPosition: Vector3?,
}

type JanitorClass = any

type PlayerRuntime = {
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
	humanoid: Humanoid?,
	effectsJunkFolder: Folder?,
	invulnerableUntil: number,
	lastKnownHealth: number?,
	lastDamageFeedbackAt: number,
	isRestoringHealth: boolean,
	highlightToken: number,
	damageHighlight: Highlight?,
	movementLockAnchoredRoot: BasePart?,
	deathFeedbackLocked: boolean,
}

type WorldGenerationObject = {
	worldOrigin: Vector3,
	tileSize: number,
	basePlaneX: number,
	minTileY: number,
	maxTileY: number,
	tileId: { [string]: number },
	GetTileAt: (self: WorldGenerationObject, tileXRaw: any, tileYRaw: any) -> (number, number),
}

type GoreServiceServerObject = {
	RegisterPlayerCharacter: (self: GoreServiceServerObject, playerRaw: any, characterRaw: any) -> boolean,
	UnregisterPlayer: (self: GoreServiceServerObject, playerRaw: any) -> boolean,
	OnPlayerDamaged: (self: GoreServiceServerObject, playerRaw: any, originRaw: any, damageRaw: any?) -> boolean,
	OnPlayerDied: (self: GoreServiceServerObject, playerRaw: any, originRaw: any) -> boolean,
}

type RagdollServiceServerObject = {
	SetPlayerRagdoll: (
		self: RagdollServiceServerObject,
		player: Player,
		enabledRaw: any,
		reasonRaw: any,
		durationRaw: any,
		canRecoverRaw: any,
		impulseRaw: any
	) -> boolean,
}

local PlayerServiceServer = {}
PlayerServiceServer.ServiceName = "PlayerServiceServer"
local DAMAGE_HIGHLIGHT_NAME = "InvincibilityFramesHighlight"
local HP_SUPPRESS_DAMAGE_FEEDBACK_ATTRIBUTE = "HpService_SuppressDamageFeedback"
local WORLD_SURFACE_SNAP_MAX_WAIT_SECONDS = 20
local WORLD_SURFACE_SNAP_RETRY_INTERVAL_SECONDS = 0.06
local WORLD_SURFACE_SNAP_RAYCAST_HEIGHT = 2048
local WORLD_SURFACE_SNAP_RAYCAST_DEPTH = WORLD_SURFACE_SNAP_RAYCAST_HEIGHT * 2
local WORLD_SURFACE_MIN_NORMAL_Y = 0.5
local WORLD_SURFACE_SNAP_SURFACE_Y_TOLERANCE = 0.75
local DAMAGE_FEEDBACK_MIN_INTERVAL = 0.12
local LOADING_SCREEN_READY_REMOTE_NAME = "AquariaLoadingScreenReady"

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getInvincibilityFramesConfigFromTemplate(): InvincibilityFramesConfig
	local template = if typeof(DataTemplate) == "table" then DataTemplate else {} :: any
	local playerData = if typeof((template :: any).playerData) == "table"
		then (template :: any).playerData
		else {} :: any
	return PlayerServiceUtils.CoerceInvincibilityFramesConfig((playerData :: any).invincibilityFrames)
end

local function getAllowMovementFreezeFromTemplate(): boolean
	local template = if typeof(DataTemplate) == "table" then DataTemplate else {} :: any
	local playerData = if typeof((template :: any).playerData) == "table"
		then (template :: any).playerData
		else {} :: any
	local allowMovementFreeze = (playerData :: any).allowMovementFreeze
	if typeof(allowMovementFreeze) == "boolean" then
		return allowMovementFreeze
	end
	return true
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("RemoteEvent") then
			return existing
		end
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getWorldNumber(world: any, key: string, fallback: number, minimum: number?): number
	local value = (world :: any)[key]
	if not isFiniteNumber(value) then
		return fallback
	end
	local Got = value :: number
	if minimum ~= nil then
		Got = math.max(minimum, Got)
	end
	return Got
end

local function getWorldTileId(world: any, tileX: number, tileY: number): number?
	local getTileAt = (world :: any).GetTileAt
	if typeof(getTileAt) ~= "function" then
		return nil
	end

	local ok, tileIdOrError = pcall(function()
		return getTileAt(world, tileX, tileY)
	end)
	if not ok or typeof(tileIdOrError) ~= "number" then
		return nil
	end
	return tileIdOrError
end

local function getGeneratedSurfaceRootPosition(
	world: WorldGenerationObject?,
	rootPart: BasePart,
	humanoid: Humanoid
): (Vector3?, number?)
	if world == nil then
		return nil, nil
	end

	local worldOrigin = if typeof((world :: any).worldOrigin) == "Vector3"
		then (world :: any).worldOrigin
		else Vector3.zero
	local tileSize = getWorldNumber(world, "tileSize", 4, 0.001)
	local basePlaneX = getWorldNumber(world, "basePlaneX", 0, nil)
	local minTileY = math.floor(getWorldNumber(world, "minTileY", -360, nil))
	local maxTileY = math.floor(getWorldNumber(world, "maxTileY", 180, nil))
	if maxTileY < minTileY then
		return nil, nil
	end

	local tileIdMap = (world :: any).tileId
	local airTileId = if typeof(tileIdMap) == "table" and typeof((tileIdMap :: any).AIR) == "number"
		then (tileIdMap :: any).AIR
		else 0
	local tileX = math.floor((rootPart.Position.Z - worldOrigin.Z) / tileSize)

	for tileY = maxTileY, minTileY, -1 do
		local tileId = getWorldTileId(world, tileX, tileY)
		if tileId == nil or tileId == airTileId then
			continue
		end

		local aboveTileId = if tileY >= maxTileY then airTileId else getWorldTileId(world, tileX, tileY + 1)
		if aboveTileId ~= nil and aboveTileId ~= airTileId then
			continue
		end

		local surfaceY = worldOrigin.Y + (tileY + 1) * tileSize
		local rootOffset = HumanoidTeleportUtils.getRootPartOffset(humanoid, rootPart)
		return Vector3.new(worldOrigin.X + basePlaneX, surfaceY + rootOffset.Y, rootPart.Position.Z), surfaceY
	end

	return nil, nil
end

function PlayerServiceServer.EmitPlayerGore(
	self: PlayerServiceServer,
	player: Player,
	humanoid: Humanoid,
	isDeathRaw: any,
	damageRaw: any?
)
	local goreService = self.goreService
	if goreService == nil then
		return
	end

	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end

	local rig = PlayerServiceUtils.GetCharacterRig(character)
	local originPart = if rig then rig.rootPart else nil
	if isDeathRaw == true then
		goreService:OnPlayerDied(player, originPart)
	else
		goreService:OnPlayerDamaged(player, originPart, damageRaw)
	end
end

function PlayerServiceServer.FireDamageFeedback(self: PlayerServiceServer, player: Player, damageAmountRaw: any)
	local runtime = self:GetRuntime(player)
	local damageAmount = if typeof(damageAmountRaw) == "number" and damageAmountRaw == damageAmountRaw
		then math.max(0, damageAmountRaw)
		else 0
	if damageAmount <= 0 then
		return
	end

	local now = os.clock()
	if now - runtime.lastDamageFeedbackAt < DAMAGE_FEEDBACK_MIN_INTERVAL then
		return
	end

	runtime.lastDamageFeedbackAt = now
	sendPacket(player, "onDamaged", damageAmount)
end

function PlayerServiceServer.Init(
	self: PlayerServiceServer,
	serviceBag: any,
	worldGenerationWorld: WorldGenerationObject?
)
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self.playerState = {}
	self.playerRuntimes = {}
	self.activeGameplayPlayers = {}
	self.loadingScreenReadyPlayers = {}
	self.worldGenerationWorld = worldGenerationWorld
	self.invincibilityFramesConfig = getInvincibilityFramesConfigFromTemplate()
	self.allowMovementFreeze = getAllowMovementFreezeFromTemplate()
	Players.CharacterAutoLoads = false
	PlayerServiceUtils.GetOrCreateWorkspaceGameFolder()
	PlayerServiceUtils.GetOrCreateWorkspacePlayersFolder()
	PlayerSpawnCooldown.ApplyConfiguredRespawnDelay()
	self.goreService = GoreServiceServer :: GoreServiceServerObject
	self.ragdollService = require("RagdollServiceServer") :: RagdollServiceServerObject
	bindPackets(self)
	local loadingScreenReadyRemote =
		ensureRemoteEvent(ReplicatedStorage, LOADING_SCREEN_READY_REMOTE_NAME) :: RemoteEvent
	self.loadingScreenReadyRemote = loadingScreenReadyRemote
	self.loadingScreenReadyConnection = loadingScreenReadyRemote.OnServerEvent:Connect(function(player, statusRaw)
		self:OnLoadingScreenReady(player, statusRaw)
	end);
	(self :: any).binders = serviceBag:GetService(BinderSupportServer)

	for _, player in Players:GetPlayers() do
		self:TrackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player)
		self:TrackPlayer(player)
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		self:UntrackPlayer(player)
	end)
end

function PlayerServiceServer.IsGameplayActiveForPlayer(self: PlayerServiceServer, player: Player): boolean
	if self.activeGameplayPlayers == nil then
		return false
	end

	return self.activeGameplayPlayers[player] == true
end

function PlayerServiceServer.OnLoadingScreenReady(self: PlayerServiceServer, player: Player, statusRaw: any): boolean
	if player.Parent ~= Players then
		return false
	end
	if self.loadingScreenReadyPlayers[player] == true then
		return true
	end

	local status = if typeof(statusRaw) == "string" then statusRaw else ""
	if status ~= "complete" and status ~= "failed" then
		return false
	end

	self.loadingScreenReadyPlayers[player] = true
	return self:EnterGameplay(player)
end

function PlayerServiceServer.EnterGameplay(self: PlayerServiceServer, player: Player): boolean
	self.activeGameplayPlayers[player] = true
	self:SetMovementLocked(player, true, true, true)

	local character = player.Character
	if character ~= nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid.Health > 0 then
			self:ApplyGameplaySpawnToCharacter(player, character)
			if self:TrySnapCharacterToWorldSurface(player, character, humanoid) then
				self:SetMovementLocked(player, false, true)
			else
				self:QueueSpawnSurfaceSnap(player, character, humanoid)
			end
			return true
		end
	end

	player:LoadCharacter()
	return true
end

function PlayerServiceServer.CreateRuntime(_self: PlayerServiceServer): PlayerRuntime
	return {
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		humanoid = nil,
		effectsJunkFolder = nil,
		invulnerableUntil = 0,
		lastKnownHealth = nil,
		lastDamageFeedbackAt = -math.huge,
		isRestoringHealth = false,
		highlightToken = 0,
		damageHighlight = nil,
		movementLockAnchoredRoot = nil,
		deathFeedbackLocked = false,
	}
end

function PlayerServiceServer.GetRuntime(self: PlayerServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime then
		return runtime
	end

	local nextRuntime = self:CreateRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function PlayerServiceServer.StopInvincibilityFrames(_self: PlayerServiceServer, runtime: PlayerRuntime)
	runtime.invulnerableUntil = 0
	runtime.highlightToken += 1
	if runtime.damageHighlight then
		runtime.damageHighlight.Enabled = false
	end
end

function PlayerServiceServer.ApplyMovementLockToRuntime(
	_self: PlayerServiceServer,
	runtime: PlayerRuntime,
	player: Player,
	movementLocked: boolean
)
	local character = player.Character
	local rootPart = PlayerServiceUtils.GetCharacterRootPart(character)
	if rootPart == nil then
		runtime.movementLockAnchoredRoot = nil
		return
	end

	if movementLocked then
		if
			runtime.movementLockAnchoredRoot
			and runtime.movementLockAnchoredRoot ~= rootPart
			and runtime.movementLockAnchoredRoot.Parent ~= nil
		then
			runtime.movementLockAnchoredRoot.Anchored = false
		end
		if not rootPart.Anchored then
			runtime.movementLockAnchoredRoot = rootPart
			rootPart.Anchored = true
		end
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		if runtime.humanoid then
			runtime.humanoid:Move(Vector3.zero, false)
		end
	else
		if runtime.movementLockAnchoredRoot == rootPart and rootPart.Parent ~= nil then
			rootPart.Anchored = false
		end
		runtime.movementLockAnchoredRoot = nil
	end
end

function PlayerServiceServer.SetMovementLocked(
	self: PlayerServiceServer,
	player: Player,
	movementLocked: boolean,
	replicateToClient: boolean?,
	forceLock: boolean?
)
	if movementLocked and not self.allowMovementFreeze and forceLock ~= true then
		movementLocked = false
	end

	local state = self:GetState(player)
	state.movementLocked = movementLocked
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, movementLocked)

	local runtime = self:GetRuntime(player)
	self:ApplyMovementLockToRuntime(runtime, player, movementLocked)

	if replicateToClient ~= false then
		sendPacket(player, PlayerServiceUtils.NETWORK_METHOD_APPLY_MOVEMENT_LOCK, movementLocked)
	end
end

function PlayerServiceServer.SetGameplaySpawnPosition(self: PlayerServiceServer, player: Player, worldPositionRaw: any)
	local state = self:GetState(player)
	if typeof(worldPositionRaw) == "Vector3" then
		state.spawnWorldPosition = worldPositionRaw
	else
		state.spawnWorldPosition = nil
	end
end

function PlayerServiceServer.ApplyGameplaySpawnToCharacter(
	self: PlayerServiceServer,
	player: Player,
	character: Model
): boolean
	local state = self:GetState(player)
	local spawnWorldPosition = state.spawnWorldPosition

	local rootPart = PlayerServiceUtils.GetCharacterRootPart(character)
	if rootPart == nil then
		return false
	end

	local targetRootPosition = spawnWorldPosition
	if typeof(targetRootPosition) ~= "Vector3" then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			targetRootPosition =
				select(1, getGeneratedSurfaceRootPosition(self.worldGenerationWorld, rootPart, humanoid))
		end
	end
	if typeof(targetRootPosition) ~= "Vector3" then
		return false
	end

	local rootToPivot = CFrame.identity
	local pivotOk, currentPivot = pcall(function(): CFrame
		return character:GetPivot()
	end)
	if pivotOk then
		rootToPivot = rootPart.CFrame:ToObjectSpace(currentPivot :: CFrame)
	end

	local targetRootCFrame =
		CFrame.lookAt(targetRootPosition, targetRootPosition + Vector3.new(0, 0, -state.facingSign), Vector3.yAxis)
	local pivotTarget = targetRootCFrame * rootToPivot
	local pivotApplied = pcall(function()
		character:PivotTo(pivotTarget)
	end)
	if not pivotApplied then
		rootPart.CFrame = targetRootCFrame
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	PlayerServiceUtils.SnapRootPartFacing(rootPart, state.facingSign)
	return true
end

function PlayerServiceServer.TrySnapCharacterToWorldSurface(
	self: PlayerServiceServer,
	player: Player,
	character: Model,
	humanoid: Humanoid
): boolean
	local rootPart = PlayerServiceUtils.GetCharacterRootPart(character)
	if rootPart == nil then
		return false
	end
	local _surfaceRootPosition, expectedSurfaceY =
		getGeneratedSurfaceRootPosition(self.worldGenerationWorld, rootPart, humanoid)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = false

	local right = rootPart.CFrame.RightVector
	local forward = rootPart.CFrame.LookVector
	local horizontalRight = Vector3.new(right.X, 0, right.Z)
	if horizontalRight.Magnitude <= 1e-4 then
		horizontalRight = Vector3.new(1, 0, 0)
	else
		horizontalRight = horizontalRight.Unit
	end
	local horizontalForward = Vector3.new(forward.X, 0, forward.Z)
	if horizontalForward.Magnitude <= 1e-4 then
		horizontalForward = Vector3.new(0, 0, 1)
	else
		horizontalForward = horizontalForward.Unit
	end

	local footprintRadius = math.max(1.25, math.max(rootPart.Size.X, rootPart.Size.Z) * 0.4)
	local sampleOffsets = {
		Vector3.zero,
		horizontalRight * footprintRadius,
		-horizontalRight * footprintRadius,
		horizontalForward * footprintRadius,
		-horizontalForward * footprintRadius,
	}

	local bestHit: RaycastResult? = nil
	for _, offset in sampleOffsets do
		local origin = rootPart.Position + offset + Vector3.new(0, WORLD_SURFACE_SNAP_RAYCAST_HEIGHT, 0)
		local direction = Vector3.new(0, -WORLD_SURFACE_SNAP_RAYCAST_DEPTH, 0)
		local hit = Workspace:Raycast(origin, direction, raycastParams)
		if hit == nil then
			continue
		end

		local hitPart = hit.Instance
		if not hitPart:IsA("BasePart") then
			continue
		end
		if not PlayerServiceUtils.IsSurfaceTerrainPart(hitPart) then
			continue
		end
		if hit.Normal.Y < WORLD_SURFACE_MIN_NORMAL_Y then
			continue
		end
		if expectedSurfaceY ~= nil and hit.Position.Y < expectedSurfaceY - WORLD_SURFACE_SNAP_SURFACE_Y_TOLERANCE then
			continue
		end

		if bestHit == nil or hit.Position.Y > bestHit.Position.Y then
			bestHit = hit
		end
	end

	if bestHit == nil then
		return false
	end

	local state = self:GetState(player)
	local position = rootPart.Position
	local rotation = rootPart.CFrame - position
	local targetY = bestHit.Position.Y + HumanoidTeleportUtils.getRootPartOffset(humanoid, rootPart).Y
	rootPart.CFrame = CFrame.new(position.X, targetY, position.Z) * rotation
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	PlayerServiceUtils.SnapRootPartFacing(rootPart, state.facingSign)
	return true
end

function PlayerServiceServer.QueueSpawnSurfaceSnap(
	self: PlayerServiceServer,
	player: Player,
	character: Model,
	humanoid: Humanoid
)
	local runtime = self:GetRuntime(player)
	task.spawn(function()
		local deadline = os.clock() + WORLD_SURFACE_SNAP_MAX_WAIT_SECONDS
		while os.clock() < deadline do
			if runtime.humanoid ~= humanoid then
				return
			end
			if character.Parent == nil then
				return
			end
			if not self:GetState(player).movementLocked then
				return
			end

			if self:TrySnapCharacterToWorldSurface(player, character, humanoid) then
				if self:GetState(player).movementLocked then
					self:SetMovementLocked(player, false, true)
				end
				return
			end

			task.wait(WORLD_SURFACE_SNAP_RETRY_INTERVAL_SECONDS)
		end
	end)
end

function PlayerServiceServer.GetOrCreateDamageHighlight(
	self: PlayerServiceServer,
	runtime: PlayerRuntime,
	character: Model
): Highlight
	local effectsJunkFolder = runtime.effectsJunkFolder
	if effectsJunkFolder == nil or effectsJunkFolder.Parent ~= character then
		effectsJunkFolder = PlayerServiceUtils.GetOrCreateEffectsJunkFolder(character)
		runtime.effectsJunkFolder = effectsJunkFolder
	end

	local existingHighlight = runtime.damageHighlight
	if existingHighlight and existingHighlight.Parent ~= nil then
		existingHighlight.Adornee = character
		existingHighlight.FillColor = Color3.new(1, 1, 1)
		existingHighlight.OutlineColor = Color3.new(1, 1, 1)
		existingHighlight.FillTransparency = self.invincibilityFramesConfig.highlightFillTransparency
		existingHighlight.OutlineTransparency = self.invincibilityFramesConfig.highlightOutlineTransparency
		existingHighlight.Parent = effectsJunkFolder
		return existingHighlight
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = DAMAGE_HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = self.invincibilityFramesConfig.highlightFillTransparency
	highlight.OutlineTransparency = self.invincibilityFramesConfig.highlightOutlineTransparency
	highlight.Enabled = false
	highlight.Parent = effectsJunkFolder
	runtime.damageHighlight = highlight
	runtime.characterJanitor:GiveChore(highlight)
	return highlight
end

function PlayerServiceServer.PlayInvincibilityFlicker(
	self: PlayerServiceServer,
	runtime: PlayerRuntime,
	humanoid: Humanoid
)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	if self.invincibilityFramesConfig.duration <= 0 then
		return
	end

	local highlight = self:GetOrCreateDamageHighlight(runtime, character)
	runtime.highlightToken += 1
	local token = runtime.highlightToken
	local flickerInterval = self.invincibilityFramesConfig.flickerInterval

	task.spawn(function()
		local isVisible = true
		while runtime.highlightToken == token do
			if runtime.humanoid ~= humanoid then
				break
			end
			if highlight.Parent == nil then
				break
			end
			if humanoid.Health <= 0 then
				break
			end
			if os.clock() >= runtime.invulnerableUntil then
				break
			end

			highlight.Enabled = isVisible
			isVisible = not isVisible
			task.wait(flickerInterval)
		end

		if runtime.highlightToken == token and highlight.Parent ~= nil then
			highlight.Enabled = false
		end
	end)
end

function PlayerServiceServer.OnHumanoidHealthChanged(
	self: PlayerServiceServer,
	player: Player,
	humanoid: Humanoid,
	nextHealthRaw: number
)
	local runtime = self:GetRuntime(player)
	if runtime.humanoid ~= humanoid then
		return
	end

	local maxHealth = math.max(1, humanoid.MaxHealth)
	local nextHealth = math.clamp(
		if typeof(nextHealthRaw) == "number" and nextHealthRaw == nextHealthRaw then nextHealthRaw else humanoid.Health,
		0,
		maxHealth
	)

	if runtime.deathFeedbackLocked then
		runtime.lastKnownHealth = 0
		self:StopInvincibilityFrames(runtime)
		return
	end

	local previousHealthRaw = runtime.lastKnownHealth
	if nextHealth <= 0 then
		local previousHealth = if previousHealthRaw ~= nil then math.clamp(previousHealthRaw, 0, maxHealth) else 0
		local damageAmount = math.max(0, previousHealth - nextHealth)
		runtime.deathFeedbackLocked = true
		runtime.lastKnownHealth = 0
		self:EmitPlayerGore(player, humanoid, true, damageAmount)
		self:FireDamageFeedback(player, damageAmount)
		self:StopInvincibilityFrames(runtime)
		return
	end

	if not PlayerServiceUtils.IsHumanoidAlive(humanoid) then
		runtime.lastKnownHealth = nextHealth
		self:StopInvincibilityFrames(runtime)
		return
	end

	if previousHealthRaw == nil then
		runtime.lastKnownHealth = nextHealth
		return
	end
	if humanoid:GetAttribute(HP_SUPPRESS_DAMAGE_FEEDBACK_ATTRIBUTE) == true then
		runtime.lastKnownHealth = nextHealth
		return
	end

	local previousHealth = math.clamp(previousHealthRaw, 0, maxHealth)
	if runtime.isRestoringHealth then
		runtime.lastKnownHealth = nextHealth
		return
	end

	if nextHealth >= previousHealth then
		runtime.lastKnownHealth = nextHealth
		return
	end

	if previousHealth <= 0 then
		runtime.lastKnownHealth = nextHealth
		return
	end

	local now = os.clock()
	if now < runtime.invulnerableUntil then
		runtime.isRestoringHealth = true
		humanoid.Health = previousHealth
		runtime.isRestoringHealth = false
		runtime.lastKnownHealth = previousHealth
		return
	end

	runtime.lastKnownHealth = nextHealth
	local appliedDamage = previousHealth - nextHealth
	self:EmitPlayerGore(player, humanoid, false, appliedDamage)
	self:FireDamageFeedback(player, appliedDamage)
	runtime.invulnerableUntil = now + self.invincibilityFramesConfig.duration
	self:PlayInvincibilityFlicker(runtime, humanoid)
end

function PlayerServiceServer.BindHumanoid(self: PlayerServiceServer, player: Player, humanoid: Humanoid)
	local runtime = self:GetRuntime(player)
	local state = self:GetState(player)
	runtime.humanoid = humanoid
	runtime.invulnerableUntil = 0
	runtime.lastDamageFeedbackAt = -math.huge
	runtime.isRestoringHealth = false
	runtime.deathFeedbackLocked = false

	local pendingHealth = state.nextSpawnHealth
	if pendingHealth ~= nil then
		humanoid.Health = math.clamp(pendingHealth, 0, math.max(1, humanoid.MaxHealth))
		state.nextSpawnHealth = nil
	end
	runtime.lastKnownHealth = math.clamp(humanoid.Health, 0, math.max(1, humanoid.MaxHealth))
	PlayerServiceUtils.ApplyCharacterSettings(humanoid)
	local character = humanoid.Parent
	if character and character:IsA("Model") then
		if self.goreService ~= nil then
			self.goreService:RegisterPlayerCharacter(player, character)
		end
		local appliedSpawn = self:ApplyGameplaySpawnToCharacter(player, character)
		if not appliedSpawn then
			local rig = PlayerServiceUtils.GetCharacterRig(character)
			if rig then
				PlayerServiceUtils.SnapRootPartFacing(rig.rootPart, state.facingSign)
			end
		end
	end
	self:ApplyMovementLockToRuntime(runtime, player, state.movementLocked)
	if character and character:IsA("Model") then
		if self:TrySnapCharacterToWorldSurface(player, character, humanoid) then
			self:SetMovementLocked(player, false, true)
		else
			self:QueueSpawnSurfaceSnap(player, character, humanoid)
		end
	end

	runtime.characterJanitor:GiveChore(humanoid.HealthChanged:Connect(function(nextHealth: number)
		if runtime.humanoid ~= humanoid then
			return
		end

		self:OnHumanoidHealthChanged(player, humanoid, nextHealth)
	end))

	runtime.characterJanitor:GiveChore(humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if runtime.humanoid ~= humanoid then
			return
		end

		runtime.lastKnownHealth = math.clamp(humanoid.Health, 0, math.max(1, humanoid.MaxHealth))
	end))

	runtime.characterJanitor:GiveChore(humanoid.Died:Connect(function()
		if runtime.humanoid ~= humanoid then
			return
		end

		runtime.deathFeedbackLocked = true
		self:StopInvincibilityFrames(runtime)
		state.nextSpawnHealth = PlayerServiceUtils.ComputeRespawnHealthFromDeath(
			humanoid.MaxHealth,
			PlayerServiceUtils.DEFAULT_DEATH_RESPAWN_HEALTH_SCALE
		)
		if self.ragdollService ~= nil then
			pcall(function()
				self.ragdollService:SetPlayerRagdoll(player, true, "Death", nil, false, nil)
			end)
		end

		if self:IsGameplayActiveForPlayer(player) then
			local respawnDelay = PlayerSpawnCooldown.GetCurrentRespawnDelay()
			task.delay(respawnDelay, function()
				if player.Parent == nil then
					return
				end
				if not self:IsGameplayActiveForPlayer(player) then
					return
				end
				local currentCharacter = player.Character
				if currentCharacter ~= nil then
					local currentHumanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
					if currentHumanoid ~= nil and currentHumanoid.Health > 0 then
						return
					end
				end
				player:LoadCharacter()
			end)
		end
	end))

	runtime.characterJanitor:GiveChore(humanoid.Destroying:Connect(function()
		if runtime.humanoid == humanoid then
			if self.goreService ~= nil then
				self.goreService:UnregisterPlayer(player)
			end
			self:StopInvincibilityFrames(runtime)
			runtime.humanoid = nil
			runtime.lastKnownHealth = nil
			runtime.deathFeedbackLocked = false
		end
	end))
end

function PlayerServiceServer.BindCharacter(self: PlayerServiceServer, player: Player, character: Model)
	local runtime = self:GetRuntime(player)
	local playersFolder = PlayerServiceUtils.GetOrCreateWorkspacePlayersFolder()
	if character.Parent ~= playersFolder then
		character.Parent = playersFolder
	end
	TagBinder.applyTag(character, TagBinder.Tags.Character)
	if self.goreService ~= nil then
		self.goreService:UnregisterPlayer(player)
	end
	self:SetMovementLocked(player, true, true, true)
	self:StopInvincibilityFrames(runtime)
	runtime.characterJanitor:Clean()
	runtime.humanoid = nil
	runtime.effectsJunkFolder = PlayerServiceUtils.GetOrCreateEffectsJunkFolder(character)
	runtime.lastKnownHealth = nil
	runtime.lastDamageFeedbackAt = -math.huge
	runtime.isRestoringHealth = false
	runtime.damageHighlight = nil
	runtime.deathFeedbackLocked = false

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self:BindHumanoid(player, humanoid)
	end

	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if runtime.humanoid ~= nil then
			return
		end
		if child:IsA("Humanoid") then
			self:BindHumanoid(player, child)
		end
	end))

	runtime.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if runtime.effectsJunkFolder == child then
			runtime.effectsJunkFolder = nil
		end
		if runtime.humanoid == child then
			self:StopInvincibilityFrames(runtime)
			runtime.humanoid = nil
			runtime.lastKnownHealth = nil
		end
	end))
end

function PlayerServiceServer.TrackPlayer(self: PlayerServiceServer, player: Player)
	local loadingReady = self.loadingScreenReadyPlayers[player] == true
	self.activeGameplayPlayers[player] = loadingReady
	self.playerState[player] = {
		facingSign = PlayerServiceUtils.DEFAULT_FACING_SIGN,
		nextSpawnHealth = nil,
		movementLocked = true,
		spawnWorldPosition = nil,
	}
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, true)

	local runtime = self:GetRuntime(player)
	runtime.playerJanitor:Clean()
	self:StopInvincibilityFrames(runtime)
	runtime.characterJanitor:Clean()
	runtime.humanoid = nil
	runtime.effectsJunkFolder = nil
	runtime.lastKnownHealth = nil
	runtime.lastDamageFeedbackAt = -math.huge
	runtime.isRestoringHealth = false
	runtime.damageHighlight = nil
	runtime.deathFeedbackLocked = false

	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		if self.loadingScreenReadyPlayers[player] ~= true then
			character:Destroy()
			return
		end

		self:BindCharacter(player, character)
	end))

	if player.Character and loadingReady then
		self:BindCharacter(player, player.Character)
	elseif player.Character then
		player.Character:Destroy()
	end

	if loadingReady then
		self:EnterGameplay(player)
	end
end

function PlayerServiceServer.UntrackPlayer(self: PlayerServiceServer, player: Player)
	self.activeGameplayPlayers[player] = nil
	self.loadingScreenReadyPlayers[player] = nil
	self.playerState[player] = nil
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, nil)
	if self.goreService ~= nil then
		self.goreService:UnregisterPlayer(player)
	end

	local runtime = self.playerRuntimes[player]
	if not runtime then
		return
	end

	if runtime.movementLockAnchoredRoot and runtime.movementLockAnchoredRoot.Parent ~= nil then
		runtime.movementLockAnchoredRoot.Anchored = false
	end
	runtime.movementLockAnchoredRoot = nil
	self:StopInvincibilityFrames(runtime)
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function PlayerServiceServer.GetState(self: PlayerServiceServer, player: Player): PlayerState
	local state = self.playerState[player]
	if state then
		return state
	end

	local defaultState: PlayerState = {
		facingSign = PlayerServiceUtils.DEFAULT_FACING_SIGN,
		nextSpawnHealth = nil,
		movementLocked = true,
		spawnWorldPosition = nil,
	}
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, true)
	self.playerState[player] = defaultState
	return defaultState
end

function PlayerServiceServer.RequestState(self: PlayerServiceServer, player: Player)
	local state = self:GetState(player)
	local runtime = self:GetRuntime(player)
	local rig = PlayerServiceUtils.GetCharacterRig(player.Character)
	if rig then
		PlayerServiceUtils.ApplyCharacterSettings(rig.humanoid)
		PlayerServiceUtils.SnapRootPartFacing(rig.rootPart, state.facingSign)
	end
	self:ApplyMovementLockToRuntime(runtime, player, state.movementLocked)
	sendPacket(player, "applyFacing", state.facingSign)
	sendPacket(player, PlayerServiceUtils.NETWORK_METHOD_APPLY_MOVEMENT_LOCK, state.movementLocked)
end

function PlayerServiceServer.SetWorldReadyForMovement(self: PlayerServiceServer, player: Player, worldReadyRaw: any)
	if typeof(worldReadyRaw) ~= "boolean" then
		return
	end

	if worldReadyRaw then
		local state = self:GetState(player)
		if not state.movementLocked then
			return
		end

		local character = player.Character
		if character == nil then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or not PlayerServiceUtils.IsHumanoidAlive(humanoid) then
			return
		end
		if not self:TrySnapCharacterToWorldSurface(player, character, humanoid) then
			return
		end
		self:SetMovementLocked(player, false, true)
	else
		self:SetMovementLocked(player, true, true, true)
	end
end

function PlayerServiceServer.SetFacing(self: PlayerServiceServer, player: Player, facingSignRaw: any)
	local state = self:GetState(player)
	local facingSign = PlayerServiceUtils.CoerceFacingSign(facingSignRaw, state.facingSign)
	state.facingSign = facingSign

	local character = player.Character
	local rig = PlayerServiceUtils.GetCharacterRig(character)
	if not rig then
		return
	end

	PlayerServiceUtils.ApplyCharacterSettings(rig.humanoid)
end

function PlayerServiceServer.Destroy(self: PlayerServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end

	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
	if self.loadingScreenReadyConnection then
		self.loadingScreenReadyConnection:Disconnect()
		self.loadingScreenReadyConnection = nil
	end

	for player, runtime in self.playerRuntimes do
		if self.goreService ~= nil then
			self.goreService:UnregisterPlayer(player)
		end
		if runtime.movementLockAnchoredRoot and runtime.movementLockAnchoredRoot.Parent ~= nil then
			runtime.movementLockAnchoredRoot.Anchored = false
		end
		runtime.movementLockAnchoredRoot = nil
		self:StopInvincibilityFrames(runtime)
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
		player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, nil)
	end
	self._serviceBag = nil
end
type PlayerServiceServer = typeof(PlayerServiceServer) & {
	_serviceBag: any?,
	isGameplayActiveForPlayer: (self: PlayerServiceServer, player: Player) -> boolean,
	onLoadingScreenReady: (self: PlayerServiceServer, player: Player, statusRaw: any) -> boolean,
	EnterGameplay: (self: PlayerServiceServer, player: Player) -> boolean,
	enterGameplay: (self: PlayerServiceServer, player: Player) -> boolean,
	setMovementLocked: (
		self: PlayerServiceServer,
		player: Player,
		movementLocked: boolean,
		replicateToClient: boolean?,
		forceLock: boolean?
	) -> (),
	setGameplaySpawnPosition: (self: PlayerServiceServer, player: Player, worldPositionRaw: any) -> (),
	applyGameplaySpawnToCharacter: (self: PlayerServiceServer, player: Player, character: Model) -> boolean,
	emitPlayerGore: (
		self: PlayerServiceServer,
		player: Player,
		humanoid: Humanoid,
		isDeathRaw: any,
		damageRaw: any?
	) -> (),
	goreService: GoreServiceServerObject?,
	ragdollService: RagdollServiceServerObject?,
	invincibilityFramesConfig: InvincibilityFramesConfig,
	allowMovementFreeze: boolean,
	worldGenerationWorld: WorldGenerationObject?,
	playerState: { [Player]: PlayerState },
	activeGameplayPlayers: { [Player]: boolean },
	loadingScreenReadyPlayers: { [Player]: boolean },
	playerRuntimes: { [Player]: PlayerRuntime },
	loadingScreenReadyRemote: RemoteEvent?,
	loadingScreenReadyConnection: RBXScriptConnection?,
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return PlayerServiceServer :: PlayerServiceServer
