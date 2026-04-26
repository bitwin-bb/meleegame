--!strict
-- selene: allow(undefined_variable)

local ParallaxServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.ParallaxServiceUtils)

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
	end)
end
