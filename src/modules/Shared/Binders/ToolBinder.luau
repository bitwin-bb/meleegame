--!strict

local Players = game:GetService("Players")

local ResolveItem = require(script:FindFirstAncestor("game").Shared.Modules.Game.ResolveItem)
local ResolveToolInstance = require(script:FindFirstAncestor("game").Shared.Modules.Game.ResolveToolInstance)
local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)
local MeleeServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.MeleeServiceUtils)
local MagicServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.MagicServiceUtils)
local TagBinder = require(script.Parent.TagBinder)

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

local function resolveOwnerPlayer(tool: Tool?): (Player?, Model?)
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

local function resolveMeleeVariantTag(itemIdRaw: any, definitionRaw: any): string?
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

	if toolRaw ~= nil and MagicServiceUtils.isMagicTool(toolRaw) then
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

function ToolBinder.Resolve(toolOrInstanceRaw: any): ToolResolution
	local tool = ResolveToolInstance.resolveTool(toolOrInstanceRaw)
	local itemId = ResolveToolInstance.resolveToolItemId(tool)
	local itemType = ResolveToolInstance.resolveToolItemType(tool)
	local definition = if itemId ~= nil then ItemRegistry.resolveDefinition(itemId) else nil
	local templates = if itemId ~= nil then ResolveItem.resolve(itemId) else { primaryTemplate = nil, toolTemplate = nil }
	local ownerPlayer, ownerCharacter = resolveOwnerPlayer(tool)
	local deployable = if typeof(definition) == "table" and typeof((definition :: { [string]: any }).deployable) == "table"
		then ((definition :: { [string]: any }).deployable :: { [string]: any })
		else nil
	local isMelee = if itemId ~= nil
		then MeleeServiceUtils.resolveWeaponConfig(itemId) ~= nil or MeleeServiceUtils.isMeleeTool(tool)
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
		meleeVariantTag = resolveMeleeVariantTag(itemId, definition),
	}
end

function ToolBinder.ResolveTool(toolOrInstanceRaw: any): Tool?
	return ToolBinder.Resolve(toolOrInstanceRaw).tool
end

function ToolBinder.ResolveItemId(toolOrInstanceRaw: any): string?
	return ToolBinder.Resolve(toolOrInstanceRaw).itemId
end

function ToolBinder.ResolveDefinition(toolOrInstanceRaw: any): { [string]: any }?
	return ToolBinder.Resolve(toolOrInstanceRaw).definition
end

function ToolBinder.ResolveDeployable(toolOrInstanceRaw: any): { [string]: any }?
	return ToolBinder.Resolve(toolOrInstanceRaw).deployable
end

function ToolBinder.ResolveStationTag(toolOrInstanceRaw: any): string?
	local resolution = ToolBinder.Resolve(toolOrInstanceRaw)
	if resolution.deployable == nil then
		return nil
	end

	return TagBinder.getCanonicalTag(resolution.deployable.stationTag)
end

function ToolBinder.IsMelee(toolOrInstanceRaw: any): boolean
	return ToolBinder.Resolve(toolOrInstanceRaw).isMelee
end

function ToolBinder.IsMagic(toolOrInstanceRaw: any): boolean
	return ToolBinder.Resolve(toolOrInstanceRaw).isMagic
end

function ToolBinder.ResolveMeleeVariantTag(toolOrInstanceRaw: any): string?
	return ToolBinder.Resolve(toolOrInstanceRaw).meleeVariantTag
end

function ToolBinder.ApplyTags(toolOrInstanceRaw: any): number
	local resolution = ToolBinder.Resolve(toolOrInstanceRaw)
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

ToolBinder.resolve = ToolBinder.Resolve
ToolBinder.resolveTool = ToolBinder.ResolveTool
ToolBinder.resolveItemId = ToolBinder.ResolveItemId
ToolBinder.resolveDefinition = ToolBinder.ResolveDefinition
ToolBinder.resolveDeployable = ToolBinder.ResolveDeployable
ToolBinder.resolveStationTag = ToolBinder.ResolveStationTag
ToolBinder.isMelee = ToolBinder.IsMelee
ToolBinder.isMagic = ToolBinder.IsMagic
ToolBinder.resolveMeleeVariantTag = ToolBinder.ResolveMeleeVariantTag
ToolBinder.applyTags = ToolBinder.ApplyTags

return ToolBinder
