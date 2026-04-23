--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local Workspace = game:GetService("Workspace")

local RagdollServiceUtils = {}

export type CharacterRig = {
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	rigType: Enum.HumanoidRigType,
}

export type RagdollServiceState = {
	isRagdolled: boolean,
	reason: string,
	startedAt: number,
	scheduledRecoveryAt: number?,
	canRecover: boolean,
	sequence: number,
}

export type JointConstraintConfig = {
	upperAngle: number,
	twistLowerAngle: number,
	twistUpperAngle: number,
	maxFrictionTorque: number,
	restitution: number,
}

export type PartSnapshot = {
	part: BasePart,
	canCollide: boolean,
	massless: boolean,
	collisionGroup: string,
}

export type MotorSnapshot = {
	motor: Motor6D,
	wasEnabled: boolean,
}

export type HumanoidSnapshot = {
	autoRotate: boolean,
	platformStand: boolean,
	gettingUpEnabled: boolean,
	breakJointsOnDeath: boolean,
	requiresNeck: boolean,
}

export type BeginRagdollOptions = {
	reason: string?,
	impulse: Vector3?,
	runtimeFolderName: string?,
}

export type EndRagdollOptions = {
	restoreHumanoid: boolean?,
}

export type RagdollContext = {
	rig: CharacterRig,
	reason: string,
	createdAt: number,
	motorSnapshots: { MotorSnapshot },
	partSnapshots: { PartSnapshot },
	humanoidSnapshot: HumanoidSnapshot,
	createdInstances: { Instance },
}

local DEFAULT_REASON = "None"
local DEATH_REASON = "Death"
local CHARACTER_RESET_REASON = "CharacterReset"
local MANUAL_REASON = "Manual"

local DEFAULT_RUNTIME_FOLDER_NAME = "RagdollRuntime"
local DEFAULT_STATE_SEQUENCE = 0

local MIN_DURATION = 0.1
local MAX_DURATION = 30
local DEFAULT_SELF_RAGDOLL_DURATION = 2.25
local MAX_SELF_REQUEST_DURATION = 8
local MAX_ABS_PLANE_X = 4096
local PLANE_POSITION_EPSILON = 1e-3
local PLANE_LINEAR_VELOCITY_EPSILON = 1e-3

local DEFAULT_JOINT_CONFIG: JointConstraintConfig = {
	upperAngle = 40,
	twistLowerAngle = -40,
	twistUpperAngle = 40,
	maxFrictionTorque = 5,
	restitution = 0,
}

local JOINT_CONFIGS: { [string]: JointConstraintConfig } = {
	RootJoint = {
		upperAngle = 12,
		twistLowerAngle = -12,
		twistUpperAngle = 12,
		maxFrictionTorque = 40,
		restitution = 0,
	},
	Waist = {
		upperAngle = 22,
		twistLowerAngle = -18,
		twistUpperAngle = 18,
		maxFrictionTorque = 24,
		restitution = 0,
	},
	Neck = {
		upperAngle = 38,
		twistLowerAngle = -45,
		twistUpperAngle = 45,
		maxFrictionTorque = 16,
		restitution = 0.05,
	},
	LeftShoulder = {
		upperAngle = 95,
		twistLowerAngle = -78,
		twistUpperAngle = 78,
		maxFrictionTorque = 8,
		restitution = 0.02,
	},
	RightShoulder = {
		upperAngle = 95,
		twistLowerAngle = -78,
		twistUpperAngle = 78,
		maxFrictionTorque = 8,
		restitution = 0.02,
	},
	LeftElbow = {
		upperAngle = 10,
		twistLowerAngle = -6,
		twistUpperAngle = 6,
		maxFrictionTorque = 18,
		restitution = 0,
	},
	RightElbow = {
		upperAngle = 10,
		twistLowerAngle = -6,
		twistUpperAngle = 6,
		maxFrictionTorque = 18,
		restitution = 0,
	},
	LeftWrist = {
		upperAngle = 26,
		twistLowerAngle = -20,
		twistUpperAngle = 20,
		maxFrictionTorque = 7,
		restitution = 0,
	},
	RightWrist = {
		upperAngle = 26,
		twistLowerAngle = -20,
		twistUpperAngle = 20,
		maxFrictionTorque = 7,
		restitution = 0,
	},
	LeftHip = {
		upperAngle = 65,
		twistLowerAngle = -36,
		twistUpperAngle = 36,
		maxFrictionTorque = 14,
		restitution = 0,
	},
	RightHip = {
		upperAngle = 65,
		twistLowerAngle = -36,
		twistUpperAngle = 36,
		maxFrictionTorque = 14,
		restitution = 0,
	},
	LeftKnee = {
		upperAngle = 8,
		twistLowerAngle = -4,
		twistUpperAngle = 4,
		maxFrictionTorque = 20,
		restitution = 0,
	},
	RightKnee = {
		upperAngle = 8,
		twistLowerAngle = -4,
		twistUpperAngle = 4,
		maxFrictionTorque = 20,
		restitution = 0,
	},
	LeftAnkle = {
		upperAngle = 34,
		twistLowerAngle = -20,
		twistUpperAngle = 20,
		maxFrictionTorque = 8,
		restitution = 0,
	},
	RightAnkle = {
		upperAngle = 34,
		twistLowerAngle = -20,
		twistUpperAngle = 20,
		maxFrictionTorque = 8,
		restitution = 0,
	},
}

