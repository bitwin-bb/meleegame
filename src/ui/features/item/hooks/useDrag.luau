--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local itemSlice = require(ReplicatedStorage.UI.features.item.state.itemSlice)
local itemThunks = require(ReplicatedStorage.UI.features.item.state.itemThunks)
local SoundServiceClient = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceClient)
local SoundServiceUtils = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceUtils)

type ItemDragState = itemSlice.ItemDragState

export type UseDragOptions = {
	hoveredSlotIndex: number?,
}

export type UseDragResult = {
	handleSlotInput: (slotIndexRaw: any, stackRaw: any, inputObjectRaw: any?) -> (),
	cancelDrag: () -> (),
	shouldSuppressActivation: (slotIndexRaw: any) -> boolean,
	isDragging: boolean,
	dragSourceSlot: number?,
}

type ActivationSuppression = {
	sourceSlot: number?,
	targetSlot: number?,
	untilTime: number,
}

type UiItemSoundCache = {
	pickup: string?,
	release: string?,
	resolved: boolean,
}

local ACTIVATION_SUPPRESSION_SECONDS = 0.2
local SLOT_CLICK_GRACE_SECONDS = 0.1
local POINTER_SMOOTHING_SPEED = 10
local MOUSE_CURSOR_CENTER_OFFSET = Vector2.new(0, -60)
local uiItemSoundCache: UiItemSoundCache = {
	pickup = nil,
	release = nil,
	resolved = false,
}

local function resolveUiItemSounds()
	if uiItemSoundCache.resolved then
		return
	end
	uiItemSoundCache.resolved = true

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder == nil then
		return
	end

	local soundsFolder = assetsFolder:FindFirstChild("Sounds")
	if soundsFolder == nil then
		return
	end

	local uiFolder = soundsFolder:FindFirstChild("Ui")
	if uiFolder == nil then
		return
	end

	local pickupSound = uiFolder:FindFirstChild("UiItemPickUp")
	if pickupSound ~= nil and pickupSound:IsA("Sound") then
		uiItemSoundCache.pickup = SoundServiceUtils.resolveSoundAssetId(pickupSound)
	end

	local releaseSound = uiFolder:FindFirstChild("UiItemRelease")
	if releaseSound ~= nil and releaseSound:IsA("Sound") then
		uiItemSoundCache.release = SoundServiceUtils.resolveSoundAssetId(releaseSound)
	end
end

local function playUiItemPickupSound()
	if SoundServiceClient.categoryGroups == nil then
		return
	end
	resolveUiItemSounds()
	if uiItemSoundCache.pickup == nil then
		return
	end
	SoundServiceClient:playUi(uiItemSoundCache.pickup, {
		replaceChannel = false,
	})
end

local function playUiItemReleaseSound()
	if SoundServiceClient.categoryGroups == nil then
		return
	end
	resolveUiItemSounds()
	if uiItemSoundCache.release == nil then
		return
	end
	SoundServiceClient:playUi(uiItemSoundCache.release, {
		replaceChannel = false,
	})
end

local function toGuiPosition(screenPosition: Vector2): Vector2
	local topLeftInset, _ = GuiService:GetGuiInset()
	return Vector2.new(math.max(0, screenPosition.X - topLeftInset.X), math.max(0, screenPosition.Y - topLeftInset.Y))
end

local function applyMouseCenterOffset(guiPosition: Vector2, inputType: Enum.UserInputType?): Vector2
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseMovement then
		return guiPosition + MOUSE_CURSOR_CENTER_OFFSET
	end
	return guiPosition
end

local function isDragInput(inputObject: InputObject): boolean
	return inputObject.UserInputType == Enum.UserInputType.MouseButton1
		or inputObject.UserInputType == Enum.UserInputType.Touch
end

local function resolvePointerPosition(inputObject: InputObject): Vector2
	local position = inputObject.Position
	local screenPosition = Vector2.new(position.X, position.Y)
	local guiPosition = toGuiPosition(screenPosition)
	return applyMouseCenterOffset(guiPosition, inputObject.UserInputType)
end

local function resolveCurrentMousePosition(): Vector2
	local mousePosition = UserInputService:GetMouseLocation()
	local guiPosition = toGuiPosition(Vector2.new(mousePosition.X, mousePosition.Y))
	return guiPosition + MOUSE_CURSOR_CENTER_OFFSET
end

local function sanitizeSlot(slotRaw: any): number?
	if typeof(slotRaw) ~= "number" or slotRaw ~= slotRaw then
		return nil
	end

	local slot = math.floor(slotRaw)
	if slot <= 0 then
		return nil
	end
	return slot
end

local function shouldSuppressActivationNow(suppression: ActivationSuppression, slotRaw: any): boolean
	local slot = sanitizeSlot(slotRaw)
	if slot == nil then
		return false
	end
	if os.clock() > suppression.untilTime then
		return false
	end
	return slot == suppression.sourceSlot or slot == suppression.targetSlot
end

local function setActivationSuppression(suppressionRef: any, sourceSlot: number?, targetSlot: number?)
	suppressionRef.current = {
		sourceSlot = sourceSlot,
		targetSlot = targetSlot,
		untilTime = os.clock() + ACTIVATION_SUPPRESSION_SECONDS,
	}
end

local function finalizeDragWithSuppression(suppressionRef: any, targetSlotRaw: any): boolean
	local state = itemSlice.getDragState()
	if not state.active then
		return false
	end

	local sourceSlot = state.sourceSlot
	local targetSlot = sanitizeSlot(targetSlotRaw)
	local didMove = itemThunks.endDrag(targetSlot)
	playUiItemReleaseSound()
	setActivationSuppression(suppressionRef, sourceSlot, targetSlot)
	return didMove
