# Celestial Cycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an in-game celestial cycle with SurfaceGui sun and moon presentation, an eight in-game day lunar phase loop, and Rx-observable state synced to the existing Weather world clock.

**Architecture:** `WeatherServiceServer` remains the authoritative clock and gains a replicated `worldDayIndex` that increments when the in-game clock wraps past midnight. Shared CelestialCycle modules derive pure sun/moon/phase presentation state from `clockTime` and `worldDayIndex`; server and client classes publish that derived state through Nevermore `ValueObject`, `Rx`, and `RxSignal`, while the client owns Fusion-created anchor instances and React/Charm SurfaceGui rendering.

**Tech Stack:** Roblox Luau, Rojo, Nevermore loader packages (`Maid`, `Rx`, `RxSignal`, `ValueObject`, `ContentProviderUtils`, `WorkspaceFolders`, `SunPositionUtils`, `Table`), Wally packages (`Fusion`, `React`, `ReactRoblox`, `Charm`), existing WeatherService ByteNet snapshots, TestEZ.

---

## File Structure

- Create: `src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau`
  - Tests clock normalization, eight-day moon phase progression, derived body visibility, asset lookup, and Weather `worldDayIndex` wrapping.
- Modify: `src/modules/Shared/CelestialCycle/CelestialCycleConstants.lua`
  - Owns display constants, day part thresholds, moon phase ordering, and SurfaceGui sizing defaults.
- Modify: `src/modules/Shared/CelestialCycle/CelestialCycleTypes.lua`
  - Exports shared type aliases for phase names, body names, layout state, and service snapshots.
- Modify: `src/modules/Shared/CelestialCycle/SunAsset.lua`
  - Normalizes the existing sun image asset and exposes lookup helpers.
- Modify: `src/modules/Shared/CelestialCycle/MoonAssets.lua`
  - Normalizes all eight moon phase image assets and exposes lookup helpers.
- Modify: `src/modules/Shared/CelestialCycle/RotationMath.lua`
  - Derives cycle progress, day part, moon phase, body screen positions, alpha, image, and full service state from clock/world-day inputs.
- Modify: `src/modules/Shared/World/WeatherServiceUtils.luau`
  - Adds `worldDayIndex` to snapshots and a helper that advances clock time while returning midnight wrap count.
- Modify: `src/modules/Server/World/WeatherServiceServer.luau`
  - Increments `worldDayIndex` during day/night stepping and keeps snapshots backward compatible.
- Modify: `src/modules/Server/CelestialCycle/Classes/CelestialCycleClassServer.lua`
  - Server-realm class that observes Weather state, derives celestial state, and publishes `ObserveState()`/`GetStateChangedSignal()`.
- Modify: `src/modules/Server/CelestialCycle/CelestialCycleServer.lua`
  - Singleton service facade over the server class.
- Modify: `src/modules/Client/CelestialCycle/UI/State/celestialSlice.lua`
  - Charm atom for SurfaceGui render state.
- Modify: `src/modules/Client/CelestialCycle/UI/State/celestialThunks.lua`
  - Narrow mutation helpers for publishing and clearing celestial UI state.
- Modify: `src/modules/Client/CelestialCycle/UI/Hooks/useCycle.lua`
  - React hook that reads the Charm atom.
- Modify: `src/modules/Client/CelestialCycle/UI/Components/CelestialBody.lua`
  - Reusable ImageLabel renderer for a sun or moon body.
- Modify: `src/modules/Client/CelestialCycle/UI/Screens/CelestialBodyScreen.lua`
  - SurfaceGui portal that renders all celestial bodies on the Fusion anchor.
- Modify: `src/modules/Client/CelestialCycle/UI/CelestialRoot.lua`
  - React root for the celestial SurfaceGui screen.
- Modify: `src/modules/Client/CelestialCycle/Components/CelestialBodyRoot.lua`
  - Fusion-owned invisible anchor part that follows the active camera X/Z and uses world-relative Y.
- Modify: `src/modules/Client/CelestialCycle/Classes/CelestialCycleClassClient.lua`
  - Client runtime class that observes Lighting/Weather-derived time, updates the anchor, preloads assets, and publishes Charm/Rx state.
- Modify: `src/modules/Client/CelestialCycle/CelestialCycleClient.lua`
  - Singleton service facade over the client class.
- Modify: `src/modules/Client/App/RootUI.luau`
  - Mounts `CelestialRoot` alongside the existing UI roots.
- Modify: `src/modules/Client/AquariaBackupServiceClient.lua`
  - Requires and initializes `CelestialCycleClient` after `WeatherServiceClient`.
- Modify: `src/modules/Server/AquariaBackupService.lua`
  - Requires and initializes `CelestialCycleServer` after `WeatherServiceServer`.

## Task 1: Failing Shared Tests

**Files:**
- Create: `src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau`

- [ ] **Step 1: Write the failing TestEZ spec**

Use this file content:

