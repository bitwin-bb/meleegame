--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Ripple = require(ReplicatedStorage.Packages.Ripple)
local Networker = require(ReplicatedStorage.Packages.Networker)
local AudioRegistry = require(ReplicatedStorage.Shared.Modules.Items.Audio)
local StringUtils = require(ReplicatedStorage.Shared.Modules.Core.StringUtils)
local InstanceUtils = require(ReplicatedStorage.Shared.Modules.Platform.InstanceUtils)
local ResolveItem = require(ReplicatedStorage.Shared.Modules.Game.ResolveItem)
local ResolveToolInstance = require(ReplicatedStorage.Shared.Modules.Game.ResolveToolInstance)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local LootServiceData = require(ReplicatedStorage.Shared.Services.LootService.Data)
local LootServiceUtils = require(ReplicatedStorage.Shared.Services.LootService.LootServiceUtils)
local AudioServiceUtils = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceUtils)
local InventoryServiceServer = require(ServerScriptService.Services.InventoryService.InventoryServiceServer)
local PlayerDataServiceServer = require(ServerScriptService.Services.PlayerDataService.PlayerDataServiceServer)
local AudioServiceServer = require(ServerScriptService.Services.AudioService.AudioServiceServer)
local LootServiceCache = require(ReplicatedStorage.Shared.Services.LootService.Cache)

type NumberMotion = Ripple.Motion<number>
type SpringOptions = Ripple.SpringOptions

type LootState = LootServiceUtils.LootState
type LootSettings = LootServiceUtils.LootSettings
type LootMetadata = LootServiceUtils.LootMetadata
type LootRollContext = LootServiceUtils.LootRollContext
type LootRarity = LootServiceUtils.LootRarity
type LootRollResult = LootServiceUtils.LootRollResult

type InventoryState = InventoryServiceUtils.InventoryState
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack
type AddItemResult = InventoryServiceUtils.AddItemResult
type SlotMutationResult = InventoryServiceUtils.SlotMutationResult

type InventoryServiceServerObject = {
	getState: (self: InventoryServiceServerObject, player: Player) -> InventoryState,
	addItem: (
		self: InventoryServiceServerObject,
		player: Player,
		itemIdRaw: any,
		amountRaw: any,
		optionsRaw: any
	) -> AddItemResult,
	removeFromSlot: (
		self: InventoryServiceServerObject,
		player: Player,
		slotIndexRaw: any,
		amountRaw: any
	) -> SlotMutationResult,
	releaseSuppressedToolImport: (
		self: InventoryServiceServerObject,
		player: Player,
		itemIdRaw: any,
		amountRaw: any
	) -> number,
	setDropFromSlotHandler: (self: InventoryServiceServerObject, handlerRaw: any) -> (),
}

type PlayerDataServiceServerObject = {
	incrementValue: (
		self: PlayerDataServiceServerObject,
		player: Player,
		pathRaw: any,
		amountRaw: any,
		fallbackValueRaw: any,
		replicateToClientRaw: any
	) -> number?,
}

