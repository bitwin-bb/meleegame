# Math Utility Audit - 2026-04-01

## Scope

This audit was a repo-wide pass across shared modules, client/server services, gameplay classes, UI hooks, world generation, AI, boss logic, combat/projectile helpers, camera code, foliage, and chunk/world simulation code. The goal was to separate reusable math from local gameplay policy without moving feature rules into the shared math layer.

Search patterns used included:

- `math.clamp`, manual `isFinite` / sanitize helpers, sign/snap/remap patterns
- shortest-angle wrapping, `math.rad` / `math.deg`, `math.atan2`, `math.acos`
- safe unit-vector code, planar flattening, projection/rejection, plane/ray helpers
- spring stepping, exponential damping, easing, sine/cosine motion, bezier sampling
- `math.noise`, seeded randomness, octave noise wrappers, coordinate hashing
- AABB / bounds intersection and closest-point logic

High-signal files were then reviewed manually before refactoring.

## Inventory

| Candidate helper | Representative locations found during audit | Existing duplication / inconsistency | Destination | Disposition |
| --- | --- | --- | --- | --- |
| Scalar clamp / remap / finite checks | `src/services/AudioService/Utils.luau`, `src/services/AnimationService/Utils.luau`, `src/services/BuildService/Utils.luau`, `src/classes/WorldGeneration/{Biome,Cave,Structures}.luau`, `src/services/WorldSimulationService/{Shared,Config,Net,Data}.luau` | Many copies of finite-number guards and clamp wrappers; naming varies between `clampNumber`, `sanitizeNumber`, `isFiniteNumber` | `Math.Num`, `Math.Range` | Extract reusable math primitives only. Boundary sanitizers stay local because they also encode fallback policy, accepted input types, and service-specific constraints. |
| Weighted averages / variance / moving averages | Sparse ad hoc local calculations, mostly in stats-like UI and data helpers | No cohesive shared location before this pass | `Math.Avg`, `Math.Stat` | Shared modules added as the standard library target. No forced repo-wide rewrites where local code was already business-specific. |
| Shortest-angle math / wrapping | `src/services/PlayerService/Utils.luau`, `src/services/WeatherService/Utils.luau`, boss/camera helpers, marker/UI rotation code | Manual `%` wrapping and bespoke shortest-delta logic existed in multiple shapes | `Math.Angle`, `Math.Trig`, `Math.Arc` | Refactored player look-angle wrapping and weather clock deltas to shared helpers. Remaining direct trig/orbit math that is domain-specific stays inline. |
| Projection / rejection / plane hits | `src/services/BossService/Utils.luau`, `src/services/BuildService/Utils.luau`, `src/services/PlayerService/Utils.luau` | Plane intersection and projection math repeated in slightly different shapes | `Math.Proj`, `Math.Plane`, `Math.Ray` | Refactored shared plane/raycast/project helpers into callers. |
| Safe unit vectors / planar flattening / move-towards | `src/classes/Boss/EyeOfCthulhu/Motion.luau`, `src/services/LootService/Server.luau`, `src/services/MagicService/Utils.luau`, `src/classes/WindFoliage/{WindField,TreeFoliageGraph,FoliageInstance}.luau`, `src/services/BossService/Utils.luau` | Repeated `Magnitude <= epsilon` plus fallback direction logic; inconsistent epsilon thresholds | `Math.Vec` | Added `unit`, `moveTowards`, `distance`, `flattenX/Y/Z`, then refactored the shared-pattern call sites. Local epsilon-sensitive guards remain where the exact threshold is part of the feature behavior. |
| AABB / bounds / closest point | `src/classes/EnemyHitbox/Utils/SpatialHash.luau`, `src/services/NpcService/Server.luau` | Repeated min/max normalization and overlap tests | `Math.Bounds` | Refactored to shared bounds helpers. |
| Easing / damping / spring stepping | `src/modules/UI/UISpringAnimator.luau`, `src/services/WorldAnimatorService/Utils.luau`, `src/ui/features/{miningProgress,crafting,item}/hooks`, `src/classes/Boss/EyeOfCthulhu/Motion.luau`, wind foliage recovery code | Multiple one-off `1 - exp(-lambda * dt)` formulas; local spring steps duplicated; easing names inconsistent | `Math.Ease`, `Math.Damp`, `Math.Spring` | Refactored UI smoothing, world animator easing, boss velocity damping, and UI spring stepping. Custom foliage spring integration remains local because it stores feature-specific bend state and stiffness/damping semantics. |
| Bezier / curve sampling | `src/classes/Gore/Gib.luau` | Local quadratic bezier and tangent helpers duplicated curve math inline | `Math.Curve` | Refactored to shared curve helpers. |
| Deterministic seeded randomness / coordinate hashing | `src/modules/Core/DeterministicRNG.luau`, `src/classes/WorldGeneration/{Biome,Cave,Structures}.luau`, `src/services/BuildService/Utils.luau` | Coordinate hashing, seeded float conversion, octave accumulation, and unit-interval conversion existed in multiple versions | `Math.Rand`, `Math.Noise` | Expanded shared deterministic helpers, then rewired `DeterministicRNG` and worldgen/build helpers to reuse them without changing their public APIs. |
| Color interpolation | `src/services/ParallaxService/Utils.luau`, `src/services/LiquidService/{Utils,Client}.luau`, `src/modules/UI/RichTextFormatter.luau` | Same `Color3.new(a + (b-a)*t)` formula repeated in several modules | `Math.Lerp` | Refactored to `Lerp.color3`. |
| Analytic solving | Projectile/intersection style helpers were mostly local or absent as a standard | No dedicated shared solver module before this pass | `Math.Solve` | Shared quadratic and ray helpers added; focused tests added because these are higher-risk primitives. |

