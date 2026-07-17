local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require("Maid")
local PlatformServiceClient = require("PlatformServiceClient")
local React: any = require(ReplicatedStorage.Packages.React)
local ReactRoblox: any = require(ReplicatedStorage.Packages.ReactRoblox)
local RootUI = require("RootUI")
local ServiceBag = require("ServiceBag")
local SnackbarNotifications = require("FeatureSnackbarNotifications")

local e: typeof(React.createElement) = React.createElement

local UI_ROOT_NAME = "App"
local LEGACY_UI_ROOT_NAME = "ui"

local UI = {}
UI.ServiceName = "UI"

local function configureUiRoot(rootGui: ScreenGui): ScreenGui
	rootGui.ResetOnSpawn = false
	rootGui.IgnoreGuiInset = true
	rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return rootGui
end

local function ensureUiRoot(playerGui: PlayerGui): ScreenGui
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

function UI.Init(self: any, serviceBag: ServiceBag.ServiceBag)
	assert(self._serviceBag == nil, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function UI.Start(self: any)
	local maid = assert(self._maid, "Not initialized")
	maid:GiveTask(task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
		if self._maid ~= maid or not playerGui:IsA("PlayerGui") then
			return
		end

		local uiRoot = ensureUiRoot(playerGui)
		local root = ReactRoblox.createRoot(uiRoot)
		self._uiRoot = uiRoot
		self._root = root

		PlatformServiceClient:SetScreenGui(uiRoot)
		SnackbarNotifications.AttachToScreenGui(uiRoot)
		root:render(e(RootUI, {
			currentScreen = nil,
			onCanvasMounted = function(canvas: Frame)
				PlatformServiceClient:SetScaleTarget(canvas)
			end,
		}))

		maid:GiveTask(player.AncestryChanged:Connect(function()
			if not player:IsDescendantOf(game) then
				self:Destroy()
			end
		end))
		maid:GiveTask(function()
			root:unmount()
			if uiRoot.Parent ~= nil then
				uiRoot:Destroy()
			end
		end)
	end))
end

function UI.Destroy(self: any)
	if self._maid ~= nil then
		self._maid:DoCleaning()
	end
	self._maid = nil
	self._serviceBag = nil
	self._uiRoot = nil
	self._root = nil
end

return UI