```lua
local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

-- selene: allow(undefined_variable)

local CelestialCycleConstants = require("CelestialCycleConstants")
local MoonAssets = require("MoonAssets")
local RotationMath = require("RotationMath")
local SunAsset = require("SunAsset")
local WeatherServiceUtils = require("WeatherServiceUtils")

return function()
	local function expectNear(actual: number, expected: number, epsilon: number?)
		local tolerance = epsilon or 1e-4
		expect(math.abs(actual - expected) <= tolerance).to.equal(true)
	end

	describe("CelestialCycle shared math", function()
		it("normalizes clock time and derives day progress", function()
			expect(RotationMath.normalizeClockTime(24.5)).to.equal(0.5)
			expect(RotationMath.normalizeClockTime(-1)).to.equal(23)
			expectNear(RotationMath.GetDayProgress(6), 0.25)
			expectNear(RotationMath.GetDayProgress(18), 0.75)
		end)

		it("walks one real-world style phase per in-game day across eight days", function()
			local expected = {
				"new",
				"waxingCrescent",
				"firstQuarter",
				"waxingGibbous",
				"fullMoon",
				"waningGibbous",
				"thirdQuarter",
				"waningCrescent",
				"new",
			}

			for dayIndex, phaseName in expected do
				expect(RotationMath.GetMoonPhase(dayIndex - 1)).to.equal(phaseName)
			end
			expect(CelestialCycleConstants.MOON_PHASE_DAY_COUNT).to.equal(8)
		end)

		it("gets sun and moon image assets", function()
			expect(SunAsset.getImage()).to.equal("rbxassetid://130185077109129")
			expect(MoonAssets.getImageForPhase("fullMoon")).to.equal("rbxassetid://71652201703042")
			expect(MoonAssets.getImageForPhase("not-a-phase")).to.equal(MoonAssets.getImageForPhase("new"))
		end)

		it("derives body state from clock time and world day index", function()
			local noonState = RotationMath.GetCycleState(12, 4)
			local midnightState = RotationMath.GetCycleState(0, 4)

			expect(noonState.clockTime).to.equal(12)
			expect(noonState.worldDayIndex).to.equal(4)
			expect(noonState.moonPhase).to.equal("fullMoon")
			expect(noonState.sun.visible).to.equal(true)
			expect(noonState.sun.alpha < noonState.moon.alpha).to.equal(false)

			expect(midnightState.moon.visible).to.equal(true)
			expect(midnightState.moon.phase).to.equal("fullMoon")
			expect(midnightState.dayPart).to.equal("Night")
		end)
	end)

	describe("WeatherService world day index", function()
		it("preserves worldDayIndex through Coerce and clone", function()
			local state = WeatherServiceUtils.CoerceState({
				worldDayIndex = 17,
			}, nil)
			local cloned = WeatherServiceUtils.cloneState(state)

			expect(state.worldDayIndex).to.equal(17)
			expect(cloned.worldDayIndex).to.equal(17)
		end)

		it("reports midnight wraps while advancing the clock", function()
			local result = WeatherServiceUtils.advanceClockTimeWithDayDelta(23.5, 60, 24 / 120)

			expectNear(result.clockTime, 11.5)
			expect(result.dayDelta).to.equal(1)
		end)
	end)
end
```

- [ ] **Step 2: Run tests and verify the new spec fails**

Run: `rojo serve default.project.json`

In Studio, set `ServerScriptService/AquariaBackup/game/Server/Tests.server` attribute `RunTests` to `true`, press Play, and read the TestEZ output.

Expected: FAIL with missing functions such as `GetMoonPhase`, `GetCycleState`, `getImageForPhase`, or `advanceClockTimeWithDayDelta`.

- [ ] **Step 3: Commit the failing spec**

```bash
git add src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau
git commit -m "test: cover celestial cycle derivation"
```

## Task 2: Shared Celestial Modules

**Files:**
- Modify: `src/modules/Shared/CelestialCycle/CelestialCycleConstants.lua`
- Modify: `src/modules/Shared/CelestialCycle/CelestialCycleTypes.lua`
- Modify: `src/modules/Shared/CelestialCycle/SunAsset.lua`
- Modify: `src/modules/Shared/CelestialCycle/MoonAssets.lua`
- Modify: `src/modules/Shared/CelestialCycle/RotationMath.lua`
- Test: `src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau`

- [ ] **Step 1: Implement constants and shared types**

`CelestialCycleConstants.lua` must define the exact eight-phase order and the SurfaceGui defaults:

```lua
local require = require(script.Parent.loader).load(script)

local Table = require("Table")

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
```

`CelestialCycleTypes.lua` must return a table and export these types:

```lua
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
```

- [ ] **Step 2: Normalize asset modules**

`SunAsset.lua` must expose `getImage()` and a frozen asset list:

```lua
local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local SunAsset = {}

SunAsset.Images = Table.deepReadonly({
	"rbxassetid://130185077109129",
})

function SunAsset.GetImage(): string
	return SunAsset.Images[1]
end

SunAsset.getImage = SunAsset.GetImage

return Table.readonly(SunAsset)
```

`MoonAssets.lua` must preserve all provided asset IDs and fall back to `new`:

```lua
local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local MoonAssets = {}

MoonAssets.ImagesByPhase = Table.deepReadonly({
	fullMoon = "rbxassetid://71652201703042",
	new = "rbxassetid://73088477000613",
	waxingGibbous = "rbxassetid://110054209286689",
	waningGibbous = "rbxassetid://133426730044312",
	waningCrescent = "rbxassetid://71828721926188",
	thirdQuarter = "rbxassetid://85935416509317",
	firstQuarter = "rbxassetid://77620348569206",
	waxingCrescent = "rbxassetid://137582270298372",
})

function MoonAssets.GetImageForPhase(phaseNameRaw: any): string
	local phaseName = if typeof(phaseNameRaw) == "string" then phaseNameRaw else "new"
	return MoonAssets.ImagesByPhase[phaseName] or MoonAssets.ImagesByPhase.new
end

MoonAssets.getImageForPhase = MoonAssets.GetImageForPhase

return Table.readonly(MoonAssets)
```

- [ ] **Step 3: Implement `RotationMath.lua`**

`RotationMath` must use `SunPositionUtils` for Roblox-compatible sun/moon direction and expose both PascalCase and camelCase aliases used by tests and callers:

