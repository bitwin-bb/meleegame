--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ServerBinderSupport = require(script:FindFirstAncestor("game").Server.Binders.ServerBinderSupport)
local GoreServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.GoreService.GoreServiceUtils)

local GoreServiceServer = {}
local SHARED_LARGE_BLOOD_POOL_SIZE = NumberRange.new(0.95, 1.7)
local SHARED_LARGE_BLOOD_POOL_SIZE_Y = NumberRange.new(0.16, 0.28)
local SHARED_LARGE_BLOOD_POOL_STARTING_SIZE = Vector3.new(0.2, 0.42, 0.2)
local SHARED_LARGE_BLOOD_POOL_MAX_SIZE = 1.8
local SHARED_LARGE_BLOOD_POOL_EXPANSE_DIVIDER = 2
local DEFAULT_SLIME_BLOOD_EMIT_COUNT = 22
local DEFAULT_SLIME_BLOOD_FOLLOW_DURATION = 0.1
local DEFAULT_SLIME_BLOOD_DROPLET_AMOUNT = 8

type EntityRuntime = {
	entityId: string,
	model: Model,
	bloodColor: Color3,
	damageBloodAmount: number,
	deathBloodAmount: number,
	deathGibCount: number,
	emitDeathGibs: boolean,
	controllerConfig: { [string]: any },
}

local function sanitizeEntityId(entityIdRaw: any): string?
	return GoreServiceUtils.sanitizeEntityId(entityIdRaw)
end

local function cloneDictionary(sourceRaw: any): { [string]: any }
	return GoreServiceUtils.cloneDictionary(sourceRaw)
end

