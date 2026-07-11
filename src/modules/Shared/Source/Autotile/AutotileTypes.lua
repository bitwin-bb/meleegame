local require = require(script.Parent.loader).load(script)

local Table = require("Table")

export type TileData = {
	TileId: number?,
	tileId: number?,
	ConnectGroup: string?,
	connectGroup: string?,
}

export type VariantEntry = {
	Cell: Vector2,
	Weight: number?,
	Image: string?,
}

export type AtlasEntry = {
	Cell: Vector2?,
	Image: string?,
	Variants: { VariantEntry }?,
}

export type RectResult = {
	ImageRectOffset: Vector2,
	ImageRectSize: Vector2,
}

export type AtlasResult = RectResult & {
	Image: string,
	Mask: number,
	RequestedMask: number,
	Cell: Vector2?,
	Entry: AtlasEntry?,
}

export type AtlasDefinition = {
	Id: string,
	TileId: number,
	Image: string,
	TileSize: number | Vector2,
	Padding: number?,
	Spacing: number?,
	Mode: string,
	ConnectGroup: string?,
	Entries: { [number]: AtlasEntry },
	Aliases: { [number]: number }?,
	Fallback: AtlasEntry,
	VariantSeed: number?,
}

export type TileAccessor = ((x: number, y: number) -> TileData?) | {
	GetTile: ((self: any, x: number, y: number) -> TileData?)?,
	GetTileAtCoord: ((self: any, coord: Vector2) -> TileData?)?,
}

return Table.readonly({})