local JOINT_ALIASES: { [string]: string } = {
	Root = "RootJoint",
	["Left Shoulder"] = "LeftShoulder",
	["Right Shoulder"] = "RightShoulder",
	["Left Hip"] = "LeftHip",
	["Right Hip"] = "RightHip",
}

local IGNORED_MOTOR_NAMES: { [string]: boolean } = {
	RightGrip = true,
	LeftGrip = true,
}

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end

	local nextValue = value
	if minimum ~= nil and nextValue < minimum then
		nextValue = minimum
	end
	if maximum ~= nil and nextValue > maximum then
		nextValue = maximum
	end
	return nextValue
end

local function sanitizeOptionalTimestamp(value: any): number?
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end
	return value
end

local function getNow(): number
	local success, value = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if success and typeof(value) == "number" and value == value then
		return value
	end
	return os.clock()
end

local function resolveJointConfig(motorName: string): JointConstraintConfig
	local aliasName = JOINT_ALIASES[motorName]
	local resolvedName = if aliasName ~= nil then aliasName else motorName
	local config = JOINT_CONFIGS[resolvedName]
	if config then
		return config
	end
	return DEFAULT_JOINT_CONFIG
end

local function collectRagdollMotors(character: Model): { Motor6D }
	local motors: { Motor6D } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 ~= nil and descendant.Part1 ~= nil then
			if IGNORED_MOTOR_NAMES[descendant.Name] then
				continue
			end
			table.insert(motors, descendant)
		end
	end
	return motors
end

local function collectRagdollParts(motors: { Motor6D }, rootPart: BasePart): { BasePart }
	local parts: { BasePart } = { rootPart }
	local seenParts: { [BasePart]: boolean } = {
		[rootPart] = true,
	}

	for _, motor in motors do
		local part0 = motor.Part0
		if part0 and not seenParts[part0] then
			seenParts[part0] = true
			table.insert(parts, part0)
		end

		local part1 = motor.Part1
		if part1 and not seenParts[part1] then
			seenParts[part1] = true
			table.insert(parts, part1)
		end
	end

	return parts
end

local function capturePartSnapshots(parts: { BasePart }): { PartSnapshot }
	local snapshots: { PartSnapshot } = Sift.Array.create(#parts)
	for index, part in parts do
		snapshots[index] = {
			part = part,
			canCollide = part.CanCollide,
			massless = part.Massless,
			collisionGroup = part.CollisionGroup,
		}
	end
	return snapshots
end

local function shouldTreatAsHumanoidRootPart(rootPart: BasePart): boolean
	return rootPart.Name == "HumanoidRootPart"
end

local function applyPartRagdollState(partSnapshots: { PartSnapshot }, rootPart: BasePart)
	local hasHumanoidRootPartRole = shouldTreatAsHumanoidRootPart(rootPart)

	for _, snapshot in partSnapshots do
		local part = snapshot.part
		if part.Parent == nil then
			continue
		end

		if part == rootPart and hasHumanoidRootPartRole then
			part.CanCollide = false
			part.Massless = true
			continue
		end

		part.CanCollide = true
		part.Massless = false
	end
end

local function restorePartSnapshots(partSnapshots: { PartSnapshot })
	for _, snapshot in partSnapshots do
		local part = snapshot.part
		if part.Parent == nil then
			continue
		end

		part.CanCollide = snapshot.canCollide
		part.Massless = snapshot.massless
		part.CollisionGroup = snapshot.collisionGroup
	end
end

local function captureHumanoidSnapshot(humanoid: Humanoid): HumanoidSnapshot
	return {
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
		gettingUpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp),
		breakJointsOnDeath = humanoid.BreakJointsOnDeath,
		requiresNeck = humanoid.RequiresNeck,
	}
