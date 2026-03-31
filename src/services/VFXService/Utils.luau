--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)

local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)

local VFXServiceUtils = {}

export type VFXTemplateKind = "Part" | "Attachment"

export type VFXPlaybackOptions = {
	target: Instance?,
	followInstance: Instance?,
	parent: Instance?,
	position: Vector3?,
	cframe: CFrame?,
	offset: CFrame,
	emitCount: number?,
	enabledDuration: number,
	followDuration: number,
	cleanupDelay: number?,
	channel: string?,
	replaceChannel: boolean,
}

VFXServiceUtils.NETWORK_METHOD_PLAY = "play"
VFXServiceUtils.NETWORK_METHOD_STOP_CHANNEL = "stopChannel"
VFXServiceUtils.NETWORK_METHOD_STOP_ALL = "stopAll"
VFXServiceUtils.RUNTIME_FOLDER_NAME = "VFXRuntime"
VFXServiceUtils.DEFAULT_ENABLED_DURATION = 0.1
VFXServiceUtils.DEFAULT_CLEANUP_BUFFER = 0.2
VFXServiceUtils.MIN_CLEANUP_DELAY = 0.35
VFXServiceUtils.MAX_DURATION = 60
VFXServiceUtils.MAX_EMIT_COUNT = 512

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function token(valueRaw: any): string
	local value = string.lower(trim(valueRaw))
	if value == "" then
		return ""
	end
	return string.gsub(value, "[%s_%-%.]+", "")
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeIntegerOrNil(valueRaw: any, minimum: number, maximum: number): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	local rounded = math.floor(math.clamp(valueRaw, minimum, maximum) + 0.5)
	if rounded <= 0 then
		return nil
	end
	return rounded
end

local function asInstance(valueRaw: any): Instance?
	if typeof(valueRaw) == "Instance" then
		return valueRaw
	end
	return nil
end

local function splitPathSegments(pathRaw: string): { string }
	local segments = {}
	if string.find(pathRaw, "[/\\]") == nil then
		return segments
	end

	for segment in string.gmatch(pathRaw, "[^/\\]+") do
		if segment ~= "" then
			table.insert(segments, segment)
		end
	end
	return segments
end

