
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local GoreServiceUtils = require("GoreServiceUtils")
local PacketPayload = require("PacketPayload")
local GoreServicePackets = require("NetPacketsShared").GoreService

local function sendPacket(player: Player, methodName: string, ...: any)
	local packet = GoreServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for GoreService`)
		return
	end

	packet.sendTo(PacketPayload.Pack(...), player)
end

local function bindPacket(self: any, methodName: string)
	local packet = GoreServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for GoreService`)
		return
	end

	packet.listen(function(payload: any, player: Player?)
		if player == nil then
			return
		end

		local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, player, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "requestSync")
end

local NevermoreSupport = require("NevermoreSupport")
local BinderSupportServer = require("BinderSupportServer")

local GoreServiceServer = {}
local SHARED_LARGE_BLOOD_POOL_SIZE = NumberRange.new(0.95, 1.7)
local SHARED_LARGE_BLOOD_POOL_SIZE_Y = NumberRange.new(0.16, 0.28)
local SHARED_LARGE_BLOOD_POOL_STARTING_SIZE = Vector3.new(0.2, 0.42, 0.2)
local SHARED_LARGE_BLOOD_POOL_MAX_SIZE = 1.8
local SHARED_LARGE_BLOOD_POOL_EXPANSE_DIVIDER = 2

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

local function CoerceEntityId(entityIdRaw: any): string?
	return GoreServiceUtils.CoerceEntityId(entityIdRaw)
end

local function cloneDictionary(sourceRaw: any): { [string]: any }
	return GoreServiceUtils.CloneDictionary(sourceRaw)
end

