--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioServiceUtils)
local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)
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
local UI_AUDIO = (AudioRegistry :: any).UI or {}
local UI_TRASH_OPEN_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.TrashCanOpen)
local UI_TRASH_CLOSE_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.TrashCanClose)
local UI_TRASH_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Trash)
local UI_ITEM_PUT_DOWN_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.ItemPutDown)

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
	if AudioServiceClient.categoryGroups == nil then
		return
	end
	if soundAssetId == nil then
		return
	end
	AudioServiceClient:playUi(soundAssetId, {
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
			playUiTrashSound(UI_TRASH_OPEN_SOUND)
		end,
		[React.Event.MouseLeave] = function()
			trashThunks.close()
			infoThunks.hideHover(TRASH_HOVER_ID)
			playUiTrashSound(UI_TRASH_CLOSE_SOUND)
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
				playUiTrashSound(UI_ITEM_PUT_DOWN_SOUND)
				playUiTrashSound(UI_TRASH_SOUND)
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
				playUiTrashSound(UI_TRASH_SOUND)
			end
		end,
	})
end
