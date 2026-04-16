local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local HUD = require(script:FindFirstAncestor("game").Client.UI.hud)
local InfoScreen = require(script:FindFirstAncestor("game").Client.UI.features.info.screens.infoScreen)
local InfoPlayerScreen = require(script:FindFirstAncestor("game").Client.UI.features.infoPlayer.screens.infoPlayerScreen)
local EntityInfoScreen = require(script:FindFirstAncestor("game").Client.UI.features.entityInfo.screens.entityInfoScreen)
local MarkerScreen = require(script:FindFirstAncestor("game").Client.UI.features.bossMarker.screens.markerScreen)
local BiomeNameScreen = require(script:FindFirstAncestor("game").Client.UI.features.biome.screens.biomeNameScreen)
local DeathScreen = require(script:FindFirstAncestor("game").Client.UI.features.death.screens.deathScreen)
local MiningProgressScreen = require(script:FindFirstAncestor("game").Client.UI.features.miningProgress.screens.miningProgressScreen)
local CraftingSlotsScreen = require(script:FindFirstAncestor("game").Client.UI.features.crafting.screens.craftingSlots)
local BindingHintScreen = require(script:FindFirstAncestor("game").Client.UI.features.bindingHint.screens.bindingHintScreen)
local MouseScreen = require(script:FindFirstAncestor("game").Client.UI.features.mouse.screen.mouseScreen)

type RootUIProps = {
	currentScreen: React.ReactElement<any, any>?,
	hudProps: { [string]: any }?,
}

return function(props: RootUIProps)
	return React.createElement(React.Fragment, nil, {
		HUD = React.createElement(HUD, props.hudProps),
		CurrentScreen = props.currentScreen,
		InfoScreen = React.createElement(InfoScreen, {
			zIndex = 140,
		}),
		InfoPlayerScreen = React.createElement(InfoPlayerScreen, {
			zIndex = 145,
		}),
		BiomeNameScreen = React.createElement(BiomeNameScreen, {
			zIndex = 150,
		}),
		EntityInfoScreen = React.createElement(EntityInfoScreen, {
			zIndex = 160,
		}),
		MarkerScreen = React.createElement(MarkerScreen, {
			zIndex = 165,
		}),
		MiningProgressScreen = React.createElement(MiningProgressScreen, {
			zIndex = 170,
		}),
		CraftingSlotsScreen = React.createElement(CraftingSlotsScreen, {
			zIndex = 175,
		}),
		BindingHintScreen = React.createElement(BindingHintScreen, {
			zIndex = 180,
		}),
		MouseScreen = React.createElement(MouseScreen, {
			zIndex = 1000,
		}),
		DeathScreen = React.createElement(DeathScreen, {
			zIndex = 230,
		}),
	})
end