```lua
local require = require(script.Parent.loader).load(script)

local Range = require("Range")
local SunPositionUtils = require("SunPositionUtils")
local Table = require("Table")

local CelestialCycleConstants = require("CelestialCycleConstants")
local CelestialCycleTypes = require("CelestialCycleTypes")
local MoonAssets = require("MoonAssets")
local SunAsset = require("SunAsset")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState
type CelestialBodyState = CelestialCycleTypes.CelestialBodyState
type DayPart = CelestialCycleTypes.DayPart
type MoonPhaseName = CelestialCycleTypes.MoonPhaseName

local RotationMath = {}

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

function RotationMath.NormalizeClockTime(clockTimeRaw: any): number
	local clockTime = if typeof(clockTimeRaw) == "number" and clockTimeRaw == clockTimeRaw then clockTimeRaw else 0
	return Range.wrap(clockTime, 0, 24)
end

function RotationMath.GetDayProgress(clockTimeRaw: any): number
	return RotationMath.NormalizeClockTime(clockTimeRaw) / 24
end

function RotationMath.GetMoonPhase(worldDayIndexRaw: any): MoonPhaseName
	local worldDayIndex = if typeof(worldDayIndexRaw) == "number" then math.floor(worldDayIndexRaw) else 0
	local phaseIndex = (worldDayIndex % CelestialCycleConstants.MOON_PHASE_DAY_COUNT) + 1
	return CelestialCycleConstants.MOON_PHASES[phaseIndex] :: MoonPhaseName
end

function RotationMath.GetDayPart(clockTimeRaw: any): DayPart
	local clockTime = RotationMath.NormalizeClockTime(clockTimeRaw)
	local Got = "Night"
	for _, threshold in CelestialCycleConstants.DAY_PARTS do
		if clockTime >= threshold.startsAt then
			Got = threshold.name
		end
	end
	return Got :: DayPart
end

local function directionToPosition(direction: Vector3): UDim2
	local center = CelestialCycleConstants.BODY_ARC_CENTER
	local radius = CelestialCycleConstants.BODY_ARC_RADIUS
	return UDim2.fromScale(center.X + direction.X * radius.X, center.Y - direction.Y * radius.Y)
end

local function directionToAlpha(direction: Vector3): number
	return clamp01((direction.Y + 0.08) / 0.22)
end

local function GetBodyState(
	name: "Sun" | "Moon",
	image: string,
	phase: MoonPhaseName?,
	direction: Vector3,
	zIndex: number
): CelestialBodyState
	local alpha = directionToAlpha(direction)
	return {
		name = name,
		image = image,
		phase = phase,
		visible = alpha > 0.001,
		alpha = alpha,
		position = directionToPosition(direction),
		size = CelestialCycleConstants.BODY_SIZE,
		rotation = math.deg(math.atan2(direction.Y, direction.X)),
		zIndex = zIndex,
	}
end

function RotationMath.GetCycleState(clockTimeRaw: any, worldDayIndexRaw: any): CelestialCycleState
	local clockTime = RotationMath.NormalizeClockTime(clockTimeRaw)
	local worldDayIndex = if typeof(worldDayIndexRaw) == "number" then math.max(0, math.floor(worldDayIndexRaw)) else 0
	local sunDirection, moonDirection =
		SunPositionUtils.getSunPosition(clockTime, CelestialCycleConstants.GEO_LATITUDE)
	local moonPhase = RotationMath.GetMoonPhase(worldDayIndex)

	return {
		ready = true,
		clockTime = clockTime,
		worldDayIndex = worldDayIndex,
		dayProgress = RotationMath.GetDayProgress(clockTime),
		dayPart = RotationMath.GetDayPart(clockTime),
		moonPhase = moonPhase,
		sun = GetBodyState("Sun", SunAsset.getImage(), nil, sunDirection, 10),
		moon = GetBodyState("Moon", MoonAssets.getImageForPhase(moonPhase), moonPhase, moonDirection, 9),
	}
end

RotationMath.normalizeClockTime = RotationMath.NormalizeClockTime
RotationMath.GetDayProgress = RotationMath.GetDayProgress
RotationMath.GetMoonPhase = RotationMath.GetMoonPhase
RotationMath.GetDayPart = RotationMath.GetDayPart
RotationMath.GetCycleState = RotationMath.GetCycleState

return Table.readonly(RotationMath)
```

- [ ] **Step 4: Run the focused spec and verify shared failures are gone except Weather**

Run: `rojo serve default.project.json`

In Studio, run TestEZ through `Tests.server` as in Task 1.

Expected: `CelestialCycle shared math` examples PASS; `WeatherService world day index` still FAILS until Task 3.

- [ ] **Step 5: Commit shared modules**

```bash
git add src/modules/Shared/CelestialCycle/CelestialCycleConstants.lua src/modules/Shared/CelestialCycle/CelestialCycleTypes.lua src/modules/Shared/CelestialCycle/SunAsset.lua src/modules/Shared/CelestialCycle/MoonAssets.lua src/modules/Shared/CelestialCycle/RotationMath.lua
git commit -m "feat: add shared celestial cycle math"
```

## Task 3: Weather World Day Index

**Files:**
- Modify: `src/modules/Shared/World/WeatherServiceUtils.luau`
- Modify: `src/modules/Server/World/WeatherServiceServer.luau`
- Test: `src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau`

- [ ] **Step 1: Add `worldDayIndex` to Weather state**

In `WeatherServiceUtils.WeatherServiceState`, insert:

```lua
	worldDayIndex: number,
```

In `CreateStateFromConfig`, add:

```lua
		worldDayIndex = 0,
```

In `CoerceState`, add:

```lua
		worldDayIndex = math.max(0, math.floor(CoerceNumber(source.worldDayIndex, fallback.worldDayIndex, 0, 10 ^ 9))),
```

In `CloneState`, add:

```lua
		worldDayIndex = state.worldDayIndex,
```

- [ ] **Step 2: Add a clock advance helper that reports midnight wraps**

Add this exported helper next to `AdvanceClockTime`:

```lua
export type ClockAdvanceResult = {
	clockTime: number,
	dayDelta: number,
}

function WeatherServiceUtils.AdvanceClockTimeWithDayDelta(
	clockTimeRaw: any,
	dtRaw: any,
	clockSpeedRaw: any
): ClockAdvanceResult
	local clockTime = normalizeClockTime(clockTimeRaw, 12)
	local dt = CoerceNumber(dtRaw, 0, 0, 60)
	local clockSpeed = CoerceNumber(clockSpeedRaw, 0, -100, 100)
	if dt <= 0 or clockSpeed == 0 then
		return {
			clockTime = clockTime,
			dayDelta = 0,
		}
	end

	local rawClockTime = clockTime + dt * clockSpeed
	local dayDelta = if clockSpeed > 0 then math.max(0, math.floor(rawClockTime / 24)) else 0
	return {
		clockTime = normalizeClockTime(rawClockTime, clockTime),
		dayDelta = dayDelta,
	}
end
```

