--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local Workspace = game:GetService("Workspace")
local WorldGenerationColor = require(script:FindFirstAncestor("game").Shared.Modules.Items.WorldGenerationColor)
local TagBinder = require(script:FindFirstAncestor("game").Shared.Binders.TagBinder)

local ProceduralTree = {}
ProceduralTree.__index = ProceduralTree

type BranchAlgorithm = "Recursive" | "LSystemStyle"

export type ProceduralTreeConfig = {
	Algorithm: BranchAlgorithm?,
	Seed: number?,
	MaxDepth: number?,
	BranchAngleRange: NumberRange?,
	LengthScale: number?,
	ThicknessScale: number?,
	BranchChance: number?,
	InitialLength: number?,
	InitialThickness: number?,
	TrunkWobbleAngle: number?,
	UpwardBias: number?,
	MinBranchLength: number?,
	MinBranchThickness: number?,
	MinBranchesPerNode: number?,
	MaxBranchesPerNode: number?,
	LengthJitter: NumberRange?,
	ThicknessJitter: NumberRange?,
	LeafSizeMin: Vector3?,
	LeafSizeMax: Vector3?,
	LeafRotationVariance: number?,
	LeavesPerTerminalMin: number?,
	LeavesPerTerminalMax: number?,
	MaxBranchParts: number?,
	MaxLeafParts: number?,
	UseWelds: boolean?,
	BranchCanCollide: boolean?,
	BranchMaterial: Enum.Material?,
	BranchColor: Color3?,
	LeafMaterial: Enum.Material?,
	LeafColor: Color3?,
	ModelName: string?,
}

type ResolvedProceduralTreeConfig = {
	Algorithm: BranchAlgorithm,
	Seed: number,
	MaxDepth: number,
	BranchAngleRange: NumberRange,
	LengthScale: number,
	ThicknessScale: number,
	BranchChance: number,
	InitialLength: number,
	InitialThickness: number,
	TrunkWobbleAngle: number,
	UpwardBias: number,
	MinBranchLength: number,
	MinBranchThickness: number,
	MinBranchesPerNode: number,
	MaxBranchesPerNode: number,
	LengthJitter: NumberRange,
	ThicknessJitter: NumberRange,
	LeafSizeMin: Vector3,
	LeafSizeMax: Vector3,
	LeafRotationVariance: number,
	LeavesPerTerminalMin: number,
	LeavesPerTerminalMax: number,
	MaxBranchParts: number,
	MaxLeafParts: number,
	UseWelds: boolean,
	BranchCanCollide: boolean,
	BranchMaterial: Enum.Material,
	BranchColor: Color3,
	LeafMaterial: Enum.Material,
	LeafColor: Color3,
	ModelName: string,
}

type BranchDescriptor = {
	index: number,
	parentIndex: number,
	startPosition: Vector3,
	endPosition: Vector3,
	thickness: number,
	depth: number,
}

type LeafDescriptor = {
	index: number,
	parentBranchIndex: number,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
}

type GrowthNode = {
	parentIndex: number,
	startPosition: Vector3,
	direction: Vector3,
	length: number,
	thickness: number,
	depth: number,
}

export type ProceduralTree = typeof(setmetatable(
	{} :: {
		config: ResolvedProceduralTreeConfig,
		seed: number,
		model: Model?,
		lastParent: Instance?,
		lastBaseCFrame: CFrame,
	},
	ProceduralTree
))

local function resolveLeafMaterialFallback(): Enum.Material
	local success, material = pcall(function()
		return Enum.Material.LeafyGrass
	end)
	if success and typeof(material) == "EnumItem" then
		return material :: Enum.Material
	end
	return Enum.Material.Grass
end

local function applyStudSurfaces(part: BasePart)
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
end

local DEFAULT_LEAF_MATERIAL = resolveLeafMaterialFallback()
local DEFAULT_TREE_PALETTE = WorldGenerationColor.TREE_PALETTES.Default
	or {
		BranchColor = Color3.fromRGB(102, 72, 49),
		LeafColor = Color3.fromRGB(91, 153, 66),
	}
local WIND_FOLIAGE_TAG = TagBinder.Tags.Foliage
local WIND_FOLIAGE_PIVOT_ATTACHMENT_NAME = "WindFoliagePivot"
local TREE_GRAPH_ATTRIBUTE = "WindFoliageTreeGraph"
local TREE_NODE_TYPE_ATTRIBUTE = "WindTreeNodeType"
local TREE_NODE_INDEX_ATTRIBUTE = "WindTreeNodeIndex"
local TREE_PARENT_INDEX_ATTRIBUTE = "WindTreeParentIndex"
local TREE_DEPTH_ATTRIBUTE = "WindTreeDepth"

