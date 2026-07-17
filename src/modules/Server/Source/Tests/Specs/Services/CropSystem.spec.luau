local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CropDefinitions = require("CropDefinitions")
local CropRules = require("CropRules")
local CropStateStore = require("CropStateStore")
local CropTreeBuilder = require("CropTreeBuilder")
local CropTypes = require("CropTypes")

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local function createEnvironment(overridesRaw: any?): any
	local environment = {
		targetTileId = 0,
		soilTileId = 1,
		biomeId = 1,
		biomeType = 1,
		clockTime = 12,
		dayPart = "Day",
		weatherType = "Clear",
		light = 1,
		water = 0,
		rain = 0,
		targetOpen = true,
		openAbove = 16,
		openLeft = 16,
		openRight = 16,
	}
	for key, value in if typeof(overridesRaw) == "table" then overridesRaw else {} do
		environment[key] = value
	end
	return environment
end

return function()
	describe("CropSystem", function()
		it("requires final-stage bloom conditions before harvest", function()
			local definition = CropDefinitions.Get("Daybloom")
			local state = {
				cropId = "Daybloom",
				tileX = 4,
				tileY = 8,
				stage = CropRules.GetFinalStage(definition),
			}

			local dayAllowed = select(1, CropRules.CanHarvest(definition, state, createEnvironment()))
			local nightAllowed, reason = CropRules.CanHarvest(
				definition,
				state,
				createEnvironment({ dayPart = "Night", clockTime = 23, light = 0.1 })
			)

			expect(dayAllowed).to.equal(true)
			expect(nightAllowed).to.equal(false)
			expect(reason).to.equal("invalid_time")
		end)

		it("indexes compact crop states by chunk and tree root", function()
			local store = CropStateStore.New(32)
			local rootKey = CropTypes.GetTileKey(2, 3)
			store:Set({
				cropId = "ForestTree",
				tileX = 2,
				tileY = 3,
				stage = 1,
				rootKey = rootKey,
				segment = CropTypes.Segment.Trunk,
			})
			store:Set({
				cropId = "ForestTree",
				tileX = 3,
				tileY = 6,
				stage = 1,
				rootKey = rootKey,
				segment = CropTypes.Segment.Branch,
			})

			expect(store:GetCount()).to.equal(2)
			expect(#store:GetChunkStates("0:0")).to.equal(2)
			expect(#store:RemoveRoot(rootKey)).to.equal(2)
			expect(store:GetCount()).to.equal(0)
			store:Destroy()
		end)

		it("builds deterministic tile trees with all segment roles", function()
			local definition = CropDefinitions.Get("ForestTree")
			local state = {
				cropId = "ForestTree",
				tileX = 10,
				tileY = 20,
				stage = 0,
			}
			local first = CropTreeBuilder.Generate(definition, state, 123456)
			local second = CropTreeBuilder.Generate(definition, state, 123456)
			local roles = {}
			for _, segment in first do
				roles[segment.segment] = true
			end

			expect(Table.deepEquivalent(first, second)).to.equal(true)
			expect(#first > 6).to.equal(true)
			expect(Table.count(roles) >= 2).to.equal(true)
			expect(roles[CropTypes.Segment.Trunk]).to.equal(true)
			expect(roles[CropTypes.Segment.Foliage]).to.equal(true)
		end)
	end)
end
