--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local mouseSlice = require(script:FindFirstAncestor("game").Client.UI.features.mouse.state.mouseSlice)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)

type MouseState = mouseSlice.MouseState

local mouseThunks = {}

local runtime = {
	started = false,
	defaultMouseIconEnabled = nil :: boolean?,
	inputChangedConnection = nil :: RBXScriptConnection?,
	inputBeganConnection = nil :: RBXScriptConnection?,
	inputEndedConnection = nil :: RBXScriptConnection?,
	lastInputTypeChangedConnection = nil :: RBXScriptConnection?,
	renderSteppedConnection = nil :: RBXScriptConnection?,
	platformDisconnect = nil :: (() -> ())?,
	usingSharedCursor = false,
	customCursorAllowed = false,
	cursor = nil :: any?,
	cursorDisconnect = nil :: (() -> ())?,
}

local function toGuiPosition(screenPosition: Vector2): Vector2
	return screenPosition
end

local function getPlayerGui(): PlayerGui?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui and playerGui:IsA("PlayerGui") then
		return playerGui
	end

	return nil
end

local function isMouseButtonInput(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
end

local function isMouseMovementInput(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch
end

local function isCustomCursorGui(guiObject: GuiObject): boolean
	local current: Instance? = guiObject
	while current do
		if current:GetAttribute("IsCustomMouseCursor") == true then
			return true
		end
		if CollectionService:HasTag(current, "IsCustomMouseCursor") then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isHoverTarget(guiObject: GuiObject): boolean
	if not guiObject.Visible then
		return false
	end
	if isCustomCursorGui(guiObject) then
		return false
	end
	if guiObject:IsA("GuiButton") then
		return true
	end
	if guiObject:IsA("TextBox") then
		return true
	end
	if guiObject.Active then
		return true
	end
	if guiObject.Selectable then
		return true
	end
	return false
end

local function resolveHoveredGuiObject(guiPosition: Vector2): GuiObject?
	local playerGui = getPlayerGui()
	if playerGui == nil then
		return nil
	end

	local success, guiObjects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(math.floor(guiPosition.X), math.floor(guiPosition.Y))
	end)
	if not success or type(guiObjects) ~= "table" then
		return nil
	end

	for _, guiObject in guiObjects do
		if guiObject:IsA("GuiObject") and isHoverTarget(guiObject) then
			return guiObject
		end
	end

	return nil
end

local function applyPointerStateFromCursorState(cursorStateRaw: any)
	if not runtime.customCursorAllowed then
		return
	end
	if typeof(cursorStateRaw) ~= "table" then
		return
	end
	local pointerPosition = if typeof(cursorStateRaw.screenPosition) == "Vector2"
		then cursorStateRaw.screenPosition
		else if typeof(cursorStateRaw.guiPosition) == "Vector2" then cursorStateRaw.guiPosition else Vector2.zero
	local isHoveringGui = cursorStateRaw.isHoveringGui == true
	local hoveredGuiPath = if typeof(cursorStateRaw.hoveredGuiPath) == "string" then cursorStateRaw.hoveredGuiPath else nil
	mouseSlice.setMouseVisible(cursorStateRaw.visible == true)
	mouseSlice.setMouseDown(cursorStateRaw.mouseDown == true)
	mouseSlice.updatePointer(pointerPosition, isHoveringGui, hoveredGuiPath)
end

local function applyPointerStateFromScreenPosition(screenPosition: Vector2)
	local guiPosition = toGuiPosition(screenPosition)
	local hoveredGui = resolveHoveredGuiObject(guiPosition)
	mouseSlice.updatePointer(guiPosition, hoveredGui ~= nil, if hoveredGui ~= nil then hoveredGui:GetFullName() else nil)
end

local function syncPointerFromMouseLocation()
	if not runtime.customCursorAllowed then
		return
	end
	local success, mouseLocation = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if success and typeof(mouseLocation) == "Vector2" then
		applyPointerStateFromScreenPosition(mouseLocation)
	end
end

local function applyVisibilityFromInputMode()
	if not runtime.customCursorAllowed then
		mouseSlice.setMouseVisible(false)
		mouseSlice.setMouseDown(false)
		return
	end
	local shouldShowMouse = UserInputService.MouseEnabled
	mouseSlice.setMouseVisible(shouldShowMouse)
	mouseSlice.setMouseDown(false)
end

local function bindSharedCursor(): boolean
	local runtimeContext = CoreRuntime.getClientRuntime()
	local cursor = if runtimeContext ~= nil then (runtimeContext :: any).cursor else nil
	if cursor == nil or typeof((cursor :: any).onChanged) ~= "function" then
		return false
	end

	runtime.cursor = cursor
	runtime.usingSharedCursor = true
	if typeof((cursor :: any).init) == "function" then
		local cursorAny = cursor :: any
		cursorAny:init()
	end
	runtime.cursorDisconnect = (cursor :: any):onChanged(function(nextState: any)
		applyPointerStateFromCursorState(nextState)
	end)
	if typeof((cursor :: any).setEnabled) == "function" then
		local cursorAny = cursor :: any
		cursorAny:setEnabled(runtime.customCursorAllowed)
	end
	if typeof((cursor :: any).sync) == "function" then
		local cursorAny = cursor :: any
		cursorAny:sync()
	end
	if typeof((cursor :: any).getState) == "function" then
		applyPointerStateFromCursorState((cursor :: any):getState())
	end
	return true
end

local function applyCursorPolicy()
	runtime.customCursorAllowed = PlatformServiceClient:shouldUseCustomCursor()
	local machineFamily = PlatformServiceClient:getMachineFamily()

	if runtime.usingSharedCursor and runtime.cursor ~= nil and typeof((runtime.cursor :: any).setEnabled) == "function" then
		local cursorAny = runtime.cursor :: any
		cursorAny:setEnabled(runtime.customCursorAllowed)
		if runtime.customCursorAllowed then
			if typeof((runtime.cursor :: any).sync) == "function" then
				cursorAny:sync()
			end
			if typeof((runtime.cursor :: any).getState) == "function" then
				applyPointerStateFromCursorState(cursorAny:getState())
			end
			return
		end
	end

	if runtime.customCursorAllowed then
		if not runtime.usingSharedCursor then
			UserInputService.MouseIconEnabled = false
		end
		applyVisibilityFromInputMode()
		syncPointerFromMouseLocation()
		return
	end

	if runtime.defaultMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = if machineFamily == "desktop" then runtime.defaultMouseIconEnabled else false
	else
		UserInputService.MouseIconEnabled = machineFamily == "desktop"
	end
	mouseSlice.setMouseVisible(false)
	mouseSlice.setMouseDown(false)
end

function mouseThunks.Start(): () -> ()
	if runtime.started then
		return mouseThunks.Stop
	end

	runtime.started = true
	if not PlatformServiceClient:isReady() then
		PlatformServiceClient:init()
	end
	runtime.defaultMouseIconEnabled = UserInputService.MouseIconEnabled

	if not bindSharedCursor() then
		runtime.inputChangedConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			if not runtime.started or not runtime.customCursorAllowed then
				return
			end
			if isMouseMovementInput(inputObject.UserInputType) then
				applyPointerStateFromScreenPosition(inputObject.Position)
			end
		end)

		runtime.inputBeganConnection = UserInputService.InputBegan:Connect(function(inputObject: InputObject)
			if not runtime.started or not runtime.customCursorAllowed then
				return
			end
			if isMouseButtonInput(inputObject.UserInputType) then
				local currentMouseState = mouseSlice.getMouseState()
				if currentMouseState.isHoveringGui then
					mouseSlice.setMouseDown(true)
				else
					mouseSlice.setMouseDown(false)
				end
				syncPointerFromMouseLocation()
			end
		end)

		runtime.inputEndedConnection = UserInputService.InputEnded:Connect(function(inputObject: InputObject)
			if not runtime.started or not runtime.customCursorAllowed then
				return
			end
			if isMouseButtonInput(inputObject.UserInputType) then
				mouseSlice.setMouseDown(false)
				syncPointerFromMouseLocation()
			end
		end)

		runtime.lastInputTypeChangedConnection = UserInputService.LastInputTypeChanged:Connect(function()
			if not runtime.started then
				return
			end
			applyVisibilityFromInputMode()
			syncPointerFromMouseLocation()
		end)

		runtime.renderSteppedConnection = RunService.RenderStepped:Connect(function()
			if not runtime.started or not runtime.customCursorAllowed then
				return
			end
			if not UserInputService.MouseEnabled then
				return
			end
			syncPointerFromMouseLocation()
		end)
	end

	runtime.platformDisconnect = PlatformServiceClient:onPlatformChanged(function()
		applyCursorPolicy()
	end)
	applyCursorPolicy()

	return mouseThunks.Stop
