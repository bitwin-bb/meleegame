--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local RaycastHitbox = require(ReplicatedStorage.Packages.RaycastHitbox)
local Melee = require(script:FindFirstAncestor("game").Shared.Classes.Melee)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ServerBinderSupport = require(script:FindFirstAncestor("game").Server.Binders.ServerBinderSupport)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryServiceUtils)
local MeleeServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.MeleeServiceUtils)
local InventoryServiceServer = require(script:FindFirstAncestor("game").Server.Services.InventoryServiceServer)
local BossServiceServer = require(script:FindFirstAncestor("game").Server.Services.BossServiceServer)
local NpcServiceServer = require(script:FindFirstAncestor("game").Server.Services.NpcServiceServer)
local PlayerServiceServer = require(script:FindFirstAncestor("game").Server.Services.PlayerServiceServer)
local RagdollServiceServer = require(script:FindFirstAncestor("game").Server.Services.RagdollServiceServer)

type MeleeWeaponConfig = MeleeServiceUtils.MeleeWeaponConfig
type InventoryState = InventoryServiceUtils.InventoryState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type MeleeController = {
	inputBegan: (self: MeleeController, triggerRaw: any) -> boolean,
	inputEnded: (self: MeleeController, triggerRaw: any) -> boolean,
	setCharacter: (self: MeleeController, characterRaw: any) -> (),
	destroy: (self: MeleeController) -> (),
}

type HitboxConnection = {
	Disconnect: (self: HitboxConnection) -> (),
}

type HitboxSignal = {
	Connect: (
		self: HitboxSignal,
		callback: (part: BasePart, humanoid: Humanoid?, raycastResult: RaycastResult?, group: string?) -> ()
	) -> HitboxConnection,
}

type HitboxObject = {
	RaycastParams: RaycastParams?,
	Visualizer: boolean,
	DebugLog: boolean,
	OnHit: HitboxSignal,
	HitStart: (self: HitboxObject, seconds: number?) -> (),
	HitStop: (self: HitboxObject) -> (),
	Destroy: (self: HitboxObject) -> (),
	LinkAttachments: (self: HitboxObject, attachment1: Attachment, attachment2: Attachment) -> (),
	UnlinkAttachments: (self: HitboxObject, attachment: Attachment) -> (),
	SetPoints: (self: HitboxObject, object: BasePart | Bone, vectorPoints: { Vector3 }, group: string?) -> (),
	RemovePoints: (self: HitboxObject, object: BasePart | Bone, vectorPoints: { Vector3 }) -> (),
}

type PlayerRuntime = {
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
	character: Model?,
	humanoid: Humanoid?,
	rootPart: BasePart?,
	inputHeld: boolean,
	equippedItemId: string?,
	equippedSlot: number?,
	equippedTool: Tool?,
	equippedWeaponConfig: MeleeWeaponConfig?,
	meleeController: MeleeController?,
	hitbox: HitboxObject?,
	hitboxConnection: HitboxConnection?,
	hitboxPointsPart: BasePart?,
	hitboxPoints: { Vector3 },
	hitboxCleanupPromise: any?,
}

type InventoryServiceServerObject = {
	getState: (self: InventoryServiceServerObject, player: Player) -> InventoryState,
}

type RagdollServiceServerObject = {
	isPlayerRagdolled: (self: RagdollServiceServerObject, player: Player) -> boolean,
}

type BossServiceServerObject = {
	damageBossFromHitPart: (
		self: BossServiceServerObject,
		hitPartRaw: any,
		damageRaw: any,
		sourceRaw: any?,
		damageContextRaw: any?
	) -> number,
	damageBossesInBox: (
		self: BossServiceServerObject,
		boxCFrameRaw: any,
		boxSizeRaw: any,
		damageRaw: any,
		sourceRaw: any?,
		damageContextRaw: any?
	) -> number,
}

local MeleeServiceServer = {}

local HITBOX_CLEANUP_PADDING = 0.03
local RAYCAST_HITBOX_DEBUG = false
local DEFAULT_NPC_OVERLAP_QUERY_MAX_PARTS = 64

local function isHumanoidAlive(humanoid: Humanoid?): boolean
	if humanoid == nil then
		return false
	end
	if humanoid.Health <= 0 then
		return false
	end
	return humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

