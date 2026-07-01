local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AudioRegistry = require("Audio")
local AudioServiceServer = require("AudioServiceServer")
local AudioServiceUtils =
	require(script:FindFirstAncestor("game").Shared.Audio:WaitForChild("AudioServiceUtils"))
local InstanceUtils = require("InstanceUtils")
local InventoryServiceServer = require("InventoryServiceServer")
local InventoryServiceUtils = require("InventoryServiceUtils")
local LootItemServer = require("LootItemServer")
local LootServiceCache = require("LootCache")
local LootServiceData = require("Data")
local LootServiceUtils = require("LootServiceUtils")
local PacketPayload = require("PacketPayload")
local LootServicePackets = require("NetPacketsShared").LootService

local function bindPacket(self: any, methodName: string)
	local packet = LootServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for LootService`)
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
	bindPacket(self, "requestDropFromSlot")
	bindPacket(self, "requestDropSelectedSlot")
	bindPacket(self, "requestSync")
end

local NevermoreSupport = require("NevermoreSupport")
local PlayerDataServiceServer = require("PlayerDataServiceServer")
local GetItem = require("GetItem")
local GetToolInstance = require("GetToolInstance")
local Ripple = require(ReplicatedStorage.Packages.Ripple)
local BinderSupportServer = require("BinderSupportServer")
local StringUtils = require("StringUtils")
local Vec = require("Vec")
local WorkspaceFolders = require("WorkspaceFolders")

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

type LootState = string
type LootSettings = LootServiceUtils.LootSettings
type LootMetadata = LootServiceUtils.LootMetadata
type LootRollContext = LootServiceUtils.LootRollContext
type LootRarity = string
type LootRollResult = LootServiceUtils.LootRollResult

type InventoryState = InventoryServiceUtils.InventoryState
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack
type AddItemResult = InventoryServiceUtils.AddItemResult
type SlotMutationResult = InventoryServiceUtils.SlotMutationResult

type InventoryServiceServerObject = {
	GetState: (self: InventoryServiceServerObject, player: Player) -> InventoryState,
	addItem: (
		self: InventoryServiceServerObject,
		player: Player,
		itemIdRaw: any,
		amountRaw: any,
		optionsRaw: any
	) -> AddItemResult,
	RemoveFromSlot: (
		self: InventoryServiceServerObject,
		player: Player,
		slotIndexRaw: any,
		amountRaw: any
	) -> SlotMutationResult,
	ReleaseSuppressedToolImport: (
		self: InventoryServiceServerObject,
		player: Player,
		itemIdRaw: any,
		amountRaw: any
	) -> number,
	SetDropFromSlotHandler: (self: InventoryServiceServerObject, handlerRaw: any) -> (),
}

type PlayerDataServiceServerObject = {
	IncrementValue: (
		self: PlayerDataServiceServerObject,
		player: Player,
		pathRaw: any,
		amountRaw: any,
		fallbackValueRaw: any,
		replicateToClientRaw: any
	) -> number?,
}

type AudioServiceServerObject = {
	PlaySfxForPlayer: (
		self: AudioServiceServerObject,
		player: Player,
		soundAssetIdRaw: any,
		optionsRaw: any
	) -> (),
	PlaySfxForAll: (self: AudioServiceServerObject, soundAssetIdRaw: any, optionsRaw: any) -> (),
}

type LootServiceCacheObject = LootServiceCache.Cache

type PlayerContext = {
	player: Player,
	rootPart: BasePart,
	position: Vector3,
}

type MagnetRuntime = {
	player: Player,
	startedAt: number,
	elapsed: number,
	startDistance: number,
	speed: number,
	xMotion: NumberMotion,
	yMotion: NumberMotion,
	zMotion: NumberMotion,
}

type LootRuntime = {
	id: string,
	itemId: string,
	amount: number,
	maxStack: number,
	metadata: LootMetadata?,
	rarity: LootRarity,
	sourceType: string,
	state: LootState,
	ownerUserId: number?,
	ownerReleaseAt: number,
	spawnedAt: number,
	expiresAt: number,
	stateEnteredAt: number,
	instance: Instance,
	rootPart: BasePart,
	lastKnownPosition: Vector3,
	lockedPlaneX: number?,
	nativeRotation: CFrame,
	stableSince: number?,
	forceIdleUntil: number,
	magnet: MagnetRuntime?,
	disposed: boolean,
	destroyConnection: RBXScriptConnection?,
}

local LootServiceServer = {}

local EPSILON = 1e-4
local LOOT_FOLDER_NAME = "LootRuntime"
local DROP_REQUEST_THROTTLE_SECONDS = 1 / 30
local MISSING_ASSET_ERROR = "no asset found!"
local COIN_TYPE_BY_ITEM_TOKEN: { [string]: "copper" | "silver" | "gold" | "platinum" } = {
	coppercoin = "copper",
	coincopper = "copper",
	silvercoin = "silver",
	coinsilver = "silver",
	goldcoin = "gold",
	coingold = "gold",
	platinumcoin = "platinum",
	coinplatinum = "platinum",
}
local KATANA_DROP_TOKEN = "katana"
local LOOT_AUDIO = (AudioRegistry :: any).Loot or ({} :: any)
local LOOT_ITEM_PICKUP_AUDIO = LOOT_AUDIO.ItemPickup or ({} :: any)
local LOOT_COIN_DROP_AUDIO = LOOT_AUDIO.CoinDrop or ({} :: any)
local LOOT_COIN_PICKUP_AUDIO = LOOT_AUDIO.CoinPickup or ({} :: any)
local LOOT_PICKUP_VOLUME = 1.5

local function CoerceOwnerUserId(userIdRaw: any): number?
	if typeof(userIdRaw) ~= "number" or userIdRaw ~= userIdRaw then
		return nil
	end
	local userId = math.floor(userIdRaw)
	if userId <= 0 then
		return nil
	end
	return userId
end

local function GetPlayerRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.Health <= 0 then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

local function forEachBasePart(instance: Instance, callback: (BasePart) -> ())
	if instance:IsA("BasePart") then
		callback(instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

local function toUnitVectorOrFallback(directionRaw: any, fallbackRaw: Vector3): Vector3
	local fallback = fallbackRaw
	if fallback.Magnitude <= EPSILON then
		fallback = Vector3.new(0, 0, -1)
	end
	local fallbackUnit = Vec.Unit(fallback, Vector3.new(0, 0, -1))

	local direction = LootServiceUtils.CoerceVector3(directionRaw, fallback)
	if direction.Magnitude <= EPSILON then
		return fallbackUnit
	end
	return Vec.Unit(direction, fallbackUnit)
end

local function shallowCopy(sourceRaw: any): { [string]: any }
	local output = {}
	if typeof(sourceRaw) ~= "table" then
		return output
	end
	for key, value in sourceRaw do
		if typeof(key) == "string" then
			output[key] = value
		end
	end
	return output
end

local function pickRandomSoundAssetId(randomObject: Random, soundAssetIds: { string }): string?
	local count = #soundAssetIds
	if count <= 0 then
		return nil
	end
	return soundAssetIds[randomObject:NextInteger(1, count)]
end

function LootServiceServer.CacheToolTemplateIfPossible(self: LootServiceServer, itemId: string, template: Instance?)
	if template == nil then
		return
	end
	if template:IsA("Tool") then
		self.cache:RememberToolTemplate(itemId, template)
	end
end

function LootServiceServer.IsToolMatchingItemId(self: LootServiceServer, tool: Tool, itemIdRaw: any): boolean
	local itemId = LootServiceUtils.CoerceString(itemIdRaw, nil)
	if itemId == nil then
		return false
	end

	local targetTokens: { [string]: boolean } = {}
	for _, candidate in LootServiceUtils.GetItemNameCandidates(self.data, itemId) do
		local token = StringUtils.CompactToken(candidate)
		if token ~= "" then
			targetTokens[token] = true
		end
	end
	if next(targetTokens) == nil then
		targetTokens[StringUtils.CompactToken(itemId)] = true
	end

	local GotToolItemId = GetToolInstance.GetToolItemId(tool)
	local idCandidates: { any } = {
		GotToolItemId,
		tool:GetAttribute("itemId"),
		tool:GetAttribute("ItemId"),
		tool:GetAttribute("ittemId"),
		tool.Name,
	}
	for _, candidate in idCandidates do
		local candidateToken = StringUtils.CompactToken(candidate)
		if candidateToken ~= "" and targetTokens[candidateToken] == true then
			return true
		end
	end
	return false
end

function LootServiceServer.CaptureDropToolClones(
	self: LootServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any
): { Tool }
	local itemId = LootServiceUtils.CoerceString(itemIdRaw, nil)
	if itemId == nil then
		return {}
	end

	local amount = LootServiceUtils.GotRopAmount(amountRaw, 1)
	local remaining = math.max(0, math.floor(amount))
	if remaining <= 0 then
		return {}
	end

	local captured = {}
	local function captureFromContainer(container: Instance?)
		if container == nil or remaining <= 0 then
			return
		end
		for _, child in container:GetChildren() do
			if remaining <= 0 then
				break
			end
			if not child:IsA("Tool") then
				continue
			end
			if not self:IsToolMatchingItemId(child, itemId) then
				continue
			end
			local clone = child:Clone()
			if clone:IsA("Tool") then
				clone.Parent = nil
				table.insert(captured, clone)
				remaining -= 1
			else
				clone:Destroy()
			end
		end
	end

	captureFromContainer(player.Character)
	local backpack = player:FindFirstChildOfClass("Backpack")
	captureFromContainer(backpack)
	return captured
end

function LootServiceServer.RestoreCachedDropTools(
	self: LootServiceServer,
	player: Player,
	runtime: LootRuntime,
	amountRaw: any
)
	local amount = LootServiceUtils.GotRopAmount(amountRaw, 1)
	local remaining = math.max(0, math.floor(amount))
	if remaining <= 0 then
		return
	end

	local targetContainer: Instance? = player:FindFirstChildOfClass("Backpack")
	if targetContainer == nil then
		targetContainer = player.Character
	end
	if targetContainer == nil then
		return
	end

	while remaining > 0 do
		local tool = self.cache:PopDroppedTool(runtime.id, runtime.itemId)
		if tool == nil then
			tool = self.cache:CloneToolTemplate(runtime.itemId)
			if tool ~= nil then
				tool:SetAttribute("itemId", runtime.itemId)
				tool:SetAttribute("ItemId", runtime.itemId)
				local metadata = runtime.metadata
				if typeof(metadata) == "table" then
					local itemType = LootServiceUtils.CoerceString((metadata :: { [string]: any }).itemType, nil)
					if itemType ~= nil then
						tool:SetAttribute("itemType", itemType)
						tool:SetAttribute("ItemType", itemType)
					end
				end
			end
		end
		if tool == nil then
			break
		end

		self.inventoryService:ReleaseSuppressedToolImport(player, runtime.itemId, 1)
		tool.Parent = targetContainer
		remaining -= 1
	end
end

function LootServiceServer.GetCoinTypeFromItemId(self: LootServiceServer, itemIdRaw: any): string?
	local itemId = LootServiceUtils.CoerceString(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local itemToken = StringUtils.CompactToken(itemId)
	local mapped = COIN_TYPE_BY_ITEM_TOKEN[itemToken]
	if mapped ~= nil then
		return mapped
	end

	for _, candidate in LootServiceUtils.GetItemNameCandidates(self.data, itemId) do
		local token = StringUtils.CompactToken(candidate)
		local byToken = COIN_TYPE_BY_ITEM_TOKEN[token]
		if byToken ~= nil then
			return byToken
		end
	end

	return nil
end

function LootServiceServer.ShouldRouteRuntimeToCoinWallet(self: LootServiceServer, runtime: LootRuntime): boolean
	if runtime.sourceType == "PlayerDrop" then
		return false
	end
	return self:GetCoinTypeFromItemId(runtime.itemId) ~= nil
end

function LootServiceServer.TryCollectRuntimeToCoinWallet(
	self: LootServiceServer,
	runtime: LootRuntime,
	player: Player
): boolean
	local coinType = self:GetCoinTypeFromItemId(runtime.itemId)
	if coinType == nil then
		return false
	end

	local amount = math.max(1, math.floor(runtime.amount))
	local nextValue = self.playerDataService:IncrementValue(player, { "coins", coinType }, amount, 0, true)
	if nextValue == nil then
		return false
	end

	self:PlayPickupSound(runtime, player)
	self:TransitionState(runtime, LootServiceUtils.STATE_COLLECTED, "CollectedCoinWallet")
	self:DisposeRuntime(runtime, "CollectedCoinWallet")
	return true
end

function LootServiceServer.EnsureLootFolder(_self: LootServiceServer): Folder
	return WorkspaceFolders.GetOrCreateFolderInGame(LOOT_FOLDER_NAME)
end

function LootServiceServer.RefreshPickupSoundTemplates(self: LootServiceServer)
	self.itemPickupSoundAssetIds = AudioServiceUtils.CollectSoundAssetIds(LOOT_ITEM_PICKUP_AUDIO)
	self.coinDropSoundAssetIds = AudioServiceUtils.CollectSoundAssetIds(LOOT_COIN_DROP_AUDIO)
	self.coinPickupSoundAssetIds = AudioServiceUtils.CollectSoundAssetIds(LOOT_COIN_PICKUP_AUDIO)
end

function LootServiceServer.PlayCoinDropSound(self: LootServiceServer, runtime: LootRuntime)
	local soundService = self.soundService
	if soundService == nil then
		return
	end

	if #self.coinDropSoundAssetIds <= 0 then
		self:RefreshPickupSoundTemplates()
	end

	local soundAssetId = pickRandomSoundAssetId(self.random, self.coinDropSoundAssetIds)
	if soundAssetId == nil then
		return
	end
	if runtime.rootPart.Parent == nil then
		return
	end

	soundService:PlaySfxForAll(soundAssetId, {
		category = "SFX",
		parent = runtime.rootPart,
		autoDestroy = true,
	})
end

function LootServiceServer.PlayPickupSound(self: LootServiceServer, runtime: LootRuntime, player: Player)
	local soundService = self.soundService
	if soundService == nil then
		return
	end

	if #self.itemPickupSoundAssetIds <= 0 and #self.coinPickupSoundAssetIds <= 0 then
		self:RefreshPickupSoundTemplates()
	end

	local soundAssetId: string?
	if self:GetCoinTypeFromItemId(runtime.itemId) ~= nil then
		soundAssetId = pickRandomSoundAssetId(self.random, self.coinPickupSoundAssetIds)
	else
		soundAssetId = pickRandomSoundAssetId(self.random, self.itemPickupSoundAssetIds)
	end
	if soundAssetId == nil then
		return
	end

	local parent: Instance? = GetPlayerRootPart(player)
	if parent == nil then
		parent = player.Character
	end

	soundService:PlaySfxForPlayer(player, soundAssetId, {
		category = "SFX",
		volume = LOOT_PICKUP_VOLUME,
		parent = parent,
		autoDestroy = true,
	})
end

function LootServiceServer.GetItemTemplate(self: LootServiceServer, itemIdRaw: any): Instance?
	local itemId = LootServiceUtils.CoerceString(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local cached = self.itemTemplateByItemId[itemId]
	if cached ~= nil then
		if cached == false then
			error(MISSING_ASSET_ERROR, 0)
		end
		local cachedInstance = cached :: Instance
		if cachedInstance.Parent ~= nil then
			self:CacheToolTemplateIfPossible(itemId, cachedInstance)
			self:CacheToolTemplateIfPossible(itemId, GetItem.GetToolTemplate(itemId))
			return cachedInstance
		end
		self.itemTemplateByItemId[itemId] = nil
	end

	local GotTemplate = GetItem.GetPrimaryTemplate(itemId)
	if GotTemplate ~= nil then
		self.itemTemplateByItemId[itemId] = GotTemplate
		self:CacheToolTemplateIfPossible(itemId, GotTemplate)
		self:CacheToolTemplateIfPossible(itemId, GetItem.GetToolTemplate(itemId))
		return GotTemplate
	end

	error(MISSING_ASSET_ERROR, 0)
end

function LootServiceServer.CloneLootInstanceFromTemplate(
	self: LootServiceServer,
	template: Instance,
	itemId: string
): (Instance?, BasePart?)
	if template:IsA("Tool") then
		local handle = template:FindFirstChild("Handle")
		if handle ~= nil and handle:IsA("BasePart") then
			local handleClone = handle:Clone()
			handleClone.Name = itemId
			return handleClone, handleClone
		end
		return nil, nil
	end

	if template:IsA("Accessory") then
		local handle = template:FindFirstChild("Handle")
		if handle ~= nil and handle:IsA("BasePart") then
			local model = Instance.new("Model")
			model.Name = itemId
			local handleClone = handle:Clone()
			handleClone.Parent = model
			model.PrimaryPart = handleClone
			return model, handleClone
		end
		return nil, nil
	end

	local clone = template:Clone()
	local rootPart = InstanceUtils.GetInstanceRootPart(clone, true)
	if rootPart == nil then
		clone:Destroy()
		return nil, nil
	end

	return clone, rootPart
end

function LootServiceServer.GetUntimePlaneX(self: LootServiceServer, runtime: LootRuntime): number?
	if self.settings.lockTo2DPlane ~= true then
		return nil
	end
	return runtime.lockedPlaneX
end

function LootServiceServer.ClampPositionToRuntimePlane(
	self: LootServiceServer,
	runtime: LootRuntime,
	positionRaw: Vector3
): Vector3
	local planeX = self:GetUntimePlaneX(runtime)
	if planeX == nil then
		return positionRaw
	end
	return Vector3.new(planeX, positionRaw.Y, positionRaw.Z)
end

function LootServiceServer.ApplyRuntimePlaneConstraint(self: LootServiceServer, runtime: LootRuntime)
	local planeX = self:GetUntimePlaneX(runtime)
	if planeX == nil or runtime.disposed then
		return
	end
	if runtime.rootPart.Parent == nil then
		return
	end

	local velocity = runtime.rootPart.AssemblyLinearVelocity
	if math.abs(velocity.X) > EPSILON then
		runtime.rootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, velocity.Z)
	end

	local rootPosition = runtime.rootPart.Position
	runtime.rootPart.AssemblyAngularVelocity = Vector3.zero;
	(runtime.instance :: any):PivotTo(CFrame.new(planeX, rootPosition.Y, rootPosition.Z) * runtime.nativeRotation)

	local updatedRootPosition = runtime.rootPart.Position
	runtime.lastKnownPosition = Vector3.new(planeX, updatedRootPosition.Y, updatedRootPosition.Z)
end

function LootServiceServer.SetRuntimePosition(self: LootServiceServer, runtime: LootRuntime, positionRaw: any)
	local position = LootServiceUtils.CoerceVector3(positionRaw, runtime.lastKnownPosition)
	position = self:ClampPositionToRuntimePlane(runtime, position)
	if runtime.disposed then
		return
	end

	(runtime.instance :: any):PivotTo(CFrame.new(position) * runtime.nativeRotation)
	runtime.rootPart.AssemblyAngularVelocity = Vector3.zero;
	runtime.lastKnownPosition = position
end

function LootServiceServer.RefreshRuntimePosition(self: LootServiceServer, runtime: LootRuntime)
	if runtime.disposed then
		return
	end
	if runtime.rootPart.Parent == nil then
		return
	end
	local position = runtime.rootPart.Position
	runtime.lastKnownPosition = self:ClampPositionToRuntimePlane(runtime, position)
end

function LootServiceServer.ApplyRuntimeAttributes(_self: LootServiceServer, runtime: LootRuntime, reasonRaw: any?)
	local reason = LootServiceUtils.CoerceString(reasonRaw, nil)
	runtime.instance:SetAttribute("LootId", runtime.id)
	runtime.instance:SetAttribute("ItemId", runtime.itemId)
	runtime.instance:SetAttribute("Amount", runtime.amount)
	runtime.instance:SetAttribute("MaxStack", runtime.maxStack)
	runtime.instance:SetAttribute("Rarity", runtime.rarity)
	runtime.instance:SetAttribute("SourceType", runtime.sourceType)
	runtime.instance:SetAttribute("LootState", runtime.state)
	runtime.instance:SetAttribute("OwnerUserId", runtime.ownerUserId)
	runtime.instance:SetAttribute("OwnerReleaseAt", runtime.ownerReleaseAt)
	runtime.instance:SetAttribute("ExpiresAt", runtime.expiresAt)
	if reason ~= nil then
		runtime.instance:SetAttribute("LootStateReason", reason)
	end

	runtime.rootPart:SetAttribute("LootId", runtime.id)
	runtime.rootPart:SetAttribute("ItemId", runtime.itemId)
	runtime.rootPart:SetAttribute("LootState", runtime.state)
end

function LootServiceServer.SetRuntimePhysics(
	self: LootServiceServer,
	runtime: LootRuntime,
	anchored: boolean,
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean,
	applyBounceProperties: boolean
)
	if runtime.disposed then
		return
	end

	forEachBasePart(runtime.instance, function(part: BasePart)
		part.Anchored = anchored
		part.CanCollide = canCollide
		part.CanTouch = canTouch
		part.CanQuery = canQuery

		if applyBounceProperties then
			local current = part.CustomPhysicalProperties :: PhysicalProperties?
			local density = if current ~= nil then current.Density else 0.7
			local frictionWeight = if current ~= nil then current.FrictionWeight else 1
			part.CustomPhysicalProperties = PhysicalProperties.new(
				density,
				self.settings.dropFriction,
				self.settings.dropBounciness,
				frictionWeight,
				self.settings.dropElasticityWeight
			)
		end
	end)

	if not anchored then
		pcall(function()
			runtime.rootPart:SetNetworkOwner(nil)
		end)
	end
end

function LootServiceServer.DestroyMagnetRuntime(_self: LootServiceServer, runtime: LootRuntime)
	local magnet = runtime.magnet
	if magnet == nil then
		return
	end

	magnet.xMotion:destroy()
	magnet.yMotion:destroy()
	magnet.zMotion:destroy()
	runtime.magnet = nil
end

function LootServiceServer.TransitionState(
	self: LootServiceServer,
	runtime: LootRuntime,
	nextStateRaw: any,
	reasonRaw: any?
): boolean
	local currentState = runtime.state
	local nextState = LootServiceUtils.CoerceState(nextStateRaw, currentState)
	if currentState == nextState then
		return true
	end

	if not LootServiceUtils.IsAllowedStateTransition(currentState, nextState) then
		return false
	end

	runtime.state = nextState
	runtime.stateEnteredAt = os.clock()
	runtime.stableSince = nil

	if nextState ~= LootServiceUtils.STATE_MAGNETIZED then
		self:DestroyMagnetRuntime(runtime)
	end

	if nextState == LootServiceUtils.STATE_DROPPED or nextState == LootServiceUtils.STATE_SETTLING then
		self:SetRuntimePhysics(runtime, false, true, true, true, true)
	elseif nextState == LootServiceUtils.STATE_IDLE then
		self:SetRuntimePhysics(runtime, true, true, true, true, false)
		runtime.rootPart.AssemblyLinearVelocity = Vector3.zero
		runtime.rootPart.AssemblyAngularVelocity = Vector3.zero
	elseif nextState == LootServiceUtils.STATE_MAGNETIZED or nextState == LootServiceUtils.STATE_COLLECTED then
		self:SetRuntimePhysics(runtime, true, false, false, false, false)
	end

	self:ApplyRuntimeAttributes(runtime, reasonRaw)
	return true
end

function LootServiceServer.DisposeRuntime(self: LootServiceServer, runtime: LootRuntime, reasonRaw: any?)
	if runtime.disposed then
		return
	end

	runtime.disposed = true
	self.lootById[runtime.id] = nil
	self.cache:DiscardDroppedTools(runtime.id)
	self:DestroyMagnetRuntime(runtime)
	if runtime.destroyConnection ~= nil then
		runtime.destroyConnection:Disconnect()
		runtime.destroyConnection = nil
	end
	self:ApplyRuntimeAttributes(runtime, reasonRaw)
	if runtime.instance.Parent ~= nil then
		runtime.instance:Destroy()
	end
end

function LootServiceServer.RemoveRuntimeById(self: LootServiceServer, lootIdRaw: any, reasonRaw: any?)
	local lootId = LootServiceUtils.CoerceString(lootIdRaw, nil)
	if lootId == nil then
		return
	end
	local runtime = self.lootById[lootId]
	if runtime == nil then
		return
	end

	self:TransitionState(runtime, LootServiceUtils.STATE_COLLECTED, reasonRaw)
	self:DisposeRuntime(runtime, reasonRaw)
end

function LootServiceServer.ApplyDropImpulse(self: LootServiceServer, runtime: LootRuntime, throwDirectionRaw: any)
	local isPlaneLocked = self:GetUntimePlaneX(runtime) ~= nil
	local randomHorizontal =
		Vector3.new(if isPlaneLocked then 0 else self.random:NextNumber(-1, 1), 0, self.random:NextNumber(-1, 1))
	if randomHorizontal.Magnitude <= EPSILON then
		randomHorizontal = if isPlaneLocked then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	end

	local throwDirection = toUnitVectorOrFallback(throwDirectionRaw, randomHorizontal)
	if isPlaneLocked then
		throwDirection = Vector3.new(0, throwDirection.Y, throwDirection.Z)
		if throwDirection.Magnitude <= EPSILON then
			throwDirection = Vector3.new(0, 0, -1)
		end
		throwDirection = throwDirection.Unit
	end
	local lateralDirection = randomHorizontal.Unit
	local upwardVelocity = self.settings.dropImpulseUp + self.random:NextNumber(0, self.settings.dropImpulseRandomUp)
	local linearVelocity = throwDirection * self.settings.dropImpulseForward
		+ lateralDirection * self.settings.dropImpulseRandomHorizontal
		+ Vector3.new(0, upwardVelocity, 0)
	if isPlaneLocked then
		linearVelocity = Vector3.new(0, linearVelocity.Y, linearVelocity.Z)
	end

	local itemToken = StringUtils.CompactToken(runtime.itemId)
	local linearScale = 1
	local maxLinearSpeed: number? = nil

	if itemToken == KATANA_DROP_TOKEN then
		linearScale = 0.28
		maxLinearSpeed = 10
	elseif runtime.sourceType == "PlayerDrop" and runtime.maxStack <= 1 then
		linearScale = 0.5
		maxLinearSpeed = 16
	end

	linearVelocity *= linearScale
	if maxLinearSpeed ~= nil then
		local speed = linearVelocity.Magnitude
		if speed > maxLinearSpeed and speed > EPSILON then
			linearVelocity = linearVelocity.Unit * maxLinearSpeed
		end
	end
	if isPlaneLocked then
		linearVelocity = Vector3.new(0, linearVelocity.Y, linearVelocity.Z)
	end

	runtime.rootPart.AssemblyLinearVelocity = linearVelocity
	runtime.rootPart.AssemblyAngularVelocity = Vector3.zero
end

function LootServiceServer.ToPublicSnapshot(_self: LootServiceServer, runtime: LootRuntime): { [string]: any }
	return {
		id = runtime.id,
		itemId = runtime.itemId,
		amount = runtime.amount,
		maxStack = runtime.maxStack,
		rarity = runtime.rarity,
		sourceType = runtime.sourceType,
		state = runtime.state,
		position = runtime.lastKnownPosition,
	}
end

function LootServiceServer.SpawnLootRuntime(
	self: LootServiceServer,
	itemIdRaw: any,
	amountRaw: any,
	positionRaw: any,
	optionsRaw: any
): LootRuntime?
	local itemId = LootServiceUtils.CoerceString(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local itemConfig = LootServiceUtils.GetItemConfig(self.data, itemId)
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {} :: any
	local amount = LootServiceUtils.CoerceInteger(amountRaw, 1, 1, 999999)
	local maxStack = LootServiceUtils.CoerceInteger((options :: any).maxStack, itemConfig.maxStack, 1, 999999)
	local rarity = LootServiceUtils.CoerceRarity((options :: any).rarity, itemConfig.rarity)
	local sourceType = LootServiceUtils.CoerceString((options :: any).sourceType, "Generic") or "Generic"
	local metadata = if typeof((options :: any).metadata) == "table"
		then LootServiceUtils.CloneDeep((options :: any).metadata)
		else nil
	local ownerUserId = CoerceOwnerUserId((options :: any).ownerUserId)
	local ownerLockSeconds =
		LootServiceUtils.CoerceNumber((options :: any).ownerLockSeconds, self.settings.ownerLockSeconds, 0, 120)
	local now = os.clock()
	local expiresAt = now
		+ LootServiceUtils.CoerceNumber((options :: any).despawnSeconds, self.settings.despawnSeconds, 0.1, 3600)
	local requestedLootId = LootServiceUtils.CoerceString((options :: any).lootId, nil)
	local lootId = requestedLootId or LootServiceUtils.CreateLootId(self.random, itemId)

	local instance = LootItemServer.CreateModel({
		itemId = itemId,
		amount = amount,
		name = ("Loot_%s"):format(itemId),
	}) :: Instance
	local rootPart = InstanceUtils.GetInstanceRootPart(instance, true)
	if instance == nil or rootPart == nil then
		error(MISSING_ASSET_ERROR, 0)
	end

	if self.lootById[lootId] ~= nil then
		self:RemoveRuntimeById(lootId, "Replaced")
	end

	instance.Name = ("Loot_%s"):format(itemId)
	instance.Parent = self.lootFolder

	local spawnPosition = LootServiceUtils.CoerceVector3(positionRaw, Vector3.zero)
	local lockedPlaneX = if self.settings.lockTo2DPlane then spawnPosition.X else nil
	if lockedPlaneX ~= nil then
		spawnPosition = Vector3.new(lockedPlaneX, spawnPosition.Y, spawnPosition.Z)
	end
	local runtime: LootRuntime = {
		id = lootId,
		itemId = itemId,
		amount = amount,
		maxStack = maxStack,
		metadata = metadata,
		rarity = rarity,
		sourceType = sourceType,
		state = LootServiceUtils.STATE_DROPPED,
		ownerUserId = ownerUserId,
		ownerReleaseAt = if ownerUserId ~= nil then now + ownerLockSeconds else 0,
		spawnedAt = now,
		expiresAt = expiresAt,
		stateEnteredAt = now,
		instance = instance,
		rootPart = rootPart,
		lastKnownPosition = spawnPosition,
		lockedPlaneX = lockedPlaneX,
		nativeRotation = rootPart.CFrame - rootPart.CFrame.Position,
		stableSince = nil,
		forceIdleUntil = -math.huge,
		magnet = nil,
		disposed = false,
		destroyConnection = nil,
	}

	self.lootById[lootId] = runtime
	self:SetRuntimePosition(runtime, spawnPosition)
	self:SetRuntimePhysics(runtime, false, true, true, true, true)
	self:ApplyDropImpulse(runtime, (options :: any).throwDirection)
	self:ApplyRuntimeAttributes(runtime, "Spawned")
	if self:GetCoinTypeFromItemId(itemId) ~= nil then
		self:PlayCoinDropSound(runtime)
	end

	runtime.destroyConnection = runtime.instance.Destroying:Connect(function()
		local liveRuntime = self.lootById[lootId]
		if liveRuntime == nil or liveRuntime.disposed then
			return
		end
		liveRuntime.disposed = true
		self.lootById[lootId] = nil
		self:DestroyMagnetRuntime(liveRuntime)
	end)

	return runtime
end

function LootServiceServer.GetDropOriginForPlayer(
	self: LootServiceServer,
	player: Player,
	throwDirectionRaw: any
): Vector3
	local rootPart = GetPlayerRootPart(player)
	if rootPart == nil then
		return Vector3.zero
	end

	local throwDirection = toUnitVectorOrFallback(throwDirectionRaw, rootPart.CFrame.LookVector)
	local origin = rootPart.Position
		+ throwDirection * self.settings.playerDropForwardOffset
		+ Vector3.new(0, self.settings.playerDropUpOffset, 0)
	if self.settings.lockTo2DPlane then
		return Vector3.new(rootPart.Position.X, origin.Y, origin.Z)
	end
	return origin
end

function LootServiceServer.SpawnDropsFromTable(
	self: LootServiceServer,
	dropTableIdRaw: any,
	originRaw: any,
	optionsRaw: any
): { [string]: any }
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {} :: any
	local onlyCoinLoot = (options :: any).onlyCoinLoot == true
	local origin = LootServiceUtils.CoerceVector3(originRaw, Vector3.zero)
	local context = if typeof((options :: any).context) == "table"
		then shallowCopy((options :: any).context)
		else {} :: any
	local mutableContext = context :: any
	local sourceType = LootServiceUtils.CoerceString((options :: any).sourceType, nil)
	if sourceType ~= nil then
		mutableContext.sourceType = sourceType
	end

	local drops: { LootRollResult } =
		LootServiceUtils.RollDropTable(self.data, dropTableIdRaw, self.random, context :: LootRollContext)
	local ownerUserId = CoerceOwnerUserId((options :: any).ownerUserId)
	local ownerLockSeconds =
		LootServiceUtils.CoerceNumber((options :: any).ownerLockSeconds, self.settings.ownerLockSeconds, 0, 120)

	local output = {}
	for _, drop in drops do
		if onlyCoinLoot and self:GetCoinTypeFromItemId(drop.itemId) == nil then
			continue
		end

		local radius = self.random:NextNumber(self.settings.scatterRadiusMin, self.settings.scatterRadiusMax)
		local horizontalOffset: Vector3
		if self.settings.lockTo2DPlane then
			horizontalOffset = Vector3.new(0, 0, self.random:NextNumber(-radius, radius))
		else
			local angle = self.random:NextNumber(0, math.pi * 2)
			horizontalOffset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		end
		local spawnPosition = origin + horizontalOffset + Vector3.new(0, self.settings.spawnHeightOffset, 0)
		local throwDirection = if horizontalOffset.Magnitude > EPSILON then horizontalOffset.Unit else nil

		local runtime = self:SpawnLootRuntime(drop.itemId, drop.amount, spawnPosition, {
			maxStack = drop.maxStack,
			metadata = drop.metadata,
			rarity = drop.rarity,
			sourceType = drop.sourceType,
			ownerUserId = ownerUserId,
			ownerLockSeconds = ownerLockSeconds,
			throwDirection = throwDirection,
		})
		if runtime ~= nil then
			table.insert(output, self:ToPublicSnapshot(runtime))
		end
	end

	return output :: any
end

function LootServiceServer.SpawnDropsFromSource(
	self: LootServiceServer,
	sourceRaw: any,
	originRaw: any,
	optionsRaw: any
): { [string]: any }
	local dropTableId = LootServiceUtils.GotRopTableId(self.data, sourceRaw, "Slime")
	if dropTableId == nil then
		return {}
	end

	local options = if typeof(optionsRaw) == "table" then shallowCopy(optionsRaw) else {} :: any
	local mutableOptions = options :: any
	local sourceType = LootServiceUtils.CoerceString(mutableOptions.sourceType, nil)
	if sourceType == nil then
		if typeof(sourceRaw) == "string" then
			sourceType = sourceRaw
		elseif typeof(sourceRaw) == "table" then
			local source = sourceRaw :: { [string]: any }
			sourceType = LootServiceUtils.CoerceString(source.sourceType, nil)
				or LootServiceUtils.CoerceString(source.npcType, nil)
				or LootServiceUtils.CoerceString(source.displayName, nil)
		end
	end
	mutableOptions.sourceType = sourceType or dropTableId
	mutableOptions.onlyCoinLoot = true

	return self:SpawnDropsFromTable(dropTableId, originRaw, options)
end

function LootServiceServer.CanPlayerPickupRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	playerContext: PlayerContext,
	now: number
): (boolean, string)
	if runtime.amount <= 0 then
		return false, "NoAmount"
	end
	if
		runtime.ownerUserId ~= nil
		and runtime.ownerUserId ~= playerContext.player.UserId
		and now < runtime.ownerReleaseAt
	then
		return false, "OwnerLocked"
	end
	local delta = playerContext.position - runtime.lastKnownPosition
	if delta.Magnitude > self.settings.pickupScanRadius then
		return false, "TooFar"
	end
	return true, "Ok"
end

function LootServiceServer.CollectPlayerContexts(
	self: LootServiceServer
): ({ PlayerContext }, { [Player]: PlayerContext })
	local contexts = {}
	local contextsByPlayer = {}
	for _, player in Players:GetPlayers() do
		local rootPart = GetPlayerRootPart(player)
		if rootPart == nil then
			continue
		end

		local context: PlayerContext = {
			player = player,
			rootPart = rootPart,
			position = rootPart.Position,
		}
		table.insert(contexts, context)
		contextsByPlayer[player] = context
	end
	return contexts, contextsByPlayer
end

function LootServiceServer.FindNearestEligiblePlayerContext(
	self: LootServiceServer,
	runtime: LootRuntime,
	playerContexts: { PlayerContext },
	now: number
): PlayerContext?
	local nearest: PlayerContext? = nil
	local nearestDistance = math.huge
	for _, context in playerContexts do
		local canPickup = self:CanPlayerPickupRuntime(runtime, context, now)
		if not canPickup then
			continue
		end

		local distance = (context.position - runtime.lastKnownPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = context
		end
	end
	return nearest
end

function LootServiceServer.BeginMagnetization(
	self: LootServiceServer,
	runtime: LootRuntime,
	playerContext: PlayerContext,
	now: number
): boolean
	if runtime.disposed then
		return false
	end

	local targetPosition = playerContext.position + Vector3.new(0, self.settings.collectOffsetY, 0)
	local currentPosition = runtime.lastKnownPosition
	local startDistance = (targetPosition - currentPosition).Magnitude
	local magnet: MagnetRuntime = {
		player = playerContext.player,
		startedAt = now,
		elapsed = 0,
		startDistance = math.max(startDistance, EPSILON),
		speed = self.settings.magnetBaseSpeed,
		xMotion = Ripple.createMotion(currentPosition.X),
		yMotion = Ripple.createMotion(currentPosition.Y),
		zMotion = Ripple.createMotion(currentPosition.Z),
	}
	runtime.magnet = magnet

	if not self:TransitionState(runtime, LootServiceUtils.STATE_MAGNETIZED, "PickupEligible") then
		self:DestroyMagnetRuntime(runtime)
		return false
	end
	return true
end

function LootServiceServer.CanInventoryAcceptRuntime(
	self: LootServiceServer,
	player: Player,
	runtime: LootRuntime
): boolean
	local inventoryState = self.inventoryService:GetState(player)
	if not InventoryServiceUtils.IsLoadedState(inventoryState.loadState) then
		return false
	end

	local remaining = runtime.amount
	for _, slot in inventoryState.slots do
		local stack = slot.stack
		if stack == nil then
			continue
		end
		if stack.itemId ~= runtime.itemId then
			continue
		end
		if not LootServiceUtils.DeepEqual(stack.metadata, runtime.metadata) then
			continue
		end

		local room = math.max(0, stack.maxStack - stack.amount)
		remaining -= room
		if remaining <= 0 then
			return true
		end
	end

	local emptySlotCount = 0
	for _, slot in inventoryState.slots do
		if slot.stack == nil then
			emptySlotCount += 1
		end
	end

	local perSlotMax = math.max(1, runtime.maxStack)
	remaining -= emptySlotCount * perSlotMax
	return remaining <= 0
end

function LootServiceServer.TryCollectRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	player: Player,
	now: number
): boolean
	if runtime.disposed or runtime.state ~= LootServiceUtils.STATE_MAGNETIZED then
		return false
	end

	if self:ShouldRouteRuntimeToCoinWallet(runtime) then
		local didCollectToWallet = self:TryCollectRuntimeToCoinWallet(runtime, player)
		if didCollectToWallet then
			return true
		end
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		return self:TransitionState(runtime, LootServiceUtils.STATE_IDLE, "CoinWalletUnavailable")
	end

	if not self:CanInventoryAcceptRuntime(player, runtime) then
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		return self:TransitionState(runtime, LootServiceUtils.STATE_IDLE, "InventoryFull")
	end

	local addResult = self.inventoryService:AddItem(player, runtime.itemId, runtime.amount, {
		maxStack = runtime.maxStack,
		metadata = LootServiceUtils.CloneDeep(runtime.metadata),
		stackIdPrefix = "loot",
	})
	local addedAmount = math.clamp(addResult.added, 0, runtime.amount)
	if addedAmount > 0 then
		self:RestoreCachedDropTools(player, runtime, addedAmount)
		self:PlayPickupSound(runtime, player)
	end
	if addedAmount ~= runtime.amount then
		if addedAmount > 0 then
			runtime.amount -= addedAmount
		end
		if runtime.amount <= 0 then
			self:TransitionState(runtime, LootServiceUtils.STATE_COLLECTED, "Collected")
			self:DisposeRuntime(runtime, "Collected")
			return true
		end
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		return self:TransitionState(runtime, LootServiceUtils.STATE_IDLE, "PartialCollect")
	end

	self:TransitionState(runtime, LootServiceUtils.STATE_COLLECTED, "Collected")
	self:DisposeRuntime(runtime, "Collected")
	return true
end

function LootServiceServer.UpdateDroppedRuntime(self: LootServiceServer, runtime: LootRuntime, now: number)
	if now - runtime.stateEnteredAt >= self.settings.droppedStateDuration then
		self:TransitionState(runtime, LootServiceUtils.STATE_SETTLING, "DroppedImpulseComplete")
	end
end

function LootServiceServer.UpdateSettlingRuntime(self: LootServiceServer, runtime: LootRuntime, now: number)
	self:RefreshRuntimePosition(runtime)
	if now - runtime.stateEnteredAt < self.settings.settleMinDuration then
		return
	end

	local linearSpeed = runtime.rootPart.AssemblyLinearVelocity.Magnitude
	local angularSpeed = runtime.rootPart.AssemblyAngularVelocity.Magnitude
	if
		linearSpeed <= self.settings.settleLinearSpeedThreshold
		and angularSpeed <= self.settings.settleAngularSpeedThreshold
	then
		if runtime.stableSince == nil then
			runtime.stableSince = now
		end
	else
		runtime.stableSince = nil
	end

	local isStableLongEnough = runtime.stableSince ~= nil
		and (now - runtime.stableSince) >= self.settings.settleStableDuration
	local exceededMaxDuration = (now - runtime.stateEnteredAt) >= self.settings.settleMaxDuration
	if isStableLongEnough or exceededMaxDuration then
		self:TransitionState(runtime, LootServiceUtils.STATE_IDLE, "Settled")
		self:RefreshRuntimePosition(runtime)
	end
end

function LootServiceServer.UpdateIdleRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	playerContexts: { PlayerContext },
	now: number
)
	self:RefreshRuntimePosition(runtime)
	if now < runtime.forceIdleUntil then
		return
	end

	local nearest = self:FindNearestEligiblePlayerContext(runtime, playerContexts, now)
	if nearest ~= nil then
		self:BeginMagnetization(runtime, nearest, now)
	end
end

function LootServiceServer.UpdateMagnetizedRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	dt: number,
	contextsByPlayer: { [Player]: PlayerContext },
	now: number
)
	local magnet = runtime.magnet
	if magnet == nil then
		self:TransitionState(runtime, LootServiceUtils.STATE_IDLE, "MissingMagnetRuntime")
		return
	end

	local targetContext = contextsByPlayer[magnet.player]
	if targetContext == nil then
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		self:TransitionState(runtime, LootServiceUtils.STATE_IDLE, "TargetMissing")
		return
	end

	local canPickup = self:CanPlayerPickupRuntime(runtime, targetContext, now)
	if not canPickup then
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		self:TransitionState(runtime, LootServiceUtils.STATE_IDLE, "TargetInvalid")
		return
	end

	magnet.elapsed += dt
	local currentPosition = runtime.lastKnownPosition
	local targetPosition = targetContext.position + Vector3.new(0, self.settings.collectOffsetY, 0)
	local toTarget = targetPosition - currentPosition
	local distance = toTarget.Magnitude
	local radiusSpan = math.max(self.settings.pickupScanRadius, EPSILON)
	local distanceRatio = math.clamp(distance / radiusSpan, 0, 1)
	local nearFactor = 1 - distanceRatio
	local distanceStrength = math.max(0.2, nearFactor)
	local accelerationStrength = 0.35 + distanceStrength * 0.65
	magnet.speed = math.min(
		self.settings.magnetMaxSpeed,
		magnet.speed + self.settings.magnetAcceleration * accelerationStrength * dt
	)
	local progress = 1 - math.clamp(distance / magnet.startDistance, 0, 1)
	local closeSpeedBoost = 1 + nearFactor * 1.6

	local springFrequency = self.settings.magnetSpringFrequency
		+ magnet.elapsed * self.settings.magnetSpringFrequencyRamp
		+ progress * self.settings.magnetSpringFrequencyCloseBoost * closeSpeedBoost
	local spring: SpringOptions = {
		frequency = springFrequency,
		damping = self.settings.magnetSpringDamping + (1 - distanceStrength) * 0.2,
	}

	magnet.xMotion:spring(targetPosition.X, spring)
	magnet.yMotion:spring(targetPosition.Y, spring)
	magnet.zMotion:spring(targetPosition.Z, spring)
	local springPosition = Vector3.new(magnet.xMotion:step(dt), magnet.yMotion:step(dt), magnet.zMotion:step(dt))

	local speedPosition =
		Vec.MoveTowards(currentPosition, targetPosition, magnet.speed * closeSpeedBoost * distanceStrength * dt)

	local nextPosition = springPosition:Lerp(speedPosition, self.settings.magnetSpeedBlend)
	self:SetRuntimePosition(runtime, nextPosition)

	local nextDistance = (targetPosition - nextPosition).Magnitude
	if nextDistance <= self.settings.collectDistance then
		self:TryCollectRuntime(runtime, targetContext.player, now)
	end
end

function LootServiceServer.UpdateRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	dt: number,
	playerContexts: { PlayerContext },
	contextsByPlayer: { [Player]: PlayerContext },
	now: number
)
	if runtime.disposed then
		return
	end
	if runtime.expiresAt <= now then
		self:TransitionState(runtime, LootServiceUtils.STATE_COLLECTED, "Expired")
		self:DisposeRuntime(runtime, "Expired")
		return
	end
	self:ApplyRuntimePlaneConstraint(runtime)

	if runtime.state == LootServiceUtils.STATE_DROPPED then
		self:UpdateDroppedRuntime(runtime, now)
		return
	end
	if runtime.state == LootServiceUtils.STATE_SETTLING then
		self:UpdateSettlingRuntime(runtime, now)
		return
	end
	if runtime.state == LootServiceUtils.STATE_IDLE then
		self:UpdateIdleRuntime(runtime, playerContexts, now)
		return
	end
	if runtime.state == LootServiceUtils.STATE_MAGNETIZED then
		self:UpdateMagnetizedRuntime(runtime, dt, contextsByPlayer, now)
		return
	end
end

function LootServiceServer.StepSimulation(self: LootServiceServer, dt: number)
	local now = os.clock()
	local playerContexts, contextsByPlayer = self:CollectPlayerContexts()
	local runtimeIds = {}
	for runtimeId in self.lootById do
		table.insert(runtimeIds, runtimeId)
	end

	for _, runtimeId in runtimeIds do
		local runtime = self.lootById[runtimeId]
		if runtime ~= nil then
			self:UpdateRuntime(runtime, dt, playerContexts, contextsByPlayer, now)
		end
	end
end

function LootServiceServer.OnHeartbeat(self: LootServiceServer, dtRaw: any)
	local dt = LootServiceUtils.CoerceNumber(dtRaw, 0, 0, 1)
	if dt <= 0 then
		return
	end

	self.simulationAccumulator += dt
	local step = self.settings.fixedStep
	local maxSteps = self.settings.maxSimulationStepsPerHeartbeat
	local steps = 0
	while self.simulationAccumulator >= step and steps < maxSteps do
		self.simulationAccumulator -= step
		steps += 1
		self:StepSimulation(step)
	end
	if steps >= maxSteps and self.simulationAccumulator >= step then
		self.simulationAccumulator = 0
	end
end

function LootServiceServer.DropFromInventorySlot(
	self: LootServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
): boolean
	if not self:CanAcceptDropRequest(player) then
		return false
	end

	local inventoryState = self.inventoryService:GetState(player)
	if not InventoryServiceUtils.IsLoadedState(inventoryState.loadState) then
		return false
	end

	local stack = InventoryServiceUtils.GetStack(inventoryState, slotIndexRaw)
	if stack == nil then
		return false
	end

	local dropAmount = LootServiceUtils.GotRopAmount(amountRaw, stack.amount)
	dropAmount = math.clamp(dropAmount, 1, stack.amount)

	local stackSnapshot: InventoryItemStack = {
		stackId = stack.stackId,
		itemId = stack.itemId,
		amount = stack.amount,
		maxStack = stack.maxStack,
		metadata = LootServiceUtils.CloneDeep(stack.metadata),
	}
	local cachedToolClones = self:CaptureDropToolClones(player, stackSnapshot.itemId, dropAmount)

	local removeResult = self.inventoryService:RemoveFromSlot(player, slotIndexRaw, dropAmount)
	if removeResult.removedAmount <= 0 then
		for _, toolClone in cachedToolClones do
			toolClone:Destroy()
		end
		return false
	end

	local dropOrigin = self:GetDropOriginForPlayer(player, throwDirectionRaw)
	local runtime = self:SpawnLootRuntime(stackSnapshot.itemId, removeResult.removedAmount, dropOrigin, {
		maxStack = stackSnapshot.maxStack,
		metadata = stackSnapshot.metadata,
		sourceType = "PlayerDrop",
		ownerUserId = player.UserId,
		ownerLockSeconds = self.settings.playerDropOwnerLockSeconds,
		throwDirection = throwDirectionRaw,
	})
	if runtime ~= nil then
		self.cache:CacheDroppedTools(runtime.id, stackSnapshot.itemId, player.UserId, cachedToolClones)
		return true
	end

	self.inventoryService:AddItem(player, stackSnapshot.itemId, removeResult.removedAmount, {
		maxStack = stackSnapshot.maxStack,
		metadata = stackSnapshot.metadata,
		stackIdPrefix = "rollback",
	})
	local targetContainer: Instance? = player:FindFirstChildOfClass("Backpack")
	if targetContainer == nil then
		targetContainer = player.Character
	end
	for _, toolClone in cachedToolClones do
		self.inventoryService:ReleaseSuppressedToolImport(player, stackSnapshot.itemId, 1)
		if targetContainer ~= nil then
			toolClone.Parent = targetContainer
		else
			toolClone:Destroy()
		end
	end
	return false
end

function LootServiceServer.CanAcceptDropRequest(self: LootServiceServer, player: Player): boolean
	local now = os.clock()
	local lastAt = self.lastDropRequestAtByPlayer[player] or -math.huge
	if now - lastAt < DROP_REQUEST_THROTTLE_SECONDS then
		return false
	end
	self.lastDropRequestAtByPlayer[player] = now
	return true
end

function LootServiceServer.RequestSync(_self: LootServiceServer, _player: Player) end

function LootServiceServer.RequestDropFromSlot(
	self: LootServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	self:DropFromInventorySlot(player, slotIndexRaw, amountRaw, throwDirectionRaw)
end

function LootServiceServer.RequestDropSelectedSlot(
	self: LootServiceServer,
	player: Player,
	amountRaw: any,
	throwDirectionRaw: any
)
	local inventoryState = self.inventoryService:GetState(player)
	if not InventoryServiceUtils.IsLoadedState(inventoryState.loadState) then
		return
	end
	local selectedSlot = inventoryState.selectedSlot
	if selectedSlot == nil then
		return
	end
	self:DropFromInventorySlot(player, selectedSlot, amountRaw, throwDirectionRaw)
end

function LootServiceServer.Init(self: LootServiceServer)
	bindPackets(self)
	self.inventoryService = InventoryServiceServer :: InventoryServiceServerObject
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.soundService = AudioServiceServer :: AudioServiceServerObject
	self.data = LootServiceData
	self.settings = LootServiceUtils.GetSettings(self.data)
	self.random = Random.new()
	self.cache = LootServiceCache.New()
	self.lootById = {}
	self.itemTemplateByItemId = {}
	self.itemPickupSoundAssetIds = {} :: { string }
	self.coinDropSoundAssetIds = {} :: { string }
	self.coinPickupSoundAssetIds = {} :: { string }
	self:RefreshPickupSoundTemplates()
	self.lastDropRequestAtByPlayer = {}
	self.simulationAccumulator = 0
	self.lootFolder = self:EnsureLootFolder()
	self.binders = NevermoreSupport.GetService(BinderSupportServer)

	self.inventoryService:SetDropFromSlotHandler(
		function(player: Player, slotIndexRaw: any, amountRaw: any, throwDirectionRaw: any)
			return self:DropFromInventorySlot(player, slotIndexRaw, amountRaw, throwDirectionRaw)
		end
	)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self.lastDropRequestAtByPlayer[player] = nil
	end)
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:OnHeartbeat(dt)
	end)
end

function LootServiceServer.Destroy(self: LootServiceServer)
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	self.inventoryService:SetDropFromSlotHandler(nil)

	local runtimeIds = {}
	for runtimeId in self.lootById do
		table.insert(runtimeIds, runtimeId)
	end
	for _, runtimeId in runtimeIds do
		self:RemoveRuntimeById(runtimeId, "Cleanup")
	end
	local cache = self.cache :: LootServiceCacheObject?
	if cache ~= nil then
		cache:Destroy()
	end

	self.soundService = nil
end
type LootServiceServer = typeof(LootServiceServer) & {
	inventoryService: InventoryServiceServerObject,
	playerDataService: PlayerDataServiceServerObject,
	soundService: AudioServiceServerObject?,
	data: { [string]: any },
	settings: LootSettings,
	random: Random,
	cache: LootServiceCacheObject,
	lootFolder: Folder,
	lootById: { [string]: LootRuntime },
	itemTemplateByItemId: { [string]: Instance | boolean },
	itemPickupSoundAssetIds: { string },
	coinDropSoundAssetIds: { string },
	coinPickupSoundAssetIds: { string },
	lastDropRequestAtByPlayer: { [Player]: number },
	simulationAccumulator: number,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
	binders: any,
}

return LootServiceServer :: LootServiceServer
