--!strict
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local BloodEngine = require(ReplicatedStorage.Packages.BloodEngine)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)
local Gib = require(script.Gib)
local LimbDestruction = require(script.LimbDestruction)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

export type LimbProfile = {
	bloodColor: Color3?,
	bloodAmount: number?,
	arcHeight: number?,
	travelTime: number?,
	restDistance: NumberRange?,
}

export type GoreConfig = {
	entity: Model?,
	model: Model?,
	parent: Instance?,
	raycastFilter: { Instance }?,
	bloodColor: Color3?,
	bloodSettings: { [string]: any }?,
	gibLifetime: number?,
	gibArcHeight: number?,
	gibTravelTime: number?,
	gibRestDistance: NumberRange?,
	bloodBurstAmount: number?,
	limbProfiles: { [string]: LimbProfile }?,
	limbDestruction: LimbDestruction.LimbDestructionConfig?,
}

export type DestroyLimbOptions = {
	bloodColor: Color3?,
	bloodAmount: number?,
	arcHeight: number?,
	travelTime: number?,
	restDistance: NumberRange?,
	restPosition: Vector3?,
	spawnGib: boolean?,
}

export type DestroyLimbResult = {
	limbName: string,
	limb: BasePart,
	gib: Gib.Gib?,
	bloodColor: Color3,
}

local Gore = {}
Gore.__index = Gore

export type Gore = typeof(setmetatable(
	{} :: {
		janitor: JanitorClass,
		random: Random,
		entityModel: Model?,
		runtimeFolder: Folder,
		raycastParams: RaycastParams,
		limbProfiles: { [string]: LimbProfile },
		bloodColor: Color3,
		bloodBurstAmount: number,
		gibLifetime: number,
		gibArcHeight: number,
		gibTravelTime: number,
		gibRestDistance: NumberRange,
		cleanupDelaySeconds: number,
		bloodEngine: any?,
		limbDestruction: LimbDestruction.LimbDestruction,
		activeGibs: { [Gib.Gib]: true },
		isDestroyed: boolean,
	},
	Gore
))

local DEFAULT_BLOOD_COLOR = Color3.fromRGB(105, 0, 0)
local DEFAULT_BLOOD_BURST_AMOUNT = 16
local DEFAULT_GIB_LIFETIME = 10
local DEFAULT_GIB_ARC_HEIGHT = 5.5
local DEFAULT_GIB_TRAVEL_TIME = 0.48
local DEFAULT_GIB_REST_DISTANCE = NumberRange.new(2.5, 6.5)
local DEFAULT_BLOOD_DECAY_DELAY_SECONDS = 15
local DEFAULT_BLOOD_DECAY_TWEEN_SECONDS = 1
local DEFAULT_CLEANUP_BUFFER_SECONDS = 0.5
local MAX_DESTROY_DRAIN_WAIT_SECONDS = 5

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

local function sanitizeColor(valueRaw: any, fallback: Color3): Color3
	if typeof(valueRaw) == "Color3" then
		return valueRaw
	end
	return fallback
end

local function sanitizeRange(valueRaw: any, fallback: NumberRange): NumberRange
	if typeof(valueRaw) == "NumberRange" then
		local minimum = math.min(valueRaw.Min, valueRaw.Max)
		local maximum = math.max(valueRaw.Min, valueRaw.Max)
		return NumberRange.new(minimum, maximum)
	end
	return fallback
end

local function getRangeMaximum(valueRaw: any, fallback: number): number
	if typeof(valueRaw) == "NumberRange" then
		return math.max(valueRaw.Min, valueRaw.Max)
	end
	return fallback
end

local function getTweenDuration(valueRaw: any, fallback: number): number
	if typeof(valueRaw) == "TweenInfo" then
		return math.max(0, valueRaw.Time)
	end
	return fallback
end

