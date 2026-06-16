local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Children = Fusion.Children

local Tile = {}

export type AttributeMap = { [string]: any }

export type PartConfig = {
	name: string?,
	parent: Instance?,
	children: { Instance }?,
	attributes: AttributeMap?,
	size: Vector3?,
	cframe: CFrame?,
	color: Color3?,
	material: Enum.Material?,
	materialVariant: string?,
	transparency: number?,
	reflectance: number?,
	anchored: boolean?,
	locked: boolean?,
	massless: boolean?,
	castShadow: boolean?,
	canCollide: boolean?,
	canQuery: boolean?,
	canTouch: boolean?,
	shape: Enum.PartType?,
}

export type TextureConfig = {
	name: string?,
	parent: Instance?,
	face: Enum.NormalId?,
	texture: string?,
	color: Color3?,
	studsPerTileU: number?,
	studsPerTileV: number?,
	transparency: number?,
}

export type HighlightConfig = {
	name: string?,
	parent: Instance?,
	adornee: Instance?,
	depthMode: Enum.HighlightDepthMode?,
	fillColor: Color3?,
	fillTransparency: number?,
	outlineColor: Color3?,
	outlineTransparency: number?,
	enabled: boolean?,
}

export type ModelConfig = {
	name: string?,
	parent: Instance?,
	children: { Instance }?,
	attributes: AttributeMap?,
}

export type FolderConfig = {
	name: string?,
	parent: Instance?,
	children: { Instance }?,
	attributes: AttributeMap?,
}

export type AttachmentConfig = {
	name: string?,
	parent: Instance?,
	position: Vector3?,
	cframe: CFrame?,
	attributes: AttributeMap?,
}

export type WeldConfig = {
	name: string?,
	parent: Instance?,
	part0: BasePart?,
	part1: BasePart?,
	enabled: boolean?,
	attributes: AttributeMap?,
}

export type BindableEventConfig = {
	name: string?,
	parent: Instance?,
	attributes: AttributeMap?,
}

local function assignAttributes(props: any, attributesRaw: AttributeMap?)
	if typeof(attributesRaw) ~= "table" then
		return
	end

	for key, value in attributesRaw do
		if typeof(key) == "string" then
			props[Fusion.Attribute(key)] = value
		end
	end
end

