local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local BindingRoot = require(script:FindFirstAncestor("game").Client.Features.binding.ui.BindingRoot)
local BiomeRoot = require(script:FindFirstAncestor("game").Client.Features.biome.ui.BiomeRoot)
local BossRoot = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.boss.BossRoot)
local CraftingRoot = require(script:FindFirstAncestor("game").Shared.Features.crafting.ui.CraftingRoot)
local DeathRoot = require(script:FindFirstAncestor("game").Client.Features.death.ui.DeathRoot)
local EntityRoot = require(script:FindFirstAncestor("game").Client.Features.entity.ui.EntityRoot)
local HUD = require(script:FindFirstAncestor("game").Client.UI.hud)
local InfoRoot = require(script:FindFirstAncestor("game").Client.Features.info.ui.InfoRoot)
local MiningRoot = require(script:FindFirstAncestor("game").Client.Features.mining.ui.MiningRoot)
local MouseRoot = require(script:FindFirstAncestor("game").Client.Features.mouse.ui.MouseRoot)
local NpcRoot = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.NpcRoot)
local PadRoot = require(script:FindFirstAncestor("game").Client.Features.pad.ui.PadRoot)
local PlayerRoot = require(script:FindFirstAncestor("game").Client.Features.player.ui.PlayerRoot)
local React = require(ReplicatedStorage.Packages.React)
local Maid = loader("Maid")
local Responsive = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useViewportScale)
local TileRoot = require(script:FindFirstAncestor("game").Client.Features.tile.ui.TileRoot)

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
		NpcRoot = e(NpcRoot),
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
			InfoRoot = e(InfoRoot, {
				zIndex = 140,
			}),
			PlayerRoot = e(PlayerRoot, {
				zIndex = 145,
			}),
			BiomeRoot = e(BiomeRoot, {
				zIndex = 150,
			}),
			EntityRoot = e(EntityRoot, {
				zIndex = 160,
			}),
			BossRoot = e(BossRoot, {
				zIndex = 165,
			}),
			MiningRoot = e(MiningRoot, {
				zIndex = 170,
			}),
			TileRoot = e(TileRoot),
			CraftingRoot = e(CraftingRoot, {
				zIndex = 175,
			}),
			BindingRoot = e(BindingRoot, {
				zIndex = 180,
			}),
			MouseRoot = e(MouseRoot, {
				zIndex = 999999999,
			}),
			PadRoot = e(PadRoot, {
				zIndex = 980,
			}),
			DeathRoot = e(DeathRoot, {
				zIndex = 230,
			}),
		}),
	})
end
