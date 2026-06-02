local require = require(script.Parent.loader).load(
	assert(script:FindFirstAncestor("AquariaBackup"), "Missing AquariaBackup package root")
)
local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BindingRoot = require(gameRoot.Client.Features.binding.ui.BindingRoot)
local BiomeRoot = require(gameRoot.Client.Features.biome.ui.BiomeRoot)
local BossRoot = require(gameRoot.Shared.Features.npc.ui.boss.BossRoot)
local CraftingRoot = require(gameRoot.Shared.Features.crafting.ui.CraftingRoot)
local DeathRoot = require(gameRoot.Client.Features.death.ui.DeathRoot)
local EntityRoot = require(gameRoot.Client.Features.entity.ui.EntityRoot)
local HUD = require(gameRoot.Client.UI.hud)
local InfoRoot = require(gameRoot.Client.Features.info.ui.InfoRoot)
local Maid = require("Maid")
local MiningRoot = require(gameRoot.Client.Features.mining.ui.MiningRoot)
local MouseRoot = require(gameRoot.Client.Features.mouse.ui.MouseRoot)
local NpcRoot = require(gameRoot.Shared.Features.npc.ui.NpcRoot)
local PadRoot = require(gameRoot.Client.Features.pad.ui.PadRoot)
local PlayerRoot = require(gameRoot.Client.Features.player.ui.PlayerRoot)
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require(gameRoot.Client.UI.core.hooks.useViewportScale)
local TileRoot = require(gameRoot.Client.Features.tile.ui.TileRoot)

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
