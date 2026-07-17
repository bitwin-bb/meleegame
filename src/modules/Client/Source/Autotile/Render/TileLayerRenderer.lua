local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")

local TileLayerRenderer = {}
TileLayerRenderer.__index = TileLayerRenderer

local TileImageSprite = {}
TileImageSprite.__index = TileImageSprite

local DEFAULT_TILE_SIZE = 2
local DEFAULT_PLANE_DEPTH = 2
local DEFAULT_PIXELS_PER_STUD = 8
local MAX_POOLED_SPRITES_PER_CHUNK = 64
local MAX_IDLE_POOLED_SPRITES_PER_CHUNK = 16
local SURFACE_FACE = Enum.NormalId.Right
local TILE_IMAGE_Z_INDEX = 2
local DEFAULT_CONTAINER_NAME = "AutotileLayer"
local DEFAULT_ROOT_NAME = "AutotileRoot"
local DEFAULT_SURFACE_NAME = "AutotileSurface"
local DEFAULT_IMAGE_NAME = "AutotileImage"

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getNumberAttribute(instance: Instance, names: { string }, fallback: number): number
	for _, name in names do
		local value = instance:GetAttribute(name)
		if isFiniteNumber(value) then
			return math.floor(value :: number)
		end
	end
	return fallback
end

