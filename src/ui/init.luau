local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RootUI = require(ReplicatedStorage.UI.app.RootUI)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local React = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

local root = ReactRoblox.createRoot(playerGui)

return function()
	root:render(e(RootUI, {
		currentScreen = nil,
	}))

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(game) then
			root:unmount()
		end
	end)
end
