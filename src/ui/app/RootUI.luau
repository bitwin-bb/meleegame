local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local HUD = require(ReplicatedStorage.UI.hud)
local InfoScreen = require(ReplicatedStorage.UI.features.info.screens.infoScreen)
local InfoPlayerScreen = require(ReplicatedStorage.UI.features.infoPlayer.screens.infoPlayerScreen)
local EntityInfoScreen = require(ReplicatedStorage.UI.features.entityInfo.screens.entityInfoScreen)
local BiomeNameScreen = require(ReplicatedStorage.UI.features.biome.screens.biomeNameScreen)
local DeathScreen = require(ReplicatedStorage.UI.features.death.screens.deathScreen)
local MiningProgressScreen = require(ReplicatedStorage.UI.features.miningProgress.screens.miningProgressScreen)
local CraftingSlotsScreen = require(ReplicatedStorage.UI.features.crafting.screens.craftingSlots)
local MouseScreen = require(ReplicatedStorage.UI.features.mouse.screen.mouseScreen)

type RootUIProps = {
	currentScreen: React.ReactElement<any, any>?,
	hudProps: { [string]: any }?,
}

return function(props: RootUIProps)
	return React.createElement("ScreenGui", {
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
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
		MiningProgressScreen = React.createElement(MiningProgressScreen, {
			zIndex = 170,
		}),
		CraftingSlotsScreen = React.createElement(CraftingSlotsScreen, {
			zIndex = 175,
		}),
		MouseScreen = React.createElement(MouseScreen, {
			zIndex = 220,
		}),
		DeathScreen = React.createElement(DeathScreen, {
			zIndex = 230,
		}),
	})
end