local DEFAULT_CONFIG: ResolvedProceduralTreeConfig = {
	Algorithm = "Recursive",
	Seed = 13371337,
	MaxDepth = 5,
	BranchAngleRange = NumberRange.new(18, 46),
	LengthScale = 0.72,
	ThicknessScale = 0.72,
	BranchChance = 0.6,
	InitialLength = 26,
	InitialThickness = 4.2,
	TrunkWobbleAngle = 8,
	UpwardBias = 0.48,
	MinBranchLength = 3.5,
	MinBranchThickness = 0.35,
	MinBranchesPerNode = 1,
	MaxBranchesPerNode = 3,
	LengthJitter = NumberRange.new(0.88, 1.18),
	ThicknessJitter = NumberRange.new(0.9, 1.08),
	LeafSizeMin = Vector3.new(6, 4, 6),
	LeafSizeMax = Vector3.new(10, 8, 10),
	LeafRotationVariance = 32,
	LeavesPerTerminalMin = 1,
	LeavesPerTerminalMax = 2,
	MaxBranchParts = 180,
	MaxLeafParts = 220,
	UseWelds = true,
	BranchCanCollide = false,
	BranchMaterial = Enum.Material.Wood,
	BranchColor = DEFAULT_TREE_PALETTE.BranchColor,
	LeafMaterial = DEFAULT_LEAF_MATERIAL,
	LeafColor = DEFAULT_TREE_PALETTE.LeafColor,
	ModelName = "ProceduralTree",
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not isFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw :: number, minimum, maximum)
end

local function clampInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	return math.floor(clampNumber(valueRaw, minimum, maximum, fallback))
end

local function sanitizeNumberRange(valueRaw: any, fallback: NumberRange, minimum: number, maximum: number): NumberRange
	local minValue = fallback.Min
	local maxValue = fallback.Max

	if typeof(valueRaw) == "NumberRange" then
		minValue = valueRaw.Min
		maxValue = valueRaw.Max
	elseif typeof(valueRaw) == "Vector2" then
		minValue = valueRaw.X
		maxValue = valueRaw.Y
	elseif typeof(valueRaw) == "table" then
		local source = valueRaw :: { [string]: any }
		local minRaw = source.min
		if not isFiniteNumber(minRaw) then
			minRaw = source.Min
		end
		local maxRaw = source.max
		if not isFiniteNumber(maxRaw) then
			maxRaw = source.Max
		end
		minValue = clampNumber(minRaw, minimum, maximum, minValue)
		maxValue = clampNumber(maxRaw, minimum, maximum, maxValue)
	end

	minValue = math.clamp(minValue, minimum, maximum)
	maxValue = math.clamp(maxValue, minimum, maximum)
	if maxValue < minValue then
		maxValue = minValue
	end
	return NumberRange.new(minValue, maxValue)
end

local function sanitizeVector3(valueRaw: any, fallback: Vector3): Vector3
	if typeof(valueRaw) == "Vector3" then
		return valueRaw
	end
	if typeof(valueRaw) ~= "table" then
		return fallback
	end

	local source = valueRaw :: { [string]: any }
	local xRaw = source.x
	if not isFiniteNumber(xRaw) then
		xRaw = source.X
	end
	local yRaw = source.y
	if not isFiniteNumber(yRaw) then
		yRaw = source.Y
	end
	local zRaw = source.z
	if not isFiniteNumber(zRaw) then
		zRaw = source.Z
	end

	if not isFiniteNumber(xRaw) or not isFiniteNumber(yRaw) or not isFiniteNumber(zRaw) then
		return fallback
	end

	return Vector3.new(xRaw, yRaw, zRaw)
end

local function sanitizeAlgorithm(valueRaw: any, fallback: BranchAlgorithm): BranchAlgorithm
	if valueRaw == "Recursive" then
		return "Recursive"
	end
	if valueRaw == "LSystemStyle" then
		return "LSystemStyle"
	end
	return fallback
end

local function sanitizeMaterial(valueRaw: any, fallback: Enum.Material): Enum.Material
	if typeof(valueRaw) == "EnumItem" and valueRaw.EnumType == Enum.Material then
		return valueRaw :: Enum.Material
	end
	return fallback
end

local function sanitizeColor(valueRaw: any, fallback: Color3): Color3
	if typeof(valueRaw) == "Color3" then
		return valueRaw
	end
	return fallback
end