end

local function applyHumanoidRagdollState(humanoid: Humanoid)
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
end

local function restoreHumanoidState(humanoid: Humanoid, snapshot: HumanoidSnapshot)
	humanoid.AutoRotate = snapshot.autoRotate
	humanoid.PlatformStand = snapshot.platformStand
	humanoid.BreakJointsOnDeath = snapshot.breakJointsOnDeath
	humanoid.RequiresNeck = snapshot.requiresNeck
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, snapshot.gettingUpEnabled)

	if humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function sanitizePlaneX(valueRaw: any, fallback: number): number
	return sanitizeNumber(valueRaw, fallback, -MAX_ABS_PLANE_X, MAX_ABS_PLANE_X)
end

local function createConstraintsForMotor(
	motor: Motor6D,
	runtimeFolder: Folder,
	createdInstances: { Instance }
)
	local part0 = motor.Part0
	local part1 = motor.Part1
	if part0 == nil or part1 == nil then
		return
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = (`{motor.Name}_RagdollAttachment0`)
	attachment0.CFrame = motor.C0
	attachment0.Parent = part0

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = (`{motor.Name}_RagdollAttachment1`)
	attachment1.CFrame = motor.C1
	attachment1.Parent = part1

	local config = resolveJointConfig(motor.Name)

	local ballSocket = Instance.new("BallSocketConstraint")
	ballSocket.Name = (`{motor.Name}_RagdollSocket`)
	ballSocket.Attachment0 = attachment0
	ballSocket.Attachment1 = attachment1
	ballSocket.LimitsEnabled = true
	ballSocket.UpperAngle = config.upperAngle
	ballSocket.TwistLimitsEnabled = true
	ballSocket.TwistLowerAngle = config.twistLowerAngle
	ballSocket.TwistUpperAngle = config.twistUpperAngle
	ballSocket.MaxFrictionTorque = config.maxFrictionTorque
	ballSocket.Restitution = config.restitution
	ballSocket.Parent = runtimeFolder

	local noCollision = Instance.new("NoCollisionConstraint")
	noCollision.Name = (`{motor.Name}_RagdollNoCollision`)
	noCollision.Part0 = part0
	noCollision.Part1 = part1
	noCollision.Parent = runtimeFolder

	table.insert(createdInstances, attachment0)
	table.insert(createdInstances, attachment1)
	table.insert(createdInstances, ballSocket)
	table.insert(createdInstances, noCollision)
end

function RagdollServiceUtils.Now(): number
	return getNow()
end

function RagdollServiceUtils.SanitizeReason(reasonRaw: any, fallback: string?): string
	if typeof(reasonRaw) ~= "string" then
		return fallback or DEFAULT_REASON
	end

	if #reasonRaw <= 0 then
		return fallback or DEFAULT_REASON
	end

	if #reasonRaw > 64 then
		return string.sub(reasonRaw, 1, 64)
	end

	return reasonRaw
end

function RagdollServiceUtils.SanitizeDuration(
	durationRaw: any,
	fallback: number?,
	minimum: number?,
	maximum: number?
): number?
	local nextDuration: number?
	if typeof(durationRaw) == "number" and durationRaw == durationRaw then
		nextDuration = durationRaw
	elseif fallback ~= nil then
		nextDuration = fallback
	else
		nextDuration = nil
	end

	if nextDuration == nil then
		return nil
	end

	return math.clamp(nextDuration, minimum or MIN_DURATION, maximum or MAX_DURATION)
end

