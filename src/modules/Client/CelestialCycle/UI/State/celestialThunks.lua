local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CelestialSlice = require("celestialSlice")

type CelestialSurfaceState = CelestialSlice.CelestialSurfaceState

local CelestialThunks = {}

function CelestialThunks.PublishSurfaceState(state: CelestialSurfaceState)
	CelestialSlice.setSurfaceState(state)
end

function CelestialThunks.ClearSurfaceState()
	CelestialSlice.clearSurfaceState()
end

CelestialThunks.publishSurfaceState = CelestialThunks.PublishSurfaceState
CelestialThunks.clearSurfaceState = CelestialThunks.ClearSurfaceState

return Table.readonly(CelestialThunks)
