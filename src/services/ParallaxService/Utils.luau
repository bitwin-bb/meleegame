--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldSimulationShared = require(ReplicatedStorage.Shared.Services.WorldSimulationService.Shared)

local ParallaxServiceUtils = {}

export type TransitionState = "Idle" | "Blending" | "Interrupting"
export type VerticalAlign = "Top" | "Center" | "Bottom"

export type LayerDefinition = {
	id: string,
	image: string,
	imageAspectRatio: number,
	depth: number,
	planeDepthBlocks: number,
	heightScale: number,
	segmentWidthScale: number,
	minSegments: number,
	overscanSegments: number,
	tint: Color3,
	transparency: number,
	scrollSpeed: number,
	textureStudsPerTileU: number,
	textureStudsPerTileV: number,
	verticalAlign: VerticalAlign,
	verticalOffsetStuds: number,
	verticalDepth: number,
}

export type BiomeVariantDefinition = {
	name: string,
	layers: { LayerDefinition },
}

export type BiomeDefinition = {
	name: string,
	aliases: { string },
	defaultVariantName: string,
	orderedVariantNames: { string },
	variants: { [string]: BiomeVariantDefinition },
}

export type CatalogSettings = {
	defaultBiome: string,
	transitionSeconds: number,
	biomeSampleIntervalSeconds: number,
	folderName: string,
	segmentThickness: number,
}

export type Catalog = {
	settings: CatalogSettings,
	biomes: { [string]: BiomeDefinition },
	orderedBiomeNames: { string },
	aliases: { [string]: string },
}

export type ServiceState = {
	initialized: boolean,
	currentBiome: string,
	targetBiome: string,
	transitionState: TransitionState,
}

ParallaxServiceUtils.DEPTH_LAYER_SKY = 0
ParallaxServiceUtils.DEPTH_LAYER_UNDERGROUND = 2

local BIOME_RESERVED_KEYS = {
	settings = true,
	aliases = true,
	layers = true,
	variants = true,
	defaultVariant = true,
	selectedVariant = true,
}

local BUILT_IN_BIOME_ALIASES = {
	overworld = { "Forest", "Default", "Overworld", "Surface" },
	forest = { "Forest", "Default", "Overworld", "Surface" },
	desert = { "Desert", "Sand", "Dunes" },
	snow = { "Snow", "Tundra", "Ice" },
	jungle = { "Jungle", "Rainforest" },
	corruption = { "Corruption", "Corrupt", "Evil" },
	underground = { "Underground", "Cavern", "Caves" },
}

local IMPLICIT_BIOME_TINTS = {
	overworld = Color3.fromRGB(175, 214, 188),
	forest = Color3.fromRGB(175, 214, 188),
	desert = Color3.fromRGB(229, 205, 160),
	snow = Color3.fromRGB(208, 227, 255),
	jungle = Color3.fromRGB(141, 190, 132),
	corruption = Color3.fromRGB(166, 140, 208),
	underground = Color3.fromRGB(132, 144, 170),
}

