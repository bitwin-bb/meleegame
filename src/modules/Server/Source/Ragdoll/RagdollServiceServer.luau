local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local RagdollServicePackets = require("NetPacketsShared").RagdollService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = RagdollServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for RagdollService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = RagdollServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for RagdollService`)
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
	bindPacket(self, "requestSelfRagdoll")
	bindPacket(self, "requestSelfRecover")
	bindPacket(self, "requestSync")
end

local NevermoreSupport = require("NevermoreSupport")
local RagdollServiceUtils = require("RagdollServiceUtils")
local BinderSupportServer = require("BinderSupportServer")

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

function RagdollServiceServer.Init(self: RagdollServiceServer)
	bindPackets(self)
	self.playerRuntimes = {}
	(self :: any).binders = NevermoreSupport.GetService(BinderSupportServer)

	for _, player in Players:GetPlayers() do
		self:TrackPlayer(player)
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:TrackPlayer(player)
	end)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self:UntrackPlayer(player)
	end)

	self.heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:StepRagdollPlaneConstraint()
	end)
end

function RagdollServiceServer.CreateRuntime(self: RagdollServiceServer): PlayerRuntime
	return {
		playerJanitor = Janitor.new(),
		characterJanitor = Janitor.new(),
		character = nil,
		humanoid = nil,
		ragdollContext = nil,
		ragdollPlaneX = nil,
		state = RagdollServiceUtils.CreateDefaultState(),
		stateToken = 0,
	}
end

function RagdollServiceServer.GetRuntime(self: RagdollServiceServer, player: Player): PlayerRuntime
	local runtime = self.playerRuntimes[player]
	if runtime then
		return runtime
	end

	local nextRuntime = self:CreateRuntime()
	self.playerRuntimes[player] = nextRuntime
	return nextRuntime
end

function RagdollServiceServer.PushState(self: RagdollServiceServer, player: Player)
	local runtime = self:GetRuntime(player)
	sendPacket(player, "applyState", RagdollServiceUtils.CloneState(runtime.state))
end

function RagdollServiceServer.CommitState(
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
	local now = RagdollServiceUtils.Now()
	local sequence = runtime.state.sequence + 1
	local scheduledRecoveryAt = if isRagdolled
			and canRecover
			and durationSeconds ~= nil
		then now + durationSeconds
		else nil
	runtime.state = RagdollServiceUtils.CreateState(
		isRagdolled,
		reasonRaw,
		now,
		scheduledRecoveryAt,
		canRecover,
		sequence,
		runtime.state
	)
	self:PushState(player)
	return token
end

function RagdollServiceServer.ScheduleRecovery(
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

		self:RecoverPlayer(player, TIMER_RECOVER_REASON)
	end)
end

function RagdollServiceServer.ClearActiveRagdoll(
	self: RagdollServiceServer,
	runtime: PlayerRuntime,
	restoreHumanoid: boolean?
)
	local context = runtime.ragdollContext
	if context == nil then
		runtime.ragdollPlaneX = nil
		return
	end

	RagdollServiceUtils.EndRagdoll(context, {
		restoreHumanoid = if restoreHumanoid == nil then true else restoreHumanoid,
	})
	runtime.ragdollContext = nil
	runtime.ragdollPlaneX = nil
end

function RagdollServiceServer.StepRagdollPlaneConstraint(self: RagdollServiceServer)
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
		RagdollServiceUtils.EnforceRagdoll2DPlane(context, runtime.ragdollPlaneX)
	end
end

function RagdollServiceServer.GetPlayerRig(
	self: RagdollServiceServer,
	player: Player,
	runtime: PlayerRuntime
): CharacterRig?
	local character = runtime.character
	if character == nil or character.Parent == nil then
		character = player.Character
		runtime.character = character
	end

	local rig = RagdollServiceUtils.GetCharacterRig(character)
	if rig ~= nil then
		runtime.character = rig.character
		runtime.humanoid = rig.humanoid
	end
	return rig
end

function RagdollServiceServer.RagdollPlayer(
	self: RagdollServiceServer,
	player: Player,
	reasonRaw: any,
	durationRaw: any,
	canRecoverRaw: any,
	impulseRaw: any
): boolean
	local runtime = self:GetRuntime(player)
	local rig = self:GetPlayerRig(player, runtime)
	if rig == nil then
		return false
	end

	if runtime.ragdollContext == nil then
		local context = RagdollServiceUtils.BeginRagdoll(rig, {
			reason = reasonRaw,
			impulse = if typeof(impulseRaw) == "Vector3" then impulseRaw else nil,
		})
		if context == nil then
			return false
		end
		runtime.ragdollContext = context
		RagdollServiceUtils.SetCharacterNetworkOwner(rig.character, nil)
	elseif typeof(impulseRaw) == "Vector3" and impulseRaw.Magnitude > 0 then
		local mass = math.max(1, rig.rootPart.AssemblyMass)
		rig.rootPart:ApplyImpulse(impulseRaw * mass)
	end

	if runtime.ragdollPlaneX == nil then
		runtime.ragdollPlaneX = rig.rootPart.Position.X
	end
	if runtime.ragdollContext ~= nil then
		RagdollServiceUtils.EnforceRagdoll2DPlane(runtime.ragdollContext, runtime.ragdollPlaneX)
	end

	local canRecover = canRecoverRaw ~= false
	local duration = if canRecover
		then RagdollServiceUtils.CoerceDuration(
			durationRaw,
			nil,
			RagdollServiceUtils.MIN_DURATION,
			RagdollServiceUtils.MAX_DURATION
		)
		else nil

	local stateToken = self:CommitState(player, runtime, true, reasonRaw, duration, canRecover)
	if duration ~= nil then
		self:ScheduleRecovery(player, runtime, stateToken, duration)
	end

	return true
end

function RagdollServiceServer.RecoverPlayer(self: RagdollServiceServer, player: Player, reasonRaw: any): boolean
	local runtime = self:GetRuntime(player)
	if runtime.ragdollContext == nil and not runtime.state.isRagdolled then
		return false
	end

	self:ClearActiveRagdoll(runtime, true)
	self:CommitState(player, runtime, false, reasonRaw, nil, true)

	local rig = self:GetPlayerRig(player, runtime)
	if rig ~= nil then
		RagdollServiceUtils.SetCharacterNetworkOwner(rig.character, player)
	end

	return true
end

function RagdollServiceServer.SetPlayerRagdoll(
	self: RagdollServiceServer,
	player: Player,
	enabledRaw: any,
	reasonRaw: any,
	durationRaw: any,
	canRecoverRaw: any,
	impulseRaw: any
): boolean
	if enabledRaw == true then
		return self:RagdollPlayer(player, reasonRaw, durationRaw, canRecoverRaw, impulseRaw)
	end

	return self:RecoverPlayer(player, reasonRaw)
end

function RagdollServiceServer.GetState(self: RagdollServiceServer, player: Player): RagdollServiceState
	local runtime = self:GetRuntime(player)
	return RagdollServiceUtils.CloneState(runtime.state)
end

function RagdollServiceServer.IsPlayerRagdolled(self: RagdollServiceServer, player: Player): boolean
	local runtime = self:GetRuntime(player)
	return runtime.state.isRagdolled
end

function RagdollServiceServer.BindHumanoid(self: RagdollServiceServer, player: Player, humanoid: Humanoid)
	local runtime = self:GetRuntime(player)
	runtime.humanoid = humanoid
	humanoid.BreakJointsOnDeath = false

	runtime.characterJanitor:GiveChore(humanoid.Died:Connect(function()
		if runtime.humanoid ~= humanoid then
			return
		end
		self:RagdollPlayer(player, RagdollServiceUtils.DEATH_REASON, nil, false, nil)
	end))

	runtime.characterJanitor:GiveChore(humanoid.Destroying:Connect(function()
		if runtime.humanoid == humanoid then
			runtime.humanoid = nil
		end
	end))
end

function RagdollServiceServer.BindCharacter(self: RagdollServiceServer, player: Player, character: Model)
	local runtime = self:GetRuntime(player)
	runtime.characterJanitor:Clean()
	self:ClearActiveRagdoll(runtime, false)
	runtime.character = character
	runtime.humanoid = nil
	runtime.ragdollPlaneX = nil
	self:CommitState(player, runtime, false, RagdollServiceUtils.CHARACTER_RESET_REASON, nil, true)

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
		if runtime.humanoid == child then
			runtime.humanoid = nil
		end
	end))
end

function RagdollServiceServer.TrackPlayer(self: RagdollServiceServer, player: Player)
	local runtime = self:GetRuntime(player)
	runtime.playerJanitor:Clean()
	runtime.characterJanitor:Clean()
	self:ClearActiveRagdoll(runtime, false)
	runtime.character = nil
	runtime.humanoid = nil
	runtime.ragdollPlaneX = nil
	runtime.state = RagdollServiceUtils.CreateDefaultState()
	runtime.stateToken = 0

	runtime.playerJanitor:GiveChore(player.CharacterAdded:Connect(function(character: Model)
		self:BindCharacter(player, character)
	end))

	if player.Character then
		self:BindCharacter(player, player.Character)
	else
		self:PushState(player)
	end
end

function RagdollServiceServer.UntrackPlayer(self: RagdollServiceServer, player: Player)
	local runtime = self.playerRuntimes[player]
	if runtime == nil then
		return
	end

	self:ClearActiveRagdoll(runtime, false)
	runtime.playerJanitor:Destroy()
	runtime.characterJanitor:Destroy()
	self.playerRuntimes[player] = nil
end

function RagdollServiceServer.RequestSync(self: RagdollServiceServer, player: Player)
	if self.playerRuntimes[player] == nil then
		self:TrackPlayer(player)
		return
	end
	self:PushState(player)
end

function RagdollServiceServer.RequestSelfRagdoll(
	self: RagdollServiceServer,
	player: Player,
	durationRaw: any,
	reasonRaw: any,
	impulseRaw: any
)
	local duration = RagdollServiceUtils.CoerceDuration(
		durationRaw,
		RagdollServiceUtils.DEFAULT_SELF_RAGDOLL_DURATION,
		RagdollServiceUtils.MIN_DURATION,
		RagdollServiceUtils.MAX_SELF_REQUEST_DURATION
	)
	self:RagdollPlayer(
		player,
		RagdollServiceUtils.CoerceReason(reasonRaw, SELF_REQUEST_REASON),
		duration,
		true,
		impulseRaw
	)
end

function RagdollServiceServer.RequestSelfRecover(self: RagdollServiceServer, player: Player)
	local runtime = self:GetRuntime(player)
	if not runtime.state.isRagdolled then
		return
	end
	if runtime.state.canRecover ~= true then
		return
	end

	self:RecoverPlayer(player, SELF_RECOVER_REASON)
end

function RagdollServiceServer.ForceRecoverPlayer(self: RagdollServiceServer, player: Player): boolean
	return self:RecoverPlayer(player, SERVER_RECOVER_REASON)
end

function RagdollServiceServer.Destroy(self: RagdollServiceServer)
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
		self:ClearActiveRagdoll(runtime, false)
		runtime.playerJanitor:Destroy()
		runtime.characterJanitor:Destroy()
		self.playerRuntimes[player] = nil
	end
end
export type RagdollServiceServer = typeof(RagdollServiceServer) & {
	playerRuntimes: { [Player]: PlayerRuntime },
	playerAddedConnection: RBXScriptConnection?,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return RagdollServiceServer :: RagdollServiceServer
