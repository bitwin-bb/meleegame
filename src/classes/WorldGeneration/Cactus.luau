--!strict

local Workspace = game:GetService("Workspace")

export type CactusConfig = {
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
	MaxSymbols: number?,
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
}

type ResolvedCactusConfig = {
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
	MaxSymbols: number,
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
}

export type Segment = {
	Index: number,
	ParentIndex: number,
	Start: Vector3,
	End: Vector3,
	Thickness: number,
	Depth: number,
	Age: number,
}

type TurtleState = {
	Position: Vector3,
	Orientation: CFrame,
	Thickness: number,
	Depth: number,
	Age: number,
	Height: number,
	LastSegmentIndex: number,
}

export type CactusGenerator = typeof(setmetatable(
	{} :: {
		Config: ResolvedCactusConfig,
		Seed: number,
		Model: Model?,
		LastExpandedGrammar: string,
		LastSegments: { Segment },
	},
	{} :: any
))

local CactusGenerator = {}
CactusGenerator.__index = CactusGenerator

local DEFAULT_CONFIG: ResolvedCactusConfig = {
	Seed = 24680,
	Iterations = 6,
	StepLength = 4.4,
	BaseThickness = 3.1,
	AngleDegrees = 34,
	MinBranchHeight = 8,
	MaxBranches = 4,
	Curvature = 13,
	SegmentMaterial = Enum.Material.SmoothPlastic,
	SegmentColor = Color3.fromRGB(80, 143, 74),
	UseWelds = true,
	Parent = nil,
	ModelName = "ProceduralCactus",
	MaxSymbols = 4096,
	MaxSegments = 180,
	BranchChance = 0.38,
	BranchStartIteration = 2,
	LengthJitter = NumberRange.new(0.92, 1.08),
	AngleJitter = NumberRange.new(-4, 4),
	CurvatureJitter = NumberRange.new(-2, 2),
	ThicknessFalloff = 0.55,
	ArmThicknessScale = 0.7,
	TrunkWobbleDegrees = 3.5,
	MinimumThickness = 0.45,
	SegmentCanCollide = false,
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

local function SanitizeNumberRange(
	valueRaw: any,
	fallback: NumberRange,
	minimum: number,
	maximum: number
): NumberRange
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

local function ResolveConfig(configRaw: CactusConfig?): ResolvedCactusConfig
	local source = if typeof(configRaw) == "table" then configRaw :: { [string]: any } else {}

	return {
		Seed = ClampInteger(source.Seed, -2147483648, 2147483647, DEFAULT_CONFIG.Seed),
		Iterations = ClampInteger(source.Iterations, 1, 8, DEFAULT_CONFIG.Iterations),
		StepLength = ClampNumber(source.StepLength, 0.75, 24, DEFAULT_CONFIG.StepLength),
		BaseThickness = ClampNumber(source.BaseThickness, 0.35, 20, DEFAULT_CONFIG.BaseThickness),
		AngleDegrees = ClampNumber(source.AngleDegrees, 5, 80, DEFAULT_CONFIG.AngleDegrees),
		MinBranchHeight = ClampNumber(source.MinBranchHeight, 0, 128, DEFAULT_CONFIG.MinBranchHeight),
		MaxBranches = ClampInteger(source.MaxBranches, 0, 8, DEFAULT_CONFIG.MaxBranches),
		Curvature = ClampNumber(source.Curvature, 0, 45, DEFAULT_CONFIG.Curvature),
		SegmentMaterial = SanitizeMaterial(source.SegmentMaterial, DEFAULT_CONFIG.SegmentMaterial),
		SegmentColor = SanitizeColor(source.SegmentColor, DEFAULT_CONFIG.SegmentColor),
		UseWelds = if source.UseWelds == nil then DEFAULT_CONFIG.UseWelds else source.UseWelds == true,
		Parent = if typeof(source.Parent) == "Instance" then source.Parent else DEFAULT_CONFIG.Parent,
		ModelName = SanitizeString(source.ModelName, DEFAULT_CONFIG.ModelName),
		MaxSymbols = ClampInteger(source.MaxSymbols, 64, 32768, DEFAULT_CONFIG.MaxSymbols),
		MaxSegments = ClampInteger(source.MaxSegments, 4, 512, DEFAULT_CONFIG.MaxSegments),
		BranchChance = ClampNumber(source.BranchChance, 0, 1, DEFAULT_CONFIG.BranchChance),
		BranchStartIteration = ClampInteger(source.BranchStartIteration, 1, 8, DEFAULT_CONFIG.BranchStartIteration),
		LengthJitter = SanitizeNumberRange(source.LengthJitter, DEFAULT_CONFIG.LengthJitter, 0.5, 2),
		AngleJitter = SanitizeNumberRange(source.AngleJitter, DEFAULT_CONFIG.AngleJitter, -30, 30),
		CurvatureJitter = SanitizeNumberRange(source.CurvatureJitter, DEFAULT_CONFIG.CurvatureJitter, -20, 20),
		ThicknessFalloff = ClampNumber(source.ThicknessFalloff, 0, 1, DEFAULT_CONFIG.ThicknessFalloff),
		ArmThicknessScale = ClampNumber(source.ArmThicknessScale, 0.25, 1, DEFAULT_CONFIG.ArmThicknessScale),
		TrunkWobbleDegrees = ClampNumber(source.TrunkWobbleDegrees, 0, 18, DEFAULT_CONFIG.TrunkWobbleDegrees),
		MinimumThickness = ClampNumber(source.MinimumThickness, 0.1, 8, DEFAULT_CONFIG.MinimumThickness),
		SegmentCanCollide = if source.SegmentCanCollide == nil
			then DEFAULT_CONFIG.SegmentCanCollide
			else source.SegmentCanCollide == true,
	}
end

local function RandomInRange(randomObject: Random, range: NumberRange): number
	if range.Max <= range.Min then
		return range.Min
	end
	return randomObject:NextNumber(range.Min, range.Max)
end

local function MakeOrientation(position: Vector3, directionRaw: Vector3): CFrame
	local direction = if directionRaw.Magnitude > 0.0001 then directionRaw.Unit else Vector3.yAxis
	local upVector = if math.abs(direction:Dot(Vector3.yAxis)) > 0.985 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + direction, upVector)
