--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Cleanup = require(script.Parent.internal.cleanup)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local PlatformServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlatformServiceUtils)
local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

type PromptBinding = PlatformServiceUtils.PromptBinding
type ActionDefinition = PlatformServiceUtils.ActionDefinition

export type KeybindPhase = "Began" | "Changed" | "Ended"

export type KeybindContext = {
	phase: KeybindPhase,
	inputObject: InputObject?,
	keyCode: Enum.KeyCode?,
	inputType: Enum.UserInputType?,
	gameProcessed: boolean,
	actionContext: any?,
	prompt: PromptBinding?,
}

export type KeybindOptions = {
	enabled: boolean?,
	actionName: string?,
	keyCodes: { Enum.KeyCode }?,
	inputTypes: { Enum.UserInputType }?,
	captureProcessed: boolean?,
	overrideDefinition: ActionDefinition?,
	onTriggered: ((KeybindContext) -> ())?,
}

export type KeybindResult = {
	isPressed: boolean,
	prompt: PromptBinding?,
	lastContext: KeybindContext?,
}

local function keyCodeMatchesInput(inputObject: InputObject, keyCode: Enum.KeyCode): boolean
	if inputObject.KeyCode == keyCode then
		return true
	end

	if keyCode == Enum.KeyCode.MouseLeftButton then
		return inputObject.UserInputType == Enum.UserInputType.MouseButton1
	end
	if keyCode == Enum.KeyCode.MouseRightButton then
		return inputObject.UserInputType == Enum.UserInputType.MouseButton2
	end
	if keyCode == Enum.KeyCode.MouseMiddleButton then
		return inputObject.UserInputType == Enum.UserInputType.MouseButton3
	end

	return false
end

local function matchesConfiguredInput(
	inputObject: InputObject,
	keyCodesRaw: { Enum.KeyCode }?,
	inputTypesRaw: { Enum.UserInputType }?
): boolean
	local hasKeyCodes = type(keyCodesRaw) == "table" and #keyCodesRaw > 0
	local hasInputTypes = type(inputTypesRaw) == "table" and #inputTypesRaw > 0
	if not hasKeyCodes and not hasInputTypes then
		return false
	end

	if hasKeyCodes then
		for _, keyCode in keyCodesRaw :: { Enum.KeyCode } do
			if keyCodeMatchesInput(inputObject, keyCode) then
				return true
			end
		end
	end

	if hasInputTypes then
		for _, inputType in inputTypesRaw :: { Enum.UserInputType } do
			if inputObject.UserInputType == inputType then
				return true
			end
		end
	end

	return false
end

local function useKeybind(options: KeybindOptions?): KeybindResult
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local actionName = if options ~= nil then options.actionName else nil
	local keyCodes = if options ~= nil then options.keyCodes else nil
	local inputTypes = if options ~= nil then options.inputTypes else nil
	local captureProcessed = if options ~= nil and options.captureProcessed ~= nil
		then options.captureProcessed == true
		else false
	local overrideDefinition = if options ~= nil then options.overrideDefinition else nil
	local onTriggered = useStableCallback(if options ~= nil then options.onTriggered else nil)
	local isPressed, setIsPressed = React.useState(false)
	local prompt, setPrompt = React.useState(nil :: PromptBinding?)
	local lastContext, setLastContext = React.useState(nil :: KeybindContext?)

	React.useEffect(function()
		setIsPressed(false)
		setLastContext(nil)

		if not enabled then
			setPrompt(nil)
			return
		end

		if typeof(actionName) == "string" and actionName ~= "" then
			setPrompt(PlatformServiceClient:getPromptForAction(actionName))
			local promptSignal = PlatformServiceClient:getPromptSignal(actionName)
			local promptConnection = if promptSignal ~= nil
					and typeof((promptSignal :: any).Connect) == "function"
				then (promptSignal :: any):Connect(function(nextPrompt: PromptBinding?)
					setPrompt(nextPrompt)
				end)
				else nil

			local unbind = PlatformServiceClient:bindAction(
				actionName,
				function(phase: KeybindPhase, actionContext: any)
					local nextPrompt = PlatformServiceClient:getPromptForAction(actionName)
					local context: KeybindContext = {
						phase = phase,
						inputObject = if typeof((actionContext :: any).inputObject) == "InputObject"
							then (actionContext :: any).inputObject
							else nil,
						keyCode = if typeof((actionContext :: any).inputObject) == "InputObject"
							then ((actionContext :: any).inputObject :: InputObject).KeyCode
							else nil,
						inputType = if typeof((actionContext :: any).inputObject) == "InputObject"
							then ((actionContext :: any).inputObject :: InputObject).UserInputType
							else nil,
						gameProcessed = false,
						actionContext = actionContext,
						prompt = nextPrompt,
					}

					setPrompt(nextPrompt)
					setIsPressed(phase ~= "Ended")
					setLastContext(context)
					onTriggered(context)
				end,
				overrideDefinition
			)

			return function()
				setIsPressed(false)
				Cleanup.Call(unbind)
				Cleanup.Call(promptConnection)
			end
		end

		local function handlePhase(phase: KeybindPhase, inputObject: InputObject, gameProcessed: boolean)
			if gameProcessed and not captureProcessed then
				return
			end
			if not matchesConfiguredInput(inputObject, keyCodes, inputTypes) then
				return
			end

			local context: KeybindContext = {
				phase = phase,
				inputObject = inputObject,
				keyCode = inputObject.KeyCode,
				inputType = inputObject.UserInputType,
				gameProcessed = gameProcessed,
				actionContext = nil,
				prompt = nil,
			}

			setIsPressed(phase ~= "Ended")
			setLastContext(context)
			onTriggered(context)
		end

		local beganConnection = UserInputService.InputBegan:Connect(
			function(inputObject: InputObject, gameProcessed: boolean)
				handlePhase("Began", inputObject, gameProcessed)
			end
		)

		local changedConnection = UserInputService.InputChanged:Connect(
			function(inputObject: InputObject, gameProcessed: boolean)
				handlePhase("Changed", inputObject, gameProcessed)
			end
		)

		local endedConnection = UserInputService.InputEnded:Connect(
			function(inputObject: InputObject, gameProcessed: boolean)
				handlePhase("Ended", inputObject, gameProcessed)
			end
		)

		return function()
			setIsPressed(false)
			Cleanup.Call(beganConnection)
			Cleanup.Call(changedConnection)
			Cleanup.Call(endedConnection)
		end
	end, {
		enabled,
		actionName,
		keyCodes,
		inputTypes,
		captureProcessed,
		overrideDefinition,
		onTriggered,
	})

	return {
		isPressed = isPressed,
		prompt = prompt,
		lastContext = lastContext,
	}
end

return useKeybind