local function resolveEffectsRoot(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets == nil then
		return nil
	end

	local effects = assets:FindFirstChild("Effects")
	if effects ~= nil then
		return effects
	end
	return nil
end

local function resolveDescendantByPath(root: Instance?, pathRaw: string): Instance?
	local segments = splitPathSegments(pathRaw)
	if root == nil or #segments <= 0 then
		return nil
	end

	local cursor: Instance? = root
	for _, segment in segments do
		if cursor == nil then
			return nil
		end
		cursor = cursor:FindFirstChild(segment)
	end

	return cursor
end

local function setBasePartRuntimeProperties(basePart: BasePart, hideVisual: boolean)
	basePart.Anchored = true
	basePart.CanCollide = false
	basePart.CanTouch = false
	basePart.CanQuery = false
	basePart.CastShadow = false
	basePart.Massless = true
	if hideVisual then
		basePart.Transparency = 1
	end
end

local function setAuxiliaryVisualHidden(instance: Instance)
	if instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = 1
	end
end

local function getParticleEmitterLifetimeMax(emitter: ParticleEmitter): number
	local lifetime = emitter.Lifetime
	return math.max(0, lifetime.Min, lifetime.Max)
end

function VFXServiceUtils.cloneDictionary(sourceRaw: any): { [string]: any }
	local source = if typeof(sourceRaw) == "table" then sourceRaw else {}
	return Sift.Dictionary.copy(source)
end

function VFXServiceUtils.getTemplateKind(templateRaw: any): VFXTemplateKind?
	local template = asInstance(templateRaw)
	if template == nil then
		return nil
	end
	if template:IsA("BasePart") then
		return "Part"
	end
	if template:IsA("Attachment") then
		return "Attachment"
	end
	return nil
end

function VFXServiceUtils.isPartTemplate(templateRaw: any): boolean
	return VFXServiceUtils.getTemplateKind(templateRaw) == "Part"
end

function VFXServiceUtils.isAttachmentTemplate(templateRaw: any): boolean
	return VFXServiceUtils.getTemplateKind(templateRaw) == "Attachment"
end

function VFXServiceUtils.sanitizeChannelName(channelNameRaw: any): string?
	local channelName = trim(channelNameRaw)
	if channelName == "" then
		return nil
	end
	return channelName
end

function VFXServiceUtils.sanitizeEffectReference(effectSourceRaw: any): any?
	local templateKind = VFXServiceUtils.getTemplateKind(effectSourceRaw)
	if templateKind ~= nil then
		local template = effectSourceRaw :: Instance
		if template.Parent ~= nil then
			return template
		end
		return nil
	end

	local effectName = trim(effectSourceRaw)
	if effectName ~= "" then
		return effectName
	end
	return nil
end

function VFXServiceUtils.resolveEffectTemplate(effectSourceRaw: any): Instance?
	local templateKind = VFXServiceUtils.getTemplateKind(effectSourceRaw)
	if templateKind ~= nil then
		return effectSourceRaw :: Instance
	end

	local effectName = trim(effectSourceRaw)
	if effectName == "" then
		return nil
	end

	local effectsRoot = resolveEffectsRoot()
	if effectsRoot == nil then
		return nil
	end

	local byPath = resolveDescendantByPath(effectsRoot, effectName)
	if VFXServiceUtils.getTemplateKind(byPath) ~= nil then
		return byPath
	end

	local exact = effectsRoot:FindFirstChild(effectName, true)
	if VFXServiceUtils.getTemplateKind(exact) ~= nil then
		return exact
	end

	local targetToken = token(effectName)
	if targetToken == "" then
		return nil
	end

	for _, descendant in effectsRoot:GetDescendants() do
		if VFXServiceUtils.getTemplateKind(descendant) ~= nil and token(descendant.Name) == targetToken then
			return descendant
		end
	end

	return nil
end

function VFXServiceUtils.sanitizePlaybackOptions(optionsRaw: any): VFXPlaybackOptions
	local source = if typeof(optionsRaw) == "table" then optionsRaw else {}

	local offsetRaw = (source :: any).offset
	if offsetRaw == nil then
		offsetRaw = (source :: any).cframeOffset
	end
	if offsetRaw == nil then
		offsetRaw = (source :: any).positionOffset
	end
	local offset = if typeof(offsetRaw) == "CFrame"
		then offsetRaw
		else if typeof(offsetRaw) == "Vector3" then CFrame.new(offsetRaw) else CFrame.new()

	local target = asInstance((source :: any).target)
	if target == nil then
		target = asInstance((source :: any).at)
	end
	if target == nil then
		target = asInstance((source :: any).origin)
	end

	local followInstance = asInstance((source :: any).followInstance)
	local followRequested = if typeof((source :: any).follow) == "boolean"
		then (source :: any).follow
		else followInstance ~= nil
	if followRequested and followInstance == nil then
		followInstance = target
	end

	local enabledDuration = sanitizeNumber(
		if (source :: any).enabledDuration ~= nil
			then (source :: any).enabledDuration
			else if (source :: any).duration ~= nil then (source :: any).duration else (source :: any).emitWindow,
		VFXServiceUtils.DEFAULT_ENABLED_DURATION,
		0,
		VFXServiceUtils.MAX_DURATION
	)
	local followDuration = sanitizeNumber(
		(source :: any).followDuration,
		enabledDuration,
		0,
		VFXServiceUtils.MAX_DURATION
	)

	local cleanupDelayRaw = (source :: any).cleanupDelay
	if cleanupDelayRaw == nil then
		cleanupDelayRaw = (source :: any).lifetime
	end
	local cleanupDelay = if typeof(cleanupDelayRaw) == "number" and cleanupDelayRaw == cleanupDelayRaw
		then math.clamp(cleanupDelayRaw, 0, VFXServiceUtils.MAX_DURATION)
		else nil

	local parent = asInstance((source :: any).parent)
	if parent ~= nil and parent.Parent == nil then
		parent = nil
	end

	local position = if typeof((source :: any).position) == "Vector3"
		then (source :: any).position
		else if typeof((source :: any).worldPosition) == "Vector3" then (source :: any).worldPosition else nil
	local cframe = if typeof((source :: any).cframe) == "CFrame"
		then (source :: any).cframe
		else if typeof((source :: any).worldCFrame) == "CFrame" then (source :: any).worldCFrame else nil

	return {
		target = target,
		followInstance = followInstance,
		parent = parent,
		position = position,
		cframe = cframe,
		offset = offset,
		emitCount = sanitizeIntegerOrNil((source :: any).emitCount, 1, VFXServiceUtils.MAX_EMIT_COUNT),
		enabledDuration = enabledDuration,
		followDuration = if followInstance ~= nil then followDuration else 0,
		cleanupDelay = cleanupDelay,
		channel = VFXServiceUtils.sanitizeChannelName((source :: any).channel),
		replaceChannel = if typeof((source :: any).replaceChannel) == "boolean"
			then (source :: any).replaceChannel
			else true,
	}
end

function VFXServiceUtils.serializePlaybackOptions(optionsRaw: any): { [string]: any }
	local options = VFXServiceUtils.sanitizePlaybackOptions(optionsRaw)
	local serialized = {}

	if options.target ~= nil and options.target.Parent ~= nil then
		serialized.target = options.target
	end
	if options.followInstance ~= nil and options.followInstance.Parent ~= nil then
		serialized.followInstance = options.followInstance
	end
	if options.parent ~= nil and options.parent.Parent ~= nil then
		serialized.parent = options.parent
	end
	if options.position ~= nil then
		serialized.position = options.position
	end
	if options.cframe ~= nil then
		serialized.cframe = options.cframe
	end
	if options.offset ~= CFrame.new() then
		serialized.offset = options.offset
	end
	if options.emitCount ~= nil then
		serialized.emitCount = options.emitCount
	end
	if options.enabledDuration ~= VFXServiceUtils.DEFAULT_ENABLED_DURATION then
		serialized.enabledDuration = options.enabledDuration
	end
	if options.followDuration > 0 then
		serialized.followDuration = options.followDuration
	end
	if options.cleanupDelay ~= nil then
		serialized.cleanupDelay = options.cleanupDelay
	end
	if options.channel ~= nil then
		serialized.channel = options.channel
	end
	if options.replaceChannel == false then
		serialized.replaceChannel = false
	end

	return serialized
end

function VFXServiceUtils.resolveInstanceWorldCFrame(instanceRaw: any): CFrame?
	local instance = asInstance(instanceRaw)
	if instance == nil then
		return nil
	end
	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	if instance:IsA("Model") then
		local ok, pivotOrError = pcall(function()
			return instance:GetPivot()
		end)
		if ok and typeof(pivotOrError) == "CFrame" then
			return pivotOrError
		end
	end
	return nil
end

function VFXServiceUtils.resolvePlaybackCFrame(optionsRaw: any): CFrame?
	local options = VFXServiceUtils.sanitizePlaybackOptions(optionsRaw)
	local baseCFrame = options.cframe
	if baseCFrame == nil and options.position ~= nil then
		baseCFrame = CFrame.new(options.position)
	end
	if baseCFrame == nil then
		baseCFrame = VFXServiceUtils.resolveInstanceWorldCFrame(options.target)
	end
	if baseCFrame == nil then
		baseCFrame = VFXServiceUtils.resolveInstanceWorldCFrame(options.followInstance)
	end
	if baseCFrame == nil then
		return nil
	end
	return baseCFrame * options.offset
end

function VFXServiceUtils.resolveFollowCFrame(optionsRaw: any): CFrame?
	local options = VFXServiceUtils.sanitizePlaybackOptions(optionsRaw)
	if options.followInstance == nil then
		return nil
	end
	local followCFrame = VFXServiceUtils.resolveInstanceWorldCFrame(options.followInstance)
	if followCFrame == nil then
		return nil
	end
	return followCFrame * options.offset
end

function VFXServiceUtils.ensureRuntimeFolder(): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(VFXServiceUtils.RUNTIME_FOLDER_NAME)
end

function VFXServiceUtils.createRuntimeCarrier(effectNameRaw: any): Part
	local carrier = Instance.new("Part")
	carrier.Name = if trim(effectNameRaw) ~= "" then trim(effectNameRaw) .. "_Carrier" else "VFXCarrier"
	carrier.Size = Vector3.new(0.2, 0.2, 0.2)
	carrier.Transparency = 1
	carrier.Material = Enum.Material.SmoothPlastic
	carrier.Anchored = true
	carrier.Locked = true
	carrier.CanCollide = false
	carrier.CanTouch = false
	carrier.CanQuery = false
	carrier.CastShadow = false
	return carrier
end

function VFXServiceUtils.prepareRuntimeRoot(root: BasePart, hideVisual: boolean)
	setBasePartRuntimeProperties(root, hideVisual)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			setBasePartRuntimeProperties(descendant, hideVisual)
		else
			setAuxiliaryVisualHidden(descendant)
		end
	end
end

function VFXServiceUtils.createRuntimeEffect(effectTemplateRaw: any, runtimeParentRaw: any): BasePart?
	local template = asInstance(effectTemplateRaw)
	local runtimeParent = asInstance(runtimeParentRaw)
	if template == nil or runtimeParent == nil then
		return nil
	end

	local templateKind = VFXServiceUtils.getTemplateKind(template)
	if templateKind == "Part" then
		local partClone = template:Clone() :: BasePart
		VFXServiceUtils.prepareRuntimeRoot(partClone, false)
		partClone.Parent = runtimeParent
		return partClone
	end

	if templateKind == "Attachment" then
		local templateParent = template.Parent
		if templateParent ~= nil and templateParent:IsA("BasePart") then
			local carrierClone = templateParent:Clone() :: BasePart
			carrierClone.Name = template.Name .. "_Carrier"
			VFXServiceUtils.prepareRuntimeRoot(carrierClone, true)
			carrierClone.Parent = runtimeParent
			return carrierClone
		end

		local runtimeCarrier = VFXServiceUtils.createRuntimeCarrier(template.Name)
		local attachmentClone = template:Clone()
		attachmentClone.Parent = runtimeCarrier
		runtimeCarrier.Parent = runtimeParent
		return runtimeCarrier
	end

	return nil
end

function VFXServiceUtils.setRuntimeEffectEnabled(runtimeRootRaw: any, enabled: boolean)
	local runtimeRoot = asInstance(runtimeRootRaw)
	if runtimeRoot == nil then
		return
	end

	for _, descendant in runtimeRoot:GetDescendants() do
		if descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Smoke")
			or descendant:IsA("Fire")
			or descendant:IsA("Sparkles")
			or descendant:IsA("PointLight")
			or descendant:IsA("SpotLight")
			or descendant:IsA("SurfaceLight")
		then
			(descendant :: any).Enabled = enabled
		end
	end
end

function VFXServiceUtils.emitRuntimeParticles(runtimeRootRaw: any, emitCountRaw: any)
	local runtimeRoot = asInstance(runtimeRootRaw)
	if runtimeRoot == nil then
		return
	end

	local emitCount = sanitizeIntegerOrNil(emitCountRaw, 1, VFXServiceUtils.MAX_EMIT_COUNT)
	if emitCount == nil then
		return
	end

	for _, descendant in runtimeRoot:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(emitCount)
		end
	end
end

function VFXServiceUtils.getMaxEffectLifetime(runtimeRootRaw: any): number
	local runtimeRoot = asInstance(runtimeRootRaw)
	if runtimeRoot == nil then
		return 0
	end

	local maxLifetime = 0
	for _, descendant in runtimeRoot:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			maxLifetime = math.max(maxLifetime, getParticleEmitterLifetimeMax(descendant))
		elseif descendant:IsA("Trail") then
			maxLifetime = math.max(maxLifetime, math.max(0, descendant.Lifetime))
		end
	end
	return maxLifetime
end

function VFXServiceUtils.resolveCleanupDelay(runtimeRootRaw: any, optionsRaw: any): number
	local options = VFXServiceUtils.sanitizePlaybackOptions(optionsRaw)
	if options.cleanupDelay ~= nil then
		return math.max(0, options.cleanupDelay)
	end

	local lifetime = VFXServiceUtils.getMaxEffectLifetime(runtimeRootRaw)
	local cleanupDelay = options.enabledDuration + lifetime + VFXServiceUtils.DEFAULT_CLEANUP_BUFFER
	return math.max(VFXServiceUtils.MIN_CLEANUP_DELAY, cleanupDelay)
end

return VFXServiceUtils