end

local function RotateAroundDepthAxis(orientation: CFrame, angleRadians: number): CFrame
	local rotatedDirection = CFrame.fromAxisAngle(Vector3.xAxis, angleRadians):VectorToWorldSpace(orientation.LookVector)
	return MakeOrientation(orientation.Position, rotatedDirection)
end

local function BendOrientationTowardUp(orientation: CFrame, curvatureRadians: number): CFrame
	local lookVector = orientation.LookVector
	local planarAngle = math.atan2(lookVector.Z, lookVector.Y)
	if math.abs(planarAngle) <= 1e-4 then
		return MakeOrientation(orientation.Position, Vector3.yAxis)
	end

	local nextAngle = planarAngle
	if planarAngle > 0 then
		nextAngle = math.max(0, planarAngle - curvatureRadians)
	else
		nextAngle = math.min(0, planarAngle + curvatureRadians)
	end

	local bentDirection = Vector3.new(0, math.cos(nextAngle), math.sin(nextAngle))
	return MakeOrientation(orientation.Position, bentDirection)
end

local function CloneTurtleState(state: TurtleState): TurtleState
	return {
		Position = state.Position,
		Orientation = state.Orientation,
		Thickness = state.Thickness,
		Depth = state.Depth,
		Age = state.Age,
		Height = state.Height,
		LastSegmentIndex = state.LastSegmentIndex,
	}
end

