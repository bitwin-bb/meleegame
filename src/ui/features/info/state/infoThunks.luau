local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local infoState = require(ReplicatedStorage.UI.features.info.state.infoState)
local Input = require(ReplicatedStorage.Shared.Modules.Platform.Input)
local CoreRuntime = require(ReplicatedStorage.Shared.Modules.Core.Runtime)

type HoverInfoState = infoState.HoverInfoState

export type ShowHoverPayload = {
	id: string?,
	text: string,
	mousePosition: Vector2?,
}

local infoThunks = {}
local POINTER_TRACK_ACTION = "UI.InfoHover.TrackPointer"

local runtime = {
	started = false,
	inputChangedConnection = nil :: RBXScriptConnection?,
	inputRouter = nil :: any?,
	ownsInputRouter = false,
	pointerActionBound = false,
}

local function toGuiPosition(screenPosition: Vector2): Vector2
	local topLeftInset, _ = GuiService:GetGuiInset()
	return Vector2.new(math.max(0, screenPosition.X - topLeftInset.X), math.max(0, screenPosition.Y - topLeftInset.Y))
end

local function resolveMousePosition(fallback: Vector2?): Vector2
	if fallback ~= nil then
		return toGuiPosition(fallback)
	end

	local success, mousePosition = pcall(function()
		return UserInputService:GetMouseLocation()
	end)

	if success and typeof(mousePosition) == "Vector2" then
		return toGuiPosition(mousePosition)
	end

	return infoState.getInfoState().mousePosition
end

local function shouldTrackInput(inputObject: InputObject): boolean
	return inputObject.UserInputType == Enum.UserInputType.MouseMovement
		or inputObject.UserInputType == Enum.UserInputType.Touch
end

local function bindPointerTrackingWithInputModule(): boolean
	local inputRouter = runtime.inputRouter
	if inputRouter == nil then
		local sharedRuntime = CoreRuntime.getClientRuntime()
		local sharedInput = if sharedRuntime ~= nil then (sharedRuntime :: any).input else nil
		if sharedInput ~= nil then
			inputRouter = sharedInput
			runtime.ownsInputRouter = false
		else
			inputRouter = Input.new()
			runtime.ownsInputRouter = true
		end
		runtime.inputRouter = inputRouter
		if typeof((inputRouter :: any).init) == "function" then
			local inputRouterAny = inputRouter :: any
			inputRouterAny:init()
		end
	end

	if runtime.pointerActionBound then
		return true
	end
	if typeof((inputRouter :: any).bindAction) ~= "function" then
		return false
	end

	local bound = (inputRouter :: any):bindAction(POINTER_TRACK_ACTION, function(phase: string, context: any)
		if phase ~= "Changed" and phase ~= "Began" then
			return false
		end
		local inputObject = if typeof(context) == "table" then context.input else nil
		if typeof(inputObject) == "InputObject" and shouldTrackInput(inputObject) then
			infoState.updateMousePosition(toGuiPosition((inputObject :: InputObject).Position))
		end
		return false
	end, {
		layer = "UI",
		consume = false,
		allowGameProcessed = true,
		allowWhileTyping = true,
		bindings = {
			{
				inputType = Enum.UserInputType.MouseMovement,
			},
			{
				inputType = Enum.UserInputType.Touch,
			},
		},
	})

	if bound == true then
		runtime.pointerActionBound = true
		return true
	end

	return false
end

local function unbindPointerTrackingWithInputModule()
	local inputRouter = runtime.inputRouter
	if inputRouter ~= nil and runtime.pointerActionBound and typeof((inputRouter :: any).unbindAction) == "function" then
		local inputRouterAny = inputRouter :: any
		inputRouterAny:unbindAction(POINTER_TRACK_ACTION)
	end
	runtime.pointerActionBound = false

	if runtime.ownsInputRouter and inputRouter ~= nil and typeof((inputRouter :: any).destroy) == "function" then
		local inputRouterAny = inputRouter :: any
		inputRouterAny:destroy()
	end
	runtime.ownsInputRouter = false
	runtime.inputRouter = nil
end

function infoThunks.start(): () -> ()
	if runtime.started then
		return infoThunks.stop
	end

	runtime.started = true
	local boundWithInputModule = bindPointerTrackingWithInputModule()
	if not boundWithInputModule then
		runtime.inputChangedConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			if shouldTrackInput(inputObject) then
				infoState.updateMousePosition(toGuiPosition(inputObject.Position))
			end
		end)
	end

	return infoThunks.stop
end

function infoThunks.stop()
	ConnectionUtils.disconnect(runtime.inputChangedConnection)
	runtime.inputChangedConnection = nil
	unbindPointerTrackingWithInputModule()
	runtime.started = false
end

function infoThunks.showHover(payload: ShowHoverPayload): HoverInfoState
	infoThunks.start()
	return infoState.showHover(payload.id, payload.text, resolveMousePosition(payload.mousePosition))
end

function infoThunks.hideHover(hoverId: string?): HoverInfoState
	return infoState.hideHover(hoverId)
end

function infoThunks.updateMousePosition(mousePosition: Vector2): HoverInfoState
	return infoState.updateMousePosition(mousePosition)
end

function infoThunks.syncMousePosition(): HoverInfoState
	return infoState.updateMousePosition(resolveMousePosition(nil))
end

function infoThunks.getInfoState(): HoverInfoState
	return infoState.getInfoState()
end

function infoThunks.reset()
	infoThunks.stop()
	infoState.resetInfoState()
end

return infoThunks
