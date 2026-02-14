local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RootUI = require(ReplicatedStorage.UI.app.RootUI)

local e: typeof(React.createElement) = React.createElement

return function(target)
	local root = ReactRoblox.createRoot(target)
	root:render(e(RootUI, {
		currentScreen = nil,
	}))

	return function()
		root:unmount()
	end
end
