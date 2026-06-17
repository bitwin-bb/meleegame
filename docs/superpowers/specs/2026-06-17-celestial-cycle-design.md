# Celestial Cycle Design

## Summary

Build a feature-owned celestial cycle system for Aquaria that renders the sun and moon through a client-side `SurfaceGui`, derives its time from the existing world time owned by `WeatherService`, and exposes Rx-observable state for other systems.

The moon uses real-world phase order, but the pacing is compressed to Aquaria time: one full lunar cycle lasts 8 in-game days, with one named phase per in-game day.

## Goals

- Render the sun and moon as SurfaceGui-backed UI, not native Roblox sky celestial bodies.
- Sync sun, moon, and moon phase state with the world's existing day/night time.
- Use the requested feature files under `Shared/CelestialCycle`, `Client/CelestialCycle`, and `Server/CelestialCycle`.
- Keep shared math and constants reusable by client and server.
- Use Rx-based observation so other systems can subscribe to celestial state.
- Keep server and client classes distinct; the server class represents server realm state, while the client class owns presentation and UI state.
- Use Charm for celestial UI state and Fusion for the SurfaceGui anchor/root part.
- Mount `CelestialRoot` from `RootUI`.

## Non-Goals

- Do not replace `WeatherService` as the owner of world time.
- Do not add new ByteNet packets for celestial state in the first implementation.
- Do not make celestial bodies gameplay authority on the client.
- Do not introduce a new UI framework or global state pattern.
- Do not use real-world wall-clock lunar timing.

## Architecture

The system uses approach 1: weather-driven celestial state.

`WeatherServiceServer` remains the authoritative source for `clockTime`, `dayNightCycleEnabled`, `clockSpeed`, and replicated world-time snapshots. To make the 8-day moon cycle deterministic for late-joining clients, WeatherService state gains a backward-compatible `worldDayIndex` number that increments when server clock time wraps past midnight. `CelestialCycleClassServer` reads `WeatherServiceServer:getState()` and derives a server-realm celestial snapshot for gameplay systems. It stores that snapshot in a `ValueObject` and exposes `ObserveState()` plus `GetStateChangedSignal()`.

`WeatherServiceClient` already smooths replicated world time into `Lighting.ClockTime`. `CelestialCycleClassClient` observes presentation time through Rx, derives visual state using shared math, and publishes a sanitized Charm state through `celestialThunks`.

Rendering is entirely client-side. `CelestialBodyRoot` creates a Fusion-owned invisible anchor part that follows the camera in X/Z, keeps its Y placement relative to world height, and updates size/cframe as screen/camera conditions change. `CelestialBodyScreen` renders a `SurfaceGui` against that anchor. `CelestialBody` renders the sun or current moon phase image.

## Shared Modules

`CelestialCycleConstants.lua`

- Defines cycle constants, including `LUNAR_CYCLE_DAYS = 8`.
- Defines phase ids in order:
  - `new`
  - `waxingCrescent`
  - `firstQuarter`
  - `waxingGibbous`
  - `fullMoon`
  - `waningGibbous`
  - `thirdQuarter`
  - `waningCrescent`
- Defines presentation defaults such as body size, canvas size, visibility thresholds, and anchor folder names.

`CelestialCycleTypes.lua`

- Defines shared state and view-state types:
  - `CelestialBodyId`
  - `MoonPhaseId`
  - `CelestialBodyState`
  - `CelestialCycleState`
  - `CelestialViewState`
  - `CelestialSurfaceState`

`RotationMath.lua`

- Sanitizes and normalizes clock values.
- Converts world clock time to day progress.
- Maps `worldDayIndex` plus day progress to the 8-day lunar phase.
- Uses `SunPositionUtils.getSunPositionData(clockTime, geoLatitude)` for sun/moon vectors and brightness.
- Converts world-space celestial vectors into deterministic presentation data for the client.

`SunAsset.lua` and `MoonAssets.lua`

- Preserve existing asset ids.
- Export explicit lookup helpers or tables so consumers can ask for one sun image and one moon image by phase id.

## Server Realm

`CelestialCycleClassServer.lua`

- Is a real server-side class, not a wrapper around the client class.
- Owns current server celestial state, state observation, and cleanup.
- Reads weather state from `WeatherServiceServer`.
- Computes phase/day values from weather clock and `worldDayIndex`.
- Exposes:
  - `new(weatherServiceServer)`
  - `init()`
  - `start()`
  - `destroy()`
  - `getState()`
  - `observeState()`
  - `getStateChangedSignal()`

`CelestialCycleServer.lua`

- Owns one server runtime instance.
- Initializes after `WeatherServiceServer` in `AquariaBackupService`.
- Provides service-facing `init`, `destroy`, `getState`, `observeState`, and `getStateChangedSignal` aliases following local service style.

