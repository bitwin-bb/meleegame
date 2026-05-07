local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BindingHintScreen = require(script:FindFirstAncestor("game").Client.UI.features.binding.screens.bindingHintScreen)
local BiomeNameScreen = require(script:FindFirstAncestor("game").Client.UI.features.biome.screens.biomeNameScreen)
local CraftingSlotsScreen = require(script:FindFirstAncestor("game").Client.UI.features.crafting.screens.craftingSlots)
local DeathScreen = require(script:FindFirstAncestor("game").Client.UI.features.death.screens.deathScreen)
local EntityInfoScreen = require(script:FindFirstAncestor("game").Client.UI.features.entity.screens.entityInfoScreen)
local HUD = require(script:FindFirstAncestor("game").Client.UI.hud)
local InfoPlayerScreen = require(script:FindFirstAncestor("game").Client.UI.features.player.screens.infoPlayerScreen)
local InfoScreen = require(script:FindFirstAncestor("game").Client.UI.features.info.screens.infoScreen)
local MarkerScreen = require(script:FindFirstAncestor("game").Client.UI.features.boss.screens.markerScreen)
local MiningProgressScreen =
	require(script:FindFirstAncestor("game").Client.UI.features.mining.screens.miningProgressScreen)
local MouseScreen = require(script:FindFirstAncestor("game").Client.UI.features.mouse.screen.mouseScreen)
local PadScreen = require(script:FindFirstAncestor("game").Client.UI.features.pad.screens.pad)
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useViewportScale)

local e: typeof(React.createElement) = React.createElement

type RootUIProps = {
	currentScreen: React.ReactElement<any, any>?,
	hudProps: { [string]: any }?,
	onCanvasMounted: ((Frame) -> ())?,
}

return function(props: RootUIProps)
	local canvasRef = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local canvas = canvasRef.current
		if canvas ~= nil and props.onCanvasMounted ~= nil then
			props.onCanvasMounted(canvas)
		end
	end, { props.onCanvasMounted })

	return e(Responsive.Provider, {}, {
		RootCanvas = e("Frame", {
			ref = canvasRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			Selectable = false,
		}, {
			e(HUD, props.hudProps),
			props.currentScreen,
			e(InfoScreen, {
				zIndex = 140,
			}),
			e(InfoPlayerScreen, {
				zIndex = 145,
			}),
			e(BiomeNameScreen, {
				zIndex = 150,
			}),
			e(EntityInfoScreen, {
				zIndex = 160,
			}),
			e(MarkerScreen, {
				zIndex = 165,
			}),
			e(MiningProgressScreen, {
				zIndex = 170,
			}),
			e(CraftingSlotsScreen, {
				zIndex = 175,
			}),
			e(BindingHintScreen, {
				zIndex = 180,
			}),
			e(MouseScreen, {
				zIndex = 1000,
			}),
			e(PadScreen, {
				zIndex = 980,
			}),
			e(DeathScreen, {
				zIndex = 230,
			}),
		}),
	})
end