local function assignInstance(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "Instance" then
		props[propertyName] = valueRaw
	end
end

local function assignString(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "string" then
		props[propertyName] = valueRaw
	end
end

local function assignBoolean(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "boolean" then
		props[propertyName] = valueRaw
	end
end

local function assignNumber(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		props[propertyName] = valueRaw
	end
end

local function assignVector3(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "Vector3" then
		props[propertyName] = valueRaw
	end
end

local function assignCFrame(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "CFrame" then
		props[propertyName] = valueRaw
	end
end

local function assignColor3(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "Color3" then
		props[propertyName] = valueRaw
	end
end

local function assignEnumItem(props: any, propertyName: string, valueRaw: any)
	if typeof(valueRaw) == "EnumItem" then
		props[propertyName] = valueRaw
	end
end

local function assignChildren(props: any, childrenRaw: { Instance }?)
	if typeof(childrenRaw) == "table" then
		props[Children] = childrenRaw
	end
end

local function applyBasePartProps(props: any, config: PartConfig)
	assignString(props, "Name", config.name)
	assignVector3(props, "Size", config.size)
	assignCFrame(props, "CFrame", config.cframe)
	assignColor3(props, "Color", config.color)
	assignEnumItem(props, "Material", config.material)
	assignString(props, "MaterialVariant", config.materialVariant)
	assignNumber(props, "Transparency", config.transparency)
	assignNumber(props, "Reflectance", config.reflectance)
	assignBoolean(props, "Anchored", config.anchored)
	assignBoolean(props, "Locked", config.locked)
	assignBoolean(props, "Massless", config.massless)
	assignBoolean(props, "CastShadow", config.castShadow)
	assignBoolean(props, "CanCollide", config.canCollide)
	assignBoolean(props, "CanQuery", config.canQuery)
	assignBoolean(props, "CanTouch", config.canTouch)
	assignEnumItem(props, "Shape", config.shape)
	assignInstance(props, "Parent", config.parent)
	assignChildren(props, config.children)
	assignAttributes(props, config.attributes)
end

function Tile.CreatePart(configRaw: PartConfig?): Part
	local config = if typeof(configRaw) == "table" then configRaw :: PartConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	applyBasePartProps(props, config)
	return (scope:New("Part"))(props) :: Part
end

function Tile.CreateWedgePart(configRaw: PartConfig?): WedgePart
	local config = if typeof(configRaw) == "table" then configRaw :: PartConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	applyBasePartProps(props, config)
	return (scope:New("WedgePart"))(props) :: WedgePart
end

function Tile.CreateTexture(configRaw: TextureConfig?): Texture
	local config = if typeof(configRaw) == "table" then configRaw :: TextureConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	assignString(props, "Name", config.name)
	assignEnumItem(props, "Face", config.face)
	assignString(props, "Texture", config.texture)
	assignColor3(props, "Color3", config.color)
	assignNumber(props, "StudsPerTileU", config.studsPerTileU)
	assignNumber(props, "StudsPerTileV", config.studsPerTileV)
	assignNumber(props, "Transparency", config.transparency)
	assignInstance(props, "Parent", config.parent)
	return (scope:New("Texture"))(props) :: Texture
end

function Tile.CreateHighlight(configRaw: HighlightConfig?): Highlight
	local config = if typeof(configRaw) == "table" then configRaw :: HighlightConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	assignString(props, "Name", config.name)
	assignInstance(props, "Adornee", config.adornee)
	assignEnumItem(props, "DepthMode", config.depthMode)
	assignColor3(props, "FillColor", config.fillColor)
	assignNumber(props, "FillTransparency", config.fillTransparency)
	assignColor3(props, "OutlineColor", config.outlineColor)
	assignNumber(props, "OutlineTransparency", config.outlineTransparency)
	assignBoolean(props, "Enabled", config.enabled)
	assignInstance(props, "Parent", config.parent)
	return (scope:New("Highlight"))(props) :: Highlight
end

function Tile.CreateModel(configRaw: ModelConfig?): Model
	local config = if typeof(configRaw) == "table" then configRaw :: ModelConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	assignString(props, "Name", config.name)
	assignInstance(props, "Parent", config.parent)
	assignChildren(props, config.children)
	assignAttributes(props, config.attributes)
	return (scope:New("Model"))(props) :: Model
end

function Tile.CreateFolder(configRaw: FolderConfig?): Folder
	local config = if typeof(configRaw) == "table" then configRaw :: FolderConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	assignString(props, "Name", config.name)
	assignInstance(props, "Parent", config.parent)
	assignChildren(props, config.children)
	assignAttributes(props, config.attributes)
	return (scope:New("Folder"))(props) :: Folder
end

function Tile.CreateAttachment(configRaw: AttachmentConfig?): Attachment
	local config = if typeof(configRaw) == "table" then configRaw :: AttachmentConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	assignString(props, "Name", config.name)
	assignVector3(props, "Position", config.position)
	assignCFrame(props, "CFrame", config.cframe)
	assignInstance(props, "Parent", config.parent)
	assignAttributes(props, config.attributes)
	return (scope:New("Attachment"))(props) :: Attachment
end

function Tile.CreateWeldConstraint(configRaw: WeldConfig?): WeldConstraint
	local config = if typeof(configRaw) == "table" then configRaw :: WeldConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	assignString(props, "Name", config.name)
	assignInstance(props, "Part0", config.part0)
	assignInstance(props, "Part1", config.part1)
	assignBoolean(props, "Enabled", config.enabled)
	assignInstance(props, "Parent", config.parent)
	assignAttributes(props, config.attributes)
	return (scope:New("WeldConstraint"))(props) :: WeldConstraint
end

function Tile.CreateBindableEvent(configRaw: BindableEventConfig?): BindableEvent
	local config = if typeof(configRaw) == "table" then configRaw :: BindableEventConfig else {} :: any
	local scope = Fusion.scoped(Fusion)
	local props = {} :: any
	assignString(props, "Name", config.name)
	assignInstance(props, "Parent", config.parent)
	assignAttributes(props, config.attributes)
	return (scope:New("BindableEvent"))(props) :: BindableEvent
end

Tile.createPart = Tile.CreatePart
Tile.createWedgePart = Tile.CreateWedgePart
Tile.createTexture = Tile.CreateTexture
Tile.createHighlight = Tile.CreateHighlight
Tile.createModel = Tile.CreateModel
Tile.createFolder = Tile.CreateFolder
Tile.createAttachment = Tile.CreateAttachment
Tile.createWeldConstraint = Tile.CreateWeldConstraint
Tile.createBindableEvent = Tile.CreateBindableEvent

return Tile
