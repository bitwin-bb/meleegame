local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local ImageIds = require("ImageIds")
local ItemRegistry = require("ItemRegistry")
local Maid = require("Maid")
local StringUtils = require("StringUtils")

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
type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> number,
	DoCleaning: (self: MaidClass) -> (),
}
type CoinSpriteSheet = {
	image: string,
	frameSize: Vector2,
	frameCount: number,
	columns: number,
	fps: number,
}

local DEFAULT_NAME = "LootItem"
local DEFAULT_ITEM_ID = "Item"
local DEFAULT_ROOT_SIZE = Vector3.new(0.2, 2.2, 2.2)
local CANVAS_SIZE = Vector2.new(128, 128)
local SIDE_VIEW_FACE = Enum.NormalId.Right
local ROOT_PART_NAME = "Root"
local SURFACE_GUI_NAME = "LootIcon"
local ICON_NAME = "Icon"
local AMOUNT_NAME = "Amount"
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

local function sanitizeName(valueRaw: any): string
	local value = StringUtils.sanitize(valueRaw, nil)
	if value ~= nil then
		return value
	end
	return DEFAULT_NAME
end

local function sanitizeItemId(valueRaw: any): string
	local value = StringUtils.sanitize(valueRaw, nil)
	if value ~= nil then
		return value
	end
	return DEFAULT_ITEM_ID
end

local function sanitizeAmount(valueRaw: any): number
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		return math.max(1, math.floor(valueRaw))
	end
	return 1
end

local function sanitizeSize(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return Vector3.new(math.max(0.05, valueRaw.X), math.max(0.05, valueRaw.Y), math.max(0.05, valueRaw.Z))
	end
	return DEFAULT_ROOT_SIZE
end

local function normalizeKey(valueRaw: any): string?
	local token = StringUtils.compactToken(valueRaw)
	if token == "" then
		return nil
	end
	return token
end

local function resolveIconValue(valueRaw: any): string?
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return nil
end

local function resolveItemIcons(): IconMap?
	local itemIcons = (ImageIds :: any).itemIcons
	if typeof(itemIcons) == "table" then
		return itemIcons :: IconMap
	end
	return nil
end

local function resolveSpriteSheets(): IconMap?
	local spriteSheets = (ImageIds :: any).spriteSheets
	if typeof(spriteSheets) == "table" then
		return spriteSheets :: IconMap
	end
	return nil
end

local function resolveItemTypeFromDefinition(definitionRaw: any): string?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end

	local definition = definitionRaw :: ItemDefinition
	return StringUtils.sanitize(definition.itemType or definition.type, nil)
end

local function resolveItemTypeFromItemId(itemIdRaw: any): string?
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

local function resolveIconByNormalizedKey(itemIcons: IconMap, normalizedKey: string): string?
	local directIcon = resolveIconValue(itemIcons[normalizedKey])
	if directIcon ~= nil then
		return directIcon
	end

	for key, value in itemIcons do
		if normalizeKey(key) == normalizedKey then
			local icon = resolveIconValue(value)
			if icon ~= nil then
				return icon
			end
		end
	end

	return nil
end

local function resolveIconByItemId(itemIcons: IconMap, itemIdRaw: any): string?
	local normalizedItemId = normalizeKey(itemIdRaw)
	if normalizedItemId == nil then
		return nil
	end
	return resolveIconByNormalizedKey(itemIcons, normalizedItemId)
end

local function resolveIconByItemType(itemIcons: IconMap, itemTypeRaw: any): string?
	local normalizedType = normalizeKey(itemTypeRaw)
	if normalizedType == nil then
		return nil
	end
	return resolveIconValue(itemIcons[normalizedType])
end

local function resolveFallbackIcon(itemIcons: IconMap?): string
	if itemIcons ~= nil then
		local fallbackIcon = resolveIconValue(itemIcons.default)
		if fallbackIcon ~= nil then
			return fallbackIcon
		end
	end

	local questionMarkIcon = resolveIconValue((ImageIds :: any).questionMark)
	if questionMarkIcon ~= nil then
		return questionMarkIcon
	end
	return ""
end

local function resolveCoinSpriteSheet(itemIdRaw: any): CoinSpriteSheet?
	local itemId = sanitizeItemId(itemIdRaw)
	local canonicalItemId = ItemRegistry.resolveCanonicalItemId(itemId) or itemId
	local spriteSheetKey = COIN_SPRITE_SHEET_KEY_BY_TOKEN[normalizeKey(canonicalItemId) or ""]
		or COIN_SPRITE_SHEET_KEY_BY_TOKEN[normalizeKey(itemId) or ""]
	if spriteSheetKey == nil then
		return nil
	end

	local spriteSheets = resolveSpriteSheets()
	if spriteSheets == nil then
		return nil
	end

	local spriteSheetImage = resolveIconValue(spriteSheets[spriteSheetKey])
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

local function resolveSpriteFrameOffset(frameIndex: number, spriteSheet: CoinSpriteSheet): Vector2
	local column = frameIndex % spriteSheet.columns
	local row = math.floor(frameIndex / spriteSheet.columns)
	return Vector2.new(column * spriteSheet.frameSize.X, row * spriteSheet.frameSize.Y)
end

function LootItemServer.ResolveIcon(itemIdRaw: any): string
	local itemId = sanitizeItemId(itemIdRaw)
	local canonicalItemId = ItemRegistry.resolveCanonicalItemId(itemId) or itemId
	local definition = ItemRegistry.resolveDefinition(canonicalItemId)
	local itemType = resolveItemTypeFromDefinition(definition)
		or resolveItemTypeFromItemId(canonicalItemId)
		or resolveItemTypeFromItemId(itemId)

	local itemIcons = resolveItemIcons()
	if itemIcons == nil then
		return resolveFallbackIcon(nil)
	end

	local resolvedIcon = resolveIconByItemId(itemIcons, canonicalItemId)
	if resolvedIcon ~= nil then
		return resolvedIcon
	end

	if canonicalItemId ~= itemId then
		resolvedIcon = resolveIconByItemId(itemIcons, itemId)
		if resolvedIcon ~= nil then
			return resolvedIcon
		end
	end

	resolvedIcon = resolveIconByItemType(itemIcons, itemType)
	if resolvedIcon ~= nil then
		return resolvedIcon
	end

	return resolveFallbackIcon(itemIcons)
end

local function createAnimatedCoinIconImage(scope: any, maid: MaidClass, itemId: string): ImageLabel?
	local spriteSheet = resolveCoinSpriteSheet(itemId)
	if spriteSheet == nil then
		return nil
	end

	local frameIndex = scope:Value(0)
	local frameOffset = scope:Computed(function(use)
		return resolveSpriteFrameOffset(use(frameIndex), spriteSheet)
	end)
	local elapsed = 0
	maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += math.max(0, deltaTime)
		local nextFrameIndex = math.floor(elapsed * spriteSheet.fps) % spriteSheet.frameCount
		if Fusion.peek(frameIndex) ~= nextFrameIndex then
			frameIndex:set(nextFrameIndex)
		end
	end))

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
		ImageRectOffset = frameOffset,
		ImageRectSize = spriteSheet.frameSize,
		ScaleType = Enum.ScaleType.Fit,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		[Fusion.Attribute("LootIconAnimated")] = true,
	} :: ImageLabel
