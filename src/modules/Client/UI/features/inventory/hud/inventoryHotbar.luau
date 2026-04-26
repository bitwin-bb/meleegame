--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Sift = require(ReplicatedStorage.Packages.Sift)

local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Modules.Items.Audio)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Services.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.AudioServiceUtils)
local CoinScreen = require(script:FindFirstAncestor("game").Client.UI.features.inventory.screens.coinScreen)
local CraftButton = require(script:FindFirstAncestor("game").Client.UI.features.crafting.hud.craftButton)
local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local InventoryServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.InventoryServiceUtils)
local ItemScreen = require(script:FindFirstAncestor("game").Client.UI.features.item.screen.itemScreen)
local NavButton = require(script:FindFirstAncestor("game").Client.UI.core.components.NavButton)
local React = require(ReplicatedStorage.Packages.React)
local TrashScreen = require(script:FindFirstAncestor("game").Client.UI.features.inventory.screens.trashScreen)
local infoThunks = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoThunks)
local inventorySlice = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.inventorySlice)
local inventoryThunks = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.inventoryThunks)
local trashThunks = require(script:FindFirstAncestor("game").Client.UI.features.inventory.state.trashThunks)
local itemSlice = require(script:FindFirstAncestor("game").Client.UI.features.item.state.itemSlice)
local itemThunks = require(script:FindFirstAncestor("game").Client.UI.features.item.state.itemThunks)
local useCoinEmerge = require(script:FindFirstAncestor("game").Client.UI.features.inventory.hooks.useCoinEmerge)
local useDrag = require(script:FindFirstAncestor("game").Client.UI.features.item.hooks.useDrag)
local useInterval = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useInterval)
local useInventorySlide = require(script:FindFirstAncestor("game").Client.UI.features.inventory.hooks.useInventorySlide)
local useSlotSelect = require(script:FindFirstAncestor("game").Client.UI.features.inventory.hooks.useSlotSelect)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)
local useToggle = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useToggle)
local useTrashAppear = require(script:FindFirstAncestor("game").Client.UI.features.inventory.hooks.useTrashAppear)

type InventoryState = InventoryServiceUtils.InventoryState
type InventorySlot = InventoryServiceUtils.InventorySlot
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack
type ItemDragState = itemSlice.ItemDragState

type InventoryHotbarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	slotSize: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	slotPadding: UDim?,
	showKeyHints: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local HOTBAR_SLOT_COUNT = 8
local HOTBAR_CONTROL_BUTTON_COUNT = 2
local INVENTORY_COLUMNS = 8
local INVENTORY_ROWS = 8
local INVENTORY_MAX_SLOTS = INVENTORY_COLUMNS * INVENTORY_ROWS
local GRID_SLOT_START_INDEX = HOTBAR_SLOT_COUNT + 1
local TOTAL_VISIBLE_SLOTS = HOTBAR_SLOT_COUNT + INVENTORY_MAX_SLOTS
local DEFAULT_SLOT_SIZE = UDim2.fromOffset(58, 58)
local DEFAULT_SLOT_GAP = 6
local DEFAULT_LEFT_PADDING = 16
local HOTBAR_SLOT_SELECTED_SCALE = 1.12
local SLOT_HOVER_ID_PREFIX = "inventory_slot_"
local EMPTY_SLOT_TINT = Color3.fromRGB(152, 160, 172)
local FILLED_SLOT_TINT = Color3.fromRGB(255, 255, 255)
local SELECTED_SLOT_TINT = Color3.fromRGB(142, 220, 255)
local DISABLED_SLOT_TINT = Color3.fromRGB(100, 108, 120)
local EXPANSION_VISIBILITY_EPSILON = 0.001
local TRASH_VISIBILITY_EPSILON = 0.001
local UI_AUDIO = (AudioRegistry :: any).UI or {}
local UI_HOVER_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Hover)
local UI_PRESS_SOUND = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Press or UI_AUDIO.Click)
type HoveredSlotSource = "Hotbar" | "Grid"
local GAMEPAD_INVENTORY_TOGGLE_KEY = Enum.KeyCode.ButtonY
local GAMEPAD_DROP_TRASH_KEY = Enum.KeyCode.ButtonX
local GAMEPAD_HOTBAR_PREVIOUS_KEY = Enum.KeyCode.ButtonL1
local GAMEPAD_HOTBAR_NEXT_KEY = Enum.KeyCode.ButtonR1
local KEYCODE_TO_SLOT_INDEX: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
}

local DEFAULT_RENDER_INVENTORY_STATE =
	InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADING)

local function snapToPixel(value: number): number
	return math.floor(value + 0.5)
end

local function playUiHoverSound()
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	if UI_HOVER_SOUND == nil then
		return
	end

	AudioServiceClient:playUi(UI_HOVER_SOUND, {
		replaceChannel = false,
	})
end

