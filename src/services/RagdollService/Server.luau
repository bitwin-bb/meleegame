--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local RagdollServiceUtils = require(ReplicatedStorage.Shared.Services.RagdollService.RagdollServiceUtils)

type CharacterRig = RagdollServiceUtils.CharacterRig
type RagdollContext = RagdollServiceUtils.RagdollContext
type RagdollServiceState = RagdollServiceUtils.RagdollServiceState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type PlayerRuntime = {
	playerJanitor: JanitorClass,
	characterJanitor: JanitorClass,
	character: Model?,
	humanoid: Humanoid?,
	ragdollContext: RagdollContext?,
	ragdollPlaneX: number?,
	state: RagdollServiceState,
	stateToken: number,
}

local RagdollServiceServer = {}

local SELF_REQUEST_REASON = "SelfRequest"
local SELF_RECOVER_REASON = "SelfRecover"
local TIMER_RECOVER_REASON = "TimerRecovery"
local SERVER_RECOVER_REASON = "ServerRecovery"

function RagdollServiceServer.init(self: RagdollServiceServer)
	self.networker = Networker.server.new("RagdollService", self, {
		self.requestSync,
		self.requestSelfRagdoll,
		self.requestSelfRecover,
	})
	self.playerRuntimes = {}

	for _, player in Players:GetPlayers() do
		self:trackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:trackPlayer(player)
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:untrackPlayer(player)
	end)

	self.heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:stepRagdollPlaneConstraint()
	end)
end

function RagdollServiceServer.createRuntime(self: RagdollServiceServer): PlayerRuntime
	return {
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		character = nil,
		humanoid = nil,
		ragdollContext = nil,
		ragdollPlaneX = nil,
		state = RagdollServiceUtils.createDefaultState(),
		stateToken = 0,
	}
end

