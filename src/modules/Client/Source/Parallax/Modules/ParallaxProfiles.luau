local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local ParallaxBackgrounds = require("ParallaxBackgrounds")
local ParallaxConstants = require("ParallaxConstants")

local Profile = {}

export type LayerProfile = {
	id: string,
	image: string,
	imageWidth: number?,
	imageHeight: number?,
	imageAspectRatio: number?,
	bgStyle: number,
	alphaGroup: "bgAlpha" | "bgAlpha2"?,
	parallaxX: number,
	bgScale: number,
	verticalStrength: number,
	baseScreenY: number,
	offsetX: number,
	offsetY: number,
	planeDepthBlocks: number?,
	tint: Color3?,
	transparency: number,
	zIndex: number?,
	flipX: boolean,
}

type LayerTuning = {
	label: string?,
	Scale: number,
	ParallaxX: number,
	verticalStrength: number,
	baseScreenY: number,
	alphaGroup: "bgAlpha" | "bgAlpha2"?,
}

local Styles = Table.deepReadonly({
	Overworld = 0,
	Corruption = 1,
	Desert = 2,
	Jungle = 3,
	Ocean = 4,
	DesertHybrid = 5,
	Hallow = 6,
	Snow = 7,
	Crimson = 8,
	Mushroom = 9,
})

local StyleNames = Table.deepReadonly({
	[Styles.Overworld] = "Overworld",
	[Styles.Corruption] = "Corruption",
	[Styles.Desert] = "Desert",
	[Styles.Jungle] = "Jungle",
	[Styles.Ocean] = "Ocean",
	[Styles.DesertHybrid] = "DesertHybrid",
	[Styles.Hallow] = "Hallow",
	[Styles.Snow] = "Snow",
	[Styles.Crimson] = "Crimson",
	[Styles.Mushroom] = "Mushroom",
})

local BiomeToStyle = Table.deepReadonly({
	overworld = Styles.Overworld,
	forest = Styles.Overworld,
	default = Styles.Overworld,
	surface = Styles.Overworld,
	corruption = Styles.Corruption,
	corrupt = Styles.Corruption,
	evil = Styles.Corruption,
	desert = Styles.Desert,
	sand = Styles.Desert,
	jungle = Styles.Jungle,
	snow = Styles.Snow,
	tundra = Styles.Snow,
})

