# AGENT.md

## Scope
This file is the style and refactor contract for `aquaria`. These rules are hard requirements for all future scripts and edits.

## Repository Scan Baseline
Scan performed across `src/*`, `Packages/*`, and dependency manifests.

- Source files scanned: `211`
- `--!strict` usage: `99` files (`46.92%`)
- Comment density: `0.2%` (comments are intentionally sparse)
- Indentation: tabs dominate (`41854` tab-indented lines, `62` space-indented lines)
- Service triad coverage: `26/27` service folders have `Client.luau`, `Server.luau`, `Utils.luau`
- Empty placeholder modules exist in several packages; treat them as intentional unless explicitly removed by user request

Package-level style profile:

- `services`: 83 files, 62.65% strict, median function size ~16 lines, strong `request/apply/on/get/set/resolve/sanitize` naming
- `classes`: 34 files, 44.12% strict, class table + `__index` + constructor pattern
- `ui`: 58 files, 53.45% strict, mostly camelCase file names, React functional composition
- `modules`: 34 files, mostly static data/config exports, very low strict usage
- `startup`: 2 files, orchestration-only entrypoints
- `Packages/_Index/leifstout_networker@0.2.1/networker/src`: explicit RPC wrapper style with low abstraction and predictable naming

## Global Hard Rules

1. Preserve behavior first.
- No public API changes unless explicitly requested.
- No execution-order changes in startup/service boot unless explicitly requested.
- Treat remote method names and payload shapes as compatibility contracts.

2. Match existing readability bias.
- Prefer short, explicit functions over generic helper abstractions.
- Prefer guard clauses and early returns over nested branching.
- Keep sanitization near call boundaries.

3. Keep comments minimal.
- Do not add explanatory noise.
- Add comments only for non-obvious contracts or side effects.
- Comments use lower case with no punctuation unless a required identifier must keep its original casing.

4. Respect existing naming rhythm.
- Types/tables/modules/services/classes: `PascalCase`.
- Method/field/local names: `camelCase`.
- Constants: `UPPER_SNAKE_CASE`.
- Raw untrusted inputs: suffix `Raw`.
- Optional fallback/input-normalizer helpers: `sanitize*`, `resolve*`, `clone*`, `create*`.

5. Preserve formatting conventions.
- Tabs for indentation.
- Logical top-to-bottom layout:
  - Services/Requires
  - Local constants/types
  - Local helper functions
  - Public methods
  - Runtime type alias near bottom
  - Return value

6. Type discipline.
- Keep existing type style (`export type`, explicit runtime object types, narrow unions).
- Do not weaken existing strictness in strict files.

## Package Conventions

### `Packages/Networker` (Highest Priority)
Observed in `NetworkerClient.luau`, `NetworkerServer.luau`, `NetworkerUtils.luau`.

- Transport model:
  - One remotes folder per network tag under `_remotes`.
  - Uses `RemoteEvent` for fire-and-forget and `RemoteFunction` for fetch/invoke.
- Construction:
  - Server: `Networker.server.new("ServiceTag", self, { self.allowedMethod, ... })`
  - Client: `Networker.client.new("ServiceTag", self)`
- Security model:
  - Server only executes whitelisted methods passed through `clientAccess`.
  - Unrecognized/restricted calls warn and return.
- Naming intent:
  - Client->server calls are verb requests (`request*`, `set*`, action verbs).
  - Server->client calls are application/event verbs (`apply*`, `on*`, `play*`, `stop*`).
- Payload shape:
  - Simple updates often use positional args.
  - Complex events use a single table payload.
- Design bias:
  - Explicit dispatch, no reflection-heavy abstraction, no hidden middleware.
  - Keep endpoint names readable and concrete.

Hard rule: for networking, follow the above pattern exactly unless the user explicitly requests a different transport design.

### `src/services`

- Directory contract:
  - Prefer `Client.luau` + `Server.luau` + `Utils.luau`.
- Responsibility split:
  - `Server`: authority, validation, canonical state, replication.
  - `Client`: input/UI glue, local projection, request emission.
  - `Utils`: shared types/constants/sanitizers/state transformers.
- Network naming contract:
  - Request methods: `request*`.
  - Server push methods: `apply*`.
  - Event notifications: `on*`.
  - Constants in utils use `NETWORK_METHOD_*`, `CLIENT_METHOD_*` where established.
- Validation style:
  - `typeof(...)` checks + nil checks + value clamping.
  - Use fallback defaults instead of throwing for recoverable bad input.
