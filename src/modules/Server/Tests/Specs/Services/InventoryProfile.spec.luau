local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local InventoryProfile = require("Profile")
local InventoryServiceUtils = require("InventoryServiceUtils")

local function createPlayer(): Player
	return {
		Name = "InventorySpec",
		UserId = 12345,
	} :: any
end

return function()
	describe("InventoryProfile", function()
		it("seeds new profiles with copper starter tools in the first three hotbar slots", function()
			local adapter = InventoryProfile.new(nil :: any)

			local defaultInventory = adapter:cloneDefaultInventoryData()

			expect(defaultInventory.selectedSlot).to.equal(nil)
			expect(defaultInventory.slots[1].index).to.equal(1)
			expect(defaultInventory.slots[1].itemId).to.equal("CopperBroadSword")
			expect(defaultInventory.slots[1].amount).to.equal(1)
			expect(defaultInventory.slots[1].maxStack).to.equal(1)
			expect(defaultInventory.slots[2].index).to.equal(2)
			expect(defaultInventory.slots[2].itemId).to.equal("CopperPickaxe")
			expect(defaultInventory.slots[2].amount).to.equal(1)
			expect(defaultInventory.slots[2].maxStack).to.equal(1)
			expect(defaultInventory.slots[3].index).to.equal(3)
			expect(defaultInventory.slots[3].itemId).to.equal("CopperAxe")
			expect(defaultInventory.slots[3].amount).to.equal(1)
			expect(defaultInventory.slots[3].maxStack).to.equal(1)
		end)

		it("writes loaded inventory state back into the live profile data path without saving immediately", function()
			local saveCalls = 0
			local profile = {
				Data = {
					inventory = {
						capacity = 40,
						selectedSlot = nil,
						slots = {},
					},
				},
			}
			local playerDataService = {
				getProfile = function(_self: any, _player: Player)
					return profile
				end,
				savePlayerData = function(_self: any, _player: Player)
					saveCalls += 1
					return true
				end,
			}

			local adapter = InventoryProfile.new(playerDataService :: any)
			local state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.addItem(state, "Stone", 3, 99, nil, "spec")
			InventoryServiceUtils.setSelectedSlot(state, 1)

			local didWrite, writeReason = adapter:writeState(createPlayer(), state)

			expect(didWrite).to.equal(true)
			expect(writeReason).to.equal("written:inventory")
			expect(saveCalls).to.equal(0)
			expect(profile.Data.inventory.selectedSlot).to.equal(1)
			expect(profile.Data.inventory.slots[1].itemId).to.equal("Stone")
			expect(profile.Data.inventory.slots[1].amount).to.equal(3)
		end)

		it("saves through the same live profile path after writing the serialized inventory snapshot", function()
			local saveCalls = 0
			local profile = {
				Data = {
					inventory = {
						capacity = 40,
						selectedSlot = nil,
						slots = {},
					},
				},
			}
			local playerDataService = {
				getProfile = function(_self: any, _player: Player)
					return profile
				end,
				savePlayerData = function(_self: any, _player: Player)
					saveCalls += 1
					return true
				end,
			}

			local adapter = InventoryProfile.new(playerDataService :: any)
			local state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.addItem(state, "CopperOre", 2, 99, nil, "spec")

			local didSave, saveReason = adapter:saveState(createPlayer(), state)

			expect(didSave).to.equal(true)
			expect(saveReason).to.equal("saved:inventory")
			expect(saveCalls).to.equal(1)
			expect(profile.Data.inventory.slots[1].itemId).to.equal("CopperOre")
			expect(profile.Data.inventory.slots[1].amount).to.equal(2)
		end)

		it("refuses to touch the profile for unloaded inventory states", function()
			local didLookupProfile = false
			local playerDataService = {
				getProfile = function(_self: any, _player: Player)
					didLookupProfile = true
					return {
						Data = {},
					}
				end,
				savePlayerData = function(_self: any, _player: Player)
					return true
				end,
			}

			local adapter = InventoryProfile.new(playerDataService :: any)
			local state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADING)

			local didSave, saveReason = adapter:saveState(createPlayer(), state)

			expect(didSave).to.equal(false)
			expect(saveReason).to.equal("state_not_loaded")
			expect(didLookupProfile).to.equal(false)
		end)
	end)
end
