local require = require(script.Parent.loader).load(script)

local Table = require("Table")

export type CelestialBodyName = "Sun" | "Moon"
export type MoonPhaseName =
	"new"
	| "waxingCrescent"
	| "firstQuarter"
	| "waxingGibbous"
	| "fullMoon"
	| "waningGibbous"
	| "thirdQuarter"
	| "waningCrescent"

export type DayPart = "Dawn" | "Day" | "Dusk" | "Night"

export type CelestialBodyState = {
	name: CelestialBodyName,
	image: string,
	phase: MoonPhaseName?,
	visible: boolean,
	alpha: number,
	position: UDim2,
	size: UDim2,
	rotation: number,
	zIndex: number,
}

export type CelestialCycleState = {
	ready: boolean,
	clockTime: number,
	worldDayIndex: number,
	dayProgress: number,
	dayPart: DayPart,
	moonPhase: MoonPhaseName,
	sun: CelestialBodyState,
	moon: CelestialBodyState,
}

return Table.readonly({})
