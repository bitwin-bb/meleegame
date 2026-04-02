--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryProfile = require(ReplicatedStorage.Shared.Services.InventoryService.Profile)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)

local function createPlayer(): Player
	return {
		Name = "InventorySpec",
		UserId = 12345,
	} :: any
end

return function()
	describe("InventoryProfile", function()
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
