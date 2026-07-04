local require = require(script.Parent.loader).load(script)

local Table: any = require("Table")

local CelestialCycleConstants = {}

CelestialCycleConstants.SERVICE_UPDATE_INTERVAL_SECONDS = 0.1
CelestialCycleConstants.SERVER_OBSERVE_INTERVAL_SECONDS = 0.25
CelestialCycleConstants.MOON_PHASE_DAY_COUNT = 8
CelestialCycleConstants.GEO_LATITUDE = 0

CelestialCycleConstants.SURFACE_FACE = Enum.NormalId.Right
CelestialCycleConstants.SURFACE_BRIGHTNESS = 1
CelestialCycleConstants.SURFACE_PIXELS_PER_STUD = 10
CelestialCycleConstants.SURFACE_MIN_CANVAS = Vector2.new(512, 256)
CelestialCycleConstants.SURFACE_MAX_CANVAS = Vector2.new(4096, 2048)
CelestialCycleConstants.ANCHOR_DISTANCE_STUDS = 320
CelestialCycleConstants.ANCHOR_HEIGHT_STUDS = 180
CelestialCycleConstants.ANCHOR_WIDTH_STUDS = 320
CelestialCycleConstants.ANCHOR_WORLD_Y = 128

CelestialCycleConstants.BODY_SIZE = UDim2.fromScale(0.14, 0.14)
CelestialCycleConstants.BODY_ARC_CENTER = Vector2.new(0.5, 0.54)
CelestialCycleConstants.BODY_ARC_RADIUS = Vector2.new(0.42, 0.46)
CelestialCycleConstants.BODY_MIN_ALPHA = 0
CelestialCycleConstants.BODY_MAX_ALPHA = 1

CelestialCycleConstants.DAY_PARTS = Table.deepReadonly({
	{ name = "Night", startsAt = 0 },
	{ name = "Dawn", startsAt = 5 },
	{ name = "Day", startsAt = 7 },
	{ name = "Dusk", startsAt = 17 },
	{ name = "Night", startsAt = 19 },
})

CelestialCycleConstants.MOON_PHASES = Table.deepReadonly({
	"new",
	"waxingCrescent",
	"firstQuarter",
	"waxingGibbous",
	"fullMoon",
	"waningGibbous",
	"thirdQuarter",
	"waningCrescent",
})

return Table.readonly(CelestialCycleConstants)
