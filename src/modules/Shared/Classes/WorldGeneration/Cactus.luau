--!strict

local Workspace = game:GetService("Workspace")

local function ApplyStudSurfaces(part: BasePart)
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
end

export type CactusArchetype = "Saguaro" | "Barrel" | "PricklyPear"
export type SegmentKind = "Trunk" | "Arm" | "Pad"

export type CactusConfig = {
	Archetype: CactusArchetype?,
	Seed: number?,
	Iterations: number?,
	StepLength: number?,
	BaseThickness: number?,
	AngleDegrees: number?,
	MinBranchHeight: number?,
	MaxBranches: number?,
	Curvature: number?,
	SegmentMaterial: Enum.Material?,
	SegmentColor: Color3?,
	UseWelds: boolean?,
	Parent: Instance?,
	ModelName: string?,
	MaxSegments: number?,
	BranchChance: number?,
	BranchStartIteration: number?,
	LengthJitter: NumberRange?,
	AngleJitter: NumberRange?,
	CurvatureJitter: NumberRange?,
	ThicknessFalloff: number?,
	ArmThicknessScale: number?,
	TrunkWobbleDegrees: number?,
	MinimumThickness: number?,
	SegmentCanCollide: boolean?,
	MinHeight: number?,
	MaxHeight: number?,
	NodeSpacing: number?,
	DetailDensity: number?,
}

type ResolvedCactusConfig = {
	Archetype: CactusArchetype,
	Seed: number,
	Iterations: number,
	StepLength: number,
	BaseThickness: number,
	AngleDegrees: number,
	MinBranchHeight: number,
	MaxBranches: number,
	Curvature: number,
	SegmentMaterial: Enum.Material,
	SegmentColor: Color3,
	UseWelds: boolean,
	Parent: Instance?,
	ModelName: string,
	MaxSegments: number,
	BranchChance: number,
	BranchStartIteration: number,
	LengthJitter: NumberRange,
	AngleJitter: NumberRange,
	CurvatureJitter: NumberRange,
	ThicknessFalloff: number,
	ArmThicknessScale: number,
	TrunkWobbleDegrees: number,
	MinimumThickness: number,
	SegmentCanCollide: boolean,
	MinHeight: number,
	MaxHeight: number,
	NodeSpacing: number,
	DetailDensity: number,
}

type ArchetypeProfile = {
	MinHeight: number,
	MaxHeight: number,
	NodeSpacingScale: number,
	UpwardBias: number,
	BendStrength: number,
	TrunkLeanDegrees: number,
	BranchSpawnMinAlpha: number,
	BranchSpawnMaxAlpha: number,
	BranchSpacingNodes: number,
	ArmOutwardBias: number,
	ArmUpwardBias: number,
	ArmCurvature: number,
	ArmLengthAlphaMin: number,
	ArmLengthAlphaMax: number,
	ArmNodeSpacingScale: number,
	BaseBulge: number,
	TaperPower: number,
	PadMode: boolean,
	AllowsArms: boolean,
	FlowerChance: number,
	RibCount: number,
}

export type GrowthNode = {
	Index: number,
	ParentIndex: number,
	Position: Vector3,
	Direction: Vector3,
	Thickness: number,
	Depth: number,
	Height: number,
	ChainId: number,
	Kind: SegmentKind,
	SideSign: number,
}

export type Segment = {
	Index: number,
	ParentIndex: number,
	Start: Vector3,
	End: Vector3,
	Thickness: number,
	ThicknessStart: number,
	ThicknessEnd: number,
	Depth: number,
	Age: number,
	Kind: SegmentKind,
	ChainId: number,
	SideSign: number,
}

type Skeleton = {
	Nodes: { GrowthNode },
	Segments: { Segment },
	Archetype: CactusArchetype,
	Height: number,
	ArmCount: number,
	TrunkTipNodeIndex: number,
}

export type CactusGenerator = typeof(setmetatable(
	{} :: {
		Config: ResolvedCactusConfig,
		Seed: number,
		Model: Model?,
		LastSegments: { Segment },
		LastSkeleton: Skeleton?,
		LastExpandedGrammar: string,
	},
	{} :: any
))

local CactusGenerator = {}
CactusGenerator.__index = CactusGenerator