local function resolveHumanoidAndRootPart(character: Model?): (Humanoid?, BasePart?)
	if character == nil then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPartCandidate = character:FindFirstChild("HumanoidRootPart")
	local rootPart = if rootPartCandidate and rootPartCandidate:IsA("BasePart") then rootPartCandidate else nil
	return humanoid, rootPart
end

local function resolveToolHandlePart(toolRaw: any): BasePart?
	if typeof(toolRaw) ~= "Instance" or not toolRaw:IsA("Tool") then
		return nil
	end

	local tool = toolRaw :: Tool
	local handleCandidate = tool:FindFirstChild("Handle")
	if handleCandidate ~= nil and handleCandidate:IsA("BasePart") then
		return handleCandidate
	end

	local directBasePart = tool:FindFirstChildWhichIsA("BasePart")
	if directBasePart ~= nil then
		return directBasePart
	end

	return tool:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveCharacterHandPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end

	for _, partName in { "RightHand", "Right Arm", "RightLowerArm", "RightUpperArm", "LeftHand", "Left Arm" } do
		local candidate = character:FindFirstChild(partName)
		if candidate ~= nil and candidate:IsA("BasePart") then
			return candidate
		end
	end

	return nil
end

local function resolveHitboxAnchorPart(runtime: PlayerRuntime): BasePart?
	local character = runtime.character
	local equippedTool = runtime.equippedTool
	if equippedTool ~= nil and character ~= nil and equippedTool:IsDescendantOf(character) then
		local toolPart = resolveToolHandlePart(equippedTool)
		if toolPart ~= nil then
			return toolPart
		end
	end

	local handPart = resolveCharacterHandPart(character)
	if handPart ~= nil then
		return handPart
	end

	return runtime.rootPart
end

local function resolveNpcOverlapAnchorPart(runtime: PlayerRuntime): BasePart?
	if runtime.rootPart ~= nil then
		return runtime.rootPart
	end

	local handPart = resolveCharacterHandPart(runtime.character)
	if handPart ~= nil then
		return handPart
	end

	return resolveHitboxAnchorPart(runtime)
end

local function applyNpcOverlapDamageFallback(player: Player, runtime: PlayerRuntime, weaponConfig: MeleeWeaponConfig)
	if not weaponConfig.canHitNpcs then
		return
	end
	if runtime.character == nil then
		return
	end

	local damage = math.max(0, weaponConfig.damage)
	if damage <= 0 then
		return
	end

	local anchorPart = resolveNpcOverlapAnchorPart(runtime)
	if anchorPart == nil then
		return
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { runtime.character }
	overlapParams.MaxParts = DEFAULT_NPC_OVERLAP_QUERY_MAX_PARTS

	local querySize = Vector3.new(
		math.max(1.5, weaponConfig.width * 1.3),
		math.max(2, weaponConfig.height + 1.25),
		math.max(2.25, weaponConfig.range + 1)
	)
	local queryCFrame = anchorPart.CFrame * CFrame.new(0, querySize.Y * 0.15, -querySize.Z * 0.5)
	if runtime.rootPart ~= nil and anchorPart == runtime.rootPart then
		querySize = Vector3.new(querySize.X, querySize.Y, querySize.Z * 2)
		queryCFrame = CFrame.new(anchorPart.Position + Vector3.new(0, querySize.Y * 0.15, 0))
	end

	local ok, overlapPartsOrError = pcall(function()
		return Workspace:GetPartBoundsInBox(queryCFrame, querySize, overlapParams)
	end)
	if not ok or typeof(overlapPartsOrError) ~= "table" then
		overlapPartsOrError = {}
	end

	local seenModels: { [Model]: true } = {}
	local overlapDamageApplied = 0
	for _, candidate in overlapPartsOrError do
		if typeof(candidate) ~= "Instance" or not candidate:IsA("BasePart") then
			continue
		end

		local model = candidate:FindFirstAncestorOfClass("Model")
		if model ~= nil then
			if seenModels[model] == true then
				continue
			end
			seenModels[model] = true
		end

		local appliedDamage = (NpcServiceServer :: any):damageNpcFromHitPart(candidate, damage, player, "Melee")
		if typeof(appliedDamage) == "number" and appliedDamage > 0 then
			overlapDamageApplied += appliedDamage
			continue
		end

		local bossDamage = (BossServiceServer :: BossServiceServerObject):damageBossFromHitPart(
			candidate,
			damage,
			player,
			"Melee"
		)
		if typeof(bossDamage) == "number" and bossDamage > 0 then
			overlapDamageApplied += bossDamage
		end
	end
	if overlapDamageApplied > 0 then
		return
	end

	local runtimeDamageOk, runtimeDamageOrError = pcall(function()
		return (NpcServiceServer :: any):damageNpcsInBox(queryCFrame, querySize, damage, player, "Melee")
	end)
	if runtimeDamageOk and typeof(runtimeDamageOrError) == "number" and runtimeDamageOrError > 0 then
		return
	end

	local bossRuntimeDamage =
		(BossServiceServer :: BossServiceServerObject):damageBossesInBox(queryCFrame, querySize, damage, player, "Melee")
	if typeof(bossRuntimeDamage) == "number" and bossRuntimeDamage > 0 then
		return
	end