Add the alias near the other aliases:

```lua
WeatherServiceUtils.advanceClockTimeWithDayDelta = WeatherServiceUtils.AdvanceClockTimeWithDayDelta
```

- [ ] **Step 3: Increment server day index during automatic clock stepping**

Replace `WeatherServiceServer.StepDayNight` line that assigns `clockTime` with:

```lua
	local advanceResult =
		WeatherServiceUtils.advanceClockTimeWithDayDelta(self.state.clockTime, dt, self.state.clockSpeed)
	self.state.clockTime = advanceResult.clockTime
	if advanceResult.dayDelta > 0 then
		self.state.worldDayIndex += advanceResult.dayDelta
	end
	self.stateDirty = true
```

Do not increment `worldDayIndex` from `SetClockTime`; time commands move the clock position without claiming an in-game day elapsed.

- [ ] **Step 4: Run the celestial spec**

Run: `rojo serve default.project.json`

In Studio, run TestEZ through `Tests.server`.

Expected: all `CelestialCycleCore` examples PASS.

- [ ] **Step 5: Commit Weather sync**

```bash
git add src/modules/Shared/World/WeatherServiceUtils.luau src/modules/Server/World/WeatherServiceServer.luau src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau
git commit -m "feat: track world day index for celestial phases"
```

## Task 4: Server Celestial Runtime

**Files:**
- Modify: `src/modules/Server/CelestialCycle/Classes/CelestialCycleClassServer.lua`
- Modify: `src/modules/Server/CelestialCycle/CelestialCycleServer.lua`

- [ ] **Step 1: Implement the server-realm class**

Use a true server class that reads Weather state and publishes derived celestial state:

```lua
local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Rx = require("Rx")
local RxSignal = require("RxSignal")
local ValueObject = require("ValueObject")

local CelestialCycleConstants = require("CelestialCycleConstants")
local CelestialCycleTypes = require("CelestialCycleTypes")
local RotationMath = require("RotationMath")
local WeatherServiceServer = require("WeatherServiceServer")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState

local CelestialCycleClassServer = {}
CelestialCycleClassServer.__index = CelestialCycleClassServer

local function cloneState(state: CelestialCycleState): CelestialCycleState
	return RotationMath.GetCycleState(state.clockTime, state.worldDayIndex)
end

function CelestialCycleClassServer.new(): CelestialCycleClassServer
	local self = setmetatable({}, CelestialCycleClassServer)
	self.maid = Maid.new()
	self.stateValue = ValueObject.new(RotationMath.GetCycleState(0, 0), "table")
	self.stateChangedSignal = RxSignal.new(function()
		return self:ObserveState()
	end)
	self.initialized = false
	return (self :: any) :: CelestialCycleClassServer
end

function CelestialCycleClassServer.PublishFromWeather(self: CelestialCycleClassServer)
	local weatherState = WeatherServiceServer:getState()
	self.stateValue.Value = RotationMath.GetCycleState(weatherState.clockTime, weatherState.worldDayIndex)
end

function CelestialCycleClassServer.Init(self: CelestialCycleClassServer)
	if self.initialized then
		return
	end
	self.initialized = true
	self:PublishFromWeather()
	self.maid:GiveTask(Rx.timer(
		CelestialCycleConstants.SERVER_OBSERVE_INTERVAL_SECONDS,
		CelestialCycleConstants.SERVER_OBSERVE_INTERVAL_SECONDS
	):Subscribe(function()
		self:PublishFromWeather()
	end))
end

function CelestialCycleClassServer.ObserveState(self: CelestialCycleClassServer): any
	return self.stateValue:Observe():Pipe({
		Rx.map(function(state: CelestialCycleState)
			return cloneState(state)
		end),
	})
end

function CelestialCycleClassServer.GetStateChangedSignal(self: CelestialCycleClassServer): any
	return self.stateChangedSignal
end

function CelestialCycleClassServer.GetState(self: CelestialCycleClassServer): CelestialCycleState
	return cloneState(self.stateValue.Value)
end

function CelestialCycleClassServer.Destroy(self: CelestialCycleClassServer)
	self.maid:Destroy()
	self.initialized = false
end

CelestialCycleClassServer.publishFromWeather = CelestialCycleClassServer.PublishFromWeather
CelestialCycleClassServer.init = CelestialCycleClassServer.Init
CelestialCycleClassServer.observeState = CelestialCycleClassServer.ObserveState
CelestialCycleClassServer.getStateChangedSignal = CelestialCycleClassServer.GetStateChangedSignal
CelestialCycleClassServer.getState = CelestialCycleClassServer.GetState
CelestialCycleClassServer.destroy = CelestialCycleClassServer.Destroy

export type CelestialCycleClassServer = typeof(setmetatable(
	{} :: {
		maid: any,
		stateValue: any,
		stateChangedSignal: any,
		initialized: boolean,
	},
	{} :: typeof({ __index = CelestialCycleClassServer })
))

return CelestialCycleClassServer
```

- [ ] **Step 2: Implement the server service facade**

`CelestialCycleServer.lua` should mirror the singleton facade pattern used by Parallax:

