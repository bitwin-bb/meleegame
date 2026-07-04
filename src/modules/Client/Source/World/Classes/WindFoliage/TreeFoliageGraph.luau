local require = require(script.Parent.loader).load(script)

local TweenService = game:GetService("TweenService")

local Damp = require("Damp")
local DeterministicRNG = require("DeterministicRng")
local Vec = require("Vec")

local TreeFoliageGraph = {}
TreeFoliageGraph.__index = TreeFoliageGraph

export type WindSample = {
	vector: Vector3,
	direction: Vector3,
	strength: number,
	gustAlpha: number,
	detailAlpha: number,
	detailVector: Vector3,
	flutter: number,
}

export type LODState = {
	level: string,
	windScale: number,
	detailScale: number,
	disturbanceScale: number,
}

type BranchNode = {
	part: BasePart,
	index: number,
	parentIndex: number,
	depth: number,
	restLocal: CFrame,
	jointToPart: CFrame,
	restWorld: CFrame,
	currentWorld: CFrame,
	currentBend: Vector3,
	springVelocity: Vector3,
	reactiveBend: Vector3,
	phaseOffset: number,
	amplitudeScale: number,
	stiffness: number,
	damping: number,
	maxAngleRadians: number,
	swayScale: number,
	detailScale: number,
	inheritedScale: number,
	disturbanceScale: number,
	yawScale: number,
	recoverySpeed: number,
	activeTween: Tween?,
}

type LeafNode = {
	part: BasePart,
	index: number,
	parentIndex: number,
	restLocal: CFrame,
	restWorld: CFrame,
	currentWorld: CFrame,
	currentBend: Vector3,
	springVelocity: Vector3,
	reactiveBend: Vector3,
	phaseOffset: number,
	amplitudeScale: number,
	stiffness: number,
	damping: number,
	maxAngleRadians: number,
	swayScale: number,
	detailScale: number,
	inheritedScale: number,
	disturbanceScale: number,
	yawScale: number,
	translationScale: number,
	recoverySpeed: number,
	activeTween: Tween?,
}

type Config = {
	seed: number,
	bendStiffness: number,
	damping: number,
	maxBendAngle: number,
	heightMultiplier: number,
	swayAmplitude: number,
	gustSensitivity: number,
	recoverySpeed: number,
	disturbanceSensitivity: number,
	detailAmplitude: number?,
	tweenSmoothingEnabled: boolean?,
	tweenSmoothingDuration: number?,
	tweenSmoothingMaxDuration: number?,
}

export type TreeFoliageGraph = typeof(setmetatable({} :: any, TreeFoliageGraph))

local ZERO = Vector3.zero
local TREE_GRAPH_ATTRIBUTE = "WindFoliageTreeGraph"
local NODE_TYPE_ATTRIBUTE = "WindTreeNodeType"
local NODE_INDEX_ATTRIBUTE = "WindTreeNodeIndex"
local PARENT_INDEX_ATTRIBUTE = "WindTreeParentIndex"
local DEPTH_ATTRIBUTE = "WindTreeDepth"
local DEFAULT_TWEEN_SMOOTHING_DURATION = 0.16
local DEFAULT_TWEEN_SMOOTHING_MAX_DURATION = 0.24
local TWEEN_EASING_STYLE = Enum.EasingStyle.Sine
local TWEEN_EASING_DIRECTION = Enum.EasingDirection.Out

local function clampNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

local function GetDeterministicPhase(seed: number, salt: string): (number, number)
	local nodeSeed = DeterministicRNG.SeedFrom(("%s:%s"):format(tostring(seed), salt))
	local phaseOffset = (nodeSeed % 100000) / 100000 * math.pi * 2
	local amplitudeScale = 0.92 + ((nodeSeed % 8191) / 8191) * 0.18
	return phaseOffset, amplitudeScale
end

local function GetBranchBaseFrame(part: BasePart): CFrame
	return part.CFrame * CFrame.new(0, 0, part.Size.Z * 0.5)
