--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioServiceUtils)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local EyeOfCthulhuMotion = require(script.Parent.Motion)
local Ripple = require(ReplicatedStorage.Packages.Ripple)

type BossSnapshot = BossServiceUtils.BossSnapshot
type Motion<T> = Ripple.Motion<T>
type SpringOptions = Ripple.SpringOptions

type CameraShakerObject = {
	ShakeOnce: (
		self: CameraShakerObject,
		magnitude: number,
		roughness: number,
		fadeInTime: number?,
		fadeOutTime: number?,
		posInfluence: Vector3?,
		rotInfluence: Vector3?
	) -> (),
}

type PresentationRuntime = {
	model: Model?,
	rootPart: BasePart?,
	snapshot: BossSnapshot,
	cameraShaker: CameraShakerObject?,
	shellMotion: Motion<CFrame>,
	anticipationMotion: Motion<number>,
	recoilMotion: Motion<number>,
	damageMotion: Motion<number>,
	roarMotion: Motion<number>,
	deathMotion: Motion<number>,
	transformMotion: Motion<number>,
	startedAt: number,
	lastDashPulseToken: number,
	lastDamagePulseToken: number,
	lastRoarPulseToken: number,
	lastTransformPulseToken: number,
	lastDeathPulseToken: number,
	lastServantPulseToken: number,
	partRefs: {
		iris: BasePart?,
		pupil: BasePart?,
		jaw: BasePart?,
	},
	soundRefs: {
		roar: Sound?,
	},
	createdRuntimeSounds: { [Sound]: boolean },
	deformParts: { BasePart },
	baseLocalCFrames: { [BasePart]: CFrame },
}

local EyeOfCthulhuPresentation = {}
local EYE_ROAR_SOUND_ID = AudioServiceUtils.resolveSoundAssetId((((AudioRegistry :: any).Npcs :: any).Bosses :: any).EyeOfCthulhu.roar)

local SHELL_SPRING: SpringOptions = {
	frequency = 5.2,
	damping = 0.82,
}

local IMPULSE_SPRING: SpringOptions = {
	frequency = 6.4,
	damping = 0.76,
}

local function resolvePartRefs(
	model: Model?
): ({ [string]: BasePart? }, { BasePart }, { [BasePart]: CFrame }, BasePart?)
	local refs = {
		iris = nil :: BasePart?,
		pupil = nil :: BasePart?,
		jaw = nil :: BasePart?,
	}
	local deformParts = {}
	local baseLocalCFrames: { [BasePart]: CFrame } = {}
	if model == nil then
		return refs, deformParts, baseLocalCFrames, nil
	end

	local rootPart = BossServiceUtils.resolveRootPart(model)
	if rootPart == nil then
		return refs, deformParts, baseLocalCFrames, nil
	end

	local iris = BossServiceUtils.findFirstDescendantByNormalizedName(model, { "Iris", "Eye", "PupilSocket" })
	if iris ~= nil and iris:IsA("BasePart") then
		refs.iris = iris
	end
	local pupil = BossServiceUtils.findFirstDescendantByNormalizedName(model, { "Pupil", "PupilCore", "EyePupil" })
	if pupil ~= nil and pupil:IsA("BasePart") then
		refs.pupil = pupil
	end
	local jaw = BossServiceUtils.findFirstDescendantByNormalizedName(model, { "Jaw", "Mouth", "Teeth" })
	if jaw ~= nil and jaw:IsA("BasePart") then
		refs.jaw = jaw
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= rootPart then
			baseLocalCFrames[descendant] = rootPart.CFrame:ToObjectSpace(descendant.CFrame)
			table.insert(deformParts, descendant)
		end
	end

	return refs, deformParts, baseLocalCFrames, rootPart
end

local function resolveTargetPosition(snapshot: BossSnapshot): Vector3?
	local targetUserId = snapshot.targetUserId
	if targetUserId == nil then
		return nil
	end

	local player = Players:GetPlayerByUserId(targetUserId)
	if player == nil then
		return nil
	end

	local rootPart = BossServiceUtils.resolveCharacterRootPart(player)
	if rootPart == nil then
		return nil
	end
	return rootPart.Position
end

local function restartSound(sound: Sound)
	pcall(function()
		sound:Stop()
		sound.TimePosition = 0
		sound:Play()
	end)