local function sanitizeString(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end
	local trimmed = string.match(valueRaw, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return fallback
	end
	return trimmed
end

local function resolveConfig(configRaw: ProceduralTreeConfig?): ResolvedProceduralTreeConfig
	local source = if typeof(configRaw) == "table" then configRaw :: { [string]: any } else {}

	local minBranches = clampInteger(source.MinBranchesPerNode, 0, 6, DEFAULT_CONFIG.MinBranchesPerNode)
	local maxBranches = clampInteger(source.MaxBranchesPerNode, minBranches, 8, DEFAULT_CONFIG.MaxBranchesPerNode)

	local leavesMin = clampInteger(source.LeavesPerTerminalMin, 1, 8, DEFAULT_CONFIG.LeavesPerTerminalMin)
	local leavesMax = clampInteger(source.LeavesPerTerminalMax, leavesMin, 8, DEFAULT_CONFIG.LeavesPerTerminalMax)

	local leafSizeMin = sanitizeVector3(source.LeafSizeMin, DEFAULT_CONFIG.LeafSizeMin)
	local leafSizeMax = sanitizeVector3(source.LeafSizeMax, DEFAULT_CONFIG.LeafSizeMax)
	local resolvedLeafSizeMin = Vector3.new(
		math.max(0.5, math.min(leafSizeMin.X, leafSizeMax.X)),
		math.max(0.5, math.min(leafSizeMin.Y, leafSizeMax.Y)),
		math.max(0.5, math.min(leafSizeMin.Z, leafSizeMax.Z))
	)
	local resolvedLeafSizeMax = Vector3.new(
		math.max(resolvedLeafSizeMin.X, leafSizeMin.X, leafSizeMax.X),
		math.max(resolvedLeafSizeMin.Y, leafSizeMin.Y, leafSizeMax.Y),
		math.max(resolvedLeafSizeMin.Z, leafSizeMin.Z, leafSizeMax.Z)
	)

	local resolved = {
		Algorithm = sanitizeAlgorithm(source.Algorithm, DEFAULT_CONFIG.Algorithm),
		Seed = clampInteger(source.Seed, -2147483648, 2147483647, DEFAULT_CONFIG.Seed),
		MaxDepth = clampInteger(source.MaxDepth, 1, 12, DEFAULT_CONFIG.MaxDepth),
		BranchAngleRange = sanitizeNumberRange(source.BranchAngleRange, DEFAULT_CONFIG.BranchAngleRange, 0, 89),
		LengthScale = clampNumber(source.LengthScale, 0.25, 0.95, DEFAULT_CONFIG.LengthScale),
		ThicknessScale = clampNumber(source.ThicknessScale, 0.2, 0.95, DEFAULT_CONFIG.ThicknessScale),
		BranchChance = clampNumber(source.BranchChance, 0, 1, DEFAULT_CONFIG.BranchChance),
		InitialLength = clampNumber(source.InitialLength, 2, 256, DEFAULT_CONFIG.InitialLength),
		InitialThickness = clampNumber(source.InitialThickness, 0.25, 64, DEFAULT_CONFIG.InitialThickness),
		TrunkWobbleAngle = clampNumber(source.TrunkWobbleAngle, 0, 30, DEFAULT_CONFIG.TrunkWobbleAngle),
		UpwardBias = clampNumber(source.UpwardBias, 0, 2, DEFAULT_CONFIG.UpwardBias),
		MinBranchLength = clampNumber(source.MinBranchLength, 0.25, 64, DEFAULT_CONFIG.MinBranchLength),
		MinBranchThickness = clampNumber(source.MinBranchThickness, 0.1, 32, DEFAULT_CONFIG.MinBranchThickness),
		MinBranchesPerNode = minBranches,
		MaxBranchesPerNode = maxBranches,
		LengthJitter = sanitizeNumberRange(source.LengthJitter, DEFAULT_CONFIG.LengthJitter, 0.5, 2),
		ThicknessJitter = sanitizeNumberRange(source.ThicknessJitter, DEFAULT_CONFIG.ThicknessJitter, 0.5, 2),
		LeafSizeMin = resolvedLeafSizeMin,
		LeafSizeMax = resolvedLeafSizeMax,
		LeafRotationVariance = clampNumber(source.LeafRotationVariance, 0, 90, DEFAULT_CONFIG.LeafRotationVariance),
		LeavesPerTerminalMin = leavesMin,
		LeavesPerTerminalMax = leavesMax,
		MaxBranchParts = clampInteger(source.MaxBranchParts, 8, 1200, DEFAULT_CONFIG.MaxBranchParts),
		MaxLeafParts = clampInteger(source.MaxLeafParts, 1, 4000, DEFAULT_CONFIG.MaxLeafParts),
		UseWelds = if source.UseWelds == nil then DEFAULT_CONFIG.UseWelds else source.UseWelds == true,
		BranchCanCollide = if source.BranchCanCollide == nil
			then DEFAULT_CONFIG.BranchCanCollide
			else source.BranchCanCollide == true,
		BranchMaterial = sanitizeMaterial(source.BranchMaterial, DEFAULT_CONFIG.BranchMaterial),
		BranchColor = sanitizeColor(source.BranchColor, DEFAULT_CONFIG.BranchColor),
		LeafMaterial = sanitizeMaterial(source.LeafMaterial, DEFAULT_CONFIG.LeafMaterial),
		LeafColor = sanitizeColor(source.LeafColor, DEFAULT_CONFIG.LeafColor),
		ModelName = sanitizeString(source.ModelName, DEFAULT_CONFIG.ModelName),
	}

	resolved.MinBranchLength = math.min(resolved.MinBranchLength, resolved.InitialLength)
	resolved.MinBranchThickness = math.min(resolved.MinBranchThickness, resolved.InitialThickness)
	resolved.MaxLeafParts = math.max(resolved.MaxLeafParts, resolved.LeavesPerTerminalMin)

	return resolved
end

local function randomInRange(randomObject: Random, range: NumberRange): number
	if range.Max <= range.Min then
		return range.Min
	end
	return randomObject:NextNumber(range.Min, range.Max)
end

local function randomBetween(randomObject: Random, minimum: number, maximum: number): number
	if maximum <= minimum then
		return minimum
	end
	return randomObject:NextNumber(minimum, maximum)
end

local function computePerpendicularBasis(direction: Vector3): (Vector3, Vector3)
	local unitDirection = if direction.Magnitude > 0.0001 then direction.Unit else Vector3.yAxis
	local tangent = unitDirection:Cross(Vector3.yAxis)
	if tangent.Magnitude <= 0.0001 then
		tangent = unitDirection:Cross(Vector3.xAxis)
	end
	if tangent.Magnitude <= 0.0001 then
		tangent = Vector3.zAxis
	end
	tangent = tangent.Unit
	local bitangent = tangent:Cross(unitDirection).Unit
	return tangent, bitangent
end

local function rotateDirectionByAngles(
	baseDirection: Vector3,
	tiltRadians: number,
	azimuthRadians: number,
	upwardBias: number
): Vector3
	local unitDirection = if baseDirection.Magnitude > 0.0001 then baseDirection.Unit else Vector3.yAxis
	local tangent, bitangent = computePerpendicularBasis(unitDirection)

	local sinTilt = math.sin(tiltRadians)
	local candidate = unitDirection * math.cos(tiltRadians)
		+ tangent * (math.cos(azimuthRadians) * sinTilt)
		+ bitangent * (math.sin(azimuthRadians) * sinTilt)

	if upwardBias > 0 then
		candidate += Vector3.yAxis * upwardBias
	end

	if candidate.Magnitude <= 0.0001 then
		return Vector3.yAxis
	end
	return candidate.Unit
end

local function randomVector3Between(randomObject: Random, minimum: Vector3, maximum: Vector3): Vector3
	return Vector3.new(
		randomBetween(randomObject, minimum.X, maximum.X),
		randomBetween(randomObject, minimum.Y, maximum.Y),
		randomBetween(randomObject, minimum.Z, maximum.Z)
	)
end

local function createWeld(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "TreeWeld"
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
end

local function ensureWindFoliagePivotAttachment(rootPart: BasePart): Attachment
	local localBaseOffset = Vector3.new(0, 0, rootPart.Size.Z * 0.5)
	local existing = rootPart:FindFirstChild(WIND_FOLIAGE_PIVOT_ATTACHMENT_NAME)
	if existing ~= nil then
		if existing:IsA("Attachment") then
			existing.Position = localBaseOffset
			return existing
		end
		existing:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = WIND_FOLIAGE_PIVOT_ATTACHMENT_NAME
	attachment.Position = localBaseOffset
	attachment.Parent = rootPart
	return attachment
end

local function resolveWindFoliagePreset(
	config: ResolvedProceduralTreeConfig
): (string, number, number, number, number, number)
	local isHeavyTree = config.InitialLength >= 22 or config.InitialThickness >= 3.6 or config.MaxDepth >= 6
	if isHeavyTree then
		return "BranchHeavy", 5.5, 0.34, 0.58, 0.72, 0.28
	end
	return "BranchSmall", 7.25, 0.46, 0.72, 0.86, 0.42
end

local function applyWindFoliageMetadata(treeModel: Model, rootPart: BasePart, config: ResolvedProceduralTreeConfig)
	local presetName, maxBendAngle, swayAmplitude, heightMultiplier, gustSensitivity, disturbanceSensitivity =
		resolveWindFoliagePreset(config)

	ensureWindFoliagePivotAttachment(rootPart)

	treeModel:SetAttribute("WindFoliageEnabled", true)
	treeModel:SetAttribute(TREE_GRAPH_ATTRIBUTE, true)
	treeModel:SetAttribute("WindFoliagePreset", presetName)
	treeModel:SetAttribute("WindFoliageRepresentation", "Model")
	treeModel:SetAttribute("WindFoliageMotionStyle", "Branch")
	treeModel:SetAttribute("WindFoliagePivotAttachment", WIND_FOLIAGE_PIVOT_ATTACHMENT_NAME)
	treeModel:SetAttribute("WindFoliagePivotMode", "Attachment")
	treeModel:SetAttribute("WindFoliageMaxBendAngle", maxBendAngle)
	treeModel:SetAttribute("WindFoliageSwayAmplitude", swayAmplitude)
	treeModel:SetAttribute("WindFoliageHeightMultiplier", heightMultiplier)
	treeModel:SetAttribute("WindFoliageGustSensitivity", gustSensitivity)
	treeModel:SetAttribute("WindFoliageDisturbanceSensitivity", disturbanceSensitivity)
	treeModel:SetAttribute("WindFoliageTranslationWeight", 0)
end

function ProceduralTree.New(configRaw: ProceduralTreeConfig?): ProceduralTree
	local config = resolveConfig(configRaw)

	local self = setmetatable({
		config = config,
		seed = config.Seed,
		model = nil :: Model?,
		lastParent = nil :: Instance?,
		lastBaseCFrame = CFrame.identity,
	}, ProceduralTree)

	return self
end

function ProceduralTree.SetSeed(self: ProceduralTree, seedRaw: any)
	self.seed = clampInteger(seedRaw, -2147483648, 2147483647, self.seed)
	self.config.Seed = self.seed
end

function ProceduralTree.GetSeed(self: ProceduralTree): number
	return self.seed
end

function ProceduralTree.Destroy(self: ProceduralTree)
	if self.model ~= nil then
		self.model:Destroy()
		self.model = nil
	end
end

function ProceduralTree.AddLeafCluster(
	self: ProceduralTree,
	leaves: { LeafDescriptor },
	randomObject: Random,
	parentBranchIndex: number,
	position: Vector3,
	direction: Vector3
)
	if #leaves >= self.config.MaxLeafParts then
		return
	end

	local clusterCount = randomObject:NextInteger(self.config.LeavesPerTerminalMin, self.config.LeavesPerTerminalMax)
	local tangent, bitangent = computePerpendicularBasis(direction)

	for _ = 1, clusterCount do
		if #leaves >= self.config.MaxLeafParts then
			break
		end

		local size = randomVector3Between(randomObject, self.config.LeafSizeMin, self.config.LeafSizeMax)
		local radius = math.max(size.X, size.Z) * 0.16
		local jitterX = randomBetween(randomObject, -radius, radius)
		local jitterZ = randomBetween(randomObject, -radius, radius)
		local jitterY = randomBetween(randomObject, 0, size.Y * 0.24)
		local rotationVariance = self.config.LeafRotationVariance
		local rotation = Vector3.new(
			randomBetween(randomObject, -rotationVariance, rotationVariance),
			randomBetween(randomObject, 0, 360),
			randomBetween(randomObject, -rotationVariance, rotationVariance)
		)

		leaves[#leaves + 1] = {
			index = #leaves + 1,
			parentBranchIndex = parentBranchIndex,
			position = position + tangent * jitterX + bitangent * jitterZ + Vector3.yAxis * jitterY,
			size = size,
			rotation = rotation,
		}
	end
end

function ProceduralTree.BuildRecursiveDescriptors(
	self: ProceduralTree,
	randomObject: Random
): ({ BranchDescriptor }, { LeafDescriptor })
	local branches: { BranchDescriptor } = {}
	local leaves: { LeafDescriptor } = {}

	local function grow(
		startPosition: Vector3,
		direction: Vector3,
		length: number,
		thickness: number,
		depth: number,
		parentIndex: number
	)
		if #branches >= self.config.MaxBranchParts then
			self:addLeafCluster(leaves, randomObject, parentIndex, startPosition, direction)
			return
		end

		local unitDirection = if direction.Magnitude > 0.0001 then direction.Unit else Vector3.yAxis
		local clampedLength = math.max(self.config.MinBranchLength, length)
		local clampedThickness = math.max(self.config.MinBranchThickness, thickness)
		local endPosition = startPosition + unitDirection * clampedLength
		local branchIndex = #branches + 1

		branches[#branches + 1] = {
			index = branchIndex,
			parentIndex = parentIndex,
			startPosition = startPosition,
			endPosition = endPosition,
			thickness = clampedThickness,
			depth = depth,
		}

		local nextDepth = depth + 1
		local nextLengthBase = clampedLength * self.config.LengthScale
		local nextThicknessBase = clampedThickness * self.config.ThicknessScale

		if
			nextDepth > self.config.MaxDepth
			or nextLengthBase < self.config.MinBranchLength
			or nextThicknessBase < self.config.MinBranchThickness
		then
			self:addLeafCluster(leaves, randomObject, branchIndex, endPosition, unitDirection)
			return
		end

		local wobbleTilt = math.rad(randomBetween(randomObject, 0, self.config.TrunkWobbleAngle))
		local wobbleAzimuth = randomBetween(randomObject, 0, math.pi * 2)
		local continuationDirection =
			rotateDirectionByAngles(unitDirection, wobbleTilt, wobbleAzimuth, self.config.UpwardBias)
		local continuationLength = nextLengthBase * randomInRange(randomObject, self.config.LengthJitter)
		local continuationThickness = nextThicknessBase * randomInRange(randomObject, self.config.ThicknessJitter)
		grow(endPosition, continuationDirection, continuationLength, continuationThickness, nextDepth, branchIndex)

		local depthAlpha = if self.config.MaxDepth > 0 then depth / self.config.MaxDepth else 1
		local depthChanceScale = math.clamp(1 - depthAlpha * 0.45, 0.35, 1)
		local effectiveBranchChance = math.clamp(self.config.BranchChance * depthChanceScale, 0, 1)
		local branchAttempts = randomObject:NextInteger(self.config.MinBranchesPerNode, self.config.MaxBranchesPerNode)

		for _ = 1, branchAttempts do
			if #branches >= self.config.MaxBranchParts then
				break
			end
			if randomObject:NextNumber() > effectiveBranchChance then
				continue
			end

			local branchAngle = math.rad(randomInRange(randomObject, self.config.BranchAngleRange))
			local azimuth = randomBetween(randomObject, 0, math.pi * 2)
			local branchDirection =
				rotateDirectionByAngles(unitDirection, branchAngle, azimuth, self.config.UpwardBias * 0.55)
			local branchLength = nextLengthBase * randomInRange(randomObject, self.config.LengthJitter)
			local branchThickness = nextThicknessBase * randomInRange(randomObject, self.config.ThicknessJitter)
			grow(endPosition, branchDirection, branchLength, branchThickness, nextDepth, branchIndex)
		end
	end

	grow(Vector3.zero, Vector3.yAxis, self.config.InitialLength, self.config.InitialThickness, 0, 0)
	return branches, leaves
end

function ProceduralTree.BuildLSystemStyleDescriptors(
	self: ProceduralTree,
	randomObject: Random
): ({ BranchDescriptor }, { LeafDescriptor })
	local branches: { BranchDescriptor } = {}
	local leaves: { LeafDescriptor } = {}

	local queue: { GrowthNode } = {
		{
			parentIndex = 0,
			startPosition = Vector3.zero,
			direction = Vector3.yAxis,
			length = self.config.InitialLength,
			thickness = self.config.InitialThickness,
			depth = 0,
		},
	}
	local cursor = 1

	while cursor <= #queue do
		local node = queue[cursor]
		cursor += 1

		if #branches >= self.config.MaxBranchParts then
			self:addLeafCluster(leaves, randomObject, node.parentIndex, node.startPosition, node.direction)
			break
		end

		local unitDirection = if node.direction.Magnitude > 0.0001 then node.direction.Unit else Vector3.yAxis
		local clampedLength = math.max(self.config.MinBranchLength, node.length)
		local clampedThickness = math.max(self.config.MinBranchThickness, node.thickness)
		local endPosition = node.startPosition + unitDirection * clampedLength
		local branchIndex = #branches + 1

		branches[#branches + 1] = {
			index = branchIndex,
			parentIndex = node.parentIndex,
			startPosition = node.startPosition,
			endPosition = endPosition,
			thickness = clampedThickness,
			depth = node.depth,
		}

		local nextDepth = node.depth + 1
		local nextLengthBase = clampedLength * self.config.LengthScale
		local nextThicknessBase = clampedThickness * self.config.ThicknessScale

		if
			nextDepth > self.config.MaxDepth
			or nextLengthBase < self.config.MinBranchLength
			or nextThicknessBase < self.config.MinBranchThickness
		then
			self:addLeafCluster(leaves, randomObject, branchIndex, endPosition, unitDirection)
			continue
		end

		local wobbleTilt = math.rad(randomBetween(randomObject, 0, self.config.TrunkWobbleAngle))
		local wobbleAzimuth = randomBetween(randomObject, 0, math.pi * 2)
		local continuationDirection =
			rotateDirectionByAngles(unitDirection, wobbleTilt, wobbleAzimuth, self.config.UpwardBias)

		queue[#queue + 1] = {
			parentIndex = branchIndex,
			startPosition = endPosition,
			direction = continuationDirection,
			length = nextLengthBase * randomInRange(randomObject, self.config.LengthJitter),
			thickness = nextThicknessBase * randomInRange(randomObject, self.config.ThicknessJitter),
			depth = nextDepth,
		}

		local depthAlpha = if self.config.MaxDepth > 0 then node.depth / self.config.MaxDepth else 1
		local depthChanceScale = math.clamp(1 - depthAlpha * 0.45, 0.35, 1)
		local effectiveBranchChance = math.clamp(self.config.BranchChance * depthChanceScale, 0, 1)
		local branchAttempts = randomObject:NextInteger(self.config.MinBranchesPerNode, self.config.MaxBranchesPerNode)

		for _ = 1, branchAttempts do
			if #queue >= self.config.MaxBranchParts * 2 then
				break
			end
			if randomObject:NextNumber() > effectiveBranchChance then
				continue
			end

			local branchAngle = math.rad(randomInRange(randomObject, self.config.BranchAngleRange))
			local azimuth = randomBetween(randomObject, 0, math.pi * 2)
			local sideDirection =
				rotateDirectionByAngles(unitDirection, branchAngle, azimuth, self.config.UpwardBias * 0.55)
			queue[#queue + 1] = {
				parentIndex = branchIndex,
				startPosition = endPosition,
				direction = sideDirection,
				length = nextLengthBase * randomInRange(randomObject, self.config.LengthJitter),
				thickness = nextThicknessBase * randomInRange(randomObject, self.config.ThicknessJitter),
				depth = nextDepth,
			}
		end
	end

	return branches, leaves
end

function ProceduralTree.BuildDescriptors(
	self: ProceduralTree,
	randomObject: Random
): ({ BranchDescriptor }, { LeafDescriptor })
	if self.config.Algorithm == "LSystemStyle" then
		return self:buildLSystemStyleDescriptors(randomObject)
	end
	return self:buildRecursiveDescriptors(randomObject)
end

function ProceduralTree.CreateBranchPart(self: ProceduralTree, descriptor: BranchDescriptor, baseCFrame: CFrame): Part
	local worldStart = baseCFrame:PointToWorldSpace(descriptor.startPosition)
	local worldEnd = baseCFrame:PointToWorldSpace(descriptor.endPosition)
	local direction = worldEnd - worldStart
	local length = direction.Magnitude
	if length <= 0.0001 then
		direction = Vector3.yAxis
		length = 0.0001
	end

	local midpoint = worldStart + direction * 0.5
	local part = Instance.new("Part")
	part.Name = if descriptor.parentIndex == 0
		then "Trunk"
		else ("Branch_%d_%d"):format(descriptor.depth, descriptor.index)
	part.Size = Vector3.new(descriptor.thickness, descriptor.thickness, length)
	part.CFrame = CFrame.lookAt(midpoint, midpoint + direction.Unit)
	part.Color = self.config.BranchColor
	part.Material = Enum.Material.Plastic
	applyStudSurfaces(part)
	part.CastShadow = false
	part.CanCollide = self.config.BranchCanCollide
	part.CanTouch = self.config.BranchCanCollide
	part.CanQuery = self.config.BranchCanCollide
	part:SetAttribute(TREE_NODE_TYPE_ATTRIBUTE, if descriptor.parentIndex == 0 then "Trunk" else "Branch")
	part:SetAttribute(TREE_NODE_INDEX_ATTRIBUTE, descriptor.index)
	part:SetAttribute(TREE_PARENT_INDEX_ATTRIBUTE, descriptor.parentIndex)
	part:SetAttribute(TREE_DEPTH_ATTRIBUTE, descriptor.depth)
	return part
end

function ProceduralTree.CreateLeafPart(self: ProceduralTree, descriptor: LeafDescriptor, baseCFrame: CFrame): Part
	local worldPosition = baseCFrame:PointToWorldSpace(descriptor.position)
	local baseRotation = baseCFrame - baseCFrame.Position
	local part = Instance.new("Part")
	part.Name = "Leaf"
	part.Size = descriptor.size
	part.CFrame = CFrame.new(worldPosition)
		* baseRotation
		* CFrame.Angles(
			math.rad(descriptor.rotation.X),
			math.rad(descriptor.rotation.Y),
			math.rad(descriptor.rotation.Z)
		)
	part.Color = self.config.LeafColor
	part.Material = Enum.Material.Plastic
	applyStudSurfaces(part)
	part.CastShadow = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part:SetAttribute(TREE_NODE_TYPE_ATTRIBUTE, "Leaf")
	part:SetAttribute(TREE_NODE_INDEX_ATTRIBUTE, descriptor.index)
	part:SetAttribute(TREE_PARENT_INDEX_ATTRIBUTE, descriptor.parentBranchIndex)
	part:SetAttribute(TREE_DEPTH_ATTRIBUTE, 0)
	return part
end

function ProceduralTree.Generate(self: ProceduralTree, parentRaw: Instance?, baseCFrameRaw: CFrame?): Model
	local parent = if typeof(parentRaw) == "Instance" then parentRaw else self.lastParent or Workspace
	local baseCFrame = if typeof(baseCFrameRaw) == "CFrame" then baseCFrameRaw else self.lastBaseCFrame

	self.lastParent = parent
	self.lastBaseCFrame = baseCFrame

	if self.model ~= nil then
		self.model:Destroy()
		self.model = nil
	end

	local randomObject = Random.new(self.seed)
	local branchDescriptors, leafDescriptors = self:buildDescriptors(randomObject)

	local treeModel = Instance.new("Model")
	treeModel.Name = self.config.ModelName
	treeModel:SetAttribute("Seed", self.seed)
	treeModel:SetAttribute("Algorithm", self.config.Algorithm)
	treeModel:SetAttribute("BranchCount", #branchDescriptors)
	treeModel:SetAttribute("LeafCount", #leafDescriptors)

	local branchModel = Instance.new("Model")
	branchModel.Name = "Branches"
	branchModel.Parent = treeModel

	local leavesModel = Instance.new("Model")
	leavesModel.Name = "Leaves"
	leavesModel.Parent = treeModel

	local branchParts = Sift.Array.create(#branchDescriptors)
	local rootPart: BasePart? = nil
	for index, descriptor in branchDescriptors do
		local branchPart = self:createBranchPart(descriptor, baseCFrame)
		if rootPart == nil then
			rootPart = branchPart
		end
		branchPart.Anchored = true
		branchPart.Massless = false
		branchPart.Parent = branchModel
		branchParts[index] = branchPart
	end

	if rootPart == nil then
		local anchor = Instance.new("Part")
		anchor.Name = "Anchor"
		anchor.Size = Vector3.new(0.25, 0.25, 0.25)
		anchor.CFrame = baseCFrame
		anchor.Transparency = 1
		anchor.Material = Enum.Material.SmoothPlastic
		anchor.CastShadow = false
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Parent = branchModel
		rootPart = anchor
	end

	local leafParts = Sift.Array.create(#leafDescriptors)
	for index, descriptor in leafDescriptors do
		local leafPart = self:createLeafPart(descriptor, baseCFrame)
		leafPart.Anchored = true
		leafPart.Massless = false
		leafPart.Parent = leavesModel
		leafParts[index] = leafPart
	end

	treeModel.PrimaryPart = rootPart
	applyWindFoliageMetadata(treeModel, rootPart, self.config)
	treeModel.Parent = parent
	TagBinder.applyTag(treeModel, WIND_FOLIAGE_TAG)
	self.model = treeModel
	return treeModel
end

function ProceduralTree.Regenerate(
	self: ProceduralTree,
	seedRaw: any?,
	parentRaw: Instance?,
	baseCFrameRaw: CFrame?
): Model
	if seedRaw ~= nil then
		self:setSeed(seedRaw)
	end
	return self:generate(parentRaw, baseCFrameRaw)
end

ProceduralTree.new = ProceduralTree.New
ProceduralTree.setSeed = ProceduralTree.SetSeed
ProceduralTree.getSeed = ProceduralTree.GetSeed
ProceduralTree.destroy = ProceduralTree.Destroy
ProceduralTree.addLeafCluster = ProceduralTree.AddLeafCluster
ProceduralTree.buildRecursiveDescriptors = ProceduralTree.BuildRecursiveDescriptors
ProceduralTree.buildLSystemStyleDescriptors = ProceduralTree.BuildLSystemStyleDescriptors
ProceduralTree.buildDescriptors = ProceduralTree.BuildDescriptors
ProceduralTree.createBranchPart = ProceduralTree.CreateBranchPart
ProceduralTree.createLeafPart = ProceduralTree.CreateLeafPart
ProceduralTree.generate = ProceduralTree.Generate
ProceduralTree.regenerate = ProceduralTree.Regenerate

return ProceduralTree
