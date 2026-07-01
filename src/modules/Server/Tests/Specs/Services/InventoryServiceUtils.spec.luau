local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local InventoryServiceUtils = require("InventoryServiceUtils")
local ItemIcons = require("ItemIcons")
local itemThunks = require("itemThunks")

return function()
	describe("InventoryServiceUtils", function()
		it("hydrates persisted data into the canonical state shape", function()
			local state = InventoryServiceUtils.CreateStateFromData(
				{
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
				},
				InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_UNLOADED),
				InventoryServiceUtils.LOAD_STATE_LOADED
			)

			expect(state.loadState).to.equal(InventoryServiceUtils.LOAD_STATE_LOADED)
			expect(state.selectedSlot).to.equal(2)
			expect(state.occupiedSlotCount).to.equal(1)
			expect(state.totalItemCount).to.equal(1)
			expect((InventoryServiceUtils.GetStack(state, 2) :: any).itemId).to.equal("CopperPickaxe")
		end)

		it("moves partial stacks into empty slots deterministically", function()
			local state = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.AddItem(state, "Stone", 10, 99, nil, "test")

			local result = InventoryServiceUtils.MoveSlot(state, 1, 3, 4)

			expect(result.changed).to.equal(true)
			expect(result.movedAmount).to.equal(4)
			expect((InventoryServiceUtils.GetStack(state, 1) :: any).amount).to.equal(6)
			expect((InventoryServiceUtils.GetStack(state, 3) :: any).amount).to.equal(4)
		end)

		it("splits stacks without mutating the selected slot contract", function()
			local state = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.AddItem(state, "Stone", 9, 99, nil, "test")
			InventoryServiceUtils.SetSelectedSlot(state, 1)

			local result = InventoryServiceUtils.SplitSlot(state, 1, 2, 3)

			expect(result.changed).to.equal(true)
			expect(state.selectedSlot).to.equal(1)
			expect((InventoryServiceUtils.GetStack(state, 1) :: any).amount).to.equal(6)
			expect((InventoryServiceUtils.GetStack(state, 2) :: any).amount).to.equal(3)
		end)

		it("trashes the selected slot through the same pure mutation path the UI uses", function()
			local state = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.AddItem(state, "Stone", 5, 99, nil, "test")
			InventoryServiceUtils.SetSelectedSlot(state, 1)

			local result = InventoryServiceUtils.TrashSelected(state, 2)

			expect(result.changed).to.equal(true)
			expect(result.removedAmount).to.equal(2)
			expect((InventoryServiceUtils.GetStack(state, 1) :: any).amount).to.equal(3)
		end)

		it("seeds starter tools into empty join slots without replacing occupied slots", function()
			local state = InventoryServiceUtils.CreateDefaultState(InventoryServiceUtils.LOAD_STATE_LOADED)
			InventoryServiceUtils.AddItem(state, "Stone", 8, 99, nil, "test")
			InventoryServiceUtils.MoveSlot(state, 1, 2, nil)

			local changed = InventoryServiceUtils.ApplyStarterSlots(state)

			expect(changed).to.equal(true)
			expect((InventoryServiceUtils.GetStack(state, 1) :: any).itemId).to.equal("CopperBroadSword")
			expect((InventoryServiceUtils.GetStack(state, 1) :: any).amount).to.equal(1)
			expect((InventoryServiceUtils.GetStack(state, 2) :: any).itemId).to.equal("Stone")
			expect((InventoryServiceUtils.GetStack(state, 3) :: any).itemId).to.equal("CopperAxe")
			expect(state.occupiedSlotCount).to.equal(3)
			expect(state.totalItemCount).to.equal(10)
		end)

		it("exposes inventory-owned item icon assets", function()
			expect(ItemIcons.default).to.equal("rbxassetid://105837137977667")
			expect(ItemIcons.copperPickaxe).to.equal("rbxassetid://135500881364781")
			expect(ItemIcons.copperOre).to.equal("rbxassetid://86523519459129")
			expect(ItemIcons.torch).to.equal("rbxassetid://117501832045596")
		end)

		it("builds item hover text without blank spacer rows", function()
			local hoverText = itemThunks.GetHoverTextForStack({
				stackId = "copper_ore_stack",
				itemId = "CopperOre",
				amount = 20,
				maxStack = 99,
				metadata = {},
			}, 1)

			expect(string.find(hoverText, "\n\n", 1, true)).to.equal(nil)
			expect(hoverText).to.equal(
				"Copper Ore\nAmount: 20\nA chunk of copper-bearing stone ready to be smelted or crafted with."
			)
		end)
	end)
end
