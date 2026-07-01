
local require = require(script.Parent.loader).load(script)

local ParallaxSlice = require("ParallaxSlice")

type ParallaxSurfaceState = ParallaxSlice.ParallaxSurfaceState

local ParallaxThunks = {}

function ParallaxThunks.PublishSurfaceState(state: ParallaxSurfaceState)
	ParallaxSlice.SetSurfaceState(state)
end

function ParallaxThunks.ClearSurfaceState()
	ParallaxSlice.ClearSurfaceState()
end
return ParallaxThunks
