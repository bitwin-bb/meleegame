local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RootUI = require(script:FindFirstAncestor("game").Client.Features.app.RootUI)
local SnackbarNotifications = require(script:FindFirstAncestor("game").Client.SnackbarNotifications)

local e: typeof(React.createElement) = React.createElement

local UI_ROOT_NAME = "App"
local LEGACY_UI_ROOT_NAME = "ui"

local function configureUiRoot(rootGui: ScreenGui): ScreenGui
	rootGui.ResetOnSpawn = false
	rootGui.IgnoreGuiInset = true
	rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return rootGui
end

local function ensureUiRoot(): ScreenGui
	local existing = playerGui:FindFirstChild(UI_ROOT_NAME)
	if existing ~= nil and existing:IsA("ScreenGui") then
		local legacy = playerGui:FindFirstChild(LEGACY_UI_ROOT_NAME)
		if legacy ~= nil and legacy ~= existing then
			legacy:Destroy()
		end

		return configureUiRoot(existing)
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local legacy = playerGui:FindFirstChild(LEGACY_UI_ROOT_NAME)
	if legacy ~= nil and legacy:IsA("ScreenGui") then
		legacy.Name = UI_ROOT_NAME
		return configureUiRoot(legacy)
	end

	if legacy ~= nil then
		legacy:Destroy()
	end

	local rootGui = Instance.new("ScreenGui")
	rootGui.Name = UI_ROOT_NAME
	configureUiRoot(rootGui)
	rootGui.Parent = playerGui
	return rootGui
end

local uiRoot = ensureUiRoot()
local root = ReactRoblox.createRoot(uiRoot)

return function()
	PlatformServiceClient:setScreenGui(uiRoot)
	SnackbarNotifications.attachToScreenGui(uiRoot)
	root:render(e(RootUI, {
		currentScreen = nil,
		onCanvasMounted = function(canvas: Frame)
			PlatformServiceClient:setScaleTarget(canvas)
		end,
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