end

local function playModelSound(runtime: PresentationRuntime, candidateNames: { string })
	local model = runtime.model
	if model == nil then
		return
	end

	local sound = BossServiceUtils.findFirstDescendantByNormalizedName(model, candidateNames)
	if sound ~= nil and sound:IsA("Sound") then
		restartSound(sound :: Sound)
	end
end

local function ensureRoarSound(runtime: PresentationRuntime): Sound?
	local roarSound = runtime.soundRefs.roar
	if roarSound ~= nil and roarSound.Parent ~= nil then
		return roarSound
	end

	local model = runtime.model
	if model == nil then
		return nil
	end

	local existingSound = BossServiceUtils.findFirstDescendantByNormalizedName(model, { "Roar" })
	if existingSound ~= nil and existingSound:IsA("Sound") then
		runtime.soundRefs.roar = existingSound :: Sound
		return runtime.soundRefs.roar
	end

	local rootPart = runtime.rootPart
	if rootPart == nil or EYE_ROAR_SOUND_ID == nil then
		return nil
	end

	local categoryGroups = AudioServiceUtils.ensureCategoryGroups(SoundService)
	local createdSound = AudioServiceUtils.createSoundInstance(
		EYE_ROAR_SOUND_ID,
		{
			category = "SFX",
			volume = 1,
			rollOffMaxDistance = 120,
			emitterSize = 10,
			autoDestroy = false,
			parent = rootPart,
		},
		rootPart,
		categoryGroups.SFX
	)
	if createdSound == nil then
		return nil
	end

	createdSound.Name = "Roar"
	runtime.soundRefs.roar = createdSound
	runtime.createdRuntimeSounds[createdSound] = true
	return createdSound
end

local function playRoarSound(runtime: PresentationRuntime)
	local roarSound = ensureRoarSound(runtime)
	if roarSound ~= nil then
		restartSound(roarSound)
		return
	end

	playModelSound(runtime, { "Roar", "Scream", "Transform" })
end

local function shake(runtime: PresentationRuntime, magnitude: number, roughness: number, fadeOut: number)
	local cameraShaker = runtime.cameraShaker
	if cameraShaker == nil then
		return
	end
	pcall(function()
		cameraShaker:ShakeOnce(
			magnitude,
			roughness,
			0.03,
			fadeOut,
			Vector3.new(0.14, 0.14, 0.14),
			Vector3.new(0.8, 0.4, 0.4)
		)
	end)
end

local function getSuggestedOffset(snapshot: BossSnapshot): Vector3
	local motion = snapshot.motion
	if motion.localPresentationOffset ~= nil then
		return motion.localPresentationOffset
	end
	return Vector3.zero
end

local function computeShellTarget(
	snapshot: BossSnapshot,
	anticipation: number,
	recoil: number,
	damage: number,
	roar: number,
	transform: number,
	death: number
): CFrame
	local stateTime = snapshot.stateTime
	local hoverLift = if snapshot.state == "SpawnIntro"
		then math.sin(stateTime * 2.1) * 0.55
		else if snapshot.state == "Phase1Hover" or snapshot.state == "Phase1ServantBurst"
			then math.sin(stateTime * 3.9) * 0.22
			else if snapshot.state == "Phase2HoverIdle" or snapshot.state == "Phase2Hover"
				then math.sin(stateTime * 5.1) * 0.14
				else 0
	local suggestedOffset = getSuggestedOffset(snapshot)
	local forwardOffset = anticipation * -1.1 + recoil * 1.45
	local verticalOffset = hoverLift + roar * 0.95 + transform * 1.25 - death * 1.55 + damage * 0.22
	local shellOffset = suggestedOffset + Vector3.new(0, verticalOffset, forwardOffset)
	local shellTilt = CFrame.Angles(
		math.rad((recoil - anticipation * 0.7 + roar * 0.35) * 10),
		0,
		math.rad(damage * math.sin(os.clock() * 28) * 3.2)
	)

	return CFrame.new(shellOffset) * shellTilt
end

