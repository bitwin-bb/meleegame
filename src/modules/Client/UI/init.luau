local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RootUI = require(script:FindFirstAncestor("game").Client.UI.app.RootUI)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local React = require(ReplicatedStorage.Packages.React)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local SnackbarNotifications = require(script:FindFirstAncestor("game").Client.SnackbarNotifications)

local e: typeof(React.createElement) = React.createElement

local UI_ROOT_NAME = "ui"
local UI_CANVAS_NAME = "uiCanvas"

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

local function ensureUiCanvas(parent: ScreenGui): Frame
	local existing = parent:FindFirstChild(UI_CANVAS_NAME)
	if existing ~= nil and existing:IsA("Frame") then
		return existing
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local canvas = Instance.new("Frame")
	canvas.Name = UI_CANVAS_NAME
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Position = UDim2.fromScale(0, 0)
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Parent = parent
	return canvas
end

local uiRoot = ensureUiRoot()
local uiCanvas = ensureUiCanvas(uiRoot)
local root = ReactRoblox.createRoot(uiCanvas)

return function()
	PlatformServiceClient:setScreenGui(uiRoot)
	PlatformServiceClient:setScaleTarget(uiCanvas)
	SnackbarNotifications.attachToScreenGui(uiRoot)
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
