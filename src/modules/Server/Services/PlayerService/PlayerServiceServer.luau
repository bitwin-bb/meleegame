--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ServerBinderSupport = require(script:FindFirstAncestor("game").Server.Binders.ServerBinderSupport)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)
local PlayerServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerService.PlayerServiceUtils)
local DataTemplate = require(script:FindFirstAncestor("game").Shared.Modules.Core.DataTemplate)
local PlayerSpawnCooldown = require(script:FindFirstAncestor("game").Shared.Modules.Game.Player.PlayerSpawnCooldown)
local GoreServiceServer = require(script:FindFirstAncestor("game").Server.Services.GoreService.GoreServiceServer)

type FacingSign = PlayerServiceUtils.FacingSign
type InvincibilityFramesConfig = PlayerServiceUtils.InvincibilityFramesConfig

type PlayerState = {
	facingSign: FacingSign,
	nextSpawnHealth: number?,
	movementLocked: boolean,
	spawnWorldPosition: Vector3?,
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

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

type GoreServiceServerObject = {
	registerPlayerCharacter: (self: GoreServiceServerObject, playerRaw: any, characterRaw: any) -> boolean,
	unregisterPlayer: (self: GoreServiceServerObject, playerRaw: any) -> boolean,
	onPlayerDamaged: (self: GoreServiceServerObject, playerRaw: any, originRaw: any, damageRaw: any?) -> boolean,
	onPlayerDied: (self: GoreServiceServerObject, playerRaw: any, originRaw: any) -> boolean,
}

type RagdollServiceServerObject = {
	setPlayerRagdoll: (
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
local DAMAGE_HIGHLIGHT_NAME = "InvincibilityFramesHighlight"
local HP_SUPPRESS_DAMAGE_FEEDBACK_ATTRIBUTE = "HpService_SuppressDamageFeedback"
local WORLD_SURFACE_SNAP_MAX_WAIT_SECONDS = 20
local WORLD_SURFACE_SNAP_RETRY_INTERVAL_SECONDS = 0.06
local WORLD_SURFACE_SNAP_RAYCAST_HEIGHT = 2048
local WORLD_SURFACE_SNAP_RAYCAST_DEPTH = WORLD_SURFACE_SNAP_RAYCAST_HEIGHT * 2
local WORLD_SURFACE_MIN_NORMAL_Y = 0.5
local DAMAGE_FEEDBACK_MIN_INTERVAL = 0.12

local function resolveInvincibilityFramesConfigFromTemplate(): InvincibilityFramesConfig
	local template = if typeof(DataTemplate) == "table" then DataTemplate else {}
	local playerData = if typeof((template :: any).playerData) == "table" then (template :: any).playerData else {}
	return PlayerServiceUtils.sanitizeInvincibilityFramesConfig((playerData :: any).invincibilityFrames)
end

local function resolveAllowMovementFreezeFromTemplate(): boolean
	local template = if typeof(DataTemplate) == "table" then DataTemplate else {}
	local playerData = if typeof((template :: any).playerData) == "table" then (template :: any).playerData else {}
	local allowMovementFreeze = (playerData :: any).allowMovementFreeze
	if typeof(allowMovementFreeze) == "boolean" then
		return allowMovementFreeze
	end
	return true
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

	local rig = PlayerServiceUtils.resolveCharacterRig(character)
	local originPart = if rig then rig.rootPart else nil
	if isDeathRaw == true then
		goreService:onPlayerDied(player, originPart)
	else
		goreService:onPlayerDamaged(player, originPart, damageRaw)
	end
end

function PlayerServiceServer.FireDamageFeedback(self: PlayerServiceServer, player: Player, damageAmountRaw: any)
	local runtime = self:getRuntime(player)
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
	self.networker:fire(player, "onDamaged", damageAmount)
end

function PlayerServiceServer.Init(self: PlayerServiceServer)
	self.playerState = {}
	self.playerRuntimes = {}
	self.activeGameplayPlayers = {}
	self.invincibilityFramesConfig = resolveInvincibilityFramesConfigFromTemplate()
	self.allowMovementFreeze = resolveAllowMovementFreezeFromTemplate()
	Players.CharacterAutoLoads = true
	PlayerServiceUtils.getOrCreateWorkspaceGameFolder()
	PlayerSpawnCooldown.applyConfiguredRespawnDelay()
	self.goreService = GoreServiceServer :: GoreServiceServerObject
	self.ragdollService =
		require(script:FindFirstAncestor("game").Server.Services.RagdollService.RagdollServiceServer) :: RagdollServiceServerObject
	self.networker = Networker.server.new("PlayerService", self, {
		self.SetFacing,
		self.RequestState,
		self.SetWorldReadyForMovement,
	})
	self.binders = NevermoreSupport.getService(ServerBinderSupport)

	for _, player in Players:GetPlayers() do
		self:trackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player)
		self:trackPlayer(player)
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		self:untrackPlayer(player)
	end)
end

function PlayerServiceServer.IsGameplayActiveForPlayer(self: PlayerServiceServer, player: Player): boolean
	return self.activeGameplayPlayers[player] == true
end

function PlayerServiceServer.EnterGameplay(self: PlayerServiceServer, player: Player): boolean
	self.activeGameplayPlayers[player] = true

	local character = player.Character
	if character ~= nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid.Health > 0 then
			self:setMovementLocked(player, true, true)
			self:applyGameplaySpawnToCharacter(player, character)
			self:queueSpawnSurfaceSnap(player, character, humanoid)
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

	local nextRuntime = self:createRuntime()
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
	local rootPart = PlayerServiceUtils.resolveCharacterRootPart(character)
	if rootPart == nil then
		runtime.movementLockAnchoredRoot = nil
		return
	end

	if movementLocked then
		if runtime.movementLockAnchoredRoot
			and runtime.movementLockAnchoredRoot ~= rootPart
			and runtime.movementLockAnchoredRoot.Parent ~= nil then
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
	replicateToClient: boolean?
)
	if not self.allowMovementFreeze then
		movementLocked = false
	end

	local state = self:getState(player)
	state.movementLocked = movementLocked
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, movementLocked)

	local runtime = self:getRuntime(player)
	self:applyMovementLockToRuntime(runtime, player, movementLocked)

	if replicateToClient ~= false and self.networker then
		self.networker:fire(player, PlayerServiceUtils.NETWORK_METHOD_APPLY_MOVEMENT_LOCK, movementLocked)
	end
