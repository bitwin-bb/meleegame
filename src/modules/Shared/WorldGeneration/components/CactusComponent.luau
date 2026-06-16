
local require = require(script.Parent.loader).load(script)

local Tile = require("Tile")

local Cactus = {}

export type CactusPartConfig = Tile.PartConfig
export type CactusModelConfig = Tile.ModelConfig
export type CactusFolderConfig = Tile.FolderConfig
export type WeldConfig = Tile.WeldConfig

function Cactus.CreateSegmentPart(config: CactusPartConfig): Part
	return Tile.CreatePart(config)
end

function Cactus.CreateDetailPart(config: CactusPartConfig): Part
	return Tile.CreatePart(config)
end

function Cactus.CreateAnchorPart(config: CactusPartConfig): Part
	return Tile.CreatePart(config)
end

function Cactus.CreateModel(config: CactusModelConfig): Model
	return Tile.CreateModel(config)
end

function Cactus.CreateFolder(config: CactusFolderConfig): Folder
	return Tile.CreateFolder(config)
end

function Cactus.CreateWeld(config: WeldConfig): WeldConstraint
	return Tile.CreateWeldConstraint(config)
end

Cactus.createSegmentPart = Cactus.CreateSegmentPart
Cactus.createDetailPart = Cactus.CreateDetailPart
Cactus.createAnchorPart = Cactus.CreateAnchorPart
Cactus.createModel = Cactus.CreateModel
Cactus.createFolder = Cactus.CreateFolder
Cactus.createWeld = Cactus.CreateWeld

return Cactus