end

local function shallowCopyWeaponConfig(weaponConfig: MeleeWeaponConfig): MeleeWeaponConfig
	return {
		itemId = weaponConfig.itemId,
		displayName = weaponConfig.displayName,
		damage = weaponConfig.damage,
		cooldown = weaponConfig.cooldown,
		slashCooldown = weaponConfig.slashCooldown,
		slashResetCooldown = weaponConfig.slashResetCooldown,
		swingDuration = weaponConfig.swingDuration,
		hitboxDuration = weaponConfig.hitboxDuration,
		range = weaponConfig.range,
		width = weaponConfig.width,
		height = weaponConfig.height,
		pointCount = weaponConfig.pointCount,
		autoRepeatWhileHeld = weaponConfig.autoRepeatWhileHeld,
		canHitPlayers = weaponConfig.canHitPlayers,
		canHitNpcs = weaponConfig.canHitNpcs,
		animations = weaponConfig.animations,
	}
end

local function isWeaponConfigEquivalent(lhsRaw: any, rhsRaw: any): boolean
	if lhsRaw == rhsRaw then
		return true
	end
	if typeof(lhsRaw) ~= "table" or typeof(rhsRaw) ~= "table" then
		return false
	end

	local lhs = lhsRaw :: MeleeWeaponConfig
	local rhs = rhsRaw :: MeleeWeaponConfig
	if lhs.itemId ~= rhs.itemId then
		return false
	end
	if lhs.displayName ~= rhs.displayName then
		return false
	end
	if lhs.damage ~= rhs.damage then
		return false
	end
	if lhs.cooldown ~= rhs.cooldown then
		return false
	end
	if lhs.slashCooldown ~= rhs.slashCooldown then
		return false
	end
	if lhs.slashResetCooldown ~= rhs.slashResetCooldown then
		return false
	end
	if lhs.swingDuration ~= rhs.swingDuration then
		return false
	end
	if lhs.hitboxDuration ~= rhs.hitboxDuration then
		return false
	end
	if lhs.range ~= rhs.range then
		return false
	end
	if lhs.width ~= rhs.width then
		return false
	end
	if lhs.height ~= rhs.height then
		return false
	end
	if lhs.pointCount ~= rhs.pointCount then
		return false
	end
	if lhs.autoRepeatWhileHeld ~= rhs.autoRepeatWhileHeld then
		return false
	end
	if lhs.canHitPlayers ~= rhs.canHitPlayers then
		return false
	end
	if lhs.canHitNpcs ~= rhs.canHitNpcs then
		return false
	end
	if not MeleeServiceUtils.areAnimationConfigsEquivalent(lhs.animations, rhs.animations) then
		return false
	end

	return true
end

function MeleeServiceServer.Init(self: MeleeServiceServer)
	self.networker = Networker.server.new("MeleeService", self, {
		self.RequestRefreshEquipped,
		self.RequestSetInputHeld,
	})
	self.inventoryService = InventoryServiceServer :: InventoryServiceServerObject
	self.ragdollService = RagdollServiceServer :: RagdollServiceServerObject
	self.playerRuntimes = {}
	self.binders = NevermoreSupport.getService(ServerBinderSupport)

	for _, player in Players:GetPlayers() do
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self:trackPlayer(player)
		end
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		if PlayerServiceServer:isGameplayActiveForPlayer(player) then
			self:trackPlayer(player)
		end
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)
end

function MeleeServiceServer.IsAttackBlocked(self: MeleeServiceServer, player: Player, runtime: PlayerRuntime): boolean
	if not isHumanoidAlive(runtime.humanoid) then
		return true
	end

	local humanoid = runtime.humanoid
	if humanoid ~= nil and humanoid.PlatformStand and humanoid:GetState() == Enum.HumanoidStateType.Physics then
		return true
	end

	local ragdollService = self.ragdollService
	if ragdollService ~= nil then
		local ok, isRagdolledOrError = pcall(function()
			return ragdollService:isPlayerRagdolled(player)
		end)
		if ok and isRagdolledOrError == true then
			return true
		end
	end

	return false
