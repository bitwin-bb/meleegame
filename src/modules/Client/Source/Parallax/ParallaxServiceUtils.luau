local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift: any = require(ReplicatedStorage.Packages.Sift)

local ParallaxConstants = require("ParallaxConstants")
local ParallaxTypes = require("ParallaxTypes")
local WorldSimulationShared = require("Shared")

local ParallaxServiceUtils = {}

export type TransitionState = ParallaxTypes.TransitionState
export type VerticalAlign = ParallaxTypes.VerticalAlign
export type LayerDefinition = ParallaxTypes.LayerDefinition
export type BiomeVariantDefinition = ParallaxTypes.BiomeVariantDefinition
export type BiomeDefinition = ParallaxTypes.BiomeDefinition
export type CatalogSettings = ParallaxTypes.CatalogSettings
export type Catalog = ParallaxTypes.Catalog
export type ServiceState = ParallaxTypes.ServiceState
export type PlaneSizing = ParallaxTypes.PlaneSizing

ParallaxServiceUtils.DEPTH_LAYER_SKY = ParallaxConstants.DEPTH_LAYER_SKY
ParallaxServiceUtils.DEPTH_LAYER_UNDERGROUND = ParallaxConstants.DEPTH_LAYER_UNDERGROUND

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

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
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

local function CoerceInteger(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	return math.floor(CoerceNumber(valueRaw, fallback, minimum, maximum))
end

local function CoerceColor3(valueRaw: any, fallback: Color3): Color3
	if typeof(valueRaw) == "Color3" then
		return valueRaw
	end
	return fallback
end

local function readSourceValue(source: { [string]: any }, camelName: string, pascalName: string): any
	local camelValue = source[camelName]
	if camelValue ~= nil then
		return camelValue
	end
	return source[pascalName]
end

local function GetImageAspectRatio(source: { [string]: any }, fallback: number): number
	local directAspectRatio = CoerceNumber(source.imageAspectRatio, fallback, 0.05, 64)
	if typeof(source.imageAspectRatio) == "number" then
		return directAspectRatio
	end

	local imageWidth = CoerceNumber(source.imageWidth, -1, 1, 65536)
	local imageHeight = CoerceNumber(source.imageHeight, -1, 1, 65536)
	if imageWidth > 0 and imageHeight > 0 then
		return CoerceNumber(imageWidth / imageHeight, fallback, 0.05, 64)
	end

	local tileWidth = CoerceNumber(source.textureStudsPerTileU, -1, 1, 4096)
	local tileHeight = CoerceNumber(source.textureStudsPerTileV, -1, 1, 4096)
	if tileWidth > 0 and tileHeight > 0 then
		return CoerceNumber(tileWidth / tileHeight, fallback, 0.05, 64)
	end

	return directAspectRatio
end

local function GetImplicitSourceImageAspectRatio(biomeName: string, layerIndex: number): number?
	local normalizedBiomeName = normalizeToken(biomeName)
	if normalizedBiomeName == "forest" then
		normalizedBiomeName = "overworld"
	end

	local biomeDimensions = ParallaxConstants.IMPLICIT_PARALLAX_SOURCE_DIMENSIONS[normalizedBiomeName]
	if biomeDimensions == nil then
		return nil
	end

	local imageDimensions = biomeDimensions[layerIndex]
	if imageDimensions == nil or imageDimensions.width <= 0 or imageDimensions.height <= 0 then
		return nil
	end

	return imageDimensions.width / imageDimensions.height
end

local function GetImplicitLayerDefaults(biomeName: string, layerIndex: number, _totalLayers: number): { [string]: any }
	local stackIndex = math.max(layerIndex - 1, 0)
	local imageAspectRatio = GetImplicitSourceImageAspectRatio(biomeName, layerIndex)
		or ParallaxConstants.IMPLICIT_LAYER_FALLBACK_IMAGE_ASPECT_RATIO

	return {
		imageAspectRatio = imageAspectRatio,
		depth = math.clamp(
			ParallaxConstants.IMPLICIT_LAYER_DEPTH_BASE - stackIndex * ParallaxConstants.IMPLICIT_LAYER_DEPTH_STEP,
			0.05,
			0.98
		),
		planeDepthBlocks = ParallaxConstants.IMPLICIT_LAYER_PLANE_DEPTH_BASE
			+ stackIndex * ParallaxConstants.IMPLICIT_LAYER_PLANE_DEPTH_STEP,
		heightScale = 1,
		segmentWidthScale = ParallaxConstants.IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_BASE
			+ stackIndex * ParallaxConstants.IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_STEP,
		minSegments = 2,
		overscanSegments = 4,
		tint = Color3.new(1, 1, 1),
		transparency = 0,
		scrollSpeed = 0,
		textureStudsPerTileU = ParallaxConstants.IMPLICIT_LAYER_BASE_TEXTURE_TILE_STUDS,
		textureStudsPerTileV = ParallaxConstants.IMPLICIT_LAYER_BASE_TEXTURE_TILE_STUDS,
		verticalAlign = "Center",
		verticalOffsetStuds = ParallaxConstants.IMPLICIT_LAYER_VERTICAL_OFFSET_BASE
			+ stackIndex * ParallaxConstants.IMPLICIT_LAYER_VERTICAL_OFFSET_STEP,
		verticalDepth = ParallaxConstants.IMPLICIT_LAYER_VERTICAL_DEPTH_BASE
			+ stackIndex * ParallaxConstants.IMPLICIT_LAYER_VERTICAL_DEPTH_STEP,
		verticalParallax = ParallaxConstants.IMPLICIT_LAYER_VERTICAL_DEPTH_BASE
			+ stackIndex * ParallaxConstants.IMPLICIT_LAYER_VERTICAL_DEPTH_STEP,
		baseYOffset = ParallaxConstants.IMPLICIT_LAYER_BASE_Y_OFFSET,
		bottomOverscan = ParallaxConstants.IMPLICIT_LAYER_BOTTOM_OVERSCAN,
		minY = ParallaxConstants.IMPLICIT_LAYER_MIN_Y,
		maxY = ParallaxConstants.IMPLICIT_LAYER_MAX_Y,
	}
end

local function CoerceVerticalAlign(valueRaw: any, fallback: VerticalAlign): VerticalAlign
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
	local source = if typeof(sourceRaw) == "table" then sourceRaw :: { [any]: any } else {} :: any
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
	local source = if typeof(sourceRaw) == "table" then sourceRaw :: { [any]: any } else {} :: any
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
	local defaults = GetImplicitLayerDefaults(biomeName, layerIndex, totalLayers)
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
		verticalParallax = defaults.verticalParallax,
		baseYOffset = defaults.baseYOffset,
		bottomOverscan = defaults.bottomOverscan,
		minY = defaults.minY,
		maxY = defaults.maxY,
	}