function RagdollServiceUtils.CreateState(
	isRagdolledRaw: any,
	reasonRaw: any,
	startedAtRaw: any,
	scheduledRecoveryAtRaw: any,
	canRecoverRaw: any,
	sequenceRaw: any,
	fallback: RagdollServiceState?
): RagdollServiceState
	local isRagdolled = isRagdolledRaw == true
	local fallbackStartedAt = if fallback then fallback.startedAt else getNow()
	local startedAt = sanitizeNumber(startedAtRaw, fallbackStartedAt, 0, nil)
	local fallbackSequence = if fallback then fallback.sequence else DEFAULT_STATE_SEQUENCE
	local sequence = sanitizeNumber(sequenceRaw, fallbackSequence, DEFAULT_STATE_SEQUENCE, nil)

	local reasonFallback = if fallback then fallback.reason else DEFAULT_REASON
	local reason = RagdollServiceUtils.SanitizeReason(reasonRaw, reasonFallback)
	local canRecover = if isRagdolled then canRecoverRaw ~= false else true

	local scheduledRecoveryAt: number? = nil
	if isRagdolled and canRecover then
		local parsedRecoveryAt = sanitizeOptionalTimestamp(scheduledRecoveryAtRaw)
		if parsedRecoveryAt ~= nil and parsedRecoveryAt > startedAt then
			scheduledRecoveryAt = parsedRecoveryAt
		end
	end

	return {
		isRagdolled = isRagdolled,
		reason = reason,
		startedAt = startedAt,
		scheduledRecoveryAt = scheduledRecoveryAt,
		canRecover = canRecover,
		sequence = sequence,
	}
end

function RagdollServiceUtils.CreateDefaultState(): RagdollServiceState
	return RagdollServiceUtils.CreateState(false, DEFAULT_REASON, getNow(), nil, true, DEFAULT_STATE_SEQUENCE, nil)
end

function RagdollServiceUtils.SanitizeState(stateRaw: any, fallback: RagdollServiceState?): RagdollServiceState
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	local fallbackState = if fallback then fallback else RagdollServiceUtils.CreateDefaultState()

	return RagdollServiceUtils.CreateState(
		(source :: any).isRagdolled,
		(source :: any).reason,
		(source :: any).startedAt,
		(source :: any).scheduledRecoveryAt,
		(source :: any).canRecover,
		(source :: any).sequence,
		fallbackState
	)
end

function RagdollServiceUtils.CloneState(state: RagdollServiceState): RagdollServiceState
	return {
		isRagdolled = state.isRagdolled,
		reason = state.reason,
		startedAt = state.startedAt,
		scheduledRecoveryAt = state.scheduledRecoveryAt,
		canRecover = state.canRecover,
		sequence = state.sequence,
	}
end

function RagdollServiceUtils.ResolveCharacterRig(character: Model?): CharacterRig?
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end

	local rootPartCandidate = character:FindFirstChild("HumanoidRootPart")
	if rootPartCandidate == nil then
		rootPartCandidate = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	end
	if rootPartCandidate == nil then
		rootPartCandidate = character.PrimaryPart
	end
	local rootPart = if rootPartCandidate and rootPartCandidate:IsA("BasePart") then rootPartCandidate else nil
	if rootPart == nil then
		return nil
	end

	return {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		rigType = humanoid.RigType,
	}
end