local ARCHETYPE_PROFILES: { [CactusArchetype]: ArchetypeProfile } = {
	Saguaro = {
		MinHeight = 22,
		MaxHeight = 48,
		NodeSpacingScale = 0.95,
		UpwardBias = 0.88,
		BendStrength = 0.18,
		TrunkLeanDegrees = 5,
		BranchSpawnMinAlpha = 0.34,
		BranchSpawnMaxAlpha = 0.84,
		BranchSpacingNodes = 3,
		ArmOutwardBias = 0.82,
		ArmUpwardBias = 0.38,
		ArmCurvature = 0.24,
		ArmLengthAlphaMin = 0.2,
		ArmLengthAlphaMax = 0.42,
		ArmNodeSpacingScale = 0.86,
		BaseBulge = 0.06,
		TaperPower = 1.08,
		PadMode = false,
		AllowsArms = true,
		FlowerChance = 0.18,
		RibCount = 4,
	},
	Barrel = {
		MinHeight = 8,
		MaxHeight = 16,
		NodeSpacingScale = 0.55,
		UpwardBias = 0.96,
		BendStrength = 0.06,
		TrunkLeanDegrees = 2,
		BranchSpawnMinAlpha = 1,
		BranchSpawnMaxAlpha = 1,
		BranchSpacingNodes = 99,
		ArmOutwardBias = 0,
		ArmUpwardBias = 1,
		ArmCurvature = 0,
		ArmLengthAlphaMin = 0,
		ArmLengthAlphaMax = 0,
		ArmNodeSpacingScale = 1,
		BaseBulge = 0.34,
		TaperPower = 0.32,
		PadMode = false,
		AllowsArms = false,
		FlowerChance = 0.54,
		RibCount = 7,
	},
	PricklyPear = {
		MinHeight = 8,
		MaxHeight = 18,
		NodeSpacingScale = 0.62,
		UpwardBias = 0.8,
		BendStrength = 0.12,
		TrunkLeanDegrees = 4,
		BranchSpawnMinAlpha = 0.28,
		BranchSpawnMaxAlpha = 0.92,
		BranchSpacingNodes = 2,
		ArmOutwardBias = 0.68,
		ArmUpwardBias = 0.62,
		ArmCurvature = 0.12,
		ArmLengthAlphaMin = 0.12,
		ArmLengthAlphaMax = 0.24,
		ArmNodeSpacingScale = 0.62,
		BaseBulge = 0.12,
		TaperPower = 0.58,
		PadMode = true,
		AllowsArms = true,
		FlowerChance = 0.32,
		RibCount = 2,
	},
}

local DEFAULT_CONFIG: ResolvedCactusConfig = {
	Archetype = "Saguaro",
	Seed = 24680,
	Iterations = 7,
	StepLength = 3.6,
	BaseThickness = 1.8,
	AngleDegrees = 22,
	MinBranchHeight = 6,
	MaxBranches = 4,
	Curvature = 10,
	SegmentMaterial = Enum.Material.SmoothPlastic,
	SegmentColor = Color3.fromRGB(80, 143, 74),
	UseWelds = true,
	Parent = nil,
	ModelName = "ProceduralCactus",
	MaxSegments = 180,
	BranchChance = 0.42,
	BranchStartIteration = 2,
	LengthJitter = NumberRange.new(0.92, 1.08),
	AngleJitter = NumberRange.new(-4, 4),
	CurvatureJitter = NumberRange.new(-2, 2),
	ThicknessFalloff = 0.6,
	ArmThicknessScale = 0.72,
	TrunkWobbleDegrees = 2.5,
	MinimumThickness = 0.42,
	SegmentCanCollide = false,
	MinHeight = 0,
	MaxHeight = 0,
	NodeSpacing = 0,
	DetailDensity = 1,
}

