--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingButton = require(gameRoot.Shared.Features.crafting.ui.components.craftingButton)
local ImageIds = require(gameRoot.Client.UI.core.ImageIds)
local NavButton = require(gameRoot.Client.UI.core.components.NavButton)
local React = require(ReplicatedStorage.Packages.React)
local craftingSlice = require(gameRoot.Shared.Features.crafting.ui.state.craftingSlice)
local craftingThunks = require(gameRoot.Shared.Features.crafting.ui.state.craftingThunks)
local hudInventorySlice = require(gameRoot.Shared.Features.inventory.ui.hud.state.slice.inventorySlice)
local hudInventoryThunks = require(gameRoot.Shared.Features.inventory.ui.hud.state.slice.inventoryThunks)
local useStore = require(gameRoot.Client.UI.core.hooks.useStore)

type CraftingState = craftingSlice.CraftingState
type InventoryHudState = hudInventorySlice.InventoryHudState

type AttachedButtonProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
}

type ExpandInventoryButtonProps = AttachedButtonProps & {
	iconSize: UDim2?,
	iconColor3: Color3?,
	padding: UDim?,
	cornerRadius: UDim?,
	backgroundTransparency: number?,
	strokeTransparency: number?,
	isPressed: boolean?,
	onPressedChanged: ((boolean) -> ())?,
	onHoverChanged: ((boolean) -> ())?,
	onActivated: (() -> ())?,
}

local e: typeof(React.createElement) = React.createElement

local function ExpandInventoryButton(props: ExpandInventoryButtonProps): React.ReactNode
	local inventoryHudState = (useStore(hudInventorySlice.inventoryHudStateAtom) :: InventoryHudState?)
		or hudInventorySlice.getInventoryHudState()
	local isExpanded = inventoryHudState.isHotbarExpanded

	return e(NavButton, {
		id = "InventoryExpander",
		label = nil,
		icon = if props.isPressed == true or isExpanded
			then ImageIds.expandInventoryPressed
			else ImageIds.expandInventory,
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		iconSize = props.iconSize or props.size,
		iconColor3 = props.iconColor3,
		padding = props.padding,
		cornerRadius = props.cornerRadius,
		backgroundTransparency = props.backgroundTransparency,
		strokeTransparency = props.strokeTransparency,
		zIndex = props.zIndex,
		layoutOrder = props.layoutOrder,
		visible = props.visible,
		selected = isExpanded,
		onPressedChanged = props.onPressedChanged,
		onHoverChanged = props.onHoverChanged,
		onActivated = function()
			hudInventoryThunks.toggleInventory()
			if props.onActivated ~= nil then
				props.onActivated()
			end
		end,
	})
end

local function CraftingHudButton(props: AttachedButtonProps): React.ReactNode
	local craftingState = (useStore(craftingSlice.craftingStateAtom) :: CraftingState?)
		or craftingSlice.getCraftingState()

	React.useEffect(function()
		local stop = craftingThunks.start()

		return function()
			stop()
		end
	end, {})

	return e(CraftingButton, {
		layoutOrder = props.layoutOrder,
		visible = props.visible,
		zIndex = props.zIndex,
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		selected = craftingState.visible,
		onActivated = function()
			hudInventoryThunks.toggleCrafting()
		end,
	})
end

return {
	ExpandInventoryButton = ExpandInventoryButton,
	CraftingButton = CraftingHudButton,
}