```lua
local require = require(script.Parent.loader).load(script)

local CelestialCycleClassServer = require("CelestialCycleClassServer")

local CelestialCycleServer = {}

local runtime: CelestialCycleClassServer.CelestialCycleClassServer? = nil

local function getRuntime(): CelestialCycleClassServer.CelestialCycleClassServer
	if runtime == nil then
		runtime = CelestialCycleClassServer.new()
	end
	return runtime :: CelestialCycleClassServer.CelestialCycleClassServer
end

function CelestialCycleServer.Init(_self: any)
	getRuntime():init()
end

function CelestialCycleServer.ObserveState(_self: any): any
	return getRuntime():observeState()
end

function CelestialCycleServer.GetStateChangedSignal(_self: any): any
	return getRuntime():getStateChangedSignal()
end

function CelestialCycleServer.GetState(_self: any): any
	return getRuntime():getState()
end

function CelestialCycleServer.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:destroy()
	runtime = nil
end

CelestialCycleServer.init = CelestialCycleServer.Init
CelestialCycleServer.observeState = CelestialCycleServer.ObserveState
CelestialCycleServer.getStateChangedSignal = CelestialCycleServer.GetStateChangedSignal
CelestialCycleServer.getState = CelestialCycleServer.GetState
CelestialCycleServer.destroy = CelestialCycleServer.Destroy

return CelestialCycleServer
```

- [ ] **Step 3: Run focused static checks**

Run: `selene --no-summary --config=selene.toml src/modules/Server/CelestialCycle/Classes/CelestialCycleClassServer.lua src/modules/Server/CelestialCycle/CelestialCycleServer.lua`

Expected: no diagnostics.

- [ ] **Step 4: Commit server runtime**

```bash
git add src/modules/Server/CelestialCycle/Classes/CelestialCycleClassServer.lua src/modules/Server/CelestialCycle/CelestialCycleServer.lua
git commit -m "feat: add server celestial cycle observable"
```

## Task 5: Charm State and SurfaceGui UI

**Files:**
- Modify: `src/modules/Client/CelestialCycle/UI/State/celestialSlice.lua`
- Modify: `src/modules/Client/CelestialCycle/UI/State/celestialThunks.lua`
- Modify: `src/modules/Client/CelestialCycle/UI/Hooks/useCycle.lua`
- Modify: `src/modules/Client/CelestialCycle/UI/Components/CelestialBody.lua`
- Modify: `src/modules/Client/CelestialCycle/UI/Screens/CelestialBodyScreen.lua`
- Modify: `src/modules/Client/CelestialCycle/UI/CelestialRoot.lua`

- [ ] **Step 1: Implement the Charm slice**

`celestialSlice.lua` must use Charm exactly as requested:

```lua
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
```

- [ ] **Step 2: Implement thunks and hook**

`celestialThunks.lua`:

```lua
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
```

`useCycle.lua`:

```lua
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
```

- [ ] **Step 3: Render each celestial body**

`CelestialBody.lua` should render one `ImageLabel` and use alpha as image transparency:

```lua
local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Table = require("Table")

local CelestialCycleTypes = require("CelestialCycleTypes")

type CelestialBodyState = CelestialCycleTypes.CelestialBodyState

local e: typeof(React.createElement) = React.createElement

local CelestialBody = {}

function CelestialBody.Render(props: { body: CelestialBodyState }): React.ReactNode
	local body = props.body
	if not body.visible then
		return nil
	end

	return e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = body.image,
		ImageTransparency = 1 - body.alpha,
		Position = body.position,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		Rotation = body.rotation,
		ScaleType = Enum.ScaleType.Fit,
		Size = body.size,
		ZIndex = body.zIndex,
	})
end

return Table.readonly(setmetatable(CelestialBody, {
	__call = function(_self, props)
		return CelestialBody.Render(props)
	end,
}))
```

- [ ] **Step 4: Render the SurfaceGui portal and root**

`CelestialBodyScreen.lua` should follow `ParallaxScreen` and portal to `PlayerGui`:

```lua
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Table = require("Table")

local CelestialBody = require("CelestialBody")
local Hooks = require("useCycle")

local e: typeof(React.createElement) = React.createElement

local function GetPortalTarget(): PlayerGui?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function GetAspectRatio(canvasSize: Vector2): number
	if canvasSize.X <= 0 or canvasSize.Y <= 0 then
		return 1
	end
	return math.clamp(canvasSize.X / canvasSize.Y, 0.01, 100)
end

local CelestialBodyScreen = {}

function CelestialBodyScreen.Render(): React.ReactNode
	local state = Hooks.useCycle()
	local portalTarget = GetPortalTarget()
	if state.adornee == nil or portalTarget == nil or state.cycle == nil then
		return nil
	end

	return ReactRoblox.createPortal(e("SurfaceGui", {
		Adornee = state.adornee,
		AlwaysOnTop = false,
		Brightness = state.brightness,
		CanvasSize = state.canvasSize,
		Enabled = state.visible,
		Face = state.face,
		LightInfluence = 0,
		ResetOnSpawn = false,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Frame = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
		}, {
			Aspect = e("UIAspectRatioConstraint", {
				AspectRatio = GetAspectRatio(state.canvasSize),
				DominantAxis = Enum.DominantAxis.Width,
			}),
			Sun = e(CelestialBody, {
				body = state.cycle.sun,
			}),
			Moon = e(CelestialBody, {
				body = state.cycle.moon,
			}),
		}),
	}), portalTarget)
end

return Table.readonly(setmetatable(CelestialBodyScreen, {
	__call = function()
		return CelestialBodyScreen.Render()
	end,
}))
```

`CelestialRoot.lua`:

```lua
local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Table = require("Table")

local CelestialBodyScreen = require("CelestialBodyScreen")

local e: typeof(React.createElement) = React.createElement

local CelestialRoot = {}

function CelestialRoot.Render(): React.ReactNode
	return e(CelestialBodyScreen)
end

return Table.readonly(setmetatable(CelestialRoot, {
	__call = function()
		return CelestialRoot.Render()
	end,
}))
```

- [ ] **Step 5: Run focused static checks**

Run: `selene --no-summary --config=selene.toml src/modules/Client/CelestialCycle/UI/State/celestialSlice.lua src/modules/Client/CelestialCycle/UI/State/celestialThunks.lua src/modules/Client/CelestialCycle/UI/Hooks/useCycle.lua src/modules/Client/CelestialCycle/UI/Components/CelestialBody.lua src/modules/Client/CelestialCycle/UI/Screens/CelestialBodyScreen.lua src/modules/Client/CelestialCycle/UI/CelestialRoot.lua`

