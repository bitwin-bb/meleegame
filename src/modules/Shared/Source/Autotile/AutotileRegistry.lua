local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local definitionsFolder = script.Parent:WaitForChild("Definitions")

local AutotileRegistry = {}

local definitionsByTileId = {}
local definitionsById = {}

local DEFINITION_MODULE_NAMES = Table.readonly({
	"Grass",
	"Dirt",
	"Stone",
	"Sand",
	"Sandstone",
	"Snow",
	"Ice",
	"Mud",
	"Clay",
	"CopperOre",
	"IronOre",
	"SilverOre",
	"GoldOre",
	"CorruptGrass",
	"CorruptSoil",
	"CorruptStone",
	"JungleGrass",
	"Wood",
})

local function normalizeId(idRaw: any): string?
	if typeof(idRaw) ~= "string" or idRaw == "" then
		return nil
	end
	return string.lower(idRaw)
end

function AutotileRegistry.RegisterDefinition(definitionRaw: any): boolean
	if typeof(definitionRaw) ~= "table" then
		return false
	end

	local definition = definitionRaw :: any
	if typeof(definition.TileId) ~= "number" then
		return false
	end
	if typeof(definition.Id) ~= "string" or definition.Id == "" then
		return false
	end

	local tileId = math.floor(definition.TileId)
	definitionsByTileId[tileId] = definition
	definitionsById[normalizeId(definition.Id) :: string] = definition
	return true
end

local function loadDefinition(moduleName: string)
	local module = definitionsFolder:FindFirstChild(moduleName)
	if module == nil then
		return
	end
	AutotileRegistry.RegisterDefinition(require(module))
end

for _, moduleName in DEFINITION_MODULE_NAMES do
	loadDefinition(moduleName)
end

function AutotileRegistry.GetDefinition(tileIdRaw: any): any?
	if typeof(tileIdRaw) == "number" then
		return definitionsByTileId[math.floor(tileIdRaw)]
	end

	local id = normalizeId(tileIdRaw)
	if id ~= nil then
		return definitionsById[id]
	end

	return nil
end

function AutotileRegistry.GetAtlas(tileIdRaw: any): any?
	return AutotileRegistry.GetDefinition(tileIdRaw)
end

function AutotileRegistry.HasDefinition(tileIdRaw: any): boolean
	return AutotileRegistry.GetDefinition(tileIdRaw) ~= nil
end

function AutotileRegistry.GetDefinitions(): { [number]: any }
	return table.clone(definitionsByTileId)
end

return Table.readonly(AutotileRegistry)
