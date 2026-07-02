local require = (require :: any)(
		game:GetService("ServerScriptService"):FindFirstChild("LoaderUtils", true).Parent
	).bootstrapStory(script) :: typeof(require(script.Parent.loader).load(script))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RootUI = require("RootUI")

local e: typeof(React.createElement) = React.createElement

local STORY_ROOT_NAME = "RootStoryUI"

local function GetMountTarget(target: Instance): ScreenGui
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
	local mountTarget = GetMountTarget(target)
	local root = ReactRoblox.createRoot(mountTarget)

	root:render(e(RootUI, {
		currentScreen = nil,
	}))

	return function()
		root:unmount()
		if mountTarget.Name == STORY_ROOT_NAME and mountTarget.Parent ~= nil then
			mountTarget:Destroy()
		end
	end
end
