--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)
local Damp = require(ReplicatedStorage.Shared.Modules.Math.Damp)
local AudioRegistry = require(ReplicatedStorage.Shared.Modules.Items.Audio)
local BuildServiceUtils = require(ReplicatedStorage.Shared.Services.BuildService.BuildServiceUtils)
local itemSlice = require(ReplicatedStorage.UI.features.item.state.itemSlice)
local itemThunks = require(ReplicatedStorage.UI.features.item.state.itemThunks)
local inventoryThunks = require(ReplicatedStorage.UI.features.inventory.state.inventoryThunks)
local AudioServiceClient = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceClient)
local AudioServiceUtils = require(ReplicatedStorage.Shared.Services.AudioService.AudioServiceUtils)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)

type ItemDragState = itemSlice.ItemDragState
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack

export type UseDragOptions = {
	hoveredSlotIndex: number?,
}

export type UseDragResult = {
	handleSlotInput: (slotIndexRaw: any, stackRaw: any, inputObjectRaw: any?) -> (),
	handleSlotSecondaryInput: (slotIndexRaw: any, stackRaw: any, pointerPositionRaw: any?) -> (),
	cancelDrag: () -> (),
	shouldSuppressActivation: (slotIndexRaw: any) -> boolean,
	isDragging: boolean,
	dragSourceSlot: number?,
	dragState: ItemDragState,
}

type ActivationSuppression = {
	sourceSlot: number?,
	targetSlot: number?,
	untilTime: number,
}

type PendingSplitHold = {
	slotIndex: number,
	stack: InventoryItemStack,
	startedAt: number,
	nextIncrementAt: number,
	canSplit: boolean,
}

type SplitHoldConfig = {
	enabled: boolean,
	holdDelaySeconds: number,
	initialIntervalSeconds: number,
	minimumIntervalSeconds: number,
	accelerationRampSeconds: number,
}

local ACTIVATION_SUPPRESSION_SECONDS = 0.2
local SLOT_CLICK_GRACE_SECONDS = 0.1
local POINTER_SMOOTHING_SPEED = 10
local MOUSE_CURSOR_CENTER_OFFSET = Vector2.zero
local DEFAULT_SPLIT_HOLD_CONFIG: SplitHoldConfig = {
	enabled = true,
	holdDelaySeconds = 0.18,
	initialIntervalSeconds = 0.18,
	minimumIntervalSeconds = 0.035,
	accelerationRampSeconds = 1.1,
}
local UI_AUDIO = (AudioRegistry :: any).UI or {}
local UI_ITEM_PICKUP_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.ItemPickup)
local UI_ITEM_PUT_DOWN_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.ItemPutDown)

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number, maximum: number?): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end

	local value = valueRaw
	if value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function resolveSplitHoldConfig(configRaw: any): SplitHoldConfig
	local inventoryConfig = if typeof(configRaw) == "table" then (configRaw :: any).inventory else nil
	local splitConfig = if typeof(inventoryConfig) == "table" then (inventoryConfig :: any).rightHoldSplit else nil
	if typeof(splitConfig) ~= "table" then
		return DEFAULT_SPLIT_HOLD_CONFIG
	end

	return {
		enabled = (splitConfig :: any).enabled ~= false,
		holdDelaySeconds = sanitizeNumber(
			(splitConfig :: any).holdDelaySeconds,
			DEFAULT_SPLIT_HOLD_CONFIG.holdDelaySeconds,
			0.05,
			1
		),
		initialIntervalSeconds = sanitizeNumber(
			(splitConfig :: any).initialIntervalSeconds,
			DEFAULT_SPLIT_HOLD_CONFIG.initialIntervalSeconds,
			0.02,
			0.5
		),
		minimumIntervalSeconds = sanitizeNumber(
			(splitConfig :: any).minimumIntervalSeconds,
			DEFAULT_SPLIT_HOLD_CONFIG.minimumIntervalSeconds,
			0.01,
			0.2
		),
		accelerationRampSeconds = sanitizeNumber(
			(splitConfig :: any).accelerationRampSeconds,
			DEFAULT_SPLIT_HOLD_CONFIG.accelerationRampSeconds,
			0.1,
			4
		),
	}
end

local SPLIT_HOLD_CONFIG = resolveSplitHoldConfig(Configs)

local function playUiItemPickupSound()
	if AudioServiceClient.categoryGroups == nil then
		return
	end
	if UI_ITEM_PICKUP_SOUND == nil then
		return
	end
	AudioServiceClient:playUi(UI_ITEM_PICKUP_SOUND, {
		replaceChannel = false,
	})
end

