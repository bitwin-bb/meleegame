local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Sift = require(ReplicatedStorage.Packages.Sift)

local Damp = require("Damp")
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local TreeFoliageGraph = require("TreeFoliageGraph")
local Vec = require("Vec")

local FoliageInstance = {}
FoliageInstance.__index = FoliageInstance

export type MotionStyle = "GrassTip" | "BushBlend" | "Branch"
export type Representation = "BasePart" | "Model" | "Bone"

export type Config = {
	id: number,
	seed: number,
	bucketIndex: number,
	presetName: string,
	representation: Representation?,
	motionStyle: MotionStyle?,
	bendStiffness: number,
	damping: number,
	maxBendAngle: number,
	heightMultiplier: number,
	swayAmplitude: number,
	gustSensitivity: number,
	recoverySpeed: number,
	disturbanceSensitivity: number,
	detailAmplitude: number?,
	translationWeight: number?,
	yawWeight: number?,
	tipBias: number?,
	pivotMode: string?,
	pivotAttachmentName: string?,
	pivotOffset: Vector3?,
	boneNames: { string }?,
	tweenSmoothingEnabled: boolean?,
	tweenSmoothingDuration: number?,
	tweenSmoothingMaxDuration: number?,
}

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

export type FoliageInstance = typeof(setmetatable({} :: any, FoliageInstance))

