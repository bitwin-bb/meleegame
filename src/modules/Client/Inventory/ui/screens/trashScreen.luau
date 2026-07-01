local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local React = require(ReplicatedStorage.Packages.React)
local TrashButton = require("TrashButton")
local UiSound = require("UiSound")
local infoThunks = require("infoThunks")
local itemSlice = require("itemSlice")
local itemThunks = require("itemThunks")
local trashSlice = require("trashSlice")
local trashThunks = require("trashThunks")
local useStore = require("useCoreStore")

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

local function GetEmergeOffset(offsetRaw: any): Vector2
	if typeof(offsetRaw) ~= "Vector2" then
		return Vector2.zero
	end
	if offsetRaw.X ~= offsetRaw.X or offsetRaw.Y ~= offsetRaw.Y then
		return Vector2.zero
	end
	return offsetRaw
end

local function GetTransparency(valueRaw: any): number
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

local function GetHoverText(state: TrashState, dragState: ItemDragState): string
	if dragState.active and dragState.stack ~= nil then
		local slotIndex = if typeof(dragState.sourceSlot) == "number" then dragState.sourceSlot else 0
		return ("Trash\nDrop to destroy:\n%s"):format(itemThunks.GetHoverTextForStack(dragState.stack, slotIndex))
	end

	if not state.canTrash or state.selectedStack == nil or state.selectedSlot == nil then
		return "Trash\nSelect an inventory slot to trash items."
	end

	return ("Trash\n%s"):format(itemThunks.GetHoverTextForStack(state.selectedStack, state.selectedSlot))
end

return function(props: TrashScreenProps): React.ReactNode
	local state = (useStore(trashSlice.trashStateAtom) :: TrashState?) or trashSlice.getTrashState()
	local dragState = (useStore(itemSlice.dragStateAtom) :: ItemDragState?) or itemSlice.getDragState()

	React.useEffect(function()
		local stop = trashThunks.Start()

		return function()
			stop()
			infoThunks.HideHover(TRASH_HOVER_ID)
		end
	end, {})

	React.useEffect(function()
		if not state.isHovered then
			return
		end
		infoThunks.ShowHover({
			id = TRASH_HOVER_ID,
			text = GetHoverText(state, dragState),
		})
	end, { state.updatedAt, state.isHovered, dragState.updatedAt, dragState.active } :: { any })

	if props.visible == false then
		return nil
	end

	local zIndex = props.zIndex or 60
	local emergeOffset = GetEmergeOffset(props.emergeOffset)
	local emergeTransparency = GetTransparency(props.emergeTransparency)
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
			trashThunks.Open()
			infoThunks.ShowHover({
				id = TRASH_HOVER_ID,
				text = GetHoverText(state, dragState),
			})
			playUiTrashSound((UiSound :: any).trashCanOpen)
		end,
		onMouseLeave = function()
			trashThunks.Close()
			infoThunks.HideHover(TRASH_HOVER_ID)
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

			local didRequest = itemThunks.TrashDrag(nil)
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

			local didRequest = trashThunks.TrashSelected(nil)
			if didRequest then
				playUiTrashSound(UiSound.trash)
			end
		end,
	})
end
