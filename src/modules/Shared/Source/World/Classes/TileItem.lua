local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)

local Children = Fusion.Children

local TileItem = {}
TileItem.__index = TileItem

export type TileDefinition = {
	itemId: string,
	displayName: string,
	material: Enum.Material,
	color: Color3,
}

local TILE_DEFINITION_BY_ID: { [string]: TileDefinition } = {
	Wood = {
		itemId = "Wood",
		displayName = "Wood",
		material = Enum.Material.Wood,
		color = Color3.fromRGB(111, 72, 42),
	},
	Dirt = {
		itemId = "Dirt",
		displayName = "Dirt",
		material = Enum.Material.Ground,
		color = Color3.fromRGB(92, 64, 42),
	},
	Stone = {
		itemId = "Stone",
		displayName = "Stone",
		material = Enum.Material.Slate,
		color = Color3.fromRGB(93, 95, 96),
	},
	Snow = {
		itemId = "Snow",
		displayName = "Snow",
		material = Enum.Material.Snow,
		color = Color3.fromRGB(235, 242, 244),
	},
	Ice = {
		itemId = "Ice",
		displayName = "Ice",
		material = Enum.Material.Ice,
		color = Color3.fromRGB(170, 221, 241),
	},
	Mud = {
		itemId = "Mud",
		displayName = "Mud",
		material = Enum.Material.Ground,
		color = Color3.fromRGB(56, 50, 42),
	},
	RichMahogany = {
		itemId = "RichMahogany",
		displayName = "Rich Mahogany",
		material = Enum.Material.Wood,
		color = Color3.fromRGB(82, 41, 26),
	},
	EbonStone = {
		itemId = "EbonStone",
		displayName = "Ebon Stone",
		material = Enum.Material.Slate,
		color = Color3.fromRGB(76, 50, 103),
	},
}

local TILE_ID_ALIAS = {
	CorruptStone = "EbonStone",
}

local function GetDefinition(tileIdRaw: any): TileDefinition?
	if typeof(tileIdRaw) ~= "string" then
		return nil
	end

	local tileId = TILE_ID_ALIAS[tileIdRaw] or tileIdRaw
	return TILE_DEFINITION_BY_ID[tileId]
end

function TileItem.new(scope: any)
	assert(typeof(scope) == "table", "bad scope")

	local self = setmetatable({}, TileItem)
	self._scope = scope
	return self
end

function TileItem:NewTile(tileIdRaw: any): Tool
	local definition = GetDefinition(tileIdRaw)
	assert(definition ~= nil, "unknown tile item")

	local scope = self._scope
	local block = scope:New "Part" {
		Name = definition.itemId,
		Size = Vector3.new(1, 1, 1),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Massless = true,
		Material = definition.material,
		Color = definition.color,
	}

	local handle = scope:New "Part" {
		Name = "Handle",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Massless = true,
		Transparency = 1,
	}

	scope:New "WeldConstraint" {
		Name = "HandleWeld",
		Part0 = handle,
		Part1 = block,
		Parent = handle,
	}

	return scope:New "Tool" {
		Name = definition.displayName,
		RequiresHandle = true,
		CanBeDropped = true,
		[Fusion.Attribute("itemId")] = definition.itemId,
		[Fusion.Attribute("ItemId")] = definition.itemId,
		[Fusion.Attribute("itemType")] = "Tile",
		[Fusion.Attribute("ItemType")] = "Tile",
		[Children] = {
			handle,
			scope:New "Model" {
				Name = "Contents",
				[Children] = {
					block,
				},
			},
		},
	}
end
TileItem.GetDefinition = GetDefinition

export type TileItem = typeof(setmetatable({} :: { _scope: any }, TileItem))

return TileItem
