
local require = require(script.Parent.loader).load(script)

local Tile = require("Tile")

local Tree = {}

export type TreePartConfig = Tile.PartConfig
export type TreeModelConfig = Tile.ModelConfig
export type AttachmentConfig = Tile.AttachmentConfig
export type WeldConfig = Tile.WeldConfig

function Tree.CreateBranchPart(config: TreePartConfig): Part
	return Tile.CreatePart(config)
end

function Tree.CreateLeafPart(config: TreePartConfig): Part
	return Tile.CreatePart(config)
end

function Tree.CreateAnchorPart(config: TreePartConfig): Part
	return Tile.CreatePart(config)
end

function Tree.CreateTreeModel(config: TreeModelConfig): Model
	return Tile.CreateModel(config)
end

function Tree.CreatePartGroup(config: TreeModelConfig): Model
	return Tile.CreateModel(config)
end

function Tree.CreatePivotAttachment(config: AttachmentConfig): Attachment
	return Tile.CreateAttachment(config)
end

function Tree.CreateWeld(config: WeldConfig): WeldConstraint
	return Tile.CreateWeldConstraint(config)
end
return Tree