end

function MeleeServiceServer.EnforceInputAllowed(
	self: MeleeServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	reason: string
)
	if not self:isAttackBlocked(player, runtime) then
		return
	end

	if runtime.inputHeld then
		runtime.inputHeld = false
	end
	self:stopHitbox(runtime)

	local meleeController = runtime.meleeController
	if meleeController ~= nil then
		meleeController:inputEnded(reason)
	end
end

function MeleeServiceServer.CreateRuntime(self: MeleeServiceServer): PlayerRuntime
	return {
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		character = nil,
		humanoid = nil,
		rootPart = nil,
		inputHeld = false,
		equippedItemId = nil,
		equippedSlot = nil,
		equippedTool = nil,
		equippedWeaponConfig = nil,
		meleeController = nil,
		hitbox = nil,
		hitboxConnection = nil,
		hitboxPointsPart = nil,
		hitboxPoints = {},
		hitboxCleanupPromise = nil,
	}
end

function MeleeServiceServer.GetRuntime(self: MeleeServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime ~= nil then
		return runtime
	end

	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function MeleeServiceServer.CancelHitboxCleanupPromise(self: MeleeServiceServer, runtime: PlayerRuntime)
	local hitboxCleanupPromise = runtime.hitboxCleanupPromise
	runtime.hitboxCleanupPromise = nil
	if hitboxCleanupPromise == nil then
		return
	end
	hitboxCleanupPromise:Destroy()
end

function MeleeServiceServer.StopHitbox(self: MeleeServiceServer, runtime: PlayerRuntime)
	self:cancelHitboxCleanupPromise(runtime)
	local hitbox = runtime.hitbox
	if hitbox == nil then
		return
	end
	pcall(function()
		hitbox:HitStop()
	end)
end

function MeleeServiceServer.ClearHitboxPoints(self: MeleeServiceServer, runtime: PlayerRuntime)
	local hitbox = runtime.hitbox
	local hitboxPointsPart = runtime.hitboxPointsPart
	local hitboxPoints = runtime.hitboxPoints
	if hitbox ~= nil and hitboxPointsPart ~= nil and #hitboxPoints > 0 then
		pcall(function()
			hitbox:RemovePoints(hitboxPointsPart, hitboxPoints)
		end)
	end

	runtime.hitboxPointsPart = nil
	runtime.hitboxPoints = {}
end

function MeleeServiceServer.ApplyHitboxPoints(self: MeleeServiceServer, runtime: PlayerRuntime)
	local hitbox = runtime.hitbox
	local weaponConfig = runtime.equippedWeaponConfig
	if hitbox == nil or weaponConfig == nil then
		self:clearHitboxPoints(runtime)
		return
	end

	local anchorPart = resolveHitboxAnchorPart(runtime)
	if anchorPart == nil then
		self:clearHitboxPoints(runtime)
		return
	end

	self:clearHitboxPoints(runtime)
	local points = MeleeServiceUtils.buildHitboxPoints(weaponConfig)
	if #points <= 0 then
		return
	end

	runtime.hitboxPointsPart = anchorPart
	runtime.hitboxPoints = points
	pcall(function()
		hitbox:SetPoints(anchorPart, points)
	end)
end

function MeleeServiceServer.DestroyHitbox(self: MeleeServiceServer, runtime: PlayerRuntime)
	self:stopHitbox(runtime)
	self:clearHitboxPoints(runtime)

	local hitboxConnection = runtime.hitboxConnection
	runtime.hitboxConnection = nil
	if hitboxConnection ~= nil then
		hitboxConnection:Disconnect()
	end

	local hitbox = runtime.hitbox
	runtime.hitbox = nil
	if hitbox ~= nil then
		pcall(function()
			hitbox:Destroy()
		end)
	end
end

function MeleeServiceServer.DestroyMeleeController(self: MeleeServiceServer, runtime: PlayerRuntime)
	local meleeController = runtime.meleeController
	runtime.meleeController = nil
	if meleeController == nil then
		return
	end
	pcall(function()
		meleeController:destroy()
	end)
end

function MeleeServiceServer.OnHit(
	self: MeleeServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	hitPart: BasePart,
	hitHumanoidRaw: Humanoid?
)
	local resolvedItemId = nil :: string?
	if runtime.equippedTool ~= nil then
		resolvedItemId = MeleeServiceUtils.resolveToolItemId(runtime.equippedTool)
	end
	if resolvedItemId == nil then
		resolvedItemId = runtime.equippedItemId
	end

	local weaponConfig = if resolvedItemId ~= nil then MeleeServiceUtils.resolveWeaponConfig(resolvedItemId) else nil
	if weaponConfig == nil then
		weaponConfig = runtime.equippedWeaponConfig
	end
	if weaponConfig == nil then
		return
	end

	local damage = math.max(0, weaponConfig.damage)
	if damage <= 0 then
		return
	end

	if weaponConfig.canHitNpcs then
		local serviceDamage = (NpcServiceServer :: any):damageNpcFromHitPart(hitPart, damage, player, "Melee")
		if typeof(serviceDamage) == "number" and serviceDamage > 0 then
			return
		end

		local bossDamage = (BossServiceServer :: BossServiceServerObject):damageBossFromHitPart(hitPart, damage, player, "Melee")
		if typeof(bossDamage) == "number" and bossDamage > 0 then
			return
		end
	end

	local hitHumanoid = if typeof(hitHumanoidRaw) == "Instance" and hitHumanoidRaw:IsA("Humanoid")
		then hitHumanoidRaw
		else nil
	if hitHumanoid == nil then
		return
	end
	if hitHumanoid.Health <= 0 then
		return
	end

	local targetCharacter = hitHumanoid.Parent
	if targetCharacter == runtime.character then
		return
	end
	if targetCharacter == nil or not targetCharacter:IsA("Model") then
		return
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer ~= nil and not weaponConfig.canHitPlayers then
		return
	end
	if targetPlayer == nil and not weaponConfig.canHitNpcs then
		return
	end

	hitHumanoid:TakeDamage(damage)
end

function MeleeServiceServer.OnAttackStarted(
	self: MeleeServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	_context: { [string]: any }
)
	local currentRuntime = self.playerRuntimes[player]
	if currentRuntime ~= runtime then
		return
	end
	if self:isAttackBlocked(player, runtime) then
		self:enforceInputAllowed(player, runtime, "BlockedAttackStarted")
		return
	end

	local hitbox = runtime.hitbox
	if hitbox == nil or runtime.equippedWeaponConfig == nil then
		return
	end

	self:cancelHitboxCleanupPromise(runtime)
	self:applyHitboxPoints(runtime)
	pcall(function()
		hitbox:HitStart()
	end)

	local weaponConfig = runtime.equippedWeaponConfig
	if weaponConfig ~= nil then
		applyNpcOverlapDamageFallback(player, runtime, weaponConfig)
	end
end

function MeleeServiceServer.OnSwingEnded(
	self: MeleeServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	_context: { [string]: any }
)
	local currentRuntime = self.playerRuntimes[player]
	if currentRuntime ~= runtime then
		return
	end
	self:stopHitbox(runtime)
end

function MeleeServiceServer.OnAttackFinished(
	self: MeleeServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	_context: { [string]: any }
)
	local currentRuntime = self.playerRuntimes[player]
	if currentRuntime ~= runtime then
		return
	end
	self:stopHitbox(runtime)
end

function MeleeServiceServer.BindCharacter(self: MeleeServiceServer, player: Player, character: Model)
	local runtime = self:getRuntime(player)
	runtime.characterJanitor:Clean()

	runtime.character = character
	runtime.humanoid, runtime.rootPart = resolveHumanoidAndRootPart(character)

	self:destroyHitbox(runtime)
	local hitbox = RaycastHitbox.new(character) :: any
	runtime.hitbox = hitbox :: HitboxObject
	hitbox.Visualizer = RAYCAST_HITBOX_DEBUG
	hitbox.DebugLog = RAYCAST_HITBOX_DEBUG

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	hitbox.RaycastParams = params

	runtime.hitboxConnection = hitbox.OnHit:Connect(
		function(hitPart: BasePart, hitHumanoid: Humanoid?, raycastResult: RaycastResult?, group: string?)
			self:onHit(player, runtime, hitPart, hitHumanoid)
		end
	)

	runtime.characterJanitor:GiveChore(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") or child.Name == "HumanoidRootPart" then
			runtime.humanoid, runtime.rootPart = resolveHumanoidAndRootPart(character)
			if child:IsA("Humanoid") then
				runtime.characterJanitor:GiveChore(child.Died:Connect(function()
					self:enforceInputAllowed(player, runtime, "HumanoidDied")
				end))
				runtime.characterJanitor:GiveChore(child.StateChanged:Connect(function()
					self:enforceInputAllowed(player, runtime, "HumanoidStateChanged")
				end))
				runtime.characterJanitor:GiveChore(child.HealthChanged:Connect(function()
					self:enforceInputAllowed(player, runtime, "HumanoidHealthChanged")
				end))
			end
			self:applyHitboxPoints(runtime)
			return
		end
		if child:IsA("Tool") then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))

	runtime.characterJanitor:GiveChore(character.ChildRemoved:Connect(function(child: Instance)
		if child == runtime.humanoid then
			runtime.humanoid = nil
		end
		if child == runtime.rootPart then
			runtime.rootPart = nil
			self:clearHitboxPoints(runtime)
		end
		if child:IsA("Tool") then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))

	local function shouldRefreshFromDescendant(descendant: Instance): boolean
		if not (descendant:IsA("Animation") or descendant:IsA("Sound")) then
			return false
		end

		local cursor: Instance? = descendant
		while cursor ~= nil and cursor ~= character do
			if cursor:IsA("Tool") then
				return true
			end
			cursor = cursor.Parent
		end
		return false
	end

	runtime.characterJanitor:GiveChore(character.DescendantAdded:Connect(function(descendant: Instance)
		if shouldRefreshFromDescendant(descendant) then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))

	runtime.characterJanitor:GiveChore(character.DescendantRemoving:Connect(function(descendant: Instance)
		if shouldRefreshFromDescendant(descendant) then
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))

	runtime.characterJanitor:GiveChore(character.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
		if parent ~= nil then
			return
		end
		runtime.character = nil
		runtime.humanoid = nil
		runtime.rootPart = nil
		self:destroyHitbox(runtime)
	end))

	local currentHumanoid = runtime.humanoid
	if currentHumanoid ~= nil then
		runtime.characterJanitor:GiveChore(currentHumanoid.Died:Connect(function()
			self:enforceInputAllowed(player, runtime, "HumanoidDied")
		end))
		runtime.characterJanitor:GiveChore(currentHumanoid.StateChanged:Connect(function()
			self:enforceInputAllowed(player, runtime, "HumanoidStateChanged")
		end))
		runtime.characterJanitor:GiveChore(currentHumanoid.HealthChanged:Connect(function()
			self:enforceInputAllowed(player, runtime, "HumanoidHealthChanged")
		end))
	end

	self:applyHitboxPoints(runtime)
	if runtime.inputHeld and runtime.meleeController ~= nil then
		self:enforceInputAllowed(player, runtime, "CharacterBound")
		if runtime.inputHeld then
			runtime.meleeController:inputBegan("CharacterBound")
		end
	end
