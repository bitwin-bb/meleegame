--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local PortalTargets = require(gameRoot.Client.UI.core.utils.PortalTargets)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local BreakComponent = require(gameRoot.Client.Features.tile.ui.components.BreakSurface)
local tileSlice = require(gameRoot.Client.Features.tile.ui.state.tileSlice)
local useStore = require(gameRoot.Client.UI.core.hooks.useStore)

type BreakState = tileSlice.BreakState
type ShinySpeckState = tileSlice.ShinySpeckState

local e: typeof(React.createElement) = React.createElement

return function(): React.ReactNode
	local state = (useStore(tileSlice.breakStateAtom) :: BreakState?) or tileSlice.getBreakState()
	local shinySpecks = (useStore(tileSlice.shinySpecksAtom) :: { [string]: ShinySpeckState }?)
		or tileSlice.getShinySpecks()
	local portalTarget = PortalTargets.resolveUiScreenGui()

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