local function normalizeToken(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	local value = string.lower(valueRaw)
	value = string.gsub(value, "%s+", "")
	value = string.gsub(value, "_", "")
	value = string.gsub(value, "%-", "")
	return value
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

local function getVariantLayers(biomeName: string): { [number]: any }
	local biome = (ParallaxBackgrounds :: any)[biomeName]
	if typeof(biome) ~= "table" then
		return {}
	end

	local source = biome :: { [any]: any }
	if typeof(source.layers) == "table" then
		return source.layers :: { [number]: any }
	end

	local defaultVariantName = source.defaultVariant
	if typeof(defaultVariantName) == "string" then
		local defaultVariant = source[defaultVariantName]
		if typeof(defaultVariant) == "table" then
			local variantSource = defaultVariant :: { [any]: any }
			if typeof(variantSource.layers) == "table" then
				return variantSource.layers :: { [number]: any }
			end
			return variantSource :: { [number]: any }
		end
	end

	for _, variantName in collectSortedStringKeys(source) do
		if ParallaxConstants.BIOME_RESERVED_KEYS[variantName] then
			continue
		end
		local value = source[variantName]
		if typeof(value) == "table" then
			local variantSource = value :: { [any]: any }
			if typeof(variantSource.layers) == "table" then
				return variantSource.layers :: { [number]: any }
			end
			return variantSource :: { [number]: any }
		end
	end
	return {}
end

local function getSourceDimensions(biomeName: string, layerIndex: number): (number, number)
	local biomeDimensions = ParallaxConstants.IMPLICIT_PARALLAX_SOURCE_DIMENSIONS[biomeName]
	local dimensions = if biomeDimensions ~= nil then biomeDimensions[layerIndex] else nil
	if dimensions ~= nil then
		return dimensions.width, dimensions.height
	end
	return 1024, 600
end

local function getImage(biomeName: string, layerIndex: number): string?
	local layers = getVariantLayers(biomeName)
	local image = layers[layerIndex]
	if typeof(image) == "string" and image ~= "" then
		return image
	end
	return nil
end

local function createLayer(
	style: number,
	styleName: string,
	assetBiomeName: string,
	layerIndex: number,
	label: string,
	scale: number,
	parallaxX: number,
	verticalStrength: number,
	baseScreenY: number,
	alphaGroup: "bgAlpha" | "bgAlpha2"?
): LayerProfile?
	local image = getImage(assetBiomeName, layerIndex)
	if image == nil then
		return nil
	end

	local imageWidth, imageHeight = getSourceDimensions(assetBiomeName, layerIndex)
	local stackIndex = math.max(layerIndex - 1, 0)
	return {
		id = `{styleName}_{label}`,
		image = image,
		imageWidth = imageWidth,
		imageHeight = imageHeight,
		imageAspectRatio = imageWidth / math.max(imageHeight, 1),
		bgStyle = style,
		alphaGroup = alphaGroup,
		parallaxX = parallaxX,
		bgScale = scale,
		verticalStrength = verticalStrength,
		baseScreenY = baseScreenY,
		offsetX = 0,
		offsetY = 0,
		planeDepthBlocks = ParallaxConstants.IMPLICIT_LAYER_PLANE_DEPTH_BASE
			+ stackIndex * ParallaxConstants.IMPLICIT_LAYER_PLANE_DEPTH_STEP,
		tint = Color3.new(1, 1, 1),
		transparency = 0,
		zIndex = 1000 - layerIndex,
		flipX = false,
	}
end

local DEFAULT_LAYER_TUNINGS: { LayerTuning } = {
	{
		label = "Layer1",
		Scale = 2.68,
		ParallaxX = 0.49,
		verticalStrength = 2100,
		baseScreenY = 2000,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer2",
		Scale = 2.62,
		ParallaxX = 0.43,
		verticalStrength = 1950,
		baseScreenY = 1750,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer3",
		Scale = 2.5,
		ParallaxX = 0.4,
		verticalStrength = 1800,
		baseScreenY = 1500,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer4",
		Scale = 2,
		ParallaxX = 0.15,
		verticalStrength = 1300,
		baseScreenY = 1090,
		alphaGroup = "bgAlpha2",
	},
}

local DESERT_LAYER_TUNINGS: { LayerTuning } = {
	{
		label = "Layer1",
		Scale = 2.68,
		ParallaxX = 0.49,
		verticalStrength = 2100,
		baseScreenY = 2150,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer2",
		Scale = 2.68,
		ParallaxX = 0.49,
		verticalStrength = 2100,
		baseScreenY = 2150,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer3",
		Scale = 2.5,
		ParallaxX = 0.37,
		verticalStrength = 1800,
		baseScreenY = 1750,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer4",
		Scale = 2,
		ParallaxX = 0.15,
		verticalStrength = 1300,
		baseScreenY = 1090,
		alphaGroup = "bgAlpha2",
	},
}

local JUNGLE_LAYER_TUNINGS: { LayerTuning } = {
	{
		label = "Layer1",
		Scale = 2.68,
		ParallaxX = 0.49,
		verticalStrength = 2100,
		baseScreenY = 2060,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer2",
		Scale = 2.62,
		ParallaxX = 0.43,
		verticalStrength = 1950,
		baseScreenY = 1840,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer3",
		Scale = 2.5,
		ParallaxX = 0.4,
		verticalStrength = 1800,
		baseScreenY = 1660,
		alphaGroup = "bgAlpha",
	},
	{
		label = "Layer4",
		Scale = 2,
		ParallaxX = 0.15,
		verticalStrength = 1300,
		baseScreenY = 1090,
		alphaGroup = "bgAlpha2",
	},
}

local function getLayerTuning(tuningsRaw: { LayerTuning }?, ordinal: number): LayerTuning
	local tunings = tuningsRaw or DEFAULT_LAYER_TUNINGS
	local tuning = tunings[ordinal]
	if tuning ~= nil then
		return tuning
	end
	return tunings[#tunings]
		or DEFAULT_LAYER_TUNINGS[math.min(ordinal, #DEFAULT_LAYER_TUNINGS)]
		or DEFAULT_LAYER_TUNINGS[1]
end

local function createProfilesFromAssetOrder(
	style: number,
	styleName: string,
	assetBiomeName: string,
	tuningsRaw: { LayerTuning }?
): { LayerProfile }
	local profiles: { LayerProfile } = {}
	local layerIndices = collectSortedNumericIndices(getVariantLayers(assetBiomeName))
	for _, layerIndex in layerIndices do
		local tuning = getLayerTuning(tuningsRaw, layerIndex)
		local profile = createLayer(
			style,
			styleName,
			assetBiomeName,
			layerIndex,
			`Layer{layerIndex}`,
			tuning.Scale,
			tuning.ParallaxX,
			tuning.verticalStrength,
			tuning.baseScreenY,
			tuning.alphaGroup
		)
		if profile ~= nil then
			table.insert(profiles, profile)
		end
	end
	return profiles
end

local ByStyle = {
	[Styles.Overworld] = createProfilesFromAssetOrder(
		Styles.Overworld,
		"Overworld",
		"overworld",
		DEFAULT_LAYER_TUNINGS
	),
	[Styles.Corruption] = createProfilesFromAssetOrder(
		Styles.Corruption,
		"Corruption",
		"corruption",
		DEFAULT_LAYER_TUNINGS
	),
	[Styles.Desert] = createProfilesFromAssetOrder(Styles.Desert, "Desert", "desert", DESERT_LAYER_TUNINGS),
	[Styles.Jungle] = createProfilesFromAssetOrder(Styles.Jungle, "Jungle", "jungle", JUNGLE_LAYER_TUNINGS),
	[Styles.Snow] = createProfilesFromAssetOrder(Styles.Snow, "Snow", "snow", DEFAULT_LAYER_TUNINGS),
}

function Profile.GetProfilesForStyle(style: number): { LayerProfile }
	return ByStyle[style] or ByStyle[Styles.Overworld]
end

function Profile.GetStyleName(style: number): string
	return StyleNames[style] or StyleNames[Styles.Overworld]
end

function Profile.GetStyleFromBiomeName(biomeNameRaw: any): number
	return BiomeToStyle[normalizeToken(biomeNameRaw)] or Styles.Overworld
end

Profile.Styles = Styles
Profile.StyleNames = StyleNames
Profile.ByStyle = Table.deepReadonly(ByStyle)

return Profile
