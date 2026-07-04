local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CoinSprites = require("CoinSprites")
local LootServiceUtils = require("LootServiceUtils")
local Maid = require("Maid")
local PacketPayload = require("PacketPayload")
local WorkspaceFolders = require("WorkspaceFolders")
local LootServicePackets = require("NetPacketsShared").LootService

local function sendPacket(methodName: string, ...: any)
	local packet = LootServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for LootService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = LootServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for LootService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
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

type MaidClass = any

local LootServiceClient = {}

local LOOT_FOLDER_NAME = "LootRuntime"
local LOOT_ICON_ANIMATED_ATTRIBUTE = "LootIconAnimated"
local LOOT_ICON_ITEM_ID_ATTRIBUTE = "LootIconItemId"
local LOOT_ICON_SPRITE_SHEET_NAME = "SpriteSheet"

local function GetLootIconItemId(icon: ImageLabel): string?
	local itemId = icon:GetAttribute(LOOT_ICON_ITEM_ID_ATTRIBUTE)
	if typeof(itemId) == "string" and itemId ~= "" then
		return itemId
	end

	local ancestor = icon.Parent
	while ancestor ~= nil do
		local ancestorItemId = ancestor:GetAttribute(LOOT_ICON_ITEM_ID_ATTRIBUTE)
		if typeof(ancestorItemId) == "string" and ancestorItemId ~= "" then
			return ancestorItemId
		end
		ancestor = ancestor.Parent
	end

	return nil
end

local function isAnimatedLootIcon(instance: Instance): boolean
	if not instance:IsA("ImageLabel") then
		return false
	end
	return instance:GetAttribute(LOOT_ICON_ANIMATED_ATTRIBUTE) == true
end

local function scanAnimatedLootIcons(root: Instance, callback: (ImageLabel) -> ())
	if isAnimatedLootIcon(root) then
		callback(root :: ImageLabel)
	end
	for _, descendant in root:GetDescendants() do
		if isAnimatedLootIcon(descendant) then
			callback(descendant :: ImageLabel)
		end
	end
end

local function applySpriteSheetFrame(spriteSheetIcon: ImageLabel, frameIndex: number)
	local columns = math.max(1, CoinSprites.columns)
	local column = frameIndex % columns
	local row = math.floor(frameIndex / columns)
	spriteSheetIcon.Position = UDim2.fromScale(-column, -row)
end

local function createSpriteSheetIcon(icon: ImageLabel, spriteSheet: string): ImageLabel
	local existing = icon:FindFirstChild(LOOT_ICON_SPRITE_SHEET_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local rows = math.max(1, CoinSprites.rows)
	local columns = math.max(1, CoinSprites.columns)
	local spriteSheetIcon = Instance.new("ImageLabel")
	spriteSheetIcon.Name = LOOT_ICON_SPRITE_SHEET_NAME
	spriteSheetIcon.Size = UDim2.fromScale(columns, rows)
	spriteSheetIcon.Position = UDim2.fromScale(0, 0)
	spriteSheetIcon.BackgroundTransparency = 1
	spriteSheetIcon.BorderSizePixel = 0
	spriteSheetIcon.Image = spriteSheet
	spriteSheetIcon.ScaleType = Enum.ScaleType.Stretch
	spriteSheetIcon.ResampleMode = Enum.ResamplerMode.Pixelated
	spriteSheetIcon.ZIndex = icon.ZIndex + 1
	spriteSheetIcon.Parent = icon

	return spriteSheetIcon
end

function LootServiceClient.ApplyState(self: LootServiceClient, _payloadRaw: any) end

function LootServiceClient.RequestSync(self: LootServiceClient)
	sendPacket(LootServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function LootServiceClient.RequestDropFromSlot(
	self: LootServiceClient,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	sendPacket(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SLOT, slotIndexRaw, amountRaw, throwDirectionRaw)
end

function LootServiceClient.RequestDropSelectedSlot(self: LootServiceClient, amountRaw: any, throwDirectionRaw: any)
	sendPacket(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SELECTED, amountRaw, throwDirectionRaw)
end

function LootServiceClient.GotRopAmount(self: LootServiceClient, amountRaw: any, fallbackAmountRaw: any?): number
	return LootServiceUtils.GotRopAmount(amountRaw, fallbackAmountRaw)
end

function LootServiceClient.StartLootIconAnimation(self: LootServiceClient, iconRaw: Instance)
	if not iconRaw:IsA("ImageLabel") then
		return
	end
	local icon = iconRaw :: ImageLabel
	if icon:GetAttribute(LOOT_ICON_ANIMATED_ATTRIBUTE) ~= true then
		return
	end
	if self.animatedLootIconMaids[icon] ~= nil then
		return
	end

	local itemId = GetLootIconItemId(icon)
	if itemId == nil then
		return
	end

	local spriteSheet = CoinSprites.GetSpriteSheet(itemId)
	if spriteSheet == nil then
		return
	end

	icon.Image = ""
	icon.ImageTransparency = 1
	icon.ClipsDescendants = true
	icon.ResampleMode = Enum.ResamplerMode.Pixelated

	local iconMaid = Maid.new()
	self.animatedLootIconMaids[icon] = iconMaid
	iconMaid:GiveTask(function()
		self.animatedLootIconMaids[icon] = nil
	end)
	iconMaid:GiveTask(icon.Destroying:Connect(function()
		iconMaid:DoCleaning()
	end))

	local spriteSheetIcon = createSpriteSheetIcon(icon, spriteSheet)
	iconMaid:GiveTask(spriteSheetIcon)
	applySpriteSheetFrame(spriteSheetIcon, 0)

	local frameCount = math.max(1, CoinSprites.frameCount)
	local frameDuration = 1 / math.max(0.01, CoinSprites.fps)
	local elapsed = 0
	local frameIndex = 0
	iconMaid:GiveTask(RunService.RenderStepped:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < frameDuration then
			return
		end

		local advancedFrames = math.floor(elapsed / frameDuration)
		elapsed -= advancedFrames * frameDuration
		frameIndex = (frameIndex + advancedFrames) % frameCount
		applySpriteSheetFrame(spriteSheetIcon, frameIndex)
	end))
end

function LootServiceClient.StartLootIconAnimations(self: LootServiceClient)
	local maid = self.maid
	if maid == nil then
		return
	end

	local lootFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(LOOT_FOLDER_NAME)
	local scanRoot = lootFolder or Workspace
	scanAnimatedLootIcons(scanRoot, function(icon: ImageLabel)
		self:StartLootIconAnimation(icon)
	end)

	maid:GiveTask(Workspace.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ImageLabel") then
			task.defer(function()
				if descendant.Parent ~= nil then
					self:StartLootIconAnimation(descendant)
				end
			end)
		end
	end))
end

function LootServiceClient.Init(self: LootServiceClient)
	bindPackets(self)
	local maid = Maid.new()
	self.maid = maid
	self.animatedLootIconMaids = {}
	maid:GiveTask(function()
		for _, iconMaid in self.animatedLootIconMaids do
			if iconMaid ~= nil then
				(iconMaid :: any):DoCleaning()
			end
		end
		self.animatedLootIconMaids = {}
	end)
	self:StartLootIconAnimations()
	self:RequestSync()
end

function LootServiceClient.Destroy(self: LootServiceClient)
	if self.maid ~= nil then
		self.maid:DoCleaning()
	end
end

type LootServiceClient = typeof(LootServiceClient) & {
	maid: MaidClass?,
	animatedLootIconMaids: { [ImageLabel]: MaidClass? },
}

return LootServiceClient :: LootServiceClient