local function playUiPressSound()
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	if UI_PRESS_SOUND == nil then
		return
	end

	AudioServiceClient:playUi(UI_PRESS_SOUND, {
		replaceChannel = false,
	})
end

local function sanitizeRenderState(stateRaw: any): InventoryState
	return InventoryServiceUtils.sanitizeState(stateRaw, DEFAULT_RENDER_INVENTORY_STATE)
end

local function resolveSlot(stateRaw: any, slotIndexRaw: any): InventorySlot
	local slotIndex = if typeof(slotIndexRaw) == "number" and slotIndexRaw == slotIndexRaw
		then math.max(1, math.floor(slotIndexRaw))
		else 1
	local state = sanitizeRenderState(stateRaw)
	local slot = InventoryServiceUtils.getSlot(state, slotIndex)
	if slot == nil or typeof(slot) ~= "table" then
		return {
			index = slotIndex,
			stack = nil,
		}
	end

	local stackRaw = (slot :: any).stack
	local stack = if typeof(stackRaw) == "table" then stackRaw :: InventoryItemStack else nil
	local indexRaw = (slot :: any).index
	local index = if typeof(indexRaw) == "number" and indexRaw == indexRaw
		then math.max(1, math.floor(indexRaw))
		else slotIndex
	return {
		index = index,
		stack = stack,
	}
end

local function resolveStackAmount(stackRaw: any): number
	if typeof(stackRaw) ~= "table" then
		return 0
	end
	local amountRaw = (stackRaw :: any).amount
	if typeof(amountRaw) ~= "number" or amountRaw ~= amountRaw then
		return 0
	end
	return math.max(0, math.floor(amountRaw))
end

local function resolveStackIcon(stackRaw: any): string?
	if typeof(stackRaw) ~= "table" then
		return nil
	end
	local success, icon = pcall(function()
		return itemThunks.resolveIconForStack(stackRaw :: InventoryItemStack)
	end)
	if not success then
		return nil
	end
	if typeof(icon) == "string" then
		return icon
	end
	return nil
end

local function resolveSlotHoverText(slot: InventorySlot): string
	local stack = slot.stack
	if typeof(stack) ~= "table" then
		return ("Slot %d\nEmpty"):format(slot.index)
	end

	local success, hoverText = pcall(function()
		return itemThunks.resolveHoverTextForStack(stack :: InventoryItemStack, slot.index)
	end)
	if success and typeof(hoverText) == "string" then
		return hoverText
	end
	return ("Slot %d\nEmpty"):format(slot.index)
end

local function cloneStackWithAmount(stack: InventoryItemStack, amount: number): InventoryItemStack
	return {
		stackId = stack.stackId,
		itemId = stack.itemId,
		amount = amount,
		maxStack = stack.maxStack,
		metadata = InventoryServiceUtils.cloneDeep(stack.metadata),
	}
end

local function resolveDisplayedStackForSlot(slot: InventorySlot, dragState: ItemDragState): InventoryItemStack?
	local stack = slot.stack
	if stack == nil then
		return nil
	end
	if not dragState.active or dragState.mode ~= "SplitHold" then
		return stack
	end
	if dragState.sourceSlot ~= slot.index then
		return stack
	end
	if dragState.stack == nil or dragState.sourceStackAmount == nil then
		return stack
	end
	if dragState.stack.stackId ~= stack.stackId then
		return stack
	end

	local remainingAmount = math.max(0, dragState.sourceStackAmount - dragState.stack.amount)
	if remainingAmount <= 0 then
		return nil
	end
	if remainingAmount == stack.amount then
		return stack
	end
	return cloneStackWithAmount(stack, remainingAmount)
end

local function selectSlot(slotIndex: number, currentlySelectedSlot: number?)
	if currentlySelectedSlot == slotIndex then
		inventoryThunks.clearSelectedSlot()
	else
		inventoryThunks.selectSlot(slotIndex)
	end
end

local function resolveColumnRevealProgress(progress: number, columnIndex: number, totalColumns: number): number
	local clampedProgress = math.clamp(progress, 0, 1)
	local start = (columnIndex - 1) / totalColumns
	local finish = columnIndex / totalColumns
	local span = math.max(0.0001, finish - start)
	return math.clamp((clampedProgress - start) / span, 0, 1)
end

