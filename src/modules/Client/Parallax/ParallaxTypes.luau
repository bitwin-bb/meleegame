local require = require(script.Parent.loader).load(script)

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
	verticalParallax: number,
	baseYOffset: number,
	bottomOverscan: number,
	minY: number,
	maxY: number,
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

export type PlaneSizing = {
	planeWidth: number,
	textureRepeatWidth: number,
	textureRepeatHeight: number,
}

return {}
