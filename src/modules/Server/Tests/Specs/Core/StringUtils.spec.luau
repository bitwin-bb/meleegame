--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StringUtils = require(script:FindFirstAncestor("game").Shared.Modules.Core.StringUtils)

return function()
	describe("StringUtils", function()
		it("trims surrounding whitespace", function()
			expect(StringUtils.trim("  Aquaria  ")).to.equal("Aquaria")
		end)

		it("falls back when sanitize receives an empty string", function()
			expect(StringUtils.sanitize("   ", "fallback")).to.equal("fallback")
		end)

		it("compacts tokens for shared lookup paths", function()
			expect(StringUtils.compactToken(" Green-Slime ")).to.equal("greenslime")
		end)
	end)
end
