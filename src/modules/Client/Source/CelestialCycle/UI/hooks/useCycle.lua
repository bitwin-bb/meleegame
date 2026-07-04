local require = require(script.Parent.loader).load(script)

local Table: any = require("Table")

local CelestialSlice = require("CelestialSlice")
local useStore = require("useCoreStore")

local Hooks = {}

function Hooks.UseCycle(): CelestialSlice.CelestialSurfaceState
	return (useStore(CelestialSlice.surfaceStateAtom) :: CelestialSlice.CelestialSurfaceState?)
		or CelestialSlice.GetSurfaceState()
end
return Table.readonly(Hooks)
