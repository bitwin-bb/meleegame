--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeterministicRNG = require(ReplicatedStorage.Shared.Modules.Core.DeterministicRNG)

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
}

export type TreeFoliageGraph = typeof(setmetatable({} :: any, TreeFoliageGraph))

local ZERO = Vector3.zero
local TREE_GRAPH_ATTRIBUTE = "WindFoliageTreeGraph"
local NODE_TYPE_ATTRIBUTE = "WindTreeNodeType"
local NODE_INDEX_ATTRIBUTE = "WindTreeNodeIndex"
local PARENT_INDEX_ATTRIBUTE = "WindTreeParentIndex"
local DEPTH_ATTRIBUTE = "WindTreeDepth"

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

local function resolveDeterministicPhase(seed: number, salt: string): (number, number)
	local nodeSeed = DeterministicRNG.seedFrom(("%s:%s"):format(tostring(seed), salt))
	local phaseOffset = (nodeSeed % 100000) / 100000 * math.pi * 2
	local amplitudeScale = 0.92 + ((nodeSeed % 8191) / 8191) * 0.18
	return phaseOffset, amplitudeScale
end

local function resolveBranchBaseFrame(part: BasePart): CFrame
	return part.CFrame * CFrame.new(0, 0, part.Size.Z * 0.5)
end

local function resolveBranchTipFrame(part: BasePart): CFrame
	return part.CFrame * CFrame.new(0, 0, -part.Size.Z * 0.5)
end

local function resolveTrunkBasePosition(part: BasePart): Vector3
	return resolveBranchBaseFrame(part).Position
end

local function resolvePlanarAngles(referenceFrame: CFrame, bendWorld: Vector3, maxAngleRadians: number, yawAmount: number): (number, number, number)
	local planar = Vector3.new(bendWorld.X, 0, bendWorld.Z)
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
	local recoveryAlpha = math.exp(-node.recoverySpeed * dt)
	node.reactiveBend *= recoveryAlpha
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
	if node.reactiveBend.Magnitude > 2 then
		node.reactiveBend = node.reactiveBend.Unit * 2
	end
	node.springVelocity += scaledImpulse * 0.22
end

function TreeFoliageGraph.new(modelRaw: any, configRaw: any): TreeFoliageGraph?
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

		local nodeIndex = descendant:GetAttribute(NODE_INDEX_ATTRIBUTE)
		if typeof(nodeIndex) ~= "number" then
			continue
		end
		local parentIndex = descendant:GetAttribute(PARENT_INDEX_ATTRIBUTE)
		if typeof(parentIndex) ~= "number" then
			parentIndex = 0
		end
		local depth = descendant:GetAttribute(DEPTH_ATTRIBUTE)
		if typeof(depth) ~= "number" then
			depth = 0
		end

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
	local trunkRestTipWorld = resolveBranchTipFrame(trunkPart)
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
			parentAttachmentWorld = resolveBranchTipFrame(parentBranch.part)
		end

		local part = candidate.part :: BasePart
		part.Anchored = true
		part.Massless = false

		local branchBaseWorld = resolveBranchBaseFrame(part)
		local thinness = 1 - math.clamp(part.Size.X / trunkThickness, 0.1, 1)
		local depthAlpha = if maxDepth <= 0 then 1 else math.clamp(candidate.depth / maxDepth, 0, 1)
		local phaseOffset, amplitudeScale =
			resolveDeterministicPhase(config.seed, ("branch:%d"):format(candidate.index))

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
		} :: BranchNode

		branchNodesByIndex[node.index] = node
		branchOrder[#branchOrder + 1] = node
	end

	for _, candidate in leafCandidates do
		local parentAttachmentWorld = trunkRestTipWorld
		if branchNodesByIndex[candidate.parentIndex] ~= nil then
			parentAttachmentWorld = resolveBranchTipFrame(branchNodesByIndex[candidate.parentIndex].part)
		end

		local part = candidate.part :: BasePart
		part.Anchored = true
		part.Massless = false

		local parentBranch = branchNodesByIndex[candidate.parentIndex]
		local inheritedScale = if parentBranch ~= nil then 0.9 + math.min(0.4, parentBranch.depth * 0.05) else 0.95
		local phaseOffset, amplitudeScale =
			resolveDeterministicPhase(config.seed, ("leaf:%d"):format(candidate.index))

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
		} :: LeafNode
	end

	local ok, _, boundsSize = pcall(function()
		return model:GetBoundingBox()
	end)
	local influenceRadius = 16
	if ok and typeof(boundsSize) == "Vector3" then
		influenceRadius = math.max(8, boundsSize.Magnitude * 0.45)
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
		rootPosition = resolveTrunkBasePosition(trunkPart),
		influenceRadius = influenceRadius,
		destroyed = false,
	}, TreeFoliageGraph)

	self:reset()
	return self
end

function TreeFoliageGraph.getRootPosition(self: TreeFoliageGraph): Vector3
	return self.rootPosition
end

