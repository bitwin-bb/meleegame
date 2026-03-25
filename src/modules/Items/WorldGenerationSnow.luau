--!strict

return {
	Region = {
		Weight = 1.08,
		TemperatureMax = 0.18,
		HumidityMax = 0.42,
		BandHalfWidthMin = 120,
		BandHalfWidthMax = 235,
		BandFeatherWidth = 132,
		AnchorDistanceBase = 220,
		AnchorDistanceJitter = 108,
		PrimaryThreshold = 0.2,
		MacroFrequencyScale = 0.88,
		BorderFrequencyScale = 1.38,
		DetailFrequencyScale = 2.16,
	},
	Terrain = {
		HeightOffset = 0,
		SmoothedRidgeScale = 0.78,
		StoneDepthOffset = 2,
	},
	Surface = {
		SurfaceTile = "SNOW",
		FillerTile = "SNOW",
		DeepTile = "STONE",
		SnowCapDepth = 3,
		ColdSoilDepth = 6,
		IceDepthStart = 11,
		IceBandThickness = 10,
		IceDensity = 0.34,
		PackedSnowDensity = 0.52,
	},
	Caves = {
		UndergroundThresholdDelta = -0.025,
		CavernThresholdDelta = -0.045,
		PocketThresholdDelta = -0.06,
	},
	Decoration = {
		TreeChance = 0.38,
		TreeEdgeBufferTiles = 8,
		SnowPileSpacingTiles = 11,
		SnowPileChance = 0.24,
		IceSpikeSpacingTiles = 15,
		IceSpikeChance = 0.13,
		PropEdgeBufferTiles = 6,
		PropStructureBufferTiles = 10,
		PropAirClearanceTiles = 5,
	},
	Liquid = {
		WaterTint = Color3.fromRGB(39, 90, 114),
	},
}