function EyeOfCthulhuPresentation.CreateRuntime(
	modelRaw: any,
	snapshot: BossSnapshot,
	cameraShaker: CameraShakerObject?
): PresentationRuntime
	local model = if typeof(modelRaw) == "Instance" and modelRaw:IsA("Model") then modelRaw else nil
	local partRefs, deformParts, baseLocalCFrames, rootPart = resolvePartRefs(model)
	local soundRefs: { roar: Sound? } = {
		roar = nil :: Sound?,
	}
	local createdRuntimeSounds: { [Sound]: boolean } = {}

	local runtime: PresentationRuntime = {
		model = model,
		rootPart = rootPart,
		snapshot = snapshot,
		cameraShaker = cameraShaker,
		shellMotion = Ripple.createMotion(CFrame.new()),
		anticipationMotion = Ripple.createMotion(0),
		recoilMotion = Ripple.createMotion(0),
		damageMotion = Ripple.createMotion(0),
		roarMotion = Ripple.createMotion(0),
		deathMotion = Ripple.createMotion(0),
		transformMotion = Ripple.createMotion(0),
		startedAt = os.clock(),
		lastDashPulseToken = snapshot.presentation.dashPulseToken,
		lastDamagePulseToken = snapshot.presentation.damagePulseToken,
		lastRoarPulseToken = snapshot.presentation.roarPulseToken,
		lastTransformPulseToken = snapshot.presentation.transformPulseToken,
		lastDeathPulseToken = snapshot.presentation.deathPulseToken,
		lastServantPulseToken = snapshot.presentation.servantPulseToken,
		partRefs = partRefs,
		soundRefs = soundRefs,
		createdRuntimeSounds = createdRuntimeSounds,
		deformParts = deformParts,
		baseLocalCFrames = baseLocalCFrames,
	}

	ensureRoarSound(runtime)
	return runtime
end

function EyeOfCthulhuPresentation.ApplySnapshot(runtime: PresentationRuntime, snapshot: BossSnapshot)
	runtime.snapshot = snapshot

	if snapshot.presentation.dashPulseToken ~= runtime.lastDashPulseToken then
		runtime.lastDashPulseToken = snapshot.presentation.dashPulseToken
		runtime.anticipationMotion:immediate(1)
		runtime.recoilMotion:immediate(0.95)
		playModelSound(runtime, { "Charge", "Dash" })
		shake(runtime, 1.25, 12, 0.18)
	end

	if snapshot.presentation.damagePulseToken ~= runtime.lastDamagePulseToken then
		runtime.lastDamagePulseToken = snapshot.presentation.damagePulseToken
		runtime.damageMotion:immediate(1)
	end

	if snapshot.presentation.roarPulseToken ~= runtime.lastRoarPulseToken then
		runtime.lastRoarPulseToken = snapshot.presentation.roarPulseToken
		runtime.roarMotion:immediate(1)
		playRoarSound(runtime)
		shake(runtime, 1.8, 10, 0.3)
	end

	if snapshot.presentation.transformPulseToken ~= runtime.lastTransformPulseToken then
		runtime.lastTransformPulseToken = snapshot.presentation.transformPulseToken
		runtime.transformMotion:immediate(1)
		shake(runtime, 2.25, 8, 0.45)
	end

	if snapshot.presentation.deathPulseToken ~= runtime.lastDeathPulseToken then
		runtime.lastDeathPulseToken = snapshot.presentation.deathPulseToken
		runtime.deathMotion:immediate(1)
		playModelSound(runtime, { "Death", "Roar", "Impact" })
		shake(runtime, 2.75, 7.5, 0.55)
	end

	if snapshot.presentation.servantPulseToken ~= runtime.lastServantPulseToken then
		runtime.lastServantPulseToken = snapshot.presentation.servantPulseToken
		shake(runtime, 0.7, 14, 0.08)
	end
end

