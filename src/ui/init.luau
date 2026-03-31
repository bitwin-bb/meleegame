local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RootUI = require(ReplicatedStorage.UI.app.RootUI)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local React = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

local UI_ROOT_NAME = "ui"

local function ensureUiRoot(): ScreenGui
	local existing = playerGui:FindFirstChild(UI_ROOT_NAME)
	if existing ~= nil and existing:IsA("ScreenGui") then
		return existing
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local rootGui = Instance.new("ScreenGui")
	rootGui.Name = UI_ROOT_NAME
	rootGui.ResetOnSpawn = false
	rootGui.IgnoreGuiInset = true
	rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rootGui.Parent = playerGui
	return rootGui
end

local uiRoot = ensureUiRoot()
local root = ReactRoblox.createRoot(uiRoot)

return function()
	root:render(e(RootUI, {
		currentScreen = nil,
	}))

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(game) then
			root:unmount()
			if uiRoot.Parent ~= nil then
				uiRoot:Destroy()
			end
		end
	end)
end
