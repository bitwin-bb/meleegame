--!strict
-- selene: allow(undefined_variable)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Angle = require(ReplicatedStorage.Shared.Modules.Math.Angle)
local Bounds = require(ReplicatedStorage.Shared.Modules.Math.Bounds)
local Damp = require(ReplicatedStorage.Shared.Modules.Math.Damp)
local Num = require(ReplicatedStorage.Shared.Modules.Math.Num)
local Proj = require(ReplicatedStorage.Shared.Modules.Math.Proj)
local Solve = require(ReplicatedStorage.Shared.Modules.Math.Solve)
local Spring = require(ReplicatedStorage.Shared.Modules.Math.Spring)

local function expectNear(actual: number, expected: number, epsilon: number?)
	local tolerance = epsilon or 1e-5
	expect(math.abs(actual - expected) <= tolerance).to.equal(true)
end

return function()
	describe("Math modules", function()
		it("wraps shortest radian deltas across the -pi/pi seam", function()
			local delta = Angle.deltaRadians(math.rad(350), math.rad(10))
			expectNear(delta, math.rad(20), 1e-6)
		end)

		it("projects vectors onto an axis without leaking orthogonal components", function()
			local projected = Proj.vector(Vector3.new(3, 4, 0), Vector3.xAxis)
			expect(projected).to.equal(Vector3.new(3, 0, 0))
		end)

		it("computes squared distance to bounds from the closest point", function()
			local bounds = Bounds.fromCenterSize(Vector3.zero, Vector3.new(4, 4, 4))
			expect(Bounds.distanceSqToPoint(bounds, Vector3.new(5, 0, 0))).to.equal(9)
		end)

		it("preserves remap behavior for basic scalar normalization", function()
			expect(Num.remap(5, 0, 10, 0, 1)).to.equal(0.5)
			expect(Num.remap(2.5, 0, 5, -1, 1)).to.equal(0)
		end)

		it("matches the exponential damping factor definition", function()
			expectNear(Damp.factor(5, 0.1), 1 - math.exp(-0.5), 1e-6)
			expect(Damp.factor(0, 0.1)).to.equal(0)
		end)

		it("steps springs toward the target and respects mass scaling", function()
			local lightState = Spring.step(Spring.state(0, 0), 10, 2, 1, 0.1, 1)
			local heavyState = Spring.step(Spring.state(0, 0), 10, 2, 1, 0.1, 4)

			expect(lightState.value > 0).to.equal(true)
			expect(lightState.velocity > 0).to.equal(true)
			expect(lightState.value > heavyState.value).to.equal(true)
			expect(lightState.velocity > heavyState.velocity).to.equal(true)
		end)

		it("solves quadratic roots deterministically", function()
			local roots = Solve.quadratic(1, -3, 2)
			expect(roots.count).to.equal(2)
			expect(roots.min).to.equal(1)
			expect(roots.max).to.equal(2)
		end)
	end)
end