Expected: no diagnostics.

- [ ] **Step 6: Commit UI state and rendering**

```bash
git add src/modules/Client/CelestialCycle/UI/State/celestialSlice.lua src/modules/Client/CelestialCycle/UI/State/celestialThunks.lua src/modules/Client/CelestialCycle/UI/Hooks/useCycle.lua src/modules/Client/CelestialCycle/UI/Components/CelestialBody.lua src/modules/Client/CelestialCycle/UI/Screens/CelestialBodyScreen.lua src/modules/Client/CelestialCycle/UI/CelestialRoot.lua
git commit -m "feat: add celestial SurfaceGui UI"
```

## Task 6: Client Anchor and Runtime Class

**Files:**
- Modify: `src/modules/Client/CelestialCycle/Components/CelestialBodyRoot.lua`
- Modify: `src/modules/Client/CelestialCycle/Classes/CelestialCycleClassClient.lua`
- Modify: `src/modules/Client/CelestialCycle/CelestialCycleClient.lua`

- [ ] **Step 1: Implement the Fusion anchor**

`CelestialBodyRoot.lua` must create a Fusion-owned invisible anchor part and update it from camera/world inputs:

```lua
local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Maid = require("Maid")
local Table = require("Table")

local CelestialCycleConstants = require("CelestialCycleConstants")

local CelestialBodyRoot = {}
CelestialBodyRoot.__index = CelestialBodyRoot

function CelestialBodyRoot.new(parent: Instance): CelestialBodyRoot
	local self = setmetatable({}, CelestialBodyRoot)
	self.maid = Maid.new()
	self.scope = Fusion.scoped(Fusion)
	self.anchorPart = self.scope:New "Part" {
		Name = "CelestialBodyRoot",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Locked = true,
		Size = Vector3.new(1, CelestialCycleConstants.ANCHOR_HEIGHT_STUDS, CelestialCycleConstants.ANCHOR_WIDTH_STUDS),
		Transparency = 1,
		Parent = parent,
	}
	self.maid:GiveTask(function()
		Fusion.doCleanup(self.scope)
	end)
	return (self :: any) :: CelestialBodyRoot
end

function CelestialBodyRoot.Update(self: CelestialBodyRoot, camera: Camera?)
	local GotCamera = camera or Workspace.CurrentCamera
	if GotCamera == nil then
		return
	end

	local cameraCFrame = GotCamera.CFrame
	local cameraPosition = cameraCFrame.Position
	local forward = cameraCFrame.LookVector
	local right = cameraCFrame.RightVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	if flatForward.Magnitude < 0.001 then
		flatForward = Vector3.zAxis
	end
	local anchorCenter = Vector3.new(cameraPosition.X, CelestialCycleConstants.ANCHOR_WORLD_Y, cameraPosition.Z)
		+ flatForward.Unit * CelestialCycleConstants.ANCHOR_DISTANCE_STUDS

	self.anchorPart.CFrame = CFrame.fromMatrix(anchorCenter, right, Vector3.yAxis)
end

function CelestialBodyRoot.GetAdornee(self: CelestialBodyRoot): BasePart
	return self.anchorPart
end

function CelestialBodyRoot.Destroy(self: CelestialBodyRoot)
	self.maid:Destroy()
end

CelestialBodyRoot.update = CelestialBodyRoot.Update
CelestialBodyRoot.getAdornee = CelestialBodyRoot.GetAdornee
CelestialBodyRoot.destroy = CelestialBodyRoot.Destroy

export type CelestialBodyRoot = typeof(setmetatable(
	{} :: {
		maid: any,
		scope: any,
		anchorPart: Part,
	},
	{} :: typeof({ __index = CelestialBodyRoot })
))

return Table.readonly(CelestialBodyRoot)
```

- [ ] **Step 2: Implement the client runtime class**

`CelestialCycleClassClient.lua` must preload assets, derive state from `Lighting.ClockTime` plus `WeatherServiceClient.state.worldDayIndex`, publish Charm state, and expose Rx:

