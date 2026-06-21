local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingButton = require("craftingButton")
local ImageIds = require("ImageIds")
local NavButton = require("NavButton")
local React = require(ReplicatedStorage.Packages.React)
local UiSound = require("UiSound")
local craftingSlice = require("craftingSlice")
local craftingThunks = require("craftingThunks")
local hudInventorySlice = require("inventorySlice")
local hudInventoryThunks = require("inventoryThunks")
local useStore = require("useCoreStore")

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
		onHoverChanged = function(isHovered: boolean)
			if isHovered then
				UiSound.playHover()
			end
		end,
		onActivated = function()
			UiSound.playPress()
			hudInventoryThunks.toggleCrafting()
		end,
	})
end

return {
	ExpandInventoryButton = ExpandInventoryButton,
	CraftingButton = CraftingHudButton,
}