end

function MeleeServiceServer.SetEquippedWeaponConfig(
	self: MeleeServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	itemId: string?,
	slotIndex: number?,
	weaponConfig: MeleeWeaponConfig?,
	selectedTool: Tool?
)
	runtime.equippedItemId = itemId
	runtime.equippedSlot = slotIndex
	runtime.equippedTool = selectedTool
	runtime.equippedWeaponConfig = weaponConfig

	self:destroyMeleeController(runtime)
	self:stopHitbox(runtime)
	self:applyHitboxPoints(runtime)

	if weaponConfig == nil then
		return
	end

	local classConfig = MeleeServiceUtils.createMeleeClassConfig(weaponConfig, {
		autoRepeatWhileHeld = weaponConfig.autoRepeatWhileHeld,
		namedAnimationPlaybackEnabled = false,
		animations = false,
		callbacks = {
			onAttackStarted = function(_: any, context: { [string]: any })
				self:onAttackStarted(player, runtime, context)
			end,
			onSwingEnded = function(_: any, context: { [string]: any })
				self:onSwingEnded(player, runtime, context)
			end,
			onAttackFinished = function(_: any, context: { [string]: any })
				self:onAttackFinished(player, runtime, context)
			end,
		},
	})
	if classConfig == nil then
		return
	end
	classConfig.fallbackSwingDuration = weaponConfig.hitboxDuration
	classConfig.fallbackSwingPadding = 0

	local meleeController = Melee.new(classConfig) :: any
	runtime.meleeController = meleeController :: MeleeController

	self:applyHitboxPoints(runtime)
	if runtime.inputHeld then
		self:enforceInputAllowed(player, runtime, "EquipWhileHeld")
		if runtime.inputHeld then
			runtime.meleeController:inputBegan("EquipWhileHeld")
		end
	end
