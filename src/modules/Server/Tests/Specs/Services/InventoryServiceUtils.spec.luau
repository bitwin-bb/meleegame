--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryService.InventoryServiceUtils)

return function()
	describe("InventoryServiceUtils", function()
		it("hydrates persisted data into the canonical state shape", function()
			local state = InventoryServiceUtils.createStateFromData({
				capacity = 72,
				selectedSlot = 2,
				slots = {
					{
						index = 2,
						itemId = "CopperPickaxe",
						stackId = "tool_pickaxe",
						amount = 1,
						maxStack = 1,
						metadata = { itemType = "pickaxe" },
					},
				},
			}, InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED), InventoryServiceUtils.LOAD_STATE_LOADED)

			expect(state.loadState).to.equal(InventoryServiceUtils.LOAD_STATE_LOADED)
			expect(state.selectedSlot).to.equal(2)
			expect(state.occupiedSlotCount).to.equal(1)
			expect(state.totalItemCount).to.equal(1)
			expect(InventoryServiceUtils.getStack(state, 2).itemId).to.equal("CopperPickaxe")
		end)

		it("moves partial stacks into empty slots deterministically", function()
			local state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.addItem(state, "Stone", 10, 99, nil, "test")

			local result = InventoryServiceUtils.moveSlot(state, 1, 3, 4)

			expect(result.changed).to.equal(true)
			expect(result.movedAmount).to.equal(4)
			expect(InventoryServiceUtils.getStack(state, 1).amount).to.equal(6)
			expect(InventoryServiceUtils.getStack(state, 3).amount).to.equal(4)
		end)

		it("splits stacks without mutating the selected slot contract", function()
			local state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.addItem(state, "Stone", 9, 99, nil, "test")
			InventoryServiceUtils.setSelectedSlot(state, 1)

			local result = InventoryServiceUtils.splitSlot(state, 1, 2, 3)

			expect(result.changed).to.equal(true)
			expect(state.selectedSlot).to.equal(1)
			expect(InventoryServiceUtils.getStack(state, 1).amount).to.equal(6)
			expect(InventoryServiceUtils.getStack(state, 2).amount).to.equal(3)
		end)

		it("trashes the selected slot through the same pure mutation path the UI uses", function()
			local state = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.addItem(state, "Stone", 5, 99, nil, "test")
			InventoryServiceUtils.setSelectedSlot(state, 1)

			local result = InventoryServiceUtils.trashSelected(state, 2)

			expect(result.changed).to.equal(true)
			expect(result.removedAmount).to.equal(2)
			expect(InventoryServiceUtils.getStack(state, 1).amount).to.equal(3)
		end)
	end)
end