local function IsFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function ClampNumber(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	if not IsFiniteNumber(valueRaw) then
		return fallback
	end
	return math.clamp(valueRaw :: number, minimum, maximum)
end

local function ClampInteger(valueRaw: any, minimum: number, maximum: number, fallback: number): number
	return math.floor(ClampNumber(valueRaw, minimum, maximum, fallback))
end

local function SanitizeNumberRange(valueRaw: any, fallback: NumberRange, minimum: number, maximum: number): NumberRange
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
		minValue = ClampNumber(source.Min or source.min, minimum, maximum, minValue)
		maxValue = ClampNumber(source.Max or source.max, minimum, maximum, maxValue)
	end

	minValue = math.clamp(minValue, minimum, maximum)
	maxValue = math.clamp(maxValue, minimum, maximum)
	if maxValue < minValue then
		maxValue = minValue
	end
	return NumberRange.new(minValue, maxValue)
end

local function SanitizeMaterial(valueRaw: any, fallback: Enum.Material): Enum.Material
	if typeof(valueRaw) == "EnumItem" and valueRaw.EnumType == Enum.Material then
		return valueRaw :: Enum.Material
	end
	return fallback
end

local function SanitizeColor(valueRaw: any, fallback: Color3): Color3
	if typeof(valueRaw) == "Color3" then
		return valueRaw
	end
	return fallback
end

local function SanitizeString(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end
	local trimmed = string.match(valueRaw, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return fallback
	end
	return trimmed
end

local function ResolveArchetype(valueRaw: any, fallback: CactusArchetype): CactusArchetype
	if valueRaw == "Saguaro" or valueRaw == "Barrel" or valueRaw == "PricklyPear" then
		return valueRaw
	end
	return fallback
end

local function RandomInRange(randomObject: Random, range: NumberRange): number
	if range.Max <= range.Min then
		return range.Min
	end
	return randomObject:NextNumber(range.Min, range.Max)
end

local function ResolveVisibleMaterial(material: Enum.Material): Enum.Material
	if material == Enum.Material.SmoothPlastic then
		return Enum.Material.Plastic
	end
	return material
end

local function RotateWithinPlane(directionRaw: Vector3, angleRadians: number): Vector3
	local direction = if directionRaw.Magnitude > 0.0001 then directionRaw.Unit else Vector3.yAxis
	local y = direction.Y
	local z = direction.Z
	local cosine = math.cos(angleRadians)
	local sine = math.sin(angleRadians)
	local rotated = Vector3.new(0, y * cosine - z * sine, y * sine + z * cosine)
	if rotated.Magnitude <= 0.0001 then
		return Vector3.yAxis
	end
	return rotated.Unit
end

local function BlendDirection(currentRaw: Vector3, targetRaw: Vector3, alphaRaw: number): Vector3
	local current = if currentRaw.Magnitude > 0.0001 then currentRaw.Unit else Vector3.yAxis
	local target = if targetRaw.Magnitude > 0.0001 then targetRaw.Unit else Vector3.yAxis
	local alpha = math.clamp(alphaRaw, 0, 1)
	local blended = current:Lerp(target, alpha)
	if blended.Magnitude <= 0.0001 then
		return target
	end
	return blended.Unit
end

local function MakeCFrameFromSegment(startPosition: Vector3, endPosition: Vector3): (CFrame, number)
	local direction = endPosition - startPosition
	local length = direction.Magnitude
	if length <= 1e-4 then
		direction = Vector3.yAxis
		length = 1e-4
	end

	local axisX = direction.Unit
	local axisY = if math.abs(axisX:Dot(Vector3.yAxis)) > 0.985 then Vector3.zAxis else Vector3.yAxis
	local axisZ = axisX:Cross(axisY).Unit
	axisY = axisZ:Cross(axisX).Unit
	local midpoint = startPosition + direction * 0.5
	return CFrame.fromMatrix(midpoint, axisX, axisY, axisZ), length
end

local function CreateWeld(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CactusWeld"
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
end

local function ResolveConfig(configRaw: CactusConfig?): ResolvedCactusConfig
	local source = if typeof(configRaw) == "table" then configRaw :: { [string]: any } else {}
	local archetype = ResolveArchetype(source.Archetype, DEFAULT_CONFIG.Archetype)
	local profile = ARCHETYPE_PROFILES[archetype]
	local resolvedMinHeight = ClampNumber(source.MinHeight, 0, 160, profile.MinHeight)
	local resolvedMaxHeight = ClampNumber(source.MaxHeight, resolvedMinHeight, 220, profile.MaxHeight)

	return {
		Archetype = archetype,
		Seed = ClampInteger(source.Seed, -2147483648, 2147483647, DEFAULT_CONFIG.Seed),
		Iterations = ClampInteger(source.Iterations, 2, 16, DEFAULT_CONFIG.Iterations),
		StepLength = ClampNumber(source.StepLength, 0.4, 18, DEFAULT_CONFIG.StepLength),
		BaseThickness = ClampNumber(source.BaseThickness, 0.3, 12, DEFAULT_CONFIG.BaseThickness),
		AngleDegrees = ClampNumber(source.AngleDegrees, 0, 65, DEFAULT_CONFIG.AngleDegrees),
		MinBranchHeight = ClampNumber(source.MinBranchHeight, 0, 160, DEFAULT_CONFIG.MinBranchHeight),
		MaxBranches = ClampInteger(source.MaxBranches, 0, 8, DEFAULT_CONFIG.MaxBranches),
		Curvature = ClampNumber(source.Curvature, 0, 35, DEFAULT_CONFIG.Curvature),
		SegmentMaterial = SanitizeMaterial(source.SegmentMaterial, DEFAULT_CONFIG.SegmentMaterial),
		SegmentColor = SanitizeColor(source.SegmentColor, DEFAULT_CONFIG.SegmentColor),
		UseWelds = if source.UseWelds == nil then DEFAULT_CONFIG.UseWelds else source.UseWelds == true,
		Parent = if typeof(source.Parent) == "Instance" then source.Parent else DEFAULT_CONFIG.Parent,
		ModelName = SanitizeString(source.ModelName, DEFAULT_CONFIG.ModelName),
		MaxSegments = ClampInteger(source.MaxSegments, 4, 512, DEFAULT_CONFIG.MaxSegments),
		BranchChance = ClampNumber(source.BranchChance, 0, 1, DEFAULT_CONFIG.BranchChance),
		BranchStartIteration = ClampInteger(source.BranchStartIteration, 1, 16, DEFAULT_CONFIG.BranchStartIteration),
		LengthJitter = SanitizeNumberRange(source.LengthJitter, DEFAULT_CONFIG.LengthJitter, 0.5, 1.5),
		AngleJitter = SanitizeNumberRange(source.AngleJitter, DEFAULT_CONFIG.AngleJitter, -25, 25),
		CurvatureJitter = SanitizeNumberRange(source.CurvatureJitter, DEFAULT_CONFIG.CurvatureJitter, -18, 18),
		ThicknessFalloff = ClampNumber(source.ThicknessFalloff, 0, 1, DEFAULT_CONFIG.ThicknessFalloff),
		ArmThicknessScale = ClampNumber(source.ArmThicknessScale, 0.2, 1, DEFAULT_CONFIG.ArmThicknessScale),
		TrunkWobbleDegrees = ClampNumber(source.TrunkWobbleDegrees, 0, 16, DEFAULT_CONFIG.TrunkWobbleDegrees),
		MinimumThickness = ClampNumber(source.MinimumThickness, 0.08, 6, DEFAULT_CONFIG.MinimumThickness),
		SegmentCanCollide = if source.SegmentCanCollide == nil
			then DEFAULT_CONFIG.SegmentCanCollide
			else source.SegmentCanCollide == true,
		MinHeight = resolvedMinHeight,
		MaxHeight = resolvedMaxHeight,
		NodeSpacing = ClampNumber(source.NodeSpacing, 0, 12, DEFAULT_CONFIG.NodeSpacing),
		DetailDensity = ClampNumber(source.DetailDensity, 0.2, 2.5, DEFAULT_CONFIG.DetailDensity),
	}
end

function CactusGenerator.New(configRaw: CactusConfig?): CactusGenerator
	local config = ResolveConfig(configRaw)
	local self = setmetatable({
		Config = config,
		Seed = config.Seed,
		Model = nil :: Model?,
		LastSegments = {} :: { Segment },
		LastSkeleton = nil :: Skeleton?,
		LastExpandedGrammar = "",
	}, CactusGenerator)
	return self
end

function CactusGenerator.Destroy(self: CactusGenerator)
	if self.Model ~= nil then
		self.Model:Destroy()
		self.Model = nil
	end
	self.LastSegments = {}
	self.LastSkeleton = nil
	self.LastExpandedGrammar = ""
end

function CactusGenerator.SetSeed(self: CactusGenerator, seedRaw: any)
	self.Seed = ClampInteger(seedRaw, -2147483648, 2147483647, self.Seed)
	self.Config.Seed = self.Seed
end

function CactusGenerator.GetSeed(self: CactusGenerator): number
	return self.Seed
end

function CactusGenerator.GetArchetypeProfile(self: CactusGenerator): ArchetypeProfile
	return ARCHETYPE_PROFILES[self.Config.Archetype]
end

function CactusGenerator.ComputeTargetHeight(
	self: CactusGenerator,
	profile: ArchetypeProfile,
	randomObject: Random
): number
	local configuredMin = if self.Config.MinHeight > 0 then self.Config.MinHeight else profile.MinHeight
	local configuredMax = if self.Config.MaxHeight > 0 then self.Config.MaxHeight else profile.MaxHeight
	local seededHeight = randomObject:NextNumber(configuredMin, configuredMax)
	local iterationBias = self.Config.StepLength * self.Config.Iterations
	return math.clamp((seededHeight + iterationBias) * 0.5, configuredMin, configuredMax)
end

function CactusGenerator.ComputeNodeSpacing(self: CactusGenerator, profile: ArchetypeProfile): number
	if self.Config.NodeSpacing > 0 then
		return self.Config.NodeSpacing
	end
	return math.max(0.45, self.Config.StepLength * profile.NodeSpacingScale)
end

function CactusGenerator.ComputeThicknessAtProgress(
	self: CactusGenerator,
	profile: ArchetypeProfile,
	progress: number,
	randomObject: Random,
	isArm: boolean
): number
	local clampedProgress = math.clamp(progress, 0, 1)
	local baseThickness = self.Config.BaseThickness
	if isArm then
		baseThickness *= self.Config.ArmThicknessScale
	end

	local bulgeAlpha = math.sin(clampedProgress * math.pi)
	local bulgeScale = 1 + bulgeAlpha * profile.BaseBulge
	local taperAlpha = clampedProgress ^ profile.TaperPower
	local taperScale = 1 - taperAlpha * self.Config.ThicknessFalloff
	local noiseScale = 1 + randomObject:NextNumber(-0.045, 0.045)
	local thickness = baseThickness * bulgeScale * taperScale * noiseScale
	return math.max(self.Config.MinimumThickness, thickness)
end

function CactusGenerator.CreateNode(
	self: CactusGenerator,
	nodes: { GrowthNode },
	parentIndex: number,
	position: Vector3,
	direction: Vector3,
	thickness: number,
	depth: number,
	height: number,
	chainId: number,
	kind: SegmentKind,
	sideSign: number
): GrowthNode
	local node: GrowthNode = {
		Index = #nodes + 1,
		ParentIndex = parentIndex,
		Position = position,
		Direction = direction,
		Thickness = thickness,
		Depth = depth,
		Height = height,
		ChainId = chainId,
		Kind = kind,
		SideSign = sideSign,
	}
	nodes[node.Index] = node
	return node
end

function CactusGenerator.CreateSegment(
	self: CactusGenerator,
	segments: { Segment },
	parentIndex: number,
	startPosition: Vector3,
	endPosition: Vector3,
	thicknessStart: number,
	thicknessEnd: number,
	depth: number,
	age: number,
	kind: SegmentKind,
	chainId: number,
	sideSign: number
): Segment
	local segment: Segment = {
		Index = #segments + 1,
		ParentIndex = parentIndex,
		Start = startPosition,
		End = endPosition,
		Thickness = (thicknessStart + thicknessEnd) * 0.5,
		ThicknessStart = thicknessStart,
		ThicknessEnd = thicknessEnd,
		Depth = depth,
		Age = age,
		Kind = kind,
		ChainId = chainId,
		SideSign = sideSign,
	}
	segments[segment.Index] = segment
	return segment
end

function CactusGenerator.ValidateBranchSpawn(
	self: CactusGenerator,
	profile: ArchetypeProfile,
	currentNode: GrowthNode,
	stepIndex: number,
	stepCount: number,
	armCount: number,
	lastBranchStep: number,
	randomObject: Random
): boolean
	if not profile.AllowsArms then
		return false
	end
	if armCount >= math.min(self.Config.MaxBranches, 8) then
		return false
	end
	if stepIndex < math.max(self.Config.BranchStartIteration, 2) then
		return false
	end
	if stepIndex - lastBranchStep < profile.BranchSpacingNodes then
		return false
	end
	if currentNode.Height < self.Config.MinBranchHeight then
		return false
	end

	local alpha = if stepCount > 0 then stepIndex / stepCount else 1
	if alpha < profile.BranchSpawnMinAlpha or alpha > profile.BranchSpawnMaxAlpha then
		return false
	end

	local uprightAlpha = math.clamp(currentNode.Direction.Y, 0, 1)
	local branchChance = self.Config.BranchChance
	branchChance *= 0.3 + alpha * 0.85
	branchChance *= 0.45 + uprightAlpha * 0.7

	if self.Config.Archetype == "PricklyPear" then
		branchChance *= 1.18
	elseif self.Config.Archetype == "Barrel" then
		branchChance *= 0
	end

	return randomObject:NextNumber() <= math.clamp(branchChance, 0, 0.95)
end

function CactusGenerator.GrowArm(
	self: CactusGenerator,
	skeleton: Skeleton,
	parentNode: GrowthNode,
	attachSegmentIndex: number,
	armOrdinal: number,
	sideSign: number,
	profile: ArchetypeProfile,
	randomObject: Random,
	targetHeight: number
)
	if #skeleton.Segments >= self.Config.MaxSegments then
		return
	end

	local heightAlpha = math.clamp(parentNode.Height / math.max(targetHeight, 0.001), 0, 1)
	local maxRemainingHeight = math.max(targetHeight - parentNode.Height, self.Config.StepLength)
	local desiredArmHeight = maxRemainingHeight
		* randomObject:NextNumber(profile.ArmLengthAlphaMin, profile.ArmLengthAlphaMax)
	local nodeSpacing = math.max(0.35, self.Config.StepLength * profile.ArmNodeSpacingScale)
	local armSteps = math.max(1, math.min(8, math.floor(desiredArmHeight / math.max(nodeSpacing, 0.001) + 0.5)))

	local direction = BlendDirection(
		parentNode.Direction,
		Vector3.new(0, profile.ArmUpwardBias, sideSign * profile.ArmOutwardBias),
		0.62
	)
	local position = parentNode.Position
	local parentSegmentIndex = attachSegmentIndex
	local lastNode = parentNode
	local chainId = armOrdinal + 1
	local kind: SegmentKind = if profile.PadMode then "Pad" else "Arm"

	for armStep = 1, armSteps do
		if #skeleton.Segments >= self.Config.MaxSegments then
			break
		end

		local progress0 = (armStep - 1) / math.max(1, armSteps)
		local progress1 = armStep / math.max(1, armSteps)
		local curvatureDegrees = self.Config.Curvature * (0.9 + profile.ArmCurvature)
		curvatureDegrees += RandomInRange(randomObject, self.Config.CurvatureJitter) * 0.5
		local outwardAngle = math.rad(sideSign * (self.Config.AngleDegrees * (1 - progress0) * 0.18))
		local wobbleAngle = math.rad(RandomInRange(randomObject, self.Config.AngleJitter) * 0.32)

		direction = RotateWithinPlane(direction, outwardAngle + wobbleAngle)
		direction = BlendDirection(
			direction,
			Vector3.new(0, 1, sideSign * 0.08),
			math.clamp(profile.ArmCurvature + progress1 * 0.44 + curvatureDegrees * 0.0025, 0, 0.92)
		)

		local stepLength = nodeSpacing * RandomInRange(randomObject, self.Config.LengthJitter)
		if kind == "Pad" then
			stepLength *= 0.72
		end

		local endPosition = position + direction * stepLength
		local thicknessStart = if armStep == 1
			then math.max(self.Config.MinimumThickness, parentNode.Thickness * self.Config.ArmThicknessScale)
			else lastNode.Thickness
		local thicknessEnd =
			self:ComputeThicknessAtProgress(profile, math.max(heightAlpha, progress1), randomObject, true)
		if kind == "Pad" then
			thicknessEnd *= 1.12
		end
		thicknessEnd = math.max(self.Config.MinimumThickness, thicknessEnd)

		local segment = self:CreateSegment(
			skeleton.Segments,
			parentSegmentIndex,
			position,
			endPosition,
			thicknessStart,
			thicknessEnd,
			1,
			armStep,
			kind,
			chainId,
			sideSign
		)
		parentSegmentIndex = segment.Index

		local nextNode = self:CreateNode(
			skeleton.Nodes,
			lastNode.Index,
			endPosition,
			direction,
			thicknessEnd,
			1,
			endPosition.Y - skeleton.Nodes[1].Position.Y,
			chainId,
			kind,
			sideSign
		)

		lastNode = nextNode
		position = endPosition
		skeleton.Height = math.max(skeleton.Height, nextNode.Height)
	end

	skeleton.ArmCount += 1
end

function CactusGenerator.GrowTrunk(
	self: CactusGenerator,
	skeleton: Skeleton,
	origin: Vector3,
	profile: ArchetypeProfile,
	randomObject: Random
)
	local targetHeight = self:ComputeTargetHeight(profile, randomObject)
	local nodeSpacing = self:ComputeNodeSpacing(profile)
	local stepCount =
		math.max(3, math.min(self.Config.MaxSegments, math.floor(targetHeight / math.max(nodeSpacing, 0.001) + 0.5)))

	local rootNode =
		self:CreateNode(skeleton.Nodes, 0, origin, Vector3.yAxis, self.Config.BaseThickness, 0, 0, 1, "Trunk", 0)
	local currentNode = rootNode
	local direction = Vector3.yAxis
	local previousSideSign = if randomObject:NextNumber() < 0.5 then -1 else 1
	local lastBranchStep = -999
	local parentSegmentIndex = 0

	for stepIndex = 1, stepCount do
		if #skeleton.Segments >= self.Config.MaxSegments then
			break
		end

		local progress0 = (stepIndex - 1) / math.max(1, stepCount)
		local progress1 = stepIndex / math.max(1, stepCount)
		local driftSign = if progress1 > 0.5 then previousSideSign else -previousSideSign
		local leanAngle = math.rad(profile.TrunkLeanDegrees * 0.08 * driftSign)
		local wobbleAngle = math.rad(RandomInRange(randomObject, self.Config.AngleJitter) * 0.18)
		local trunkBendAngle = math.rad(
			RandomInRange(
				randomObject,
				NumberRange.new(-self.Config.TrunkWobbleDegrees, self.Config.TrunkWobbleDegrees)
			)
		)

		direction = RotateWithinPlane(direction, leanAngle + wobbleAngle + trunkBendAngle)
		direction = BlendDirection(
			direction,
			Vector3.yAxis,
			math.clamp(profile.UpwardBias + profile.BendStrength * (1 - progress0), 0, 0.98)
		)

		local stepLength = nodeSpacing * RandomInRange(randomObject, self.Config.LengthJitter)
		local startPosition = currentNode.Position
		local endPosition = startPosition + direction * stepLength
		local thicknessStart = currentNode.Thickness
		local thicknessEnd = self:ComputeThicknessAtProgress(profile, progress1, randomObject, false)

		local segment = self:CreateSegment(
			skeleton.Segments,
			parentSegmentIndex,
			startPosition,
			endPosition,
			thicknessStart,
			thicknessEnd,
			0,
			stepIndex,
			"Trunk",
			1,
			0
		)
		parentSegmentIndex = segment.Index

		currentNode = self:CreateNode(
			skeleton.Nodes,
			currentNode.Index,
			endPosition,
			direction,
			thicknessEnd,
			0,
			endPosition.Y - origin.Y,
			1,
			"Trunk",
			0
		)
		skeleton.Height = math.max(skeleton.Height, currentNode.Height)
		skeleton.TrunkTipNodeIndex = currentNode.Index

		if
			self:ValidateBranchSpawn(
				profile,
				currentNode,
				stepIndex,
				stepCount,
				skeleton.ArmCount,
				lastBranchStep,
				randomObject
			)
		then
			previousSideSign *= -1
			lastBranchStep = stepIndex
			self:GrowArm(
				skeleton,
				currentNode,
				parentSegmentIndex,
				skeleton.ArmCount + 1,
				previousSideSign,
				profile,
				randomObject,
				targetHeight
			)
		end
	end
end

function CactusGenerator.GenerateSkeleton(self: CactusGenerator, origin: Vector3): Skeleton
	local profile = self:GetArchetypeProfile()
	local randomObject = Random.new(self.Seed)
	local skeleton: Skeleton = {
		Nodes = {},
		Segments = {},
		Archetype = self.Config.Archetype,
		Height = 0,
		ArmCount = 0,
		TrunkTipNodeIndex = 0,
	}

	self:GrowTrunk(skeleton, origin, profile, randomObject)

	self.LastSkeleton = skeleton
	self.LastSegments = skeleton.Segments
	self.LastExpandedGrammar = ""
	return skeleton
end

function CactusGenerator.BuildSegmentPart(self: CactusGenerator, segment: Segment): Part
	local segmentCFrame, segmentLength = MakeCFrameFromSegment(segment.Start, segment.End)
	local thickness = math.max(self.Config.MinimumThickness, segment.Thickness)
	local part = Instance.new("Part")

	part.Name = if segment.Kind == "Trunk"
		then `Trunk_{segment.Index}`
		else if segment.Kind == "Pad"
			then `Pad_{segment.ChainId}_{segment.Index}`
			else `Arm_{segment.ChainId}_{segment.Index}`
	part.Shape = Enum.PartType.Cylinder
	part.Size = if segment.Kind == "Pad"
		then Vector3.new(math.max(segmentLength * 0.82, thickness * 0.95), thickness * 1.22, thickness * 1.22)
		else Vector3.new(segmentLength, thickness, thickness)
	part.CFrame = segmentCFrame
	part.Material = ResolveVisibleMaterial(self.Config.SegmentMaterial)
	part.Color = self.Config.SegmentColor
	part.CastShadow = false
	part.CanCollide = self.Config.SegmentCanCollide
	part.CanTouch = self.Config.SegmentCanCollide
	part.CanQuery = self.Config.SegmentCanCollide
	ApplyStudSurfaces(part)
	part:SetAttribute("Depth", segment.Depth)
	part:SetAttribute("Age", segment.Age)
	part:SetAttribute("SegmentKind", segment.Kind)
	part:SetAttribute("ChainId", segment.ChainId)
	part:SetAttribute("SideSign", segment.SideSign)
	part:SetAttribute("ThicknessStart", segment.ThicknessStart)
	part:SetAttribute("ThicknessEnd", segment.ThicknessEnd)
	part:SetAttribute("RibCount", self:GetArchetypeProfile().RibCount)
	return part
end

function CactusGenerator.CreateDetailPart(
	self: CactusGenerator,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = ResolveVisibleMaterial(material)
	part.Anchored = not self.Config.UseWelds
	part.Massless = self.Config.UseWelds
	part.CastShadow = false
	part.CanCollide = canCollide
	part.CanTouch = canCollide
	part.CanQuery = canCollide
	ApplyStudSurfaces(part)
	return part
end

function CactusGenerator.ApplyDetails(
	self: CactusGenerator,
	model: Model,
	skeleton: Skeleton,
	partsByIndex: { [number]: BasePart }
)
	local detailFolder = Instance.new("Folder")
	detailFolder.Name = "Details"
	detailFolder.Parent = model

	local profile = self:GetArchetypeProfile()
	local randomObject = Random.new(self.Seed + 4096)
	local trunkSegments = {} :: { Segment }
	for _, segment in skeleton.Segments do
		if segment.Kind == "Trunk" then
			trunkSegments[#trunkSegments + 1] = segment
		end
	end

	local areoleStep = math.max(1, math.floor(3 / math.max(self.Config.DetailDensity, 0.2)))
	local detailBudget =
		math.max(8, math.floor((#skeleton.Segments + skeleton.ArmCount * 2) * 0.45 * self.Config.DetailDensity))
	local detailCount = 0

	for segmentIndex, segment in skeleton.Segments do
		if detailCount >= detailBudget then
			break
		end

		local segmentPart = partsByIndex[segment.Index]
		if segmentPart == nil then
			continue
		end

		if segmentIndex % areoleStep == 0 then
			local alpha = randomObject:NextNumber(0.28, 0.78)
			local anchor = segment.Start:Lerp(segment.End, alpha)
			local forward = if segmentPart.CFrame.LookVector.Magnitude > 0.001
				then segmentPart.CFrame.LookVector.Unit
				else Vector3.xAxis
			local normal = if randomObject:NextNumber() < 0.5 then forward else -forward
			local areoleSize = math.max(0.08, segment.Thickness * 0.12)
			local areole = self:CreateDetailPart(
				"Areole",
				Vector3.new(areoleSize, areoleSize, areoleSize),
				CFrame.new(anchor + normal * (segment.Thickness * 0.28)),
				self.Config.SegmentColor:Lerp(Color3.new(1, 1, 1), 0.2),
				Enum.Material.Plastic,
				false
			)
			areole.Shape = Enum.PartType.Ball
			areole.Parent = detailFolder
			if self.Config.UseWelds then
				CreateWeld(segmentPart, areole)
			end

			local spineDirection = BlendDirection(normal, Vector3.yAxis, 0.25 + randomObject:NextNumber() * 0.25)
			local spineLength = math.max(0.16, segment.Thickness * 0.24)
			local spine = self:CreateDetailPart(
				"Spine",
				Vector3.new(spineLength, 0.05, 0.05),
				CFrame.lookAt(
					anchor + normal * (segment.Thickness * 0.36),
					anchor + normal * (segment.Thickness * 0.36) + spineDirection
				),
				self.Config.SegmentColor:Lerp(Color3.new(0.95, 0.9, 0.7), 0.7),
				Enum.Material.Plastic,
				false
			)
			spine.Shape = Enum.PartType.Cylinder
			spine.Parent = detailFolder
			if self.Config.UseWelds then
				CreateWeld(segmentPart, spine)
			end

			detailCount += 2
		end
	end

	local ribEvery = if self.Config.Archetype == "Barrel" then 1 else 2
	for trunkIndex, segment in trunkSegments do
		if detailCount >= detailBudget then
			break
		end
		if trunkIndex % ribEvery ~= 0 then
			continue
		end

		local segmentPart = partsByIndex[segment.Index]
		if segmentPart == nil then
			continue
		end

		local cframe, length = MakeCFrameFromSegment(segment.Start, segment.End)
		local ribOffset = math.max(0.06, segment.Thickness * 0.18)
		for _, side in ipairs({ -1, 1 }) do
			if detailCount >= detailBudget then
				break
			end
			local rib = self:CreateDetailPart(
				"Rib",
				Vector3.new(
					length * 0.96,
					math.max(0.06, segment.Thickness * 0.11),
					math.max(0.06, segment.Thickness * 0.11)
				),
				cframe + cframe.UpVector * ribOffset * side,
				self.Config.SegmentColor:Lerp(Color3.new(0, 0, 0), 0.08),
				Enum.Material.Plastic,
				false
			)
			rib.Shape = Enum.PartType.Cylinder
			rib.Parent = detailFolder
			if self.Config.UseWelds then
				CreateWeld(segmentPart, rib)
			end
			detailCount += 1
		end
	end

	if #trunkSegments > 1 then
		local scarCount = math.min(3, math.max(1, math.floor(self.Config.DetailDensity * 2)))
		for _ = 1, scarCount do
			if detailCount >= detailBudget then
				break
			end
			local segment = trunkSegments[randomObject:NextInteger(1, #trunkSegments)]
			local segmentPart = partsByIndex[segment.Index]
			if segmentPart == nil then
				continue
			end

			local anchor = segment.Start:Lerp(segment.End, randomObject:NextNumber(0.22, 0.78))
			local scar = self:CreateDetailPart(
				"Scar",
				Vector3.new(
					math.max(0.14, segment.Thickness * 0.34),
					math.max(0.06, segment.Thickness * 0.1),
					math.max(0.03, segment.Thickness * 0.05)
				),
				CFrame.lookAt(
					anchor + segmentPart.CFrame.LookVector * (segment.Thickness * 0.24),
					anchor + segmentPart.CFrame.LookVector * (segment.Thickness * 0.24) + segmentPart.CFrame.LookVector
				),
				self.Config.SegmentColor:Lerp(Color3.fromRGB(92, 64, 43), 0.34),
				Enum.Material.Plastic,
				false
			)
			scar.Parent = detailFolder
			if self.Config.UseWelds then
				CreateWeld(segmentPart, scar)
			end
			detailCount += 1
		end
	end

	local topSegment = skeleton.Segments[#skeleton.Segments]
	if topSegment ~= nil and randomObject:NextNumber() <= profile.FlowerChance * self.Config.DetailDensity then
		local topPart = partsByIndex[topSegment.Index]
		if topPart ~= nil then
			local tipPosition = topSegment.End
			local petalCount = if self.Config.Archetype == "Barrel" then 4 else 3
			for petalIndex = 1, petalCount do
				local angle = math.rad((360 / petalCount) * (petalIndex - 1))
				local offset = Vector3.new(math.cos(angle) * 0.14, 0.08 + petalIndex * 0.005, math.sin(angle) * 0.14)
				local flower = self:CreateDetailPart(
					"Flower",
					Vector3.new(0.16, 0.16, 0.16),
					CFrame.new(tipPosition + offset),
					Color3.fromRGB(245, 196, 83),
					Enum.Material.Plastic,
					false
				)
				flower.Shape = Enum.PartType.Ball
				flower.Parent = detailFolder
				if self.Config.UseWelds then
					CreateWeld(topPart, flower)
				end
			end
		end
	end
end

function CactusGenerator.BuildGeometry(self: CactusGenerator, skeleton: Skeleton, origin: Vector3): Model
	if self.Model ~= nil then
		self.Model:Destroy()
		self.Model = nil
	end

	local model = Instance.new("Model")
	model.Name = self.Config.ModelName
	model:SetAttribute("Seed", self.Seed)
	model:SetAttribute("Archetype", skeleton.Archetype)
	model:SetAttribute("SegmentCount", #skeleton.Segments)
	model:SetAttribute("ArmCount", skeleton.ArmCount)
	model:SetAttribute("Height", skeleton.Height)

	local segmentsFolder = Instance.new("Folder")
	segmentsFolder.Name = "Segments"
	segmentsFolder.Parent = model

	local partsByIndex: { [number]: BasePart } = {}
	local primaryPart: BasePart? = nil

	for _, segment in skeleton.Segments do
		local segmentPart = self:BuildSegmentPart(segment)
		if primaryPart == nil then
			primaryPart = segmentPart
			segmentPart.Anchored = true
			segmentPart.Massless = false
		elseif self.Config.UseWelds then
			segmentPart.Anchored = false
			segmentPart.Massless = true
		else
			segmentPart.Anchored = true
			segmentPart.Massless = false
		end

		segmentPart.Parent = segmentsFolder
		partsByIndex[segment.Index] = segmentPart

		if self.Config.UseWelds and primaryPart ~= nil and segment.Index ~= 1 then
			local parentPart = partsByIndex[segment.ParentIndex] or primaryPart
			CreateWeld(parentPart, segmentPart)
		end
	end

	if primaryPart == nil then
		local anchor = Instance.new("Part")
		anchor.Name = "Anchor"
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(origin)
		anchor.Transparency = 1
		anchor.CastShadow = false
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Parent = segmentsFolder
		primaryPart = anchor
	end

	model.PrimaryPart = primaryPart
	self:ApplyDetails(model, skeleton, partsByIndex)

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local boundsBottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	local bottomAlignmentOffset = origin.Y - boundsBottomY
	if math.abs(bottomAlignmentOffset) > 0.0001 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, bottomAlignmentOffset, 0))
	end

	model.Parent = if self.Config.Parent ~= nil then self.Config.Parent else Workspace
	self.Model = model
	return model
end

function CactusGenerator.BuildModel(self: CactusGenerator, skeletonOrSegments: any, origin: Vector3): Model
	if typeof(skeletonOrSegments) == "table" and skeletonOrSegments.Segments ~= nil then
		return self:BuildGeometry(skeletonOrSegments :: Skeleton, origin)
	end

	local segments = if typeof(skeletonOrSegments) == "table" then skeletonOrSegments :: { Segment } else {}
	local skeleton: Skeleton = {
		Nodes = {},
		Segments = segments,
		Archetype = self.Config.Archetype,
		Height = 0,
		ArmCount = 0,
		TrunkTipNodeIndex = 0,
	}
	return self:BuildGeometry(skeleton, origin)
end

function CactusGenerator.Interpret(self: CactusGenerator, origin: Vector3): { Segment }
	local skeleton = self:GenerateSkeleton(origin)
	return skeleton.Segments
end

function CactusGenerator.ExpandGrammar(self: CactusGenerator): string
	self.LastExpandedGrammar = ""
	return self.LastExpandedGrammar
end

function CactusGenerator.Generate(self: CactusGenerator, origin: Vector3): Model
	local skeleton = self:GenerateSkeleton(origin)
	return self:BuildGeometry(skeleton, origin)
end

CactusGenerator.new = CactusGenerator.New

return CactusGenerator
