local require = require(script.Parent.loader).load(script)

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local ImageIds = require("ImageIds")
local ItemIcons = require("ItemIcons")
local ItemRegistry = require("ItemRegistry")
local StringUtils = require("StringUtils")
local WorldGenerationConstants = require("WorldGenerationConstants")

local Children = Fusion.Children

local LootItemServer = {}

export type LootItemServerConfig = {
	itemId: string?,
	amount: number?,
	name: string?,
	size: Vector3?,
	cframe: CFrame?,
	parent: Instance?,
}

type IconMap = { [any]: any }
type ItemDefinition = { [string]: any }
type CoinSpriteSheet = {
	image: string,
	frameSize: Vector2,
	frameCount: number,
	columns: number,
	fps: number,
}

local DEFAULT_NAME = "LootItem"
local DEFAULT_ITEM_ID = "Item"
local PLANE_DEPTH = WorldGenerationConstants.DEFAULT_TILE_DEPTH
local DEFAULT_ROOT_SIZE = Vector3.new(PLANE_DEPTH, 2.2, 2.2)
local CANVAS_SIZE = Vector2.new(128, 128)
local SIDE_VIEW_FACE = Enum.NormalId.Right
local ROOT_PART_NAME = "Root"
local SURFACE_GUI_NAME = "LootIcon"
local ICON_NAME = "Icon"
local AMOUNT_NAME = "Amount"
local LOOT_COLLISION_GROUP = "LootItems"
local PLAYER_COLLISION_GROUP = "PlayersCharacters"
local ROTATION_LOCK_ATTACHMENT_NAME = "RotationLockAttachment"
local ROTATION_LOCK_NAME = "RotationLock"
local ROTATION_LOCK_MAX_ANGULAR_VELOCITY = 1000000
local ROTATION_LOCK_MAX_TORQUE = 1000000000
local ROTATION_LOCK_RESPONSIVENESS = 200
local COIN_SPRITE_SHEET_SIZE = Vector2.new(1290, 774)
local COIN_SPRITE_ROWS = 3
local COIN_SPRITE_COLUMNS = 5
local COIN_SPRITE_FRAME_SIZE = Vector2.new(
	math.floor(COIN_SPRITE_SHEET_SIZE.X / COIN_SPRITE_COLUMNS),
	math.floor(COIN_SPRITE_SHEET_SIZE.Y / COIN_SPRITE_ROWS)
)
local COIN_SPRITE_FRAME_COUNT = COIN_SPRITE_ROWS * COIN_SPRITE_COLUMNS
local COIN_SPRITE_FPS = 12
local COIN_SPRITE_SHEET_KEY_BY_TOKEN = {
	coppercoin = "copperCoin",
	coincopper = "copperCoin",
	silvercoin = "silverCoin",
	coinsilver = "silverCoin",
	goldcoin = "goldCoin",
	coingold = "goldCoin",
	platinumcoin = "platinumCoin",
	coinplatinum = "platinumCoin",
}
local collisionGroupsReady = false

local function safeRegisterCollisionGroup(groupName: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
end

local function safeSetCollisionGroupCollidable(groupA: string, groupB: string, collidable: boolean)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(groupA, groupB, collidable)
	end)
end