end

function PlayerServiceServer.SetGameplaySpawnPosition(self: PlayerServiceServer, player: Player, worldPositionRaw: any)
	local state = self:getState(player)
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
	local state = self:getState(player)
	local spawnWorldPosition = state.spawnWorldPosition
	if typeof(spawnWorldPosition) ~= "Vector3" then
		return false
	end

	local rootPart = PlayerServiceUtils.resolveCharacterRootPart(character)
	if rootPart == nil then
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
		CFrame.lookAt(spawnWorldPosition, spawnWorldPosition + Vector3.new(0, 0, -state.facingSign), Vector3.yAxis)
	local pivotTarget = targetRootCFrame * rootToPivot
	local pivotApplied = pcall(function()
		character:PivotTo(pivotTarget)
	end)
	if not pivotApplied then
		rootPart.CFrame = targetRootCFrame
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	PlayerServiceUtils.snapRootPartFacing(rootPart, state.facingSign)
	return true
end

function PlayerServiceServer.TrySnapCharacterToWorldSurface(
	self: PlayerServiceServer,
	player: Player,
	character: Model,
	humanoid: Humanoid
): boolean
	local rootPart = PlayerServiceUtils.resolveCharacterRootPart(character)
	if rootPart == nil then
		return false
	end

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
		if not PlayerServiceUtils.isSurfaceTerrainPart(hitPart) then
			continue
		end
		if hit.Normal.Y < WORLD_SURFACE_MIN_NORMAL_Y then
			continue
		end

		if bestHit == nil or hit.Position.Y > bestHit.Position.Y then
			bestHit = hit
		end
	end

	if bestHit == nil then
		return false
	end

	local state = self:getState(player)
	local position = rootPart.Position
	local rotation = rootPart.CFrame - position
	local targetY = bestHit.Position.Y + humanoid.HipHeight + rootPart.Size.Y * 0.5
	rootPart.CFrame = CFrame.new(position.X, targetY, position.Z) * rotation
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	PlayerServiceUtils.snapRootPartFacing(rootPart, state.facingSign)
	return true
end

