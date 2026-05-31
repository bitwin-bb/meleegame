--!strict

local ParallaxSlice = require(script.Parent.ParallaxSlice)

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