local function ensureLootCollisionGroups()
	if collisionGroupsReady then
		return
	end

	safeRegisterCollisionGroup(LOOT_COLLISION_GROUP)
	safeRegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	safeSetCollisionGroupCollidable(LOOT_COLLISION_GROUP, LOOT_COLLISION_GROUP, false)
	safeSetCollisionGroupCollidable(LOOT_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	safeSetCollisionGroupCollidable(PLAYER_COLLISION_GROUP, LOOT_COLLISION_GROUP, false)
	collisionGroupsReady = true
end

local function coerceName(valueRaw: any): string
	local value = StringUtils.Coerce(valueRaw, nil)
	if value ~= nil then
		return value
	end
	return DEFAULT_NAME
end

local function coerceItemId(valueRaw: any): string
	local value = StringUtils.Coerce(valueRaw, nil)
	if value ~= nil then
		return value
	end
	return DEFAULT_ITEM_ID
end

local function coerceAmount(valueRaw: any): number
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		return math.max(1, math.floor(valueRaw))
	end
	return 1
end

local function coerceSize(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return Vector3.new(PLANE_DEPTH, math.max(0.05, valueRaw.Y), math.max(0.05, valueRaw.Z))
	end
	return DEFAULT_ROOT_SIZE
end

local function normalizeKey(valueRaw: any): string?
	local token = StringUtils.CompactToken(valueRaw)
	if token == "" then
		return nil
	end
	return token
end

local function getIconValue(valueRaw: any): string?
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return nil
end

local function getItemIcons(): IconMap?
	local itemIcons = ItemIcons
	if typeof(itemIcons) == "table" then
		return itemIcons :: IconMap
	end
	return nil
end

local function getSpriteSheets(): IconMap?
	local spriteSheets = (ImageIds :: any).spriteSheets
	if typeof(spriteSheets) == "table" then
		return spriteSheets :: IconMap
	end
	return nil
end

local function getItemTypeFromDefinition(definitionRaw: any): string?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end

	local definition = definitionRaw :: ItemDefinition
	return StringUtils.Coerce(definition.itemType or definition.type, nil)
end

local function getItemTypeFromItemId(itemIdRaw: any): string?
	local itemId = normalizeKey(itemIdRaw)
	if itemId == nil then
		return nil
	end

	if string.find(itemId, "sword", 1, true) ~= nil then
		return "sword"
	end
	if string.find(itemId, "pickaxe", 1, true) ~= nil then
		return "pickaxe"
	end
	if string.find(itemId, "axe", 1, true) ~= nil then
		return "axe"
	end
	if string.find(itemId, "hammer", 1, true) ~= nil then
		return "hammer"
	end
	if string.find(itemId, "coin", 1, true) ~= nil then
		return "coin"
	end
	if string.find(itemId, "crystal", 1, true) ~= nil then
		return "consumable"
	end

	return nil
end

local function getIconByNormalizedKey(itemIcons: IconMap, normalizedKey: string): string?
	local directIcon = getIconValue(itemIcons[normalizedKey])
	if directIcon ~= nil then
		return directIcon
	end

	for key, value in itemIcons do
		if normalizeKey(key) == normalizedKey then
			local icon = getIconValue(value)
			if icon ~= nil then
				return icon
			end
		end
	end

	return nil
end

local function getIconByItemId(itemIcons: IconMap, itemIdRaw: any): string?
	local normalizedItemId = normalizeKey(itemIdRaw)
	if normalizedItemId == nil then
		return nil
	end
	return getIconByNormalizedKey(itemIcons, normalizedItemId)
end

local function getIconByItemType(itemIcons: IconMap, itemTypeRaw: any): string?
	local normalizedType = normalizeKey(itemTypeRaw)
	if normalizedType == nil then
		return nil
	end
	return getIconValue(itemIcons[normalizedType])
end

local function getFallbackIcon(itemIcons: IconMap?): string
	if itemIcons ~= nil then
		local fallbackIcon = getIconValue(itemIcons.default)
		if fallbackIcon ~= nil then
			return fallbackIcon
		end
	end

	local questionMarkIcon = getIconValue((ImageIds :: any).questionMark)
	if questionMarkIcon ~= nil then
		return questionMarkIcon
	end
	return ""
end

local function getCoinSpriteSheet(itemIdRaw: any): CoinSpriteSheet?
	local itemId = coerceItemId(itemIdRaw)
	local canonicalItemId = ItemRegistry.GetCanonicalItemId(itemId) or itemId
	local spriteSheetKey = COIN_SPRITE_SHEET_KEY_BY_TOKEN[normalizeKey(canonicalItemId) or ""]
		or COIN_SPRITE_SHEET_KEY_BY_TOKEN[normalizeKey(itemId) or ""]
	if spriteSheetKey == nil then
		return nil
	end

	local spriteSheets = getSpriteSheets()
	if spriteSheets == nil then
		return nil
	end

	local spriteSheetImage = getIconValue(spriteSheets[spriteSheetKey])
	if spriteSheetImage == nil then
		return nil
	end

	return {
		image = spriteSheetImage,
		frameSize = COIN_SPRITE_FRAME_SIZE,
		frameCount = COIN_SPRITE_FRAME_COUNT,
		columns = COIN_SPRITE_COLUMNS,
		fps = COIN_SPRITE_FPS,
	}
end

function LootItemServer.GetIcon(itemIdRaw: any): string
	local itemId = coerceItemId(itemIdRaw)
	local canonicalItemId = ItemRegistry.GetCanonicalItemId(itemId) or itemId
	local definition = ItemRegistry.GetDefinition(canonicalItemId)
	local itemType = getItemTypeFromDefinition(definition)
		or getItemTypeFromItemId(canonicalItemId)
		or getItemTypeFromItemId(itemId)

	local itemIcons = getItemIcons()
	if itemIcons == nil then
		return getFallbackIcon(nil)
	end

	local itemIcon = getIconByItemId(itemIcons, canonicalItemId)
	if itemIcon ~= nil then
		return itemIcon
	end

	if canonicalItemId ~= itemId then
		itemIcon = getIconByItemId(itemIcons, itemId)
		if itemIcon ~= nil then
			return itemIcon
		end
	end

	itemIcon = getIconByItemType(itemIcons, itemType)
	if itemIcon ~= nil then
		return itemIcon
	end

	return getFallbackIcon(itemIcons)
end

local function createAnimatedCoinIconImage(scope: any, itemId: string): ImageLabel?
	local spriteSheet = getCoinSpriteSheet(itemId)
	if spriteSheet == nil then
		return nil
	end

	return scope:New "ImageLabel" {
		Name = ICON_NAME,
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = spriteSheet.image,
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ImageTransparency = 0,
		ImageRectOffset = Vector2.zero,
		ImageRectSize = spriteSheet.frameSize,
		ScaleType = Enum.ScaleType.Fit,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		[Fusion.Attribute("LootIconAnimated")] = true,
		[Fusion.Attribute("LootIconItemId")] = itemId,
	} :: ImageLabel
end

local function createIconImage(scope: any, itemId: string): ImageLabel
	local coinIcon = createAnimatedCoinIconImage(scope, itemId)
	if coinIcon ~= nil then
		return coinIcon
	end

	return scope:New "ImageLabel" {
		Name = ICON_NAME,
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = LootItemServer.GetIcon(itemId),
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Fit,
		[Fusion.Attribute("LootIconAnimated")] = false,
	} :: ImageLabel
end

local function createAmountLabel(scope: any, amount: number): TextLabel
	return scope:New "TextLabel" {
		Name = AMOUNT_NAME,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = UDim2.new(1, -10, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.PatrickHand,
		Text = tostring(amount),
		TextColor3 = Color3.fromRGB(248, 253, 255),
		TextSize = 28,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	} :: TextLabel
end

local function createIconChildren(scope: any, itemId: string, amount: number): { Instance }
	local iconChildren: { Instance } = {
		createIconImage(scope, itemId),
	}
	if amount > 1 then
		table.insert(iconChildren, createAmountLabel(scope, amount))
	end
	return iconChildren
end

local function createRotationLock(scope: any): (Attachment, AlignOrientation)
	local rotationAttachment = scope:New "Attachment" {
		Name = ROTATION_LOCK_ATTACHMENT_NAME,
		CFrame = CFrame.identity,
	} :: Attachment
	local rotationLock = scope:New "AlignOrientation" {
		Name = ROTATION_LOCK_NAME,
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = rotationAttachment,
		CFrame = CFrame.identity,
		RigidityEnabled = true,
		MaxAngularVelocity = ROTATION_LOCK_MAX_ANGULAR_VELOCITY,
		MaxTorque = ROTATION_LOCK_MAX_TORQUE,
		Responsiveness = ROTATION_LOCK_RESPONSIVENESS,
	} :: AlignOrientation

	return rotationAttachment, rotationLock
end

local function createSurfaceGui(scope: any, iconChildren: { Instance }): SurfaceGui
	return scope:New "SurfaceGui" {
		Name = SURFACE_GUI_NAME,
		Face = SIDE_VIEW_FACE,
		AlwaysOnTop = true,
		LightInfluence = 0,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = CANVAS_SIZE,

		[Children] = iconChildren,
	} :: SurfaceGui
end

local function createRootPart(
	scope: any,
	config: LootItemServerConfig,
	rotationAttachment: Attachment,
	rotationLock: AlignOrientation,
	surfaceGui: SurfaceGui
): BasePart
	ensureLootCollisionGroups()

	return scope:New "Part" {
		Name = ROOT_PART_NAME,
		Size = coerceSize(config.size),
		CFrame = CFrame.identity,
		Transparency = 1,
		Anchored = false,
		CanCollide = true,
		CanQuery = true,
		CanTouch = true,
		CollisionGroup = LOOT_COLLISION_GROUP,
		AssemblyAngularVelocity = Vector3.zero,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,

		[Children] = {
			rotationAttachment,
			rotationLock,
			surfaceGui,
		},
	} :: BasePart
end

function LootItemServer.CreateModel(configRaw: LootItemServerConfig?): Model
	local config = (if typeof(configRaw) == "table" then configRaw else {} :: any) :: LootItemServerConfig
	local itemId = coerceItemId(config.itemId)
	local amount = coerceAmount(config.amount)
	local scope = Fusion.scoped(Fusion)
	local rotationAttachment, rotationLock = createRotationLock(scope)
	local surfaceGui = createSurfaceGui(scope, createIconChildren(scope, itemId, amount))
	local rootPart = createRootPart(scope, config, rotationAttachment, rotationLock, surfaceGui)

	local model = scope:New "Model" {
		Name = coerceName(config.name),
		Parent = if typeof(config.parent) == "Instance" then config.parent else nil,
		[Fusion.Attribute("LootIconItemId")] = itemId,
		[Fusion.Attribute("LootIconSurfaceFace")] = SIDE_VIEW_FACE.Name,

		[Children] = {
			rootPart,
		},
	} :: Model

	model.PrimaryPart = rootPart
	if typeof(config.cframe) == "CFrame" then
		model:PivotTo(CFrame.new((config.cframe :: CFrame).Position))
	end

	return model
end

return LootItemServer
