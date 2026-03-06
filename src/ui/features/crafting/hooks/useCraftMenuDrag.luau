--!strict
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type CraftMenuDragOptions = {
	enabled: boolean?,
	dragSmoothness: number?,
}

export type CraftMenuDragResult = {
	offset: Vector2,
	isDragging: boolean,
	onDragInputBegan: (rbx: GuiObject, inputObject: InputObject) -> (),
	onDragInputEnded: (rbx: GuiObject, inputObject: InputObject) -> (),
}

local DEFAULT_DRAG_SMOOTHNESS = 5
local SNAP_EPSILON = 0.025

local function toGuiPosition(inputObject: InputObject): Vector2
	local inset = GuiService:GetGuiInset()
	local inputPosition = inputObject.Position
	return Vector2.new(inputPosition.X - inset.X, inputPosition.Y - inset.Y)
end

local function isPrimaryDragInput(inputObject: InputObject): boolean
	return inputObject.UserInputType == Enum.UserInputType.MouseButton1
		or inputObject.UserInputType == Enum.UserInputType.Touch
end

local function useCraftMenuDrag(options: CraftMenuDragOptions?): CraftMenuDragResult
	local enabled = if options and options.enabled ~= nil then options.enabled else false
	local dragSmoothness = math.clamp(
		if options and typeof(options.dragSmoothness) == "number" and options.dragSmoothness == options.dragSmoothness
			then options.dragSmoothness
			else DEFAULT_DRAG_SMOOTHNESS,
		1,
		120
	)

	local isDragging, setIsDragging = React.useState(false)
	local offset, setOffset = React.useState(Vector2.zero)
	local offsetRef = React.useRef(Vector2.zero)
	local targetOffsetRef = React.useRef(Vector2.zero)
	local dragInputRef = React.useRef(nil :: InputObject?)
	local dragStartPointerRef = React.useRef(Vector2.zero)
	local dragStartOffsetRef = React.useRef(Vector2.zero)
	local wasEnabledRef = React.useRef(enabled)

	React.useEffect(function()
		offsetRef.current = offset
	end, { offset })

	React.useEffect(function()
		local wasEnabled = wasEnabledRef.current
		wasEnabledRef.current = enabled

		if wasEnabled and not enabled then
			dragInputRef.current = nil
			setIsDragging(false)
			targetOffsetRef.current = offsetRef.current
		end
	end, { enabled })

	local onDragInputBegan = React.useCallback(function(_rbx: GuiObject, inputObject: InputObject)
		if not enabled or not isPrimaryDragInput(inputObject) then
			return
		end
		dragInputRef.current = inputObject
		dragStartPointerRef.current = toGuiPosition(inputObject)
		dragStartOffsetRef.current = targetOffsetRef.current
		setIsDragging(true)
	end, { enabled })

	local onDragInputEnded = React.useCallback(function(_rbx: GuiObject, inputObject: InputObject)
		local dragInput = dragInputRef.current
		if dragInput == nil then
			return
		end
		local isMatchingTouch = dragInput.UserInputType == Enum.UserInputType.Touch and inputObject == dragInput
		local isMatchingMouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and inputObject.UserInputType == Enum.UserInputType.MouseButton1
		if not isMatchingTouch and not isMatchingMouse then
			return
		end
		dragInputRef.current = nil
		setIsDragging(false)
	end, {})

	React.useEffect(function()
		local changedConnection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			if not enabled or not isDragging then
				return
			end

			local dragInput = dragInputRef.current
			if dragInput == nil then
				return
			end

			local isMatchingTouch = dragInput.UserInputType == Enum.UserInputType.Touch and inputObject == dragInput
			local isMouseMoveForDrag = dragInput.UserInputType == Enum.UserInputType.MouseButton1
				and inputObject.UserInputType == Enum.UserInputType.MouseMovement
			if not isMatchingTouch and not isMouseMoveForDrag then
				return
			end

			local pointerPosition = toGuiPosition(inputObject)
			local pointerDelta = pointerPosition - dragStartPointerRef.current
			targetOffsetRef.current = dragStartOffsetRef.current + pointerDelta
		end)

		local endedConnection = UserInputService.InputEnded:Connect(function(inputObject: InputObject)
			local dragInput = dragInputRef.current
			if dragInput == nil then
				return
			end

			local isMatchingTouch = dragInput.UserInputType == Enum.UserInputType.Touch and inputObject == dragInput
			local isMatchingMouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
				and inputObject.UserInputType == Enum.UserInputType.MouseButton1
			if not isMatchingTouch and not isMatchingMouse then
				return
			end

			dragInputRef.current = nil
			setIsDragging(false)
		end)

		return function()
			changedConnection:Disconnect()
			endedConnection:Disconnect()
		end
	end, { enabled, isDragging })

	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local currentOffset = offsetRef.current
			local targetOffset = targetOffsetRef.current
			local alpha = math.clamp(1 - math.exp(-dragSmoothness * math.max(0, deltaTime)), 0, 1)
			local nextOffset = currentOffset:Lerp(targetOffset, alpha)

			if (targetOffset - nextOffset).Magnitude <= SNAP_EPSILON then
				nextOffset = targetOffset
			end
			if (nextOffset - currentOffset).Magnitude <= SNAP_EPSILON then
				return
			end

			offsetRef.current = nextOffset
			setOffset(nextOffset)
		end)

		return function()
			connection:Disconnect()
		end
	end, { dragSmoothness })

	return {
		offset = offset,
		isDragging = isDragging,
		onDragInputBegan = onDragInputBegan,
		onDragInputEnded = onDragInputEnded,
	}
end

return useCraftMenuDrag