function RagdollServiceUtils.BeginRagdoll(rig: CharacterRig, options: BeginRagdollOptions?): RagdollContext?
	if rig.character.Parent == nil or rig.humanoid.Parent == nil or rig.rootPart.Parent == nil then
		return nil
	end

	local runtimeFolderName = if options and typeof(options.runtimeFolderName) == "string" and #options.runtimeFolderName > 0
		then options.runtimeFolderName
		else DEFAULT_RUNTIME_FOLDER_NAME
	local existingRuntimeFolder = rig.character:FindFirstChild(runtimeFolderName)
	if existingRuntimeFolder ~= nil then
		existingRuntimeFolder:Destroy()
	end

	local motors = collectRagdollMotors(rig.character)
	if #motors <= 0 then
		return nil
	end

	local runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = runtimeFolderName
	runtimeFolder.Parent = rig.character

	local createdInstances: { Instance } = { runtimeFolder }
	local motorSnapshots: { MotorSnapshot } = Sift.Array.create(#motors)

	for index, motor in motors do
		motorSnapshots[index] = {
			motor = motor,
			wasEnabled = motor.Enabled,
		}
		createConstraintsForMotor(motor, runtimeFolder, createdInstances)
		motor.Enabled = false
	end

	local ragdollParts = collectRagdollParts(motors, rig.rootPart)
	local partSnapshots = capturePartSnapshots(ragdollParts)
	local humanoidSnapshot = captureHumanoidSnapshot(rig.humanoid)

	applyPartRagdollState(partSnapshots, rig.rootPart)
	applyHumanoidRagdollState(rig.humanoid)

	local impulseRaw = if options ~= nil then options.impulse else nil
	if typeof(impulseRaw) == "Vector3" and impulseRaw.Magnitude > 0 then
		local mass = math.max(1, rig.rootPart.AssemblyMass)
		rig.rootPart:ApplyImpulse(impulseRaw * mass)
	end

	return {
		rig = rig,
		reason = RagdollServiceUtils.SanitizeReason(if options ~= nil then options.reason else nil, MANUAL_REASON),
		createdAt = getNow(),
		motorSnapshots = motorSnapshots,
		partSnapshots = partSnapshots,
		humanoidSnapshot = humanoidSnapshot,
		createdInstances = createdInstances,
	}
end

function RagdollServiceUtils.EndRagdoll(context: RagdollContext, options: EndRagdollOptions?)
	local restoreHumanoid = if options ~= nil and options.restoreHumanoid == false then false else true

	for index = #context.createdInstances, 1, -1 do
		local instance = context.createdInstances[index]
		if instance.Parent ~= nil then
			instance:Destroy()
		end
	end

	restorePartSnapshots(context.partSnapshots)

	for _, snapshot in context.motorSnapshots do
		local motor = snapshot.motor
		if motor.Parent == nil then
			continue
		end
		motor.Enabled = snapshot.wasEnabled
	end

	if restoreHumanoid and context.rig.humanoid.Parent ~= nil then
		restoreHumanoidState(context.rig.humanoid, context.humanoidSnapshot)
	end
end

function RagdollServiceUtils.EnforceRagdoll2DPlane(context: RagdollContext, planeXRaw: any)
	local rootPart = context.rig.rootPart
	if rootPart.Parent == nil then
		return
	end

	local planeX = sanitizePlaneX(planeXRaw, rootPart.Position.X)

	for _, snapshot in context.partSnapshots do
		local part = snapshot.part
		if part.Parent == nil then
			continue
		end

		local velocity = part.AssemblyLinearVelocity
		if math.abs(velocity.X) > PLANE_LINEAR_VELOCITY_EPSILON then
			part.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, velocity.Z)
		end
	end

	local rootPosition = rootPart.Position
	if math.abs(rootPosition.X - planeX) > PLANE_POSITION_EPSILON then
		local currentCFrame = rootPart.CFrame
		local rotationOnly = currentCFrame - rootPosition
		rootPart.CFrame = CFrame.new(planeX, rootPosition.Y, rootPosition.Z) * rotationOnly
	end
end

function RagdollServiceUtils.SetCharacterNetworkOwner(character: Model, owner: Player?)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				descendant:SetNetworkOwner(owner)
			end)
		end
	end
end

RagdollServiceUtils.DEFAULT_REASON = DEFAULT_REASON
RagdollServiceUtils.DEATH_REASON = DEATH_REASON
RagdollServiceUtils.CHARACTER_RESET_REASON = CHARACTER_RESET_REASON
RagdollServiceUtils.MANUAL_REASON = MANUAL_REASON
RagdollServiceUtils.DEFAULT_RUNTIME_FOLDER_NAME = DEFAULT_RUNTIME_FOLDER_NAME
RagdollServiceUtils.DEFAULT_SELF_RAGDOLL_DURATION = DEFAULT_SELF_RAGDOLL_DURATION
RagdollServiceUtils.MAX_SELF_REQUEST_DURATION = MAX_SELF_REQUEST_DURATION
RagdollServiceUtils.MIN_DURATION = MIN_DURATION
RagdollServiceUtils.MAX_DURATION = MAX_DURATION

RagdollServiceUtils.now = RagdollServiceUtils.Now
RagdollServiceUtils.sanitizeReason = RagdollServiceUtils.SanitizeReason
RagdollServiceUtils.sanitizeDuration = RagdollServiceUtils.SanitizeDuration
RagdollServiceUtils.createState = RagdollServiceUtils.CreateState
RagdollServiceUtils.createDefaultState = RagdollServiceUtils.CreateDefaultState
RagdollServiceUtils.sanitizeState = RagdollServiceUtils.SanitizeState
RagdollServiceUtils.cloneState = RagdollServiceUtils.CloneState
RagdollServiceUtils.resolveCharacterRig = RagdollServiceUtils.ResolveCharacterRig
RagdollServiceUtils.beginRagdoll = RagdollServiceUtils.BeginRagdoll
RagdollServiceUtils.endRagdoll = RagdollServiceUtils.EndRagdoll
RagdollServiceUtils.enforceRagdoll2DPlane = RagdollServiceUtils.EnforceRagdoll2DPlane
RagdollServiceUtils.setCharacterNetworkOwner = RagdollServiceUtils.SetCharacterNetworkOwner

return RagdollServiceUtils
