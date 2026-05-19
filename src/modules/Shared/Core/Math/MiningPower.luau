--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Registry)

local MiningPower = {}

export type ToolProfile = {
	toolType: string?,
	toolPower: number,
}

export type SelectedToolContext = ToolProfile & {
	itemId: string,
	slotIndex: number,
}

export type TreeRequirement = {
	requiredToolType: string,
	requiredToolPower: number,
	treeTier: string,
}

export type TileRequirement = {
	requiredToolType: string,
	requiredToolPower: number,
	tileTier: string,
}

local TREE_REQUIREMENTS_BY_TOKEN: { [string]: TreeRequirement } = {
	defaulttree = {
		requiredToolType = "axe",
		requiredToolPower = 0,
		treeTier = "default",
	},
	foresttree = {
		requiredToolType = "axe",
		requiredToolPower = 0,
		treeTier = "forest",
	},
	jungletree = {
		requiredToolType = "axe",
		requiredToolPower = 35,
		treeTier = "jungle",
	},
	corrupttree = {
		requiredToolType = "axe",
		requiredToolPower = 50,
		treeTier = "corrupt",
	},
}

local TILE_REQUIREMENTS_BY_TOKEN: { [string]: TileRequirement } = {
	grass = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	dirt = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	stone = {
		requiredToolType = "pickaxe",
		requiredToolPower = 35,
		tileTier = "stone",
	},
	sand = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	sandstone = {
		requiredToolType = "pickaxe",
		requiredToolPower = 20,
		tileTier = "sandstone",
	},
	snow = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	ice = {
		requiredToolType = "pickaxe",
		requiredToolPower = 15,
		tileTier = "ice",
	},
	mud = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	clay = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	copperore = {
		requiredToolType = "pickaxe",
		requiredToolPower = 30,
		tileTier = "copper",
	},
	ironore = {
		requiredToolType = "pickaxe",
		requiredToolPower = 40,
		tileTier = "iron",
	},
	silverore = {
		requiredToolType = "pickaxe",
		requiredToolPower = 45,
		tileTier = "silver",
	},
	goldore = {
		requiredToolType = "pickaxe",
		requiredToolPower = 55,
		tileTier = "gold",
	},
	corruptgrass = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	corruptsoil = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	corruptstone = {
		requiredToolType = "pickaxe",
		requiredToolPower = 45,
		tileTier = "corrupt",
	},
	ebonstone = {
		requiredToolType = "pickaxe",
		requiredToolPower = 45,
		tileTier = "corrupt",
	},
	junglegrass = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
	wood = {
		requiredToolType = "pickaxe",
		requiredToolPower = 0,
		tileTier = "surface",
	},
}

local TILE_REQUIREMENTS_BY_ID: { [number]: TileRequirement } = {
	[1] = TILE_REQUIREMENTS_BY_TOKEN.grass,
	[2] = TILE_REQUIREMENTS_BY_TOKEN.dirt,
	[3] = TILE_REQUIREMENTS_BY_TOKEN.stone,
	[4] = TILE_REQUIREMENTS_BY_TOKEN.sand,
	[5] = TILE_REQUIREMENTS_BY_TOKEN.sandstone,
	[6] = TILE_REQUIREMENTS_BY_TOKEN.snow,
	[7] = TILE_REQUIREMENTS_BY_TOKEN.ice,
	[8] = TILE_REQUIREMENTS_BY_TOKEN.mud,
	[9] = TILE_REQUIREMENTS_BY_TOKEN.clay,
	[10] = TILE_REQUIREMENTS_BY_TOKEN.copperore,
	[11] = TILE_REQUIREMENTS_BY_TOKEN.ironore,
	[12] = TILE_REQUIREMENTS_BY_TOKEN.silverore,
	[13] = TILE_REQUIREMENTS_BY_TOKEN.goldore,
	[14] = TILE_REQUIREMENTS_BY_TOKEN.corruptgrass,
	[15] = TILE_REQUIREMENTS_BY_TOKEN.corruptsoil,
	[16] = TILE_REQUIREMENTS_BY_TOKEN.corruptstone,
	[17] = TILE_REQUIREMENTS_BY_TOKEN.junglegrass,
	[18] = TILE_REQUIREMENTS_BY_TOKEN.wood,
}

