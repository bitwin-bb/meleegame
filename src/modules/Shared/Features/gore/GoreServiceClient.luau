--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local Workspace = game:GetService("Workspace")

local Gore = require(script:FindFirstAncestor("game").Shared.Features.gore.classes.Gore)
local GoreServiceUtils = require(script:FindFirstAncestor("game").Shared.Features.gore.GoreServiceUtils)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> any,
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local GoreServiceClient = {}
local NPC_RUNTIME_ID_ATTRIBUTE = "NpcRuntimeId"
local PLAYER_PREFIX = "player:"
local NPC_PREFIX = "npc:"

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

function GoreServiceClient.ResolveModelFromEntityId(self: GoreServiceClient, entityIdRaw: any): Model?
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

function GoreServiceClient.TryResolvePendingEntity(self: GoreServiceClient, entityIdRaw: any): Gore.Gore?
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

function GoreServiceClient.RegisterEntity(
	self: GoreServiceClient,
	entityIdRaw: any,
	modelRaw: any,
	configRaw: any
): Gore.Gore?
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end

	local config = if typeof(configRaw) == "table" then Sift.Dictionary.copy(configRaw) else ({} :: any)
	local model = if isModel(modelRaw) then modelRaw :: Model else self:resolveModelFromEntityId(entityId)
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

function GoreServiceClient.GetEntity(self: GoreServiceClient, entityIdRaw: any): Gore.Gore?
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end

	if self.controllersByEntityId[entityId] == nil then
		self:tryResolvePendingEntity(entityId)
	end
	return self.controllersByEntityId[entityId]
end

function GoreServiceClient.RemoveEntity(self: GoreServiceClient, entityIdRaw: any)
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

function GoreServiceClient.SetBloodColor(self: GoreServiceClient, entityIdRaw: any, bloodColorRaw: any): boolean
	local controller = self:getEntity(entityIdRaw)
	if controller == nil then
		return false
	end
	controller:setBloodColor(bloodColorRaw)
	return true
end

function GoreServiceClient.DestroyLimb(self: GoreServiceClient, entityIdRaw: any, limbRaw: any, optionsRaw: any): any?
	local controller = self:getEntity(entityIdRaw)
	if controller == nil then
		return nil
	end
	return controller:destroyLimb(limbRaw, optionsRaw)
end

function GoreServiceClient.EmitBlood(
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

function GoreServiceClient.SpawnGibs(
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

	local options = if typeof(optionsRaw) == "table" then optionsRaw else ({} :: any)
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

function GoreServiceClient.Init(self: GoreServiceClient)
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
		for _, controller in pairs(self.controllersByEntityId :: { [string]: Gore.Gore? }) do
			if controller ~= nil then
				controller:destroy()
			end
		end
		table.clear(self.controllersByEntityId)
		table.clear(self.pendingEntityConfigById)
	end)
	self.janitor:GiveChore(function()
		self.isDestroyed = true
	end)

	task.spawn(function()
		while not self.isDestroyed do
			for entityId in pairs(self.pendingEntityConfigById :: { [string]: { [string]: any }? }) do
				self:tryResolvePendingEntity(entityId)
			end
			task.wait(0.25)
		end
	end)

	self.networker:fire(GoreServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function GoreServiceClient.Destroy(self: GoreServiceClient)
	self.isDestroyed = true
	if self.janitor ~= nil then
		self.janitor:Destroy()
		self.janitor = nil
	end
end

GoreServiceClient.resolveModelFromEntityId = GoreServiceClient.ResolveModelFromEntityId
GoreServiceClient.tryResolvePendingEntity = GoreServiceClient.TryResolvePendingEntity
GoreServiceClient.registerEntity = GoreServiceClient.RegisterEntity
GoreServiceClient.getEntity = GoreServiceClient.GetEntity
GoreServiceClient.removeEntity = GoreServiceClient.RemoveEntity
GoreServiceClient.setBloodColor = GoreServiceClient.SetBloodColor
GoreServiceClient.destroyLimb = GoreServiceClient.DestroyLimb
GoreServiceClient.emitBlood = GoreServiceClient.EmitBlood
GoreServiceClient.spawnGibs = GoreServiceClient.SpawnGibs
GoreServiceClient.init = GoreServiceClient.Init
GoreServiceClient.destroy = GoreServiceClient.Destroy

type GoreServiceClient = typeof(GoreServiceClient) & {
	resolveModelFromEntityId: (self: GoreServiceClient, entityIdRaw: any) -> Model?,
	tryResolvePendingEntity: (self: GoreServiceClient, entityIdRaw: any) -> Gore.Gore?,
	networker: Networker.Client,
	janitor: any,
	random: Random,
	controllersByEntityId: { [string]: Gore.Gore? },
	pendingEntityConfigById: { [string]: { [string]: any }? },
	isDestroyed: boolean,
}

return GoreServiceClient :: GoreServiceClient