- Error handling style:
  - Use `pcall` around external boundaries (cross-service calls, tool requires, optional services).
  - Warn with service-prefixed messages when needed.
  - Printed, warned, or errored message text uses lower case with no punctuation unless a required identifier must keep its original casing.
- State style:
  - Clone before exposing mutable state (`cloneState` style).
  - Push snapshots, not direct runtime references.

Hard rule: new service endpoints must preserve naming polarity (`request` vs `apply/on`) and data sanitization boundary pattern.

### `src/classes`

- Structural pattern:
  - Table module + `__index`.
  - `new(...)` constructor builds deterministic runtime fields.
  - `destroy(...)` cleans connections/resources and is idempotent.
- Runtime safety:
  - Track `destroyed`/`isDestroyed` state where appropriate.
  - Prefer explicit `resolve*`/`sanitize*` helpers for instance resolution and numeric bounds.
- Signal/event style:
  - Prefer typed signal objects with explicit `Connect/Fire/Destroy` usage.

Hard rule: do not introduce metaprogramming-heavy class frameworks; stay with explicit table methods.

### `src/modules`

- Dominant use is data/config payload modules and small utility modules.
- Keep modules flat and explicit.
- Avoid over-abstracting static data definitions.
- Preserve existing return shapes (some modules intentionally export keyed wrapper tables).

Hard rule: do not normalize module export shapes unless all call sites and dynamic loaders are proven compatible.

### `src/ui`

- Composition style:
  - React functional components and direct element construction.
  - Common alias: `local e = React.createElement`.
- File naming:
  - Predominantly camelCase under features.
  - `init.luau` used for package entrypoints.
- State style:
  - Slice/thunk split under `features/*/state`.
  - Charm atom/selector usage for local UI state projection.
- Runtime behavior:
  - Keep effects/subscriptions explicit and cleaned up in returned callbacks.

Hard rule: prefer existing UI state and composition idioms over introducing a new state architecture per feature.

### `src/startup`

- Startup files orchestrate initialization only.
- Keep as ordered `:init()` calls with minimal branching.
- Do not move feature logic into startup scripts.

Hard rule: preserve init order unless there is an explicit dependency fix requested.

## Dependency Package Map (From `wally.toml`)

Actively required in source:

- `Networker`, `Janitor`, `React`, `ReactRoblox`, `Charm`, `Signal`, `Ripple`, `EZCameraShake`, `ProfileStore`, `RaycastHitbox`, `BloodEngine`, `Promise`

Installed but currently low/zero direct usage in source:

- `Roact`, `Sift`, `Rodux`, `RoactRodux`, `Smartbone`, `ReactRodux`, `ReactCharm`, `ZonePlus`, `FastCast`, `PartCache`

Hard rule: before adding new infrastructure, prefer an already-installed package if a clear fit exists and project style remains consistent.

## Human-Style Mirroring Rules

When creating/modifying code:

1. Copy an existing local pattern from the same package first.
2. Reuse existing naming prefixes/suffixes (`Get`, `Set`, `Bind`, `On`, `Request`, `Payload`, `Context`) when that package already uses them.
3. Match local function granularity (small, explicit, guard-heavy).
4. Keep data flow explicit (sanitize input -> mutate runtime -> push clone/snapshot).
5. If uncertain, choose verbatim local pattern reuse over inventing a new pattern.

## Safe Cleanup Rules

Allowed cleanup without behavior change:

- Rename unclear locals if scope-local and no API impact.
- Replace repeated string literals with existing constants.
- Normalize indentation/spacing/casing to local package conventions.
- Remove unreachable/dead local code only when references/contracts are provably absent.
- Flatten trivial indirection when call graph and side effects remain identical.

Disallowed in cleanup pass:

- Remote method renames.
- Public method signature changes.
- Reordering side-effectful initialization.
- Changing payload schemas or replication cadence.

## Internal Pre-Emit Checklist

- [ ] Did I follow the target package’s existing structure and naming rhythm?
- [ ] Are network method names/payloads unchanged unless explicitly requested?
- [ ] Are all edits behavior-preserving and API-compatible?
- [ ] Did I keep comments minimal and useful only where needed?
- [ ] Did I use tabs and existing file layout conventions?
- [ ] Did I avoid introducing new abstractions when explicit local patterns already exist?
- [ ] If uncertain, did I copy an existing pattern verbatim?
