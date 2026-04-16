local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local infoState = require(script:FindFirstAncestor("game").Client.UI.features.info.state.infoState)
local Input = require(script:FindFirstAncestor("game").Shared.Modules.Platform.Input)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)

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
	return screenPosition
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

function infoThunks.Start(): () -> ()
	if runtime.started then
		return infoThunks.Stop
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

	return infoThunks.Stop
end

function infoThunks.Stop()
	ConnectionUtils.disconnect(runtime.inputChangedConnection)
	runtime.inputChangedConnection = nil
	unbindPointerTrackingWithInputModule()
	runtime.started = false
end

function infoThunks.ShowHover(payload: ShowHoverPayload): HoverInfoState
	infoThunks.Start()
	return infoState.showHover(payload.id, payload.text, resolveMousePosition(payload.mousePosition))
end

function infoThunks.HideHover(hoverId: string?): HoverInfoState
	return infoState.hideHover(hoverId)
end

function infoThunks.UpdateMousePosition(mousePosition: Vector2): HoverInfoState
	return infoState.updateMousePosition(mousePosition)
end

function infoThunks.SyncMousePosition(): HoverInfoState
	return infoState.updateMousePosition(resolveMousePosition(nil))
end

function infoThunks.GetInfoState(): HoverInfoState
	return infoState.getInfoState()
end

function infoThunks.Reset()
	infoThunks.Stop()
	infoState.resetInfoState()
end

infoThunks.start = infoThunks.Start
infoThunks.stop = infoThunks.Stop
infoThunks.showHover = infoThunks.ShowHover
infoThunks.hideHover = infoThunks.HideHover
infoThunks.updateMousePosition = infoThunks.UpdateMousePosition
infoThunks.syncMousePosition = infoThunks.SyncMousePosition
infoThunks.getInfoState = infoThunks.GetInfoState
infoThunks.reset = infoThunks.Reset

return infoThunks
