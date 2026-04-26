--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GuiUtils = require(script.Parent.internal.gui)
local React = require(ReplicatedStorage.Packages.React)
local useStableCallback = require(script.Parent.internal.useStableCallback)

export type RefObject<T> = {
	current: T,
}

export type ClickOutsideOptions = {
	ref: RefObject<GuiObject?>?,
	ignoreRefs: { RefObject<GuiObject?> }?,
	enabled: boolean?,
	inputTypes: { Enum.UserInputType }?,
	onClickOutside: ((InputObject, Vector2) -> ())?,
	onClickInside: ((InputObject, Vector2) -> ())?,
}

export type ClickOutsideResult = {
	ref: RefObject<GuiObject?>,
	lastInteractionInside: boolean,
}

local DEFAULT_INPUT_TYPES = {
	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.Touch,
}

local EMPTY_IGNORE_REFS = {} :: { RefObject<GuiObject?> }

local function matchesInputType(inputObject: InputObject, inputTypesRaw: { Enum.UserInputType }?): boolean
	local inputTypes = if type(inputTypesRaw) == "table" and #inputTypesRaw > 0
		then inputTypesRaw
		else DEFAULT_INPUT_TYPES
	for _, inputType in inputTypes do
		if inputObject.UserInputType == inputType then
			return true
		end
	end
	return false
end

local function isWithinRefs(
	guiObjects: { GuiObject },
	target: GuiObject,
	ignoreRefs: { RefObject<GuiObject?> },
	screenPosition: Vector2
): boolean
	for _, guiObject in guiObjects do
		if GuiUtils.IsDescendantOf(guiObject, target) then
			return true
		end
		for _, ignoreRef in ignoreRefs do
			if ignoreRef.current ~= nil and GuiUtils.IsDescendantOf(guiObject, ignoreRef.current) then
				return true
			end
		end
	end

	if GuiUtils.IsPointInsideGui(target, screenPosition) then
		return true
	end
	for _, ignoreRef in ignoreRefs do
		if ignoreRef.current ~= nil and GuiUtils.IsPointInsideGui(ignoreRef.current, screenPosition) then
			return true
		end
	end

	return false
end

local function useClickOutside(options: ClickOutsideOptions?): ClickOutsideResult
	local internalRef = React.useRef(nil :: GuiObject?) :: RefObject<GuiObject?>
	local targetRef = if options ~= nil and options.ref ~= nil then options.ref else internalRef
	local ignoreRefs = if options ~= nil and options.ignoreRefs ~= nil then options.ignoreRefs else EMPTY_IGNORE_REFS
	local enabled = if options ~= nil and options.enabled ~= nil then options.enabled == true else true
	local inputTypes = if options ~= nil then options.inputTypes else nil
	local onClickOutside = useStableCallback(if options ~= nil then options.onClickOutside else nil)
	local onClickInside = useStableCallback(if options ~= nil then options.onClickInside else nil)
	local lastInteractionInside, setLastInteractionInside = React.useState(false)

	React.useEffect(function()
		if not enabled then
			setLastInteractionInside(false)
			return
		end

		local connection = UserInputService.InputBegan:Connect(function(inputObject: InputObject)
			if not matchesInputType(inputObject, inputTypes) then
				return
			end

			local target = targetRef.current
			if target == nil then
				return
			end

			local screenPosition = GuiUtils.ResolveScreenPositionFromInput(inputObject)
			if screenPosition == nil then
				return
			end

			local guiObjects = GuiUtils.GetGuiObjectsAtPosition(screenPosition)
			local isInside = isWithinRefs(guiObjects, target, ignoreRefs, screenPosition)
			setLastInteractionInside(isInside)
			if isInside then
				onClickInside(inputObject, screenPosition)
			else
				onClickOutside(inputObject, screenPosition)
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, { enabled, targetRef, ignoreRefs, inputTypes, onClickInside, onClickOutside })

	return {
		ref = targetRef,
		lastInteractionInside = lastInteractionInside,
	}
end

return useClickOutside
