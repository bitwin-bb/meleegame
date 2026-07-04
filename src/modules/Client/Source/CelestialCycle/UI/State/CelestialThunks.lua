local require = require(script.Parent.loader).load(script)

local Table: any = require("Table")

local CelestialSlice = require("CelestialSlice")

type CelestialSurfaceState = CelestialSlice.CelestialSurfaceState

local CelestialThunks = {}

function CelestialThunks.PublishSurfaceState(state: CelestialSurfaceState)
	CelestialSlice.SetSurfaceState(state)
end

function CelestialThunks.ClearSurfaceState()
	CelestialSlice.ClearSurfaceState()
end
return Table.readonly(CelestialThunks)