local function isModel(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Model")
end

local function buildRuntimeFromConfig(entityId: string, model: Model, configRaw: any): EntityRuntime
	local source = if typeof(configRaw) == "table" then configRaw else {} :: any
	local isPlayerEntity = GoreServiceUtils.CoerceBoolean((source :: any).isPlayerEntity, false)

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

	local bloodColor = GoreServiceUtils.CoerceColor((source :: any).bloodColor, defaultBloodColor)
	local damageBloodAmount =
		GoreServiceUtils.CoerceBloodAmount((source :: any).damageBloodAmount, defaultDamageBloodAmount)
	local deathBloodAmount =
		GoreServiceUtils.CoerceBloodAmount((source :: any).deathBloodAmount, defaultDeathBloodAmount)
	local deathGibCount = GoreServiceUtils.CoerceGibCount((source :: any).deathGibCount, defaultDeathGibCount)
	local emitDeathGibs = GoreServiceUtils.CoerceBoolean((source :: any).emitDeathGibs, defaultEmitDeathGibs)

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
	sendPacket(player, methodName, ...)
end

function GoreServiceServer.Broadcast(self: GoreServiceServer, methodName: string, ...: any)
	for _, player in Players:GetPlayers() do
		self:FireClient(player, methodName, ...)
	end
end

function GoreServiceServer.PushEntityToPlayer(self: GoreServiceServer, player: Player, runtime: EntityRuntime)
	if runtime.model.Parent == nil then
		return
	end
	self:FireClient(
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
		self:PushEntityToPlayer(player, runtime)
	end
end

function GoreServiceServer.GetEntityRuntime(self: GoreServiceServer, entityIdRaw: any): EntityRuntime?
	if self.entitiesById == nil then
		return nil
	end
	local entityId = CoerceEntityId(entityIdRaw)
	if entityId == nil then
		return nil
	end
	return self.entitiesById[entityId]
end

function GoreServiceServer.RegisterEntity(
	self: GoreServiceServer,
	entityIdRaw: any,
	modelRaw: any,
	configRaw: any?
): boolean
	local entityId = CoerceEntityId(entityIdRaw)
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
	self:Broadcast(
		GoreServiceUtils.NETWORK_METHOD_REGISTER_ENTITY,
		runtime.entityId,
		runtime.model,
		runtime.controllerConfig
	)
	return true
end

function GoreServiceServer.UnregisterEntity(self: GoreServiceServer, entityIdRaw: any): boolean
	local entityId = CoerceEntityId(entityIdRaw)
	if entityId == nil then
		return false
	end
	if self.entitiesById[entityId] == nil then
		return false
	end

	self.entitiesById[entityId] = nil
	self:Broadcast(GoreServiceUtils.NETWORK_METHOD_REMOVE_ENTITY, entityId)
	return true
end

function GoreServiceServer.SetEntityBloodColor(self: GoreServiceServer, entityIdRaw: any, bloodColorRaw: any): boolean
	local runtime = self:GetEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local bloodColor = GoreServiceUtils.CoerceColor(bloodColorRaw, runtime.bloodColor)
	runtime.bloodColor = bloodColor
	runtime.controllerConfig.bloodColor = bloodColor
	self:Broadcast(GoreServiceUtils.NETWORK_METHOD_SET_BLOOD_COLOR, runtime.entityId, bloodColor)
	return true
end

function GoreServiceServer.EmitEntityBlood(
	self: GoreServiceServer,
	entityIdRaw: any,
	originRaw: any,
	amountRaw: any?,
	settingsRaw: any?
): boolean
	local runtime = self:GetEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local origin = GoreServiceUtils.GetBloodOrigin(runtime.model, originRaw)
	if origin == nil then
		return false
	end

	local amount = GoreServiceUtils.CoerceBloodAmount(amountRaw, runtime.damageBloodAmount)
	local settings = cloneDictionary(settingsRaw)
	if typeof(settings.DropletColor) ~= "Color3" then
		settings.DropletColor = runtime.bloodColor
	end

	self:Broadcast(GoreServiceUtils.NETWORK_METHOD_EMIT_BLOOD, runtime.entityId, origin, nil, amount, settings)
	return true
end

function GoreServiceServer.EmitEntityDamage(
	self: GoreServiceServer,
	entityIdRaw: any,
	originRaw: any,
	damageRaw: any?
): boolean
	local runtime = self:GetEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local damageAmount = if typeof(damageRaw) == "number" and damageRaw == damageRaw then math.max(0, damageRaw) else 0
	local scaledAmount = if damageAmount > 0
		then runtime.damageBloodAmount + math.floor(damageAmount * 0.25 + 0.5)
		else runtime.damageBloodAmount
	return self:EmitEntityBlood(entityIdRaw, originRaw, scaledAmount, nil)
end

function GoreServiceServer.EmitEntityDeath(self: GoreServiceServer, entityIdRaw: any, originRaw: any): boolean
	local runtime = self:GetEntityRuntime(entityIdRaw)
	if runtime == nil then
		return false
	end

	local didEmitBlood = self:EmitEntityBlood(runtime.entityId, originRaw, runtime.deathBloodAmount, nil)
	if runtime.emitDeathGibs then
		local sourcePart = GoreServiceUtils.GetOriginPart(runtime.model, originRaw)
		self:Broadcast(
			GoreServiceUtils.NETWORK_METHOD_SPAWN_GIBS,
			runtime.entityId,
			runtime.deathGibCount,
			sourcePart,
			nil
		)
	end
	return didEmitBlood
end

function GoreServiceServer.RegisterPlayerCharacter(self: GoreServiceServer, playerRaw: any, characterRaw: any): boolean
	local entityId = GoreServiceUtils.MakePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	if not isModel(characterRaw) then
		return false
	end

	return self:RegisterEntity(entityId, characterRaw, {
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
	local entityId = GoreServiceUtils.MakePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	return self:UnregisterEntity(entityId)
end

function GoreServiceServer.OnPlayerDamaged(
	self: GoreServiceServer,
	playerRaw: any,
	originRaw: any,
	damageRaw: any?
): boolean
	local entityId = GoreServiceUtils.MakePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	return self:EmitEntityDamage(entityId, originRaw, damageRaw)
end

function GoreServiceServer.OnPlayerDied(self: GoreServiceServer, playerRaw: any, originRaw: any): boolean
	local entityId = GoreServiceUtils.MakePlayerEntityId(playerRaw)
	if entityId == nil then
		return false
	end
	return self:EmitEntityDeath(entityId, originRaw)
end

function GoreServiceServer.RegisterNpcEntity(
	self: GoreServiceServer,
	runtimeIdRaw: any,
	modelRaw: any,
	configRaw: any?
): boolean
	local entityId = GoreServiceUtils.MakeNpcEntityId(runtimeIdRaw)
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

	return self:RegisterEntity(entityId, modelRaw, config)
end

function GoreServiceServer.UnregisterNpcEntity(self: GoreServiceServer, runtimeIdRaw: any): boolean
	local entityId = GoreServiceUtils.MakeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end
	return self:UnregisterEntity(entityId)
end

function GoreServiceServer.OnNpcDamaged(
	self: GoreServiceServer,
	runtimeIdRaw: any,
	originRaw: any,
	damageRaw: any?
): boolean
	local entityId = GoreServiceUtils.MakeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end
	return self:EmitEntityDamage(entityId, originRaw, damageRaw)
end

function GoreServiceServer.OnNpcDied(self: GoreServiceServer, runtimeIdRaw: any, originRaw: any): boolean
	local entityId = GoreServiceUtils.MakeNpcEntityId(runtimeIdRaw)
	if entityId == nil then
		return false
	end
	return self:EmitEntityDeath(entityId, originRaw)
end

function GoreServiceServer.Init(self: GoreServiceServer)
	bindPackets(self)
	self.entitiesById = {} :: { [string]: EntityRuntime }
	(self :: any).binders = NevermoreSupport.GetService(BinderSupportServer)
end

function GoreServiceServer.Destroy(self: GoreServiceServer)
	if self.entitiesById ~= nil then
		table.clear(self.entitiesById)
	end
end
type GoreServiceServer = typeof(GoreServiceServer) & {
	entitiesById: { [string]: EntityRuntime },
}

return GoreServiceServer :: GoreServiceServer
