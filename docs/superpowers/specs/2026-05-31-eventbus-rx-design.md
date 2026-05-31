# EventBus Rx Design

## Goal

Implement a clean same-realm EventBus system using the existing Aquaria hierarchy exactly:

- `src/modules/Shared/SharedEventBus`
- `src/modules/Server/ServerEventBus`
- `src/modules/Client/ClientEventBus`

The EventBus is not networking. Client-server communication remains owned by ByteNet. This system is for decoupled local communication inside the same runtime realm.

## Scope

Create or update only the requested raw `.luau` files inside the existing EventBus folders. Do not move, rename, or replace the existing folder hierarchy. Keep the `signals` folders lowercase.

The shared package owns reusable signal, connection, event name, type, and core EventBus logic. Server and client packages own realm runtime buses, event constants, registries, helpers, and debug behavior.

## API

`Signal` exposes:

```lua
Signal.new()
Signal:Connect(callback)
Signal:Once(callback)
Signal:Fire(...)
Signal:Wait()
Signal:DisconnectAll()
Signal:Destroy()
Signal:GetConnectionCount()
```

`Connection` exposes:

```lua
Connection:Disconnect()
Connection.Connected
```

`EventBus` exposes the required callback API:

```lua
EventBus.new(name?)
EventBus:On(eventName, callback)
EventBus:Once(eventName, callback)
EventBus:Fire(eventName, ...)
EventBus:Wait(eventName)
EventBus:Off(eventName)
EventBus:Has(eventName)
EventBus:GetSignal(eventName)
EventBus:GetEventNames()
EventBus:Clear(eventName?)
EventBus:Destroy()
```

`EventBus` also exposes Rx-first usage:

```lua
EventBus:Observe(eventName)
EventBus:GetRxSignal(eventName)
```

`Observe(eventName)` returns a Nevermore `Rx` observable for the event. `GetRxSignal(eventName)` returns an `RxSignal` wrapper for advanced callers that need Nevermore signal semantics. `On`, `Once`, and `Wait` remain the simple callback interface.

## Shared Architecture

`SharedEventBus/Core/signals/Signal.luau` implements the base signal table class. It owns connection lists, one-shot listeners, waiters, safe callback dispatch, `DisconnectAll`, and idempotent destruction.

`SharedEventBus/Core/signals/Connection.luau` implements the connection object returned by `Signal:Connect` and `Signal:Once`.

`SharedEventBus/Core/EventBus.luau` stores a map from event name to signal. `On` and `Once` create a signal when missing. `Fire` does nothing if no signal exists. `Off(eventName)` disconnects and removes a single event signal. `Clear()` removes every signal. `Destroy()` clears all signals and prevents reuse.

`SharedEventBus/Core/EventName.luau` provides small event name helpers such as string sanitization and assertion. `SharedEventBus/Core/EventConnection.luau` re-exports or wraps the base connection contract for EventBus users. `SharedEventBus/Core/Types.luau` contains shared exported types.

The shared modules may load Nevermore packages through the local loader path when Rx or RxSignal is needed. No shared module creates Roblox remotes or binds to networking.

## Server Architecture

`ServerEventBus/Core/ServerBus.luau` creates one server-local runtime bus using the shared EventBus core. It exposes `On`, `Once`, `Fire`, `Wait`, `Observe`, `GetRxSignal`, and the other core methods through the runtime object.

`ServerEventBus/Core/ServerEvents.luau` exports constants for:

```txt
PlayerDataLoaded
PlayerDataSaved
InventoryChanged
ItemDropped
EnemySpawned
EnemyDied
BossSpawned
BossDefeated
PlayerDamaged
TileBroken
TilePlaced
ChunkLoaded
ChunkUnloaded
CommandExecuted
AbilityUsed
```

`ServerEventBus/Core/ServerEventRegistry.luau` provides `GetAll()`, `Has(eventName)`, and `Assert(eventName)`. `Assert` warns or errors for unknown event names depending on a config flag exposed from `ServerEventBus/Utils.luau`.

## Client Architecture

`ClientEventBus/Core/ClientBus.luau` creates one client-local runtime bus using the shared EventBus core. It exposes the same callback and Rx APIs as the server bus.

`ClientEventBus/Core/ClientEvents.luau` exports constants for:

```txt
UIOpened
UIClosed
HotbarSelected
InventoryOpened
InventoryClosed
CraftingOpened
CraftingClosed
CameraShakeRequested
LocalEffectPlayed
SoundRequested
StateMachineChanged
InputModeChanged
TooltipRequested
DebugOverlayToggled
```

`ClientEventBus/Core/ClientEventRegistry.luau` provides `GetAll()`, `Has(eventName)`, and `Assert(eventName)`. `Assert` uses config from `ClientEventBus/Utils.luau`.

## Safety And Lifecycle

Callbacks are dispatched with protected calls so one callback error cannot stop the rest of the listeners. The implementation should warn with a small EventBus-prefixed message on callback errors.

Connections are idempotent. Disconnecting twice is safe. Destroying a signal or bus disconnects owned listeners and waiters. Destroyed buses reject future creation or fire attempts without leaking listeners.

Signal waiters are resumed on `Fire`. Waiting on a destroyed signal should resume with no event values or fail predictably through the local implementation contract.

Event names are treated as string contracts. Realm wrappers should validate names through their registry helpers, while the shared core remains reusable and generic.

## Testing

Add focused TestEZ specs for the shared Signal and EventBus behavior where the current test layout supports it. Tests should cover:

- `Connect`, `Once`, `Disconnect`, `DisconnectAll`, and `Destroy`
- safe callback errors
- `Wait`
- `On`, `Once`, `Fire`, `Off`, `Clear`, `Has`, and `GetEventNames`
- `Observe(eventName)` subscriptions receiving fired values
- server and client registries accepting known constants and rejecting unknown names according to config

Follow TDD: write a failing spec for the behavior first, verify it fails for the expected reason, then implement the minimal code to pass.

## Usage Examples

Server callback usage:

```lua
local ServerEventBus = require(path.To.ServerEventBus)
local ServerBus = ServerEventBus.Core.ServerBus
local ServerEvents = ServerEventBus.Core.ServerEvents

ServerBus:On(ServerEvents.EnemyDied, function(enemy, killer)
	print("Enemy died", enemy, killer)
end)

ServerBus:Fire(ServerEvents.EnemyDied, enemy, killer)
```

Server Rx usage:

```lua
ServerBus:Observe(ServerEvents.EnemyDied):Subscribe(function(enemy, killer)
	print("Enemy died", enemy, killer)
end)
```

Client callback usage:

```lua
local ClientEventBus = require(path.To.ClientEventBus)
local ClientBus = ClientEventBus.Core.ClientBus
local ClientEvents = ClientEventBus.Core.ClientEvents

ClientBus:On(ClientEvents.UIOpened, function(screenName)
	print("Opened UI:", screenName)
end)

ClientBus:Fire(ClientEvents.UIOpened, "Inventory")
```

Client Rx usage:

```lua
ClientBus:Observe(ClientEvents.UIOpened):Subscribe(function(screenName)
	print("Opened UI:", screenName)
end)
```

## Assumptions

The existing Rojo mapping places `src/modules` under the runtime `game` folder in `ServerScriptService/AquariaBackup`. The event bus modules should therefore be requireable through the existing `script:FindFirstAncestor("game")` paths used by the repo.

The repo already contains a separate older `src/modules/Shared/Core/EventBus.luau` with a channel and priority API. This design does not replace that module unless a later explicit task asks for migration. The new implementation lives in the requested EventBus hierarchy.