local function createTileImage(imageName: string, imageZIndex: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = imageName
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = ""
	image.ImageRectOffset = Vector2.zero
	image.ImageRectSize = Vector2.zero
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.ScaleType = Enum.ScaleType.Stretch
	image.ZIndex = imageZIndex
	image.Visible = false
	return image
end

function TileImageSprite.new(parent: Instance, imageName: string, imageZIndex: number): any
	local image = createTileImage(imageName, imageZIndex)
	image.Parent = parent
	return setmetatable({
		_image = image,
	}, TileImageSprite)
end

function TileImageSprite.SetParent(self: any, parent: Instance?)
	if self._image ~= nil and self._image.Parent ~= parent then
		self._image.Parent = parent
	end
end

function TileImageSprite.SetLayout(self: any, position: UDim2, size: UDim2)
	if self._image == nil then
		return
	end
	if self._image.Position ~= position then
		self._image.Position = position
	end
	if self._image.Size ~= size then
		self._image.Size = size
	end
end

function TileImageSprite.Update(self: any, atlasResult: any?)
	local image = self._image
	if image == nil then
		return
	end
	if typeof(atlasResult) ~= "table" then
		if image.Visible then
			image.Visible = false
		end
		return
	end

	local nextImage = atlasResult.Image or ""
	local nextImageRectOffset = atlasResult.ImageRectOffset or Vector2.zero
	local nextImageRectSize = atlasResult.ImageRectSize or Vector2.zero
	if image.Image ~= nextImage then
		image.Image = nextImage
	end
	if image.ImageRectOffset ~= nextImageRectOffset then
		image.ImageRectOffset = nextImageRectOffset
	end
	if image.ImageRectSize ~= nextImageRectSize then
		image.ImageRectSize = nextImageRectSize
	end
	if not image.Visible then
		image.Visible = true
	end
end

function TileImageSprite.Destroy(self: any)
	if self._image ~= nil then
		self._image:Destroy()
		self._image = nil
	end
end

local function coerceDimension(valueRaw: any, fallback: number): number
	if isFiniteNumber(valueRaw) then
		return math.max(1, math.floor(valueRaw :: number))
	end
	return math.max(1, fallback)
end

function TileLayerRenderer.new(parent: Instance, widthRaw: any?, heightRaw: any?, optionsRaw: any?): any
	local maid = Maid.new()
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local chunkSize = math.max(1, getNumberAttribute(parent, { "ChunkSize", "chunkSize" }, 32))
	local width =
		coerceDimension(widthRaw, getNumberAttribute(parent, { "Width", "TileWidth", "tileWidth" }, chunkSize))
	local height =
		coerceDimension(heightRaw, getNumberAttribute(parent, { "Height", "TileHeight", "tileHeight" }, chunkSize))
	local container = Instance.new("Folder")
	container.Name = if typeof((options :: any).containerName) == "string"
			and (options :: any).containerName ~= ""
		then (options :: any).containerName
		else DEFAULT_CONTAINER_NAME
	container.Parent = parent
	local frameScale = if isFiniteNumber((options :: any).frameScale)
		then math.max(1, (options :: any).frameScale :: number)
		else 1

	local self = setmetatable({
		_maid = maid,
		_width = width,
		_height = height,
		_spritesByKey = {},
		_spritePool = {},
		_activeSpriteCount = 0,
		_container = container,
		_frameScale = frameScale,
		_rootName = if typeof((options :: any).rootName) == "string" and (options :: any).rootName ~= ""
			then (options :: any).rootName
			else DEFAULT_ROOT_NAME,
		_surfaceName = if typeof((options :: any).surfaceName) == "string"
				and (options :: any).surfaceName ~= ""
			then (options :: any).surfaceName
			else DEFAULT_SURFACE_NAME,
		_imageName = if typeof((options :: any).imageName) == "string" and (options :: any).imageName ~= ""
			then (options :: any).imageName
			else DEFAULT_IMAGE_NAME,
		_imageZIndex = if isFiniteNumber((options :: any).imageZIndex)
			then math.floor((options :: any).imageZIndex :: number)
			else TILE_IMAGE_Z_INDEX,
		_surfaceRoot = nil,
		_surfaceGui = nil,
		_tilePixelWidth = math.round(DEFAULT_TILE_SIZE * DEFAULT_PIXELS_PER_STUD),
		_tilePixelHeight = math.round(DEFAULT_TILE_SIZE * DEFAULT_PIXELS_PER_STUD),
	}, TileLayerRenderer)

	maid:GiveTask(container)

	return self
end

function TileLayerRenderer.GetContainer(self: any): Folder?
	return self._container
end

function TileLayerRenderer._ensureSurface(self: any, localX: number, localY: number, layoutRaw: any)
	local layout = if typeof(layoutRaw) == "table" then layoutRaw else {}
	local tileSize = if typeof((layout :: any).size) == "Vector3"
		then (layout :: any).size
		else Vector3.new(DEFAULT_PLANE_DEPTH, DEFAULT_TILE_SIZE, DEFAULT_TILE_SIZE)
	local tileCFrame = if typeof((layout :: any).cframe) == "CFrame"
		then (layout :: any).cframe
		else CFrame.new(0, (localY + 0.5) * tileSize.Y, (localX + 0.5) * tileSize.Z)
	local pixelsPerStud = if isFiniteNumber((layout :: any).pixelsPerStud)
		then math.max(0.001, (layout :: any).pixelsPerStud)
		else DEFAULT_PIXELS_PER_STUD
	local rootSize = Vector3.new(
		math.max(0.05, tileSize.X),
		math.max(0.05, tileSize.Y * (self._height + self._frameScale - 1)),
		math.max(0.05, tileSize.Z * (self._width + self._frameScale - 1))
	)
	local rootCFrame = tileCFrame
		* CFrame.new(
			0,
			((self._height - 1) * 0.5 - localY) * tileSize.Y,
			((self._width - 1) * 0.5 - localX) * tileSize.Z
		)

	if self._surfaceRoot == nil then
		local root = Instance.new("Part")
		root.Name = self._rootName
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.CastShadow = false
		root.Locked = true
		root.Massless = true
		root.Material = Enum.Material.SmoothPlastic
		root.MaterialVariant = ""
		root.Transparency = 1
		root.Parent = self._container

		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = self._surfaceName
		surfaceGui.AlwaysOnTop = false
		surfaceGui.Brightness = 1
		surfaceGui.Enabled = false
		surfaceGui.Face = SURFACE_FACE
		surfaceGui.LightInfluence = 0
		surfaceGui.MaxDistance = 100000
		surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		surfaceGui.Parent = root

		self._surfaceRoot = root
		self._surfaceGui = surfaceGui
	end

	if self._surfaceRoot.CFrame ~= rootCFrame then
		self._surfaceRoot.CFrame = rootCFrame
	end
	if self._surfaceRoot.Size ~= rootSize then
		self._surfaceRoot.Size = rootSize
	end
	if self._surfaceGui.PixelsPerStud ~= pixelsPerStud then
		self._surfaceGui.PixelsPerStud = pixelsPerStud
	end
	self._tilePixelWidth = math.max(1, math.round(tileSize.Z * pixelsPerStud))
	self._tilePixelHeight = math.max(1, math.round(tileSize.Y * pixelsPerStud))
end

function TileLayerRenderer._acquireSprite(self: any): any
	local pool = self._spritePool
	local count = #pool
	if count > 0 then
		local sprite = pool[count]
		pool[count] = nil
		sprite:SetParent(self._surfaceGui)
		return sprite
	end
	return TileImageSprite.new(self._surfaceGui, self._imageName, self._imageZIndex)
end

function TileLayerRenderer._releaseSprite(self: any, sprite: any)
	sprite:Update(nil)
	sprite:SetParent(nil)
	if #self._spritePool < MAX_POOLED_SPRITES_PER_CHUNK then
		self._spritePool[#self._spritePool + 1] = sprite
	else
		sprite:Destroy()
	end
end

function TileLayerRenderer._releaseSurfaceIfEmpty(self: any)
	if self._activeSpriteCount > 0 or self._surfaceRoot == nil then
		return
	end
	while #self._spritePool > MAX_IDLE_POOLED_SPRITES_PER_CHUNK do
		local sprite = self._spritePool[#self._spritePool]
		self._spritePool[#self._spritePool] = nil
		sprite:Destroy()
	end
	self._surfaceRoot:Destroy()
	self._surfaceRoot = nil
	self._surfaceGui = nil
end

function TileLayerRenderer.GetSprite(self: any, localX: number, localY: number): any?
	if localX < 0 or localX >= self._width or localY < 0 or localY >= self._height then
		return nil
	end
	return self._spritesByKey[localY * self._width + localX]
end

function TileLayerRenderer.SetTile(self: any, localX: number, localY: number, atlasResult: any?, layout: any?)
	if localX < 0 or localX >= self._width or localY < 0 or localY >= self._height then
		return
	end
	if atlasResult == nil then
		self:ClearTile(localX, localY)
		return
	end

	local key = localY * self._width + localX
	local sprite = self._spritesByKey[key]
	self:_ensureSurface(localX, localY, layout)
	if sprite == nil then
		sprite = self:_acquireSprite()
		self._spritesByKey[key] = sprite
		self._activeSpriteCount += 1
	end

	local position = UDim2.fromOffset(
		(self._width - localX - 1) * self._tilePixelWidth,
		(self._height - localY - 1) * self._tilePixelHeight
	)
	sprite:SetLayout(
		position,
		UDim2.fromOffset(self._tilePixelWidth * self._frameScale, self._tilePixelHeight * self._frameScale)
	)
	sprite:Update(atlasResult)
	if not self._surfaceGui.Enabled then
		self._surfaceGui.Enabled = true
	end
end

function TileLayerRenderer.ClearTile(self: any, localX: number, localY: number)
	if localX < 0 or localX >= self._width or localY < 0 or localY >= self._height then
		return
	end
	local key = localY * self._width + localX
	local sprite = self._spritesByKey[key]
	if sprite == nil then
		return
	end

	self._spritesByKey[key] = nil
	self._activeSpriteCount = math.max(0, self._activeSpriteCount - 1)
	self:_releaseSprite(sprite)
	self:_releaseSurfaceIfEmpty()
end

function TileLayerRenderer.Clear(self: any)
	for key, sprite in self._spritesByKey do
		self._spritesByKey[key] = nil
		self:_releaseSprite(sprite)
	end
	self._activeSpriteCount = 0
	self:_releaseSurfaceIfEmpty()
end

function TileLayerRenderer.Destroy(self: any)
	for key, sprite in self._spritesByKey do
		self._spritesByKey[key] = nil
		sprite:Destroy()
	end
	for index, sprite in self._spritePool do
		self._spritePool[index] = nil
		sprite:Destroy()
	end
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self._activeSpriteCount = 0
	self._container = nil
	self._surfaceRoot = nil
	self._surfaceGui = nil
end

return TileLayerRenderer
