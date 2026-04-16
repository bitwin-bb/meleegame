--!strict
local Players = game:GetService("Players")

local PortalTargets = {}

local UI_ROOT_NAME = "ui"

function PortalTargets.ResolveUiScreenGui(): ScreenGui?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end

	local screenGui = playerGui:FindFirstChild(UI_ROOT_NAME)
	if screenGui ~= nil and screenGui:IsA("ScreenGui") then
		return screenGui
	end

	return nil
end

PortalTargets.resolveUiScreenGui = PortalTargets.ResolveUiScreenGui

return PortalTargets