function EyeOfCthulhuPresentation.Step(runtime: PresentationRuntime, dtRaw: any)
	local model = runtime.model
	if model == nil or model.Parent == nil then
		return
	end

	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 1 / 60, 0, 1)
	local snapshot = runtime.snapshot
	local rootPart = BossServiceUtils.resolveRootPart(model)
	if rootPart ~= nil then
		runtime.rootPart = rootPart
	else
		rootPart = runtime.rootPart
	end
	if rootPart == nil then
		return
	end
	ensureRoarSound(runtime)

	runtime.anticipationMotion:spring(0, IMPULSE_SPRING)
	runtime.recoilMotion:spring(0, IMPULSE_SPRING)
	runtime.damageMotion:spring(0, IMPULSE_SPRING)
	runtime.roarMotion:spring(0, IMPULSE_SPRING)
	runtime.deathMotion:spring(0, {
		frequency = 2.5,
		damping = 0.9,
	})
	runtime.transformMotion:spring(0, {
		frequency = 3.3,
		damping = 0.78,
	})

	local anticipation = runtime.anticipationMotion:step(dt)
	local recoil = runtime.recoilMotion:step(dt)
	local damage = math.min(runtime.damageMotion:step(dt), 1.1)
	local roar = runtime.roarMotion:step(dt)
	local death = runtime.deathMotion:step(dt)
	local transform = runtime.transformMotion:step(dt)
	local desiredShell = computeShellTarget(snapshot, anticipation, recoil, damage, roar, transform, death)
	runtime.shellMotion:spring(desiredShell, SHELL_SPRING)
	local shellCFrame = runtime.shellMotion:step(dt)

	for _, part in runtime.deformParts do
		if part.Parent == nil then
			continue
		end

		local base = runtime.baseLocalCFrames[part]
		if base ~= nil then
			part.CFrame = rootPart.CFrame * shellCFrame * base
		end
	end

	local targetPosition = resolveTargetPosition(snapshot)
	local pupilOffset = EyeOfCthulhuMotion.computePupilOffset(rootPart.Position, targetPosition, 0.85)

	local iris = runtime.partRefs.iris
	if iris ~= nil and iris.Parent ~= nil then
		local base = runtime.baseLocalCFrames[iris]
		if base ~= nil then
			iris.CFrame = rootPart.CFrame
				* shellCFrame
				* base
				* CFrame.new(Vector3.new(0, pupilOffset.Y * 0.35, pupilOffset.Z * 0.35))
		end
	end

	local pupil = runtime.partRefs.pupil
	if pupil ~= nil and pupil.Parent ~= nil then
		local base = runtime.baseLocalCFrames[pupil]
		if base ~= nil then
			pupil.CFrame = rootPart.CFrame * shellCFrame * base * CFrame.new(pupilOffset)
		end
	end

	local jaw = runtime.partRefs.jaw
	if jaw ~= nil and jaw.Parent ~= nil then
		local base = runtime.baseLocalCFrames[jaw]
		if base ~= nil then
			local jawOpenAlpha = if snapshot.phase <= 1
				then roar * 0.3 + transform * 0.45
				else roar * 0.85 + transform * 0.72 + anticipation * 0.15
			jaw.CFrame = rootPart.CFrame
				* shellCFrame
				* base
				* CFrame.new(0, -jawOpenAlpha * 0.4, -jawOpenAlpha * 0.18)
				* CFrame.Angles(math.rad(jawOpenAlpha * 14), 0, 0)
		end
	end
end

function EyeOfCthulhuPresentation.Destroy(runtime: PresentationRuntime)
	local model = runtime.model
	local rootPart = runtime.rootPart
	if model ~= nil and model.Parent ~= nil and rootPart ~= nil and rootPart.Parent ~= nil then
		for part, localCFrame in runtime.baseLocalCFrames do
			if part.Parent ~= nil then
				part.CFrame = rootPart.CFrame * localCFrame
			end
		end
	end

	for sound in runtime.createdRuntimeSounds do
		if sound.Parent ~= nil then
			sound:Destroy()
		end
		runtime.createdRuntimeSounds[sound] = nil
	end

	runtime.shellMotion:destroy()
	runtime.anticipationMotion:destroy()
	runtime.recoilMotion:destroy()
	runtime.damageMotion:destroy()
	runtime.roarMotion:destroy()
	runtime.deathMotion:destroy()
	runtime.transformMotion:destroy()
end

EyeOfCthulhuPresentation.createRuntime = EyeOfCthulhuPresentation.CreateRuntime
EyeOfCthulhuPresentation.applySnapshot = EyeOfCthulhuPresentation.ApplySnapshot
EyeOfCthulhuPresentation.step = EyeOfCthulhuPresentation.Step
EyeOfCthulhuPresentation.destroy = EyeOfCthulhuPresentation.Destroy

return EyeOfCthulhuPresentation