type AudioServiceServerObject = {
	playSfxForPlayer: (
		self: AudioServiceServerObject,
		player: Player,
		soundAssetIdRaw: any,
		optionsRaw: any
	) -> (),
	playSfxForAll: (self: AudioServiceServerObject, soundAssetIdRaw: any, optionsRaw: any) -> (),
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
local FALLBACK_LOOT_COLOR_BY_RARITY: { [LootRarity]: Color3 } = {
	Common = Color3.fromRGB(202, 202, 202),
	Uncommon = Color3.fromRGB(102, 210, 132),
	Rare = Color3.fromRGB(110, 166, 255),
	Epic = Color3.fromRGB(191, 118, 255),
	Legendary = Color3.fromRGB(255, 191, 97),
}
local FALLBACK_LOOT_DEFAULT_COLOR = Color3.fromRGB(220, 220, 220)
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
local LOOT_AUDIO = (AudioRegistry :: any).Loot or {}
local LOOT_ITEM_PICKUP_AUDIO = LOOT_AUDIO.ItemPickup or {}
local LOOT_COIN_DROP_AUDIO = LOOT_AUDIO.CoinDrop or {}
local LOOT_COIN_PICKUP_AUDIO = LOOT_AUDIO.CoinPickup or {}
local LOOT_PICKUP_VOLUME = 1.5

local function sanitizeOwnerUserId(userIdRaw: any): number?
	if typeof(userIdRaw) ~= "number" or userIdRaw ~= userIdRaw then
		return nil
	end
	local userId = math.floor(userIdRaw)
	if userId <= 0 then
		return nil
	end
	return userId
end

local function resolvePlayerRootPart(player: Player): BasePart?
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

	local direction = LootServiceUtils.sanitizeVector3(directionRaw, fallback)
	if direction.Magnitude <= EPSILON then
		return fallback.Unit
	end
	return direction.Unit
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

function LootServiceServer.cacheToolTemplateIfPossible(self: LootServiceServer, itemId: string, template: Instance?)
	if template == nil then
		return
	end
	if template:IsA("Tool") then
		self.cache:rememberToolTemplate(itemId, template)
	end
end

function LootServiceServer.isToolMatchingItemId(self: LootServiceServer, tool: Tool, itemIdRaw: any): boolean
	local itemId = LootServiceUtils.sanitizeString(itemIdRaw, nil)
	if itemId == nil then
		return false
	end

	local targetTokens: { [string]: boolean } = {}
	for _, candidate in LootServiceUtils.resolveItemNameCandidates(self.data, itemId) do
		local token = StringUtils.compactToken(candidate)
		if token ~= "" then
			targetTokens[token] = true
		end
	end
	if next(targetTokens) == nil then
		targetTokens[StringUtils.compactToken(itemId)] = true
	end

	local resolvedToolItemId = ResolveToolInstance.resolveToolItemId(tool)
	local idCandidates = {
		resolvedToolItemId,
		tool:GetAttribute("itemId"),
		tool:GetAttribute("ItemId"),
		tool:GetAttribute("ittemId"),
		tool.Name,
	}
	for _, candidate in idCandidates do
		local candidateToken = StringUtils.compactToken(candidate)
		if candidateToken ~= "" and targetTokens[candidateToken] == true then
			return true
		end
	end
	return false
end

function LootServiceServer.captureDropToolClones(
	self: LootServiceServer,
	player: Player,
	itemIdRaw: any,
	amountRaw: any
): { Tool }
	local itemId = LootServiceUtils.sanitizeString(itemIdRaw, nil)
	if itemId == nil then
		return {}
	end

	local amount = LootServiceUtils.resolveDropAmount(amountRaw, 1)
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
			if not self:isToolMatchingItemId(child, itemId) then
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

function LootServiceServer.restoreCachedDropTools(
	self: LootServiceServer,
	player: Player,
	runtime: LootRuntime,
	amountRaw: any
)
	local amount = LootServiceUtils.resolveDropAmount(amountRaw, 1)
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
		local tool = self.cache:popDroppedTool(runtime.id, runtime.itemId)
		if tool == nil then
			tool = self.cache:cloneToolTemplate(runtime.itemId)
			if tool ~= nil then
				tool:SetAttribute("itemId", runtime.itemId)
				tool:SetAttribute("ItemId", runtime.itemId)
				local metadata = runtime.metadata
				if typeof(metadata) == "table" then
					local itemType = LootServiceUtils.sanitizeString((metadata :: { [string]: any }).itemType, nil)
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

		self.inventoryService:releaseSuppressedToolImport(player, runtime.itemId, 1)
		tool.Parent = targetContainer
		remaining -= 1
	end
end

function LootServiceServer.resolveCoinTypeFromItemId(
	self: LootServiceServer,
	itemIdRaw: any
): ("copper" | "silver" | "gold" | "platinum")?
	local itemId = LootServiceUtils.sanitizeString(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local itemToken = StringUtils.compactToken(itemId)
	local mapped = COIN_TYPE_BY_ITEM_TOKEN[itemToken]
	if mapped ~= nil then
		return mapped
	end

	for _, candidate in LootServiceUtils.resolveItemNameCandidates(self.data, itemId) do
		local token = StringUtils.compactToken(candidate)
		local byToken = COIN_TYPE_BY_ITEM_TOKEN[token]
		if byToken ~= nil then
			return byToken
		end
	end

	return nil
end

function LootServiceServer.shouldRouteRuntimeToCoinWallet(self: LootServiceServer, runtime: LootRuntime): boolean
	if runtime.sourceType == "PlayerDrop" then
		return false
	end
	return self:resolveCoinTypeFromItemId(runtime.itemId) ~= nil
end

function LootServiceServer.tryCollectRuntimeToCoinWallet(
	self: LootServiceServer,
	runtime: LootRuntime,
	player: Player
): boolean
	local coinType = self:resolveCoinTypeFromItemId(runtime.itemId)
	if coinType == nil then
		return false
	end

	local amount = math.max(1, math.floor(runtime.amount))
	local nextValue = self.playerDataService:incrementValue(player, { "coins", coinType }, amount, 0, true)
	if nextValue == nil then
		return false
	end

	self:playPickupSound(runtime, player)
	self:transitionState(runtime, LootServiceUtils.STATE_COLLECTED, "CollectedCoinWallet")
	self:disposeRuntime(runtime, "CollectedCoinWallet")
	return true
end

function LootServiceServer.ensureLootFolder(self: LootServiceServer): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(LOOT_FOLDER_NAME)
end

function LootServiceServer.refreshPickupSoundTemplates(self: LootServiceServer)
	self.itemPickupSoundAssetIds = AudioServiceUtils.collectSoundAssetIds(LOOT_ITEM_PICKUP_AUDIO)
	self.coinDropSoundAssetIds = AudioServiceUtils.collectSoundAssetIds(LOOT_COIN_DROP_AUDIO)
	self.coinPickupSoundAssetIds = AudioServiceUtils.collectSoundAssetIds(LOOT_COIN_PICKUP_AUDIO)
end

function LootServiceServer.playCoinDropSound(self: LootServiceServer, runtime: LootRuntime)
	local soundService = self.soundService
	if soundService == nil or (soundService :: any).networker == nil then
		return
	end

	if #self.coinDropSoundAssetIds <= 0 then
		self:refreshPickupSoundTemplates()
	end

	local soundAssetId = pickRandomSoundAssetId(self.random, self.coinDropSoundAssetIds)
	if soundAssetId == nil then
		return
	end
	if runtime.rootPart.Parent == nil then
		return
	end

	soundService:playSfxForAll(soundAssetId, {
		category = "SFX",
		parent = runtime.rootPart,
		autoDestroy = true,
	})
end

function LootServiceServer.playPickupSound(self: LootServiceServer, runtime: LootRuntime, player: Player)
	local soundService = self.soundService
	if soundService == nil or (soundService :: any).networker == nil then
		return
	end

	if #self.itemPickupSoundAssetIds <= 0 and #self.coinPickupSoundAssetIds <= 0 then
		self:refreshPickupSoundTemplates()
	end

	local soundAssetId: string?
	if self:resolveCoinTypeFromItemId(runtime.itemId) ~= nil then
		soundAssetId = pickRandomSoundAssetId(self.random, self.coinPickupSoundAssetIds)
	else
		soundAssetId = pickRandomSoundAssetId(self.random, self.itemPickupSoundAssetIds)
	end
	if soundAssetId == nil then
		return
	end

	local parent: Instance? = resolvePlayerRootPart(player)
	if parent == nil then
		parent = player.Character
	end

	soundService:playSfxForPlayer(player, soundAssetId, {
		category = "SFX",
		volume = LOOT_PICKUP_VOLUME,
		parent = parent,
		autoDestroy = true,
	})
end

function LootServiceServer.resolveItemTemplate(self: LootServiceServer, itemIdRaw: any): Instance?
	local itemId = LootServiceUtils.sanitizeString(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local cached = self.itemTemplateByItemId[itemId]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		local cachedInstance = cached :: Instance
		if cachedInstance.Parent ~= nil then
			self:cacheToolTemplateIfPossible(itemId, cachedInstance)
			self:cacheToolTemplateIfPossible(itemId, ResolveItem.resolveToolTemplate(itemId))
			return cachedInstance
		end
		self.itemTemplateByItemId[itemId] = nil
	end

	local resolvedTemplate = ResolveItem.resolvePrimaryTemplate(itemId)
	if resolvedTemplate ~= nil then
		self.itemTemplateByItemId[itemId] = resolvedTemplate
		self:cacheToolTemplateIfPossible(itemId, resolvedTemplate)
		self:cacheToolTemplateIfPossible(itemId, ResolveItem.resolveToolTemplate(itemId))
		return resolvedTemplate
	end

	self.itemTemplateByItemId[itemId] = false
	return nil
end

function LootServiceServer.cloneLootInstanceFromTemplate(
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
	local rootPart = InstanceUtils.resolveInstanceRootPart(clone, true)
	if rootPart == nil then
		clone:Destroy()
		return nil, nil
	end

	return clone, rootPart
end

function LootServiceServer.resolveFallbackLootColor(self: LootServiceServer, rarityRaw: any): Color3
	if
		rarityRaw == "Common"
		or rarityRaw == "Uncommon"
		or rarityRaw == "Rare"
		or rarityRaw == "Epic"
		or rarityRaw == "Legendary"
	then
		local rarity = rarityRaw :: LootRarity
		return FALLBACK_LOOT_COLOR_BY_RARITY[rarity] or FALLBACK_LOOT_DEFAULT_COLOR
	end
	return FALLBACK_LOOT_DEFAULT_COLOR
end

function LootServiceServer.createFallbackLootInstance(
	self: LootServiceServer,
	itemIdRaw: any,
	rarityRaw: any
): (Instance?, BasePart?)
	local itemId = LootServiceUtils.sanitizeString(itemIdRaw, "Loot") or "Loot"
	local rarity = LootServiceUtils.sanitizeRarity(rarityRaw, "Common")
	local token = string.lower(itemId)

	local part = Instance.new("Part")
	part.Name = itemId
	part.Material = Enum.Material.SmoothPlastic
	part.Color = self:resolveFallbackLootColor(rarity)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(1, 1, 1)
	part:SetAttribute("FallbackLootTemplate", true)
	part:SetAttribute("FallbackItemId", itemId)
	part:SetAttribute("FallbackRarity", rarity)

	if string.find(token, "coin", 1, true) ~= nil then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.2, 0.8, 0.8)
	elseif string.find(token, "sword", 1, true) ~= nil then
		part.Size = Vector3.new(0.25, 2.3, 0.25)
	elseif string.find(token, "crystal", 1, true) ~= nil then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.1, 1.1, 1.1)
	else
		part.Size = Vector3.new(1, 1, 1)
	end

	return part, part
end

function LootServiceServer.warnMissingTemplateOnce(self: LootServiceServer, itemId: string)
	if self.missingTemplateWarnedByItemId[itemId] == true then
		return
	end
	self.missingTemplateWarnedByItemId[itemId] = true
	warn(
		(
			"[LootService] Missing loot template for item '%s'; using fallback part. "
			.. "Add an item model under ReplicatedStorage.Assets (or configured assetSearchRoots)."
		):format(itemId)
	)
end

function LootServiceServer.resolveRuntimePlaneX(self: LootServiceServer, runtime: LootRuntime): number?
	if self.settings.lockTo2DPlane ~= true then
		return nil
	end
	return runtime.lockedPlaneX
end

function LootServiceServer.clampPositionToRuntimePlane(
	self: LootServiceServer,
	runtime: LootRuntime,
	positionRaw: Vector3
): Vector3
	local planeX = self:resolveRuntimePlaneX(runtime)
	if planeX == nil then
		return positionRaw
	end
	return Vector3.new(planeX, positionRaw.Y, positionRaw.Z)
end

function LootServiceServer.applyRuntimePlaneConstraint(self: LootServiceServer, runtime: LootRuntime)
	local planeX = self:resolveRuntimePlaneX(runtime)
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
	if math.abs(rootPosition.X - planeX) > EPSILON then
		local pivot = runtime.instance:GetPivot()
		local rotationOnly = pivot - pivot.Position
		runtime.instance:PivotTo(CFrame.new(planeX, rootPosition.Y, rootPosition.Z) * rotationOnly)
	end

	local updatedRootPosition = runtime.rootPart.Position
	runtime.lastKnownPosition = Vector3.new(planeX, updatedRootPosition.Y, updatedRootPosition.Z)
end

function LootServiceServer.setRuntimePosition(self: LootServiceServer, runtime: LootRuntime, positionRaw: any)
	local position = LootServiceUtils.sanitizeVector3(positionRaw, runtime.lastKnownPosition)
	position = self:clampPositionToRuntimePlane(runtime, position)
	if runtime.disposed then
		return
	end

	local pivot = runtime.instance:GetPivot()
	local rotationOnly = pivot - pivot.Position
	runtime.instance:PivotTo(CFrame.new(position) * rotationOnly)
	runtime.lastKnownPosition = position
end

function LootServiceServer.refreshRuntimePosition(self: LootServiceServer, runtime: LootRuntime)
	if runtime.disposed then
		return
	end
	if runtime.rootPart.Parent == nil then
		return
	end
	local position = runtime.rootPart.Position
	runtime.lastKnownPosition = self:clampPositionToRuntimePlane(runtime, position)
end

function LootServiceServer.applyRuntimeAttributes(self: LootServiceServer, runtime: LootRuntime, reasonRaw: any?)
	local reason = LootServiceUtils.sanitizeString(reasonRaw, nil)
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

function LootServiceServer.setRuntimePhysics(
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
			local current = part.CustomPhysicalProperties
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

function LootServiceServer.destroyMagnetRuntime(self: LootServiceServer, runtime: LootRuntime)
	local magnet = runtime.magnet
	if magnet == nil then
		return
	end

	magnet.xMotion:destroy()
	magnet.yMotion:destroy()
	magnet.zMotion:destroy()
	runtime.magnet = nil
end

function LootServiceServer.transitionState(
	self: LootServiceServer,
	runtime: LootRuntime,
	nextStateRaw: any,
	reasonRaw: any?
): boolean
	local currentState = runtime.state
	local nextState = LootServiceUtils.sanitizeState(nextStateRaw, currentState)
	if currentState == nextState then
		return true
	end

	if not LootServiceUtils.isAllowedStateTransition(currentState, nextState) then
		warn(
			("[LootService] Rejected invalid loot transition %s -> %s for %s."):format(
				tostring(currentState),
				tostring(nextState),
				runtime.id
			)
		)
		return false
	end

	runtime.state = nextState
	runtime.stateEnteredAt = os.clock()
	runtime.stableSince = nil

	if nextState ~= LootServiceUtils.STATE_MAGNETIZED then
		self:destroyMagnetRuntime(runtime)
	end

	if nextState == LootServiceUtils.STATE_DROPPED or nextState == LootServiceUtils.STATE_SETTLING then
		self:setRuntimePhysics(runtime, false, true, true, true, true)
	elseif nextState == LootServiceUtils.STATE_IDLE then
		self:setRuntimePhysics(runtime, true, true, true, true, false)
		runtime.rootPart.AssemblyLinearVelocity = Vector3.zero
		runtime.rootPart.AssemblyAngularVelocity = Vector3.zero
	elseif nextState == LootServiceUtils.STATE_MAGNETIZED then
		self:setRuntimePhysics(runtime, true, false, false, false, false)
	elseif nextState == LootServiceUtils.STATE_COLLECTED then
		self:setRuntimePhysics(runtime, true, false, false, false, false)
	end

	self:applyRuntimeAttributes(runtime, reasonRaw)
	return true
end

function LootServiceServer.disposeRuntime(self: LootServiceServer, runtime: LootRuntime, reasonRaw: any?)
	if runtime.disposed then
		return
	end

	runtime.disposed = true
	self.lootById[runtime.id] = nil
	self.cache:discardDroppedTools(runtime.id)
	self:destroyMagnetRuntime(runtime)
	if runtime.destroyConnection ~= nil then
		runtime.destroyConnection:Disconnect()
		runtime.destroyConnection = nil
	end
	self:applyRuntimeAttributes(runtime, reasonRaw)
	if runtime.instance.Parent ~= nil then
		runtime.instance:Destroy()
	end
end

function LootServiceServer.removeRuntimeById(self: LootServiceServer, lootIdRaw: any, reasonRaw: any?)
	local lootId = LootServiceUtils.sanitizeString(lootIdRaw, nil)
	if lootId == nil then
		return
	end
	local runtime = self.lootById[lootId]
	if runtime == nil then
		return
	end

	self:transitionState(runtime, LootServiceUtils.STATE_COLLECTED, reasonRaw)
	self:disposeRuntime(runtime, reasonRaw)
end

function LootServiceServer.applyDropImpulse(self: LootServiceServer, runtime: LootRuntime, throwDirectionRaw: any)
	local isPlaneLocked = self:resolveRuntimePlaneX(runtime) ~= nil
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

	local itemToken = StringUtils.compactToken(runtime.itemId)
	local linearScale = 1
	local angularScale = 1
	local maxLinearSpeed: number? = nil

	if itemToken == KATANA_DROP_TOKEN then
		linearScale = 0.28
		angularScale = 0.05
		maxLinearSpeed = 10
	elseif runtime.sourceType == "PlayerDrop" and runtime.maxStack <= 1 then
		linearScale = 0.5
		angularScale = 0.2
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

	local angularVelocity = Vector3.new(
		self.random:NextNumber(-1, 1),
		self.random:NextNumber(-1, 1),
		self.random:NextNumber(-1, 1)
	) * self.settings.dropAngularVelocity * angularScale

	runtime.rootPart.AssemblyLinearVelocity = linearVelocity
	runtime.rootPart.AssemblyAngularVelocity = angularVelocity
end

function LootServiceServer.toPublicSnapshot(self: LootServiceServer, runtime: LootRuntime): { [string]: any }
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

function LootServiceServer.spawnLootRuntime(
	self: LootServiceServer,
	itemIdRaw: any,
	amountRaw: any,
	positionRaw: any,
	optionsRaw: any
): LootRuntime?
	local itemId = LootServiceUtils.sanitizeString(itemIdRaw, nil)
	if itemId == nil then
		return nil
	end

	local itemConfig = LootServiceUtils.resolveItemConfig(self.data, itemId)
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local amount = LootServiceUtils.sanitizeInteger(amountRaw, 1, 1, 999999)
	local maxStack = LootServiceUtils.sanitizeInteger((options :: any).maxStack, itemConfig.maxStack, 1, 999999)
	local rarity = LootServiceUtils.sanitizeRarity((options :: any).rarity, itemConfig.rarity)
	local sourceType = LootServiceUtils.sanitizeString((options :: any).sourceType, "Generic") or "Generic"
	local metadata = if typeof((options :: any).metadata) == "table"
		then LootServiceUtils.cloneDeep((options :: any).metadata)
		else nil
	local ownerUserId = sanitizeOwnerUserId((options :: any).ownerUserId)
	local ownerLockSeconds =
		LootServiceUtils.sanitizeNumber((options :: any).ownerLockSeconds, self.settings.ownerLockSeconds, 0, 120)
	local now = os.clock()
	local expiresAt = now
		+ LootServiceUtils.sanitizeNumber((options :: any).despawnSeconds, self.settings.despawnSeconds, 0.1, 3600)
	local requestedLootId = LootServiceUtils.sanitizeString((options :: any).lootId, nil)
	local lootId = requestedLootId or LootServiceUtils.createLootId(self.random, itemId)

	local template = self:resolveItemTemplate(itemId)
	local instance: Instance? = nil
	local rootPart: BasePart? = nil

	if template ~= nil then
		instance, rootPart = self:cloneLootInstanceFromTemplate(template, itemId)
	end
	if instance == nil or rootPart == nil then
		if template == nil then
			self:warnMissingTemplateOnce(itemId)
		else
			warn(("[LootService] Failed cloning loot template for item '%s'; using fallback part."):format(itemId))
		end
		instance, rootPart = self:createFallbackLootInstance(itemId, rarity)
	end

	if instance == nil or rootPart == nil then
		warn(("[LootService] Failed creating fallback loot for item '%s'; drop skipped."):format(itemId))
		return nil
	end

	if self.lootById[lootId] ~= nil then
		self:removeRuntimeById(lootId, "Replaced")
	end

	instance.Name = ("Loot_%s"):format(itemId)
	instance.Parent = self.lootFolder

	local spawnPosition = LootServiceUtils.sanitizeVector3(positionRaw, Vector3.zero)
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
		stableSince = nil,
		forceIdleUntil = -math.huge,
		magnet = nil,
		disposed = false,
		destroyConnection = nil,
	}

	self.lootById[lootId] = runtime
	self:setRuntimePosition(runtime, spawnPosition)
	self:setRuntimePhysics(runtime, false, true, true, true, true)
	self:applyDropImpulse(runtime, (options :: any).throwDirection)
	self:applyRuntimeAttributes(runtime, "Spawned")
	if self:resolveCoinTypeFromItemId(itemId) ~= nil then
		self:playCoinDropSound(runtime)
	end

	runtime.destroyConnection = runtime.instance.Destroying:Connect(function()
		local liveRuntime = self.lootById[lootId]
		if liveRuntime == nil or liveRuntime.disposed then
			return
		end
		liveRuntime.disposed = true
		self.lootById[lootId] = nil
		self:destroyMagnetRuntime(liveRuntime)
	end)

	return runtime
end

function LootServiceServer.getDropOriginForPlayer(
	self: LootServiceServer,
	player: Player,
	throwDirectionRaw: any
): Vector3
	local rootPart = resolvePlayerRootPart(player)
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

function LootServiceServer.spawnDropsFromTable(
	self: LootServiceServer,
	dropTableIdRaw: any,
	originRaw: any,
	optionsRaw: any
): { [string]: any }
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local onlyCoinLoot = (options :: any).onlyCoinLoot == true
	local origin = LootServiceUtils.sanitizeVector3(originRaw, Vector3.zero)
	local context = if typeof((options :: any).context) == "table" then shallowCopy((options :: any).context) else {}
	local mutableContext = context :: any
	local sourceType = LootServiceUtils.sanitizeString((options :: any).sourceType, nil)
	if sourceType ~= nil then
		mutableContext.sourceType = sourceType
	end

	local drops: { LootRollResult } =
		LootServiceUtils.rollDropTable(self.data, dropTableIdRaw, self.random, context :: LootRollContext)
	local ownerUserId = sanitizeOwnerUserId((options :: any).ownerUserId)
	local ownerLockSeconds =
		LootServiceUtils.sanitizeNumber((options :: any).ownerLockSeconds, self.settings.ownerLockSeconds, 0, 120)

	local output = {}
	for _, drop in drops do
		if onlyCoinLoot and self:resolveCoinTypeFromItemId(drop.itemId) == nil then
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

		local runtime = self:spawnLootRuntime(drop.itemId, drop.amount, spawnPosition, {
			maxStack = drop.maxStack,
			metadata = drop.metadata,
			rarity = drop.rarity,
			sourceType = drop.sourceType,
			ownerUserId = ownerUserId,
			ownerLockSeconds = ownerLockSeconds,
			throwDirection = throwDirection,
		})
		if runtime ~= nil then
			table.insert(output, self:toPublicSnapshot(runtime))
		end
	end

	return output
end

function LootServiceServer.spawnDropsFromSource(
	self: LootServiceServer,
	sourceRaw: any,
	originRaw: any,
	optionsRaw: any
): { [string]: any }
	local dropTableId = LootServiceUtils.resolveDropTableId(self.data, sourceRaw, "Slime")
	if dropTableId == nil then
		return {}
	end

	local options = if typeof(optionsRaw) == "table" then shallowCopy(optionsRaw) else {}
	local mutableOptions = options :: any
	local sourceType = LootServiceUtils.sanitizeString(mutableOptions.sourceType, nil)
	if sourceType == nil then
		if typeof(sourceRaw) == "string" then
			sourceType = sourceRaw
		elseif typeof(sourceRaw) == "table" then
			local source = sourceRaw :: { [string]: any }
			sourceType = LootServiceUtils.sanitizeString(source.sourceType, nil)
				or LootServiceUtils.sanitizeString(source.npcType, nil)
				or LootServiceUtils.sanitizeString(source.displayName, nil)
		end
	end
	mutableOptions.sourceType = sourceType or dropTableId
	mutableOptions.onlyCoinLoot = true

	return self:spawnDropsFromTable(dropTableId, originRaw, options)
end

function LootServiceServer.canPlayerPickupRuntime(
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

function LootServiceServer.collectPlayerContexts(
	self: LootServiceServer
): ({ PlayerContext }, { [Player]: PlayerContext })
	local contexts = {}
	local contextsByPlayer = {}
	for _, player in Players:GetPlayers() do
		local rootPart = resolvePlayerRootPart(player)
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

function LootServiceServer.findNearestEligiblePlayerContext(
	self: LootServiceServer,
	runtime: LootRuntime,
	playerContexts: { PlayerContext },
	now: number
): PlayerContext?
	local nearest: PlayerContext? = nil
	local nearestDistance = math.huge
	for _, context in playerContexts do
		local canPickup = self:canPlayerPickupRuntime(runtime, context, now)
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

function LootServiceServer.beginMagnetization(
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

	if not self:transitionState(runtime, LootServiceUtils.STATE_MAGNETIZED, "PickupEligible") then
		self:destroyMagnetRuntime(runtime)
		return false
	end
	return true
end

function LootServiceServer.canInventoryAcceptRuntime(
	self: LootServiceServer,
	player: Player,
	runtime: LootRuntime
): boolean
	local inventoryState = self.inventoryService:getState(player)
	if not InventoryServiceUtils.isLoadedState(inventoryState.loadState) then
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
		if not LootServiceUtils.deepEqual(stack.metadata, runtime.metadata) then
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

function LootServiceServer.tryCollectRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	player: Player,
	now: number
): boolean
	if runtime.disposed or runtime.state ~= LootServiceUtils.STATE_MAGNETIZED then
		return false
	end

	if self:shouldRouteRuntimeToCoinWallet(runtime) then
		local didCollectToWallet = self:tryCollectRuntimeToCoinWallet(runtime, player)
		if didCollectToWallet then
			return true
		end
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		return self:transitionState(runtime, LootServiceUtils.STATE_IDLE, "CoinWalletUnavailable")
	end

	if not self:canInventoryAcceptRuntime(player, runtime) then
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		return self:transitionState(runtime, LootServiceUtils.STATE_IDLE, "InventoryFull")
	end

	local addResult = self.inventoryService:addItem(player, runtime.itemId, runtime.amount, {
		maxStack = runtime.maxStack,
		metadata = LootServiceUtils.cloneDeep(runtime.metadata),
		stackIdPrefix = "loot",
	})
	local addedAmount = math.clamp(addResult.added, 0, runtime.amount)
	if addedAmount > 0 then
		self:restoreCachedDropTools(player, runtime, addedAmount)
		self:playPickupSound(runtime, player)
	end
	if addedAmount ~= runtime.amount then
		warn(
			("[LootService] Non-atomic inventory mutation detected for loot %s (%s). Added %d of %d; preserving leftover in world state."):format(
				runtime.id,
				runtime.itemId,
				addedAmount,
				runtime.amount
			)
		)
		if addedAmount > 0 then
			runtime.amount -= addedAmount
		end
		if runtime.amount <= 0 then
			self:transitionState(runtime, LootServiceUtils.STATE_COLLECTED, "Collected")
			self:disposeRuntime(runtime, "Collected")
			return true
		end
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		return self:transitionState(runtime, LootServiceUtils.STATE_IDLE, "PartialCollect")
	end

	self:transitionState(runtime, LootServiceUtils.STATE_COLLECTED, "Collected")
	self:disposeRuntime(runtime, "Collected")
	return true
end

function LootServiceServer.updateDroppedRuntime(self: LootServiceServer, runtime: LootRuntime, now: number)
	if now - runtime.stateEnteredAt >= self.settings.droppedStateDuration then
		self:transitionState(runtime, LootServiceUtils.STATE_SETTLING, "DroppedImpulseComplete")
	end
end

function LootServiceServer.updateSettlingRuntime(self: LootServiceServer, runtime: LootRuntime, now: number)
	self:refreshRuntimePosition(runtime)
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
		self:transitionState(runtime, LootServiceUtils.STATE_IDLE, "Settled")
		self:refreshRuntimePosition(runtime)
	end
end

function LootServiceServer.updateIdleRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	playerContexts: { PlayerContext },
	now: number
)
	self:refreshRuntimePosition(runtime)
	if now < runtime.forceIdleUntil then
		return
	end

	local nearest = self:findNearestEligiblePlayerContext(runtime, playerContexts, now)
	if nearest ~= nil then
		self:beginMagnetization(runtime, nearest, now)
	end
end

function LootServiceServer.updateMagnetizedRuntime(
	self: LootServiceServer,
	runtime: LootRuntime,
	dt: number,
	contextsByPlayer: { [Player]: PlayerContext },
	now: number
)
	local magnet = runtime.magnet
	if magnet == nil then
		self:transitionState(runtime, LootServiceUtils.STATE_IDLE, "MissingMagnetRuntime")
		return
	end

	local targetContext = contextsByPlayer[magnet.player]
	if targetContext == nil then
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		self:transitionState(runtime, LootServiceUtils.STATE_IDLE, "TargetMissing")
		return
	end

	local canPickup = self:canPlayerPickupRuntime(runtime, targetContext, now)
	if not canPickup then
		runtime.forceIdleUntil = now + self.settings.magnetCooldownAfterFailedCollect
		self:transitionState(runtime, LootServiceUtils.STATE_IDLE, "TargetInvalid")
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

	local speedPosition = currentPosition
	if distance > EPSILON then
		local maxStep = magnet.speed * closeSpeedBoost * distanceStrength * dt
		speedPosition += toTarget.Unit * math.min(maxStep, distance)
	end

	local nextPosition = springPosition:Lerp(speedPosition, self.settings.magnetSpeedBlend)
	self:setRuntimePosition(runtime, nextPosition)

	local nextDistance = (targetPosition - nextPosition).Magnitude
	if nextDistance <= self.settings.collectDistance then
		self:tryCollectRuntime(runtime, targetContext.player, now)
	end
end

function LootServiceServer.updateRuntime(
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
		self:transitionState(runtime, LootServiceUtils.STATE_COLLECTED, "Expired")
		self:disposeRuntime(runtime, "Expired")
		return
	end
	self:applyRuntimePlaneConstraint(runtime)

	if runtime.state == LootServiceUtils.STATE_DROPPED then
		self:updateDroppedRuntime(runtime, now)
		return
	end
	if runtime.state == LootServiceUtils.STATE_SETTLING then
		self:updateSettlingRuntime(runtime, now)
		return
	end
	if runtime.state == LootServiceUtils.STATE_IDLE then
		self:updateIdleRuntime(runtime, playerContexts, now)
		return
	end
	if runtime.state == LootServiceUtils.STATE_MAGNETIZED then
		self:updateMagnetizedRuntime(runtime, dt, contextsByPlayer, now)
		return
	end
end

function LootServiceServer.stepSimulation(self: LootServiceServer, dt: number)
	local now = os.clock()
	local playerContexts, contextsByPlayer = self:collectPlayerContexts()
	local runtimeIds = {}
	for runtimeId in self.lootById do
		table.insert(runtimeIds, runtimeId)
	end

	for _, runtimeId in runtimeIds do
		local runtime = self.lootById[runtimeId]
		if runtime ~= nil then
			self:updateRuntime(runtime, dt, playerContexts, contextsByPlayer, now)
		end
	end
end

function LootServiceServer.onHeartbeat(self: LootServiceServer, dtRaw: any)
	local dt = LootServiceUtils.sanitizeNumber(dtRaw, 0, 0, 1)
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
		self:stepSimulation(step)
	end
	if steps >= maxSteps and self.simulationAccumulator >= step then
		self.simulationAccumulator = 0
	end
end

function LootServiceServer.dropFromInventorySlot(
	self: LootServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
): boolean
	if not self:canAcceptDropRequest(player) then
		return false
	end

	local inventoryState = self.inventoryService:getState(player)
	if not InventoryServiceUtils.isLoadedState(inventoryState.loadState) then
		return false
	end

	local stack = InventoryServiceUtils.getStack(inventoryState, slotIndexRaw)
	if stack == nil then
		return false
	end

	local dropAmount = LootServiceUtils.resolveDropAmount(amountRaw, stack.amount)
	dropAmount = math.clamp(dropAmount, 1, stack.amount)

	local stackSnapshot: InventoryItemStack = {
		stackId = stack.stackId,
		itemId = stack.itemId,
		amount = stack.amount,
		maxStack = stack.maxStack,
		metadata = LootServiceUtils.cloneDeep(stack.metadata),
	}
	local cachedToolClones = self:captureDropToolClones(player, stackSnapshot.itemId, dropAmount)

	local removeResult = self.inventoryService:removeFromSlot(player, slotIndexRaw, dropAmount)
	if removeResult.removedAmount <= 0 then
		for _, toolClone in cachedToolClones do
			toolClone:Destroy()
		end
		return false
	end

	local dropOrigin = self:getDropOriginForPlayer(player, throwDirectionRaw)
	local runtime = self:spawnLootRuntime(stackSnapshot.itemId, removeResult.removedAmount, dropOrigin, {
		maxStack = stackSnapshot.maxStack,
		metadata = stackSnapshot.metadata,
		sourceType = "PlayerDrop",
		ownerUserId = player.UserId,
		ownerLockSeconds = self.settings.playerDropOwnerLockSeconds,
		throwDirection = throwDirectionRaw,
	})
	if runtime ~= nil then
		self.cache:cacheDroppedTools(runtime.id, stackSnapshot.itemId, player.UserId, cachedToolClones)
		return true
	end

	self.inventoryService:addItem(player, stackSnapshot.itemId, removeResult.removedAmount, {
		maxStack = stackSnapshot.maxStack,
		metadata = stackSnapshot.metadata,
		stackIdPrefix = "rollback",
	})
	local targetContainer: Instance? = player:FindFirstChildOfClass("Backpack")
	if targetContainer == nil then
		targetContainer = player.Character
	end
	for _, toolClone in cachedToolClones do
		self.inventoryService:releaseSuppressedToolImport(player, stackSnapshot.itemId, 1)
		if targetContainer ~= nil then
			toolClone.Parent = targetContainer
		else
			toolClone:Destroy()
		end
	end
	return false
end

function LootServiceServer.canAcceptDropRequest(self: LootServiceServer, player: Player): boolean
	local now = os.clock()
	local lastAt = self.lastDropRequestAtByPlayer[player] or -math.huge
	if now - lastAt < DROP_REQUEST_THROTTLE_SECONDS then
		return false
	end
	self.lastDropRequestAtByPlayer[player] = now
	return true
end

function LootServiceServer.requestSync(self: LootServiceServer, _player: Player) end

function LootServiceServer.requestDropFromSlot(
	self: LootServiceServer,
	player: Player,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	self:dropFromInventorySlot(player, slotIndexRaw, amountRaw, throwDirectionRaw)
end

function LootServiceServer.requestDropSelectedSlot(
	self: LootServiceServer,
	player: Player,
	amountRaw: any,
	throwDirectionRaw: any
)
	local inventoryState = self.inventoryService:getState(player)
	if not InventoryServiceUtils.isLoadedState(inventoryState.loadState) then
		return
	end
	local selectedSlot = inventoryState.selectedSlot
	if selectedSlot == nil then
		return
	end
	self:dropFromInventorySlot(player, selectedSlot, amountRaw, throwDirectionRaw)
end

function LootServiceServer.init(self: LootServiceServer)
	self.networker = Networker.server.new("LootService", self, {
		self.requestSync,
		self.requestDropFromSlot,
		self.requestDropSelectedSlot,
	})
	self.inventoryService = InventoryServiceServer :: InventoryServiceServerObject
	self.playerDataService = PlayerDataServiceServer :: PlayerDataServiceServerObject
	self.soundService = AudioServiceServer :: AudioServiceServerObject
	self.data = LootServiceData
	self.settings = LootServiceUtils.resolveSettings(self.data)
	self.random = Random.new()
	self.cache = LootServiceCache.new()
	self.lootById = {}
	self.itemTemplateByItemId = {}
	self.itemPickupSoundAssetIds = {} :: { string }
	self.coinDropSoundAssetIds = {} :: { string }
	self.coinPickupSoundAssetIds = {} :: { string }
	self:refreshPickupSoundTemplates()
	self.missingTemplateWarnedByItemId = {}
	self.lastDropRequestAtByPlayer = {}
	self.simulationAccumulator = 0
	self.lootFolder = self:ensureLootFolder()

	self.inventoryService:setDropFromSlotHandler(
		function(player: Player, slotIndexRaw: any, amountRaw: any, throwDirectionRaw: any)
			return self:dropFromInventorySlot(player, slotIndexRaw, amountRaw, throwDirectionRaw)
		end
	)

	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		self.lastDropRequestAtByPlayer[player] = nil
	end)
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
		self:onHeartbeat(dt)
	end)
end

function LootServiceServer.destroy(self: LootServiceServer)
	if self.playerRemovingConnection ~= nil then
		self.playerRemovingConnection:Disconnect()
		self.playerRemovingConnection = nil
	end
	if self.heartbeatConnection ~= nil then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	self.inventoryService:setDropFromSlotHandler(nil)

	local runtimeIds = {}
	for runtimeId in self.lootById do
		table.insert(runtimeIds, runtimeId)
	end
	for _, runtimeId in runtimeIds do
		self:removeRuntimeById(runtimeId, "Cleanup")
	end
	if self.cache ~= nil then
		self.cache:destroy()
	end

	if self.networker ~= nil then
		self.networker:destroy()
	end
	self.soundService = nil
end

type LootServiceServer = typeof(LootServiceServer) & {
	networker: Networker.Server,
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
	missingTemplateWarnedByItemId: { [string]: boolean },
	lastDropRequestAtByPlayer: { [Player]: number },
	simulationAccumulator: number,
	playerRemovingConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
}

return LootServiceServer :: LootServiceServer