local DEFAULT_TILE_REQUIREMENT: TileRequirement = {
	requiredToolType = "pickaxe",
	requiredToolPower = 0,
	tileTier = "default",
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeItemId(itemIdRaw: any): string?
	local itemId = trim(itemIdRaw)
	if itemId == "" then
		return nil
	end
	return itemId
end

local function normalizeToken(valueRaw: any): string
	local value = string.lower(trim(valueRaw))
	if value == "" then
		return ""
	end
	return string.gsub(value, "[%s_%-%%%.]+", "")
end

local function parseNumericValue(valueRaw: any): number?
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		return valueRaw
	end
	if typeof(valueRaw) ~= "string" then
		return nil
	end

	local numericText = string.match(string.lower(valueRaw), "%-?%d+%.?%d*")
	if numericText == nil then
		return nil
	end

	local parsed = tonumber(numericText)
	if parsed == nil or parsed ~= parsed then
		return nil
	end
	return parsed
end

local function capitalizeToken(valueRaw: any): string?
	local normalized = normalizeToken(valueRaw)
	if normalized == "" then
		return nil
	end
	return string.upper(string.sub(normalized, 1, 1)) .. string.sub(normalized, 2)
end

local function coerceDefinition(definitionRaw: any): { [string]: any }
	if typeof(definitionRaw) == "table" then
		return definitionRaw :: { [string]: any }
	end
	return {}
end

function MiningPower.ParsePowerPercent(valueRaw: any): number?
	local numericValue = parseNumericValue(valueRaw)
	if numericValue == nil then
		return nil
	end
	return math.max(0, numericValue)
end

function MiningPower.ResolveToolPower(definitionRaw: any, fallbackRaw: any?): number
	local definition = coerceDefinition(definitionRaw)
	local stats = coerceDefinition(definition.stats)
	local mining = coerceDefinition(definition.mining)

	local candidates = {
		mining.power,
		mining.toolPower,
		mining.miningPower,
		definition.power,
		definition.toolPower,
		definition.miningPower,
		stats.power,
		stats.toolPower,
		stats.miningPower,
		fallbackRaw,
	}

	for _, candidate in candidates do
		local resolved = MiningPower.ParsePowerPercent(candidate)
		if resolved ~= nil then
			return resolved
		end
	end

	return 0
end

function MiningPower.ResolveToolType(definitionRaw: any, fallbackRaw: any?): string?
	local definition = coerceDefinition(definitionRaw)
	local mining = coerceDefinition(definition.mining)

	local candidates = {
		mining.toolType,
		mining.harvestType,
		definition.toolType,
		definition.harvestType,
		definition.itemType,
		definition.type,
		fallbackRaw,
	}

	for _, candidate in candidates do
		local normalized = normalizeToken(candidate)
		if normalized ~= "" then
			return normalized
		end
	end

	return nil
end

function MiningPower.ResolveToolProfile(definitionRaw: any, fallbackTypeRaw: any?, fallbackPowerRaw: any?): ToolProfile
	return {
		toolType = MiningPower.ResolveToolType(definitionRaw, fallbackTypeRaw),
		toolPower = MiningPower.ResolveToolPower(definitionRaw, fallbackPowerRaw),
	}
end

function MiningPower.ResolveItemToolProfile(itemIdRaw: any): ToolProfile?
	local itemId = sanitizeItemId(itemIdRaw)
	if itemId == nil then
		return nil
	end

	local canonicalItemId = ItemRegistry.resolveCanonicalItemId(itemId)
	if canonicalItemId == nil then
		return nil
	end

	local definition = ItemRegistry.resolveDefinition(canonicalItemId)
	if typeof(definition) ~= "table" then
		return nil
	end

	local profile = MiningPower.ResolveToolProfile(definition, nil, nil)
	if profile.toolType == nil then
		return nil
	end

	return profile
end

function MiningPower.ResolveSelectedToolContextFromInventoryState(stateRaw: any): SelectedToolContext?
	if typeof(stateRaw) ~= "table" then
		return nil
	end

	local state = stateRaw :: { [string]: any }
	local selectedSlotRaw = state.selectedSlot
	if typeof(selectedSlotRaw) ~= "number" or selectedSlotRaw ~= selectedSlotRaw then
		return nil
	end

	local selectedSlot = math.floor(selectedSlotRaw)
	if selectedSlot <= 0 then
		return nil
	end

	local slots = state.slots
	if typeof(slots) ~= "table" then
		return nil
	end

	local slot = slots[selectedSlot]
	if typeof(slot) ~= "table" then
		return nil
	end

	local stack = (slot :: { [string]: any }).stack
	if typeof(stack) ~= "table" then
		return nil
	end

	local stackTable = stack :: { [string]: any }
	local amount = stackTable.amount
	if typeof(amount) == "number" and amount == amount and amount <= 0 then
		return nil
	end

	local canonicalItemId = ItemRegistry.resolveCanonicalItemId(stackTable.itemId)
	if canonicalItemId == nil then
		return nil
	end

	local profile = MiningPower.ResolveItemToolProfile(canonicalItemId)
	if profile == nil then
		return nil
	end

	return {
		itemId = canonicalItemId,
		slotIndex = selectedSlot,
		toolType = profile.toolType,
		toolPower = profile.toolPower,
	}
end

function MiningPower.ResolveTreeRequirement(treeTypeRaw: any): TreeRequirement
	local normalized = normalizeToken(treeTypeRaw)
	if normalized ~= "" then
		local direct = TREE_REQUIREMENTS_BY_TOKEN[normalized]
		if direct ~= nil then
			return direct
		end

		if string.find(normalized, "corrupt", 1, true) ~= nil or string.find(normalized, "ebon", 1, true) ~= nil then
			return TREE_REQUIREMENTS_BY_TOKEN.corrupttree
		end
		if string.find(normalized, "jungle", 1, true) ~= nil or string.find(normalized, "mahogany", 1, true) ~= nil then
			return TREE_REQUIREMENTS_BY_TOKEN.jungletree
		end
		if string.find(normalized, "forest", 1, true) ~= nil or string.find(normalized, "wood", 1, true) ~= nil then
			return TREE_REQUIREMENTS_BY_TOKEN.foresttree
		end
	end

	return TREE_REQUIREMENTS_BY_TOKEN.defaulttree
end

function MiningPower.ResolveTileRequirement(tileIdRaw: any, tileNameRaw: any?): TileRequirement
	if typeof(tileIdRaw) == "number" and tileIdRaw == tileIdRaw then
		local direct = TILE_REQUIREMENTS_BY_ID[math.floor(tileIdRaw)]
		if direct ~= nil then
			return direct
		end
	end

	local normalized = normalizeToken(tileNameRaw)
	if normalized ~= "" then
		local direct = TILE_REQUIREMENTS_BY_TOKEN[normalized]
		if direct ~= nil then
			return direct
		end

		if string.find(normalized, "corrupt", 1, true) ~= nil or string.find(normalized, "ebon", 1, true) ~= nil then
			return TILE_REQUIREMENTS_BY_TOKEN.corruptstone
		end
		if string.find(normalized, "gold", 1, true) ~= nil then
			return TILE_REQUIREMENTS_BY_TOKEN.goldore
		end
		if string.find(normalized, "silver", 1, true) ~= nil then
			return TILE_REQUIREMENTS_BY_TOKEN.silverore
		end
		if string.find(normalized, "iron", 1, true) ~= nil then
			return TILE_REQUIREMENTS_BY_TOKEN.ironore
		end
		if string.find(normalized, "copper", 1, true) ~= nil then
			return TILE_REQUIREMENTS_BY_TOKEN.copperore
		end
		if string.find(normalized, "stone", 1, true) ~= nil then
			return TILE_REQUIREMENTS_BY_TOKEN.stone
		end
	end

	return DEFAULT_TILE_REQUIREMENT
end

function MiningPower.ToToolAttributeBundle(
	definitionRaw: any,
	fallbackTypeRaw: any?,
	fallbackPowerRaw: any?
): { [string]: any }
	local profile = MiningPower.ResolveToolProfile(definitionRaw, fallbackTypeRaw, fallbackPowerRaw)
	local attributes: { [string]: any } = {}
	local toolType = profile.toolType
	if toolType ~= nil then
		local capitalizedToolType = capitalizeToken(toolType)
		attributes.ToolType = toolType
		attributes.HarvestType = toolType
		if capitalizedToolType ~= nil then
			attributes.WeaponType = capitalizedToolType
		end
	end

	attributes.ToolPower = profile.toolPower
	attributes.MiningPower = profile.toolPower

	if toolType == "pickaxe" then
		attributes.PickaxePower = profile.toolPower
	elseif toolType == "axe" then
		attributes.AxePower = profile.toolPower
	end

	return attributes
end

MiningPower.parsePowerPercent = MiningPower.ParsePowerPercent
MiningPower.resolveToolPower = MiningPower.ResolveToolPower
MiningPower.resolveToolType = MiningPower.ResolveToolType
MiningPower.resolveToolProfile = MiningPower.ResolveToolProfile
MiningPower.resolveItemToolProfile = MiningPower.ResolveItemToolProfile
MiningPower.resolveSelectedToolContextFromInventoryState = MiningPower.ResolveSelectedToolContextFromInventoryState
MiningPower.resolveTreeRequirement = MiningPower.ResolveTreeRequirement
MiningPower.resolveTileRequirement = MiningPower.ResolveTileRequirement
MiningPower.toToolAttributeBundle = MiningPower.ToToolAttributeBundle

return MiningPower
