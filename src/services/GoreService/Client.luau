--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GoreServiceUtils = require(script.Parent.GoreServiceUtils)
local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Gore = require(ReplicatedStorage.Shared.Classes.Gore)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)
local InstanceUtils = require(ReplicatedStorage.Shared.Modules.Platform.InstanceUtils)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local GoreServiceClient = {}
local NPC_RUNTIME_ID_ATTRIBUTE = "NpcRuntimeId"
local PLAYER_PREFIX = "player:"
local NPC_PREFIX = "npc:"
local EFFECTS_JUNK_FOLDER_NAME = "EffectsJunk"
local DEFAULT_SLIME_BLOOD_CLEANUP_BUFFER_SECONDS = 0.3
local MIN_SLIME_BLOOD_CLEANUP_SECONDS = 1
local DEFAULT_SLIME_BLOOD_EMIT_COUNT = 50
local DEFAULT_SLIME_BLOOD_FOLLOW_DURATION = 0.1
local DEFAULT_SLIME_BLOOD_DROPLET_AMOUNT = 100
local SLIME_BLOOD_EMIT_WINDOW_SECONDS = 0.1
local FALLBACK_SLIME_BLOOD_COLOR = Color3.fromRGB(39, 145, 58)

local function sanitizeEntityId(entityIdRaw: any): string?
	return GoreServiceUtils.sanitizeEntityId(entityIdRaw)
end

