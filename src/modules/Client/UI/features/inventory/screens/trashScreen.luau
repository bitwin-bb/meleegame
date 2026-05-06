--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local TrashButton = require(script:FindFirstAncestor("game").Client.UI.features.inventory.components.TrashButton)
local UiSound = require(script:FindFirstAncestor("game").Client.UI.core.utils.UiSound)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local itemSlice = require(script:FindFirstAncestor("game").Client.UI.features.item.state.itemSlice)
local itemThunks = require(script:FindFirstAncestor("game").Client.UI.features.item.state.itemThunks)
local trashSlice = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.trashSlice)
local trashThunks = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.trashThunks)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type TrashState = trashSlice.TrashState
type ItemDragState = itemSlice.ItemDragState

type TrashScreenProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	size: UDim2?,
	emergeOffset: Vector2?,
	emergeTransparency: number?,
}

local e: typeof(React.createElement) = React.createElement

local TRASH_HOVER_ID = "inventory_trash"
local DEFAULT_SIZE = UDim2.fromOffset(58, 58)

local function resolveEmergeOffset(offsetRaw: any): Vector2
	if typeof(offsetRaw) ~= "Vector2" then
		return Vector2.zero
	end
	if offsetRaw.X ~= offsetRaw.X or offsetRaw.Y ~= offsetRaw.Y then
		return Vector2.zero
	end
	return offsetRaw
end

local function resolveTransparency(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.clamp(valueRaw, 0, 1)
end

local function applyOffset(base: UDim2, offset: Vector2): UDim2
	return UDim2.new(base.X.Scale, base.X.Offset + offset.X, base.Y.Scale, base.Y.Offset + offset.Y)
end

local function playUiTrashSound(soundAssetId: string?)
	UiSound.play(soundAssetId)
end

local function resolveHoverText(state: TrashState, dragState: ItemDragState): string
	if dragState.active and dragState.stack ~= nil then
		local slotIndex = if typeof(dragState.sourceSlot) == "number" then dragState.sourceSlot else 0
		return ("Trash\n\nDrop to destroy:\n%s"):format(itemThunks.resolveHoverTextForStack(dragState.stack, slotIndex))
	end

	if not state.canTrash or state.selectedStack == nil or state.selectedSlot == nil then
		return "Trash\n\nSelect an inventory slot to trash items."
	end

	return ("Trash\n\n%s"):format(itemThunks.resolveHoverTextForStack(state.selectedStack, state.selectedSlot))
end

return function(props: TrashScreenProps): React.ReactNode
	local state = (useStore(trashSlice.trashStateAtom) :: TrashState?) or trashSlice.getTrashState()
	local dragState = (useStore(itemSlice.dragStateAtom) :: ItemDragState?) or itemSlice.getDragState()

	React.useEffect(function()
		local stop = trashThunks.start()

		return function()
			stop()
			infoThunks.hideHover(TRASH_HOVER_ID)
		end
	end, {})

	React.useEffect(function()
		if not state.isHovered then
			return
		end
		infoThunks.showHover({
			id = TRASH_HOVER_ID,
			text = resolveHoverText(state, dragState),
		})
	end, { state.updatedAt, state.isHovered, dragState.updatedAt, dragState.active })

	if props.visible == false then
		return nil
	end

	local zIndex = props.zIndex or 60
	local emergeOffset = resolveEmergeOffset(props.emergeOffset)
	local emergeTransparency = resolveTransparency(props.emergeTransparency)
	local canTrashDragged = dragState.active and dragState.stack ~= nil and dragState.sourceSlot ~= nil
	local canInteract = canTrashDragged or state.canTrash
	local isBrightHover = state.isHovered and canTrashDragged
	local imageColor = if isBrightHover
		then Color3.fromRGB(255, 255, 255)
		else if canInteract then Color3.fromRGB(222, 222, 222) else Color3.fromRGB(180, 180, 180)

	return e(TrashButton, {
		size = props.size or DEFAULT_SIZE,
		position = applyOffset(props.position or UDim2.fromScale(1, 1), emergeOffset),
		anchorPoint = props.anchorPoint or Vector2.new(1, 0),
		layoutOrder = props.layoutOrder or 1,
		zIndex = zIndex,
		isOpen = state.isOpen,
		imageColor3 = imageColor,
		imageTransparency = emergeTransparency,
		active = emergeTransparency < 0.98,
		selectable = emergeTransparency < 0.98,
		onMouseEnter = function()
			trashThunks.open()
			infoThunks.showHover({
				id = TRASH_HOVER_ID,
				text = resolveHoverText(state, dragState),
			})
			playUiTrashSound((UiSound :: any).trashCanOpen)
		end,
		onMouseLeave = function()
			trashThunks.close()
			infoThunks.hideHover(TRASH_HOVER_ID)
			playUiTrashSound((UiSound :: any).trashCanClose)
		end,
		onInputBegan = function(_: GuiObject, inputObject: InputObject)
			local inputType = inputObject.UserInputType
			if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
				return
			end
			if not canTrashDragged then
				return
			end

			local didRequest = itemThunks.trashDrag(nil)
			if didRequest then
				playUiTrashSound((UiSound :: any).itemPutDown)
				playUiTrashSound(UiSound.trash)
			end
		end,
		onActivated = function()
			if canTrashDragged then
				return
			end
			if not state.canTrash then
				return
			end

			local didRequest = trashThunks.trashSelected(nil)
			if didRequest then
				playUiTrashSound(UiSound.trash)
			end
		end,
	})
end
