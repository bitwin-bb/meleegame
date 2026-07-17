local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local AutotileTypes = {}

AutotileTypes.Modes = Table.readonly({
	FourWay16 = "FourWay16",
	EightWayBlob = "EightWayBlob",
	Full256 = "Full256",
})
AutotileTypes.DEFAULT_MODE = AutotileTypes.Modes.EightWayBlob

export type AutotileMode = "FourWay16" | "EightWayBlob" | "Full256"

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
	ImageRectScale: (number | Vector2)?,
	Mode: AutotileMode,
	ConnectGroup: string?,
	UseSurfaceGui: boolean?,
	Entries: { [number]: AtlasEntry },
	Aliases: { [number]: number }?,
	Fallback: AtlasEntry,
	VariantSeed: number?,
}

export type TileAccessor = ((x: number, y: number) -> TileData?) | {
	GetTile: ((self: any, x: number, y: number) -> TileData?)?,
	GetTileAtCoord: ((self: any, coord: Vector2) -> TileData?)?,
}

function AutotileTypes.CoerceMode(modeRaw: any): AutotileMode
	if modeRaw == AutotileTypes.Modes.FourWay16 then
		return AutotileTypes.Modes.FourWay16
	end
	if modeRaw == AutotileTypes.Modes.Full256 then
		return AutotileTypes.Modes.Full256
	end
	return AutotileTypes.DEFAULT_MODE
end

function AutotileTypes.UsesSurfaceGui(definitionRaw: any): boolean
	return typeof(definitionRaw) == "table" and rawget(definitionRaw, "UseSurfaceGui") == true
end

return Table.readonly(AutotileTypes)