function PlayerServiceServer.QueueSpawnSurfaceSnap(
	self: PlayerServiceServer,
	player: Player,
	character: Model,
	humanoid: Humanoid
)
	local runtime = self:getRuntime(player)
	task.spawn(function()
		local deadline = os.clock() + WORLD_SURFACE_SNAP_MAX_WAIT_SECONDS
		while os.clock() < deadline do
			if runtime.humanoid ~= humanoid then
				return
			end
			if character.Parent == nil then
				return
			end
			if not self:getState(player).movementLocked then
				return
			end

			if self:trySnapCharacterToWorldSurface(player, character, humanoid) then
				if self:getState(player).movementLocked then
					self:setMovementLocked(player, false, true)
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
		effectsJunkFolder = PlayerServiceUtils.getOrCreateEffectsJunkFolder(character)
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

	local highlight = self:getOrCreateDamageHighlight(runtime, character)
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
	local runtime = self:getRuntime(player)
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
		self:stopInvincibilityFrames(runtime)
		return
	end

	local previousHealthRaw = runtime.lastKnownHealth
	if nextHealth <= 0 then
		local previousHealth = if previousHealthRaw ~= nil then math.clamp(previousHealthRaw, 0, maxHealth) else 0
		local damageAmount = math.max(0, previousHealth - nextHealth)
		runtime.deathFeedbackLocked = true
		runtime.lastKnownHealth = 0
		self:emitPlayerGore(player, humanoid, true, damageAmount)
		self:fireDamageFeedback(player, damageAmount)
		self:stopInvincibilityFrames(runtime)
		return
	end

	if not PlayerServiceUtils.isHumanoidAlive(humanoid) then
		runtime.lastKnownHealth = nextHealth
		self:stopInvincibilityFrames(runtime)
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
	self:emitPlayerGore(player, humanoid, false, appliedDamage)
	self:fireDamageFeedback(player, appliedDamage)
	runtime.invulnerableUntil = now + self.invincibilityFramesConfig.duration
	self:playInvincibilityFlicker(runtime, humanoid)
end

function PlayerServiceServer.BindHumanoid(self: PlayerServiceServer, player: Player, humanoid: Humanoid)
	local runtime = self:getRuntime(player)
	local state = self:getState(player)
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
	PlayerServiceUtils.applyCharacterSettings(humanoid)
	local character = humanoid.Parent
	if character and character:IsA("Model") then
		if self.goreService ~= nil then
			self.goreService:registerPlayerCharacter(player, character)
		end
		local appliedSpawn = self:applyGameplaySpawnToCharacter(player, character)
		if not appliedSpawn then
			local rig = PlayerServiceUtils.resolveCharacterRig(character)
			if rig then
				PlayerServiceUtils.snapRootPartFacing(rig.rootPart, state.facingSign)
			end
		end
	end
	self:applyMovementLockToRuntime(runtime, player, state.movementLocked)
	if character and character:IsA("Model") then
		self:queueSpawnSurfaceSnap(player, character, humanoid)
	end

	runtime.characterJanitor:GiveChore(humanoid.HealthChanged:Connect(function(nextHealth: number)
		if runtime.humanoid ~= humanoid then
			return
		end

		self:onHumanoidHealthChanged(player, humanoid, nextHealth)
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
		self:stopInvincibilityFrames(runtime)
		state.nextSpawnHealth =
			PlayerServiceUtils.computeRespawnHealthFromDeath(humanoid.MaxHealth, PlayerServiceUtils.DEFAULT_DEATH_RESPAWN_HEALTH_SCALE)
		if self.ragdollService ~= nil then
			pcall(function()
				self.ragdollService:setPlayerRagdoll(player, true, "Death", nil, false, nil)
			end)
		end

		if self:isGameplayActiveForPlayer(player) then
			local respawnDelay = PlayerSpawnCooldown.getCurrentRespawnDelay()
			task.delay(respawnDelay, function()
				if player.Parent == nil then
					return
				end
				if not self:isGameplayActiveForPlayer(player) then
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
				self.goreService:unregisterPlayer(player)
			end
			self:stopInvincibilityFrames(runtime)
			runtime.humanoid = nil
			runtime.lastKnownHealth = nil
			runtime.deathFeedbackLocked = false
		end
	end))
end

function PlayerServiceServer.BindCharacter(self: PlayerServiceServer, player: Player, character: Model)
	local runtime = self:getRuntime(player)
	TagBinder.applyTag(character, TagBinder.Tags.Character)
	if self.goreService ~= nil then
		self.goreService:unregisterPlayer(player)
	end
	self:setMovementLocked(player, true, true)
	self:stopInvincibilityFrames(runtime)
	runtime.characterJanitor:Clean()
	runtime.humanoid = nil
	runtime.effectsJunkFolder = PlayerServiceUtils.getOrCreateEffectsJunkFolder(character)
	runtime.lastKnownHealth = nil
	runtime.lastDamageFeedbackAt = -math.huge
	runtime.isRestoringHealth = false
	runtime.damageHighlight = nil
	runtime.deathFeedbackLocked = false

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self:bindHumanoid(player, humanoid)
	end

	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if runtime.humanoid ~= nil then
			return
		end
		if child:IsA("Humanoid") then
			self:bindHumanoid(player, child)
		end
	end))

	runtime.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if runtime.effectsJunkFolder == child then
			runtime.effectsJunkFolder = nil
		end
		if runtime.humanoid == child then
			self:stopInvincibilityFrames(runtime)
			runtime.humanoid = nil
			runtime.lastKnownHealth = nil
		end
	end))