```lua
local require = require(script.Parent.loader).load(script)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ContentProviderUtils = require("ContentProviderUtils")
local Maid = require("Maid")
local Rx = require("Rx")
local RxSignal = require("RxSignal")
local ValueObject = require("ValueObject")
local WorkspaceFolders = require("WorkspaceFolders")

local CelestialBodyRoot = require("CelestialBodyRoot")
local CelestialCycleConstants = require("CelestialCycleConstants")
local CelestialThunks = require("celestialThunks")
local MoonAssets = require("MoonAssets")
local RotationMath = require("RotationMath")
local SunAsset = require("SunAsset")
local WeatherServiceClient = require("WeatherServiceClient")

local CelestialCycleTypes = require("CelestialCycleTypes")

type CelestialCycleState = CelestialCycleTypes.CelestialCycleState

local CelestialCycleClassClient = {}
CelestialCycleClassClient.__index = CelestialCycleClassClient

local ROOT_FOLDER_NAME = "CelestialCycle"

local function GetWorldDayIndex(): number
	local weatherState = (WeatherServiceClient :: any).state
	if typeof(weatherState) == "table" and typeof(weatherState.worldDayIndex) == "number" then
		return weatherState.worldDayIndex
	end
	return 0
end

local function cloneState(state: CelestialCycleState): CelestialCycleState
	return RotationMath.GetCycleState(state.clockTime, state.worldDayIndex)
end

function CelestialCycleClassClient.new(): CelestialCycleClassClient
	local self = setmetatable({}, CelestialCycleClassClient)
	self.maid = Maid.new()
	self.stateValue = ValueObject.new(RotationMath.GetCycleState(Lighting.ClockTime, GetWorldDayIndex()), "table")
	self.stateChangedSignal = RxSignal.new(function()
		return self:ObserveState()
	end)
	self.initialized = false
	return (self :: any) :: CelestialCycleClassClient
end

function CelestialCycleClassClient.PreloadAssets(self: CelestialCycleClassClient)
	local assets = { SunAsset.getImage() }
	for _, phaseName in CelestialCycleConstants.MOON_PHASES do
		table.insert(assets, MoonAssets.getImageForPhase(phaseName))
	end
	self.maid:GivePromise(ContentProviderUtils.promisePreload(assets))
end

function CelestialCycleClassClient.Publish(self: CelestialCycleClassClient)
	local cycleState = RotationMath.GetCycleState(Lighting.ClockTime, GetWorldDayIndex())
	self.stateValue.Value = cycleState
	if self.anchorRoot ~= nil then
		self.anchorRoot:update(Workspace.CurrentCamera)
		CelestialThunks.publishSurfaceState({
			visible = true,
			adornee = self.anchorRoot:getAdornee(),
			face = CelestialCycleConstants.SURFACE_FACE,
			brightness = CelestialCycleConstants.SURFACE_BRIGHTNESS,
			canvasSize = Vector2.new(1024, 512),
			cycle = cycleState,
		})
	end
end

function CelestialCycleClassClient.Init(self: CelestialCycleClassClient, container: Instance?)
	if self.initialized then
		return
	end
	self.initialized = true
	self.rootFolder = WorkspaceFolders.getOrCreateFolderInGame(ROOT_FOLDER_NAME)
	self.anchorRoot = CelestialBodyRoot.new(container or self.rootFolder)
	self:PreloadAssets()
	self:Publish()
	self.maid:GiveTask(RunService.RenderStepped:Connect(function()
		self:Publish()
	end))
end

function CelestialCycleClassClient.ObserveState(self: CelestialCycleClassClient): any
	return self.stateValue:Observe():Pipe({
		Rx.map(function(state: CelestialCycleState)
			return cloneState(state)
		end),
	})
end

function CelestialCycleClassClient.GetStateChangedSignal(self: CelestialCycleClassClient): any
	return self.stateChangedSignal
end

function CelestialCycleClassClient.GetState(self: CelestialCycleClassClient): CelestialCycleState
	return cloneState(self.stateValue.Value)
end

function CelestialCycleClassClient.Destroy(self: CelestialCycleClassClient)
	CelestialThunks.clearSurfaceState()
	if self.anchorRoot ~= nil then
		self.anchorRoot:destroy()
		self.anchorRoot = nil
	end
	self.maid:Destroy()
	self.initialized = false
end

CelestialCycleClassClient.preloadAssets = CelestialCycleClassClient.PreloadAssets
CelestialCycleClassClient.publish = CelestialCycleClassClient.Publish
CelestialCycleClassClient.init = CelestialCycleClassClient.Init
CelestialCycleClassClient.observeState = CelestialCycleClassClient.ObserveState
CelestialCycleClassClient.getStateChangedSignal = CelestialCycleClassClient.GetStateChangedSignal
CelestialCycleClassClient.getState = CelestialCycleClassClient.GetState
CelestialCycleClassClient.destroy = CelestialCycleClassClient.Destroy

export type CelestialCycleClassClient = typeof(setmetatable(
	{} :: {
		maid: any,
		rootFolder: Folder?,
		anchorRoot: CelestialBodyRoot.CelestialBodyRoot?,
		stateValue: any,
		stateChangedSignal: any,
		initialized: boolean,
	},
	{} :: typeof({ __index = CelestialCycleClassClient })
))

return CelestialCycleClassClient
```

- [ ] **Step 3: Implement the client service facade**

`CelestialCycleClient.lua`:

```lua
local require = require(script.Parent.loader).load(script)

local CelestialCycleClassClient = require("CelestialCycleClassClient")

local CelestialCycleClient = {}

local runtime: CelestialCycleClassClient.CelestialCycleClassClient? = nil

local function getRuntime(): CelestialCycleClassClient.CelestialCycleClassClient
	if runtime == nil then
		runtime = CelestialCycleClassClient.new()
	end
	return runtime :: CelestialCycleClassClient.CelestialCycleClassClient
end

function CelestialCycleClient.Init(_self: any, container: Instance?)
	getRuntime():init(container)
end

function CelestialCycleClient.ObserveState(_self: any): any
	return getRuntime():observeState()
end

function CelestialCycleClient.GetStateChangedSignal(_self: any): any
	return getRuntime():getStateChangedSignal()
end

function CelestialCycleClient.GetState(_self: any): any
	return getRuntime():getState()
end

function CelestialCycleClient.Destroy(_self: any)
	if runtime == nil then
		return
	end
	runtime:destroy()
	runtime = nil
end

CelestialCycleClient.init = CelestialCycleClient.Init
CelestialCycleClient.observeState = CelestialCycleClient.ObserveState
CelestialCycleClient.getStateChangedSignal = CelestialCycleClient.GetStateChangedSignal
CelestialCycleClient.getState = CelestialCycleClient.GetState
CelestialCycleClient.destroy = CelestialCycleClient.Destroy

return CelestialCycleClient
```

- [ ] **Step 4: Run focused static checks**

Run: `selene --no-summary --config=selene.toml src/modules/Client/CelestialCycle/Components/CelestialBodyRoot.lua src/modules/Client/CelestialCycle/Classes/CelestialCycleClassClient.lua src/modules/Client/CelestialCycle/CelestialCycleClient.lua`

Expected: no diagnostics.

- [ ] **Step 5: Commit client runtime**

```bash
git add src/modules/Client/CelestialCycle/Components/CelestialBodyRoot.lua src/modules/Client/CelestialCycle/Classes/CelestialCycleClassClient.lua src/modules/Client/CelestialCycle/CelestialCycleClient.lua
git commit -m "feat: add client celestial cycle runtime"
```

## Task 7: Root and Startup Integration

**Files:**
- Modify: `src/modules/Client/App/RootUI.luau`
- Modify: `src/modules/Client/AquariaBackupServiceClient.lua`
- Modify: `src/modules/Server/AquariaBackupService.lua`