end

local function GetBranchTipFrame(part: BasePart): CFrame
	return part.CFrame * CFrame.new(0, 0, -part.Size.Z * 0.5)
end

local function GetBranchTipFrameFromWorld(worldCFrame: CFrame, size: Vector3): CFrame
	return worldCFrame * CFrame.new(0, 0, -size.Z * 0.5)
end

local function getTweenSmoothingDuration(config: Config, presentationDt: number): number
	if config.tweenSmoothingEnabled == false then
		return 0
	end

	local maxDuration = clampNumber(config.tweenSmoothingMaxDuration, DEFAULT_TWEEN_SMOOTHING_MAX_DURATION, 0, 1)
	if maxDuration <= 0 then
		return 0
	end

	local cadenceDuration = if presentationDt > 0 then presentationDt else DEFAULT_TWEEN_SMOOTHING_DURATION
	local requestedDuration = clampNumber(config.tweenSmoothingDuration, cadenceDuration, 0, 1)
	if requestedDuration <= 0 then
		return 0
	end

	return math.min(requestedDuration, cadenceDuration, maxDuration)
end

local function cancelNodeTween(node: any)
	local tween = node.activeTween
	if tween ~= nil then
		tween:Cancel()
		node.activeTween = nil
	end
end

local function createTween(instance: Instance, tweenInfo: TweenInfo, goal: { [string]: any }): Tween?
	local ok, tween = pcall(function()
		return TweenService:Create(instance, tweenInfo, goal)
	end)
	return if ok then tween else nil
end

local function tweenNodeCFrame(node: any, config: Config, targetCFrame: CFrame, presentationDt: number)
	local part = node.part
	if part.Parent == nil then
		return
	end

	local duration = getTweenSmoothingDuration(config, presentationDt)
	cancelNodeTween(node)
	if duration <= 0 then
		part.CFrame = targetCFrame
		return
	end

	local tween = createTween(
		part,
		TweenInfo.new(duration, TWEEN_EASING_STYLE, TWEEN_EASING_DIRECTION),
		{ CFrame = targetCFrame }
	)
	if tween == nil then
		part.CFrame = targetCFrame
		return
	end

	node.activeTween = tween
	tween.Completed:Connect(function()
		if node.activeTween == tween then
			node.activeTween = nil
		end
	end)
	tween:Play()
end

local function GetTrunkBasePosition(part: BasePart): Vector3
	return GetBranchBaseFrame(part).Position
end

local function GetPlanarAngles(
	referenceFrame: CFrame,
	bendWorld: Vector3,
	maxAngleRadians: number,
	yawAmount: number
): (number, number, number)
	local planar = Vec.FlattenY(bendWorld)
	local magnitude = planar.Magnitude
	if magnitude <= 1e-5 or maxAngleRadians <= 0 then
		return 0, 0, 0
	end

	local direction = planar / magnitude
	local localDirection = referenceFrame:VectorToObjectSpace(direction)
	local finalAngle = math.min(1.25, magnitude) * maxAngleRadians
	local pitch = -localDirection.Z * finalAngle
	local roll = localDirection.X * finalAngle
	return pitch, yawAmount, roll
end

local function decayReactive(node: any, dt: number)
	node.reactiveBend = Damp.value(node.reactiveBend, ZERO, node.recoverySpeed, dt)
	if node.reactiveBend.Magnitude <= 1e-4 then
		node.reactiveBend = ZERO
	end
end

local function integrateSpring(node: any, target: Vector3, dt: number)
	local acceleration = (target - node.currentBend) * node.stiffness - node.springVelocity * node.damping
	node.springVelocity += acceleration * dt
	node.currentBend += node.springVelocity * dt
	if node.currentBend.Magnitude <= 1e-4 and node.springVelocity.Magnitude <= 1e-4 and target.Magnitude <= 1e-4 then
		node.currentBend = ZERO
		node.springVelocity = ZERO
	end