end

function PlayerServiceServer.TrackPlayer(self: PlayerServiceServer, player: Player)
	self.activeGameplayPlayers[player] = true
	local shouldStartLocked = self.allowMovementFreeze
	self.playerState[player] = {
		facingSign = PlayerServiceUtils.DEFAULT_FACING_SIGN,
		nextSpawnHealth = nil,
		movementLocked = shouldStartLocked,
		spawnWorldPosition = nil,
	}
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, shouldStartLocked)

	local runtime = self:getRuntime(player)
	runtime.playerJanitor:Clean()
	self:stopInvincibilityFrames(runtime)
	runtime.characterJanitor:Clean()
	runtime.humanoid = nil
	runtime.effectsJunkFolder = nil
	runtime.lastKnownHealth = nil
	runtime.lastDamageFeedbackAt = -math.huge
	runtime.isRestoringHealth = false
	runtime.damageHighlight = nil
	runtime.deathFeedbackLocked = false

	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:bindCharacter(player, character)
	end))

	if player.Character then
		self:bindCharacter(player, player.Character)
	end
end

function PlayerServiceServer.UntrackPlayer(self: PlayerServiceServer, player: Player)
	self.activeGameplayPlayers[player] = nil
	self.playerState[player] = nil
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, nil)
	if self.goreService ~= nil then
		self.goreService:unregisterPlayer(player)
	end

	local runtime = self.playerRuntimes[player]
	if not runtime then
		return
	end

	if runtime.movementLockAnchoredRoot and runtime.movementLockAnchoredRoot.Parent ~= nil then
		runtime.movementLockAnchoredRoot.Anchored = false
	end
	runtime.movementLockAnchoredRoot = nil
	self:stopInvincibilityFrames(runtime)
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function PlayerServiceServer.GetState(self: PlayerServiceServer, player: Player): PlayerState
	local state = self.playerState[player]
	if state then
		return state
	end

	local shouldStartLocked = self.allowMovementFreeze
	local defaultState: PlayerState = {
		facingSign = PlayerServiceUtils.DEFAULT_FACING_SIGN,
		nextSpawnHealth = nil,
		movementLocked = shouldStartLocked,
		spawnWorldPosition = nil,
	}
	player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, shouldStartLocked)
	self.playerState[player] = defaultState
	return defaultState
end

function PlayerServiceServer.RequestState(self: PlayerServiceServer, player: Player)
	local state = self:getState(player)
	local runtime = self:getRuntime(player)
	local rig = PlayerServiceUtils.resolveCharacterRig(player.Character)
	if rig then
		PlayerServiceUtils.applyCharacterSettings(rig.humanoid)
		PlayerServiceUtils.snapRootPartFacing(rig.rootPart, state.facingSign)
	end
	self:applyMovementLockToRuntime(runtime, player, state.movementLocked)
	self.networker:fire(player, "applyFacing", state.facingSign)
	self.networker:fire(player, PlayerServiceUtils.NETWORK_METHOD_APPLY_MOVEMENT_LOCK, state.movementLocked)
end

function PlayerServiceServer.SetWorldReadyForMovement(self: PlayerServiceServer, player: Player, worldReadyRaw: any)
	if typeof(worldReadyRaw) ~= "boolean" then
		return
	end

	if worldReadyRaw then
		local state = self:getState(player)
		if not state.movementLocked then
			return
		end

		local character = player.Character
		if character == nil then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or not PlayerServiceUtils.isHumanoidAlive(humanoid) then
			return
		end
		if not self:trySnapCharacterToWorldSurface(player, character, humanoid) then
			return
		end
		self:setMovementLocked(player, false, true)
	else
		self:setMovementLocked(player, true, true)
	end
end

