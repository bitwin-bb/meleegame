local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

-- selene: allow(undefined_variable)

local ParallaxBackgrounds = require("ParallaxBackgrounds")
local ParallaxBiomeResolver = require("ParallaxBiomeResolver")
local ParallaxHorizonResolver = require("ParallaxHorizonResolver")
local ParallaxMath = require("ParallaxMath")
local ParallaxProfiles = require("ParallaxProfiles")
local ParallaxServiceUtils = require("ParallaxServiceUtils")
local ParallaxState = require("ParallaxState")

return function()
	describe("ParallaxServiceUtils", function()
		it("derives horizontal vision width from streamed chunk distance", function()
			local defaultVisionStuds = ParallaxServiceUtils.computeHorizontalVisionStuds(32, 2, 4)
			local extendedVisionStuds = ParallaxServiceUtils.computeHorizontalVisionStuds(32, 2, 8)

			expect(defaultVisionStuds).to.equal(576)
			expect(extendedVisionStuds).to.equal(1088)
		end)

		it("sizes long planes from the larger of camera coverage and world vision", function()
			local visibleDriven = ParallaxServiceUtils.resolveDeterministicPlaneSizing(620, 400, 300, 2, 1, 0.75, 96)
			local visionDriven = ParallaxServiceUtils.resolveDeterministicPlaneSizing(300, 400, 900, 2, 1, 0.75, 96)

			expect(math.abs(visibleDriven.textureRepeatWidth - 300) <= 0.001).to.equal(true)
			expect(math.abs(visibleDriven.textureRepeatHeight - 150) <= 0.001).to.equal(true)
			expect(math.abs(visibleDriven.planeWidth - 669.6) <= 0.001).to.equal(true)

			expect(math.abs(visionDriven.textureRepeatWidth - 300) <= 0.001).to.equal(true)
			expect(math.abs(visionDriven.textureRepeatHeight - 150) <= 0.001).to.equal(true)
			expect(math.abs(visionDriven.planeWidth - 924) <= 0.001).to.equal(true)
		end)

		it("expands the repeat width when extra vertical coverage is needed", function()
			local preservedAspect =
				ParallaxServiceUtils.resolveDeterministicPlaneSizing(300, 400, 200, 2, 1, 0.75, 96, 240)

			expect(math.abs(preservedAspect.textureRepeatWidth - 480) <= 0.001).to.equal(true)
			expect(math.abs(preservedAspect.textureRepeatHeight - 240) <= 0.001).to.equal(true)
			expect(math.abs(preservedAspect.planeWidth - 480) <= 0.001).to.equal(true)
		end)

		it("keeps zoom reference from shrinking when the camera moves closer", function()
			local initial = ParallaxServiceUtils.resolveStableGameplayPlaneDistance(nil, 52, 0, 0)
			local closer = ParallaxServiceUtils.resolveStableGameplayPlaneDistance(initial, 36, 0, 0)
			local farther = ParallaxServiceUtils.resolveStableGameplayPlaneDistance(closer, 64, 0, 0)

			expect(initial).to.equal(52)
			expect(closer).to.equal(52)
			expect(farther).to.equal(64)
		end)

		it("resolves horizon-locked center Y from camera space", function()
			local lowCamera = ParallaxServiceUtils.resolveHorizonLockedCenterY(20, 100, 0.78, 4)
			local highCamera = ParallaxServiceUtils.resolveHorizonLockedCenterY(60, 100, 0.78, 4)

			expect(math.abs(lowCamera - 52) <= 0.001).to.equal(true)
			expect(math.abs(highCamera - 92) <= 0.001).to.equal(true)
		end)

		it("resolves world horizon center from world origin", function()
			local horizon = ParallaxServiceUtils.resolveWorldHorizonCenterY(0, 100, 1, -18)

			expect(math.abs(horizon - 82) <= 0.001).to.equal(true)
		end)

		it("offsets world horizon center by scaled subject height", function()
			local cameraHorizon =
				ParallaxServiceUtils.resolveWorldHorizonParallaxCenterY(10, 40, 100, 0.78, 4, 0.25, nil)
			local subjectHorizon = ParallaxServiceUtils.resolveWorldHorizonParallaxCenterY(
				10,
				40,
				100,
				0.78,
				4,
				0.25,
				Vector3.new(0, 70, 0)
			)

			expect(math.abs(cameraHorizon - 99.5) <= 0.001).to.equal(true)
			expect(math.abs(subjectHorizon - 107) <= 0.001).to.equal(true)
		end)

		it("resolves one vertical horizon shift for grouped layers", function()
			local shift = ParallaxServiceUtils.resolveSharedHorizonVerticalShift({
				{
					centerY = 82,
					maximumCenterY = 70,
				},
				{
					centerY = 92,
					maximumCenterY = 110,
				},
			})

			expect(shift).to.equal(-12)
		end)

		it("prefers target travel for scroll when camera is still catching up", function()
			local scrollZ = ParallaxServiceUtils.resolveScrollPositionZ(180, Vector3.new(0, 0, 24))

			expect(scrollZ).to.equal(24)
		end)
	end)

	describe("ParallaxMath", function()
		it("uses depth from world top for parallax top placement", function()
			local scAdj = ParallaxMath.ComputeScreenAdjustment(120, 900, 60, 1800)
			local topPx = ParallaxMath.ComputeBgTopPx(120, 900, 60, 1800, 1500, scAdj, 12)

			expect(math.abs(scAdj) <= 0.001).to.equal(true)
			expect(math.abs(topPx - 2412) <= 0.001).to.equal(true)
		end)

		it("converts parallax screen top into world center", function()
			local centerY = ParallaxMath.ScreenTopPxToWorldCenterY(300, 600, 100, 120, 40)

			expect(math.abs(centerY - 20) <= 0.001).to.equal(true)
		end)

		it("sizes textures from source dimensions and wraps parallax horizontally", function()
			local width, height = ParallaxMath.ComputeTextureSizeWorld(1024, 512, 2, 100, 500)
			local offset = ParallaxMath.ComputeHorizontalTextureOffsetWorld(250, 0.4, 64)

			expect(math.abs(width - 409.6) <= 0.001).to.equal(true)
			expect(math.abs(height - 204.8) <= 0.001).to.equal(true)
			expect(math.abs(offset - 36) <= 0.001).to.equal(true)
		end)
	end)

	describe("ParallaxHorizonResolver", function()
		it("smooths a broad terrain horizon and returns depth-from-top values", function()
			local sampleCount = 0
			local fakeWorldGenerationService = {
				getAverageSurfaceYAroundWorldPosition = function(_self: any, _worldPosition: Vector3, _radius: number)
					sampleCount += 1
					return if sampleCount == 1 then 160 else 200
				end,
			}
			local runtime = {
				worldGenerationServiceClient = fakeWorldGenerationService,
				worldOrigin = Vector3.new(0, 0, 0),
				worldTopY = 220,
				worldBottomY = -100,
				worldSurfaceY = 100,
				seaLevelY = 80,
				maxTilesY = 1800,
				layoutStateValue = {
					Value = {
						tileSize = 4,
						chunkSize = 32,
					},
				},
			}

			local first = ParallaxHorizonResolver.ResolveHorizon(runtime, Vector3.new(0, 130, 40), nil, 0)
			local second = ParallaxHorizonResolver.ResolveHorizon(runtime, Vector3.new(0, 130, 40), nil, 0.25)

			expect(first.globalSurfaceY).to.equal(100)
			expect(first.localSurfaceY).to.equal(160)
			expect(first.resolvedHorizonY).to.equal(115)
			expect(first.cameraDepthFromTop).to.equal(90)
			expect(first.surfaceDepthFromTop).to.equal(105)
			expect(second.resolvedHorizonY > first.resolvedHorizonY).to.equal(true)
			expect(second.resolvedHorizonY < 125).to.equal(true)
		end)
	end)

	describe("ParallaxBiomeResolver", function()
		it("resolves biome style using asset-backed biome keys", function()
			expect(ParallaxBiomeResolver.ResolveBgStyle({
				depthLayer = ParallaxServiceUtils.DEPTH_LAYER_SKY,
				isNearWorldEdge = true,
			}, nil)).to.equal(ParallaxProfiles.Styles.Overworld)

			expect(ParallaxBiomeResolver.ResolveBgStyle({
				biomeName = "Desert",
				isHallow = true,
			}, nil)).to.equal(ParallaxProfiles.Styles.Desert)

			expect(ParallaxBiomeResolver.ResolveBgStyle({
				biomeName = "Jungle",
			}, nil)).to.equal(ParallaxProfiles.Styles.Jungle)
		end)

		it("prefers explicit biome identity over secondary tile hints", function()
			expect(ParallaxBiomeResolver.ResolveBgStyle({
				biomeName = "Corruption",
				isDesert = true,
				sandTileCount = 128,
			}, nil)).to.equal(ParallaxProfiles.Styles.Corruption)

			expect(ParallaxBiomeResolver.ResolveBgStyle({
				biomeId = 2,
				biomeType = 2,
				sandTileCount = 128,
			}, nil)).to.equal(ParallaxProfiles.Styles.Corruption)

			expect(ParallaxBiomeResolver.ResolveBgStyle({
				biomeName = "Jungle",
				isSand = true,
				sandTileCount = 128,
			}, nil)).to.equal(ParallaxProfiles.Styles.Jungle)
		end)

		it("exposes render defaults on readonly parallax profiles", function()
			local ok = pcall(function()
				for _, profiles in ParallaxProfiles.ByStyle do
					for _, profile in profiles do
						local _offsetX = profile.offsetX
						local _offsetY = profile.offsetY
						local _transparency = profile.transparency
						local _flipX = profile.flipX
					end
				end
			end)

			expect(ok).to.equal(true)
		end)

		it("keeps parallax profile layers assigned to matching ParallaxBackgrounds keys", function()
			local specs = {
				{
					style = ParallaxProfiles.Styles.Overworld,
					styleName = "Overworld",
					biomeName = "overworld",
					variantName = "overworld1",
				},
				{
					style = ParallaxProfiles.Styles.Corruption,
					styleName = "Corruption",
					biomeName = "corruption",
					variantName = "corruption1",
				},
				{
					style = ParallaxProfiles.Styles.Desert,
					styleName = "Desert",
					biomeName = "desert",
					variantName = "desert1",
				},
				{
					style = ParallaxProfiles.Styles.Jungle,
					styleName = "Jungle",
					biomeName = "jungle",
					variantName = "jungle1",
				},
				{
					style = ParallaxProfiles.Styles.Snow,
					styleName = "Snow",
					biomeName = "snow",
					variantName = "snow1",
				},
			}

			for _, spec in specs do
				local profiles = ParallaxProfiles.ByStyle[spec.style]
				local sourceLayers = ParallaxBackgrounds[spec.biomeName][spec.variantName]

				for layerKey = 1, 4 do
					local profile = profiles[layerKey]
					expect(profile.id).to.equal(`{spec.styleName}_Layer{layerKey}`)
					expect(profile.image).to.equal(sourceLayers[layerKey])
					expect(profile.planeDepthBlocks).to.equal(40 + (layerKey - 1) * 16)
				end
			end
		end)

		it("uses scale, placement, and parallax speed for depth without darkening far layers", function()
			local profiles = ParallaxProfiles.ByStyle[ParallaxProfiles.Styles.Overworld]
			local nearLayer = profiles[1]
			local farLayer = profiles[4]

			expect(farLayer.bgScale < nearLayer.bgScale).to.equal(true)
			expect(farLayer.parallaxX < nearLayer.parallaxX).to.equal(true)
			expect(farLayer.baseScreenY < nearLayer.baseScreenY).to.equal(true)
			expect(farLayer.transparency).to.equal(0)
			expect(farLayer.tint).to.equal(Color3.new(1, 1, 1))
		end)
	end)

	describe("ParallaxState", function()
		it("delays style changes and fades close and far groups separately", function()
			local state = ParallaxState.new()

			state:Update(ParallaxProfiles.Styles.Desert, 1)
			expect(state.bgStyle).to.equal(ParallaxProfiles.Styles.Overworld)

			state:Update(ParallaxProfiles.Styles.Desert, 1)
			expect(state.bgStyle).to.equal(ParallaxProfiles.Styles.Desert)
			expect(state:GetStyleAlpha(ParallaxProfiles.Styles.Desert) > 0).to.equal(true)
			expect(state:GetFarAlpha(ParallaxProfiles.Styles.Desert) > 0).to.equal(true)
		end)

		it("does not let shared far groups make another biome visible", function()
			local state = ParallaxState.new()
			local jungleStyleAlpha = state:GetStyleAlpha(ParallaxProfiles.Styles.Jungle)
			local jungleFarAlpha = state:GetFarAlpha(ParallaxProfiles.Styles.Jungle)

			expect(jungleStyleAlpha).to.equal(0)
			expect(jungleFarAlpha).to.equal(1)
			expect(jungleStyleAlpha * jungleFarAlpha).to.equal(0)
		end)
	end)
end