## Client Realm

`CelestialCycleClassClient.lua`

- Owns client presentation state, asset preloading, Rx subscriptions, and the Fusion anchor runtime.
- Observes `Lighting.ClockTime` and WeatherServiceClient state, including `worldDayIndex`.
- Computes visual state from shared math.
- Publishes Charm state through `celestialThunks`.
- Exposes:
  - `new()`
  - `init()`
  - `start()`
  - `destroy()`
  - `getState()`
  - `observeState()`
  - `getStateChangedSignal()`

`CelestialCycleClient.lua`

- Owns one client runtime instance.
- Initializes after `WeatherServiceClient` in `AquariaBackupServiceClient`.
- Provides local service-style methods and aliases.

`CelestialBodyRoot.lua`

- Uses Fusion to create and own all anchor/root Instances.
- Tracks `Workspace.CurrentCamera`.
- Updates anchor CFrame and size from camera position, viewport, FOV, and shared constants.
- Cleans Fusion scope through `Maid`.

## UI

`celestialSlice.lua`

- Uses Charm atom state.
- Stores a cloned `CelestialSurfaceState`.
- Provides `getSurfaceState`, `setSurfaceState`, and `clearSurfaceState`.

`celestialThunks.lua`

- Provides state publishing functions.
- Clears state on runtime shutdown.

`useCycle.lua`

- Reads `celestialSlice` through the existing `useCoreStore` pattern.
- Returns a stable state shape to screens/components.

`CelestialBody.lua`

- Renders one ImageLabel for a sun or moon.
- Uses asset id, alpha, tint, size, position, and zIndex from state.
- Omits the body if not visible or if its asset id is empty.

`CelestialBodyScreen.lua`

- Creates a `SurfaceGui` portal to `PlayerGui`, using the anchor part as `Adornee`.
- Renders both bodies from current Charm state.
- Uses fixed canvas sizing and clips descendants for stable composition.

`CelestialRoot.lua`

- Feature UI root.
- Renders `CelestialBodyScreen`.
- Mounts from `RootUI`.

## Data Flow

1. `WeatherServiceServer` advances world time and increments `worldDayIndex` on midnight wrap.
2. `CelestialCycleClassServer` derives a server celestial snapshot from weather time.
3. Server systems observe the celestial snapshot through the public Rx APIs.
4. `WeatherServiceClient` receives weather snapshots and smooths `Lighting.ClockTime`.
5. `CelestialCycleClassClient` observes client time, `worldDayIndex`, and camera context.
6. Client class computes SurfaceGui body state and publishes Charm state.
7. React UI reads Charm state and renders the sun or current moon phase.

## Error Handling

- If weather state is not ready, use configured initial clock time and keep body visibility conservative.
- If an asset id is missing, omit that body rather than throwing.
- If there is no camera, keep the last safe anchor state or clear SurfaceGui state.
- If an optional dependency call fails, guard it with `pcall` and fall back to safe defaults.
- Destroy methods are idempotent and clear Charm/Fusion/React runtime resources.

## Testing

Add focused TestEZ specs for shared pure logic:

- Clock normalization and day progress.
- 8-day lunar phase progression.
- WeatherService `worldDayIndex` midnight-wrap behavior.
- Phase asset lookup fallback behavior.
- Derived celestial state shape for representative day, dusk, night, and dawn times.

Runtime verification after implementation:

- Run focused analyzer/lint checks on new celestial files.
- Run a Rojo sourcemap check.
- In Studio play solo, use `time set day/noon/dusk/night` and verify sun/moon SurfaceGui movement.
- Advance across 8 in-game days and verify phase order.

## Package Audit

Considered packages and project modules:

- `WeatherServiceUtils`: use existing time math helpers and weather state shape.
- `WeatherServiceServer`: server time authority.
- `WeatherServiceClient`: client presentation-time path.
- `SunPositionUtils`: compute sun/moon vectors and brightness from clock time.
- `Rx`: observe time/camera/weather streams.
- `RxSignal`: expose state-changed signals with observable backing.
- `ValueObject`: store observable class state.
- `Maid`: cleanup subscriptions, Fusion scope, render bindings, and runtime objects.
- `ServiceBag`: keep service initialization consistent with Nevermore patterns where the root services use it.
- `Fusion`: own the invisible anchor/root Instances.
- `React` and `ReactRoblox`: render UI and SurfaceGui portals.
- `Charm`: store UI state atoms.
- `ContentProviderUtils`: preload sun and moon image assets.
- `TimeSyncService`: not needed for the first implementation because WeatherService already syncs time using `Workspace:GetServerTimeNow`.
- `TestEZ`: verify shared pure logic.

## Open Decisions

No open design decisions remain for the first implementation.
