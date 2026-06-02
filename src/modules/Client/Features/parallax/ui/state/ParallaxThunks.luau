--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local ParallaxSlice = require(gameRoot.Client.Features.parallax.ui.state.ParallaxSlice)

type ParallaxSurfaceState = ParallaxSlice.ParallaxSurfaceState

local ParallaxThunks = {}

function ParallaxThunks.PublishSurfaceState(state: ParallaxSurfaceState)
	ParallaxSlice.setSurfaceState(state)
end

function ParallaxThunks.ClearSurfaceState()
	ParallaxSlice.clearSurfaceState()
end

ParallaxThunks.publishSurfaceState = ParallaxThunks.PublishSurfaceState
ParallaxThunks.clearSurfaceState = ParallaxThunks.ClearSurfaceState

return ParallaxThunks
