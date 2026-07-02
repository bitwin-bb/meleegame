local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HUD = require("Hud")
local Maid = require("Maid")
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require("useViewportScale")

local e: typeof(React.createElement) = React.createElement

type RootUIProps = {
	currentScreen: React.ReactElement<any, any>?,
	hudProps: { [string]: any }?,
	featureRootsEnabled: boolean?,
	onCanvasMounted: ((Frame) -> ())?,
	responsiveUsePlatformState: boolean?,
}

local function createFeatureRootChildren(props: RootUIProps): { [string]: React.ReactNode }
	if props.featureRootsEnabled == false then
		return {}
	end

	local BindingRoot = require("BindingRoot")
	local BiomeRoot = require("BiomeRoot")
	local BossRoot = require("BossRoot")
	local CelestialRoot = require("CelestialRoot")
	local CraftingRoot = require("CraftingRoot")
	local DeathRoot = require("DeathRoot")
	local EntityRoot = require("EntityRoot")
	local InfoRoot = require("InfoRoot")
	local MiningRoot = require("MiningRoot")
	local MouseRoot = require("MouseRoot")
	local NpcRoot = require("NpcRoot")
	local PadRoot = require("PadRoot")
	local PlayerRoot = require("PlayerRoot")
	local TileRoot = require("TileRoot")

	return {
		NpcRoot = e(NpcRoot),
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
		CelestialRoot = e(CelestialRoot),
		PadRoot = e(PadRoot, {
			zIndex = 980,
		}),
		DeathRoot = e(DeathRoot, {
			zIndex = 230,
		}),
	}
end

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

	local rootCanvasChildren = {
		HUD = e(HUD, props.hudProps),
		CurrentScreen = props.currentScreen,
	}
	for key, child in createFeatureRootChildren(props) do
		rootCanvasChildren[key] = child
	end

	return e(Responsive.Provider, {
		usePlatformState = props.responsiveUsePlatformState,
	}, {
		RootCanvas = e("Frame", {
			ref = canvasRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			Selectable = false,
		}, rootCanvasChildren),
	})
end