end

local function applyImpulse(node: any, impulseWorld: Vector3, scale: number)
	local scaledImpulse = impulseWorld * scale
	if scaledImpulse.Magnitude <= 1e-5 then
		return
	end
	node.reactiveBend += scaledImpulse
	if node.reactiveBend.Magnitude > 3.5 then
		node.reactiveBend = node.reactiveBend.Unit * 3.5
	end
	node.springVelocity += scaledImpulse * 0.34
end

function TreeFoliageGraph.New(modelRaw: any, configRaw: any): TreeFoliageGraph?
	if typeof(modelRaw) ~= "Instance" or not (modelRaw :: Instance):IsA("Model") then
		return nil
	end
	local model = modelRaw :: Model
	if model:GetAttribute(TREE_GRAPH_ATTRIBUTE) ~= true then
		return nil
	end

	local config = if typeof(configRaw) == "table" then configRaw :: Config else nil
	if config == nil then
		return nil
	end

	local trunkPart: BasePart? = nil
	local trunkIndex = 0
	local branchCandidates = {}
	local leafCandidates = {}
	local maxDepth = 0

	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local nodeType = descendant:GetAttribute(NODE_TYPE_ATTRIBUTE)
		if typeof(nodeType) ~= "string" then
			continue
		end

		local nodeIndexRaw = descendant:GetAttribute(NODE_INDEX_ATTRIBUTE)
		if typeof(nodeIndexRaw) ~= "number" then
			continue
		end
		local nodeIndex = nodeIndexRaw :: number
		local parentIndexRaw = descendant:GetAttribute(PARENT_INDEX_ATTRIBUTE)
		local parentIndex = if typeof(parentIndexRaw) == "number" then parentIndexRaw :: number else 0
		local depthRaw = descendant:GetAttribute(DEPTH_ATTRIBUTE)
		local depth = if typeof(depthRaw) == "number" then depthRaw :: number else 0

		if nodeType == "Trunk" then
			trunkPart = descendant
			trunkIndex = nodeIndex
			if depth > maxDepth then
				maxDepth = depth
			end
		elseif nodeType == "Branch" then
			if depth > maxDepth then
				maxDepth = depth
			end
			branchCandidates[#branchCandidates + 1] = {
				part = descendant,
				index = nodeIndex,
				parentIndex = parentIndex,
				depth = depth,
			}
		elseif nodeType == "Leaf" then
			leafCandidates[#leafCandidates + 1] = {
				part = descendant,
				index = nodeIndex,
				parentIndex = parentIndex,
			}
		end
	end

	if trunkPart == nil or trunkIndex == 0 then
		return nil
	end

	table.sort(branchCandidates, function(a: any, b: any): boolean
		if a.depth ~= b.depth then
			return a.depth < b.depth
		end
		return a.index < b.index
	end)
	table.sort(leafCandidates, function(a: any, b: any): boolean
		return a.index < b.index
	end)

	local trunkRestWorld = trunkPart.CFrame
	local trunkRestTipWorld = GetBranchTipFrame(trunkPart)
	local trunkThickness = math.max(0.25, trunkPart.Size.X)
	local branchNodesByIndex = {} :: { [number]: BranchNode }
	local branchOrder = {} :: { BranchNode }
	local leafNodes = {} :: { LeafNode }

	local baseStiffness = clampNumber(config.bendStiffness, 8.5, 0.1, 200)
	local baseDamping = clampNumber(config.damping, 6.3, 0, 100)
	local baseMaxAngleRadians = math.rad(clampNumber(config.maxBendAngle, 10, 0, 89))
	local baseRecovery = clampNumber(config.recoverySpeed, 3.2, 0, 30)
	local baseDisturbance = clampNumber(config.disturbanceSensitivity, 0.72, 0, 10)

	for _, candidate in branchCandidates do
		local parentAttachmentWorld = trunkRestTipWorld
		if candidate.parentIndex ~= trunkIndex and branchNodesByIndex[candidate.parentIndex] ~= nil then
			local parentBranch = branchNodesByIndex[candidate.parentIndex]
			parentAttachmentWorld = GetBranchTipFrame(parentBranch.part)
		end

		local part = candidate.part :: BasePart
		part.Anchored = true
		part.Massless = false

		local branchBaseWorld = GetBranchBaseFrame(part)
		local thinness = 1 - math.clamp(part.Size.X / trunkThickness, 0.1, 1)
		local depthAlpha = if maxDepth <= 0 then 1 else math.clamp(candidate.depth / maxDepth, 0, 1)
		local phaseOffset, amplitudeScale = GetDeterministicPhase(config.seed, ("branch:%d"):format(candidate.index))

		local node = {
			part = part,
			index = candidate.index,
			parentIndex = candidate.parentIndex,
			depth = candidate.depth,
			restLocal = parentAttachmentWorld:ToObjectSpace(branchBaseWorld),
			jointToPart = branchBaseWorld:ToObjectSpace(part.CFrame),
			restWorld = part.CFrame,
			currentWorld = part.CFrame,
			currentBend = ZERO,
			springVelocity = ZERO,
			reactiveBend = ZERO,
			phaseOffset = phaseOffset,
			amplitudeScale = amplitudeScale,
			stiffness = baseStiffness * (0.55 + thinness * 1.2),
			damping = baseDamping * (0.9 + (1 - thinness) * 0.55),
			maxAngleRadians = baseMaxAngleRadians * (0.45 + thinness * 1.1 + depthAlpha * 0.2),
			swayScale = (0.3 + thinness * 0.95 + depthAlpha * 0.3),
			detailScale = (0.35 + thinness * 0.8),
			inheritedScale = 0.45 + depthAlpha * 0.35,
			disturbanceScale = baseDisturbance * (0.45 + thinness * 0.8 + depthAlpha * 0.2),
			yawScale = 0.05 + thinness * 0.08,
			recoverySpeed = baseRecovery * (0.9 + thinness * 0.5),
			activeTween = nil,
		} :: BranchNode

		branchNodesByIndex[node.index] = node
		branchOrder[#branchOrder + 1] = node
	end

	for _, candidate in leafCandidates do
		local parentAttachmentWorld = trunkRestTipWorld
		if branchNodesByIndex[candidate.parentIndex] ~= nil then
			parentAttachmentWorld = GetBranchTipFrame(branchNodesByIndex[candidate.parentIndex].part)
		end

		local part = candidate.part :: BasePart
		part.Anchored = true
		part.Massless = false

		local parentBranch = branchNodesByIndex[candidate.parentIndex]
		local inheritedScale = if parentBranch ~= nil then 0.9 + math.min(0.4, parentBranch.depth * 0.05) else 0.95
		local phaseOffset, amplitudeScale = GetDeterministicPhase(config.seed, ("leaf:%d"):format(candidate.index))

		leafNodes[#leafNodes + 1] = {
			part = part,
			index = candidate.index,
			parentIndex = candidate.parentIndex,
			restLocal = parentAttachmentWorld:ToObjectSpace(part.CFrame),
			restWorld = part.CFrame,
			currentWorld = part.CFrame,
			currentBend = ZERO,
			springVelocity = ZERO,
			reactiveBend = ZERO,
			phaseOffset = phaseOffset,
			amplitudeScale = amplitudeScale,
			stiffness = baseStiffness * 1.45,
			damping = baseDamping * 0.8,
			maxAngleRadians = baseMaxAngleRadians * 1.15,
			swayScale = 0.28,
			detailScale = 1.55,
			inheritedScale = inheritedScale,
			disturbanceScale = baseDisturbance * 0.85,
			yawScale = 0.18,
			translationScale = 0.06,
			recoverySpeed = baseRecovery * 1.35,
			activeTween = nil,
		} :: LeafNode
	end

	local ok, _, boundsSize = pcall(function()
		return model:GetBoundingBox()
	end)
	local influenceRadius = 16
	if ok and typeof(boundsSize) == "Vector3" then
		influenceRadius = math.max(12, boundsSize.Magnitude * 0.65)
	end

	local self = setmetatable({
		model = model,
		config = config,
		trunk = trunkPart,
		trunkIndex = trunkIndex,
		trunkRestWorld = trunkRestWorld,
		trunkRestTipWorld = trunkRestTipWorld,
		branchNodesByIndex = branchNodesByIndex,
		branchOrder = branchOrder,
		leafNodes = leafNodes,
		parentAttachmentByIndex = {} :: { [number]: CFrame },
		rootPosition = GetTrunkBasePosition(trunkPart),
		influenceRadius = influenceRadius,
		destroyed = false,
	}, TreeFoliageGraph)

	self:Reset()
	return self
end

function TreeFoliageGraph.GetRootPosition(self: TreeFoliageGraph): Vector3
	return self.rootPosition
end

function TreeFoliageGraph.CancelTweens(self: TreeFoliageGraph)
	for _, branch in self.branchOrder do
		cancelNodeTween(branch)
	end

	for _, leaf in self.leafNodes do
		cancelNodeTween(leaf)
	end
end

function TreeFoliageGraph.Reset(self: TreeFoliageGraph)
	self:CancelTweens()
	self.trunk.CFrame = self.trunkRestWorld
	self.rootPosition = GetTrunkBasePosition(self.trunk)

	for _, branch in self.branchOrder do
		branch.currentBend = ZERO
		branch.springVelocity = ZERO
		branch.reactiveBend = ZERO
		branch.currentWorld = branch.restWorld
		branch.part.CFrame = branch.restWorld
	end

	for _, leaf in self.leafNodes do
		leaf.currentBend = ZERO
		leaf.springVelocity = ZERO
		leaf.reactiveBend = ZERO
		leaf.currentWorld = leaf.restWorld
		leaf.part.CFrame = leaf.restWorld
	end
end

function TreeFoliageGraph.AddDisturbance(self: TreeFoliageGraph, impulseWorld: Vector3, originWorldRaw: any?)
	if self.destroyed or impulseWorld.Magnitude <= 1e-5 then
		return
	end

	local originWorld = if typeof(originWorldRaw) == "Vector3" then originWorldRaw else self.rootPosition
	local influenceRadius = self.influenceRadius * 1.35

	for _, branch in self.branchOrder do
		local distance = (branch.currentWorld.Position - originWorld).Magnitude
		local falloff = (1 - math.clamp(distance / influenceRadius, 0, 1)) ^ 0.65
		if falloff > 0 then
			applyImpulse(branch, impulseWorld, falloff * branch.disturbanceScale)
		end
	end

	for _, leaf in self.leafNodes do
		local distance = (leaf.currentWorld.Position - originWorld).Magnitude
		local falloff = (1 - math.clamp(distance / influenceRadius, 0, 1)) ^ 0.65
		if falloff > 0 then
			applyImpulse(leaf, impulseWorld, falloff * leaf.disturbanceScale)
		end
	end
end

function TreeFoliageGraph.Step(
	self: TreeFoliageGraph,
	simulationTime: number,
	dt: number,
	windSample: WindSample,
	lod: LODState,
	presentationDtRaw: number?
)
	if self.destroyed or dt <= 0 then
		return
	end
	local presentationDt = if typeof(presentationDtRaw) == "number" then presentationDtRaw else dt

	self.trunk.CFrame = self.trunkRestWorld
	self.rootPosition = GetTrunkBasePosition(self.trunk)

	local heightMultiplier = clampNumber(self.config.heightMultiplier, 0.72, 0.1, 8)
	local swayAmplitude = clampNumber(self.config.swayAmplitude, 0.46, 0, 10)
	local gustSensitivity = clampNumber(self.config.gustSensitivity, 0.86, 0, 10)
	local detailAmplitude = clampNumber(self.config.detailAmplitude, 0.12, 0, 10)

	local parentAttachmentByIndex = self.parentAttachmentByIndex
	table.clear(parentAttachmentByIndex)
	parentAttachmentByIndex[self.trunkIndex] = self.trunkRestTipWorld

	for _, branch in self.branchOrder do
		decayReactive(branch, dt)

		local parentAttachmentWorld = parentAttachmentByIndex[branch.parentIndex] or self.trunkRestTipWorld
		local jointRestWorld = parentAttachmentWorld * branch.restLocal
		local phaseWave = math.sin(simulationTime * 0.8 + branch.phaseOffset)

		local target = (
			windSample.vector * swayAmplitude + windSample.direction * windSample.gustAlpha * gustSensitivity
		)
			* branch.swayScale
			* lod.windScale
		target += windSample.detailVector * detailAmplitude * branch.detailScale * lod.detailScale
		target += windSample.direction * phaseWave * 0.045 * branch.detailScale * lod.detailScale
		target += branch.reactiveBend * lod.disturbanceScale
		target *= heightMultiplier * branch.amplitudeScale
		target = Vec.FlattenY(target)
		if target.Magnitude > 1.2 then
			target = target.Unit * 1.2
		end

		integrateSpring(branch, target, dt)

		local yawAmount = windSample.flutter * branch.yawScale * lod.detailScale * 0.25
		local pitch, yaw, roll = GetPlanarAngles(jointRestWorld, branch.currentBend, branch.maxAngleRadians, yawAmount)
		local dynamicLocal = CFrame.Angles(pitch, yaw, roll)
		local finalBaseWorld = parentAttachmentWorld * branch.restLocal * dynamicLocal
		local finalWorld = finalBaseWorld * branch.jointToPart
		branch.currentWorld = finalWorld
		tweenNodeCFrame(branch, self.config, finalWorld, presentationDt)
		parentAttachmentByIndex[branch.index] = GetBranchTipFrameFromWorld(finalWorld, branch.part.Size)
	end

	for _, leaf in self.leafNodes do
		decayReactive(leaf, dt)

		local parentAttachmentWorld = parentAttachmentByIndex[leaf.parentIndex] or self.trunkRestTipWorld
		local flutterWave = math.sin(simulationTime * 4.6 + leaf.phaseOffset)

		local target = windSample.vector * swayAmplitude * leaf.swayScale * lod.windScale
		target += windSample.detailVector * detailAmplitude * leaf.detailScale * lod.detailScale
		target += windSample.direction * flutterWave * 0.14 * lod.detailScale
		target += leaf.reactiveBend * lod.disturbanceScale
		target *= leaf.amplitudeScale
		target = Vec.FlattenY(target)
		if target.Magnitude > 1.45 then
			target = target.Unit * 1.45
		end

		integrateSpring(leaf, target, dt)

		local restWorld = parentAttachmentWorld * leaf.restLocal
		local yawAmount = (windSample.flutter + flutterWave * 0.5) * leaf.yawScale * lod.detailScale
		local pitch, yaw, roll = GetPlanarAngles(restWorld, leaf.currentBend, leaf.maxAngleRadians, yawAmount)
		local localTranslation = restWorld:VectorToObjectSpace(leaf.currentBend) * leaf.translationScale * lod.windScale
		local dynamicLocal = CFrame.new(localTranslation) * CFrame.Angles(pitch, yaw, roll)
		local finalWorld = parentAttachmentWorld * leaf.restLocal * dynamicLocal
		leaf.currentWorld = finalWorld
		tweenNodeCFrame(leaf, self.config, finalWorld, presentationDt)
	end
end

function TreeFoliageGraph.Destroy(self: TreeFoliageGraph)
	if self.destroyed then
		return
	end
	self:Reset()
	table.clear(self.parentAttachmentByIndex)
	self.destroyed = true
end
return TreeFoliageGraph
