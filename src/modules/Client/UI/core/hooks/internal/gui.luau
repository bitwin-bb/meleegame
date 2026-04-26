--!strict
local Players = game:GetService("Players")

local GuiUtils = {}

function GuiUtils.GetPlayerGui(): PlayerGui?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui ~= nil and playerGui:IsA("PlayerGui") then
		return playerGui
	end

	return nil
end

function GuiUtils.GetGuiObjectsAtPosition(screenPositionRaw: any): { GuiObject }
	if typeof(screenPositionRaw) ~= "Vector2" then
		return {}
	end

	local playerGui = GuiUtils.GetPlayerGui()
	if playerGui == nil then
		return {}
	end

	local success, guiObjects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(math.floor(screenPositionRaw.X), math.floor(screenPositionRaw.Y))
	end)
	if not success or type(guiObjects) ~= "table" then
		return {}
	end

	local output: { GuiObject } = {}
	for _, guiObject in guiObjects do
		if guiObject:IsA("GuiObject") then
			output[#output + 1] = guiObject
		end
	end
	return output
end

function GuiUtils.IsDescendantOf(targetRaw: any, ancestorRaw: any): boolean
	if typeof(targetRaw) ~= "Instance" or typeof(ancestorRaw) ~= "Instance" then
		return false
	end

	return (targetRaw :: Instance):IsDescendantOf(ancestorRaw :: Instance)
end

function GuiUtils.IsPointInsideGui(guiObjectRaw: any, screenPositionRaw: any): boolean
	if typeof(guiObjectRaw) ~= "Instance" or not (guiObjectRaw :: Instance):IsA("GuiObject") then
		return false
	end
	if typeof(screenPositionRaw) ~= "Vector2" then
		return false
	end

	local guiObject = guiObjectRaw :: GuiObject
	local position = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return screenPositionRaw.X >= position.X
		and screenPositionRaw.X <= position.X + size.X
		and screenPositionRaw.Y >= position.Y
		and screenPositionRaw.Y <= position.Y + size.Y
end

function GuiUtils.ResolveScreenPositionFromInput(inputObjectRaw: any): Vector2?
	if typeof(inputObjectRaw) ~= "InputObject" then
		return nil
	end

	local position = (inputObjectRaw :: InputObject).Position
	if typeof(position) == "Vector3" then
		return Vector2.new(position.X, position.Y)
	end
	if typeof(position) == "Vector2" then
		return position
	end
	return nil
end

GuiUtils.getPlayerGui = GuiUtils.GetPlayerGui
GuiUtils.getGuiObjectsAtPosition = GuiUtils.GetGuiObjectsAtPosition
GuiUtils.isDescendantOf = GuiUtils.IsDescendantOf
GuiUtils.isPointInsideGui = GuiUtils.IsPointInsideGui
GuiUtils.resolveScreenPositionFromInput = GuiUtils.ResolveScreenPositionFromInput

return GuiUtils
