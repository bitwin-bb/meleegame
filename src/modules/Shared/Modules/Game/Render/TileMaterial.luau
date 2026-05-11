--!strict

local MaterialService = game:GetService("MaterialService")

local TileMaterial = {}

local TILE_ID_GRASS = 1
local TILE_ID_DIRT = 2
local TILE_ID_SAND = 4
local TILE_ID_SANDSTONE = 5
local TILE_ID_WOOD = 18
local OVERWORLD_MATERIAL_FOLDER_NAME = "Overworld"
local OVERWORLD_DIRT_MATERIAL_NAME = "Dirt"
local OVERWORLD_WOOD_MATERIAL_NAME = "Wood"
local OVERWORLD_LEAF_MATERIAL_NAME = "Leaf"
local OVERWORLD_SAND_MATERIAL_NAME = "Sand"
local OVERWORLD_SANDSTONE_MATERIAL_NAME = "Sandstone"

local cachedOverworldDirtMaterial: MaterialVariant? = nil
local cachedOverworldWoodMaterial: MaterialVariant? = nil
local cachedOverworldLeafMaterial: MaterialVariant? = nil
local cachedOverworldSandMaterial: MaterialVariant? = nil
local cachedOverworldSandstoneMaterial: MaterialVariant? = nil

local function resolveOverworldMaterialFolder(): Folder?
	local overworldFolder = MaterialService:FindFirstChild(OVERWORLD_MATERIAL_FOLDER_NAME)
	if overworldFolder ~= nil and overworldFolder:IsA("Folder") then
		return overworldFolder
	end

	return nil
end

local function resolveOverworldMaterial(materialName: string, cachedMaterial: MaterialVariant?): MaterialVariant?
	if cachedMaterial ~= nil and cachedMaterial.Parent ~= nil then
		return cachedMaterial
	end

	local overworldFolder = resolveOverworldMaterialFolder()
	local material = if overworldFolder ~= nil then overworldFolder:FindFirstChild(materialName) else nil
	if material == nil then
		material = MaterialService:FindFirstChild(materialName, true)
	end
	if material ~= nil and material:IsA("MaterialVariant") then
		return material
	end

	return nil
end

local function resolveOverworldDirtMaterial(): MaterialVariant?
	cachedOverworldDirtMaterial = resolveOverworldMaterial(OVERWORLD_DIRT_MATERIAL_NAME, cachedOverworldDirtMaterial)
	return cachedOverworldDirtMaterial
end

local function resolveOverworldWoodMaterial(): MaterialVariant?
	cachedOverworldWoodMaterial = resolveOverworldMaterial(OVERWORLD_WOOD_MATERIAL_NAME, cachedOverworldWoodMaterial)
	return cachedOverworldWoodMaterial
end

local function resolveOverworldLeafMaterial(): MaterialVariant?
	cachedOverworldLeafMaterial = resolveOverworldMaterial(OVERWORLD_LEAF_MATERIAL_NAME, cachedOverworldLeafMaterial)
	return cachedOverworldLeafMaterial
end

local function resolveOverworldSandMaterial(): MaterialVariant?
	cachedOverworldSandMaterial = resolveOverworldMaterial(OVERWORLD_SAND_MATERIAL_NAME, cachedOverworldSandMaterial)
	return cachedOverworldSandMaterial
end

local function resolveOverworldSandstoneMaterial(): MaterialVariant?
	cachedOverworldSandstoneMaterial =
		resolveOverworldMaterial(OVERWORLD_SANDSTONE_MATERIAL_NAME, cachedOverworldSandstoneMaterial)
	return cachedOverworldSandstoneMaterial
end

local function isOverworldDirtBackedTile(tileId: number): boolean
	return tileId == TILE_ID_DIRT or tileId == TILE_ID_GRASS
end

local function resolveMaterialBaseMaterial(material: MaterialVariant?, fallbackMaterial: Enum.Material): Enum.Material
	if material == nil then
		return fallbackMaterial
	end

	local ok, baseMaterial = pcall(function()
		return material.BaseMaterial
	end)
	if ok then
		return baseMaterial
	end

	return fallbackMaterial
end

local function applyMaterialVariant(part: BasePart, material: MaterialVariant?, fallbackMaterial: Enum.Material)
	part.Material = resolveMaterialBaseMaterial(material, fallbackMaterial)
	if material ~= nil then
		part.MaterialVariant = material.Name
	end
	TileMaterial.ApplySmoothSurfaces(part)
end

function TileMaterial.ApplyWoodMaterial(part: BasePart)
	local woodMaterial = resolveOverworldWoodMaterial()
	applyMaterialVariant(part, woodMaterial, Enum.Material.Wood)
end

function TileMaterial.ApplyLeafMaterial(part: BasePart)
	local leafMaterial = resolveOverworldLeafMaterial()
	applyMaterialVariant(part, leafMaterial, Enum.Material.LeafyGrass)
end

function TileMaterial.ApplyStudSurfaces(part: BasePart)
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
end

function TileMaterial.ApplySmoothSurfaces(part: BasePart)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.LeftSurface = Enum.SurfaceType.Smooth
	part.RightSurface = Enum.SurfaceType.Smooth
	part.FrontSurface = Enum.SurfaceType.Smooth
	part.BackSurface = Enum.SurfaceType.Smooth
end

function TileMaterial.ApplyTileMaterial(part: BasePart, tileId: number): boolean
	part.MaterialVariant = ""
	if isOverworldDirtBackedTile(tileId) then
		local dirtMaterial = resolveOverworldDirtMaterial()
		applyMaterialVariant(part, dirtMaterial, Enum.Material.Ground)

		return tileId == TILE_ID_DIRT
	end

	if tileId == TILE_ID_WOOD then
		TileMaterial.ApplyWoodMaterial(part)

		return true
	end

	if tileId == TILE_ID_SAND then
		local sandMaterial = resolveOverworldSandMaterial()
		applyMaterialVariant(part, sandMaterial, Enum.Material.Sand)

		return true
	end

	if tileId == TILE_ID_SANDSTONE then
		local sandstoneMaterial = resolveOverworldSandstoneMaterial()
		applyMaterialVariant(part, sandstoneMaterial, Enum.Material.Plastic)

		return true
	end

	return false
end

TileMaterial.applyStudSurfaces = TileMaterial.ApplyStudSurfaces
TileMaterial.applySmoothSurfaces = TileMaterial.ApplySmoothSurfaces
TileMaterial.applyTileMaterial = TileMaterial.ApplyTileMaterial
TileMaterial.applyWoodMaterial = TileMaterial.ApplyWoodMaterial
TileMaterial.applyLeafMaterial = TileMaterial.ApplyLeafMaterial

return TileMaterial