end

local function CoerceLayerDefinition(
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
			source = Sift.Dictionary.copy(source)
			source.image = source.asset
		end
	else
		return nil
	end

	local image = trim(source.image)
	if image == "" then
		return nil
	end

	local defaults = GetImplicitLayerDefaults(biomeName, layerIndex, totalLayers)
	local minY = CoerceNumber(readSourceValue(source, "minY", "MinY"), defaults.minY, -4, 4)
	local maxY = CoerceNumber(readSourceValue(source, "maxY", "MaxY"), defaults.maxY, -4, 4)
	if minY > maxY then
		minY, maxY = maxY, minY
	end

	return {
		id = trim(source.id) ~= "" and trim(source.id) or fallbackId,
		image = image,
		imageAspectRatio = GetImageAspectRatio(source, defaults.imageAspectRatio),
		depth = CoerceNumber(source.depth, defaults.depth, 0, 0.98),
		planeDepthBlocks = CoerceNumber(source.planeDepthBlocks, defaults.planeDepthBlocks, 1, 256),
		heightScale = CoerceNumber(source.heightScale, defaults.heightScale, 0.05, 4),
		segmentWidthScale = CoerceNumber(source.segmentWidthScale, defaults.segmentWidthScale, 0.25, 8),
		minSegments = CoerceInteger(source.minSegments, defaults.minSegments, 1, 32),
		overscanSegments = CoerceInteger(source.overscanSegments, defaults.overscanSegments, 0, 16),
		tint = CoerceColor3(source.tint, defaults.tint),
		transparency = 0,
		scrollSpeed = CoerceNumber(source.scrollSpeed, defaults.scrollSpeed, -256, 256),
		textureStudsPerTileU = CoerceNumber(source.textureStudsPerTileU, defaults.textureStudsPerTileU, 1, 4096),
		textureStudsPerTileV = CoerceNumber(source.textureStudsPerTileV, defaults.textureStudsPerTileV, 1, 4096),
		verticalAlign = CoerceVerticalAlign(source.verticalAlign, defaults.verticalAlign),
		verticalOffsetStuds = CoerceNumber(source.verticalOffsetStuds, defaults.verticalOffsetStuds, -4096, 4096),
		verticalDepth = CoerceNumber(source.verticalDepth, defaults.verticalDepth, 0, 1),
		verticalParallax = CoerceNumber(
			readSourceValue(source, "verticalParallax", "VerticalParallax"),
			defaults.verticalParallax,
			0,
			1
		),
		baseYOffset = CoerceNumber(readSourceValue(source, "baseYOffset", "BaseYOffset"), defaults.baseYOffset, -4, 4),
		bottomOverscan = CoerceNumber(
			readSourceValue(source, "bottomOverscan", "BottomOverscan"),
			defaults.bottomOverscan,
			0,
			2
		),
		minY = minY,
		maxY = maxY,
	}
end

local function CoerceVariantDefinition(biomeName: string, variantNameRaw: any, variantRaw: any): BiomeVariantDefinition?
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
		local layer = CoerceLayerDefinition(
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
	local builtIns = ParallaxConstants.BUILT_IN_BIOME_ALIASES[normalizeToken(biomeName)]
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

local function CoerceBiomeDefinition(nameRaw: any, biomeRaw: any): BiomeDefinition?
	local name = trim(nameRaw)
	if name == "" or typeof(biomeRaw) ~= "table" then
		return nil
	end

	local source = biomeRaw :: { [string]: any }
	local aliasesRaw = if typeof(source.aliases) == "table" then source.aliases :: { any } else {} :: any
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
		local variant = CoerceVariantDefinition(name, implicitVariantName, {
			layers = source.layers,
		})
		if variant ~= nil then
			variants[variant.name] = variant
			table.insert(orderedVariantNames, variant.name)
		end
	elseif typeof(source.variants) == "table" then
		for _, variantName in collectSortedStringKeys(source.variants) do
			local variant =
				CoerceVariantDefinition(name, variantName, (source.variants :: { [string]: any })[variantName])
			if variant ~= nil then
				variants[variant.name] = variant
				table.insert(orderedVariantNames, variant.name)
			end
		end
	else
		for _, variantName in collectSortedStringKeys(source) do
			if ParallaxConstants.BIOME_RESERVED_KEYS[variantName] then
				continue
			end
			local variant = CoerceVariantDefinition(name, variantName, source[variantName])
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

function ParallaxServiceUtils.NormalizeCatalog(rawCatalog: any): Catalog
	local source = if typeof(rawCatalog) == "table" then rawCatalog :: { [string]: any } else {} :: any
	local settingsRaw = if typeof(source.settings) == "table" then source.settings :: { [string]: any } else {} :: any
	local rawBiomes = if typeof(source.biomes) == "table" then source.biomes :: { [string]: any } else source

	local biomes: { [string]: BiomeDefinition } = {}
	local orderedBiomeNames: { string } = {}
	local aliases: { [string]: string } = {}

	for _, biomeName in collectSortedStringKeys(rawBiomes) do
		if ParallaxConstants.BIOME_RESERVED_KEYS[biomeName] or biomeName == "settings" then
			continue
		end

		local biome = CoerceBiomeDefinition(biomeName, rawBiomes[biomeName])
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
		local fallbackBiome = CoerceBiomeDefinition("overworld", {
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
		transitionSeconds = CoerceNumber(settingsRaw.transitionSeconds, 1.35, 0, 10),
		biomeSampleIntervalSeconds = CoerceNumber(settingsRaw.biomeSampleIntervalSeconds, 0.2, 0.02, 5),
		folderName = trim(settingsRaw.folderName) ~= "" and trim(settingsRaw.folderName) or "ParallaxDepth",
		segmentThickness = CoerceNumber(settingsRaw.segmentThickness, 0.2, 0.01, 16),
	}

	return {
		settings = settings,
		biomes = biomes,
		orderedBiomeNames = orderedBiomeNames,
		aliases = aliases,
	}
end

function ParallaxServiceUtils.GetBiomeName(catalog: Catalog, biomeNameRaw: any): string
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

function ParallaxServiceUtils.GetBiomeDefinition(catalog: Catalog, biomeNameRaw: any): BiomeDefinition
	return catalog.biomes[ParallaxServiceUtils.GetBiomeName(catalog, biomeNameRaw)]
end

function ParallaxServiceUtils.GetVariantName(biomeDefinition: BiomeDefinition, variantNameRaw: any): string
	local requestedName = trim(variantNameRaw)
	if requestedName ~= "" and biomeDefinition.variants[requestedName] ~= nil then
		return requestedName
	end
	return biomeDefinition.defaultVariantName
end

function ParallaxServiceUtils.GetVariantDefinition(
	catalog: Catalog,
	biomeNameRaw: any,
	variantNameRaw: any
): BiomeVariantDefinition
	local biomeDefinition = ParallaxServiceUtils.GetBiomeDefinition(catalog, biomeNameRaw)
	local variantName = ParallaxServiceUtils.GetVariantName(biomeDefinition, variantNameRaw)
	return biomeDefinition.variants[variantName]
end

function ParallaxServiceUtils.CollectAssetIds(catalog: Catalog, biomeNamesRaw: { any }?): { string }
	local assetIds: { string } = {}
	local seen: { [string]: boolean } = {}
	local biomeNames: { any } = if biomeNamesRaw ~= nil then biomeNamesRaw else catalog.orderedBiomeNames :: any

	for _, biomeNameRaw in biomeNames do
		local biome = ParallaxServiceUtils.GetBiomeDefinition(catalog, biomeNameRaw)
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

function ParallaxServiceUtils.CreateDefaultState(catalog: Catalog): ServiceState
	return {
		initialized = false,
		currentBiome = catalog.settings.defaultBiome,
		targetBiome = catalog.settings.defaultBiome,
		transitionState = "Idle",
	}
end

function ParallaxServiceUtils.CloneState(state: ServiceState): ServiceState
	return {
		initialized = state.initialized,
		currentBiome = state.currentBiome,
		targetBiome = state.targetBiome,
		transitionState = state.transitionState,
	}
end

function ParallaxServiceUtils.ComputeHorizontalVisionStuds(
	chunkSizeRaw: any,
	tileSizeRaw: any,
	renderDistanceChunksRaw: any
): number
	local chunkSize = CoerceInteger(chunkSizeRaw, 32, 1, 512)
	local tileSize = CoerceNumber(tileSizeRaw, 4, 0.25, 128)
	local renderDistanceChunks = CoerceInteger(renderDistanceChunksRaw, 4, 1, 128)
	return math.max(
		ParallaxConstants.DEFAULT_HORIZONTAL_VISION_STUDS,
		(renderDistanceChunks * 2 + 1) * chunkSize * tileSize
	)
end

function ParallaxServiceUtils.GetDeterministicPlaneSizing(
	visibleWidthRaw: any,
	sizeReferenceWidthRaw: any,
	horizontalVisionStudsRaw: any,
	imageAspectRatioRaw: any,
	heightScaleRaw: any,
	segmentWidthScaleRaw: any,
	textureStudsPerTileURaw: any,
	requiredPlaneHeightRaw: any?
): PlaneSizing
	local visibleWidth = CoerceNumber(visibleWidthRaw, 0, 0, 1000000)
	local sizeReferenceWidth = CoerceNumber(sizeReferenceWidthRaw, visibleWidth, 0, 1000000)
	local horizontalVisionStuds =
		CoerceNumber(horizontalVisionStudsRaw, ParallaxConstants.DEFAULT_HORIZONTAL_VISION_STUDS, 0, 1000000)
	local imageAspectRatio =
		CoerceNumber(imageAspectRatioRaw, ParallaxConstants.IMPLICIT_LAYER_FALLBACK_IMAGE_ASPECT_RATIO, 0.05, 64)
	local heightScale = CoerceNumber(heightScaleRaw, 1, 0.05, 4)
	local segmentWidthScale =
		CoerceNumber(segmentWidthScaleRaw, ParallaxConstants.IMPLICIT_LAYER_SEGMENT_WIDTH_SCALE_BASE, 0.25, 8)
	local textureStudsPerTileU =
		CoerceNumber(textureStudsPerTileURaw, ParallaxConstants.IMPLICIT_LAYER_BASE_TEXTURE_TILE_STUDS, 1, 4096)

	local minimumTextureRepeatWidth =
		math.max(textureStudsPerTileU * 0.25, ParallaxConstants.MINIMUM_TEXTURE_REPEAT_WIDTH_STUDS)
	local baseTextureRepeatWidth = math.max(sizeReferenceWidth * segmentWidthScale, minimumTextureRepeatWidth)
	local baseTextureRepeatHeight = math.max(1, (baseTextureRepeatWidth / imageAspectRatio) * heightScale)
	local textureRepeatHeight = math.max(baseTextureRepeatHeight, CoerceNumber(requiredPlaneHeightRaw, 0, 0, 1000000))
	local textureRepeatWidth = math.max(baseTextureRepeatWidth, (textureRepeatHeight / heightScale) * imageAspectRatio)
	local horizontalBleed = math.max(
		visibleWidth * ParallaxConstants.HORIZONTAL_PLANE_BLEED_FACTOR,
		ParallaxConstants.MINIMUM_HORIZONTAL_PLANE_BLEED_STUDS
	)
	local planeWidth =
		math.max(textureRepeatWidth, visibleWidth + horizontalBleed, horizontalVisionStuds + horizontalBleed)

	return {
		planeWidth = planeWidth,
		textureRepeatWidth = textureRepeatWidth,
		textureRepeatHeight = textureRepeatHeight,
	}
end

function ParallaxServiceUtils.GetStableGameplayPlaneDistance(
	referenceDistanceRaw: any?,
	cameraPositionXRaw: any,
	worldOriginXRaw: any,
	basePlaneXRaw: any
): number
	local cameraPositionX = CoerceNumber(cameraPositionXRaw, 0, nil, nil)
	local worldOriginX = CoerceNumber(worldOriginXRaw, 0, nil, nil)
	local basePlaneX = CoerceNumber(basePlaneXRaw, 0, nil, nil)
	local gameplayPlaneDistance = math.max(math.abs(cameraPositionX - (worldOriginX + basePlaneX)), 1)
	local referenceDistance = CoerceNumber(referenceDistanceRaw, gameplayPlaneDistance, 1, nil)
	return math.max(referenceDistance, gameplayPlaneDistance)
end

function ParallaxServiceUtils.GetHorizonLockedCenterY(
	cameraPositionYRaw: any,
	visibleHeightRaw: any,
	verticalOffsetAlphaRaw: any,
	verticalOffsetStudsRaw: any?
): number
	local cameraPositionY = CoerceNumber(cameraPositionYRaw, 0, nil, nil)
	local visibleHeight = CoerceNumber(visibleHeightRaw, 1, 1, nil)
	local verticalOffsetAlpha = CoerceNumber(verticalOffsetAlphaRaw, 0.5, -4, 4)
	local verticalOffsetStuds = CoerceNumber(verticalOffsetStudsRaw, 0, nil, nil)
	return cameraPositionY - visibleHeight * 0.5 + visibleHeight * verticalOffsetAlpha + verticalOffsetStuds
end

function ParallaxServiceUtils.GetWorldHorizonCenterY(
	worldOriginYRaw: any,
	visibleHeightRaw: any,
	verticalOffsetAlphaRaw: any,
	verticalOffsetStudsRaw: any?
): number
	local worldOriginY = CoerceNumber(worldOriginYRaw, 0, nil, nil)
	local visibleHeight = CoerceNumber(visibleHeightRaw, 1, 1, nil)
	local verticalOffsetAlpha = CoerceNumber(verticalOffsetAlphaRaw, 0.5, -4, 4)
	local verticalOffsetStuds = CoerceNumber(verticalOffsetStudsRaw, 0, nil, nil)
	return worldOriginY + visibleHeight * verticalOffsetAlpha + verticalOffsetStuds
end

function ParallaxServiceUtils.GetWorldHorizonParallaxCenterY(
	worldOriginYRaw: any,
	cameraPositionYRaw: any,
	visibleHeightRaw: any,
	verticalOffsetAlphaRaw: any,
	verticalOffsetStudsRaw: any?,
	verticalParallaxRaw: any?,
	subjectPositionRaw: any?
): number
	local worldOriginY = CoerceNumber(worldOriginYRaw, 0, nil, nil)
	local baseCenterY = ParallaxServiceUtils.GetWorldHorizonCenterY(
		worldOriginY,
		visibleHeightRaw,
		verticalOffsetAlphaRaw,
		verticalOffsetStudsRaw
	)
	local subjectY = if typeof(subjectPositionRaw) == "Vector3"
		then (subjectPositionRaw :: Vector3).Y
		else CoerceNumber(cameraPositionYRaw, worldOriginY, nil, nil)
	local verticalParallax = CoerceNumber(verticalParallaxRaw, 0, 0, 1)
	return baseCenterY + (subjectY - worldOriginY) * verticalParallax
end

function ParallaxServiceUtils.GetSharedHorizonVerticalShift(layerLimitsRaw: any): number
	if typeof(layerLimitsRaw) ~= "table" then
		return 0
	end

	local shift = 0
	for _, layerLimitRaw in layerLimitsRaw :: { any } do
		if typeof(layerLimitRaw) ~= "table" then
			continue
		end

		local layerLimit = layerLimitRaw :: { [string]: any }
		local centerY = CoerceNumber(layerLimit.centerY, 0, nil, nil)
		local maximumCenterY = CoerceNumber(layerLimit.maximumCenterY, centerY, nil, nil)
		shift = math.min(shift, maximumCenterY - centerY)
	end
	return shift
end

function ParallaxServiceUtils.GetScrollPositionZ(cameraPositionZRaw: any, subjectPositionRaw: any?): number
	if typeof(subjectPositionRaw) == "Vector3" then
		return (subjectPositionRaw :: Vector3).Z
	end

	return CoerceNumber(cameraPositionZRaw, 0, nil, nil)
end

function ParallaxServiceUtils.GetPlayerTravelZ(
	anchorPositionZRaw: any?,
	previousTravelZRaw: any?,
	subjectPositionRaw: any?
): (number, number?)
	local previousTravelZ = CoerceNumber(previousTravelZRaw, 0, nil, nil)
	local anchorPositionZ = if typeof(anchorPositionZRaw) == "number"
		then CoerceNumber(anchorPositionZRaw, 0, nil, nil)
		else nil

	if typeof(subjectPositionRaw) ~= "Vector3" then
		return previousTravelZ, anchorPositionZ
	end

	local subjectPositionZ = (subjectPositionRaw :: Vector3).Z
	if anchorPositionZ == nil then
		return 0, subjectPositionZ
	end

	return subjectPositionZ - anchorPositionZ, anchorPositionZ
end

function ParallaxServiceUtils.GetBiomeNameFromWorldSample(
	catalog: Catalog,
	biomeIdRaw: any,
	biomeTypeRaw: any,
	_depthLayerRaw: any
): string
	local biomeType = CoerceInteger(biomeTypeRaw, WorldSimulationShared.BIOME_ID.FOREST, 0, 1024)
	local biomeId = CoerceInteger(biomeIdRaw, WorldSimulationShared.BIOME_ID.FOREST, 0, 1024)

	if biomeId == WorldSimulationShared.BIOME_ID.CORRUPTION or biomeType == 2 then
		return ParallaxServiceUtils.GetBiomeName(catalog, "Corruption")
	end
	if biomeId == WorldSimulationShared.BIOME_ID.DESERT then
		return ParallaxServiceUtils.GetBiomeName(catalog, "Desert")
	end
	if biomeId == WorldSimulationShared.BIOME_ID.SNOW then
		return ParallaxServiceUtils.GetBiomeName(catalog, "Snow")
	end
	if biomeId == WorldSimulationShared.BIOME_ID.JUNGLE then
		return ParallaxServiceUtils.GetBiomeName(catalog, "Jungle")
	end
	return ParallaxServiceUtils.GetBiomeName(catalog, "Overworld")
end

return ParallaxServiceUtils
