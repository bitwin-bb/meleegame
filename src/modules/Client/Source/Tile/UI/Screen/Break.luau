local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local PortalTargets = require("PortalTargets")
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local BreakComponent = require("BreakSurface")
local tileSlice = require("TileSlice")
local useStore = require("useCoreStore")

type BreakState = tileSlice.BreakState
type ShinySpeckState = tileSlice.ShinySpeckState

local e: typeof(React.createElement) = React.createElement

return function(): React.ReactNode
	local state = (useStore(tileSlice.breakStateAtom) :: BreakState?) or tileSlice.GetBreakState()
	local shinySpecks = (useStore(tileSlice.shinySpecksAtom) :: { [string]: ShinySpeckState }?)
		or tileSlice.GetShinySpecks()
	local portalTarget = PortalTargets.GetUiScreenGui()

	if portalTarget == nil then
		return nil
	end

	return ReactRoblox.createPortal(
		e(BreakComponent, {
			state = state,
			shinySpecks = shinySpecks,
		}),
		portalTarget
	)
end
