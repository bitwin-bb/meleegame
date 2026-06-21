local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Table = require("Table")

local CelestialCycleTypes = require("CelestialCycleTypes")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState

export type CelestialSurfaceState = {
	visible: boolean,
	adornee: BasePart?,
	face: Enum.NormalId,
	brightness: number,
	canvasSize: Vector2,
	cycle: CelestialCycleState?,
}

local DEFAULT_STATE: CelestialSurfaceState = {
	visible = false,
	adornee = nil,
	face = Enum.NormalId.Right,
	brightness = 1,
	canvasSize = Vector2.new(1024, 512),
	cycle = nil,
}

local CelestialSlice = {}

local surfaceStateAtom: Charm.Atom<CelestialSurfaceState> = Charm.atom(DEFAULT_STATE)

local function cloneState(state: CelestialSurfaceState): CelestialSurfaceState
	return {
		visible = state.visible,
		adornee = state.adornee,
		face = state.face,
		brightness = state.brightness,
		canvasSize = state.canvasSize,
		cycle = state.cycle,
	}
end

function CelestialSlice.GetSurfaceState(): CelestialSurfaceState
	return cloneState(surfaceStateAtom())
end

function CelestialSlice.SetSurfaceState(state: CelestialSurfaceState)
	surfaceStateAtom(cloneState(state))
end

function CelestialSlice.ClearSurfaceState()
	surfaceStateAtom(cloneState(DEFAULT_STATE))
end

CelestialSlice.surfaceStateAtom = surfaceStateAtom
CelestialSlice.getSurfaceState = CelestialSlice.GetSurfaceState
CelestialSlice.setSurfaceState = CelestialSlice.SetSurfaceState
CelestialSlice.clearSurfaceState = CelestialSlice.ClearSurfaceState

return Table.readonly(CelestialSlice)