type BoneRecord = {
	bone: Bone,
	restTransform: CFrame,
	weight: number,
	activeTween: Tween?,
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> any,
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local ZERO = Vector3.zero
local DEFAULT_MOTION_STYLE: MotionStyle = "GrassTip"
local DEFAULT_REPRESENTATION: Representation = "BasePart"
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

local function CoerceString(valueRaw: any, fallback: string): string
	return if typeof(valueRaw) == "string" and valueRaw ~= "" then valueRaw else fallback
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

local function cancelTween(tween: Tween?)
	if tween ~= nil then
		tween:Cancel()
	end
end

local function createTween(instance: Instance, tweenInfo: TweenInfo, goal: { [string]: any }): Tween?
	local ok, tween = pcall(function()
		return TweenService:Create(instance, tweenInfo, goal)
	end)
	return if ok then tween else nil
end

local function normalizeMotionStyle(valueRaw: any): MotionStyle
	if valueRaw == "BushBlend" then
		return "BushBlend"
	end
	if valueRaw == "Branch" then
		return "Branch"
	end
	return "GrassTip"
end

local function normalizeRepresentation(valueRaw: any): Representation
	if valueRaw == "Model" then
		return "Model"
	end
	if valueRaw == "Bone" then
		return "Bone"
	end
	return DEFAULT_REPRESENTATION
end

local function GetBasePartFromInstance(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		if instance.PrimaryPart ~= nil then
			return instance.PrimaryPart
		end
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end
	return nil
end

local function safeModelPivot(model: Model): CFrame
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok and typeof(pivot) == "CFrame" then
		return pivot
	end
	return CFrame.new()
end

local function safeModelBoundingBox(model: Model): (CFrame, Vector3)
	local ok, boxCFrame, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and typeof(boxCFrame) == "CFrame" and typeof(boxSize) == "Vector3" then
		return boxCFrame, boxSize
	end
	return safeModelPivot(model), Vector3.one
end

local function getInstanceHeight(instance: Instance): number
	if instance:IsA("BasePart") then
		return math.max(0.25, instance.Size.Y)
	end
	if instance:IsA("Model") then
		local _, size = safeModelBoundingBox(instance)
		return math.max(0.25, size.Y)
	end
	local parentModel = instance:FindFirstAncestorOfClass("Model")
	if parentModel ~= nil then
		local _, size = safeModelBoundingBox(parentModel)
		return math.max(0.25, size.Y)
	end
	return 1
end

local function findAttachmentByName(root: Instance, name: string?): Attachment?
	if name == nil or name == "" then
		return nil
	end
	if root:IsA("Attachment") and root.Name == name then
		return root
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

local function normalizePivotMode(valueRaw: any): string
	if valueRaw == "Center" then
		return "Center"
	end
	if valueRaw == "Attachment" then
		return "Attachment"
	end
	if valueRaw == "Bottom" then
		return "Bottom"
	end
	return "Auto"
end

local function GetPartPivotFrame(part: BasePart, config: Config): CFrame
	local pivotOffset = if typeof(config.pivotOffset) == "Vector3" then config.pivotOffset else ZERO
	local pivotAttachment = findAttachmentByName(part, config.pivotAttachmentName)
	local pivotMode = normalizePivotMode(config.pivotMode)

	if pivotAttachment ~= nil then
		return pivotAttachment.WorldCFrame * CFrame.new(pivotOffset)
	end

	local localOffset = pivotOffset
	if pivotMode == "Bottom" or pivotMode == "Auto" then
		localOffset += Vector3.new(0, -part.Size.Y * 0.5, 0)
	end

	return part.CFrame * CFrame.new(localOffset)
end

local function GetModelPivotFrame(model: Model, config: Config): CFrame
	local pivotOffset = if typeof(config.pivotOffset) == "Vector3" then config.pivotOffset else ZERO
	local pivotAttachment = findAttachmentByName(model, config.pivotAttachmentName)
	local pivotMode = normalizePivotMode(config.pivotMode)

	if pivotAttachment ~= nil then
		local modelPivot = safeModelPivot(model)
		local attachmentPosition = pivotAttachment.WorldPosition
		local planarLook = Vector3.new(modelPivot.LookVector.X, 0, modelPivot.LookVector.Z)
		if planarLook.Magnitude > 1e-4 then
			return CFrame.lookAt(attachmentPosition, attachmentPosition + planarLook.Unit, Vector3.yAxis)
				* CFrame.new(pivotOffset)
		end
		return CFrame.new(attachmentPosition) * CFrame.new(pivotOffset)
	end

	local pivot = safeModelPivot(model)
	if pivotMode == "Bottom" or pivotMode == "Auto" then
		local _, boxSize = safeModelBoundingBox(model)
		return pivot * CFrame.new(pivotOffset + Vector3.new(0, -boxSize.Y * 0.5, 0))
	end

	return pivot * CFrame.new(pivotOffset)
end

local function countDepth(instance: Instance): number
	local depth = 0
	local current = instance.Parent
	while current ~= nil do
		depth += 1
		current = current.Parent
	end
	return depth
end

local function GetBoneNames(config: Config): { string }
	local raw = config.boneNames
	if typeof(raw) ~= "table" then
		return {}
	end
	local out = {}
	for _, value in raw do
		if typeof(value) == "string" and value ~= "" then
			out[#out + 1] = value
		end
	end
	return out
end

local function collectBones(root: Instance, config: Config): { BoneRecord }
	local requestedNames = GetBoneNames(config)
	local bones = {}

	if #requestedNames > 0 then
		for _, name in requestedNames do
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("Bone") and descendant.Name == name then
					bones[#bones + 1] = descendant
					break
				end
			end
		end
	elseif root:IsA("Bone") then
		bones[1] = root
	else
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Bone") then
				bones[#bones + 1] = descendant
			end
		end
		table.sort(bones, function(a: Bone, b: Bone)
			local depthA = countDepth(a)
			local depthB = countDepth(b)
			if depthA ~= depthB then
				return depthA < depthB
			end
			return a:GetFullName() < b:GetFullName()
		end)
	end

	local tipBias = clampNumber(config.tipBias, 1.9, 0.1, 6)
	local records = Sift.Array.create(#bones)
	local count = #bones
	for index, bone in bones do
		local alpha = if count <= 1 then 1 else (index - 1) / (count - 1)
		local weight = if count <= 1 then 1 else math.max(0.12, alpha ^ tipBias)
		records[index] = {
			bone = bone,
			restTransform = bone.Transform,
			weight = weight,
			activeTween = nil,
		}
	end

	return records
end

local function GetEferenceFrame(instance: Instance): CFrame
	if instance:IsA("Bone") then
		local ok, worldCFrame = pcall(function()
			return instance.WorldCFrame
		end)
		if ok and typeof(worldCFrame) == "CFrame" then
			return worldCFrame
		end
	end
	if instance:IsA("Model") then
		return safeModelPivot(instance)
	end
	local part = GetBasePartFromInstance(instance)
	if part ~= nil then
		return part.CFrame
	end
	return CFrame.new()
end

local function determineRepresentation(instance: Instance, config: Config): Representation?
	local explicitRepresentation = config.representation
	if explicitRepresentation ~= nil then
		local normalized = normalizeRepresentation(explicitRepresentation)
		if normalized == "Bone" then
			return normalized
		end
		if normalized == "Model" and instance:IsA("Model") then
			return normalized
		end
		if normalized == "BasePart" and instance:IsA("BasePart") then
			return normalized
		end
	end

	if instance:IsA("Bone") then
		return "Bone"
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Bone") then
			return "Bone"
		end
	end

	if instance:IsA("Model") then
		return "Model"
	end
	if instance:IsA("BasePart") then
		return "BasePart"
	end
	return nil
end

function FoliageInstance.New(instanceRaw: any, configRaw: Config?): FoliageInstance?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end

	local instance = instanceRaw :: Instance
	local config = if typeof(configRaw) == "table" then configRaw else {} :: Config
	local representation = determineRepresentation(instance, config)
	if representation == nil then
		return nil
	end

	local janitor = Janitor.new()
	local motionStyle = normalizeMotionStyle(config.motionStyle or DEFAULT_MOTION_STYLE)
	local referenceFrame = GetEferenceFrame(instance)
	local objectHeight = getInstanceHeight(instance)
	local phaseOffset = (config.seed % 100000) / 100000 * math.pi * 2
	local amplitudeScale = 0.92 + ((config.seed % 8191) / 8191) * 0.18

	local self = setmetatable({
		id = config.id,
		instance = instance,
		representation = representation,
		motionStyle = motionStyle,
		presetName = CoerceString(config.presetName, "GrassLight"),
		bucketIndex = config.bucketIndex,
		janitor = janitor,
		config = config,
		referenceFrame = referenceFrame,
		objectHeight = objectHeight,
		rootPosition = referenceFrame.Position,
		currentBend = ZERO,
		springVelocity = ZERO,
		reactiveBend = ZERO,
		lastDisturbanceImpulse = ZERO,
		lastUpdateTime = 0,
		phaseOffset = phaseOffset,
		amplitudeScale = amplitudeScale,
		part = nil :: BasePart?,
		model = nil :: Model?,
		treeGraph = nil :: any,
		bones = {} :: { BoneRecord },
		restCFrame = nil :: CFrame?,
		restPivotFrame = nil :: CFrame?,
		pivotToObject = nil :: CFrame?,
		activePartTween = nil :: Tween?,
		activeModelTween = nil :: Tween?,
		modelTweenValue = nil :: CFrameValue?,
		modelTweenConnection = nil :: RBXScriptConnection?,
		destroyed = false,
	}, FoliageInstance)

	if representation == "Model" then
		local model = instance :: Model
		local treeGraph = TreeFoliageGraph.New(model, config)
		if treeGraph ~= nil then
			self.model = model
			self.treeGraph = treeGraph
			self.referenceFrame = CFrame.new(treeGraph:GetRootPosition())
			self.rootPosition = treeGraph:GetRootPosition()
		else
			local restCFrame = safeModelPivot(model)
			local restPivotFrame = GetModelPivotFrame(model, config)
			self.model = model
			self.restCFrame = restCFrame
			self.restPivotFrame = restPivotFrame
			self.pivotToObject = restPivotFrame:ToObjectSpace(restCFrame)
			self.referenceFrame = restPivotFrame
			self.rootPosition = restPivotFrame.Position
		end
	elseif representation == "BasePart" then
		local part = instance :: BasePart
		local restCFrame = part.CFrame
		local restPivotFrame = GetPartPivotFrame(part, config)
		self.part = part
		self.restCFrame = restCFrame
		self.restPivotFrame = restPivotFrame
		self.pivotToObject = restPivotFrame:ToObjectSpace(restCFrame)
		self.referenceFrame = restPivotFrame
		self.rootPosition = restPivotFrame.Position
	else
		self.bones = collectBones(instance, config)
		if #self.bones <= 0 then
			janitor:Destroy()
			return nil
		end
		self.referenceFrame = GetEferenceFrame(instance)
		self.rootPosition = self.referenceFrame.Position
	end

	janitor:GiveChore(instance.Destroying:Connect(function()
		self:Destroy()
	end))

	return self
end

function FoliageInstance.GetRootPosition(self: FoliageInstance): Vector3
	if self.treeGraph ~= nil then
		return self.treeGraph:GetRootPosition()
	end
	return self.rootPosition
end

function FoliageInstance.CancelTweens(self: FoliageInstance)
	if self.treeGraph ~= nil and self.treeGraph.CancelTweens ~= nil then
		self.treeGraph:CancelTweens()
	end

	cancelTween(self.activePartTween)
	self.activePartTween = nil

	cancelTween(self.activeModelTween)
	self.activeModelTween = nil

	for _, record in self.bones do
		cancelTween(record.activeTween)
		record.activeTween = nil
	end
end

function FoliageInstance.ResetPose(self: FoliageInstance)
	if self.destroyed then
		return
	end

	self:CancelTweens()
	self.currentBend = ZERO
	self.springVelocity = ZERO
	self.reactiveBend = ZERO
	self.lastDisturbanceImpulse = ZERO

	if self.treeGraph ~= nil then
		self.treeGraph:Reset()
		self.rootPosition = self.treeGraph:GetRootPosition()
		return
	end

	if self.representation == "BasePart" then
		local part = self.part
		local restCFrame = self.restCFrame
		local restPivotFrame = self.restPivotFrame
		if part ~= nil and restCFrame ~= nil and part.Parent ~= nil then
			part.CFrame = restCFrame
		end
		if restPivotFrame ~= nil then
			self.rootPosition = restPivotFrame.Position
		end
		return
	end

	if self.representation == "Model" then
		local model = self.model
		local restCFrame = self.restCFrame
		local restPivotFrame = self.restPivotFrame
		if model ~= nil and restCFrame ~= nil and model.Parent ~= nil then
			if self.modelTweenValue ~= nil then
				self.modelTweenValue.Value = restCFrame
			end
			model:PivotTo(restCFrame)
		end
		if restPivotFrame ~= nil then
			self.rootPosition = restPivotFrame.Position
		end
		return
	end

	for _, record in self.bones do
		if record.bone.Parent ~= nil then
			record.bone.Transform = record.restTransform
		end
	end
	self.rootPosition = self.referenceFrame.Position
end

function FoliageInstance.TweenPartCFrame(
	self: FoliageInstance,
	part: BasePart,
	targetCFrame: CFrame,
	presentationDt: number
)
	local duration = getTweenSmoothingDuration(self.config, presentationDt)
	cancelTween(self.activePartTween)
	self.activePartTween = nil

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

	self.activePartTween = tween
	tween.Completed:Connect(function()
		if self.activePartTween == tween then
			self.activePartTween = nil
		end
	end)
	tween:Play()
end

function FoliageInstance.TweenModelPivot(
	self: FoliageInstance,
	model: Model,
	targetCFrame: CFrame,
	presentationDt: number
)
	local duration = getTweenSmoothingDuration(self.config, presentationDt)
	cancelTween(self.activeModelTween)
	self.activeModelTween = nil

	if duration <= 0 then
		model:PivotTo(targetCFrame)
		return
	end

	local tweenValue = self.modelTweenValue
	if tweenValue == nil then
		tweenValue = Instance.new("CFrameValue")
		tweenValue.Value = safeModelPivot(model)
		self.modelTweenValue = tweenValue

		local connection = tweenValue.Changed:Connect(function(value: CFrame)
			if self.destroyed or model.Parent == nil then
				return
			end
			model:PivotTo(value)
		end)
		self.modelTweenConnection = connection

		local janitor = self.janitor :: JanitorClass
		janitor:GiveChore(connection)
		janitor:GiveChore(tweenValue)
	end

	tweenValue.Value = safeModelPivot(model)
	local tween = createTween(
		tweenValue,
		TweenInfo.new(duration, TWEEN_EASING_STYLE, TWEEN_EASING_DIRECTION),
		{ Value = targetCFrame }
	)
	if tween == nil then
		model:PivotTo(targetCFrame)
		return
	end

	self.activeModelTween = tween
	tween.Completed:Connect(function()
		if self.activeModelTween == tween then
			self.activeModelTween = nil
		end
	end)
	tween:Play()
end

function FoliageInstance.TweenBoneTransform(
	self: FoliageInstance,
	record: BoneRecord,
	targetTransform: CFrame,
	presentationDt: number
)
	local duration = getTweenSmoothingDuration(self.config, presentationDt)
	cancelTween(record.activeTween)
	record.activeTween = nil

	if duration <= 0 then
		record.bone.Transform = targetTransform
		return
	end

	local tween = createTween(
		record.bone,
		TweenInfo.new(duration, TWEEN_EASING_STYLE, TWEEN_EASING_DIRECTION),
		{ Transform = targetTransform }
	)
	if tween == nil then
		record.bone.Transform = targetTransform
		return
	end

	record.activeTween = tween
	tween.Completed:Connect(function()
		if record.activeTween == tween then
			record.activeTween = nil
		end
	end)
	tween:Play()
end

function FoliageInstance.AddDisturbance(self: FoliageInstance, impulseWorld: Vector3, originWorldRaw: any?)
	if self.destroyed then
		return
	end
	if impulseWorld.Magnitude <= 1e-5 then
		return
	end
	if self.treeGraph ~= nil then
		self.treeGraph:AddDisturbance(impulseWorld, originWorldRaw)
		return
	end

	local scaledImpulse = impulseWorld * clampNumber(self.config.disturbanceSensitivity, 1, 0, 10)
	self.reactiveBend += scaledImpulse
	if self.reactiveBend.Magnitude > 2 then
		self.reactiveBend = self.reactiveBend.Unit * 2
	end
	self.lastDisturbanceImpulse = scaledImpulse
	self.springVelocity += scaledImpulse * 0.28
end

function FoliageInstance.GetLocalAngles(
	self: FoliageInstance,
	bendWorld: Vector3,
	flutter: number,
	lod: LODState
): (number, number, number, Vector3)
	local reference = self.referenceFrame
	local planar = Vec.FlattenY(bendWorld)
	local magnitude = planar.Magnitude
	if magnitude <= 1e-5 then
		return 0, 0, 0, ZERO
	end

	local direction = planar / magnitude
	local localDirection = reference:VectorToObjectSpace(direction)
	local angleRadians = math.rad(clampNumber(self.config.maxBendAngle, 15, 0, 89))
	local blendWeight = 1
	local translationWeight = clampNumber(self.config.translationWeight, 0.12, 0, 1)
	local yawWeight = clampNumber(self.config.yawWeight, 0.06, 0, 1)

	if self.motionStyle == "BushBlend" then
		blendWeight = 0.72
		translationWeight = math.max(translationWeight, 0.18)
		yawWeight = math.max(yawWeight, 0.14)
	elseif self.motionStyle == "Branch" then
		blendWeight = 0.58
		translationWeight = math.max(translationWeight, 0.08)
		yawWeight = math.max(yawWeight, 0.1)
	end

	local finalAngle = math.min(1.2, magnitude) * angleRadians * blendWeight
	local pitch = -localDirection.Z * finalAngle
	local roll = localDirection.X * finalAngle
	local yaw = flutter * yawWeight * lod.detailScale * angleRadians * 0.35

	local translationDistance = self.objectHeight
		* clampNumber(self.config.heightMultiplier, 1, 0.1, 8)
		* translationWeight
		* magnitude
		* lod.windScale
	local translationWorld = direction * translationDistance + Vector3.new(0, -translationDistance * 0.06, 0)

	return pitch, yaw, roll, translationWorld
end

function FoliageInstance.ApplyTransform(
	self: FoliageInstance,
	pitch: number,
	yaw: number,
	roll: number,
	translationWorld: Vector3,
	presentationDt: number
)
	if self.destroyed then
		return
	end

	if self.representation == "BasePart" then
		local part = self.part
		local restPivotFrame = self.restPivotFrame
		local pivotToObject = self.pivotToObject
		if part == nil or restPivotFrame == nil or pivotToObject == nil or part.Parent == nil then
			return
		end

		local pivotFrame = restPivotFrame + translationWorld
		local finalCFrame = pivotFrame * CFrame.Angles(pitch, yaw, roll) * pivotToObject
		self:TweenPartCFrame(part, finalCFrame, presentationDt)
		return
	end

	if self.representation == "Model" then
		local model = self.model
		local restPivotFrame = self.restPivotFrame
		local pivotToObject = self.pivotToObject
		if model == nil or restPivotFrame == nil or pivotToObject == nil or model.Parent == nil then
			return
		end

		local pivotFrame = restPivotFrame + translationWorld
		self:TweenModelPivot(model, pivotFrame * CFrame.Angles(pitch, yaw, roll) * pivotToObject, presentationDt)
		return
	end

	local lateralOffset = self.referenceFrame:VectorToObjectSpace(translationWorld)
	for _, record in self.bones do
		if record.bone.Parent == nil then
			continue
		end

		local weight = record.weight
		local targetTransform = record.restTransform
			* CFrame.new(lateralOffset * weight * 0.18)
			* CFrame.Angles(pitch * weight, yaw * weight, roll * weight)
		self:TweenBoneTransform(record, targetTransform, presentationDt)
	end
end

function FoliageInstance.Step(
	self: FoliageInstance,
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
	if self.treeGraph ~= nil then
		self.treeGraph:Step(simulationTime, dt, windSample, lod, presentationDt)
		self.rootPosition = self.treeGraph:GetRootPosition()
		self.lastUpdateTime = simulationTime
		return
	end

	local recoverySpeed = clampNumber(self.config.recoverySpeed, 4, 0, 30)
	self.reactiveBend = Damp.value(self.reactiveBend, ZERO, recoverySpeed, dt)
	if self.reactiveBend.Magnitude <= 1e-4 then
		self.reactiveBend = ZERO
	end

	local swayAmplitude = clampNumber(self.config.swayAmplitude, 1, 0, 10)
	local gustSensitivity = clampNumber(self.config.gustSensitivity, 1, 0, 10)
	local detailAmplitude = clampNumber(self.config.detailAmplitude, 0.22, 0, 10)
	local heightMultiplier = clampNumber(self.config.heightMultiplier, 1, 0.1, 8)

	local target = (windSample.vector * swayAmplitude + windSample.direction * windSample.gustAlpha * gustSensitivity)
		* lod.windScale
	target += windSample.detailVector * detailAmplitude * lod.detailScale
	target += self.reactiveBend * lod.disturbanceScale
	target *= heightMultiplier * self.amplitudeScale
	target = Vec.FlattenY(target)

	if target.Magnitude > 1.35 then
		target = target.Unit * 1.35
	end

	local stiffness = clampNumber(self.config.bendStiffness, 12, 0.1, 200)
	local damping = clampNumber(self.config.damping, 7, 0, 100)
	local acceleration = (target - self.currentBend) * stiffness - self.springVelocity * damping
	self.springVelocity += acceleration * dt
	self.currentBend += self.springVelocity * dt

	if self.currentBend.Magnitude <= 1e-4 and self.springVelocity.Magnitude <= 1e-4 and target.Magnitude <= 1e-4 then
		self.currentBend = ZERO
		self.springVelocity = ZERO
	end

	local pitch, yaw, roll, translationWorld = self:GetLocalAngles(self.currentBend, windSample.flutter, lod)
	self:ApplyTransform(pitch, yaw, roll, translationWorld, presentationDt)
	self.lastUpdateTime = simulationTime
end

function FoliageInstance.Destroy(self: FoliageInstance)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:CancelTweens()
	if self.treeGraph ~= nil then
		self.treeGraph:Destroy()
		local janitor = self.janitor :: JanitorClass
		janitor:Destroy()
		return
	end

	if self.representation == "BasePart" then
		if self.part ~= nil and self.part.Parent ~= nil and self.restCFrame ~= nil then
			self.part.CFrame = self.restCFrame
		end
	elseif self.representation == "Model" then
		if self.model ~= nil and self.model.Parent ~= nil and self.restCFrame ~= nil then
			if self.modelTweenValue ~= nil then
				self.modelTweenValue.Value = self.restCFrame
			end
			self.model:PivotTo(self.restCFrame)
		end
	else
		for _, record in self.bones do
			if record.bone.Parent ~= nil then
				record.bone.Transform = record.restTransform
			end
		end
	end

	local janitor = self.janitor :: JanitorClass
	janitor:Destroy()
end
return FoliageInstance