function TreeFoliageGraph.reset(self: TreeFoliageGraph)
	self.trunk.CFrame = self.trunkRestWorld
	self.rootPosition = resolveTrunkBasePosition(self.trunk)

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

function TreeFoliageGraph.addDisturbance(self: TreeFoliageGraph, impulseWorld: Vector3, originWorldRaw: any?)
	if self.destroyed or impulseWorld.Magnitude <= 1e-5 then
		return
	end

	local originWorld = if typeof(originWorldRaw) == "Vector3" then originWorldRaw else self.rootPosition

	for _, branch in self.branchOrder do
		local distance = (branch.currentWorld.Position - originWorld).Magnitude
		local falloff = 1 - math.clamp(distance / self.influenceRadius, 0, 1)
		if falloff > 0 then
			applyImpulse(branch, impulseWorld, falloff * branch.disturbanceScale)
		end
	end

	for _, leaf in self.leafNodes do
		local distance = (leaf.currentWorld.Position - originWorld).Magnitude
		local falloff = 1 - math.clamp(distance / self.influenceRadius, 0, 1)
		if falloff > 0 then
			applyImpulse(leaf, impulseWorld, falloff * leaf.disturbanceScale)
		end
	end
end

function TreeFoliageGraph.step(
	self: TreeFoliageGraph,
	simulationTime: number,
	dt: number,
	windSample: WindSample,
	lod: LODState
)
	if self.destroyed or dt <= 0 then
		return
	end

	self.trunk.CFrame = self.trunkRestWorld
	self.rootPosition = resolveTrunkBasePosition(self.trunk)

	local heightMultiplier = clampNumber(self.config.heightMultiplier, 0.72, 0.1, 8)
	local swayAmplitude = clampNumber(self.config.swayAmplitude, 0.46, 0, 10)
	local gustSensitivity = clampNumber(self.config.gustSensitivity, 0.86, 0, 10)
	local detailAmplitude = clampNumber(self.config.detailAmplitude, 0.12, 0, 10)

	local parentAttachmentByIndex = {
		[self.trunkIndex] = self.trunkRestTipWorld,
	} :: { [number]: CFrame }

	for _, branch in self.branchOrder do
		decayReactive(branch, dt)

		local parentAttachmentWorld = parentAttachmentByIndex[branch.parentIndex] or self.trunkRestTipWorld
		local jointRestWorld = parentAttachmentWorld * branch.restLocal
		local phaseWave = math.sin(simulationTime * 0.8 + branch.phaseOffset)

		local target =
			(windSample.vector * swayAmplitude + windSample.direction * windSample.gustAlpha * gustSensitivity)
			* branch.swayScale
			* lod.windScale
		target += windSample.detailVector * detailAmplitude * branch.detailScale * lod.detailScale
		target += windSample.direction * phaseWave * 0.045 * branch.detailScale * lod.detailScale
		target += branch.reactiveBend * lod.disturbanceScale
		target *= heightMultiplier * branch.amplitudeScale
		target = Vector3.new(target.X, 0, target.Z)
		if target.Magnitude > 1.2 then
			target = target.Unit * 1.2
		end

		integrateSpring(branch, target, dt)

		local yawAmount = windSample.flutter * branch.yawScale * lod.detailScale * 0.25
		local pitch, yaw, roll =
			resolvePlanarAngles(jointRestWorld, branch.currentBend, branch.maxAngleRadians, yawAmount)
		local dynamicLocal = CFrame.Angles(pitch, yaw, roll)
		local finalBaseWorld = parentAttachmentWorld * branch.restLocal * dynamicLocal
		local finalWorld = finalBaseWorld * branch.jointToPart
		branch.currentWorld = finalWorld
		branch.part.CFrame = finalWorld
		parentAttachmentByIndex[branch.index] = resolveBranchTipFrame(branch.part)
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
		target = Vector3.new(target.X, 0, target.Z)
		if target.Magnitude > 1.45 then
			target = target.Unit * 1.45
		end

		integrateSpring(leaf, target, dt)

		local restWorld = parentAttachmentWorld * leaf.restLocal
		local yawAmount = (windSample.flutter + flutterWave * 0.5) * leaf.yawScale * lod.detailScale
		local pitch, yaw, roll = resolvePlanarAngles(restWorld, leaf.currentBend, leaf.maxAngleRadians, yawAmount)
		local localTranslation = restWorld:VectorToObjectSpace(leaf.currentBend) * leaf.translationScale * lod.windScale
		local dynamicLocal = CFrame.new(localTranslation) * CFrame.Angles(pitch, yaw, roll)
		local finalWorld = parentAttachmentWorld * leaf.restLocal * dynamicLocal
		leaf.currentWorld = finalWorld
		leaf.part.CFrame = finalWorld
	end
end

function TreeFoliageGraph.destroy(self: TreeFoliageGraph)
	if self.destroyed then
		return
	end
	self:reset()
	self.destroyed = true
end

return TreeFoliageGraph