end

local function syncPointerRefs(
	targetPointerRef: any,
	smoothedPointerRef: any,
	hasSmoothedPointerRef: any,
	pointerPosition: Vector2
)
	targetPointerRef.current = pointerPosition
	smoothedPointerRef.current = pointerPosition
	hasSmoothedPointerRef.current = true
end

local function resolvePointerFromInput(inputObjectRaw: any): Vector2
	if typeof(inputObjectRaw) == "InputObject" then
		return resolvePointerPosition(inputObjectRaw :: InputObject)
	end
	if typeof(inputObjectRaw) == "Vector2" then
		return inputObjectRaw
	end
	return resolveCurrentMousePosition()
end

local function useDrag(options: UseDragOptions?): UseDragResult
	local hoveredSlotIndex = if options ~= nil then options.hoveredSlotIndex else nil
	local dragState, setDragState = React.useState(function(): ItemDragState
		return itemSlice.getDragState()
	end)
	local lastSlotInputTimeRef = React.useRef(0)
	local targetPointerRef = React.useRef(Vector2.zero)
	local smoothedPointerRef = React.useRef(Vector2.zero)
	local hasSmoothedPointerRef = React.useRef(false)
	local suppressionRef = React.useRef({
		sourceSlot = nil,
		targetSlot = nil,
		untilTime = 0,
	} :: ActivationSuppression)

	React.useEffect(function()
		local unsubscribe = Charm.subscribe(itemSlice.dragStateAtom, function(nextState: ItemDragState)
			setDragState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
		end
	end, {})

	React.useEffect(function()
		if dragState.active then
			itemThunks.setHoveredSlot(hoveredSlotIndex)
		end
	end, { hoveredSlotIndex, dragState.active })

	React.useEffect(function()
		local changedConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			if inputObject.UserInputType == Enum.UserInputType.Touch and itemSlice.getDragState().active then
				local pointerPosition = resolvePointerPosition(inputObject)
				targetPointerRef.current = pointerPosition
			end
		end)

		local renderConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local state = itemSlice.getDragState()
			if not state.active then
				hasSmoothedPointerRef.current = false
				return
			end

			local targetPointer = targetPointerRef.current
			if UserInputService.MouseEnabled then
				targetPointer = resolveCurrentMousePosition()
				targetPointerRef.current = targetPointer
			end

			if not hasSmoothedPointerRef.current then
				smoothedPointerRef.current = targetPointer
				hasSmoothedPointerRef.current = true
			else
				local alpha = 1 - math.exp(-POINTER_SMOOTHING_SPEED * math.max(deltaTime, 0))
				alpha = math.clamp(alpha, 0, 1)
				smoothedPointerRef.current = smoothedPointerRef.current:Lerp(targetPointer, alpha)
			end

			itemThunks.updatePointer(smoothedPointerRef.current)
		end)

		local beganConnection = UserInputService.InputBegan:Connect(function(inputObject: InputObject, _: boolean)
			local state = itemSlice.getDragState()
			if not state.active then
				return
			end
			local inputType = inputObject.UserInputType

			if inputType == Enum.UserInputType.MouseButton2 then
				if state.hoveredSlot == nil then
					local sourceSlot = state.sourceSlot
					local didDrop = itemThunks.dropDrag(nil)
					if didDrop then
						playUiItemReleaseSound()
						setActivationSuppression(suppressionRef, sourceSlot, nil)
					end
				end
				return
			end

			if not isDragInput(inputObject) then
				return
			end

			task.defer(function()
				local nextState = itemSlice.getDragState()
				if not nextState.active then
					return
				end
				if os.clock() - lastSlotInputTimeRef.current <= SLOT_CLICK_GRACE_SECONDS then
					return
				end
				finalizeDragWithSuppression(suppressionRef, nil)
			end)
		end)

		return function()
			changedConnection:Disconnect()
			renderConnection:Disconnect()
			beganConnection:Disconnect()
			itemThunks.cancelDrag()
		end
	end, {})

	local handleSlotInput = React.useCallback(function(slotIndexRaw: any, stackRaw: any, inputObjectRaw: any?)
		local slotIndex = sanitizeSlot(slotIndexRaw)
		if slotIndex == nil then
			return
		end

		lastSlotInputTimeRef.current = os.clock()
		local pointerPosition = resolvePointerFromInput(inputObjectRaw)
		local state = itemSlice.getDragState()

		if state.active then
			syncPointerRefs(targetPointerRef, smoothedPointerRef, hasSmoothedPointerRef, pointerPosition)
			itemThunks.updatePointer(pointerPosition)
			finalizeDragWithSuppression(suppressionRef, slotIndex)
			return
		end

		if typeof(stackRaw) ~= "table" then
			return
		end

		syncPointerRefs(targetPointerRef, smoothedPointerRef, hasSmoothedPointerRef, pointerPosition)
		local nextDragState = itemThunks.beginDrag(slotIndex, stackRaw, pointerPosition)
		if nextDragState.active then
			playUiItemPickupSound()
		end
		itemThunks.setHoveredSlot(slotIndex)
		setActivationSuppression(suppressionRef, slotIndex, slotIndex)
	end, {})

	local cancelDrag = React.useCallback(function()
		itemThunks.cancelDrag()
	end, {})

	local shouldSuppressActivation = React.useCallback(function(slotIndexRaw: any): boolean
		return shouldSuppressActivationNow(suppressionRef.current, slotIndexRaw)
	end, {})

	return {
		handleSlotInput = handleSlotInput,
		cancelDrag = cancelDrag,
		shouldSuppressActivation = shouldSuppressActivation,
		isDragging = dragState.active,
		dragSourceSlot = dragState.sourceSlot,
	}
end

return useDrag
