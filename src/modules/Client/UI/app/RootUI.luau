local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local BindingHintScreen = require(script:FindFirstAncestor("game").Client.UI.features.binding.screens.bindingHintScreen)
local BiomeNameScreen = require(script:FindFirstAncestor("game").Client.UI.features.biome.screens.biomeNameScreen)
local CraftingSlotsScreen = require(script:FindFirstAncestor("game").Client.UI.features.crafting.screens.craftingSlots)
local DeathScreen = require(script:FindFirstAncestor("game").Client.UI.features.death.screens.deathScreen)
local EntityInfoScreen = require(script:FindFirstAncestor("game").Client.UI.features.entity.screens.entityInfoScreen)
local EyeOfCthulhuScreen = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.screens.EyeOfCthulhuScreen)
local EyeOfCthulhuServantScreen =
	require(script:FindFirstAncestor("game").Shared.Features.npc.ui.screens.EyeOfCthulhuServantScreen)
local HUD = require(script:FindFirstAncestor("game").Client.UI.hud)
local InfoPlayerScreen = require(script:FindFirstAncestor("game").Client.UI.features.player.screens.infoPlayerScreen)
local InfoScreen = require(script:FindFirstAncestor("game").Client.UI.features.info.screens.infoScreen)
local MarkerScreen = require(script:FindFirstAncestor("game").Client.UI.features.boss.screens.markerScreen)
local MiningProgressScreen =
	require(script:FindFirstAncestor("game").Client.UI.features.mining.screens.miningProgressScreen)
local MouseScreen = require(script:FindFirstAncestor("game").Client.UI.features.mouse.screen.mouseScreen)
local PadScreen = require(script:FindFirstAncestor("game").Client.UI.features.pad.screens.pad)
local React = require(ReplicatedStorage.Packages.React)
local Maid = loader("Maid")
local QueenBeeScreen = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.screens.QueenBeeScreen)
local Responsive = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useViewportScale)
local SlimeScreen = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.screens.SlimeScreen)
local TileBreakScreen = require(script:FindFirstAncestor("game").Client.Features.tile.ui.screen.Break)

local e: typeof(React.createElement) = React.createElement

type RootUIProps = {
	currentScreen: React.ReactElement<any, any>?,
	hudProps: { [string]: any }?,
	onCanvasMounted: ((Frame) -> ())?,
}

return function(props: RootUIProps)
	local canvasRef = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local maid = Maid.new()
		local canvas = canvasRef.current
		if canvas ~= nil and props.onCanvasMounted ~= nil then
			props.onCanvasMounted(canvas)
		end

		return function()
			maid:DoCleaning()
		end
	end, { props.onCanvasMounted })

	return e(Responsive.Provider, {}, {
		EyeOfCthulhuScreen = e(EyeOfCthulhuScreen, {
			zIndex = 166,
		}),
		EyeOfCthulhuServantScreen = e(EyeOfCthulhuServantScreen, {
			zIndex = 167,
		}),
		SlimeScreen = e(SlimeScreen, {
			zIndex = 168,
		}),
		QueenBeeScreen = e(QueenBeeScreen, {
			zIndex = 169,
		}),
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
			HUD = e(HUD, props.hudProps),
			CurrentScreen = props.currentScreen,
			InfoScreen = e(InfoScreen, {
				zIndex = 140,
			}),
			InfoPlayerScreen = e(InfoPlayerScreen, {
				zIndex = 145,
			}),
			BiomeNameScreen = e(BiomeNameScreen, {
				zIndex = 150,
			}),
			EntityInfoScreen = e(EntityInfoScreen, {
				zIndex = 160,
			}),
			MarkerScreen = e(MarkerScreen, {
				zIndex = 165,
			}),
			MiningProgressScreen = e(MiningProgressScreen, {
				zIndex = 170,
			}),
			TileBreakScreen = e(TileBreakScreen),
			CraftingSlotsScreen = e(CraftingSlotsScreen, {
				zIndex = 175,
			}),
			BindingHintScreen = e(BindingHintScreen, {
				zIndex = 180,
			}),
			MouseScreen = e(MouseScreen, {
				zIndex = 999999999,
			}),
			PadScreen = e(PadScreen, {
				zIndex = 980,
			}),
			DeathScreen = e(DeathScreen, {
				zIndex = 230,
			}),
		}),
	})
end
