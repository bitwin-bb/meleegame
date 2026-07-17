local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local Maid = require("Maid")
local WorldGenerationConstants = require("WorldGenerationConstants")

local TileSprite = {}
TileSprite.__index = TileSprite

export type TileSurfaceLayout = {
	cframe: CFrame?,
	size: Vector3?,
	pixelsPerStud: number?,
}

local Children = Fusion.Children

local PLANE_DEPTH = WorldGenerationConstants.DEFAULT_TILE_DEPTH
local DEFAULT_ROOT_SIZE = Vector3.new(PLANE_DEPTH, 2, 2)
local DEFAULT_PIXELS_PER_STUD = 8
local SURFACE_FACE = Enum.NormalId.Right

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function coerceRootSize(sizeRaw: any): Vector3
	if typeof(sizeRaw) == "Vector3" then
		return Vector3.new(PLANE_DEPTH, math.max(0.05, sizeRaw.Y), math.max(0.05, sizeRaw.Z))
	end
	return DEFAULT_ROOT_SIZE
end

local function coercePixelsPerStud(pixelsPerStudRaw: any): number
	if isFiniteNumber(pixelsPerStudRaw) then
		return math.max(0.001, pixelsPerStudRaw :: number)
	end
	return DEFAULT_PIXELS_PER_STUD
end

local function coerceLayout(layoutRaw: any): TileSurfaceLayout
	local layout = if typeof(layoutRaw) == "table" then layoutRaw :: TileSurfaceLayout else {} :: any
	return {
		cframe = if typeof(layout.cframe) == "CFrame" then layout.cframe else nil,
		size = coerceRootSize(layout.size),
		pixelsPerStud = coercePixelsPerStud(layout.pixelsPerStud),
	}
end

local function setFusionValue(valueObject: any, nextValue: any)
	if valueObject ~= nil then
		valueObject:set(nextValue)
	end
end

local function getFallbackCFrame(localX: number, localY: number, size: Vector3): CFrame
	return CFrame.new(0, (localY + 0.5) * size.Y, (localX + 0.5) * size.Z)
end

function TileSprite.new(parent: Instance, localX: number, localY: number, layoutRaw: any): any
	local scope = Fusion.scoped(Fusion)
	local maid = Maid.new()

	local self = setmetatable({
		_maid = maid,
		_scope = scope,
		_imageValue = scope:Value(""),
		_imageRectOffsetValue = scope:Value(Vector2.zero),
		_imageRectSizeValue = scope:Value(Vector2.zero),
		_visibleValue = scope:Value(false),
		_rootCFrameValue = scope:Value(CFrame.new()),
		_rootSizeValue = scope:Value(DEFAULT_ROOT_SIZE),
		_pixelsPerStudValue = scope:Value(DEFAULT_PIXELS_PER_STUD),
	}, TileSprite)

	maid:GiveTask(function()
		Fusion.doCleanup(scope)
	end)

	scope:New "Part" {
		Name = "AutotileRoot",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		CFrame = self._rootCFrameValue,
		Locked = true,
		Massless = true,
		Material = Enum.Material.SmoothPlastic,
		MaterialVariant = "",
		Size = self._rootSizeValue,
		Transparency = 1,
		Parent = parent,

		[Children] = {
			scope:New "SurfaceGui" {
				Name = "AutotileSurface",
				AlwaysOnTop = false,
				Brightness = 1,
				Enabled = self._visibleValue,
				Face = SURFACE_FACE,
				LightInfluence = 0,
				MaxDistance = 100000,
				PixelsPerStud = self._pixelsPerStudValue,
				SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

				[Children] = {
					scope:New "ImageLabel" {
						Name = "AutotileImage",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Image = self._imageValue,
						ImageRectOffset = self._imageRectOffsetValue,
						ImageRectSize = self._imageRectSizeValue,
						ResampleMode = Enum.ResamplerMode.Pixelated,
						ScaleType = Enum.ScaleType.Stretch,
						Size = UDim2.fromScale(1, 1),
					},
				},
			},
		},
	}

	self:SetLayout(localX, localY, layoutRaw)

	return self
end

function TileSprite.SetLayout(self: any, localX: number, localY: number, layoutRaw: any)
	local layout = coerceLayout(layoutRaw)
	local size = layout.size or DEFAULT_ROOT_SIZE

	setFusionValue(self._rootSizeValue, size)
	setFusionValue(self._rootCFrameValue, layout.cframe or getFallbackCFrame(localX, localY, size))
	setFusionValue(self._pixelsPerStudValue, layout.pixelsPerStud or DEFAULT_PIXELS_PER_STUD)
end

function TileSprite.Update(self: any, atlasResult: any)
	if typeof(atlasResult) ~= "table" then
		setFusionValue(self._visibleValue, false)
		return
	end

	setFusionValue(self._visibleValue, true)
	setFusionValue(self._imageValue, atlasResult.Image or "")
	setFusionValue(self._imageRectOffsetValue, atlasResult.ImageRectOffset or Vector2.zero)
	setFusionValue(self._imageRectSizeValue, atlasResult.ImageRectSize or Vector2.zero)
end

function TileSprite.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
		self._maid = nil
	end
	self._scope = nil
end

return TileSprite
