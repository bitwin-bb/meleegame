local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local CelestialSlice = require("celestialSlice")
local useStore = require("useCoreStore")

local Hooks = {}

function Hooks.UseCycle(): CelestialSlice.CelestialSurfaceState
	return (useStore(CelestialSlice.surfaceStateAtom) :: CelestialSlice.CelestialSurfaceState?)
		or CelestialSlice.getSurfaceState()
end

Hooks.useCycle = Hooks.UseCycle

return Table.readonly(Hooks)