function PlayerServiceServer.SetFacing(self: PlayerServiceServer, player: Player, facingSignRaw: any)
	local state = self:getState(player)
	local facingSign = PlayerServiceUtils.sanitizeFacingSign(facingSignRaw, state.facingSign)
	state.facingSign = facingSign

	local character = player.Character
	local rig = PlayerServiceUtils.resolveCharacterRig(character)
	if not rig then
		return
	end

	PlayerServiceUtils.applyCharacterSettings(rig.humanoid)
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

	if self.networker then
		self.networker:destroy()
	end

	for player, runtime in self.playerRuntimes do
		if self.goreService ~= nil then
			self.goreService:unregisterPlayer(player)
		end
		if runtime.movementLockAnchoredRoot and runtime.movementLockAnchoredRoot.Parent ~= nil then
			runtime.movementLockAnchoredRoot.Anchored = false
		end
		runtime.movementLockAnchoredRoot = nil
		self:stopInvincibilityFrames(runtime)
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
		player:SetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE, nil)
	end
end

PlayerServiceServer.emitPlayerGore = PlayerServiceServer.EmitPlayerGore
PlayerServiceServer.fireDamageFeedback = PlayerServiceServer.FireDamageFeedback
PlayerServiceServer.init = PlayerServiceServer.Init
PlayerServiceServer.isGameplayActiveForPlayer = PlayerServiceServer.IsGameplayActiveForPlayer
PlayerServiceServer.createRuntime = PlayerServiceServer.CreateRuntime
PlayerServiceServer.getRuntime = PlayerServiceServer.GetRuntime
PlayerServiceServer.stopInvincibilityFrames = PlayerServiceServer.StopInvincibilityFrames
PlayerServiceServer.applyMovementLockToRuntime = PlayerServiceServer.ApplyMovementLockToRuntime
PlayerServiceServer.setMovementLocked = PlayerServiceServer.SetMovementLocked
PlayerServiceServer.setGameplaySpawnPosition = PlayerServiceServer.SetGameplaySpawnPosition
PlayerServiceServer.applyGameplaySpawnToCharacter = PlayerServiceServer.ApplyGameplaySpawnToCharacter
PlayerServiceServer.trySnapCharacterToWorldSurface = PlayerServiceServer.TrySnapCharacterToWorldSurface
PlayerServiceServer.queueSpawnSurfaceSnap = PlayerServiceServer.QueueSpawnSurfaceSnap
PlayerServiceServer.getOrCreateDamageHighlight = PlayerServiceServer.GetOrCreateDamageHighlight
PlayerServiceServer.playInvincibilityFlicker = PlayerServiceServer.PlayInvincibilityFlicker
PlayerServiceServer.onHumanoidHealthChanged = PlayerServiceServer.OnHumanoidHealthChanged
PlayerServiceServer.bindHumanoid = PlayerServiceServer.BindHumanoid
PlayerServiceServer.bindCharacter = PlayerServiceServer.BindCharacter
PlayerServiceServer.trackPlayer = PlayerServiceServer.TrackPlayer
PlayerServiceServer.untrackPlayer = PlayerServiceServer.UntrackPlayer
PlayerServiceServer.getState = PlayerServiceServer.GetState
PlayerServiceServer.requestState = PlayerServiceServer.RequestState
PlayerServiceServer.setWorldReadyForMovement = PlayerServiceServer.SetWorldReadyForMovement
PlayerServiceServer.setFacing = PlayerServiceServer.SetFacing
PlayerServiceServer.destroy = PlayerServiceServer.Destroy

type PlayerServiceServer = typeof(PlayerServiceServer) & {
	isGameplayActiveForPlayer: (self: PlayerServiceServer, player: Player) -> boolean,
	EnterGameplay: (self: PlayerServiceServer, player: Player) -> boolean,
	setGameplaySpawnPosition: (self: PlayerServiceServer, player: Player, worldPositionRaw: any) -> (),
	applyGameplaySpawnToCharacter: (self: PlayerServiceServer, player: Player, character: Model) -> boolean,
	emitPlayerGore: (
		self: PlayerServiceServer,
		player: Player,
		humanoid: Humanoid,
		isDeathRaw: any,
		damageRaw: any?
	) -> (),
	networker: Networker.Server,
	goreService: GoreServiceServerObject?,
	ragdollService: RagdollServiceServerObject?,
	invincibilityFramesConfig: InvincibilityFramesConfig,
	allowMovementFreeze: boolean,
	playerState: { [Player]: PlayerState },
	activeGameplayPlayers: { [Player]: boolean },
	playerRuntimes: { [Player]: PlayerRuntime },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return PlayerServiceServer :: PlayerServiceServer