function RagdollServiceServer.getRuntime(self: RagdollServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime then
		return runtime
	end

	local nextRuntime = self:createRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function RagdollServiceServer.pushState(self: RagdollServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	self.networker:fire(player, "applyState", RagdollServiceUtils.cloneState(runtime.state))
end

function RagdollServiceServer.commitState(
	self: RagdollServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	isRagdolled: boolean,
	reasonRaw: any,
	durationSeconds: number?,
	canRecover: boolean
): number
	runtime.stateToken += 1
	local token = runtime.stateToken
	local now = RagdollServiceUtils.now()
	local sequence = runtime.state.sequence + 1
	local scheduledRecoveryAt = if isRagdolled and canRecover and durationSeconds ~= nil then now + durationSeconds else nil
	runtime.state = RagdollServiceUtils.createState(
		isRagdolled,
		reasonRaw,
		now,
		scheduledRecoveryAt,
		canRecover,
		sequence,
		runtime.state
	)
	self:pushState(player)
	return token
end

function RagdollServiceServer.scheduleRecovery(
	self: RagdollServiceServer,
	player: Player,
	runtime: PlayerRuntime,
	token: number,
	durationSeconds: number
)
	task.delay(durationSeconds, function()
		local latestRuntime = self.playerRuntimes[player]
		if latestRuntime ~= runtime then
			return
		end
		if latestRuntime.stateToken ~= token then
			return
		end
		if not latestRuntime.state.isRagdolled then
			return
		end
		if latestRuntime.state.canRecover ~= true then
			return
		end

		self:recoverPlayer(player, TIMER_RECOVER_REASON)
	end)
end

function RagdollServiceServer.clearActiveRagdoll(
	self: RagdollServiceServer,
	runtime: PlayerRuntime,
	restoreHumanoid: boolean?
)
	local context = runtime.ragdollContext
	if context == nil then
		runtime.ragdollPlaneX = nil
		return
	end

	RagdollServiceUtils.endRagdoll(context, {
		restoreHumanoid = if restoreHumanoid == nil then true else restoreHumanoid,
	})
	runtime.ragdollContext = nil
	runtime.ragdollPlaneX = nil
end

function RagdollServiceServer.stepRagdollPlaneConstraint(self: RagdollServiceServer)
	for _, runtime in self.playerRuntimes do
		local context = runtime.ragdollContext
		if context == nil then
			continue
		end

		local rootPart = context.rig.rootPart
		if rootPart.Parent == nil then
			continue
		end

		if runtime.ragdollPlaneX == nil then
			runtime.ragdollPlaneX = rootPart.Position.X
		end
		RagdollServiceUtils.enforceRagdoll2DPlane(context, runtime.ragdollPlaneX)
	end
end

function RagdollServiceServer.resolvePlayerRig(
	self: RagdollServiceServer,
	player: Player,
	runtime: PlayerRuntime
): CharacterRig?
	local character = runtime.character
	if character == nil or character.Parent == nil then
		character = player.Character
		runtime.character = character
	end

	local rig = RagdollServiceUtils.resolveCharacterRig(character)
	if rig ~= nil then
		runtime.character = rig.character
		runtime.humanoid = rig.humanoid
	end
	return rig
end

function RagdollServiceServer.ragdollPlayer(
	self: RagdollServiceServer,
	player: Player,
	reasonRaw: any,
	durationRaw: any,
	canRecoverRaw: any,
	impulseRaw: any
): boolean
	local runtime = self:getRuntime(player)
	local rig = self:resolvePlayerRig(player, runtime)
	if rig == nil then
		return false
	end

	if runtime.ragdollContext == nil then
		local context = RagdollServiceUtils.beginRagdoll(rig, {
			reason = reasonRaw,
			impulse = if typeof(impulseRaw) == "Vector3" then impulseRaw else nil,
		})
		if context == nil then
			return false
		end
		runtime.ragdollContext = context
		RagdollServiceUtils.setCharacterNetworkOwner(rig.character, nil)
	elseif typeof(impulseRaw) == "Vector3" and impulseRaw.Magnitude > 0 then
		local mass = math.max(1, rig.rootPart.AssemblyMass)
		rig.rootPart:ApplyImpulse(impulseRaw * mass)
	end

	if runtime.ragdollPlaneX == nil then
		runtime.ragdollPlaneX = rig.rootPart.Position.X
	end
	if runtime.ragdollContext ~= nil then
		RagdollServiceUtils.enforceRagdoll2DPlane(runtime.ragdollContext, runtime.ragdollPlaneX)
	end

	local canRecover = canRecoverRaw ~= false
	local duration = if canRecover
		then RagdollServiceUtils.sanitizeDuration(
			durationRaw,
			nil,
			RagdollServiceUtils.MIN_DURATION,
			RagdollServiceUtils.MAX_DURATION
		)
		else nil

	local stateToken = self:commitState(player, runtime, true, reasonRaw, duration, canRecover)
	if duration ~= nil then
		self:scheduleRecovery(player, runtime, stateToken, duration)
	end

	return true
end

function RagdollServiceServer.recoverPlayer(self: RagdollServiceServer, player: Player, reasonRaw: any): boolean
	local runtime = self:getRuntime(player)
	if runtime.ragdollContext == nil and not runtime.state.isRagdolled then
		return false
	end

	self:clearActiveRagdoll(runtime, true)
	self:commitState(player, runtime, false, reasonRaw, nil, true)

	local rig = self:resolvePlayerRig(player, runtime)
	if rig ~= nil then
		RagdollServiceUtils.setCharacterNetworkOwner(rig.character, player)
	end

	return true
end

function RagdollServiceServer.setPlayerRagdoll(
	self: RagdollServiceServer,
	player: Player,
	enabledRaw: any,
	reasonRaw: any,
	durationRaw: any,
	canRecoverRaw: any,
	impulseRaw: any
): boolean
	if enabledRaw == true then
		return self:ragdollPlayer(player, reasonRaw, durationRaw, canRecoverRaw, impulseRaw)
	end

	return self:recoverPlayer(player, reasonRaw)
end

function RagdollServiceServer.getState(self: RagdollServiceServer, player: Player): RagdollServiceState
	local runtime = self:getRuntime(player)
	return RagdollServiceUtils.cloneState(runtime.state)
end

function RagdollServiceServer.isPlayerRagdolled(self: RagdollServiceServer, player: Player): boolean
	local runtime = self:getRuntime(player)
	return runtime.state.isRagdolled
end

function RagdollServiceServer.bindHumanoid(self: RagdollServiceServer, player: Player, humanoid: Humanoid)
	local runtime = self:getRuntime(player)
	runtime.humanoid = humanoid
	humanoid.BreakJointsOnDeath = false

	runtime.characterJanitor:GiveChore(humanoid.Died:Connect(function()
		if runtime.humanoid ~= humanoid then
			return
		end
		self:ragdollPlayer(player, RagdollServiceUtils.DEATH_REASON, nil, false, nil)
	end))

	runtime.characterJanitor:GiveChore(humanoid.Destroying:Connect(function()
		if runtime.humanoid == humanoid then
			runtime.humanoid = nil
		end
	end))
end

function RagdollServiceServer.bindCharacter(self: RagdollServiceServer, player: Player, character: Model)
	local runtime = self:getRuntime(player)
	runtime.characterJanitor:Clean()
	self:clearActiveRagdoll(runtime, false)
	runtime.character = character
	runtime.humanoid = nil
	runtime.ragdollPlaneX = nil
	self:commitState(player, runtime, false, RagdollServiceUtils.CHARACTER_RESET_REASON, nil, true)

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
		if runtime.humanoid == child then
			runtime.humanoid = nil
		end
	end))
