local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RootUI = require(ReplicatedStorage.UI.app.RootUI)
local HpServiceUtils = require(ReplicatedStorage.Shared.Services.HpService.HpServiceUtils)
local ManaServiceUtils = require(ReplicatedStorage.Shared.Services.ManaService.ManaServiceUtils)

local e: typeof(React.createElement) = React.createElement

local STORY_ROOT_NAME = "RootStoryUI"

local function resolveMountTarget(target: Instance): ScreenGui
	if target:IsA("ScreenGui") then
		return target
	end

	local existing = target:FindFirstChild(STORY_ROOT_NAME)
	if existing ~= nil and existing:IsA("ScreenGui") then
		return existing
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = STORY_ROOT_NAME
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = target
	return screenGui
end

return function(target)
	local mountTarget = resolveMountTarget(target)
	local root = ReactRoblox.createRoot(mountTarget)
	local mockHpState = HpServiceUtils.createState(78, 100, 20)
	local mockManaState = ManaServiceUtils.createState(17, 20, 0, true, nil)

	root:render(e(RootUI, {
		currentScreen = nil,
		hudProps = {
			hpBarProps = {
				useServiceState = false,
				mockState = mockHpState,
				mockReady = true,
			},
			manaBarProps = {
				useServiceState = false,
				mockState = mockManaState,
				mockReady = true,
			},
		},
	}))

	return function()
		root:unmount()
		if mountTarget.Name == STORY_ROOT_NAME and mountTarget.Parent ~= nil then
			mountTarget:Destroy()
		end
	end
end