local function AppendText(buffer: { string }, text: string, maxSymbols: number): boolean
	if text == "" then
		return true
	end
	local nextLength = 0
	for _, chunk in buffer do
		nextLength += #chunk
	end
	if nextLength + #text > maxSymbols then
		return false
	end
	buffer[#buffer + 1] = text
	return true
end

local function CreateWeld(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CactusWeld"
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
end

local function CreateSegmentTransform(startPosition: Vector3, endPosition: Vector3): (CFrame, number)
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

function CactusGenerator.New(configRaw: CactusConfig?): CactusGenerator
	local config = ResolveConfig(configRaw)
	local self = setmetatable({
		Config = config,
		Seed = config.Seed,
		Model = nil :: Model?,
		LastExpandedGrammar = "",
		LastSegments = {} :: { Segment },
	}, CactusGenerator)
	return self
end

function CactusGenerator.new(configRaw: CactusConfig?): CactusGenerator
	return CactusGenerator.New(configRaw)
end

function CactusGenerator.Destroy(self: CactusGenerator)
	if self.Model ~= nil then
		self.Model:Destroy()
		self.Model = nil
	end
	self.LastSegments = {}
	self.LastExpandedGrammar = ""
end

function CactusGenerator.SetSeed(self: CactusGenerator, seedRaw: any)
	self.Seed = ClampInteger(seedRaw, -2147483648, 2147483647, self.Seed)
	self.Config.Seed = self.Seed
end

function CactusGenerator.GetSeed(self: CactusGenerator): number
	return self.Seed
end

function CactusGenerator.ExpandGrammar(self: CactusGenerator): string
	local randomObject = Random.new(self.Seed)
	local current = "X"
	local plannedBranches = 0
	local preferredMajorBranchSide = if randomObject:NextNumber() < 0.5 then 0 else 1
	local branchPlanningStartIteration = math.max(
		self.Config.BranchStartIteration,
		math.min(self.Config.Iterations, math.max(2, math.floor(self.Config.Iterations * 0.45 + 0.5)))
	)

	for iteration = 1, self.Config.Iterations do
		local buffer: { string } = {}
		local overflowed = false

		for symbolIndex = 1, #current do
			local symbol = string.sub(current, symbolIndex, symbolIndex)
			local replacement = symbol

			if symbol == "X" then
				replacement = "F~X"
				local canPlanBranch = iteration >= branchPlanningStartIteration and plannedBranches < self.Config.MaxBranches
				if canPlanBranch then
					local maturityAlpha = iteration / math.max(self.Config.Iterations, 1)
					local branchChance = math.clamp(self.Config.BranchChance * (0.22 + maturityAlpha * 0.78), 0, 1)
					if randomObject:NextNumber() <= branchChance then
						local branchOrdinal = plannedBranches + 1
						local turnSymbol = if ((branchOrdinal + preferredMajorBranchSide) % 2) == 0 then "+" else "-"
						local outwardLead = if branchOrdinal <= 2
							then if randomObject:NextNumber() < 0.45 then "FFFF" else "FFF"
							else if randomObject:NextNumber() < 0.55 then "FFF" else "FF"
						replacement ..= `[{turnSymbol}B{outwardLead}CA]`
						plannedBranches += 1
					end
				end
			elseif symbol == "A" then
				local continuationRoll = randomObject:NextNumber()
				if continuationRoll < 0.2 then
					replacement = "FC"
				elseif continuationRoll < 0.56 then
					replacement = "FCA"
				else
					replacement = "FFCA"
				end
			end

			if not AppendText(buffer, replacement, self.Config.MaxSymbols) then
				overflowed = true
				break
			end
		end

		current = table.concat(buffer)
		if overflowed or #current >= self.Config.MaxSymbols then
			break
		end
	end

	self.LastExpandedGrammar = current
	return current
end

function CactusGenerator.Interpret(self: CactusGenerator, origin: Vector3): { Segment }
	local grammar = self.LastExpandedGrammar
	if grammar == "" then
		grammar = self:ExpandGrammar()
	end

	local randomObject = Random.new(self.Seed + 1009)
	local segments: { Segment } = {}
	local stack: { TurtleState } = {}
	local skipBranchDepth = 0
	local activeBranches = 0

	local current: TurtleState = {
		Position = origin,
		Orientation = MakeOrientation(origin, Vector3.yAxis),
		Thickness = self.Config.BaseThickness,
		Depth = 0,
		Age = 0,
		Height = 0,
		LastSegmentIndex = 0,
	}

	local approximateMaxHeight = math.max(self.Config.StepLength * self.Config.Iterations * 3.25, self.Config.StepLength)

	for symbolIndex = 1, #grammar do
		local symbol = string.sub(grammar, symbolIndex, symbolIndex)

		if skipBranchDepth > 0 then
			if symbol == "[" then
				skipBranchDepth += 1
			elseif symbol == "]" then
				if skipBranchDepth == 1 then
					local restored = stack[#stack]
					if restored ~= nil then
						current = restored
						table.remove(stack)
					end
				end
				skipBranchDepth -= 1
			end
			continue
		end

		if symbol == "[" then
			stack[#stack + 1] = CloneTurtleState(current)
			current = CloneTurtleState(current)
			current.Depth += 1
			current.Thickness = math.max(self.Config.MinimumThickness, current.Thickness * self.Config.ArmThicknessScale)
		elseif symbol == "]" then
			local restored = stack[#stack]
			if restored ~= nil then
				current = restored
				table.remove(stack)
			end
		elseif symbol == "B" then
			local canActivateBranch = current.Depth == 1
				and current.Height >= self.Config.MinBranchHeight
				and current.Height <= approximateMaxHeight * 0.84
				and activeBranches < self.Config.MaxBranches
			if canActivateBranch then
				activeBranches += 1
			else
				skipBranchDepth = 1
			end
		elseif symbol == "F" then
			if #segments >= self.Config.MaxSegments then
				break
			end

			local stepLength = math.max(
				self.Config.StepLength * 0.45,
				self.Config.StepLength * RandomInRange(randomObject, self.Config.LengthJitter)
			)
			local startPosition = current.Position
			local endPosition = startPosition + current.Orientation.LookVector * stepLength
			local taperAlpha = math.clamp(current.Height / approximateMaxHeight, 0, 1)
			local depthThicknessScale = if current.Depth <= 0
				then 1
				else self.Config.ArmThicknessScale ^ current.Depth
			local segmentThickness = math.max(
				self.Config.MinimumThickness,
				current.Thickness * (1 - taperAlpha * self.Config.ThicknessFalloff) * depthThicknessScale
			)
			local nextIndex = #segments + 1

			segments[nextIndex] = {
				Index = nextIndex,
				ParentIndex = current.LastSegmentIndex,
				Start = startPosition,
				End = endPosition,
				Thickness = segmentThickness,
				Depth = current.Depth,
				Age = current.Age,
			}

			current.Position = endPosition
			current.LastSegmentIndex = nextIndex
			current.Age += 1
			current.Height = math.max(current.Height, endPosition.Y - origin.Y)

			local thicknessDecay = if current.Depth <= 0 then 0.982 else 0.935
			current.Thickness = math.max(self.Config.MinimumThickness, current.Thickness * thicknessDecay)
			current.Orientation = MakeOrientation(current.Position, current.Orientation.LookVector)
		elseif symbol == "+" or symbol == "-" then
			local signedAngleDegrees =
				self.Config.AngleDegrees + RandomInRange(randomObject, self.Config.AngleJitter)
			local signedAngleRadians = math.rad(math.abs(signedAngleDegrees))
			if symbol == "-" then
				signedAngleRadians = -signedAngleRadians
			end
			current.Orientation = RotateAroundDepthAxis(current.Orientation, signedAngleRadians)
		elseif symbol == "~" then
			local wobbleRadians = math.rad(randomObject:NextNumber(-self.Config.TrunkWobbleDegrees, self.Config.TrunkWobbleDegrees))
			current.Orientation = RotateAroundDepthAxis(current.Orientation, wobbleRadians)
		elseif symbol == "C" then
			local curvatureDegrees =
				math.max(0, self.Config.Curvature + RandomInRange(randomObject, self.Config.CurvatureJitter))
			local curvatureScale = if current.Depth > 0 then 1.32 else 1
			current.Orientation = BendOrientationTowardUp(current.Orientation, math.rad(curvatureDegrees * curvatureScale))
		end
	end

	self.LastSegments = segments
	return segments
end

function CactusGenerator.BuildSegmentPart(self: CactusGenerator, segment: Segment): Part
	local segmentCFrame, segmentLength = CreateSegmentTransform(segment.Start, segment.End)
	local part = Instance.new("Part")
	part.Name = if segment.Depth <= 0 then `Trunk_{segment.Index}` else `Arm_{segment.Depth}_{segment.Index}`
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(segmentLength, segment.Thickness, segment.Thickness)
	part.CFrame = segmentCFrame
	part.Material = self.Config.SegmentMaterial
	part.Color = self.Config.SegmentColor
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.CanCollide = self.Config.SegmentCanCollide
	part.CanTouch = self.Config.SegmentCanCollide
	part.CanQuery = self.Config.SegmentCanCollide
	part:SetAttribute("Depth", segment.Depth)
	part:SetAttribute("SegmentIndex", segment.Index)
	part:SetAttribute("ParentSegmentIndex", segment.ParentIndex)
	part:SetAttribute("Age", segment.Age)
	return part
end

function CactusGenerator.BuildModel(self: CactusGenerator, segments: { Segment }, origin: Vector3): Model
	if self.Model ~= nil then
		self.Model:Destroy()
		self.Model = nil
	end

	local model = Instance.new("Model")
	model.Name = self.Config.ModelName
	model:SetAttribute("Seed", self.Seed)
	model:SetAttribute("GrammarLength", #self.LastExpandedGrammar)
	model:SetAttribute("SegmentCount", #segments)

	local segmentsFolder = Instance.new("Folder")
	segmentsFolder.Name = "Segments"
	segmentsFolder.Parent = model

	local partsByIndex: { [number]: BasePart } = {}
	local primaryPart: BasePart? = nil

	for _, segment in segments do
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
	if self.Config.Parent ~= nil then
		model.Parent = self.Config.Parent
	else
		model.Parent = Workspace
	end

	self.Model = model
	return model
end

function CactusGenerator.Generate(self: CactusGenerator, origin: Vector3): Model
	local grammar = self:ExpandGrammar()
	self.LastExpandedGrammar = grammar
	local segments = self:Interpret(origin)
	return self:BuildModel(segments, origin)
end

return CactusGenerator
