local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local StringUtils = require("StringUtils")

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
