
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local ItemRegistry = require("ItemRegistry")
local MagicServiceUtils = require("MagicServiceUtils")
local MeleeServiceUtils = require("MeleeServiceUtils")
local GetItem = require("GetItem")
local GetToolInstance = require("GetToolInstance")
local TagBinder = require("TagBinder")

local ToolBinder = {}

export type ToolResolution = {
	tool: Tool?,
	itemId: string?,
	itemType: string?,
	definition: { [string]: any }?,
	primaryTemplate: Instance?,
	toolTemplate: Tool?,
	ownerPlayer: Player?,
	ownerCharacter: Model?,
	deployable: { [string]: any }?,
	isMelee: boolean,
	isMagic: boolean,
	meleeVariantTag: string?,
}

local function normalizeToken(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	local compact = string.gsub(string.lower(valueRaw), "[%s_%-]+", "")
	return compact
end

local function GetOwnerPlayer(tool: Tool?): (Player?, Model?)
	if tool == nil then
		return nil, nil
	end

	local parent = tool.Parent
	while parent ~= nil do
		if parent:IsA("Backpack") then
			local player = parent.Parent
			if player ~= nil and player:IsA("Player") then
				return player, player.Character
			end
		elseif parent:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(parent)
			if player ~= nil then
				return player, parent
			end
		end

		parent = parent.Parent
	end

	return nil, nil
end

local function GetMeleeVariantTag(itemIdRaw: any, definitionRaw: any): string?
	local itemId = normalizeToken(itemIdRaw)
	local displayName = if typeof(definitionRaw) == "table"
		then normalizeToken((definitionRaw :: { [string]: any }).name)
		else ""
	local combined = itemId .. displayName

	if string.find(combined, "katana", 1, true) ~= nil then
		return TagBinder.Tags.Melee_Katana
	end
	if string.find(combined, "broadsword", 1, true) ~= nil then
		return TagBinder.Tags.Melee_Broadsword
	end
	if string.find(combined, "shortsword", 1, true) ~= nil then
		return TagBinder.Tags.Melee_Shortsword
	end

	return nil
end

local function isMagicDefinition(definitionRaw: any, itemTypeRaw: any, toolRaw: any): boolean
	local typeToken = normalizeToken(itemTypeRaw)
	if typeToken == "magicweapon" or typeToken == "magic" or typeToken == "staff" or typeToken == "spell" then
		return true
	end

	if toolRaw ~= nil and MagicServiceUtils.IsMagicTool(toolRaw) then
		return true
	end

	if typeof(definitionRaw) ~= "table" then
		return false
	end

	local definition = definitionRaw :: { [string]: any }
	return definition.manaCost ~= nil
		or definition.castTime ~= nil
		or definition.cooldown ~= nil
		or definition.projectile ~= nil
		or definition.effects ~= nil
end

function ToolBinder.Get(toolOrInstanceRaw: any): ToolResolution
	local tool = GetToolInstance.GetTool(toolOrInstanceRaw)
	local itemId = GetToolInstance.GetToolItemId(tool)
	local itemType = GetToolInstance.GetToolItemType(tool)
	local definition = if itemId ~= nil then ItemRegistry.GetDefinition(itemId) else nil
	local templates = if itemId ~= nil
		then GetItem.Get(itemId)
		else { primaryTemplate = nil, toolTemplate = nil }
	local ownerPlayer, ownerCharacter = GetOwnerPlayer(tool)
	local deployable = if typeof(definition) == "table"
			and typeof((definition :: { [string]: any }).deployable) == "table"
		then (definition :: { [string]: any }).deployable :: { [string]: any }
		else nil
	local isMelee = if itemId ~= nil
		then MeleeServiceUtils.GetWeaponConfig(itemId) ~= nil or MeleeServiceUtils.IsMeleeTool(tool)
		else false
	local isMagic = isMagicDefinition(definition, itemType, tool)

	return {
		tool = tool,
		itemId = itemId,
		itemType = itemType,
		definition = definition,
		primaryTemplate = templates.primaryTemplate,
		toolTemplate = templates.toolTemplate,
		ownerPlayer = ownerPlayer,
		ownerCharacter = ownerCharacter,
		deployable = deployable,
		isMelee = isMelee,
		isMagic = isMagic,
		meleeVariantTag = GetMeleeVariantTag(itemId, definition),
	}
end

function ToolBinder.GetTool(toolOrInstanceRaw: any): Tool?
	return ToolBinder.Get(toolOrInstanceRaw).tool
end

function ToolBinder.GetItemId(toolOrInstanceRaw: any): string?
	return ToolBinder.Get(toolOrInstanceRaw).itemId
end

function ToolBinder.GetDefinition(toolOrInstanceRaw: any): { [string]: any }?
	return ToolBinder.Get(toolOrInstanceRaw).definition
end

function ToolBinder.GetDeployable(toolOrInstanceRaw: any): { [string]: any }?
	return ToolBinder.Get(toolOrInstanceRaw).deployable
end

function ToolBinder.GetStationTag(toolOrInstanceRaw: any): string?
	local resolution = ToolBinder.Get(toolOrInstanceRaw)
	if resolution.deployable == nil then
		return nil
	end

	return TagBinder.getCanonicalTag(resolution.deployable.stationTag)
end

function ToolBinder.IsMelee(toolOrInstanceRaw: any): boolean
	return ToolBinder.Get(toolOrInstanceRaw).isMelee
end

function ToolBinder.IsMagic(toolOrInstanceRaw: any): boolean
	return ToolBinder.Get(toolOrInstanceRaw).isMagic
end

function ToolBinder.GetMeleeVariantTag(toolOrInstanceRaw: any): string?
	return ToolBinder.Get(toolOrInstanceRaw).meleeVariantTag
end

function ToolBinder.ApplyTags(toolOrInstanceRaw: any): number
	local resolution = ToolBinder.Get(toolOrInstanceRaw)
	if resolution.tool == nil then
		return 0
	end

	local tags = {}
	if resolution.isMelee then
		tags[#tags + 1] = TagBinder.Tags.Melee
		if resolution.meleeVariantTag ~= nil then
			tags[#tags + 1] = resolution.meleeVariantTag
		end
	end
	if resolution.isMagic then
		tags[#tags + 1] = TagBinder.Tags.Magic
	end

	if #tags <= 0 then
		return 0
	end

	return TagBinder.applyTags(resolution.tool, tags)
end

return ToolBinder