- [ ] **Step 1: Mount `CelestialRoot` in `RootUI.luau`**

Add the require near the other roots:

```lua
local CelestialRoot = require("CelestialRoot")
```

Add it to the returned children before `MouseRoot`, so it does not interfere with input overlays:

```lua
			CelestialRoot = e(CelestialRoot),
```

- [ ] **Step 2: Start the client service after Weather**

In `AquariaBackupServiceClient.lua`, add the require near the other service requires:

```lua
local CelestialCycleClient = require("CelestialCycleClient")
```

After `WeatherServiceClient:init()`, add:

```lua
	CelestialCycleClient:init()
```

- [ ] **Step 3: Start the server service after Weather**

In `AquariaBackupService.lua`, add the require near `WeatherServiceServer`:

```lua
local CelestialCycleServer = require("CelestialCycleServer")
```

After `WeatherServiceServer:init()`, add:

```lua
	CelestialCycleServer:init()
```

- [ ] **Step 4: Run Rojo sourcemap and lint**

Run: `rojo sourcemap default.project.json --output C:\tmp\aquaria-celestial-sourcemap.json --absolute`

Expected: sourcemap file is written without errors.

Run: `npm run lint:luau`

Expected: no new diagnostics from celestial files or Weather day-index edits.

- [ ] **Step 5: Commit integration**

```bash
git add src/modules/Client/App/RootUI.luau src/modules/Client/AquariaBackupServiceClient.lua src/modules/Server/AquariaBackupService.lua
git commit -m "feat: mount celestial cycle services"
```

## Task 8: Runtime Verification

**Files:**
- Verify all modified files from Tasks 1-7.

- [ ] **Step 1: Run all focused static checks**

Run:

```bash
selene --no-summary --config=selene.toml src/modules/Shared/CelestialCycle/CelestialCycleConstants.lua src/modules/Shared/CelestialCycle/CelestialCycleTypes.lua src/modules/Shared/CelestialCycle/SunAsset.lua src/modules/Shared/CelestialCycle/MoonAssets.lua src/modules/Shared/CelestialCycle/RotationMath.lua src/modules/Shared/World/WeatherServiceUtils.luau src/modules/Server/World/WeatherServiceServer.luau src/modules/Server/CelestialCycle/Classes/CelestialCycleClassServer.lua src/modules/Server/CelestialCycle/CelestialCycleServer.lua src/modules/Client/CelestialCycle/Components/CelestialBodyRoot.lua src/modules/Client/CelestialCycle/Classes/CelestialCycleClassClient.lua src/modules/Client/CelestialCycle/CelestialCycleClient.lua src/modules/Client/CelestialCycle/UI/State/celestialSlice.lua src/modules/Client/CelestialCycle/UI/State/celestialThunks.lua src/modules/Client/CelestialCycle/UI/Hooks/useCycle.lua src/modules/Client/CelestialCycle/UI/Components/CelestialBody.lua src/modules/Client/CelestialCycle/UI/Screens/CelestialBodyScreen.lua src/modules/Client/CelestialCycle/UI/CelestialRoot.lua src/modules/Client/App/RootUI.luau src/modules/Client/AquariaBackupServiceClient.lua src/modules/Server/AquariaBackupService.lua src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau
```

Expected: no diagnostics.

- [ ] **Step 2: Run full project analyzers**

Run:

```bash
rojo sourcemap default.project.json --output C:\tmp\aquaria-celestial-sourcemap.json --absolute
npm run lint:luau
npm run lint:stylua
```

Expected: each command exits 0.

- [ ] **Step 3: Run TestEZ in Studio**

Run: `rojo serve default.project.json`

In Studio, set `ServerScriptService/AquariaBackup/game/Server/Tests.server` attribute `RunTests` to `true`, press Play, and confirm `CelestialCycleCore` passes.

Expected: `CelestialCycleCore` examples pass and unrelated existing specs are unchanged.

- [ ] **Step 4: Manual in-game checks**

In Studio Play mode:

1. Run the existing `time set 12` command.
2. Confirm the sun is visible on the SurfaceGui and the moon is faded or hidden.
3. Run `time set 0`.
4. Confirm the moon is visible on the SurfaceGui and uses the current `worldDayIndex` phase image.
5. Let the cycle advance across midnight.
6. Confirm `WeatherServiceServer:getState().worldDayIndex` increments by 1.
7. Confirm `CelestialCycleClient:getState().moonPhase` changes once per in-game day and loops after 8 days.

Expected: bodies move at in-game speed, track the player camera plane, keep Y relative to the world, and do not render as screen-space HUD elements.

- [ ] **Step 5: Final commit after verification fixes**

If verification required edits, commit only those edits:

```bash
git add src/modules/Shared/CelestialCycle src/modules/Shared/World/WeatherServiceUtils.luau src/modules/Server/World/WeatherServiceServer.luau src/modules/Server/CelestialCycle src/modules/Client/CelestialCycle src/modules/Client/App/RootUI.luau src/modules/Client/AquariaBackupServiceClient.lua src/modules/Server/AquariaBackupService.lua src/modules/Server/Tests/Specs/CelestialCycle/CelestialCycleCore.spec.luau
git commit -m "fix: verify celestial cycle integration"
```

## Self-Review

- Spec coverage: The plan covers the user-listed shared, client, UI, component, service, and server files; syncs to Weather world time through `clockTime` and `worldDayIndex`; uses SurfaceGui; uses Rx observable state; uses Charm for atomic UI state; keeps the server class server-specific; and assigns the moon one real-world-style phase per in-game day across an eight-day cycle.
- Placeholder scan: The plan contains concrete paths, commands, expected outputs, and code snippets. It avoids deferred implementation language and defines every new function name before later tasks use it.
- Type consistency: `CelestialCycleState`, `CelestialBodyState`, `MoonPhaseName`, `worldDayIndex`, `GetCycleState`, `observeState`, `getStateChangedSignal`, and `publishSurfaceState` are named consistently across tests, shared modules, client runtime, server runtime, and UI.