local function isModel(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Model")
end

local function buildRuntimeFromConfig(entityId: string, model: Model, configRaw: any): EntityRuntime
	local source = if typeof(configRaw) == "table" then configRaw else {}
	local isPlayerEntity = GoreServiceUtils.sanitizeBoolean((source :: any).isPlayerEntity, false)

	local defaultBloodColor = if isPlayerEntity
		then GoreServiceUtils.DEFAULT_PLAYER_BLOOD_COLOR
		else GoreServiceUtils.DEFAULT_NPC_BLOOD_COLOR
	local defaultDamageBloodAmount = if isPlayerEntity
		then GoreServiceUtils.DEFAULT_PLAYER_DAMAGE_BLOOD_AMOUNT
		else GoreServiceUtils.DEFAULT_NPC_DAMAGE_BLOOD_AMOUNT
	local defaultDeathBloodAmount = if isPlayerEntity
		then GoreServiceUtils.DEFAULT_PLAYER_DEATH_BLOOD_AMOUNT
		else GoreServiceUtils.DEFAULT_NPC_DEATH_BLOOD_AMOUNT
	local defaultDeathGibCount = if isPlayerEntity then 0 else GoreServiceUtils.DEFAULT_NPC_DEATH_GIB_COUNT
	local defaultEmitDeathGibs = not isPlayerEntity

	local bloodColor = GoreServiceUtils.sanitizeColor((source :: any).bloodColor, defaultBloodColor)
	local damageBloodAmount = GoreServiceUtils.sanitizeBloodAmount(
		(source :: any).damageBloodAmount,
		defaultDamageBloodAmount
	)
	local deathBloodAmount = GoreServiceUtils.sanitizeBloodAmount((source :: any).deathBloodAmount, defaultDeathBloodAmount)
	local deathGibCount = GoreServiceUtils.sanitizeGibCount((source :: any).deathGibCount, defaultDeathGibCount)
	local emitDeathGibs = GoreServiceUtils.sanitizeBoolean((source :: any).emitDeathGibs, defaultEmitDeathGibs)

	local controllerConfig = cloneDictionary(source)
	controllerConfig.isPlayerEntity = nil
	controllerConfig.damageBloodAmount = nil
	controllerConfig.deathBloodAmount = nil
	controllerConfig.deathGibCount = nil
	controllerConfig.emitDeathGibs = nil
	controllerConfig.model = nil
	controllerConfig.bloodColor = bloodColor

	return {
		entityId = entityId,
		model = model,
		bloodColor = bloodColor,
		damageBloodAmount = damageBloodAmount,
		deathBloodAmount = deathBloodAmount,
		deathGibCount = deathGibCount,
		emitDeathGibs = emitDeathGibs and deathGibCount > 0,
		controllerConfig = controllerConfig,
	}
end

function GoreServiceServer.FireClient(self: GoreServiceServer, player: Player, methodName: string, ...: any)
	if self.networker == nil then
		return
	end
	self.networker:fire(player, methodName, ...)
end

function GoreServiceServer.Broadcast(self: GoreServiceServer, methodName: string, ...: any)
	for _, player in Players:GetPlayers() do
		self:fireClient(player, methodName, ...)
	end
end

function GoreServiceServer.PushEntityToPlayer(self: GoreServiceServer, player: Player, runtime: EntityRuntime)
	if runtime.model.Parent == nil then
		return
	end
	self:fireClient(
		player,
		GoreServiceUtils.NETWORK_METHOD_REGISTER_ENTITY,
		runtime.entityId,
		runtime.model,
		runtime.controllerConfig
	)
end

function GoreServiceServer.RequestSync(self: GoreServiceServer, player: Player)
	if self.entitiesById == nil then
		return
	end
	for _, runtime in self.entitiesById do
		self:pushEntityToPlayer(player, runtime)
	end
end

function GoreServiceServer.GetEntityRuntime(self: GoreServiceServer, entityIdRaw: any): EntityRuntime?
	if self.entitiesById == nil then
		return nil
	end
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end
	return self.entitiesById[entityId]
end

function GoreServiceServer.RegisterEntity(self: GoreServiceServer, entityIdRaw: any, modelRaw: any, configRaw: any?): boolean
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return false
	end
	if not isModel(modelRaw) then
		return false
	end

	if self.entitiesById == nil then
		self.entitiesById = {}
	end

	local model = modelRaw :: Model
	local runtime = buildRuntimeFromConfig(entityId, model, configRaw)
	self.entitiesById[entityId] = runtime
	self:broadcast(
		GoreServiceUtils.NETWORK_METHOD_REGISTER_ENTITY,
		runtime.entityId,
		runtime.model,
		runtime.controllerConfig
	)
	return true
end

function GoreServiceServer.UnregisterEntity(self: GoreServiceServer, entityIdRaw: any): boolean
	local entityId = sanitizeEntityId(entityIdRaw)
	if entityId == nil then
		return false
	end
	if self.entitiesById[entityId] == nil then
		return false
	end

	self.entitiesById[entityId] = nil
	self:broadcast(GoreServiceUtils.NETWORK_METHOD_REMOVE_ENTITY, entityId)
	return true
end

function GoreServiceServer.SetEntityBloodColor(self: GoreServiceServer, entityIdRaw: any, bloodColorRaw: any): boolean
	local runtime = self:getEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local bloodColor = GoreServiceUtils.sanitizeColor(bloodColorRaw, runtime.bloodColor)
	runtime.bloodColor = bloodColor
	runtime.controllerConfig.bloodColor = bloodColor
	self:broadcast(GoreServiceUtils.NETWORK_METHOD_SET_BLOOD_COLOR, runtime.entityId, bloodColor)
	return true
end

function GoreServiceServer.EmitEntityBlood(
	self: GoreServiceServer,
	entityIdRaw: any,
	originRaw: any,
	amountRaw: any?,
	settingsRaw: any?
): boolean
	local runtime = self:getEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local origin = GoreServiceUtils.resolveBloodOrigin(runtime.model, originRaw)
	if origin == nil then
		return false
	end

	local amount = GoreServiceUtils.sanitizeBloodAmount(amountRaw, runtime.damageBloodAmount)
	local settings = cloneDictionary(settingsRaw)
	if typeof(settings.DropletColor) ~= "Color3" then
		settings.DropletColor = runtime.bloodColor
	end

	self:broadcast(
		GoreServiceUtils.NETWORK_METHOD_EMIT_BLOOD,
		runtime.entityId,
		origin,
		nil,
		amount,
		settings
	)
	return true
end

function GoreServiceServer.EmitEntityDamage(
	self: GoreServiceServer,
	entityIdRaw: any,
	originRaw: any,
	damageRaw: any?
): boolean
	local runtime = self:getEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local damageAmount = if typeof(damageRaw) == "number" and damageRaw == damageRaw then math.max(0, damageRaw) else 0
	local scaledAmount = if damageAmount > 0 then runtime.damageBloodAmount + math.floor(damageAmount * 0.25 + 0.5) else runtime.damageBloodAmount
	return self:emitEntityBlood(entityIdRaw, originRaw, scaledAmount, nil)
end

function GoreServiceServer.EmitEntityDeath(self: GoreServiceServer, entityIdRaw: any, originRaw: any): boolean
	local runtime = self:getEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local didEmitBlood = self:emitEntityBlood(runtime.entityId, originRaw, runtime.deathBloodAmount, nil)
	if runtime.emitDeathGibs then
		local sourcePart = GoreServiceUtils.resolveOriginPart(runtime.model, originRaw)
		self:broadcast(
			GoreServiceUtils.NETWORK_METHOD_SPAWN_GIBS,
			runtime.entityId,
			runtime.deathGibCount,
			sourcePart,
			nil
		)
	end
	return didEmitBlood
end

function GoreServiceServer.RegisterPlayerCharacter(
	self: GoreServiceServer,
	playerRaw: any,
	characterRaw: any
): boolean
	local entityId = GoreServiceUtils.makePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	if not isModel(characterRaw) then
		return false
	end

	return self:registerEntity(entityId, characterRaw, {
		isPlayerEntity = true,
		bloodColor = GoreServiceUtils.DEFAULT_PLAYER_BLOOD_COLOR,
		damageBloodAmount = GoreServiceUtils.DEFAULT_PLAYER_DAMAGE_BLOOD_AMOUNT,
		deathBloodAmount = GoreServiceUtils.DEFAULT_PLAYER_DEATH_BLOOD_AMOUNT,
		deathGibCount = 0,
		emitDeathGibs = false,
		bloodSettings = {
			DefaultSize = SHARED_LARGE_BLOOD_POOL_SIZE,
			SizeY = SHARED_LARGE_BLOOD_POOL_SIZE_Y,
			StartingSize = SHARED_LARGE_BLOOD_POOL_STARTING_SIZE,
			MaximumSize = SHARED_LARGE_BLOOD_POOL_MAX_SIZE,
			ExpanseDivider = SHARED_LARGE_BLOOD_POOL_EXPANSE_DIVIDER,
		},
	})
end

function GoreServiceServer.UnregisterPlayer(self: GoreServiceServer, playerRaw: any): boolean
	local entityId = GoreServiceUtils.makePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	return self:unregisterEntity(entityId)
end

function GoreServiceServer.OnPlayerDamaged(self: GoreServiceServer, playerRaw: any, originRaw: any, damageRaw: any?): boolean
	local entityId = GoreServiceUtils.makePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	return self:emitEntityDamage(entityId, originRaw, damageRaw)
end

function GoreServiceServer.OnPlayerDied(self: GoreServiceServer, playerRaw: any, originRaw: any): boolean
	local entityId = GoreServiceUtils.makePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	return self:emitEntityDeath(entityId, originRaw)
end

function GoreServiceServer.RegisterNpcEntity(self: GoreServiceServer, runtimeIdRaw: any, modelRaw: any, configRaw: any?): boolean
	local entityId = GoreServiceUtils.makeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end

	local config = cloneDictionary(configRaw)
	config.isPlayerEntity = false
	if typeof(config.bloodColor) ~= "Color3" then
		config.bloodColor = GoreServiceUtils.DEFAULT_NPC_BLOOD_COLOR
	end
	if config.damageBloodAmount == nil then
		config.damageBloodAmount = GoreServiceUtils.DEFAULT_NPC_DAMAGE_BLOOD_AMOUNT
	end
	if config.deathBloodAmount == nil then
		config.deathBloodAmount = GoreServiceUtils.DEFAULT_NPC_DEATH_BLOOD_AMOUNT
	end
	if config.deathGibCount == nil then
		config.deathGibCount = GoreServiceUtils.DEFAULT_NPC_DEATH_GIB_COUNT
	end
	if config.emitDeathGibs == nil then
		config.emitDeathGibs = true
	end

	return self:registerEntity(entityId, modelRaw, config)
end

function GoreServiceServer.UnregisterNpcEntity(self: GoreServiceServer, runtimeIdRaw: any): boolean
	local entityId = GoreServiceUtils.makeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end
	return self:unregisterEntity(entityId)
end

function GoreServiceServer.OnNpcDamaged(self: GoreServiceServer, runtimeIdRaw: any, originRaw: any, damageRaw: any?): boolean
	local entityId = GoreServiceUtils.makeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end
	return self:emitEntityDamage(entityId, originRaw, damageRaw)
end

function GoreServiceServer.OnNpcDied(self: GoreServiceServer, runtimeIdRaw: any, originRaw: any): boolean
	local entityId = GoreServiceUtils.makeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end
	return self:emitEntityDeath(entityId, originRaw)
end

function GoreServiceServer.EmitNpcSlimeBlood(
	self: GoreServiceServer,
	runtimeIdRaw: any,
	originRaw: any,
	emitCountRaw: any?,
	followDurationRaw: any?,
	dropletAmountRaw: any?
): boolean
	local entityId = GoreServiceUtils.makeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end

	local runtime = self:getEntityRuntime(entityId)
	if runtime == nil then
		return false
	end

	local origin = GoreServiceUtils.resolveBloodOrigin(runtime.model, originRaw)
	if origin == nil then
		return false
	end

	local emitCount = GoreServiceUtils.sanitizeBloodAmount(emitCountRaw, DEFAULT_SLIME_BLOOD_EMIT_COUNT)
	local followDuration = GoreServiceUtils.sanitizeEffectDuration(
		followDurationRaw,
		DEFAULT_SLIME_BLOOD_FOLLOW_DURATION
	)
	local dropletAmount = GoreServiceUtils.sanitizeBloodAmount(dropletAmountRaw, DEFAULT_SLIME_BLOOD_DROPLET_AMOUNT)
	local originPosition = if typeof(origin) == "Vector3" then origin else (origin :: BasePart).Position

	self:broadcast(
		GoreServiceUtils.NETWORK_METHOD_EMIT_SLIME_BLOOD,
		entityId,
		originPosition,
		emitCount,
		followDuration,
		dropletAmount
	)
	return true
end

function GoreServiceServer.Init(self: GoreServiceServer)
	self.networker = Networker.server.new("GoreService", self, {
		self.RequestSync,
	})
	self.entitiesById = {} :: { [string]: EntityRuntime }
	self.binders = NevermoreSupport.getService(ServerBinderSupport)
end

function GoreServiceServer.Destroy(self: GoreServiceServer)
	if self.entitiesById ~= nil then
		table.clear(self.entitiesById)
	end
	if self.networker ~= nil then
		self.networker:destroy()
	end
end

GoreServiceServer.fireClient = GoreServiceServer.FireClient
GoreServiceServer.broadcast = GoreServiceServer.Broadcast
GoreServiceServer.pushEntityToPlayer = GoreServiceServer.PushEntityToPlayer
GoreServiceServer.requestSync = GoreServiceServer.RequestSync
GoreServiceServer.getEntityRuntime = GoreServiceServer.GetEntityRuntime
GoreServiceServer.registerEntity = GoreServiceServer.RegisterEntity
GoreServiceServer.unregisterEntity = GoreServiceServer.UnregisterEntity
GoreServiceServer.setEntityBloodColor = GoreServiceServer.SetEntityBloodColor
GoreServiceServer.emitEntityBlood = GoreServiceServer.EmitEntityBlood
GoreServiceServer.emitEntityDamage = GoreServiceServer.EmitEntityDamage
GoreServiceServer.emitEntityDeath = GoreServiceServer.EmitEntityDeath
GoreServiceServer.registerPlayerCharacter = GoreServiceServer.RegisterPlayerCharacter
GoreServiceServer.unregisterPlayer = GoreServiceServer.UnregisterPlayer
GoreServiceServer.onPlayerDamaged = GoreServiceServer.OnPlayerDamaged
GoreServiceServer.onPlayerDied = GoreServiceServer.OnPlayerDied
GoreServiceServer.registerNpcEntity = GoreServiceServer.RegisterNpcEntity
GoreServiceServer.unregisterNpcEntity = GoreServiceServer.UnregisterNpcEntity
GoreServiceServer.onNpcDamaged = GoreServiceServer.OnNpcDamaged
GoreServiceServer.onNpcDied = GoreServiceServer.OnNpcDied
GoreServiceServer.emitNpcSlimeBlood = GoreServiceServer.EmitNpcSlimeBlood
GoreServiceServer.init = GoreServiceServer.Init
GoreServiceServer.destroy = GoreServiceServer.Destroy

type GoreServiceServer = typeof(GoreServiceServer) & {
	networker: Networker.Server,
	entitiesById: { [string]: EntityRuntime },
}

return GoreServiceServer :: GoreServiceServer
