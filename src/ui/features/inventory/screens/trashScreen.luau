--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local itemThunks = require(ReplicatedStorage.UI.features.item.state.itemThunks)
local itemSlice = require(ReplicatedStorage.UI.features.item.state.itemSlice)
local infoThunks = require(ReplicatedStorage.UI.features.info.state.infoThunks)
local trashSlice = require(ReplicatedStorage.UI.features.inventory.state.trashSlice)
local trashThunks = require(ReplicatedStorage.UI.features.inventory.state.trashThunks)
local SoundServiceClient = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceClient)
local SoundServiceUtils = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceUtils)

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

local function resolveUiTrashSoundAssetId(soundName: string): string?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder == nil then
		return nil
	end

	local soundsFolder = assetsFolder:FindFirstChild("Sounds")
	if soundsFolder == nil then
		return nil
	end

	local uiFolder = soundsFolder:FindFirstChild("Ui")
	if uiFolder == nil then
		return nil
	end

	local sound = uiFolder:FindFirstChild(soundName)
	if sound ~= nil and sound:IsA("Sound") then
		return SoundServiceUtils.resolveSoundAssetId(sound)
	end
	return nil
end

local function playUiTrashSound(soundName: string)
	if SoundServiceClient.categoryGroups == nil then
		return
	end
	local soundAssetId = resolveUiTrashSoundAssetId(soundName)
	if soundAssetId == nil then
		return
	end
	SoundServiceClient:playUi(soundAssetId, {
		replaceChannel = false,
	})
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
	local state, setState = React.useState(function(): TrashState
		return trashSlice.getTrashState()
	end)
	local dragState, setDragState = React.useState(function(): ItemDragState
		return itemSlice.getDragState()
	end)

	React.useEffect(function()
		local stop = trashThunks.start()
		local unsubscribe = Charm.subscribe(trashSlice.trashStateAtom, function(nextState: TrashState)
			setState(nextState)
		end, {
			inclusive = true,
		})
		local unsubscribeDrag = Charm.subscribe(itemSlice.dragStateAtom, function(nextState: ItemDragState)
			setDragState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
			unsubscribeDrag()
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

	return e("ImageButton", {
		Name = "TrashScreen",
		Size = props.size or DEFAULT_SIZE,
		Position = applyOffset(props.position or UDim2.new(1, 0, 1, 0), emergeOffset),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 0),
		LayoutOrder = props.layoutOrder or 1,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = if state.isOpen then ImageIds.trashCanOpen else ImageIds.trashCanClosed,
		ImageColor3 = imageColor,
		ImageTransparency = emergeTransparency,
		ZIndex = zIndex,
		AutoButtonColor = false,
		Active = emergeTransparency < 0.98,
		Selectable = emergeTransparency < 0.98,
		[React.Event.MouseEnter] = function()
			trashThunks.open()
			infoThunks.showHover({
				id = TRASH_HOVER_ID,
				text = resolveHoverText(state, dragState),
			})
			playUiTrashSound("UiTrashOpen")
		end,
		[React.Event.MouseLeave] = function()
			trashThunks.close()
			infoThunks.hideHover(TRASH_HOVER_ID)
			playUiTrashSound("UiTrashClose")
		end,
		[React.Event.InputBegan] = function(_: GuiObject, inputObject: InputObject)
			local inputType = inputObject.UserInputType
			if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
				return
			end
			if not canTrashDragged then
				return
			end

			local didRequest = itemThunks.trashDrag(nil)
			if didRequest then
				playUiTrashSound("UiItemRelease")
				playUiTrashSound("UiTrashSound")
			end
		end,
		[React.Event.Activated] = function()
			if canTrashDragged then
				return
			end
			if not state.canTrash then
				return
			end

			local didRequest = trashThunks.trashSelected(nil)
			if didRequest then
				playUiTrashSound("UiTrashSound")
			end
		end,
	})
end