local IMPLICIT_LAYER_FALLBACK_IMAGE_ASPECT_RATIO = 3.3
local IMPLICIT_LAYER_BASE_TEXTURE_TILE_STUDS = 96
local IMPLICIT_LAYER_DEPTH_BASE = 0.32
local IMPLICIT_LAYER_DEPTH_STEP = 0.08
local IMPLICIT_LAYER_PLANE_DEPTH_BASE = 10
local IMPLICIT_LAYER_PLANE_DEPTH_STEP = 7
local IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_BASE = 0.54
local IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_STEP = 0.09
local IMPLICIT_LAYER_TRANSPARENCY_BASE = 0.04
local IMPLICIT_LAYER_TRANSPARENCY_STEP = 0.025
local IMPLICIT_LAYER_VERTICAL_OFFSET_BASE = -18
local IMPLICIT_LAYER_VERTICAL_OFFSET_STEP = 10
local IMPLICIT_LAYER_VERTICAL_DEPTH_BASE = 0.008
local IMPLICIT_LAYER_VERTICAL_DEPTH_STEP = 0.004
local IMPLICIT_PARALLAX_SOURCE_DIMENSIONS = {
	overworld = {
		[1] = { width = 1024, height = 533 },
		[2] = { width = 1024, height = 600 },
		[3] = { width = 1024, height = 660 },
		[4] = { width = 1024, height = 699 },
	},
	corruption = {
		[1] = { width = 1024, height = 533 },
		[2] = { width = 1024, height = 533 },
		[3] = { width = 1024, height = 533 },
		[4] = { width = 1024, height = 371 },
	},
	jungle = {
		[1] = { width = 1024, height = 768 },
		[2] = { width = 1024, height = 533 },
		[3] = { width = 1024, height = 540 },
		[4] = { width = 1024, height = 533 },
	},
	desert = {
		[1] = { width = 1024, height = 400 },
		[2] = { width = 1024, height = 500 },
		[3] = { width = 1024, height = 434 },
		[4] = { width = 1024, height = 434 },
	},
	snow = {
		[1] = { width = 1024, height = 529 },
		[2] = { width = 1024, height = 529 },
		[3] = { width = 1024, height = 600 },
		[4] = { width = 1024, height = 600 },
	},
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeToken(valueRaw: any): string
	local value = string.lower(trim(valueRaw))
	value = string.gsub(value, "%s+", "")
	value = string.gsub(value, "_", "")
	value = string.gsub(value, "%-", "")
	return value
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw and valueRaw ~= math.huge and valueRaw ~= -math.huge then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	return math.floor(sanitizeNumber(valueRaw, fallback, minimum, maximum))
end

local function sanitizeColor3(valueRaw: any, fallback: Color3): Color3
	if typeof(valueRaw) == "Color3" then
		return valueRaw
	end
	return fallback
end

local function resolveImageAspectRatio(source: { [string]: any }, fallback: number): number
	local directAspectRatio = sanitizeNumber(source.imageAspectRatio, fallback, 0.05, 64)
	if typeof(source.imageAspectRatio) == "number" then
		return directAspectRatio
	end

	local imageWidth = sanitizeNumber(source.imageWidth, -1, 1, 65536)
	local imageHeight = sanitizeNumber(source.imageHeight, -1, 1, 65536)
	if imageWidth > 0 and imageHeight > 0 then
		return sanitizeNumber(imageWidth / imageHeight, fallback, 0.05, 64)
	end

	local tileWidth = sanitizeNumber(source.textureStudsPerTileU, -1, 1, 4096)
	local tileHeight = sanitizeNumber(source.textureStudsPerTileV, -1, 1, 4096)
	if tileWidth > 0 and tileHeight > 0 then
		return sanitizeNumber(tileWidth / tileHeight, fallback, 0.05, 64)
	end

	return directAspectRatio
end

local function lerpColor3(from: Color3, to: Color3, alpha: number): Color3
	return Color3.new(
		from.R + (to.R - from.R) * alpha,
		from.G + (to.G - from.G) * alpha,
		from.B + (to.B - from.B) * alpha
	)
end

local function resolveImplicitBiomeTint(biomeName: string, farAlpha: number): Color3
	local baseTint = IMPLICIT_BIOME_TINTS[normalizeToken(biomeName)] or Color3.fromRGB(190, 205, 220)
	return lerpColor3(Color3.new(1, 1, 1), baseTint, 0.14 + farAlpha * 0.16)
end

local function resolveImplicitSourceImageAspectRatio(biomeName: string, layerIndex: number): number?
	local normalizedBiomeName = normalizeToken(biomeName)
	if normalizedBiomeName == "forest" then
		normalizedBiomeName = "overworld"
	end

	local biomeDimensions = IMPLICIT_PARALLAX_SOURCE_DIMENSIONS[normalizedBiomeName]
	if biomeDimensions == nil then
		return nil
	end

	local imageDimensions = biomeDimensions[layerIndex]
	if imageDimensions == nil or imageDimensions.width <= 0 or imageDimensions.height <= 0 then
		return nil
	end

	return imageDimensions.width / imageDimensions.height
end

local function resolveImplicitLayerDefaults(
	biomeName: string,
	layerIndex: number,
	totalLayers: number
): { [string]: any }
	local total = math.max(totalLayers, 1)
	local stackIndex = math.max(layerIndex - 1, 0)
	local farAlpha = if total <= 1 then 0 else (layerIndex - 1) / (total - 1)
	local imageAspectRatio = resolveImplicitSourceImageAspectRatio(biomeName, layerIndex)
		or IMPLICIT_LAYER_FALLBACK_IMAGE_ASPECT_RATIO

	return {
		imageAspectRatio = imageAspectRatio,
		depth = math.clamp(IMPLICIT_LAYER_DEPTH_BASE - stackIndex * IMPLICIT_LAYER_DEPTH_STEP, 0.05, 0.98),
		planeDepthBlocks = IMPLICIT_LAYER_PLANE_DEPTH_BASE + stackIndex * IMPLICIT_LAYER_PLANE_DEPTH_STEP,
		heightScale = 1,
		segmentWidthScale = IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_BASE
			+ stackIndex * IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_STEP,
		minSegments = 2,
		overscanSegments = 4,
		tint = resolveImplicitBiomeTint(biomeName, farAlpha),
		transparency = IMPLICIT_LAYER_TRANSPARENCY_BASE + stackIndex * IMPLICIT_LAYER_TRANSPARENCY_STEP,
		scrollSpeed = 0,
		textureStudsPerTileU = IMPLICIT_LAYER_BASE_TEXTURE_TILE_STUDS,
		textureStudsPerTileV = IMPLICIT_LAYER_BASE_TEXTURE_TILE_STUDS,
		verticalAlign = "Center",
		verticalOffsetStuds = IMPLICIT_LAYER_VERTICAL_OFFSET_BASE + stackIndex * IMPLICIT_LAYER_VERTICAL_OFFSET_STEP,
		verticalDepth = IMPLICIT_LAYER_VERTICAL_DEPTH_BASE + stackIndex * IMPLICIT_LAYER_VERTICAL_DEPTH_STEP,
	}
end

local function sanitizeVerticalAlign(valueRaw: any, fallback: VerticalAlign): VerticalAlign
	local token = normalizeToken(valueRaw)
	if token == "top" then
		return "Top"
	end
	if token == "center" or token == "middle" then
		return "Center"
	end
	if token == "bottom" then
		return "Bottom"
	end
	return fallback
end

local function collectSortedNumericIndices(sourceRaw: any): { number }
	local source = if typeof(sourceRaw) == "table" then (sourceRaw :: { [any]: any }) else {}
	local indices: { number } = {}
	for key in source do
		if typeof(key) == "number" and key % 1 == 0 then
			table.insert(indices, key)
		end
	end
	table.sort(indices)
	return indices
end

local function collectSortedStringKeys(sourceRaw: any): { string }
	local source = if typeof(sourceRaw) == "table" then (sourceRaw :: { [any]: any }) else {}
	local keys: { string } = {}
	for key in source do
		if typeof(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

local function createImplicitLayerSource(
	biomeName: string,
	variantName: string,
	layerIndex: number,
	totalLayers: number,
	image: string
): { [string]: any }
	local defaults = resolveImplicitLayerDefaults(biomeName, layerIndex, totalLayers)
	return {
		id = `{biomeName}_{variantName}_Layer_{layerIndex}`,
		image = image,
		imageAspectRatio = defaults.imageAspectRatio,
		depth = defaults.depth,
		planeDepthBlocks = defaults.planeDepthBlocks,
		heightScale = defaults.heightScale,
		segmentWidthScale = defaults.segmentWidthScale,
		minSegments = defaults.minSegments,
		overscanSegments = defaults.overscanSegments,
		tint = defaults.tint,
		transparency = defaults.transparency,
		scrollSpeed = defaults.scrollSpeed,
		textureStudsPerTileU = defaults.textureStudsPerTileU,
		textureStudsPerTileV = defaults.textureStudsPerTileV,
		verticalAlign = defaults.verticalAlign,
		verticalOffsetStuds = defaults.verticalOffsetStuds,
		verticalDepth = defaults.verticalDepth,
	}
end

local function sanitizeLayerDefinition(
	layerRaw: any,
	fallbackId: string,
	layerIndex: number,
	totalLayers: number,
	biomeName: string,
	variantName: string
): LayerDefinition?
	local source: { [string]: any }
	if typeof(layerRaw) == "string" then
		local image = trim(layerRaw)
		if image == "" then
			return nil
		end
		source = createImplicitLayerSource(biomeName, variantName, layerIndex, totalLayers, image)
	elseif typeof(layerRaw) == "table" then
		source = layerRaw :: { [string]: any }
		if trim(source.image) == "" and trim(source.asset) ~= "" then
			source = table.clone(source)
			source.image = source.asset
		end
	else
		return nil
	end

	local image = trim(source.image)
	if image == "" then
		return nil
	end

	local defaults = resolveImplicitLayerDefaults(biomeName, layerIndex, totalLayers)
	return {
		id = trim(source.id) ~= "" and trim(source.id) or fallbackId,
		image = image,
		imageAspectRatio = resolveImageAspectRatio(source, defaults.imageAspectRatio),
		depth = sanitizeNumber(source.depth, defaults.depth, 0, 0.98),
		planeDepthBlocks = sanitizeNumber(source.planeDepthBlocks, defaults.planeDepthBlocks, 1, 256),
		heightScale = sanitizeNumber(source.heightScale, defaults.heightScale, 0.05, 4),
		segmentWidthScale = sanitizeNumber(source.segmentWidthScale, defaults.segmentWidthScale, 0.25, 8),
		minSegments = sanitizeInteger(source.minSegments, defaults.minSegments, 1, 32),
		overscanSegments = sanitizeInteger(source.overscanSegments, defaults.overscanSegments, 0, 16),
		tint = sanitizeColor3(source.tint, defaults.tint),
		transparency = sanitizeNumber(source.transparency, defaults.transparency, 0, 1),
		scrollSpeed = sanitizeNumber(source.scrollSpeed, defaults.scrollSpeed, -256, 256),
		textureStudsPerTileU = sanitizeNumber(source.textureStudsPerTileU, defaults.textureStudsPerTileU, 1, 4096),
		textureStudsPerTileV = sanitizeNumber(source.textureStudsPerTileV, defaults.textureStudsPerTileV, 1, 4096),
		verticalAlign = sanitizeVerticalAlign(source.verticalAlign, defaults.verticalAlign),
		verticalOffsetStuds = sanitizeNumber(source.verticalOffsetStuds, defaults.verticalOffsetStuds, -4096, 4096),
		verticalDepth = sanitizeNumber(source.verticalDepth, defaults.verticalDepth, 0, 1),
	}
end

local function sanitizeVariantDefinition(
	biomeName: string,
	variantNameRaw: any,
	variantRaw: any
): BiomeVariantDefinition?
	local variantName = trim(variantNameRaw)
	if variantName == "" or typeof(variantRaw) ~= "table" then
		return nil
	end

	local source = variantRaw :: { [string]: any }
	local layersRaw = if typeof(source.layers) == "table" then source.layers else variantRaw
	local indices = collectSortedNumericIndices(layersRaw)
	local totalLayers = #indices
	if totalLayers <= 0 then
		return nil
	end

	local layers: { LayerDefinition } = {}
	for ordinal, numericIndex in indices do
		local layer = sanitizeLayerDefinition(
			(layersRaw :: { [any]: any })[numericIndex],
			`{biomeName}_{variantName}_Layer_{numericIndex}`,
			ordinal,
			totalLayers,
			biomeName,
			variantName
		)
		if layer ~= nil then
			table.insert(layers, layer)
		end
	end

	if #layers <= 0 then
		return nil
	end

	return {
		name = variantName,
		layers = layers,
	}
end

local function appendBuiltInAliases(aliases: { string }, biomeName: string)
	local builtIns = BUILT_IN_BIOME_ALIASES[normalizeToken(biomeName)]
	if builtIns == nil then
		return
	end

	local seen: { [string]: boolean } = {}
	for _, alias in aliases do
		seen[normalizeToken(alias)] = true
	end
	for _, alias in builtIns do
		local token = normalizeToken(alias)
		if not seen[token] then
			seen[token] = true
			table.insert(aliases, alias)
		end
	end
end

local function sanitizeBiomeDefinition(nameRaw: any, biomeRaw: any): BiomeDefinition?
	local name = trim(nameRaw)
	if name == "" or typeof(biomeRaw) ~= "table" then
		return nil
	end

	local source = biomeRaw :: { [string]: any }
	local aliasesRaw = if typeof(source.aliases) == "table" then source.aliases :: { any } else {}
	local aliases: { string } = {}
	for _, alias in aliasesRaw do
		local text = trim(alias)
		if text ~= "" then
			table.insert(aliases, text)
		end
	end
	appendBuiltInAliases(aliases, name)

	local variants: { [string]: BiomeVariantDefinition } = {}
	local orderedVariantNames: { string } = {}

	if typeof(source.layers) == "table" then
		local implicitVariantName = trim(source.defaultVariant)
		if implicitVariantName == "" then
			implicitVariantName = "default"
		end
		local variant = sanitizeVariantDefinition(name, implicitVariantName, {
			layers = source.layers,
		})
		if variant ~= nil then
			variants[variant.name] = variant
			table.insert(orderedVariantNames, variant.name)
		end
	elseif typeof(source.variants) == "table" then
		for _, variantName in collectSortedStringKeys(source.variants) do
			local variant = sanitizeVariantDefinition(name, variantName, (source.variants :: { [string]: any })[variantName])
			if variant ~= nil then
				variants[variant.name] = variant
				table.insert(orderedVariantNames, variant.name)
			end
		end
	else
		for _, variantName in collectSortedStringKeys(source) do
			if BIOME_RESERVED_KEYS[variantName] then
				continue
			end
			local variant = sanitizeVariantDefinition(name, variantName, source[variantName])
			if variant ~= nil then
				variants[variant.name] = variant
				table.insert(orderedVariantNames, variant.name)
			end
		end
	end

	if #orderedVariantNames <= 0 then
		return nil
	end

	local defaultVariantName = trim(source.defaultVariant)
	if defaultVariantName == "" or variants[defaultVariantName] == nil then
		defaultVariantName = orderedVariantNames[1]
	end

	return {
		name = name,
		aliases = aliases,
		defaultVariantName = defaultVariantName,
		orderedVariantNames = orderedVariantNames,
		variants = variants,
	}
end

function ParallaxServiceUtils.normalizeCatalog(rawCatalog: any): Catalog
	local source = if typeof(rawCatalog) == "table" then (rawCatalog :: { [string]: any }) else {}
	local settingsRaw = if typeof(source.settings) == "table" then (source.settings :: { [string]: any }) else {}
	local rawBiomes = if typeof(source.biomes) == "table" then (source.biomes :: { [string]: any }) else source

	local biomes: { [string]: BiomeDefinition } = {}
	local orderedBiomeNames: { string } = {}
	local aliases: { [string]: string } = {}

	for _, biomeName in collectSortedStringKeys(rawBiomes) do
		if BIOME_RESERVED_KEYS[biomeName] or biomeName == "settings" then
			continue
		end

		local biome = sanitizeBiomeDefinition(biomeName, rawBiomes[biomeName])
		if biome == nil then
			continue
		end

		biomes[biome.name] = biome
		table.insert(orderedBiomeNames, biome.name)
		aliases[normalizeToken(biome.name)] = biome.name
		for _, alias in biome.aliases do
			aliases[normalizeToken(alias)] = biome.name
		end
	end

	if next(biomes) == nil then
		local fallbackBiome = sanitizeBiomeDefinition("overworld", {
			defaultVariant = "default",
			default = {
				[1] = "rbxassetid://79294783523700",
			},
		})
		if fallbackBiome ~= nil then
			biomes[fallbackBiome.name] = fallbackBiome
			orderedBiomeNames = { fallbackBiome.name }
			aliases[normalizeToken(fallbackBiome.name)] = fallbackBiome.name
			for _, alias in fallbackBiome.aliases do
				aliases[normalizeToken(alias)] = fallbackBiome.name
			end
		end
	end

	local defaultBiome = trim(settingsRaw.defaultBiome)
	if defaultBiome == "" then
		if biomes.overworld ~= nil then
			defaultBiome = "overworld"
		else
			defaultBiome = orderedBiomeNames[1]
		end
	end

	local settings: CatalogSettings = {
		defaultBiome = if biomes[defaultBiome] ~= nil then defaultBiome else orderedBiomeNames[1],
		transitionSeconds = sanitizeNumber(settingsRaw.transitionSeconds, 1.35, 0, 10),
		biomeSampleIntervalSeconds = sanitizeNumber(settingsRaw.biomeSampleIntervalSeconds, 0.2, 0.02, 5),
		folderName = trim(settingsRaw.folderName) ~= "" and trim(settingsRaw.folderName) or "ParallaxDepth",
		segmentThickness = sanitizeNumber(settingsRaw.segmentThickness, 0.2, 0.01, 16),
	}

	return {
		settings = settings,
		biomes = biomes,
		orderedBiomeNames = orderedBiomeNames,
		aliases = aliases,
	}
end

function ParallaxServiceUtils.resolveBiomeName(catalog: Catalog, biomeNameRaw: any): string
	local requestedName = trim(biomeNameRaw)
	if requestedName ~= "" and catalog.biomes[requestedName] ~= nil then
		return requestedName
	end

	local aliasTarget = catalog.aliases[normalizeToken(biomeNameRaw)]
	if aliasTarget ~= nil and catalog.biomes[aliasTarget] ~= nil then
		return aliasTarget
	end

	return catalog.settings.defaultBiome
end

function ParallaxServiceUtils.resolveBiomeDefinition(catalog: Catalog, biomeNameRaw: any): BiomeDefinition
	return catalog.biomes[ParallaxServiceUtils.resolveBiomeName(catalog, biomeNameRaw)]
end

function ParallaxServiceUtils.resolveVariantName(
	biomeDefinition: BiomeDefinition,
	variantNameRaw: any
): string
	local requestedName = trim(variantNameRaw)
	if requestedName ~= "" and biomeDefinition.variants[requestedName] ~= nil then
		return requestedName
	end
	return biomeDefinition.defaultVariantName
end

function ParallaxServiceUtils.resolveVariantDefinition(
	catalog: Catalog,
	biomeNameRaw: any,
	variantNameRaw: any
): BiomeVariantDefinition
	local biomeDefinition = ParallaxServiceUtils.resolveBiomeDefinition(catalog, biomeNameRaw)
	local variantName = ParallaxServiceUtils.resolveVariantName(biomeDefinition, variantNameRaw)
	return biomeDefinition.variants[variantName]
end

function ParallaxServiceUtils.collectAssetIds(catalog: Catalog, biomeNamesRaw: { any }?): { string }
	local assetIds: { string } = {}
	local seen: { [string]: boolean } = {}
	local biomeNames = if biomeNamesRaw ~= nil then biomeNamesRaw else catalog.orderedBiomeNames

	for _, biomeNameRaw in biomeNames do
		local biome = ParallaxServiceUtils.resolveBiomeDefinition(catalog, biomeNameRaw)
		for _, variantName in biome.orderedVariantNames do
			local variant = biome.variants[variantName]
			for _, layer in variant.layers do
				if layer.image ~= "" and not seen[layer.image] then
					seen[layer.image] = true
					table.insert(assetIds, layer.image)
				end
			end
		end
	end

	return assetIds
end

function ParallaxServiceUtils.createDefaultState(catalog: Catalog): ServiceState
	return {
		initialized = false,
		currentBiome = catalog.settings.defaultBiome,
		targetBiome = catalog.settings.defaultBiome,
		transitionState = "Idle",
	}
end

function ParallaxServiceUtils.resolveBiomeNameFromWorldSample(
	catalog: Catalog,
	biomeIdRaw: any,
	biomeTypeRaw: any,
	depthLayerRaw: any
): string
	local depthLayer = sanitizeInteger(depthLayerRaw, ParallaxServiceUtils.DEPTH_LAYER_SKY, -256, 256)
	if depthLayer >= ParallaxServiceUtils.DEPTH_LAYER_UNDERGROUND then
		return ParallaxServiceUtils.resolveBiomeName(catalog, "Underground")
	end

	local biomeType = sanitizeInteger(biomeTypeRaw, WorldSimulationShared.BIOME_ID.FOREST, 0, 1024)
	local biomeId = sanitizeInteger(biomeIdRaw, WorldSimulationShared.BIOME_ID.FOREST, 0, 1024)

	if biomeId == WorldSimulationShared.BIOME_ID.CORRUPTION or biomeType == 2 then
		return ParallaxServiceUtils.resolveBiomeName(catalog, "Corruption")
	end
	if biomeId == WorldSimulationShared.BIOME_ID.DESERT then
		return ParallaxServiceUtils.resolveBiomeName(catalog, "Desert")
	end
	if biomeId == WorldSimulationShared.BIOME_ID.SNOW then
		return ParallaxServiceUtils.resolveBiomeName(catalog, "Snow")
	end
	if biomeId == WorldSimulationShared.BIOME_ID.JUNGLE then
		return ParallaxServiceUtils.resolveBiomeName(catalog, "Jungle")
	end
	return ParallaxServiceUtils.resolveBiomeName(catalog, "Overworld")
end

return ParallaxServiceUtils