end

function mouseThunks.Stop()
	ConnectionUtils.call(runtime.platformDisconnect)
	runtime.platformDisconnect = nil

	if runtime.cursor ~= nil and typeof((runtime.cursor :: any).setEnabled) == "function" then
		local cursorAny = runtime.cursor :: any
		cursorAny:setEnabled(false)
	end
	ConnectionUtils.call(runtime.cursorDisconnect)
	runtime.cursorDisconnect = nil
	runtime.cursor = nil
	runtime.usingSharedCursor = false
	runtime.customCursorAllowed = false

	ConnectionUtils.disconnectMany({
		runtime.inputChangedConnection,
		runtime.inputBeganConnection,
		runtime.inputEndedConnection,
		runtime.lastInputTypeChangedConnection,
		runtime.renderSteppedConnection,
	})
	runtime.inputChangedConnection = nil
	runtime.inputBeganConnection = nil
	runtime.inputEndedConnection = nil
	runtime.lastInputTypeChangedConnection = nil
	runtime.renderSteppedConnection = nil

	if runtime.defaultMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = runtime.defaultMouseIconEnabled
	end
	runtime.defaultMouseIconEnabled = nil

	runtime.started = false
	mouseSlice.setMouseVisible(false)
	mouseSlice.resetMouseState()
end

function mouseThunks.SyncPointer()
	if runtime.usingSharedCursor and runtime.cursor ~= nil then
		if typeof((runtime.cursor :: any).sync) == "function" then
			local cursorAny = runtime.cursor :: any
			cursorAny:sync()
		end
		if typeof((runtime.cursor :: any).getState) == "function" then
			applyPointerStateFromCursorState((runtime.cursor :: any):getState())
		end
		return
	end
	syncPointerFromMouseLocation()
end

function mouseThunks.SetMouseDown(isMouseDown: boolean)
	if runtime.usingSharedCursor and runtime.cursor ~= nil and typeof((runtime.cursor :: any).setMouseDown) == "function" then
		local cursorAny = runtime.cursor :: any
		cursorAny:setMouseDown(isMouseDown)
	end
	mouseSlice.setMouseDown(isMouseDown)
end

function mouseThunks.GetMouseState(): MouseState
	return mouseSlice.getMouseState()
end

mouseThunks.start = mouseThunks.Start
mouseThunks.stop = mouseThunks.Stop
mouseThunks.syncPointer = mouseThunks.SyncPointer
mouseThunks.setMouseDown = mouseThunks.SetMouseDown
mouseThunks.getMouseState = mouseThunks.GetMouseState

return mouseThunks
