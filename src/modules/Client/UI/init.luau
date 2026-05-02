local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RootUI = require(script:FindFirstAncestor("game").Client.UI.app.RootUI)
local SnackbarNotifications = require(script:FindFirstAncestor("game").Client.SnackbarNotifications)

local e: typeof(React.createElement) = React.createElement

local UI_ROOT_NAME = "App"
local LEGACY_UI_ROOT_NAME = "ui"
local UI_CANVAS_NAME = "uiCanvas"
local UI_CANVAS_ASPECT_RATIO_NAME = "uiCanvasAspectRatio"
local UI_CANVAS_ASPECT_RATIO = 16 / 9

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

local function ensureUiCanvas(parent: ScreenGui): Frame
	local existing = parent:FindFirstChild(UI_CANVAS_NAME)
	if existing ~= nil and existing:IsA("Frame") then
		existing.AnchorPoint = Vector2.new(0.5, 0.5)
		existing.Position = UDim2.fromScale(0.5, 0.5)
		existing.Size = UDim2.fromScale(1, 1)
		existing.Active = false
		existing.Selectable = false
		return existing
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local canvas = Instance.new("Frame")
	canvas.Name = UI_CANVAS_NAME
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Active = false
	canvas.Selectable = false
	canvas.Parent = parent
	return canvas
end

local function ensureUiCanvasAspectRatio(parent: Frame): UIAspectRatioConstraint
	local existing = parent:FindFirstChild(UI_CANVAS_ASPECT_RATIO_NAME)
	if existing ~= nil and existing:IsA("UIAspectRatioConstraint") then
		existing.AspectRatio = UI_CANVAS_ASPECT_RATIO
		return existing
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local aspectRatio = Instance.new("UIAspectRatioConstraint")
	aspectRatio.Name = UI_CANVAS_ASPECT_RATIO_NAME
	aspectRatio.AspectRatio = UI_CANVAS_ASPECT_RATIO
	aspectRatio.Parent = parent
	return aspectRatio
end

local uiRoot = ensureUiRoot()
local uiCanvas = ensureUiCanvas(uiRoot)
ensureUiCanvasAspectRatio(uiCanvas)
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