## Refactors Applied

The following call sites were moved onto the shared math layer in this pass:

- `src/services/BuildService/Utils.luau`
- `src/services/BossService/Utils.luau`
- `src/services/PlayerService/Utils.luau`
- `src/services/WeatherService/Utils.luau`
- `src/services/WorldAnimatorService/Utils.luau`
- `src/services/ParallaxService/Utils.luau`
- `src/services/LiquidService/{Utils,Client}.luau`
- `src/modules/UI/RichTextFormatter.luau`
- `src/modules/UI/UISpringAnimator.luau`
- `src/classes/EnemyHitbox/Utils/SpatialHash.luau`
- `src/services/NpcService/Server.luau`
- `src/classes/Gore/Gib.luau`
- `src/classes/Boss/EyeOfCthulhu/Motion.luau`
- `src/services/MagicService/Utils.luau`
- `src/services/LootService/Server.luau`
- `src/classes/WindFoliage/{WindField,TreeFoliageGraph,FoliageInstance}.luau`
- `src/ui/features/{crafting,item,miningProgress}/hooks`
- `src/classes/WorldGeneration/{Biome,Cave,Structures}.luau`
- `src/modules/Core/DeterministicRNG.luau`

## Kept Local On Purpose

These patterns were inspected and intentionally not extracted:

- Service boundary sanitizers that accept loose `any` input and encode service-specific fallback behavior.
- Gameplay-specific random rolls using live `Random.new()` where determinism is not required, such as moment-to-moment SFX variation and visual-only client effects.
- Feature-authored springs that own domain state and semantics, especially the foliage bend integrators.
- Domain geometry in world generation and presentation code where the formula is tied to authored content rather than a reusable primitive.
- Linear damping in `src/classes/Boss/init.luau`, which intentionally preserves existing Euler-style behavior and should not silently switch to exponential damping.

## Result

The repo now has a shared math layer that owns reusable numeric, spatial, interpolation, deterministic-random, and solver primitives, while feature code keeps its local policy and authored behavior. The net effect is less inline low-level math, fewer duplicated helper shapes, and a clearer boundary between reusable math and gameplay logic.
