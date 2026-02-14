local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local LeftSideBar = require(ReplicatedStorage.UI.hud.LeftSideBar)
local TopBar = require(ReplicatedStorage.UI.hud.TopBar)

type RootUIProps = {
	currentScreen: React.ReactElement<any, any>?,
}

return function(props: RootUIProps)
	return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		LeftSideBar = React.createElement(LeftSideBar),
		TopBar = React.createElement(TopBar),
		CurrentScreen = props.currentScreen,
	})
end