local function playUiItemReleaseSound()
	if AudioServiceClient.categoryGroups == nil then
		return
	end
	if UI_ITEM_PUT_DOWN_SOUND == nil then
		return
	end
	AudioServiceClient:playUi(UI_ITEM_PUT_DOWN_SOUND, {
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

local function cloneStack(stackRaw: any): InventoryItemStack?
	if typeof(stackRaw) ~= "table" then
		return nil
	end

	local stack = stackRaw :: { [string]: any }
	if typeof(stack.stackId) ~= "string" or typeof(stack.itemId) ~= "string" then
		return nil
	end

	local amountRaw = stack.amount
	local amount = if typeof(amountRaw) == "number" and amountRaw == amountRaw then math.max(0, math.floor(amountRaw)) else 0
	local maxStackRaw = stack.maxStack
	local maxStack = if typeof(maxStackRaw) == "number" and maxStackRaw == maxStackRaw
		then math.max(1, math.floor(maxStackRaw))
		else 1
	if amount <= 0 then
		return nil
	end

	return {
		stackId = stack.stackId,
		itemId = stack.itemId,
		amount = amount,
		maxStack = maxStack,
		metadata = InventoryServiceUtils.cloneDeep(stack.metadata),
	}
end

local function isSplitHoldDrag(state: ItemDragState): boolean
	return state.active and state.mode == "SplitHold" and state.stack ~= nil and state.sourceSlot ~= nil
end

local function isPlaceableDragOutsideInventory(state: ItemDragState): boolean
	if not state.active or state.hoveredSlot ~= nil or state.stack == nil then
		return false
	end

	return BuildServiceUtils.resolvePlaceableItemConfig(state.stack.itemId) ~= nil
end

local function resolveSplitIncrementInterval(elapsedSeconds: number): number
	local rampSeconds = math.max(SPLIT_HOLD_CONFIG.accelerationRampSeconds, 1e-4)
	local alpha = math.clamp(elapsedSeconds / rampSeconds, 0, 1)
	local easedAlpha = alpha * alpha
	return SPLIT_HOLD_CONFIG.initialIntervalSeconds
		+ (SPLIT_HOLD_CONFIG.minimumIntervalSeconds - SPLIT_HOLD_CONFIG.initialIntervalSeconds) * easedAlpha
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
	local hoveredSlotIndexRef = React.useRef(hoveredSlotIndex)
	local pendingSplitHoldRef = React.useRef(nil :: PendingSplitHold?)
	local suppressionRef = React.useRef({
		sourceSlot = nil,
		targetSlot = nil,
		untilTime = 0,
	} :: ActivationSuppression)

	local function clearPendingSplitHold()
		pendingSplitHoldRef.current = nil
	end

	local function beginPendingSplitHold(slotIndex: number, stackRaw: any, pointerPosition: Vector2)
		local stack = cloneStack(stackRaw)
		if stack == nil then
			return false
		end

		local nextDragState = itemThunks.beginSplitDrag(slotIndex, stack, pointerPosition, 1)
		if not nextDragState.active then
			return false
		end

		itemThunks.setHoveredSlot(slotIndex)
		setActivationSuppression(suppressionRef, slotIndex, slotIndex)
		playUiItemPickupSound()

		pendingSplitHoldRef.current = {
			slotIndex = slotIndex,
			stack = stack,
			startedAt = os.clock(),
			nextIncrementAt = os.clock() + SPLIT_HOLD_CONFIG.holdDelaySeconds,
			canSplit = SPLIT_HOLD_CONFIG.enabled and stack.amount > 1,
		}
		return true
	end

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
		hoveredSlotIndexRef.current = hoveredSlotIndex
	end, { hoveredSlotIndex })

	React.useEffect(function()
		if dragState.active then
			itemThunks.setHoveredSlot(hoveredSlotIndex)
		end
	end, { hoveredSlotIndex, dragState.active })

	React.useEffect(function()
		local changedConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			local pendingSplitHold = pendingSplitHoldRef.current
			if inputObject.UserInputType == Enum.UserInputType.Touch then
				if itemSlice.getDragState().active or pendingSplitHold ~= nil then
					local pointerPosition = resolvePointerPosition(inputObject)
					targetPointerRef.current = pointerPosition
				end
			end
		end)

		local renderConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local currentDragState = itemSlice.getDragState()
			local pendingSplitHold = pendingSplitHoldRef.current
			if not currentDragState.active and pendingSplitHold == nil then
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
				local alpha = Damp.factor(POINTER_SMOOTHING_SPEED, deltaTime)
				smoothedPointerRef.current = smoothedPointerRef.current:Lerp(targetPointer, alpha)
			end

			local now = os.clock()
			currentDragState = itemSlice.getDragState()
			if currentDragState.active then
				itemThunks.updatePointer(smoothedPointerRef.current)
			end

			pendingSplitHold = pendingSplitHoldRef.current
			if pendingSplitHold ~= nil then
				local activeSplitDrag = itemSlice.getDragState()
				if not isSplitHoldDrag(activeSplitDrag) or activeSplitDrag.sourceSlot ~= pendingSplitHold.slotIndex then
					clearPendingSplitHold()
					return
				end

				local stack = activeSplitDrag.stack
				if stack == nil then
					clearPendingSplitHold()
					return
				end

				local nextAmount = stack.amount
				local nextIncrementAt = pendingSplitHold.nextIncrementAt
				while nextAmount < pendingSplitHold.stack.amount and now >= nextIncrementAt do
					nextAmount += 1
					nextIncrementAt += resolveSplitIncrementInterval(nextIncrementAt - pendingSplitHold.startedAt)
				end

				pendingSplitHold.nextIncrementAt = nextIncrementAt
				pendingSplitHoldRef.current = pendingSplitHold

				if nextAmount ~= stack.amount then
					itemThunks.setDragStackAmount(nextAmount)
				end
			end
		end)

		local beganConnection = UserInputService.InputBegan:Connect(function(inputObject: InputObject, _: boolean)
			local currentDragState = itemSlice.getDragState()
			if not currentDragState.active then
				return
			end
			local inputType = inputObject.UserInputType

			if inputType == Enum.UserInputType.MouseButton2 then
				if pendingSplitHoldRef.current ~= nil then
					return
				end
				if currentDragState.hoveredSlot == nil then
					local sourceSlot = currentDragState.sourceSlot
					local didDrop = itemThunks.dropDrag(nil)
					if didDrop then
						playUiItemReleaseSound()
						setActivationSuppression(suppressionRef, sourceSlot, nil)
					end
				end
				return
			end

			if pendingSplitHoldRef.current ~= nil then
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
				if isPlaceableDragOutsideInventory(nextState) then
					return
				end
				finalizeDragWithSuppression(suppressionRef, nil)
			end)
		end)

		local endedConnection = UserInputService.InputEnded:Connect(function(inputObject: InputObject, _: boolean)
			if inputObject.UserInputType ~= Enum.UserInputType.MouseButton2 then
				return
			end
			if pendingSplitHoldRef.current == nil then
				return
			end
			clearPendingSplitHold()
		end)

		return function()
			changedConnection:Disconnect()
			renderConnection:Disconnect()
			beganConnection:Disconnect()
			endedConnection:Disconnect()
			clearPendingSplitHold()
			itemThunks.cancelDrag()
		end
	end, {})

	local handleSlotInput = React.useCallback(function(
		slotIndexRaw: any,
		stackRaw: any,
		inputObjectRaw: any?
	)
		local slotIndex = sanitizeSlot(slotIndexRaw)
		if slotIndex == nil then
			return
		end

		lastSlotInputTimeRef.current = os.clock()
		local pointerPosition = resolvePointerFromInput(inputObjectRaw)
		local state = itemSlice.getDragState()
		local inputType = if typeof(inputObjectRaw) == "InputObject"
			then (inputObjectRaw :: InputObject).UserInputType
			else nil

		if inputType == Enum.UserInputType.MouseButton2 then
			if state.active then
				return
			end
			syncPointerRefs(targetPointerRef, smoothedPointerRef, hasSmoothedPointerRef, pointerPosition)
			if typeof(stackRaw) ~= "table" then
				return
			end
			beginPendingSplitHold(slotIndex, stackRaw, pointerPosition)
			return
		end

		if state.active then
			if pendingSplitHoldRef.current ~= nil then
				return
			end
			syncPointerRefs(targetPointerRef, smoothedPointerRef, hasSmoothedPointerRef, pointerPosition)
			itemThunks.updatePointer(pointerPosition)
			finalizeDragWithSuppression(suppressionRef, slotIndex)
			return
		end

		if typeof(stackRaw) ~= "table" then
			return
		end
		if inputType ~= nil and inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end

		syncPointerRefs(targetPointerRef, smoothedPointerRef, hasSmoothedPointerRef, pointerPosition)
		clearPendingSplitHold()
		local nextDragState = itemThunks.beginDrag(slotIndex, stackRaw, pointerPosition)
		if nextDragState.active then
			playUiItemPickupSound()
		end
		itemThunks.setHoveredSlot(slotIndex)
		setActivationSuppression(suppressionRef, slotIndex, slotIndex)
	end, {})

	local handleSlotSecondaryInput = React.useCallback(function(
		slotIndexRaw: any,
		stackRaw: any,
		pointerPositionRaw: any?
	)
		local slotIndex = sanitizeSlot(slotIndexRaw)
		if slotIndex == nil then
			return
		end
		if itemSlice.getDragState().active then
			return
		end
		if typeof(stackRaw) ~= "table" then
			return
		end

		lastSlotInputTimeRef.current = os.clock()
		local pointerPosition = resolvePointerFromInput(pointerPositionRaw)
		syncPointerRefs(targetPointerRef, smoothedPointerRef, hasSmoothedPointerRef, pointerPosition)
		beginPendingSplitHold(slotIndex, stackRaw, pointerPosition)
	end, {})

	local cancelDrag = React.useCallback(function()
		clearPendingSplitHold()
		itemThunks.cancelDrag()
	end, {})

	local shouldSuppressActivation = React.useCallback(function(slotIndexRaw: any): boolean
		return shouldSuppressActivationNow(suppressionRef.current, slotIndexRaw)
	end, {})

	return {
		handleSlotInput = handleSlotInput,
		handleSlotSecondaryInput = handleSlotSecondaryInput,
		cancelDrag = cancelDrag,
		shouldSuppressActivation = shouldSuppressActivation,
		isDragging = dragState.active,
		dragSourceSlot = dragState.sourceSlot,
		dragState = dragState,
	}
end

return useDrag
