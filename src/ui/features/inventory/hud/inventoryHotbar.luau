--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local Signal = require(ReplicatedStorage.Packages.Signal)
local ImageIds = require(ReplicatedStorage.UI.core.ImageIds)
local NavButton = require(ReplicatedStorage.UI.core.components.NavButton)
local infoThunks = require(ReplicatedStorage.UI.features.info.state.infoThunks)
local CoinScreen = require(ReplicatedStorage.UI.features.inventory.screens.coinScreen)
local TrashScreen = require(ReplicatedStorage.UI.features.inventory.screens.trashScreen)
local CraftButton = require(ReplicatedStorage.UI.features.crafting.hud.craftButton)
local inventorySlice = require(ReplicatedStorage.UI.features.inventory.state.inventorySlice)
local inventoryThunks = require(ReplicatedStorage.UI.features.inventory.state.inventoryThunks)
local ItemScreen = require(ReplicatedStorage.UI.features.item.screen.itemScreen)
local useDrag = require(ReplicatedStorage.UI.features.item.hooks.useDrag)
local itemThunks = require(ReplicatedStorage.UI.features.item.state.itemThunks)
local useInventorySlide = require(ReplicatedStorage.UI.features.inventory.hooks.useInventorySlide)
local useCoinEmerge = require(ReplicatedStorage.UI.features.inventory.hooks.useCoinEmerge)
local useTrashAppear = require(ReplicatedStorage.UI.features.inventory.hooks.useTrashAppear)
local useSlotSelect = require(ReplicatedStorage.UI.features.inventory.hooks.useSlotSelect)
local InventoryServiceUtils = require(ReplicatedStorage.Shared.Services.InventoryService.InventoryServiceUtils)
local SoundServiceClient = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceClient)
local SoundServiceUtils = require(ReplicatedStorage.Shared.Services.SoundService.SoundServiceUtils)

type InventoryState = InventoryServiceUtils.InventoryState
type InventorySlot = InventoryServiceUtils.InventorySlot
type InventoryItemStack = InventoryServiceUtils.InventoryItemStack

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
local HOTBAR_SLOT_SELECTED_SCALE = 1
local SLOT_HOVER_ID_PREFIX = "inventory_slot_"
local EMPTY_SLOT_TINT = Color3.fromRGB(152, 160, 172)
local FILLED_SLOT_TINT = Color3.fromRGB(255, 255, 255)
local SELECTED_SLOT_TINT = Color3.fromRGB(142, 220, 255)
local DISABLED_SLOT_TINT = Color3.fromRGB(100, 108, 120)
local EXPANSION_VISIBILITY_EPSILON = 0.001
local TRASH_VISIBILITY_EPSILON = 0.001
type HoveredSlotSource = "Hotbar" | "Grid"
type UiSoundTemplateCache = {
	hover: string?,
	press: string?,
	resolved: boolean,
}
type DropRequestedSignal = {
	Connect: (
		self: DropRequestedSignal,
		callback: (slotIndex: number, slotGuiObject: GuiObject) -> ()
	) -> RBXScriptConnection,
	Fire: (self: DropRequestedSignal, slotIndex: number, slotGuiObject: GuiObject) -> (),
	Destroy: (self: DropRequestedSignal) -> (),
}

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

local uiSoundTemplateCache: UiSoundTemplateCache = {
	hover = nil,
	press = nil,
	resolved = false,
}

local DEFAULT_RENDER_INVENTORY_STATE = InventoryServiceUtils.createDefaultState(InventoryServiceUtils.LOAD_STATE_LOADING)

local function snapToPixel(value: number): number
	return math.floor(value + 0.5)
end

local function resolveUiSoundTemplates()
	if uiSoundTemplateCache.resolved then
		return
	end
	uiSoundTemplateCache.resolved = true

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

	local hover = uiFolder:FindFirstChild("UiHover")
	if hover ~= nil and hover:IsA("Sound") then
		uiSoundTemplateCache.hover = SoundServiceUtils.resolveSoundAssetId(hover)
	end

	local press = uiFolder:FindFirstChild("UiPress")
	if press ~= nil and press:IsA("Sound") then
		uiSoundTemplateCache.press = SoundServiceUtils.resolveSoundAssetId(press)
	end
end

local function playUiHoverSound()
	if SoundServiceClient.categoryGroups == nil then
		return
	end

	resolveUiSoundTemplates()
	local hoverAssetId = uiSoundTemplateCache.hover
	if hoverAssetId == nil then
		return
	end

	SoundServiceClient:playUi(hoverAssetId, {
		replaceChannel = false,
	})