end

local function createIconImage(scope: any, maid: MaidClass, itemId: string): ImageLabel
	local coinIcon = createAnimatedCoinIconImage(scope, maid, itemId)
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
		Image = LootItemServer.ResolveIcon(itemId),
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

local function createIconChildren(scope: any, maid: MaidClass, itemId: string, amount: number): { Instance }
	local iconChildren: { Instance } = {
		createIconImage(scope, maid, itemId),
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
	return scope:New "Part" {
		Name = ROOT_PART_NAME,
		Size = sanitizeSize(config.size),
		CFrame = CFrame.identity,
		Transparency = 1,
		Anchored = false,
		CanCollide = true,
		CanQuery = true,
		CanTouch = true,
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

local function bindScopeCleanup(model: Model, scope: any, maid: MaidClass): MaidClass
	maid:GiveTask(function()
		Fusion.doCleanup(scope)
	end)
	maid:GiveTask(model.Destroying:Connect(function()
		maid:DoCleaning()
	end))

	return maid
end

function LootItemServer.CreateModel(configRaw: LootItemServerConfig?): Model
	local config = (if typeof(configRaw) == "table" then configRaw else {} :: any) :: LootItemServerConfig
	local itemId = sanitizeItemId(config.itemId)
	local amount = sanitizeAmount(config.amount)
	local scope = Fusion.scoped(Fusion)
	local maid = Maid.new() :: MaidClass
	local rotationAttachment, rotationLock = createRotationLock(scope)
	local surfaceGui = createSurfaceGui(scope, createIconChildren(scope, maid, itemId, amount))
	local rootPart = createRootPart(scope, config, rotationAttachment, rotationLock, surfaceGui)

	local model = scope:New "Model" {
		Name = sanitizeName(config.name),
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

	bindScopeCleanup(model, scope, maid)

	return model
end

LootItemServer.resolveIcon = LootItemServer.ResolveIcon
LootItemServer.createModel = LootItemServer.CreateModel

return LootItemServer