end

function MeleeServiceServer.RefreshEquippedWeaponFromInventory(
	self: MeleeServiceServer,
	player: Player,
	runtime: PlayerRuntime
)
	local inventoryService = self.inventoryService
	if inventoryService == nil then
		self:setEquippedWeaponConfig(player, runtime, nil, nil, nil, nil)
		return
	end

	local state = inventoryService:getState(player)
	if not InventoryServiceUtils.isLoadedState(state.loadState) then
		self:setEquippedWeaponConfig(player, runtime, nil, nil, nil, nil)
		return
	end

	local selectedSlot = state.selectedSlot
	local stack = if selectedSlot ~= nil then InventoryServiceUtils.getStack(state, selectedSlot) else nil
	local itemId = if stack ~= nil then stack.itemId else nil
	local weaponConfig = if itemId ~= nil then MeleeServiceUtils.resolveWeaponConfig(itemId) else nil
	local backpack = player:FindFirstChildOfClass("Backpack")
	local selectedTool = if itemId ~= nil
		then MeleeServiceUtils.resolveToolByItemId(runtime.character, backpack, itemId)
		else nil

	if selectedTool == nil or not MeleeServiceUtils.isMeleeTool(selectedTool) then
		weaponConfig = nil
	elseif weaponConfig ~= nil then
		local nextWeaponConfig = shallowCopyWeaponConfig(weaponConfig)
		nextWeaponConfig.animations =
			MeleeServiceUtils.resolveToolAnimationOverrides(selectedTool, weaponConfig.animations)
		weaponConfig = nextWeaponConfig
	end

	local isSameWeapon = runtime.equippedItemId == itemId
		and runtime.equippedSlot == selectedSlot
		and runtime.meleeController ~= nil
		and runtime.equippedTool == selectedTool
		and isWeaponConfigEquivalent(runtime.equippedWeaponConfig, weaponConfig)
	if isSameWeapon then
		runtime.equippedTool = selectedTool
		runtime.equippedWeaponConfig = weaponConfig
		self:applyHitboxPoints(runtime)
		return
	end

	self:setEquippedWeaponConfig(player, runtime, itemId, selectedSlot, weaponConfig, selectedTool)