end

local function playUiPressSound()
	if SoundServiceClient.categoryGroups == nil then
		return
	end

	resolveUiSoundTemplates()
	local pressAssetId = uiSoundTemplateCache.press
	if pressAssetId == nil then
		return
	end

	SoundServiceClient:playUi(pressAssetId, {
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
	local stack = if typeof(stackRaw) == "table" then (stackRaw :: InventoryItemStack) else nil
	local indexRaw = (slot :: any).index
	local index = if typeof(indexRaw) == "number" and indexRaw == indexRaw then math.max(1, math.floor(indexRaw)) else slotIndex
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

local function resolveLoadingInventoryText(dotCountRaw: number): string
	local dotCount = math.clamp(math.floor(dotCountRaw), 1, 3)
	return "Loading inventory" .. string.rep(".", dotCount)
end

local function resolveCursorGuiPosition(): Vector2?
	local success, mouseLocation = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if not success or typeof(mouseLocation) ~= "Vector2" then
		return nil
	end
	local topLeftInset = GuiService:GetGuiInset()
	return Vector2.new(math.max(0, mouseLocation.X - topLeftInset.X), math.max(0, mouseLocation.Y - topLeftInset.Y))
end

local function isSlotTopmostAtCursor(slotGuiObject: GuiObject): boolean
	if slotGuiObject.Parent == nil then
		return false
	end
	local cursorPosition = resolveCursorGuiPosition()
	if cursorPosition == nil then
		return false
	end
	local success, guiObjects = pcall(function()
		return GuiService:GetGuiObjectsAtPosition(math.floor(cursorPosition.X), math.floor(cursorPosition.Y))
	end)
	if not success or type(guiObjects) ~= "table" then
		return false
	end
	local topmost = guiObjects[1]
	if topmost == nil or not topmost:IsA("GuiObject") then
		return false
	end
	if topmost == slotGuiObject then
		return true
	end
	return topmost:IsDescendantOf(slotGuiObject)
end

return function(props: InventoryHotbarProps)
	local inventoryState, setInventoryState = React.useState(function(): InventoryState
		return inventorySlice.inventoryStateAtom()
	end)
	local renderState = sanitizeRenderState(inventoryState)
	local isInventoryStateInitialized = typeof(renderState.slots) == "table" and #renderState.slots >= math.max(1, renderState.capacity)
	local hoveredSlotIndex, setHoveredSlotIndex = React.useState(nil :: number?)
	local hoveredSlotSource, setHoveredSlotSource = React.useState(nil :: HoveredSlotSource?)
	local isExpandButtonPressed, setIsExpandButtonPressed = React.useState(false)
	local isInventoryExpanded, setIsInventoryExpanded = React.useState(false)
	local loadingDotCount, setLoadingDotCount = React.useState(1)
	local dropRequestedSignal = React.useMemo(function(): DropRequestedSignal
		return Signal.new()
	end, {})
	local drag = useDrag({
		hoveredSlotIndex = hoveredSlotIndex,
	})

	local expansionProgress = useInventorySlide({
		enabled = isInventoryExpanded,
	})

	React.useEffect(function()
		local stop = inventoryThunks.start()
		local unsubscribe = Charm.subscribe(inventorySlice.inventoryStateAtom, function(nextState: InventoryState)
			setInventoryState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
			stop()
		end
	end, {})

	React.useEffect(function()
		return function()
			dropRequestedSignal:Destroy()
		end
	end, { dropRequestedSignal })

	React.useEffect(function()
		if props.visible == false or not isInventoryExpanded then
			return
		end

		local dropRequestedConnection = dropRequestedSignal:Connect(function(slotIndex: number, slotGuiObject: GuiObject)
			if props.visible == false or not isInventoryExpanded then
				return
			end
			if not isInventoryStateInitialized then
				return
			end
			if UserInputService:GetFocusedTextBox() ~= nil then
				return
			end
			if not InventoryServiceUtils.isLoadedState(renderState.loadState) then
				return
			end
			if drag.isDragging then
				return
			end

			local maxInteractiveSlots = math.min(renderState.capacity, TOTAL_VISIBLE_SLOTS)
			if slotIndex < 1 or slotIndex > maxInteractiveSlots then
				return
			end

			local slot = resolveSlot(renderState, slotIndex)
			if slot.stack == nil then
				return
			end
			if slotGuiObject.Parent == nil then
				return
			end
			if not isSlotTopmostAtCursor(slotGuiObject) then
				return
			end

			task.defer(function()
				inventoryThunks.dropFromSlot(slotIndex, nil)
			end)
		end)

		return function()
			dropRequestedConnection:Disconnect()
		end
	end, {
		props.visible,
		isInventoryExpanded,
		renderState.loadState,
		renderState.capacity,
		renderState.updatedAt,
		drag.isDragging,
		dropRequestedSignal,
		isInventoryStateInitialized,
	})

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
			if inputObject.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if not isInventoryStateInitialized then
				return
			end
			if not InventoryServiceUtils.isLoadedState(renderState.loadState) then
				return
			end

			local selectedFromKey = KEYCODE_TO_SLOT_INDEX[inputObject.KeyCode]
			if selectedFromKey == nil then
				return
			end

			inventoryThunks.selectSlot(selectedFromKey)
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
	end, { props.visible, renderState.loadState, isInventoryStateInitialized })

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
		infoThunks.showHover({
			id = SLOT_HOVER_ID_PREFIX .. tostring(hoveredSlotIndex),
			text = resolveSlotHoverText(hoveredSlot),
		})
	end, { hoveredSlotIndex, hoveredSlotSource, renderState.updatedAt, renderState.capacity, isInventoryStateInitialized })

	React.useEffect(function()
		return function()
			infoThunks.hideHover(nil)
		end
	end, {})

	React.useEffect(function()
		local isLoading = not InventoryServiceUtils.isLoadedState(renderState.loadState)
			and renderState.loadState ~= InventoryServiceUtils.LOAD_STATE_FAILED
		if not isLoading then
			setLoadingDotCount(1)
			return
		end

		local cancelled = false
		task.spawn(function()
			while not cancelled do
				task.wait(0.4)
				if cancelled then
					return
				end
				setLoadingDotCount(function(currentDotCount: number): number
					return (currentDotCount % 3) + 1
				end)
			end
		end)

		return function()
			cancelled = true
		end
	end, { renderState.loadState })

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
		enabled = isInventoryExpanded,
		fromOffset = Vector2.new(-(gridContainerWidth + gridGap), 0),
		toOffset = Vector2.zero,
	})
	local trashAppear = useTrashAppear({
		enabled = isInventoryExpanded,
		fromOffset = Vector2.new(-(hotbarSlotSize.X.Offset * 0.65), 0),
		toOffset = Vector2.zero,
	})
	local showExpandedGrid = isInventoryExpanded or expansionProgress > EXPANSION_VISIBILITY_EPSILON
	local showRevealOverlay = showExpandedGrid and expansionProgress < (1 - EXPANSION_VISIBILITY_EPSILON)
	local showTrashScreen = isInventoryExpanded or trashAppear.progress > TRASH_VISIBILITY_EPSILON
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
	local hotbarSlotScales: { number } = table.create(HOTBAR_SLOT_COUNT)

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
		local stack = slot.stack
		local isSlotAvailable = isInventoryStateInitialized and hotbarIndex <= maxInteractiveSlots
		local hasItem = isSlotAvailable and typeof(stack) == "table"
		local isSelected = selectedSlot == hotbarIndex
		local isDragSourceSlot = drag.isDragging and drag.dragSourceSlot == hotbarIndex
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
		local itemAmount = if hasVisibleItem then resolveStackAmount(stack) else 0
		local itemIcon = if hasVisibleItem then resolveStackIcon(stack) else nil

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
			[React.Event.InputBegan] = function(slotButton: GuiObject, inputObject: InputObject)
				if not isSlotAvailable then
					return
				end
				local userInputType = inputObject.UserInputType
				if userInputType == Enum.UserInputType.MouseButton2 then
					if props.visible == false or not isInventoryExpanded then
						return
					end
					if UserInputService:GetFocusedTextBox() ~= nil then
						return
					end
					if slotButton == nil or slotButton.Parent == nil then
						return
					end
					dropRequestedSignal:Fire(hotbarIndex, slotButton)
					return
				end
				if userInputType ~= Enum.UserInputType.MouseButton1 and userInputType ~= Enum.UserInputType.Touch then
					return
				end
				drag.handleSlotInput(hotbarIndex, if typeof(stack) == "table" then stack else nil, inputObject)
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
		icon = if isExpandButtonPressed or isInventoryExpanded
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
		selected = isInventoryExpanded,
		onPressedChanged = function(isPressed: boolean)
			setIsExpandButtonPressed(isPressed)
		end,
		onHoverChanged = function(isHovered: boolean)
			if isHovered then
				playUiHoverSound()
			end
		end,
		onActivated = function()
			playUiPressSound()
			setIsInventoryExpanded(not isInventoryExpanded)
		end,
	})

	hotbarChildren.CraftButton = e(CraftButton, {
		layoutOrder = HOTBAR_SLOT_COUNT + 2,
		size = expanderSize,
		zIndex = zIndex + 4,
	})

	local gridChildren: { [string]: React.ReactNode } = {
		GridLayout = e("UIGridLayout", {
			CellSize = gridSlotSize,
			CellPadding = UDim2.fromOffset(gridGap, gridGap),
			FillDirectionMaxCells = INVENTORY_COLUMNS,
			StartCorner = Enum.StartCorner.TopLeft,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	}

	for slotIndex = 1, INVENTORY_MAX_SLOTS do
		local inventorySlotIndex = GRID_SLOT_START_INDEX + slotIndex - 1
		local slot = resolveSlot(renderState, inventorySlotIndex)
		local stack = slot.stack
		local isSlotAvailable = isInventoryStateInitialized and inventorySlotIndex <= maxInteractiveSlots
		local hasItem = isSlotAvailable and typeof(stack) == "table"
		local isSelected = isSlotAvailable and selectedSlot == inventorySlotIndex
		local isDragSourceSlot = drag.isDragging and drag.dragSourceSlot == inventorySlotIndex
		local hasVisibleItem = hasItem and not isDragSourceSlot
		local isHovered = hoveredSlotSource == "Grid" and hoveredSlotIndex == inventorySlotIndex
		local columnIndex = ((slotIndex - 1) % INVENTORY_COLUMNS) + 1
		local columnRevealProgress = resolveColumnRevealProgress(expansionProgress, columnIndex, INVENTORY_COLUMNS)
		local columnRevealTransparency = 1 - columnRevealProgress
		local slotTint = if not isSlotAvailable
			then DISABLED_SLOT_TINT
			else if isSelected then SELECTED_SLOT_TINT else if hasVisibleItem then FILLED_SLOT_TINT else EMPTY_SLOT_TINT
		local slotImage = if isSelected or isHovered then ImageIds.inventorySlotHovered else ImageIds.inventorySlot
		local itemAmount = if hasVisibleItem then resolveStackAmount(stack) else 0
		local slotZIndex = zIndex + 3
		local slotBaseTransparency = if isSlotAvailable then 0 else 0.15
		local slotTransparency =
			math.clamp(slotBaseTransparency + columnRevealTransparency * (1 - slotBaseTransparency), 0, 1)
		local itemIcon = if hasVisibleItem then resolveStackIcon(stack) else nil

		gridChildren["GridSlot_" .. tostring(slotIndex)] = e("ImageButton", {
			Name = "GridSlot_" .. tostring(slotIndex),
			Size = gridSlotSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = slotImage,
			ImageColor3 = slotTint,
			ImageTransparency = slotTransparency,
			LayoutOrder = slotIndex,
			ZIndex = slotZIndex,
			AutoButtonColor = false,
			Active = isSlotAvailable,
			Selectable = isSlotAvailable,
			[React.Event.MouseEnter] = function()
				if not isSlotAvailable then
					return
				end
				setHoveredSlotSource("Grid")
				setHoveredSlotIndex(inventorySlotIndex)
				playUiHoverSound()
			end,
			[React.Event.MouseLeave] = function()
				if isSlotAvailable then
					setHoveredSlotSource(nil)
					setHoveredSlotIndex(nil)
					infoThunks.hideHover(SLOT_HOVER_ID_PREFIX .. tostring(inventorySlotIndex))
				end
			end,
			[React.Event.InputBegan] = function(slotButton: GuiObject, inputObject: InputObject)
				if not isSlotAvailable then
					return
				end
				local userInputType = inputObject.UserInputType
				if userInputType == Enum.UserInputType.MouseButton2 then
					if props.visible == false or not isInventoryExpanded then
						return
					end
					if UserInputService:GetFocusedTextBox() ~= nil then
						return
					end
					if slotButton == nil or slotButton.Parent == nil then
						return
					end
					dropRequestedSignal:Fire(inventorySlotIndex, slotButton)
					return
				end
				if userInputType ~= Enum.UserInputType.MouseButton1 and userInputType ~= Enum.UserInputType.Touch then
					return
				end
				drag.handleSlotInput(inventorySlotIndex, if typeof(stack) == "table" then stack else nil, inputObject)
			end,
			[React.Event.Activated] = function()
				if not isSlotAvailable then
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
