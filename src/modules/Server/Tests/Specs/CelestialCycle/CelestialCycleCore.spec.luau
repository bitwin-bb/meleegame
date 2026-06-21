local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

-- selene: allow(undefined_variable)

local CelestialCycleConstants = require("CelestialCycleConstants")
local MoonAssets = require("MoonAssets")
local RotationMath = require("RotationMath")
local SunAsset = require("SunAsset")
local WeatherServiceUtils = require("WeatherServiceUtils")

return function()
	local function expectNear(actual: number, expected: number, epsilon: number?)
		local tolerance = epsilon or 1e-4
		expect(math.abs(actual - expected) <= tolerance).to.equal(true)
	end

	describe("CelestialCycle shared math", function()
		it("normalizes clock time and derives day progress", function()
			expect(RotationMath.normalizeClockTime(24.5)).to.equal(0.5)
			expect(RotationMath.normalizeClockTime(-1)).to.equal(23)
			expectNear(RotationMath.resolveDayProgress(6), 0.25)
			expectNear(RotationMath.resolveDayProgress(18), 0.75)
		end)

		it("walks one real-world style phase per in-game day across eight days", function()
			local expected = {
				"new",
				"waxingCrescent",
				"firstQuarter",
				"waxingGibbous",
				"fullMoon",
				"waningGibbous",
				"thirdQuarter",
				"waningCrescent",
				"new",
			}

			for dayIndex, phaseName in expected do
				expect(RotationMath.resolveMoonPhase(dayIndex - 1)).to.equal(phaseName)
			end
			expect(CelestialCycleConstants.MOON_PHASE_DAY_COUNT).to.equal(8)
		end)

		it("resolves sun and moon image assets", function()
			local newMoonImage = MoonAssets.getImageForPhase("new")

			expect(SunAsset.getImage()).to.equal("rbxassetid://130185077109129")
			expect(newMoonImage).to.equal("rbxassetid://73088477000613")
			expect(MoonAssets.getImageForPhase("fullMoon")).to.equal("rbxassetid://71652201703042")
			expect(MoonAssets.getImageForPhase("not-a-phase")).to.equal(newMoonImage)
		end)

		it("derives body state from clock time and world day index", function()
			local noonState = RotationMath.resolveCycleState(12, 4)
			local midnightState = RotationMath.resolveCycleState(0, 4)

			expect(noonState.clockTime).to.equal(12)
			expect(noonState.worldDayIndex).to.equal(4)
			expect(noonState.moonPhase).to.equal("fullMoon")
			expect(noonState.sun.visible).to.equal(true)
			expect(noonState.sun.alpha > noonState.moon.alpha).to.equal(true)
			expect(noonState.moon.visible).to.equal(false)

			expect(midnightState.moon.visible).to.equal(true)
			expect(midnightState.moon.phase).to.equal("fullMoon")
			expect(midnightState.dayPart).to.equal("Night")
		end)
	end)

	describe("WeatherService world day index", function()
		it("preserves worldDayIndex through sanitize and clone", function()
			local state = WeatherServiceUtils.sanitizeState({
				worldDayIndex = 17,
			}, nil)
			local cloned = WeatherServiceUtils.cloneState(state)

			expect(state.worldDayIndex).to.equal(17)
			expect(cloned.worldDayIndex).to.equal(17)
		end)

		it("reports midnight wraps while advancing the clock", function()
			local result = WeatherServiceUtils.advanceClockTimeWithDayDelta(23.5, 60, 24 / 120)

			expectNear(result.clockTime, 11.5)
			expect(result.dayDelta).to.equal(1)
		end)

		it("keeps day delta at zero without a midnight wrap", function()
			local result = WeatherServiceUtils.advanceClockTimeWithDayDelta(10, 10, 0.5)

			expectNear(result.clockTime, 15)
			expect(result.dayDelta).to.equal(0)
		end)

		it("reports multiple midnight wraps while advancing the clock", function()
			local result = WeatherServiceUtils.advanceClockTimeWithDayDelta(23, 130, 24 / 60)

			expectNear(result.clockTime, 3)
			expect(result.dayDelta).to.equal(3)
		end)
	end)
end