local function isModel(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Model")
end

local function parseEntityId(entityId: string): (string?, string?)
	local playerToken = string.match(entityId, "^" .. PLAYER_PREFIX .. "([%-]?%d+)$")
	if playerToken ~= nil then
		return "player", playerToken
	end

	local npcToken = string.match(entityId, "^" .. NPC_PREFIX .. "(.+)$")
	if npcToken ~= nil and npcToken ~= "" then
		return "npc", npcToken
	end

	return nil, nil
end

local function resolveSlimeBloodEffectTemplate(): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = if assets ~= nil then assets:FindFirstChild("Effects") else nil
	if effects ~= nil then
		local directPart = InstanceUtils.resolveFirstBasePart(effects:FindFirstChild("SlimeBlood"))
		if directPart ~= nil then
			return directPart
		end

		local nestedSlimeBlood = InstanceUtils.findDescendantBasePartByToken(effects, "SlimeBlood")
		if nestedSlimeBlood ~= nil then
			return nestedSlimeBlood
		end

		local fallbackBlood = InstanceUtils.resolveFirstBasePart(effects:FindFirstChild("Blood"))
		if fallbackBlood ~= nil then
			return fallbackBlood
		end
	end

	return InstanceUtils.findDescendantBasePartByToken(ReplicatedStorage, "SlimeBlood")
end

local function createFallbackSlimeBloodEffect(): BasePart
	local part = Instance.new("Part")
	part.Name = "SlimeBlood"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Color = FALLBACK_SLIME_BLOOD_COLOR
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FallbackSlimeBloodEmitter"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(FALLBACK_SLIME_BLOOD_COLOR)
	emitter.Lifetime = NumberRange.new(0.25, 0.9)
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Drag = 3
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = part

	return part
end

local function getOrCreateEffectsJunkFolder(): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(EFFECTS_JUNK_FOLDER_NAME)
end

local function resolveModelPivotCFrame(model: Model): CFrame?
	if model.Parent == nil then
		return nil
	end

	local ok, pivotOrError = pcall(function()
		return model:GetPivot()
	end)
	if ok and typeof(pivotOrError) == "CFrame" then
		return pivotOrError
	end
	return nil
end

function GoreServiceClient.resolveModelFromEntityId(self: GoreServiceClient, entityIdRaw: any): Model?
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end

	local kind, token = parseEntityId(entityId)
	if kind == "player" and token ~= nil then
		local userId = tonumber(token)
		if userId == nil then
			return nil
		end
		for _, player in Players:GetPlayers() do
			if player.UserId == userId then
				local character = player.Character
				if character ~= nil and character.Parent ~= nil then
					return character
				end
				return nil
			end
		end
		return nil
	end

	if kind == "npc" and token ~= nil then
		for _, descendant in Workspace:GetDescendants() do
			if not descendant:IsA("Model") then
				continue
			end
			local runtimeId = descendant:GetAttribute(NPC_RUNTIME_ID_ATTRIBUTE)
			if typeof(runtimeId) == "string" and runtimeId == token then
				return descendant
			end
		end
	end

	return nil
end

function GoreServiceClient.tryResolvePendingEntity(self: GoreServiceClient, entityIdRaw: any): Gore.Gore?
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end

	local existing = self.controllersByEntityId[entityId]
	if existing ~= nil then
		return existing
	end

	local pendingConfig = self.pendingEntityConfigById[entityId]
	if pendingConfig == nil then
		return nil
	end

	local model = self:resolveModelFromEntityId(entityId)
	if model == nil then
		return nil
	end

	return self:registerEntity(entityId, model, pendingConfig)
end

function GoreServiceClient.registerEntity(self: GoreServiceClient, entityIdRaw: any, modelRaw: any, configRaw: any): Gore.Gore?
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end

	local config = if typeof(configRaw) == "table" then Sift.Dictionary.copy(configRaw) else {}
	local model = if isModel(modelRaw) then (modelRaw :: Model) else self:resolveModelFromEntityId(entityId)
	if model == nil then
		self.pendingEntityConfigById[entityId] = config
		return nil
	end

	self:removeEntity(entityId)
	self.pendingEntityConfigById[entityId] = nil
	config.model = model
	local controller = Gore.new(config)
	self.controllersByEntityId[entityId] = controller
	return controller
end

function GoreServiceClient.getEntity(self: GoreServiceClient, entityIdRaw: any): Gore.Gore?
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end

	if self.controllersByEntityId[entityId] == nil then
		self:tryResolvePendingEntity(entityId)
	end
	return self.controllersByEntityId[entityId]
end

function GoreServiceClient.removeEntity(self: GoreServiceClient, entityIdRaw: any)
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return
	end

	local controller = self.controllersByEntityId[entityId]
	if controller == nil then
		self.pendingEntityConfigById[entityId] = nil
		return
	end

	controller:destroy()
	self.controllersByEntityId[entityId] = nil
	self.pendingEntityConfigById[entityId] = nil
end

function GoreServiceClient.setBloodColor(self: GoreServiceClient, entityIdRaw: any, bloodColorRaw: any): boolean
	local controller = self:getEntity(entityIdRaw)
	if controller == nil then
		return false
	end
	controller:setBloodColor(bloodColorRaw)
	return true
end

function GoreServiceClient.destroyLimb(self: GoreServiceClient, entityIdRaw: any, limbRaw: any, optionsRaw: any): any?
	local controller = self:getEntity(entityIdRaw)
	if controller == nil then
		return nil
	end
	return controller:destroyLimb(limbRaw, optionsRaw)
end

function GoreServiceClient.emitBlood(
	self: GoreServiceClient,
	entityIdRaw: any,
	originRaw: any,
	directionRaw: any?,
	amountRaw: any?,
	settingsRaw: any?
): boolean
	local controller = self:getEntity(entityIdRaw)
	if controller == nil then
		return false
	end
	return controller:emitBlood(originRaw, directionRaw, amountRaw, settingsRaw)
end

function GoreServiceClient.emitSlimeBlood(
	self: GoreServiceClient,
	entityIdRaw: any,
	originRaw: any,
	emitCountRaw: any?,
	followDurationRaw: any?,
	dropletAmountRaw: any?
): boolean
	local model = self:resolveModelFromEntityId(entityIdRaw)
	if model == nil then
		local controller = self:getEntity(entityIdRaw)
		if controller ~= nil then
			model = controller.entityModel
		end
	end

	local template = resolveSlimeBloodEffectTemplate()
	local bloodEffect =
		(if template ~= nil then template:Clone() else createFallbackSlimeBloodEffect()) :: BasePart
	bloodEffect.Name = "SlimeBlood"
	bloodEffect.Anchored = true
	bloodEffect.CanCollide = false
	bloodEffect.CanTouch = false
	bloodEffect.CanQuery = false
	bloodEffect.Parent = getOrCreateEffectsJunkFolder()

	local initialPosition: Vector3? = nil
	if typeof(originRaw) == "Vector3" then
		initialPosition = originRaw
	elseif typeof(originRaw) == "Instance" and originRaw:IsA("BasePart") then
		initialPosition = originRaw.Position
	end
	if initialPosition == nil and model ~= nil then
		local sourcePart = GoreServiceUtils.resolveOriginPart(model, originRaw)
		if sourcePart ~= nil then
			initialPosition = sourcePart.Position
		else
			local pivot = resolveModelPivotCFrame(model)
			if pivot ~= nil then
				initialPosition = pivot.Position
			end
		end
	end
	if initialPosition == nil then
		bloodEffect:Destroy()
		return false
	end
	bloodEffect.CFrame = CFrame.new(initialPosition)

	local emitCount = GoreServiceUtils.sanitizeBloodAmount(emitCountRaw, DEFAULT_SLIME_BLOOD_EMIT_COUNT)
	local followDuration =
		GoreServiceUtils.sanitizeEffectDuration(followDurationRaw, DEFAULT_SLIME_BLOOD_FOLLOW_DURATION)
	followDuration = math.min(followDuration, SLIME_BLOOD_EMIT_WINDOW_SECONDS)
	local dropletAmount = GoreServiceUtils.sanitizeBloodAmount(dropletAmountRaw, DEFAULT_SLIME_BLOOD_DROPLET_AMOUNT)
	local maxEmitterLifetime = 0
	local emitted = false
	local effectEmitters = {} :: { ParticleEmitter }
	for _, descendant in bloodEffect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local lifetime = descendant.Lifetime
			local clampedLifetimeMax = math.max(0, lifetime.Min, lifetime.Max)
			descendant.Enabled = true
			descendant:Emit(emitCount)
			maxEmitterLifetime = math.max(maxEmitterLifetime, clampedLifetimeMax)
			emitted = true
			table.insert(effectEmitters, descendant)
		end
	end

	if not emitted then
		bloodEffect:Destroy()
		return false
	end

	local controller = self:getEntity(entityIdRaw)
	if controller ~= nil then
		controller:emitBlood(initialPosition, nil, dropletAmount, nil)
	end

	local startedAt = os.clock()
	local trackedModel = model
	local followConnection: RBXScriptConnection? = nil
	followConnection = RunService.Heartbeat:Connect(function()
		if bloodEffect.Parent == nil then
			if followConnection ~= nil then
				followConnection:Disconnect()
				followConnection = nil
			end
			return
		end

		if os.clock() - startedAt >= followDuration then
			if followConnection ~= nil then
				followConnection:Disconnect()
				followConnection = nil
			end
			return
		end

		if trackedModel == nil then
			trackedModel = self:resolveModelFromEntityId(entityIdRaw)
			if trackedModel == nil then
				local controller = self:getEntity(entityIdRaw)
				if controller ~= nil then
					trackedModel = controller.entityModel
				end
			end
		end

		if trackedModel ~= nil then
			local followPart = GoreServiceUtils.resolveOriginPart(trackedModel, nil)
			if followPart ~= nil then
				bloodEffect.CFrame = followPart.CFrame
				return
			end

			local pivot = resolveModelPivotCFrame(trackedModel)
			if pivot ~= nil then
				bloodEffect.CFrame = pivot
			end
		end
	end)

	task.delay(SLIME_BLOOD_EMIT_WINDOW_SECONDS, function()
		if followConnection ~= nil then
			followConnection:Disconnect()
			followConnection = nil
		end
		for _, emitter in effectEmitters do
			if emitter.Parent ~= nil then
				emitter.Enabled = false
			end
		end
	end)

	local cleanupDelay = math.max(
		MIN_SLIME_BLOOD_CLEANUP_SECONDS,
		SLIME_BLOOD_EMIT_WINDOW_SECONDS + maxEmitterLifetime + DEFAULT_SLIME_BLOOD_CLEANUP_BUFFER_SECONDS
	)
	task.delay(cleanupDelay, function()
		if bloodEffect.Parent ~= nil then
			bloodEffect:Destroy()
		end
	end)

	return true
end

function GoreServiceClient.spawnGibs(
	self: GoreServiceClient,
	entityIdRaw: any,
	gibCountRaw: any,
	sourceRaw: any?,
	optionsRaw: any?
): number
	local controller = self:getEntity(entityIdRaw)
	if controller == nil then
		return 0
	end

	local gibCount = GoreServiceUtils.sanitizeGibCount(gibCountRaw, 0)
	if gibCount <= 0 then
		return 0
	end

	local sourcePart = if typeof(sourceRaw) == "Instance" and sourceRaw:IsA("BasePart") then sourceRaw else nil
	local model = controller.entityModel
	local eligibleParts = {} :: { BasePart }
	if model ~= nil and model.Parent ~= nil then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(eligibleParts, descendant)
			end
		end
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local spawned = 0
	for index = 1, gibCount do
		local part = sourcePart
		if part == nil and #eligibleParts > 0 then
			part = eligibleParts[self.random:NextInteger(1, #eligibleParts)]
		end
		if part == nil then
			break
		end

		local originCFrame = part.CFrame
		if index == 1 and sourcePart ~= nil then
			originCFrame = sourcePart.CFrame
		end

		local gib = controller:spawnGib(part, {
			originCFrame = originCFrame,
			arcHeight = options.arcHeight,
			travelTime = options.travelTime,
			restDistance = options.restDistance,
		})
		if gib ~= nil then
			spawned += 1
		end
	end

	return spawned
end

function GoreServiceClient.init(self: GoreServiceClient)
	if self.janitor ~= nil then
		return
	end
	self.networker = Networker.client.new("GoreService", self)
	self.janitor = Janitor.new()
	self.random = Random.new()
	self.controllersByEntityId = {} :: { [string]: Gore.Gore }
	self.pendingEntityConfigById = {} :: { [string]: { [string]: any } }
	self.isDestroyed = false

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		for _, controller in self.controllersByEntityId do
			controller:destroy()
		end
		table.clear(self.controllersByEntityId)
		table.clear(self.pendingEntityConfigById)
	end)
	self.janitor:GiveChore(function()
		self.isDestroyed = true
	end)

	task.spawn(function()
		while not self.isDestroyed do
			for entityId in self.pendingEntityConfigById do
				self:tryResolvePendingEntity(entityId)
			end
			task.wait(0.25)
		end
	end)

	self.networker:fire(GoreServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function GoreServiceClient.destroy(self: GoreServiceClient)
	self.isDestroyed = true
	if self.janitor ~= nil then
		self.janitor:Destroy()
		self.janitor = nil
	end
end

type GoreServiceClient = typeof(GoreServiceClient) & {
	resolveModelFromEntityId: (self: GoreServiceClient, entityIdRaw: any) -> Model?,
	tryResolvePendingEntity: (self: GoreServiceClient, entityIdRaw: any) -> Gore.Gore?,
	networker: Networker.Client,
	janitor: JanitorClass,
	random: Random,
	controllersByEntityId: { [string]: Gore.Gore },
	pendingEntityConfigById: { [string]: { [string]: any } },
	isDestroyed: boolean,
}

return GoreServiceClient :: GoreServiceClient
