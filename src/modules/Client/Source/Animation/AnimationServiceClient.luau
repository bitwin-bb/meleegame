local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local AnimationServiceUtils = require("AnimationServiceUtils")
local AudioServiceClient = require("AudioServiceClient")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local ServiceBag = require("ServiceBag")
local AnimationServicePackets = require("NetPacketsShared").AnimationService

local function sendPacket(methodName: string, ...: any)
	local packet = AnimationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AnimationService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = AnimationServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for AnimationService`)
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
	bindPacket(self, "requestSync")
	bindPacket(self, "setFootstepsEnabled")
	bindPacket(self, "setProfile")
end

local PlayerServiceUtils = require("PlayerServiceUtils")

type AnimationClipConfig = AnimationServiceUtils.AnimationClipConfig
type AnimationProfile = AnimationServiceUtils.AnimationProfile
type AnimationServiceState = AnimationServiceUtils.AnimationServiceState
type CharacterRig = AnimationServiceUtils.CharacterRig

type JanitorClass = any

type CharacterRuntime = {
	rig: CharacterRig,
	profile: AnimationProfile,
	tracks: { [string]: AnimationTrack? },
	activeClipName: string?,
	lastFootstepAt: number,
	lastFootstepEventAt: number,
	lastJumpAt: number,
	lastJumpEventAt: number,
	footstepKeyframeSet: { [string]: boolean },
	jumpKeyframeSet: { [string]: boolean },
	movementSpeed: number,
	humanoidState: Enum.HumanoidStateType,
}

local AnimationServiceClient = {}
AnimationServiceClient.ServiceName = "AnimationServiceClient"
local FOOTSTEP_MOVE_DEADZONE = 0.05
local FOOTSTEP_EVENT_DEDUPE_WINDOW = 0.06
local JUMP_EVENT_DEDUPE_WINDOW = 0.09
local WALK_ANIMATION_SPEED_MIN_SCALE = 0.25
local WALK_ANIMATION_SPEED_MAX_SCALE = 2.5
local DEFAULT_TRANSITION_FADE_TIME = 0.14

local JUMP_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
}

local FALL_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local function getClipConfig(runtime: CharacterRuntime, clipName: string): AnimationClipConfig?
	return runtime.profile.animations[clipName]
end

local function isJumpState(state: Enum.HumanoidStateType): boolean
	return JUMP_STATES[state] == true
end

local function isFallState(state: Enum.HumanoidStateType): boolean
	return FALL_STATES[state] == true
end

local function getClipPlaybackSpeed(runtime: CharacterRuntime, clipName: string): number
	local clipConfig = getClipConfig(runtime, clipName)
	if not clipConfig then
		return 1
	end

	if clipName ~= "Walk" then
		return clipConfig.speed
	end

	local walkSpeed = runtime.rig.humanoid.WalkSpeed
	if walkSpeed <= 0 then
		return clipConfig.speed
	end

	local speedScale =
		math.clamp(runtime.movementSpeed / walkSpeed, WALK_ANIMATION_SPEED_MIN_SCALE, WALK_ANIMATION_SPEED_MAX_SCALE)
	return clipConfig.speed * speedScale
end

local function getTransitionFadeTime(runtime: CharacterRuntime, fromClipName: string?, toClipName: string?): number
	local fadeTime = DEFAULT_TRANSITION_FADE_TIME

	if fromClipName ~= nil then
		local fromClip = getClipConfig(runtime, fromClipName)
		if fromClip then
			fadeTime = math.max(fadeTime, fromClip.fadeTime)
		end
	end

	if toClipName ~= nil then
		local toClip = getClipConfig(runtime, toClipName)
		if toClip then
			fadeTime = math.max(fadeTime, toClip.fadeTime)
		end
	end

	return fadeTime
end

local function bindTrackAnimationEvents(
	janitor: JanitorClass,
	track: AnimationTrack?,
	markers: { string },
	keyframeSet: { [string]: boolean },
	onEvent: () -> ()
)
	if not track then
		return
	end

	for _, markerName in markers do
		janitor:GiveChore(track:GetMarkerReachedSignal(markerName):Connect(onEvent))
	end

	janitor:GiveChore(track.KeyframeReached:Connect(function(keyframeName: string)
		if keyframeSet[keyframeName] then
			onEvent()
		end
	end))
end

function AnimationServiceClient.Init(self: AnimationServiceClient, serviceBag: ServiceBag.ServiceBag?)
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.runtimeJanitor = Janitor.new()
	self.character = nil
	self.runtime = nil
	self.profileRegistry = AnimationServiceUtils.CreateDefaultProfileRegistry()
	self.state = AnimationServiceUtils.CreateDefaultState()
	self.movementLocked = false

	self.janitor:GiveChore(self.characterJanitor)
	self.characterJanitor:GiveChore(self.runtimeJanitor)

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character: Model)
		self:OnCharacterAdded(character)
	end))
	self.janitor:GiveChore(
		self.localPlayer
			:GetAttributeChangedSignal(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE)
			:Connect(function()
				local movementLockAttribute =
					self.localPlayer:GetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE)
				self.movementLocked = movementLockAttribute == true
				self:RefreshAnimation()
			end)
	)

	local movementLockAttribute = self.localPlayer:GetAttribute(PlayerServiceUtils.DEFAULT_MOVEMENT_LOCK_ATTRIBUTE)
	self.movementLocked = movementLockAttribute == true

	if self.localPlayer.Character then
		self:OnCharacterAdded(self.localPlayer.Character)
	end

	sendPacket("requestSync")
end

function AnimationServiceClient.OnCharacterAdded(self: AnimationServiceClient, character: Model)
	self.character = character
	self.characterJanitor:Clean()

	self.runtimeJanitor = Janitor.new()
	self.characterJanitor:GiveChore(self.runtimeJanitor)

	self.characterJanitor:GiveChore(character.ChildAdded:Connect(function()
		if self.runtime == nil then
			self:RebuildRuntime()
		end
	end))

	self:RebuildRuntime()
end

function AnimationServiceClient.RebuildRuntime(self: AnimationServiceClient)
	self.runtimeJanitor:Clean()
	self.runtime = nil

	local character = self.character
	if not character then
		return
	end

	local rig = AnimationServiceUtils.GetCharacterRig(character)
	if not rig then
		return
	end

	local profileName = AnimationServiceUtils.NormalizeProfileName(
		self.state.profileName,
		self.profileRegistry,
		AnimationServiceUtils.DEFAULT_PROFILE_NAME
	)
	local profile = AnimationServiceUtils.GetProfile(profileName, self.profileRegistry)
	if not profile then
		return
	end

	AnimationServiceUtils.DisableDefaultAnimateScript(character)
	local animator = AnimationServiceUtils.GetAnimator(rig.humanoid)
	local runtime: CharacterRuntime = {
		rig = rig,
		profile = profile,
		tracks = {},
		activeClipName = nil,
		lastFootstepAt = 0,
		lastFootstepEventAt = 0,
		lastJumpAt = 0,
		lastJumpEventAt = 0,
		footstepKeyframeSet = AnimationServiceUtils.ArrayToSet(profile.footstepKeyframes),
		jumpKeyframeSet = AnimationServiceUtils.ArrayToSet(profile.jumpKeyframes),
		movementSpeed = 0,
		humanoidState = rig.humanoid:GetState(),
	}

	for clipName, clipConfig in profile.animations do
		local track = AnimationServiceUtils.CreateAnimationTrack(animator, clipConfig)
		if track then
			runtime.tracks[clipName] = track
			self.runtimeJanitor:GiveChore(function()
				if track.IsPlaying then
					track:Stop(0.1)
				end
			end)
		end
	end

	bindTrackAnimationEvents(
		self.runtimeJanitor,
		runtime.tracks.Walk,
		profile.footstepMarkers,
		runtime.footstepKeyframeSet,
		function()
			self:OnFootstepEvent()
		end
	)

	bindTrackAnimationEvents(
		self.runtimeJanitor,
		runtime.tracks.Jump,
		profile.jumpMarkers,
		runtime.jumpKeyframeSet,
		function()
			self:OnJumpEvent()
		end
	)

	self.runtimeJanitor:GiveChore(rig.humanoid.Running:Connect(function(speed: number)
		self:UpdateMovementAnimation(speed)
	end))

	self.runtimeJanitor:GiveChore(rig.humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
		self:UpdateHumanoidState(newState)
	end))

	self.runtimeJanitor:GiveChore(rig.humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		self:RefreshAnimation()
	end))

	self.runtimeJanitor:GiveChore(rig.humanoid.Died:Connect(function()
		self:SwitchToClip(nil)
	end))

	self.runtime = runtime
	runtime.movementSpeed = rig.humanoid.MoveDirection.Magnitude * rig.humanoid.WalkSpeed
	runtime.humanoidState = rig.humanoid:GetState()
	self:RefreshAnimation()
end

function AnimationServiceClient.SwitchToClip(self: AnimationServiceClient, clipName: string?)
	local runtime = self.runtime
	if not runtime then
		return
	end
	local transitionFadeTime = getTransitionFadeTime(runtime, runtime.activeClipName, clipName)

	if clipName == nil then
		for _, track in runtime.tracks do
			if track and track.IsPlaying then
				track:Stop(transitionFadeTime)
			end
		end
		runtime.activeClipName = nil
		return
	end

	local requestedTrack = runtime.tracks[clipName]
	if requestedTrack == nil then
		if clipName ~= "Idle" and runtime.tracks.Idle then
			self:SwitchToClip("Idle")
		end
		return
	end

	if runtime.activeClipName == clipName then
		local activeTrack = runtime.tracks[clipName]
		local activeClipConfig = getClipConfig(runtime, clipName)
		local playbackSpeed = getClipPlaybackSpeed(runtime, clipName)
		if activeTrack and activeClipConfig then
			if activeTrack.IsPlaying then
				activeTrack:AdjustWeight(activeClipConfig.weight, transitionFadeTime)
				activeTrack:AdjustSpeed(playbackSpeed)
			else
				activeTrack:Play(transitionFadeTime, activeClipConfig.weight, playbackSpeed)
			end
		end
		return
	end

	local targetTrack = requestedTrack
	local targetClipConfig = getClipConfig(runtime, clipName)
	if targetTrack and targetClipConfig then
		local playbackSpeed = getClipPlaybackSpeed(runtime, clipName)
		if targetTrack.IsPlaying then
			targetTrack:AdjustWeight(targetClipConfig.weight, transitionFadeTime)
			targetTrack:AdjustSpeed(playbackSpeed)
		else
			targetTrack:Play(transitionFadeTime, targetClipConfig.weight, playbackSpeed)
		end
	end

	for candidateName, track in runtime.tracks do
		if candidateName ~= clipName and track and track.IsPlaying then
			track:Stop(transitionFadeTime)
		end
	end

	runtime.activeClipName = clipName
end

function AnimationServiceClient.UpdateMovementAnimation(self: AnimationServiceClient, speed: number)
	local runtime = self.runtime
	if not runtime then
		return
	end

	runtime.movementSpeed = math.max(speed, 0)
	self:RefreshAnimation()
end

function AnimationServiceClient.UpdateHumanoidState(self: AnimationServiceClient, humanoidState: Enum.HumanoidStateType)
	local runtime = self.runtime
	if not runtime then
		return
	end

	runtime.humanoidState = humanoidState
	self:RefreshAnimation()
end

function AnimationServiceClient.RefreshAnimation(self: AnimationServiceClient)
	local runtime = self.runtime
	if not runtime then
		return
	end

	if self.movementLocked then
		if runtime.tracks.Fall then
			self:SwitchToClip("Fall")
		elseif runtime.tracks.Jump then
			self:SwitchToClip("Jump")
		elseif runtime.tracks.Idle then
			self:SwitchToClip("Idle")
		else
			self:SwitchToClip(nil)
		end
		return
	end

	if isFallState(runtime.humanoidState) then
		if runtime.tracks.Fall then
			self:SwitchToClip("Fall")
			return
		end
		if runtime.tracks.Jump then
			self:SwitchToClip("Jump")
			return
		end
	end

	if runtime.tracks.Jump and isJumpState(runtime.humanoidState) then
		self:SwitchToClip("Jump")
		return
	end

	if runtime.movementSpeed > runtime.profile.walkSpeedThreshold and runtime.tracks.Walk then
		self:SwitchToClip("Walk")
		return
	end

	if runtime.tracks.Idle then
		self:SwitchToClip("Idle")
		return
	end

	self:SwitchToClip(nil)
end

function AnimationServiceClient.OnFootstepEvent(self: AnimationServiceClient)
	local runtime = self.runtime
	if not runtime then
		return
	end

	local now = os.clock()
	if now - runtime.lastFootstepEventAt < FOOTSTEP_EVENT_DEDUPE_WINDOW then
		return
	end
	runtime.lastFootstepEventAt = now
	self:PlayFootstep(runtime, now)
end

function AnimationServiceClient.CanPlayFootstep(self: AnimationServiceClient, runtime: CharacterRuntime): boolean
	if runtime.activeClipName ~= "Walk" then
		return false
	end
	if not self.state.footstepsEnabled then
		return false
	end

	local humanoid = runtime.rig.humanoid
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	if runtime.movementSpeed <= FOOTSTEP_MOVE_DEADZONE then
		return false
	end

	return true
end

function AnimationServiceClient.OnJumpEvent(self: AnimationServiceClient)
	local runtime = self.runtime
	if not runtime then
		return
	end

	local now = os.clock()
	if now - runtime.lastJumpEventAt < JUMP_EVENT_DEDUPE_WINDOW then
		return
	end
	runtime.lastJumpEventAt = now
	self:PlayJump(runtime, now)
end

function AnimationServiceClient.CanPlayJump(_self: AnimationServiceClient, runtime: CharacterRuntime): boolean
	if runtime.activeClipName ~= "Jump" then
		return false
	end
	if not isJumpState(runtime.humanoidState) and not isFallState(runtime.humanoidState) then
		return false
	end
	return true
end

function AnimationServiceClient.PlayFootstep(
	self: AnimationServiceClient,
	runtime: CharacterRuntime,
	now: number
): boolean
	if not self:CanPlayFootstep(runtime) then
		return false
	end
	if now - runtime.lastFootstepAt < runtime.profile.footstepCooldown then
		return false
	end
	if AudioServiceClient.categoryGroups == nil then
		return false
	end

	local humanoid = runtime.rig.humanoid
	local soundAssetId, soundOptions = AnimationServiceUtils.GetFootstepSoundAssetIdAndOptions(
		runtime.rig.rootPart,
		humanoid.FloorMaterial,
		runtime.profile
	)
	if soundAssetId == nil or soundOptions == nil then
		return false
	end

	local playedSound = AudioServiceClient:PlaySfx(soundAssetId, soundOptions)
	if playedSound then
		runtime.lastFootstepAt = now
		return true
	end

	return false
end

function AnimationServiceClient.PlayJump(self: AnimationServiceClient, runtime: CharacterRuntime, now: number): boolean
	if not self:CanPlayJump(runtime) then
		return false
	end
	if now - runtime.lastJumpAt < runtime.profile.jumpCooldown then
		return false
	end
	if AudioServiceClient.categoryGroups == nil then
		return false
	end

	local soundAssetId, soundOptions =
		AnimationServiceUtils.GetJumpSoundAssetIdAndOptions(runtime.rig.rootPart, runtime.profile)
	if soundAssetId == nil or soundOptions == nil then
		return false
	end

	local playedSound = AudioServiceClient:PlaySfx(soundAssetId, soundOptions)
	if playedSound then
		runtime.lastJumpAt = now
		return true
	end

	return false
end

function AnimationServiceClient.ApplyState(self: AnimationServiceClient, profileNameRaw: any, footstepsEnabledRaw: any)
	local nextState =
		AnimationServiceUtils.CreateState(profileNameRaw, footstepsEnabledRaw, self.profileRegistry, self.state)
	local shouldRebuild = nextState.profileName ~= self.state.profileName
	self.state = nextState

	if shouldRebuild then
		self:RebuildRuntime()
	end
end

function AnimationServiceClient.SetProfile(_self: AnimationServiceClient, profileName: string)
	sendPacket("setProfile", profileName)
end

function AnimationServiceClient.SetFootstepsEnabled(_self: AnimationServiceClient, enabled: boolean)
	sendPacket("setFootstepsEnabled", enabled)
end

function AnimationServiceClient.RequestSync(_self: AnimationServiceClient)
	sendPacket("requestSync")
end

function AnimationServiceClient.Destroy(self: AnimationServiceClient)
	if self.runtimeJanitor then
		self.runtimeJanitor:Destroy()
	end
	if self.characterJanitor then
		self.characterJanitor:Destroy()
	end
	if self.janitor then
		self.janitor:Destroy()
	end
	self._serviceBag = nil
end
type AnimationServiceClient = typeof(AnimationServiceClient) & {
	_serviceBag: ServiceBag.ServiceBag?,
	localPlayer: Player,
	janitor: JanitorClass,
	characterJanitor: JanitorClass,
	runtimeJanitor: JanitorClass,
	character: Model?,
	runtime: CharacterRuntime?,
	profileRegistry: { [string]: AnimationProfile },
	state: AnimationServiceState,
	movementLocked: boolean,
}

return AnimationServiceClient :: AnimationServiceClient