local function lerpNumber(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

local function lerpVector2(from: Vector2, to: Vector2, alpha: number): Vector2
	return Vector2.new(lerpNumber(from.X, to.X, alpha), lerpNumber(from.Y, to.Y, alpha))
end

local function resolveLoadingInventoryText(dotCountRaw: number): string
	local dotCount = math.clamp(math.floor(dotCountRaw), 1, 3)
	return "Loading inventory" .. string.rep(".", dotCount)
end

local function isGamepadInputType(inputTypeRaw: any): boolean
	if typeof(inputTypeRaw) ~= "EnumItem" then
		return false
	end
	return string.sub((inputTypeRaw :: Enum.UserInputType).Name, 1, 7) == "Gamepad"
end

local function resolveHotbarSelectionSlot(stateRaw: any): number
	local state = sanitizeRenderState(stateRaw)
	local selectedSlot = state.selectedSlot
	if typeof(selectedSlot) == "number" and selectedSlot == selectedSlot then
		selectedSlot = math.floor(selectedSlot)
	else
		selectedSlot = nil
	end
	if selectedSlot == nil or selectedSlot < 1 or selectedSlot > HOTBAR_SLOT_COUNT then
		return 1
	end
	return selectedSlot
end

local function cycleHotbarSelection(stepRaw: any)
	local step = if typeof(stepRaw) == "number" and stepRaw == stepRaw and stepRaw ~= 0
		then if stepRaw < 0 then -1 else 1
		else nil
	if step == nil then
		return false
	end
	local currentState = inventorySlice.getInventoryState()
	local nextSelectedSlot = ((resolveHotbarSelectionSlot(currentState) - 1 + step) % HOTBAR_SLOT_COUNT) + 1
	return inventoryThunks.selectSlot(nextSelectedSlot)
end

local function handleSelectedSlotDropOrTrash(isInventoryExpandedRaw: any): boolean
	local currentState = sanitizeRenderState(inventorySlice.getInventoryState())
	if not InventoryServiceUtils.isLoadedState(currentState.loadState) then
		return false
	end

	local selectedSlot = currentState.selectedSlot
	if typeof(selectedSlot) ~= "number" or selectedSlot ~= selectedSlot then
		return false
	end
	selectedSlot = math.floor(selectedSlot)
	if selectedSlot < 1 then
		return false
	end

	local slot = resolveSlot(currentState, selectedSlot)
	if slot.stack == nil then
		return false
	end

	if isInventoryExpandedRaw == true and trashThunks.trashSelected(nil) then
		return true
	end

	return inventoryThunks.dropFromSlot(selectedSlot, nil)
end

return function(props: InventoryHotbarProps)
	local inventoryState = (useStore(inventorySlice.inventoryStateAtom) :: InventoryState?)
		or inventorySlice.inventoryStateAtom()
	local renderState = sanitizeRenderState(inventoryState)
	local isInventoryStateInitialized = typeof(renderState.slots) == "table"
		and #renderState.slots >= math.max(1, renderState.capacity)
	local hoveredSlotIndex, setHoveredSlotIndex = React.useState(nil :: number?)
	local hoveredSlotSource, setHoveredSlotSource = React.useState(nil :: HoveredSlotSource?)
	local isExpandButtonPressed = useToggle(false)
	local isInventoryExpanded = useToggle(false)
	local loadingDotCount, setLoadingDotCount = React.useState(1)
	local drag = useDrag({
		hoveredSlotIndex = hoveredSlotIndex,
	})

	local expansionProgress = useInventorySlide({
		enabled = isInventoryExpanded.value,
	})

	React.useEffect(function()
		local stop = inventoryThunks.start()

		return function()
			stop()
		end
	end, {})

	React.useEffect(function()
		if props.visible == false then
			return
		end

		local function onInputBegan(inputObject: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			if UserInputService:GetFocusedTextBox() ~= nil then
				return
			end
			if not isInventoryStateInitialized then
				return
			end
			if not InventoryServiceUtils.isLoadedState(renderState.loadState) then
				return
			end

			if inputObject.UserInputType == Enum.UserInputType.Keyboard then
				local selectedFromKey = KEYCODE_TO_SLOT_INDEX[inputObject.KeyCode]
				if selectedFromKey == nil then
					return
				end

				inventoryThunks.selectSlot(selectedFromKey)
				return
			end

			if not isGamepadInputType(inputObject.UserInputType) then
				return
			end

			if inputObject.KeyCode == GAMEPAD_INVENTORY_TOGGLE_KEY then
				playUiPressSound()
				isInventoryExpanded.toggle()
				return
			end

			if inputObject.KeyCode == GAMEPAD_DROP_TRASH_KEY then
				handleSelectedSlotDropOrTrash(isInventoryExpanded.value)
				return
			end

			if inputObject.KeyCode == GAMEPAD_HOTBAR_PREVIOUS_KEY then
				cycleHotbarSelection(-1)
				return
			end

			if inputObject.KeyCode == GAMEPAD_HOTBAR_NEXT_KEY then
				cycleHotbarSelection(1)
			end
		end

		local function onInputChanged(inputObject: InputObject)
			if inputObject.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			if UserInputService:GetFocusedTextBox() ~= nil then
				return
			end
			if not isInventoryStateInitialized then
				return
			end
			if not InventoryServiceUtils.isLoadedState(renderState.loadState) then
				return
			end

			local wheelDelta = inputObject.Position.Z
			if wheelDelta == 0 then
				return
			end

			local currentState = inventorySlice.getInventoryState()
			local currentSelectedSlot = currentState.selectedSlot
			if currentSelectedSlot == nil or currentSelectedSlot < 1 or currentSelectedSlot > HOTBAR_SLOT_COUNT then
				currentSelectedSlot = 1
			end

			local step = if wheelDelta > 0 then -1 else 1
			local nextSelectedSlot = ((currentSelectedSlot - 1 + step) % HOTBAR_SLOT_COUNT) + 1
			inventoryThunks.selectSlot(nextSelectedSlot)
		end

		local beganConnection = UserInputService.InputBegan:Connect(onInputBegan)
		local changedConnection = UserInputService.InputChanged:Connect(onInputChanged)

		return function()
			beganConnection:Disconnect()
			changedConnection:Disconnect()
		end
	end, {
		props.visible,
		renderState.loadState,
		isInventoryStateInitialized,
		isInventoryExpanded.value,
	})

	React.useEffect(function()
		if not isInventoryStateInitialized then
			return
		end
		local currentInteractiveLimit = math.min(renderState.capacity, TOTAL_VISIBLE_SLOTS)
		if hoveredSlotIndex == nil then
			return
		end
		if hoveredSlotSource == nil then
			return
		end
		if hoveredSlotIndex < 1 or hoveredSlotIndex > currentInteractiveLimit then
			return
		end

		local hoveredSlot = resolveSlot(renderState, hoveredSlotIndex)
		hoveredSlot = {
			index = hoveredSlot.index,
			stack = resolveDisplayedStackForSlot(hoveredSlot, drag.dragState),
		}
		infoThunks.showHover({
			id = SLOT_HOVER_ID_PREFIX .. tostring(hoveredSlotIndex),
			text = resolveSlotHoverText(hoveredSlot),
		})
	end, {
		hoveredSlotIndex,
		hoveredSlotSource,
		renderState.updatedAt,
		renderState.capacity,
		isInventoryStateInitialized,
		drag.dragState.updatedAt,
	})

	React.useEffect(function()
		return function()
			infoThunks.hideHover(nil)
		end
	end, {})

	local isLoading = not InventoryServiceUtils.isLoadedState(renderState.loadState)
		and renderState.loadState ~= InventoryServiceUtils.LOAD_STATE_FAILED
	useInterval(
		function()
			setLoadingDotCount(function(currentDotCount: number): number
				return (currentDotCount % 3) + 1
			end)
		end,
		0.4,
		{
			enabled = isLoading,
		}
	)

	React.useEffect(function()
		if not isLoading then
			setLoadingDotCount(1)
		end
	end, { isLoading })

	local zIndex = props.zIndex or 30
	local selectedSlot = renderState.selectedSlot
	local rawSlotSize = props.slotSize or DEFAULT_SLOT_SIZE
	local slotWidth = snapToPixel(rawSlotSize.X.Offset)
	local slotHeight = snapToPixel(rawSlotSize.Y.Offset)
	local hotbarSlotSize = UDim2.fromOffset(slotWidth, slotHeight)
	local hotbarGap = snapToPixel(if props.slotPadding then props.slotPadding.Offset else DEFAULT_SLOT_GAP)
	local hotbarWidth = slotWidth
	local hotbarSlotsHeight = slotHeight * HOTBAR_SLOT_COUNT + hotbarGap * (HOTBAR_SLOT_COUNT - 1)
	local hotbarSidebarHeight = slotHeight * (HOTBAR_SLOT_COUNT + HOTBAR_CONTROL_BUTTON_COUNT)
		+ hotbarGap * (HOTBAR_SLOT_COUNT + HOTBAR_CONTROL_BUTTON_COUNT - 1)

	local gridSlotSize = hotbarSlotSize
	local gridGap = hotbarGap
	local gridWidth = slotWidth * INVENTORY_COLUMNS + gridGap * (INVENTORY_COLUMNS - 1)
	local gridContainerWidth = gridWidth
	local gridContainerHeight = hotbarSlotsHeight
	local coinEmerge = useCoinEmerge({
		enabled = isInventoryExpanded.value,
		fromOffset = Vector2.new(-(gridContainerWidth + gridGap), 0),
		toOffset = Vector2.zero,
	})
	local trashAppear = useTrashAppear({
		enabled = isInventoryExpanded.value,
		fromOffset = Vector2.new(-(hotbarSlotSize.X.Offset * 0.65), 0),
		toOffset = Vector2.zero,
	})
	local showExpandedGrid = isInventoryExpanded.value or expansionProgress > EXPANSION_VISIBILITY_EPSILON
	local showRevealOverlay = showExpandedGrid and expansionProgress < (1 - EXPANSION_VISIBILITY_EPSILON)
	local showTrashScreen = isInventoryExpanded.value or trashAppear.progress > TRASH_VISIBILITY_EPSILON
	local maxInteractiveSlots = if isInventoryStateInitialized
		then math.min(renderState.capacity, TOTAL_VISIBLE_SLOTS)
		else 0

	React.useEffect(function()
		if showExpandedGrid then
			return
		end
		if hoveredSlotSource ~= "Grid" then
			return
		end

		setHoveredSlotSource(nil)
		setHoveredSlotIndex(nil)
		infoThunks.hideHover(nil)
	end, { showExpandedGrid, hoveredSlotSource })

	local leftPadding = DEFAULT_LEFT_PADDING
	local expanderSize = hotbarSlotSize
	local rawHotbarPosition = props.position or UDim2.new(0, leftPadding, 0.5, 0)
	local hotbarPosition = UDim2.new(
		rawHotbarPosition.X.Scale,
		snapToPixel(rawHotbarPosition.X.Offset),
		rawHotbarPosition.Y.Scale,
		snapToPixel(rawHotbarPosition.Y.Offset)
	)
	local hotbarAnchorPoint = props.anchorPoint or Vector2.new(0, 0.5)
	local inventoryPanelPosition = UDim2.new(
		hotbarPosition.X.Scale,
		snapToPixel(hotbarPosition.X.Offset + hotbarWidth + gridGap),
		hotbarPosition.Y.Scale,
		snapToPixel(hotbarPosition.Y.Offset)
	)
	local inventoryPanelAnchorPoint = Vector2.new(0, hotbarAnchorPoint.Y)
	local inventoryTopOffset = -gridContainerHeight * hotbarAnchorPoint.Y
	local expanderPosition = UDim2.new(
		hotbarPosition.X.Scale,
		snapToPixel(hotbarPosition.X.Offset),
		hotbarPosition.Y.Scale,
		snapToPixel(hotbarPosition.Y.Offset + hotbarSlotsHeight * (1 - hotbarAnchorPoint.Y) + hotbarGap)
	)
	local trashPosition = UDim2.new(
		expanderPosition.X.Scale,
		snapToPixel(expanderPosition.X.Offset + expanderSize.X.Offset + hotbarGap),
		expanderPosition.Y.Scale,
		snapToPixel(expanderPosition.Y.Offset)
	)
	local hotbarSidebarPosition = UDim2.new(
		hotbarPosition.X.Scale,
		snapToPixel(hotbarPosition.X.Offset),
		hotbarPosition.Y.Scale,
		snapToPixel(hotbarPosition.Y.Offset + hotbarAnchorPoint.Y * (hotbarSidebarHeight - hotbarSlotsHeight))
	)
	local hotbarSlotScales: { number } = Sift.Array.create(HOTBAR_SLOT_COUNT)

	for hotbarIndex = 1, HOTBAR_SLOT_COUNT do
		local isSlotAvailable = isInventoryStateInitialized and hotbarIndex <= maxInteractiveSlots
		local isSelected = selectedSlot == hotbarIndex
		local isHovered = hoveredSlotSource == "Hotbar" and hoveredSlotIndex == hotbarIndex
		hotbarSlotScales[hotbarIndex] = useSlotSelect({
			enabled = isSlotAvailable and (isSelected or isHovered),
			selectedScale = HOTBAR_SLOT_SELECTED_SCALE,
		})
	end

	local hotbarChildren: { [string]: React.ReactNode } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, hotbarGap),
		}),
	}

	for hotbarIndex = 1, HOTBAR_SLOT_COUNT do
		local slot = resolveSlot(renderState, hotbarIndex)
		local displayStack = resolveDisplayedStackForSlot(slot, drag.dragState)
		local isSlotAvailable = isInventoryStateInitialized and hotbarIndex <= maxInteractiveSlots
		local hasItem = isSlotAvailable and typeof(displayStack) == "table"
		local isSelected = selectedSlot == hotbarIndex
		local isSplitPreviewSource = drag.dragState.active
			and drag.dragState.mode == "SplitHold"
			and drag.dragState.sourceSlot == hotbarIndex
		local isDragSourceSlot = drag.isDragging and drag.dragSourceSlot == hotbarIndex and not isSplitPreviewSource
		local hasVisibleItem = hasItem and not isDragSourceSlot
		local showKeyHints = props.showKeyHints ~= false
		local isHovered = hoveredSlotSource == "Hotbar" and hoveredSlotIndex == hotbarIndex
		local slotScale = hotbarSlotScales[hotbarIndex]
		local isExpanded = slotScale > 1.001
		local slotTint = if isSelected
			then SELECTED_SLOT_TINT
			else if hasVisibleItem then FILLED_SLOT_TINT else EMPTY_SLOT_TINT
		local slotImage = if isSelected or isHovered then ImageIds.inventorySlotHovered else ImageIds.inventorySlot
		local slotZIndex = if isExpanded then zIndex + 3 else zIndex + 2
		local itemAmount = if hasVisibleItem then resolveStackAmount(displayStack) else 0
		local itemIcon = if hasVisibleItem then resolveStackIcon(displayStack) else nil

		hotbarChildren["Slot_" .. tostring(hotbarIndex)] = e("ImageButton", {
			Name = "Slot_" .. tostring(hotbarIndex),
			Size = hotbarSlotSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = slotImage,
			ImageColor3 = slotTint,
			ImageTransparency = 0,
			LayoutOrder = hotbarIndex,
			ZIndex = slotZIndex,
			AutoButtonColor = false,
			Active = isSlotAvailable,
			Selectable = isSlotAvailable,
			[React.Event.MouseEnter] = function()
				setHoveredSlotSource("Hotbar")
				setHoveredSlotIndex(hotbarIndex)
				playUiHoverSound()
			end,
			[React.Event.MouseLeave] = function()
				setHoveredSlotSource(nil)
				setHoveredSlotIndex(nil)
				infoThunks.hideHover(SLOT_HOVER_ID_PREFIX .. tostring(hotbarIndex))
			end,
			[React.Event.MouseButton2Down] = function()
				if not isSlotAvailable then
					return
				end
				if UserInputService:GetFocusedTextBox() ~= nil then
					return
				end
				drag.handleSlotSecondaryInput(hotbarIndex, if typeof(slot.stack) == "table" then slot.stack else nil)
			end,
			[React.Event.InputBegan] = function(_: GuiObject, inputObject: InputObject)
				if not isSlotAvailable then
					return
				end
				local userInputType = inputObject.UserInputType
				if userInputType ~= Enum.UserInputType.MouseButton1 and userInputType ~= Enum.UserInputType.Touch then
					return
				end
				drag.handleSlotInput(
					hotbarIndex,
					if typeof(slot.stack) == "table" then slot.stack else nil,
					inputObject
				)
			end,
			[React.Event.Activated] = function()
				if not isSlotAvailable then
					return
				end
				if drag.isDragging or drag.shouldSuppressActivation(hotbarIndex) then
					return
				end
				if not isInventoryStateInitialized then
					return
				end
				if not InventoryServiceUtils.isLoadedState(renderState.loadState) then
					return
				end
				selectSlot(hotbarIndex, selectedSlot)
			end,
		}, {
			Scale = e("UIScale", {
				Scale = slotScale,
			}),
			KeyHint = if showKeyHints
				then e("TextLabel", {
					Name = "KeyHint",
					Size = UDim2.fromOffset(16, 14),
					Position = UDim2.fromOffset(4, 4),
					BackgroundTransparency = 1,
					Text = tostring(hotbarIndex),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = Color3.fromRGB(202, 235, 255),
					TextStrokeTransparency = 0.55,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = slotZIndex + 2,
				})
				else nil,
			Amount = if hasVisibleItem and itemAmount > 1
				then e("TextLabel", {
					Name = "Amount",
					Size = UDim2.fromOffset(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Position = UDim2.new(1, -6, 1, -5),
					AnchorPoint = Vector2.new(1, 1),
					BackgroundTransparency = 1,
					Text = tostring(itemAmount),
					Font = Enum.Font.GothamBold,
					TextSize = 13,
					TextColor3 = Color3.fromRGB(248, 253, 255),
					TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					TextStrokeTransparency = 0.3,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextYAlignment = Enum.TextYAlignment.Bottom,
					ZIndex = slotZIndex + 3,
				})
				else nil,
			Icon = if hasVisibleItem and itemIcon ~= nil
				then e("ImageLabel", {
					Name = "Icon",
					Size = UDim2.fromOffset(32, 32),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = itemIcon,
					ImageColor3 = Color3.fromRGB(255, 255, 255),
					ImageTransparency = 0,
					ZIndex = slotZIndex + 2,
				})
				else nil,
		})
	end

	hotbarChildren.ExpanderButton = e(NavButton, {
		id = "InventoryExpander",
		label = nil,
		icon = if isExpandButtonPressed.value or isInventoryExpanded.value
			then ImageIds.expandInventoryPressed
			else ImageIds.expandInventory,
		size = expanderSize,
		iconSize = expanderSize,
		iconColor3 = Color3.new(1, 1, 1),
		padding = UDim.new(0, 0),
		cornerRadius = UDim.new(0, 0),
		backgroundTransparency = 1,
		strokeTransparency = 1,
		zIndex = zIndex + 4,
		layoutOrder = HOTBAR_SLOT_COUNT + 1,
		selected = isInventoryExpanded.value,
		onPressedChanged = function(isPressedValue: boolean)
			isExpandButtonPressed.set(isPressedValue)
		end,
		onHoverChanged = function(isHovered: boolean)
			if isHovered then
				playUiHoverSound()
			end
		end,
		onActivated = function()
			playUiPressSound()
			isInventoryExpanded.toggle()
		end,
	})

	hotbarChildren.CraftButton = e(CraftButton, {
		layoutOrder = HOTBAR_SLOT_COUNT + 2,
		size = expanderSize,
		zIndex = zIndex + 4,
	})

	local gridChildren: { [string]: React.ReactNode } = {}
	local gridStepX = gridSlotSize.X.Offset + gridGap
	local gridStepY = gridSlotSize.Y.Offset + gridGap
	local hotbarOriginOffsetX = -(hotbarWidth + gridGap)

	for slotIndex = 1, INVENTORY_MAX_SLOTS do
		local inventorySlotIndex = GRID_SLOT_START_INDEX + slotIndex - 1
		local slot = resolveSlot(renderState, inventorySlotIndex)
		local displayStack = resolveDisplayedStackForSlot(slot, drag.dragState)
		local isSlotAvailable = isInventoryStateInitialized and inventorySlotIndex <= maxInteractiveSlots
		local hasItem = isSlotAvailable and typeof(displayStack) == "table"
		local isSelected = isSlotAvailable and selectedSlot == inventorySlotIndex
		local isSplitPreviewSource = drag.dragState.active
			and drag.dragState.mode == "SplitHold"
			and drag.dragState.sourceSlot == inventorySlotIndex
		local isDragSourceSlot = drag.isDragging
			and drag.dragSourceSlot == inventorySlotIndex
			and not isSplitPreviewSource
		local hasVisibleItem = hasItem and not isDragSourceSlot
		local isHovered = hoveredSlotSource == "Grid" and hoveredSlotIndex == inventorySlotIndex
		local rowIndex = math.floor((slotIndex - 1) / INVENTORY_COLUMNS)
		local columnIndex = ((slotIndex - 1) % INVENTORY_COLUMNS) + 1
		local columnRevealProgress = resolveColumnRevealProgress(expansionProgress, columnIndex, INVENTORY_COLUMNS)
		local columnRevealTransparency = 1 - columnRevealProgress
		local finalSlotOffset = Vector2.new((columnIndex - 1) * gridStepX, rowIndex * gridStepY)
		local startSlotOffset = Vector2.new(hotbarOriginOffsetX, finalSlotOffset.Y)
		local currentSlotOffset = lerpVector2(startSlotOffset, finalSlotOffset, columnRevealProgress)
		local slotTint = if not isSlotAvailable
			then DISABLED_SLOT_TINT
			else if isSelected
				then SELECTED_SLOT_TINT
				else if hasVisibleItem then FILLED_SLOT_TINT else EMPTY_SLOT_TINT
		local slotImage = if isSelected or isHovered then ImageIds.inventorySlotHovered else ImageIds.inventorySlot
		local itemAmount = if hasVisibleItem then resolveStackAmount(displayStack) else 0
		local slotZIndex = zIndex + 3
		local slotBaseTransparency = if isSlotAvailable then 0 else 0.15
		local slotTransparency =
			math.clamp(slotBaseTransparency + columnRevealTransparency * (1 - slotBaseTransparency), 0, 1)
		local itemIcon = if hasVisibleItem then resolveStackIcon(displayStack) else nil
		local isGridSlotInteractable = isSlotAvailable and columnRevealProgress >= (1 - EXPANSION_VISIBILITY_EPSILON)

		gridChildren["GridSlotContainer_" .. tostring(slotIndex)] = e("Frame", {
			Name = "GridSlotContainer_" .. tostring(slotIndex),
			Size = gridSlotSize,
			Position = UDim2.fromOffset(snapToPixel(currentSlotOffset.X), snapToPixel(currentSlotOffset.Y)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = slotZIndex,
		}, {
			Slot = e("ImageButton", {
				Name = "GridSlot_" .. tostring(slotIndex),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = slotImage,
				ImageColor3 = slotTint,
				ImageTransparency = slotTransparency,
				ZIndex = slotZIndex,
				AutoButtonColor = false,
				Active = isGridSlotInteractable,
				Selectable = isGridSlotInteractable,
				[React.Event.MouseEnter] = function()
					if not isGridSlotInteractable then
						return
					end
					setHoveredSlotSource("Grid")
					setHoveredSlotIndex(inventorySlotIndex)
					playUiHoverSound()
				end,
				[React.Event.MouseLeave] = function()
					if isGridSlotInteractable then
						setHoveredSlotSource(nil)
						setHoveredSlotIndex(nil)
						infoThunks.hideHover(SLOT_HOVER_ID_PREFIX .. tostring(inventorySlotIndex))
					end
				end,
				[React.Event.MouseButton2Down] = function()
					if not isGridSlotInteractable then
						return
					end
					if UserInputService:GetFocusedTextBox() ~= nil then
						return
					end
					drag.handleSlotSecondaryInput(
						inventorySlotIndex,
						if typeof(slot.stack) == "table" then slot.stack else nil
					)
				end,
				[React.Event.InputBegan] = function(_: GuiObject, inputObject: InputObject)
					if not isGridSlotInteractable then
						return
					end
					local userInputType = inputObject.UserInputType
					if userInputType ~= Enum.UserInputType.MouseButton1 and userInputType ~= Enum.UserInputType.Touch then
						return
					end
					drag.handleSlotInput(
						inventorySlotIndex,
						if typeof(slot.stack) == "table" then slot.stack else nil,
						inputObject
					)
				end,
				[React.Event.Activated] = function()
					if not isGridSlotInteractable then
						return
					end
					if drag.isDragging or drag.shouldSuppressActivation(inventorySlotIndex) then
						return
					end
					if not isInventoryStateInitialized then
						return
					end
					if not InventoryServiceUtils.isLoadedState(renderState.loadState) then
						return
					end
					selectSlot(inventorySlotIndex, selectedSlot)
				end,
			}, {
			Amount = if hasVisibleItem and itemAmount > 1
				then e("TextLabel", {
					Name = "Amount",
					Size = UDim2.fromOffset(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Position = UDim2.new(1, -5, 1, -4),
					AnchorPoint = Vector2.new(1, 1),
					BackgroundTransparency = 1,
					Text = tostring(itemAmount),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = Color3.fromRGB(248, 253, 255),
					TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					TextTransparency = columnRevealTransparency,
					TextStrokeTransparency = math.clamp(0.3 + columnRevealTransparency * 0.7, 0, 1),
					ZIndex = slotZIndex + 1,
				})
				else nil,
			Icon = if hasVisibleItem and itemIcon ~= nil
				then e("ImageLabel", {
					Name = "Icon",
					Size = UDim2.fromOffset(30, 30),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = itemIcon,
					ImageColor3 = Color3.fromRGB(255, 255, 255),
					ImageTransparency = columnRevealTransparency,
					ZIndex = slotZIndex + 1,
				})
				else nil,
			SelectedStroke = if isSelected
				then e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Color3.fromRGB(128, 226, 255),
					Transparency = math.clamp(0.15 + columnRevealTransparency * 0.85, 0, 1),
					Thickness = 1.25,
				})
				else nil,
			}),
		})
	end

	local rootChildren: { [string]: React.ReactNode } = {
		Hotbar = e("Frame", {
			Name = "InventoryHotbarLeft",
			Size = UDim2.fromOffset(hotbarWidth, hotbarSidebarHeight),
			Position = hotbarSidebarPosition,
			AnchorPoint = hotbarAnchorPoint,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, hotbarChildren),
		TrashScreen = e(TrashScreen, {
			layoutOrder = 3,
			visible = showTrashScreen,
			zIndex = zIndex + 7,
			position = trashPosition,
			anchorPoint = Vector2.new(0, 0),
			size = expanderSize,
			emergeOffset = trashAppear.offset,
			emergeTransparency = trashAppear.transparency,
		}),
	}

	if showExpandedGrid then
		rootChildren.ExpandedInventoryContainer = e("Frame", {
			Name = "ExpandedInventoryContainer",
			Size = UDim2.fromOffset(gridContainerWidth, gridContainerHeight),
			Position = inventoryPanelPosition,
			AnchorPoint = inventoryPanelAnchorPoint,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			ExpandedInventory = e("Frame", {
				Name = "ExpandedInventory",
				Size = UDim2.fromOffset(gridContainerWidth, gridContainerHeight),
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 2,
			}, gridChildren),
			InventoryColumnReveal = if showRevealOverlay
				then e("Frame", {
					Name = "InventoryColumnReveal",
					Size = UDim2.fromOffset(gridContainerWidth, gridContainerHeight),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = zIndex + 6,
					Active = true,
					Selectable = true,
				})
				else nil,
			CoinScreen = e(CoinScreen, {
				layoutOrder = 2,
				visible = showExpandedGrid,
				zIndex = zIndex + 7,
				position = UDim2.new(1, 0, 1, hotbarGap),
				anchorPoint = Vector2.new(1, 0),
				slotSize = gridSlotSize,
				emergeOffset = coinEmerge.offset,
				emergeTransparency = coinEmerge.transparency,
			}),
		})
	end

	rootChildren.StatusLabel = if not InventoryServiceUtils.isLoadedState(renderState.loadState)
		then e("TextLabel", {
			Name = "InventoryStatus",
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(
				hotbarPosition.X.Scale,
				snapToPixel(hotbarPosition.X.Offset),
				hotbarPosition.Y.Scale,
				snapToPixel(hotbarPosition.Y.Offset + inventoryTopOffset - 6)
			),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			Text = if renderState.loadState == InventoryServiceUtils.LOAD_STATE_FAILED
				then "Inventory unavailable"
				else resolveLoadingInventoryText(loadingDotCount),
			Font = Enum.Font.GothamSemibold,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(240, 242, 255),
			TextStrokeTransparency = 0.5,
			ZIndex = zIndex + 6,
		})
		else nil
	rootChildren.ItemScreen = e(ItemScreen, {
		layoutOrder = 99,
		visible = props.visible ~= false,
		zIndex = zIndex + 120,
	})

	return e("Frame", {
		Name = "InventoryHotbar",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 6,
		ZIndex = zIndex,
		Visible = props.visible ~= false,
		Active = false,
	}, rootChildren)
end