end

function RagdollServiceServer.trackPlayer(self: RagdollServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	runtime.playerJanitor:Clean()
	runtime.characterJanitor:Clean()
	self:clearActiveRagdoll(runtime, false)
	runtime.character = nil
	runtime.humanoid = nil
	runtime.ragdollPlaneX = nil
	runtime.state = RagdollServiceUtils.createDefaultState()
	runtime.stateToken = 0

	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:bindCharacter(player, character)
	end))

	if player.Character then
		self:bindCharacter(player, player.Character)
	else
		self:pushState(player)
	end
end

function RagdollServiceServer.untrackPlayer(self: RagdollServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:clearActiveRagdoll(runtime, false)
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function RagdollServiceServer.requestSync(self: RagdollServiceServer, player: Player)
	self:pushState(player)
end

function RagdollServiceServer.requestSelfRagdoll(
	self: RagdollServiceServer,
	player: Player,
	durationRaw: any,
	reasonRaw: any,
	impulseRaw: any
)
	local duration = RagdollServiceUtils.sanitizeDuration(
		durationRaw,
		RagdollServiceUtils.DEFAULT_SELF_RAGDOLL_DURATION,
		RagdollServiceUtils.MIN_DURATION,
		RagdollServiceUtils.MAX_SELF_REQUEST_DURATION
	)
	self:ragdollPlayer(
		player,
		RagdollServiceUtils.sanitizeReason(reasonRaw, SELF_REQUEST_REASON),
		duration,
		true,
		impulseRaw
	)
end

function RagdollServiceServer.requestSelfRecover(self: RagdollServiceServer, player: Player)
	local runtime = self:getRuntime(player)
	if not runtime.state.isRagdolled then
		return
	end
	if runtime.state.canRecover ~= true then
		return
	end

	self:recoverPlayer(player, SELF_RECOVER_REASON)
end

function RagdollServiceServer.forceRecoverPlayer(self: RagdollServiceServer, player: Player): boolean
	return self:recoverPlayer(player, SERVER_RECOVER_REASON)
end

function RagdollServiceServer.destroy(self: RagdollServiceServer)
	if self.playerAddedConnection then
		self.playerAddedConnection:Disconnect()
		self.playerAddedConnection = nil
	end

	if self.playerRemovingConnection then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end

	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	for player, runtime in self.playerRuntimes do
		self:clearActiveRagdoll(runtime, false)
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
	end

	if self.networker then
		self.networker:destroy()
	end
end

export type RagdollServiceServer = typeof(RagdollServiceServer) & {
	networker: Networker.Server,
	playerRuntimes: { [Player]: PlayerRuntime },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return RagdollServiceServer :: RagdollServiceServer