local function normalizeToken(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.lower(string.gsub(string.match(valueRaw, "^%s*(.-)%s*$") or "", "[%s_%-%.]", ""))
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function resolveEntityModel(config: GoreConfig?): Model?
	if config == nil then
		return nil
	end
	if config.model ~= nil then
		return config.model
	end
	if config.entity ~= nil then
		return config.entity
	end
	return nil
end

local function cloneDictionary(sourceRaw: any): { [string]: any }
	if typeof(sourceRaw) ~= "table" then
		return {}
	end
	local cloned = {}
	for key, value in sourceRaw do
		if typeof(key) == "string" then
			cloned[key] = value
		end
	end
	return cloned
end

local function resolveRaycastFilter(config: GoreConfig?, entityModel: Model?, runtimeFolder: Folder): { Instance }
	local filter = { runtimeFolder } :: { Instance }
	if entityModel ~= nil then
		table.insert(filter, entityModel)
	end

	if config ~= nil and typeof(config.raycastFilter) == "table" then
		for _, item in config.raycastFilter do
			if typeof(item) == "Instance" then
				table.insert(filter, item)
			end
		end
	end

	return filter
end

local function buildRaycastParams(filter: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = false
	return params
end

local function resolveCleanupDelaySeconds(
	bloodSettingsRaw: any,
	gibTravelTime: number,
	gibLifetime: number
): number
	local bloodSettings = if typeof(bloodSettingsRaw) == "table" then bloodSettingsRaw else {}
	local tweens = if typeof(bloodSettings.Tweens) == "table" then bloodSettings.Tweens else nil
	local decayDelaySeconds = getRangeMaximum(bloodSettings.DecayDelay, DEFAULT_BLOOD_DECAY_DELAY_SECONDS)
	local decayTweenSeconds =
		getTweenDuration(if tweens ~= nil then tweens.Decay else nil, DEFAULT_BLOOD_DECAY_TWEEN_SECONDS)
	local bloodCleanupSeconds = decayDelaySeconds + decayTweenSeconds + DEFAULT_CLEANUP_BUFFER_SECONDS
	local gibCleanupSeconds = gibTravelTime + gibLifetime + DEFAULT_CLEANUP_BUFFER_SECONDS

	return math.max(bloodCleanupSeconds, gibCleanupSeconds)
end

function Gore._resolveBloodColor(self: Gore, limb: BasePart, optionsRaw: any, profileRaw: LimbProfile?): Color3
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local profile = if typeof(profileRaw) == "table" then profileRaw else nil

	if typeof(options.bloodColor) == "Color3" then
		return options.bloodColor
	end
	if profile ~= nil and typeof(profile.bloodColor) == "Color3" then
		return profile.bloodColor
	end

	local limbAttribute = limb:GetAttribute("BloodColor")
	if typeof(limbAttribute) == "Color3" then
		return limbAttribute
	end

	return limb.Color
end

function Gore._resolveLimbProfile(self: Gore, limbNameRaw: any): LimbProfile?
	local token = normalizeToken(limbNameRaw)
	if token == "" then
		return nil
	end
	return self.limbProfiles[token]
end

function Gore._resolveGibRestPosition(self: Gore, originCFrame: CFrame, sourcePart: BasePart): Vector3
	local origin = originCFrame.Position
	local horizontalDirection = Vector3.new(self.random:NextNumber(-1, 1), 0, self.random:NextNumber(-1, 1))
	if horizontalDirection.Magnitude <= 1e-4 then
		horizontalDirection = Vector3.new(0, 0, 1)
	end

	if self.entityModel ~= nil then
		local entityCenter = self.entityModel:GetPivot().Position
		local outward = origin - entityCenter
		outward = Vector3.new(outward.X, 0, outward.Z)
		if outward.Magnitude > 0.1 then
			horizontalDirection = outward.Unit
		end
	end

	local distance = self.random:NextNumber(self.gibRestDistance.Min, self.gibRestDistance.Max)
	local candidate = origin + horizontalDirection.Unit * distance
	local jitter = Vector3.new(self.random:NextNumber(-0.8, 0.8), 0, self.random:NextNumber(-0.8, 0.8))
	candidate += jitter

	local castOrigin = candidate + Vector3.new(0, 40, 0)
	local castDirection = Vector3.new(0, -120, 0)
	local raycastResult = Workspace:Raycast(castOrigin, castDirection, self.raycastParams)
	if raycastResult ~= nil then
		local restY = raycastResult.Position.Y + sourcePart.Size.Y * 0.5
		return Vector3.new(candidate.X, restY, candidate.Z)
	end

	return Vector3.new(candidate.X, origin.Y, candidate.Z)
end

function Gore._trackGib(self: Gore, gib: Gib.Gib)
	self.activeGibs[gib] = true
	local timeToCleanup = self.gibTravelTime + self.gibLifetime + 1
	task.delay(timeToCleanup, function()
		if self.isDestroyed then
			return
		end
		self.activeGibs[gib] = nil
	end)
end

function Gore.new(configRaw: GoreConfig?): Gore
	local config = if typeof(configRaw) == "table" then (configRaw :: GoreConfig) else nil
	local entityModel = resolveEntityModel(config)
	local rootParent = if config ~= nil and typeof(config.parent) == "Instance"
		then config.parent
		else WorkspaceFolders.getOrCreateGameFolder()
	local rootFolder = ensureFolder(rootParent, "GoreRuntime")
	local runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = if entityModel ~= nil then ("Gore_" .. entityModel.Name) else "Gore_Entity"
	runtimeFolder.Parent = rootFolder

	local raycastFilter = resolveRaycastFilter(config, entityModel, runtimeFolder)
	local raycastParams = buildRaycastParams(raycastFilter)

	local self = setmetatable({
		janitor = Janitor.new(),
		random = Random.new(),
		entityModel = entityModel,
		runtimeFolder = runtimeFolder,
		raycastParams = raycastParams,
		limbProfiles = {} :: { [string]: LimbProfile },
		bloodColor = sanitizeColor(config and config.bloodColor, DEFAULT_BLOOD_COLOR),
		bloodBurstAmount = sanitizeNumber(config and config.bloodBurstAmount, DEFAULT_BLOOD_BURST_AMOUNT, 1, 200),
		gibLifetime = sanitizeNumber(config and config.gibLifetime, DEFAULT_GIB_LIFETIME, 0.05, 120),
		gibArcHeight = sanitizeNumber(config and config.gibArcHeight, DEFAULT_GIB_ARC_HEIGHT, 0, 200),
		gibTravelTime = sanitizeNumber(config and config.gibTravelTime, DEFAULT_GIB_TRAVEL_TIME, 0.1, 12),
		gibRestDistance = sanitizeRange(config and config.gibRestDistance, DEFAULT_GIB_REST_DISTANCE),
		cleanupDelaySeconds = 0,
		bloodEngine = nil,
		limbDestruction = LimbDestruction.new({
			model = entityModel,
			destroyedTransparency = 1,
		}),
		activeGibs = {} :: { [Gib.Gib]: true },
		isDestroyed = false,
	}, Gore)

	if config ~= nil and typeof(config.limbProfiles) == "table" then
		for limbName, profile in config.limbProfiles do
			if typeof(limbName) == "string" and typeof(profile) == "table" then
				self.limbProfiles[normalizeToken(limbName)] = profile
			end
		end
	end

	if config ~= nil and typeof(config.limbDestruction) == "table" then
		self.limbDestruction:destroy()
		local limbConfig = cloneDictionary(config.limbDestruction)
		limbConfig.model = entityModel
		self.limbDestruction = LimbDestruction.new(limbConfig)
	end

	local bloodSettings = {
		FolderName = runtimeFolder.Name .. "_Blood",
		DropletColor = self.bloodColor,
		Filter = raycastFilter,
	} :: { [string]: any }
	if config ~= nil and typeof(config.bloodSettings) == "table" then
		for key, value in config.bloodSettings do
			if typeof(key) == "string" then
				bloodSettings[key] = value
			end
		end
	end
	if typeof(bloodSettings.Filter) ~= "table" then
		bloodSettings.Filter = raycastFilter
	end
	self.cleanupDelaySeconds = resolveCleanupDelaySeconds(bloodSettings, self.gibTravelTime, self.gibLifetime)

	local ok, engineOrError = pcall(function()
		return BloodEngine(bloodSettings)
	end)
	if ok then
		self.bloodEngine = engineOrError
	else
		warn("[Gore] Failed to initialize BloodEngine: " .. tostring(engineOrError))
	end

	self.janitor:GiveChore(function()
		for gib in self.activeGibs do
			gib:destroy()
		end
		table.clear(self.activeGibs)
	end)
	self.janitor:GiveChore(function()
		self.limbDestruction:destroy()
	end)
	self.janitor:GiveChore(function()
		if self.bloodEngine ~= nil and typeof(self.bloodEngine.Destroy) == "function" then
			self.bloodEngine:Destroy()
		end
	end)
	self.janitor:GiveChore(function()
		if self.runtimeFolder.Parent ~= nil then
			self.runtimeFolder:Destroy()
		end
	end)

	return self
end

function Gore.setBloodColor(self: Gore, bloodColorRaw: any)
	local nextColor = sanitizeColor(bloodColorRaw, self.bloodColor)
	self.bloodColor = nextColor
	if self.bloodEngine ~= nil and typeof(self.bloodEngine.UpdateSettings) == "function" then
		self.bloodEngine:UpdateSettings({ DropletColor = nextColor })
	end
end

function Gore.getBloodColor(self: Gore): Color3
	return self.bloodColor
end

function Gore.emitBlood(self: Gore, originRaw: any, directionRaw: any?, amountRaw: any?, settingsRaw: any?): boolean
	if self.isDestroyed or self.bloodEngine == nil then
		return false
	end

	local origin = originRaw
	if typeof(originRaw) ~= "Vector3" and (typeof(originRaw) ~= "Instance" or not originRaw:IsA("BasePart")) then
		return false
	end

	local amount = sanitizeNumber(amountRaw, 1, 1, 200)
	local direction = if typeof(directionRaw) == "Vector3" then directionRaw else nil
	local settings = cloneDictionary(settingsRaw)
	if typeof(settings.DropletColor) ~= "Color3" then
		settings.DropletColor = self.bloodColor
	end

	if amount <= 1 then
		self.bloodEngine:Emit(origin, direction, settings)
		return true
	end

	self.bloodEngine:EmitAmount(origin, direction, amount, settings)
	return true
end

function Gore.spawnGib(self: Gore, sourceRaw: any, optionsRaw: any?): Gib.Gib?
	if self.isDestroyed then
		return nil
	end

	local sourcePart = nil :: BasePart?
	if typeof(sourceRaw) == "Instance" and sourceRaw:IsA("BasePart") then
		sourcePart = sourceRaw
	end
	if sourcePart == nil then
		return nil
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local originCFrame = if typeof(options.originCFrame) == "CFrame" then options.originCFrame else sourcePart.CFrame
	local restPosition = options.restPosition
	if typeof(restPosition) ~= "Vector3" then
		restPosition = self:_resolveGibRestPosition(originCFrame, sourcePart)
	end

	local gib = Gib.new({
		source = sourcePart,
		parent = self.runtimeFolder,
		originCFrame = originCFrame,
		restPosition = restPosition,
		raycastParams = self.raycastParams,
		arcHeight = sanitizeNumber(options.arcHeight, self.gibArcHeight, 0, 200),
		travelTime = sanitizeNumber(options.travelTime, self.gibTravelTime, 0.1, 12),
		lifetime = sanitizeNumber(options.lifetime, self.gibLifetime, 0.05, 120),
		restDistance = sanitizeRange(options.restDistance, self.gibRestDistance),
		canCollide = true,
		canTouch = false,
		canQuery = false,
		anchoredAtRest = true,
	})
	gib:play()
	self:_trackGib(gib)
	return gib
end

function Gore.destroyLimb(self: Gore, limbRaw: any, optionsRaw: DestroyLimbOptions?): DestroyLimbResult?
	if self.isDestroyed then
		return nil
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else ({} :: DestroyLimbOptions)
	local destroyResult = self.limbDestruction:destroyLimb(limbRaw, options)
	if destroyResult == nil then
		return nil
	end

	local limbProfile = self:_resolveLimbProfile(destroyResult.limbName)
	local bloodColor = self:_resolveBloodColor(destroyResult.limb, options, limbProfile)
	local bloodAmountDefault = if limbProfile ~= nil
		then sanitizeNumber(limbProfile.bloodAmount, self.bloodBurstAmount, 1, 200)
		else self.bloodBurstAmount
	local bloodAmount = sanitizeNumber(options.bloodAmount, bloodAmountDefault, 1, 200)

	self:emitBlood(destroyResult.originPosition, nil, bloodAmount, { DropletColor = bloodColor })

	local gib: Gib.Gib? = nil
	if options.spawnGib ~= false then
		local arcHeightDefault = if limbProfile ~= nil then limbProfile.arcHeight else self.gibArcHeight
		local travelTimeDefault = if limbProfile ~= nil then limbProfile.travelTime else self.gibTravelTime
		local restDistanceDefault = if limbProfile ~= nil and limbProfile.restDistance ~= nil
			then limbProfile.restDistance
			else self.gibRestDistance
		gib = self:spawnGib(destroyResult.gibSource, {
			originCFrame = destroyResult.originCFrame,
			restPosition = options.restPosition,
			arcHeight = sanitizeNumber(options.arcHeight, arcHeightDefault, 0, 200),
			travelTime = sanitizeNumber(options.travelTime, travelTimeDefault, 0.1, 12),
			restDistance = sanitizeRange(options.restDistance, restDistanceDefault),
		})
	else
		destroyResult.gibSource:Destroy()
	end

	return {
		limbName = destroyResult.limbName,
		limb = destroyResult.limb,
		gib = gib,
		bloodColor = bloodColor,
	}
end

function Gore.restoreLimb(self: Gore, limbRaw: any): boolean
	return self.limbDestruction:restoreLimb(limbRaw)
end

function Gore.restoreAllLimbs(self: Gore)
	self.limbDestruction:restoreAll()
end

function Gore._countActiveBloodDroplets(self: Gore): number
	local bloodEngine = self.bloodEngine
	if typeof(bloodEngine) ~= "table" then
		return 0
	end

	local activeEngine = (bloodEngine :: any).ActiveEngine
	if typeof(activeEngine) ~= "table" then
		return 0
	end

	local cache = activeEngine.Cache
	if typeof(cache) ~= "table" or typeof(cache.InUse) ~= "table" then
		return 0
	end

	return #cache.InUse
end

function Gore.destroy(self: Gore)
	if self.isDestroyed then
		return
	end
	self.isDestroyed = true

	local janitor = self.janitor
	local cleanupDelaySeconds = self.cleanupDelaySeconds
	task.spawn(function()
		local cleanupReadyAt = os.clock() + cleanupDelaySeconds
		local cleanupDeadlineAt = cleanupReadyAt + MAX_DESTROY_DRAIN_WAIT_SECONDS

		while os.clock() < cleanupDeadlineAt do
			if os.clock() >= cleanupReadyAt and self:_countActiveBloodDroplets() <= 0 then
				break
			end
			task.wait(0.25)
		end

		janitor:Destroy()
	end)
end

return Gore