end

function MeleeServiceServer.TrackPlayer(self: MeleeServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.playerJanitor:Clean()
	runtime.characterJanitor:Clean()
	runtime.character = nil
	runtime.humanoid = nil
	runtime.rootPart = nil
	runtime.inputHeld = false
	runtime.equippedTool = nil
	self:destroyMeleeController(runtime)
	self:destroyHitbox(runtime)

	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:bindCharacter(player, character)
	end))

	local function bindBackpack(backpack: Backpack)
		runtime.playerJanitor:GiveChore(backpack.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:refreshEquippedWeaponFromInventory(player, runtime)
			end
		end))
		runtime.playerJanitor:GiveChore(backpack.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:refreshEquippedWeaponFromInventory(player, runtime)
			end
		end))

		local function shouldRefreshFromBackpackDescendant(descendant: Instance): boolean
			if not (descendant:IsA("Animation") or descendant:IsA("Sound")) then
				return false
			end

			local cursor: Instance? = descendant
			while cursor ~= nil and cursor ~= backpack do
				if cursor:IsA("Tool") then
					return true
				end
				cursor = cursor.Parent
			end
			return false
		end

		runtime.playerJanitor:GiveChore(backpack.DescendantAdded:Connect(function(descendant: Instance)
			if shouldRefreshFromBackpackDescendant(descendant) then
				self:refreshEquippedWeaponFromInventory(player, runtime)
			end
		end))

		runtime.playerJanitor:GiveChore(backpack.DescendantRemoving:Connect(function(descendant: Instance)
			if shouldRefreshFromBackpackDescendant(descendant) then
				self:refreshEquippedWeaponFromInventory(player, runtime)
			end
		end))
	end

	runtime.playerJanitor:GiveChore(player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			bindBackpack(child)
			self:refreshEquippedWeaponFromInventory(player, runtime)
		end
	end))

	if player.Character ~= nil then
		self:bindCharacter(player, player.Character)
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		bindBackpack(backpack)
	end

	self:refreshEquippedWeaponFromInventory(player, runtime)
