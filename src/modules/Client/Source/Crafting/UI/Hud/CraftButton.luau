local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local CraftingButton = require("CraftingButton")
local React: any = require(ReplicatedStorage.Packages.React)
local UiSound = require("UISound")
local craftingSlice = require("CraftingSlice")
local craftingThunks = require("CraftingThunks")
local useStore = require("useCoreStore")

type CraftingState = craftingSlice.CraftingState

type CraftButtonProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: CraftButtonProps): React.ReactNode
	local craftingState = (useStore(craftingSlice.craftingStateAtom) :: CraftingState?)
		or craftingSlice.getCraftingState()

	React.useEffect(function()
		local stop = craftingThunks.Start()

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
			craftingThunks.ToggleVisible()
		end,
	})
end