end

function MeleeServiceServer.UntrackPlayer(self: MeleeServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	runtime.inputHeld = false
	self:destroyMeleeController(runtime)
	self:destroyHitbox(runtime)
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function MeleeServiceServer.RequestRefreshEquipped(self: MeleeServiceServer, player: Player)
	if self.playerRuntimes[player] == nil then
		self:trackPlayer(player)
	end
	local runtime = self:getRuntime(player)
	self:refreshEquippedWeaponFromInventory(player, runtime)
end

function MeleeServiceServer.RequestSetInputHeld(self: MeleeServiceServer, player: Player, inputHeldRaw: any)
	if self.playerRuntimes[player] == nil then
		self:trackPlayer(player)
	end
	local runtime = self:getRuntime(player)
	local inputHeld = inputHeldRaw == true
	if inputHeld and self:isAttackBlocked(player, runtime) then
		inputHeld = false
	end
	runtime.inputHeld = inputHeld

	self:refreshEquippedWeaponFromInventory(player, runtime)
	self:enforceInputAllowed(player, runtime, "InputHeldRequest")

	local meleeController = runtime.meleeController
	if meleeController == nil then
		if not inputHeld then
			self:stopHitbox(runtime)
		end
		return
	end

	if inputHeld then
		meleeController:inputBegan("ClientInputBegan")
	else
		meleeController:inputEnded("ClientInputEnded")
	end
end

function MeleeServiceServer.Destroy(self: MeleeServiceServer)
	if self.playerAddedConnection ~= nil then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	for player, runtime in self.playerRuntimes do
		runtime.inputHeld = false
		self:destroyMeleeController(runtime)
		self:destroyHitbox(runtime)
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
	end

	if self.networker ~= nil then
		self.networker:destroy()
	end
end

MeleeServiceServer.init = MeleeServiceServer.Init
MeleeServiceServer.isAttackBlocked = MeleeServiceServer.IsAttackBlocked
MeleeServiceServer.enforceInputAllowed = MeleeServiceServer.EnforceInputAllowed
MeleeServiceServer.createRuntime = MeleeServiceServer.CreateRuntime
MeleeServiceServer.getRuntime = MeleeServiceServer.GetRuntime
MeleeServiceServer.cancelHitboxCleanupPromise = MeleeServiceServer.CancelHitboxCleanupPromise
MeleeServiceServer.stopHitbox = MeleeServiceServer.StopHitbox
MeleeServiceServer.clearHitboxPoints = MeleeServiceServer.ClearHitboxPoints
MeleeServiceServer.applyHitboxPoints = MeleeServiceServer.ApplyHitboxPoints
MeleeServiceServer.destroyHitbox = MeleeServiceServer.DestroyHitbox
MeleeServiceServer.destroyMeleeController = MeleeServiceServer.DestroyMeleeController
MeleeServiceServer.onHit = MeleeServiceServer.OnHit
MeleeServiceServer.onAttackStarted = MeleeServiceServer.OnAttackStarted
MeleeServiceServer.onSwingEnded = MeleeServiceServer.OnSwingEnded
MeleeServiceServer.onAttackFinished = MeleeServiceServer.OnAttackFinished
MeleeServiceServer.bindCharacter = MeleeServiceServer.BindCharacter
MeleeServiceServer.setEquippedWeaponConfig = MeleeServiceServer.SetEquippedWeaponConfig
MeleeServiceServer.refreshEquippedWeaponFromInventory = MeleeServiceServer.RefreshEquippedWeaponFromInventory
MeleeServiceServer.trackPlayer = MeleeServiceServer.TrackPlayer
MeleeServiceServer.untrackPlayer = MeleeServiceServer.UntrackPlayer
MeleeServiceServer.requestRefreshEquipped = MeleeServiceServer.RequestRefreshEquipped
MeleeServiceServer.requestSetInputHeld = MeleeServiceServer.RequestSetInputHeld
MeleeServiceServer.destroy = MeleeServiceServer.Destroy

type MeleeServiceServer = typeof(MeleeServiceServer) & {
	networker: Networker.Server,
	inventoryService: InventoryServiceServerObject,
	ragdollService: RagdollServiceServerObject,
	playerRuntimes: { [Player]: PlayerRuntime },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
}

return MeleeServiceServer :: MeleeServiceServer

