# EventBus Rx Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the requested same-realm EventBus and Signal system with both callback and Nevermore Rx consumption APIs.

**Architecture:** SharedEventBus owns the reusable Signal, Connection, EventBus, types, and event name helpers. ServerEventBus and ClientEventBus each expose a realm-local runtime bus, constants, registry validation, and config helpers without using networking or globals.

**Tech Stack:** Roblox Luau, Rojo hierarchy under `src/modules`, Nevermore loader packages `Rx` and `RxSignal`, TestEZ specs under `src/modules/Server/Tests/Specs`.

---

## File Structure

- Create: `src/modules/Server/Tests/Specs/EventBus/EventBusCore.spec.luau`
  - Tests shared Signal, EventBus, Rx observe, and registry validation.
- Create: `src/modules/Shared/SharedEventBus/Client.luau`
  - Shared package client marker/export surface.
- Modify: `src/modules/Shared/SharedEventBus/init.luau`
  - Exports `Client`, `Server`, `Utils`, and `Core`.
- Create: `src/modules/Shared/SharedEventBus/Server.luau`
  - Shared package server marker/export surface.
- Create: `src/modules/Shared/SharedEventBus/Utils.luau`
  - Shared small helpers for EventBus debug/config defaults.
- Create: `src/modules/Shared/SharedEventBus/Core/init.luau`
  - Exports shared core modules.
- Create: `src/modules/Shared/SharedEventBus/Core/Types.luau`
  - Shared exported type aliases.
- Create: `src/modules/Shared/SharedEventBus/Core/EventBus.luau`
  - Reusable EventBus implementation.
- Create: `src/modules/Shared/SharedEventBus/Core/EventName.luau`
  - String event name helpers.
- Create: `src/modules/Shared/SharedEventBus/Core/EventConnection.luau`
  - EventBus connection contract export.
- Create: `src/modules/Shared/SharedEventBus/Core/signals/init.luau`
  - Exports shared signal modules.
- Create: `src/modules/Shared/SharedEventBus/Core/signals/Signal.luau`
  - Base Signal implementation.
- Create: `src/modules/Shared/SharedEventBus/Core/signals/Connection.luau`
  - Base Connection implementation.
- Create: `src/modules/Server/ServerEventBus/init.luau`
  - Exports server EventBus package.
- Create: `src/modules/Server/ServerEventBus/Server.luau`
  - Server realm package entrypoint.
- Create: `src/modules/Server/ServerEventBus/Utils.luau`
  - Server config helper for registry strictness.
- Create: `src/modules/Server/ServerEventBus/Core/init.luau`
  - Exports server core modules.
- Create: `src/modules/Server/ServerEventBus/Core/ServerBus.luau`
  - Server runtime bus wrapper.
- Create: `src/modules/Server/ServerEventBus/Core/ServerEvents.luau`
  - Server event constants.
- Create: `src/modules/Server/ServerEventBus/Core/ServerEventRegistry.luau`
  - Server event registry validation.
- Create: `src/modules/Server/ServerEventBus/Core/signals/init.luau`
  - Exports server signal wrapper.
- Create: `src/modules/Server/ServerEventBus/Core/signals/ServerSignal.luau`
  - Server signal alias over shared Signal.
- Create: `src/modules/Client/ClientEventBus/init.luau`
  - Exports client EventBus package.
- Create: `src/modules/Client/ClientEventBus/Client.luau`
  - Client realm package entrypoint.
- Create: `src/modules/Client/ClientEventBus/Utils.luau`
  - Client config helper for registry strictness.
- Create: `src/modules/Client/ClientEventBus/Core/init.luau`
  - Exports client core modules.
- Create: `src/modules/Client/ClientEventBus/Core/ClientBus.luau`
  - Client runtime bus wrapper.
- Create: `src/modules/Client/ClientEventBus/Core/ClientEvents.luau`
  - Client event constants.
- Create: `src/modules/Client/ClientEventBus/Core/ClientEventRegistry.luau`
  - Client event registry validation.
- Create: `src/modules/Client/ClientEventBus/Core/signals/init.luau`
  - Exports client signal wrapper.
- Create: `src/modules/Client/ClientEventBus/Core/signals/ClientSignal.luau`
  - Client signal alias over shared Signal.

## Task 1: Shared EventBus Tests

**Files:**
- Create: `src/modules/Server/Tests/Specs/EventBus/EventBusCore.spec.luau`

- [ ] **Step 1: Write the failing TestEZ spec**

Create `src/modules/Server/Tests/Specs/EventBus/EventBusCore.spec.luau` with:

```lua
--!strict
local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local gameRoot = script:FindFirstAncestor("game")

local SharedEventBus = require(gameRoot.Shared.SharedEventBus)
local ServerEventBus = require(gameRoot.Server.ServerEventBus)
local ClientEventBus = require(gameRoot.Client.ClientEventBus)

return function()
	describe("SharedEventBus Signal", function()
		it("connects, fires, disconnects, and reports connection count", function()
			local signal = SharedEventBus.Core.signals.Signal.new()
			local total = 0
			local connection = signal:Connect(function(value)
				total += value
			end)

			expect(connection.Connected).to.equal(true)
			expect(signal:GetConnectionCount()).to.equal(1)

			signal:Fire(3)
			connection:Disconnect()
			signal:Fire(5)

			expect(total).to.equal(3)
			expect(connection.Connected).to.equal(false)
			expect(signal:GetConnectionCount()).to.equal(0)

			signal:Destroy()
		end)

		it("disconnects once listeners after the first fire", function()
			local signal = SharedEventBus.Core.signals.Signal.new()
			local count = 0

			signal:Once(function()
				count += 1
			end)

			signal:Fire()
			signal:Fire()

			expect(count).to.equal(1)
			expect(signal:GetConnectionCount()).to.equal(0)

			signal:Destroy()
		end)

		it("keeps firing listeners after one listener errors", function()
			local signal = SharedEventBus.Core.signals.Signal.new()
			local count = 0

			signal:Connect(function()
				error("expected test error")
			end)

			signal:Connect(function()
				count += 1
			end)

			signal:Fire()

			expect(count).to.equal(1)

			signal:Destroy()
		end)

		it("waits for the next signal fire", function()
			local signal = SharedEventBus.Core.signals.Signal.new()
			local received = nil

			task.spawn(function()
				received = signal:Wait()
			end)

			task.wait()
			signal:Fire("ready")
			task.wait()

			expect(received).to.equal("ready")

			signal:Destroy()
		end)
	end)

	describe("SharedEventBus EventBus", function()
		it("supports On, Fire, Has, Off, Clear, and GetEventNames", function()
			local bus = SharedEventBus.Core.EventBus.new("test")
			local fired = 0

			bus:On("InventoryChanged", function(amount)
				fired += amount
			end)

			expect(bus:Has("InventoryChanged")).to.equal(true)
			bus:Fire("InventoryChanged", 2)
			expect(fired).to.equal(2)

			local names = bus:GetEventNames()
			expect(#names).to.equal(1)
			expect(names[1]).to.equal("InventoryChanged")

			bus:Off("InventoryChanged")
			bus:Fire("InventoryChanged", 2)
			expect(fired).to.equal(2)
			expect(bus:Has("InventoryChanged")).to.equal(false)

			bus:On("A", function() end)
			bus:On("B", function() end)
			bus:Clear()
			expect(#bus:GetEventNames()).to.equal(0)

			bus:Destroy()
		end)

		it("supports Once and Wait on named events", function()
			local bus = SharedEventBus.Core.EventBus.new("test")
			local count = 0
			local received = nil

			bus:Once("EnemyDied", function()
				count += 1
			end)

			task.spawn(function()
				received = bus:Wait("EnemyDied")
			end)

			task.wait()
			bus:Fire("EnemyDied", "slime")
			bus:Fire("EnemyDied", "zombie")
			task.wait()

			expect(count).to.equal(1)
			expect(received).to.equal("slime")

			bus:Destroy()
		end)

		it("observes events through Nevermore Rx", function()
			local bus = SharedEventBus.Core.EventBus.new("test")
			local values = {}
			local subscription = bus:Observe("UIOpened"):Subscribe(function(screenName)
				values[#values + 1] = screenName
			end)

			bus:Fire("UIOpened", "Inventory")
			task.wait()
			bus:Fire("UIOpened", "Crafting")
			task.wait()

			expect(#values).to.equal(2)
			expect(values[1]).to.equal("Inventory")
			expect(values[2]).to.equal("Crafting")

			subscription:Destroy()
			bus:Destroy()
		end)
	end)

	describe("realm event registries", function()
		it("accepts known server events and rejects unknown server events", function()
			local registry = ServerEventBus.Core.ServerEventRegistry

			expect(registry.Has(ServerEventBus.Core.ServerEvents.EnemyDied)).to.equal(true)
			expect(registry.Has("NotARealServerEvent")).to.equal(false)
			expect(registry.Assert(ServerEventBus.Core.ServerEvents.EnemyDied)).to.equal(true)
		end)

		it("accepts known client events and rejects unknown client events", function()
			local registry = ClientEventBus.Core.ClientEventRegistry

			expect(registry.Has(ClientEventBus.Core.ClientEvents.UIOpened)).to.equal(true)
			expect(registry.Has("NotARealClientEvent")).to.equal(false)
			expect(registry.Assert(ClientEventBus.Core.ClientEvents.UIOpened)).to.equal(true)
		end)
	end)
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run:

```powershell
npm run lint:luau -- --definitions=roblox
```

Expected: FAIL because `SharedEventBus.Core`, `ServerEventBus`, `ClientEventBus`, `Signal`, and `EventBus` exports do not exist yet. If the repo's `npm run lint:luau` wrapper rejects the extra argument, run `npm run lint:luau`.

- [ ] **Step 3: Commit the failing spec only if the team wants red-state commits**

Default action for this repo: do not commit the failing red state. Continue to Task 2.

## Task 2: Shared Signal And Connection

**Files:**
- Create: `src/modules/Shared/SharedEventBus/Core/signals/Connection.luau`
- Create: `src/modules/Shared/SharedEventBus/Core/signals/Signal.luau`
- Create: `src/modules/Shared/SharedEventBus/Core/signals/init.luau`

- [ ] **Step 1: Implement Connection**

Create `src/modules/Shared/SharedEventBus/Core/signals/Connection.luau`:

```lua
--!strict

local Connection = {}
Connection.__index = Connection

export type DisconnectCallback = () -> ()

export type Connection = typeof(setmetatable({} :: {
	Connected: boolean,
	_disconnect: DisconnectCallback?,
}, Connection))

function Connection.new(disconnect: DisconnectCallback): Connection
	return setmetatable({
		Connected = true,
		_disconnect = disconnect,
	}, Connection)
end

function Connection.Disconnect(self: Connection)
	if not self.Connected then
		return
	end

	self.Connected = false

	local disconnect = self._disconnect
	self._disconnect = nil

	if disconnect ~= nil then
		disconnect()
	end
end

Connection.disconnect = Connection.Disconnect

return Connection
```

- [ ] **Step 2: Implement Signal**

Create `src/modules/Shared/SharedEventBus/Core/signals/Signal.luau`:

```lua
--!strict

local Connection = require(script.Parent.Connection)

type Connection = Connection.Connection

type Listener = {
	connection: Connection,
	callback: (...any) -> (),
	once: boolean,
}

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: {
	_destroyed: boolean,
	_listeners: { Listener },
	_waitingThreads: { thread },
}, Signal))

local function reportCallbackError(message: string)
	warn("[EventBus] listener error " .. message)
end

function Signal.new(): Signal
	return setmetatable({
		_destroyed = false,
		_listeners = {},
		_waitingThreads = {},
	}, Signal)
end

function Signal._disconnectListener(self: Signal, listener: Listener)
	for index = #self._listeners, 1, -1 do
		if self._listeners[index] == listener then
			table.remove(self._listeners, index)
			break
		end
	end
end

function Signal.Connect(self: Signal, callback: (...any) -> ()): Connection
	assert(not self._destroyed, "cannot connect to destroyed signal")
	assert(typeof(callback) == "function", "callback must be a function")

	local listener = nil :: Listener?
	local connection = Connection.new(function()
		local currentListener = listener
		if currentListener ~= nil then
			self:_disconnectListener(currentListener)
		end
	end)

	listener = {
		connection = connection,
		callback = callback,
		once = false,
	}

	table.insert(self._listeners, listener)

	return connection
end

function Signal.Once(self: Signal, callback: (...any) -> ()): Connection
	assert(not self._destroyed, "cannot connect to destroyed signal")
	assert(typeof(callback) == "function", "callback must be a function")

	local listener = nil :: Listener?
	local connection = Connection.new(function()
		local currentListener = listener
		if currentListener ~= nil then
			self:_disconnectListener(currentListener)
		end
	end)

	listener = {
		connection = connection,
		callback = callback,
		once = true,
	}

	table.insert(self._listeners, listener)

	return connection
end

function Signal.Fire(self: Signal, ...: any)
	if self._destroyed then
		return
	end

	local args = table.pack(...)
	local waitingThreads = self._waitingThreads
	self._waitingThreads = {}

	for _, waitingThread in waitingThreads do
		task.spawn(waitingThread, table.unpack(args, 1, args.n))
	end

	local listeners = table.clone(self._listeners)
	for _, listener in listeners do
		if listener.connection.Connected then
			if listener.once then
				listener.connection:Disconnect()
			end

			task.spawn(function()
				local ok, result = pcall(listener.callback, table.unpack(args, 1, args.n))
				if not ok then
					reportCallbackError(tostring(result))
				end
			end)
		end
	end
end

function Signal.Wait(self: Signal): ...any
	assert(not self._destroyed, "cannot wait on destroyed signal")

	local waitingThread = coroutine.running()
	table.insert(self._waitingThreads, waitingThread)

	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	for _, listener in table.clone(self._listeners) do
		listener.connection:Disconnect()
	end

	table.clear(self._listeners)
end

function Signal.Destroy(self: Signal)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:DisconnectAll()

	local waitingThreads = self._waitingThreads
	self._waitingThreads = {}

	for _, waitingThread in waitingThreads do
		task.spawn(waitingThread)
	end
end

function Signal.GetConnectionCount(self: Signal): number
	local count = 0
	for _, listener in self._listeners do
		if listener.connection.Connected then
			count += 1
		end
	end

	return count
end

Signal.connect = Signal.Connect
Signal.once = Signal.Once
Signal.fire = Signal.Fire
Signal.wait = Signal.Wait
Signal.disconnectAll = Signal.DisconnectAll
Signal.destroy = Signal.Destroy
Signal.getConnectionCount = Signal.GetConnectionCount

return Signal
```

- [ ] **Step 3: Implement signals init export**

Create `src/modules/Shared/SharedEventBus/Core/signals/init.luau`:

```lua
--!strict

return {
	Signal = require(script.Signal),
	Connection = require(script.Connection),
}
```

- [ ] **Step 4: Run the focused spec**

Run:

```powershell
npm run lint:luau
```

Expected: still FAIL because the EventBus, package exports, and realm registries are not implemented yet. Signal-specific type errors should be fixed before moving on.

## Task 3: Shared EventBus Core With Rx

**Files:**
- Create: `src/modules/Shared/SharedEventBus/Core/EventName.luau`
- Create: `src/modules/Shared/SharedEventBus/Core/EventConnection.luau`
- Create: `src/modules/Shared/SharedEventBus/Core/Types.luau`
- Create: `src/modules/Shared/SharedEventBus/Core/EventBus.luau`
- Create: `src/modules/Shared/SharedEventBus/Core/init.luau`

- [ ] **Step 1: Implement event name helpers**

Create `src/modules/Shared/SharedEventBus/Core/EventName.luau`:

```lua
--!strict

local EventName = {}

function EventName.Sanitize(eventNameRaw: any): string?
	if typeof(eventNameRaw) ~= "string" then
		return nil
	end

	if eventNameRaw == "" then
		return nil
	end

	return eventNameRaw
end

function EventName.Assert(eventNameRaw: any): string
	local eventName = EventName.Sanitize(eventNameRaw)
	assert(eventName ~= nil, "eventName must be a non-empty string")
	return eventName
end

EventName.sanitize = EventName.Sanitize
EventName.assert = EventName.Assert

return EventName
```

- [ ] **Step 2: Implement shared type exports**

Create `src/modules/Shared/SharedEventBus/Core/Types.luau`:

```lua
--!strict

export type EventName = string
export type EventCallback = (...any) -> ()
export type EventConnection = {
	Connected: boolean,
	Disconnect: (self: EventConnection) -> (),
}

return {}
```

- [ ] **Step 3: Implement EventConnection export**

Create `src/modules/Shared/SharedEventBus/Core/EventConnection.luau`:

```lua
--!strict

return require(script.Parent.signals.Connection)
```

- [ ] **Step 4: Implement EventBus with callback and Rx APIs**

Create `src/modules/Shared/SharedEventBus/Core/EventBus.luau`:

```lua
--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("loaderUtils", true), "Missing loaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Rx = loader("Rx")
local RxSignal = loader("RxSignal")

local EventName = require(script.Parent.EventName)
local Signal = require(script.Parent.signals.Signal)

type Signal = Signal.Signal

type RxSignalObject = {
	Connect: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Once: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Wait: (self: RxSignalObject) -> ...any,
}

local EventBus = {}
EventBus.__index = EventBus

export type EventBus = typeof(setmetatable({} :: {
	Name: string,
	_destroyed: boolean,
	_signals: { [string]: Signal },
	_rxSignals: { [string]: RxSignalObject },
}, EventBus))

local function getSortedKeys(source: { [string]: any }): { string }
	local keys = {}
	for key in source do
		keys[#keys + 1] = key
	end

	table.sort(keys)
	return keys
end

function EventBus.new(name: string?): EventBus
	return setmetatable({
		Name = if typeof(name) == "string" and name ~= "" then name else "EventBus",
		_destroyed = false,
		_signals = {},
		_rxSignals = {},
	}, EventBus)
end

function EventBus._assertAlive(self: EventBus)
	assert(not self._destroyed, "cannot reuse destroyed event bus")
end

function EventBus.GetSignal(self: EventBus, eventNameRaw: any): Signal
	self:_assertAlive()

	local eventName = EventName.Assert(eventNameRaw)
	local signal = self._signals[eventName]
	if signal ~= nil then
		return signal
	end

	signal = Signal.new()
	self._signals[eventName] = signal

	return signal
end

function EventBus.On(self: EventBus, eventNameRaw: any, callback: (...any) -> ())
	return self:GetSignal(eventNameRaw):Connect(callback)
end

function EventBus.Once(self: EventBus, eventNameRaw: any, callback: (...any) -> ())
	return self:GetSignal(eventNameRaw):Once(callback)
end

function EventBus.Fire(self: EventBus, eventNameRaw: any, ...: any)
	if self._destroyed then
		return
	end

	local eventName = EventName.Sanitize(eventNameRaw)
	if eventName == nil then
		return
	end

	local signal = self._signals[eventName]
	if signal == nil then
		return
	end

	signal:Fire(...)
end

function EventBus.Wait(self: EventBus, eventNameRaw: any): ...any
	return self:GetSignal(eventNameRaw):Wait()
end

function EventBus.Off(self: EventBus, eventNameRaw: any)
	if self._destroyed then
		return
	end

	local eventName = EventName.Sanitize(eventNameRaw)
	if eventName == nil then
		return
	end

	local signal = self._signals[eventName]
	if signal == nil then
		return
	end

	signal:Destroy()
	self._signals[eventName] = nil
	self._rxSignals[eventName] = nil
end

function EventBus.Has(self: EventBus, eventNameRaw: any): boolean
	local eventName = EventName.Sanitize(eventNameRaw)
	return eventName ~= nil and self._signals[eventName] ~= nil
end

function EventBus.GetEventNames(self: EventBus): { string }
	return getSortedKeys(self._signals)
end

function EventBus.Clear(self: EventBus, eventNameRaw: any?)
	if eventNameRaw ~= nil then
		self:Off(eventNameRaw)
		return
	end

	for eventName in self._signals do
		self:Off(eventName)
	end
end

function EventBus.Destroy(self: EventBus)
	if self._destroyed then
		return
	end

	self:Clear()
	self._destroyed = true
	table.clear(self._signals)
	table.clear(self._rxSignals)
end

function EventBus.Observe(self: EventBus, eventNameRaw: any)
	return Rx.fromSignal(self:GetSignal(eventNameRaw))
end

function EventBus.GetRxSignal(self: EventBus, eventNameRaw: any): RxSignalObject
	self:_assertAlive()

	local eventName = EventName.Assert(eventNameRaw)
	local rxSignal = self._rxSignals[eventName]
	if rxSignal ~= nil then
		return rxSignal
	end

	rxSignal = RxSignal.new(function()
		return self:Observe(eventName)
	end) :: RxSignalObject

	self._rxSignals[eventName] = rxSignal

	return rxSignal
end

EventBus.on = EventBus.On
EventBus.once = EventBus.Once
EventBus.fire = EventBus.Fire
EventBus.wait = EventBus.Wait
EventBus.off = EventBus.Off
EventBus.has = EventBus.Has
EventBus.getSignal = EventBus.GetSignal
EventBus.getEventNames = EventBus.GetEventNames
EventBus.clear = EventBus.Clear
EventBus.destroy = EventBus.Destroy
EventBus.observe = EventBus.Observe
EventBus.getRxSignal = EventBus.GetRxSignal

return EventBus
```

- [ ] **Step 5: Implement shared core init**

Create `src/modules/Shared/SharedEventBus/Core/init.luau`:

```lua
--!strict

return {
	EventBus = require(script.EventBus),
	EventName = require(script.EventName),
	EventConnection = require(script.EventConnection),
	Types = require(script.Types),
	signals = require(script.signals),
}
```

- [ ] **Step 6: Run the focused spec**

Run:

```powershell
npm run lint:luau
```

Expected: still FAIL only on missing package exports and realm registries. Fix any new strict type errors in shared core before moving on.

## Task 4: Shared Package Exports

**Files:**
- Modify: `src/modules/Shared/SharedEventBus/init.luau`
- Create: `src/modules/Shared/SharedEventBus/Client.luau`
- Create: `src/modules/Shared/SharedEventBus/Server.luau`
- Create: `src/modules/Shared/SharedEventBus/Utils.luau`

- [ ] **Step 1: Implement shared client marker**

Create `src/modules/Shared/SharedEventBus/Client.luau`:

```lua
--!strict

return {
	Realm = "SharedClient",
}
```

- [ ] **Step 2: Implement shared server marker**

Create `src/modules/Shared/SharedEventBus/Server.luau`:

```lua
--!strict

return {
	Realm = "SharedServer",
}
```

- [ ] **Step 3: Implement shared utils**

Create `src/modules/Shared/SharedEventBus/Utils.luau`:

```lua
--!strict

local Utils = {}

Utils.DEBUG_WARN_CALLBACK_ERRORS = true

function Utils.Warn(message: string)
	warn("[EventBus] " .. message)
end

return Utils
```

- [ ] **Step 4: Replace shared package init**

Replace `src/modules/Shared/SharedEventBus/init.luau` with:

```lua
--!strict

return {
	Client = require(script.Client),
	Server = require(script.Server),
	Utils = require(script.Utils),
	Core = require(script.Core),
}
```

- [ ] **Step 5: Run the focused spec**

Run:

```powershell
npm run lint:luau
```

Expected: still FAIL only on missing server and client EventBus packages. Fix shared export errors before moving on.

## Task 5: Server EventBus Package

**Files:**
- Create: `src/modules/Server/ServerEventBus/init.luau`
- Create: `src/modules/Server/ServerEventBus/Server.luau`
- Create: `src/modules/Server/ServerEventBus/Utils.luau`
- Create: `src/modules/Server/ServerEventBus/Core/init.luau`
- Create: `src/modules/Server/ServerEventBus/Core/ServerBus.luau`
- Create: `src/modules/Server/ServerEventBus/Core/ServerEvents.luau`
- Create: `src/modules/Server/ServerEventBus/Core/ServerEventRegistry.luau`
- Create: `src/modules/Server/ServerEventBus/Core/signals/init.luau`
- Create: `src/modules/Server/ServerEventBus/Core/signals/ServerSignal.luau`

- [ ] **Step 1: Implement server event constants**

Create `src/modules/Server/ServerEventBus/Core/ServerEvents.luau`:

```lua
--!strict

return {
	PlayerDataLoaded = "PlayerDataLoaded",
	PlayerDataSaved = "PlayerDataSaved",
	InventoryChanged = "InventoryChanged",
	ItemDropped = "ItemDropped",
	EnemySpawned = "EnemySpawned",
	EnemyDied = "EnemyDied",
	BossSpawned = "BossSpawned",
	BossDefeated = "BossDefeated",
	PlayerDamaged = "PlayerDamaged",
	TileBroken = "TileBroken",
	TilePlaced = "TilePlaced",
	ChunkLoaded = "ChunkLoaded",
	ChunkUnloaded = "ChunkUnloaded",
	CommandExecuted = "CommandExecuted",
	AbilityUsed = "AbilityUsed",
}
```

- [ ] **Step 2: Implement server utils**

Create `src/modules/Server/ServerEventBus/Utils.luau`:

```lua
--!strict

local Utils = {}

Utils.ERROR_ON_UNKNOWN_EVENT = false

function Utils.ReportUnknownEvent(eventName: string): boolean
	local message = "[ServerEventBus] unknown event " .. eventName

	if Utils.ERROR_ON_UNKNOWN_EVENT then
		error(message, 3)
	end

	warn(message)
	return false
end

return Utils
```

- [ ] **Step 3: Implement server registry**

Create `src/modules/Server/ServerEventBus/Core/ServerEventRegistry.luau`:

```lua
--!strict

local ServerEvents = require(script.Parent.ServerEvents)
local Utils = require(script.Parent.Parent.Utils)

local eventNames = {}
local eventNameSet = {}

for _, eventName in ServerEvents do
	eventNames[#eventNames + 1] = eventName
	eventNameSet[eventName] = true
end

table.sort(eventNames)

local ServerEventRegistry = {}

function ServerEventRegistry.GetAll(): { string }
	return table.clone(eventNames)
end

function ServerEventRegistry.Has(eventNameRaw: any): boolean
	return typeof(eventNameRaw) == "string" and eventNameSet[eventNameRaw] == true
end

function ServerEventRegistry.Assert(eventNameRaw: any): boolean
	if ServerEventRegistry.Has(eventNameRaw) then
		return true
	end

	return Utils.ReportUnknownEvent(tostring(eventNameRaw))
end

return ServerEventRegistry
```

- [ ] **Step 4: Implement server bus wrapper**

Create `src/modules/Server/ServerEventBus/Core/ServerBus.luau`:

```lua
--!strict

local SharedEventBus = require(script:FindFirstAncestor("game").Shared.SharedEventBus)
local ServerEventRegistry = require(script.Parent.ServerEventRegistry)

local bus = SharedEventBus.Core.EventBus.new("ServerEventBus")

local ServerBus = {}

function ServerBus:On(eventName: string, callback: (...any) -> ())
	ServerEventRegistry.Assert(eventName)
	return bus:On(eventName, callback)
end

function ServerBus:Once(eventName: string, callback: (...any) -> ())
	ServerEventRegistry.Assert(eventName)
	return bus:Once(eventName, callback)
end

function ServerBus:Fire(eventName: string, ...: any)
	if not ServerEventRegistry.Assert(eventName) then
		return
	end

	bus:Fire(eventName, ...)
end

function ServerBus:Wait(eventName: string): ...any
	ServerEventRegistry.Assert(eventName)
	return bus:Wait(eventName)
end

function ServerBus:Observe(eventName: string)
	ServerEventRegistry.Assert(eventName)
	return bus:Observe(eventName)
end

function ServerBus:GetRxSignal(eventName: string)
	ServerEventRegistry.Assert(eventName)
	return bus:GetRxSignal(eventName)
end

function ServerBus:Off(eventName: string)
	bus:Off(eventName)
end

function ServerBus:Has(eventName: string): boolean
	return bus:Has(eventName)
end

function ServerBus:GetSignal(eventName: string)
	ServerEventRegistry.Assert(eventName)
	return bus:GetSignal(eventName)
end

function ServerBus:GetEventNames(): { string }
	return bus:GetEventNames()
end

function ServerBus:Clear(eventName: string?)
	bus:Clear(eventName)
end

function ServerBus:Destroy()
	bus:Destroy()
end

ServerBus.on = ServerBus.On
ServerBus.once = ServerBus.Once
ServerBus.fire = ServerBus.Fire
ServerBus.wait = ServerBus.Wait
ServerBus.observe = ServerBus.Observe

return ServerBus
```

- [ ] **Step 5: Implement server signal alias**

Create `src/modules/Server/ServerEventBus/Core/signals/ServerSignal.luau`:

```lua
--!strict

return require(script:FindFirstAncestor("game").Shared.SharedEventBus.SharedEventBusCore.SharedEventBusSignals.EventBusSignal)
```

Create `src/modules/Server/ServerEventBus/Core/signals/init.luau`:

```lua
--!strict

return {
	ServerSignal = require(script.ServerSignal),
}
```

- [ ] **Step 6: Implement server core and package exports**

Create `src/modules/Server/ServerEventBus/Core/init.luau`:

```lua
--!strict

return {
	ServerBus = require(script.ServerBus),
	ServerEvents = require(script.ServerEvents),
	ServerEventRegistry = require(script.ServerEventRegistry),
	signals = require(script.signals),
}
```

Create `src/modules/Server/ServerEventBus/Server.luau`:

```lua
--!strict

return require(script.Core.ServerBus)
```

Create `src/modules/Server/ServerEventBus/init.luau`:

```lua
--!strict

return {
	Server = require(script.Server),
	Utils = require(script.Utils),
	Core = require(script.Core),
}
```

- [ ] **Step 7: Run the focused spec**

Run:

```powershell
npm run lint:luau
```

Expected: still FAIL only on missing client EventBus package. Fix server package errors before moving on.

## Task 6: Client EventBus Package

**Files:**
- Create: `src/modules/Client/ClientEventBus/init.luau`
- Create: `src/modules/Client/ClientEventBus/Client.luau`
- Create: `src/modules/Client/ClientEventBus/Utils.luau`
- Create: `src/modules/Client/ClientEventBus/Core/init.luau`
- Create: `src/modules/Client/ClientEventBus/Core/ClientBus.luau`
- Create: `src/modules/Client/ClientEventBus/Core/ClientEvents.luau`
- Create: `src/modules/Client/ClientEventBus/Core/ClientEventRegistry.luau`
- Create: `src/modules/Client/ClientEventBus/Core/signals/init.luau`
- Create: `src/modules/Client/ClientEventBus/Core/signals/ClientSignal.luau`

- [ ] **Step 1: Implement client event constants**

Create `src/modules/Client/ClientEventBus/Core/ClientEvents.luau`:

```lua
--!strict

return {
	UIOpened = "UIOpened",
	UIClosed = "UIClosed",
	HotbarSelected = "HotbarSelected",
	InventoryOpened = "InventoryOpened",
	InventoryClosed = "InventoryClosed",
	CraftingOpened = "CraftingOpened",
	CraftingClosed = "CraftingClosed",
	CameraShakeRequested = "CameraShakeRequested",
	LocalEffectPlayed = "LocalEffectPlayed",
	SoundRequested = "SoundRequested",
	StateMachineChanged = "StateMachineChanged",
	InputModeChanged = "InputModeChanged",
	TooltipRequested = "TooltipRequested",
	DebugOverlayToggled = "DebugOverlayToggled",
}
```

- [ ] **Step 2: Implement client utils**

Create `src/modules/Client/ClientEventBus/Utils.luau`:

```lua
--!strict

local Utils = {}

Utils.ERROR_ON_UNKNOWN_EVENT = false

function Utils.ReportUnknownEvent(eventName: string): boolean
	local message = "[ClientEventBus] unknown event " .. eventName

	if Utils.ERROR_ON_UNKNOWN_EVENT then
		error(message, 3)
	end

	warn(message)
	return false
end

return Utils
```

- [ ] **Step 3: Implement client registry**

Create `src/modules/Client/ClientEventBus/Core/ClientEventRegistry.luau`:

```lua
--!strict

local ClientEvents = require(script.Parent.ClientEvents)
local Utils = require(script.Parent.Parent.Utils)

local eventNames = {}
local eventNameSet = {}

for _, eventName in ClientEvents do
	eventNames[#eventNames + 1] = eventName
	eventNameSet[eventName] = true
end

table.sort(eventNames)

local ClientEventRegistry = {}

function ClientEventRegistry.GetAll(): { string }
	return table.clone(eventNames)
end

function ClientEventRegistry.Has(eventNameRaw: any): boolean
	return typeof(eventNameRaw) == "string" and eventNameSet[eventNameRaw] == true
end

function ClientEventRegistry.Assert(eventNameRaw: any): boolean
	if ClientEventRegistry.Has(eventNameRaw) then
		return true
	end

	return Utils.ReportUnknownEvent(tostring(eventNameRaw))
end

return ClientEventRegistry
```

- [ ] **Step 4: Implement client bus wrapper**

Create `src/modules/Client/ClientEventBus/Core/ClientBus.luau`:

```lua
--!strict

local SharedEventBus = require(script:FindFirstAncestor("game").Shared.SharedEventBus)
local ClientEventRegistry = require(script.Parent.ClientEventRegistry)

local bus = SharedEventBus.Core.EventBus.new("ClientEventBus")

local ClientBus = {}

function ClientBus:On(eventName: string, callback: (...any) -> ())
	ClientEventRegistry.Assert(eventName)
	return bus:On(eventName, callback)
end

function ClientBus:Once(eventName: string, callback: (...any) -> ())
	ClientEventRegistry.Assert(eventName)
	return bus:Once(eventName, callback)
end

function ClientBus:Fire(eventName: string, ...: any)
	if not ClientEventRegistry.Assert(eventName) then
		return
	end

	bus:Fire(eventName, ...)
end

function ClientBus:Wait(eventName: string): ...any
	ClientEventRegistry.Assert(eventName)
	return bus:Wait(eventName)
end

function ClientBus:Observe(eventName: string)
	ClientEventRegistry.Assert(eventName)
	return bus:Observe(eventName)
end

function ClientBus:GetRxSignal(eventName: string)
	ClientEventRegistry.Assert(eventName)
	return bus:GetRxSignal(eventName)
end

function ClientBus:Off(eventName: string)
	bus:Off(eventName)
end

function ClientBus:Has(eventName: string): boolean
	return bus:Has(eventName)
end

function ClientBus:GetSignal(eventName: string)
	ClientEventRegistry.Assert(eventName)
	return bus:GetSignal(eventName)
end

function ClientBus:GetEventNames(): { string }
	return bus:GetEventNames()
end

function ClientBus:Clear(eventName: string?)
	bus:Clear(eventName)
end

function ClientBus:Destroy()
	bus:Destroy()
end

ClientBus.on = ClientBus.On
ClientBus.once = ClientBus.Once
ClientBus.fire = ClientBus.Fire
ClientBus.wait = ClientBus.Wait
ClientBus.observe = ClientBus.Observe

return ClientBus
```

- [ ] **Step 5: Implement client signal alias**

Create `src/modules/Client/ClientEventBus/Core/signals/ClientSignal.luau`:

```lua
--!strict

return require(script:FindFirstAncestor("game").Shared.SharedEventBus.SharedEventBusCore.SharedEventBusSignals.EventBusSignal)
```

Create `src/modules/Client/ClientEventBus/Core/signals/init.luau`:

```lua
--!strict

return {
	ClientSignal = require(script.ClientSignal),
}
```

- [ ] **Step 6: Implement client core and package exports**

Create `src/modules/Client/ClientEventBus/Core/init.luau`:

```lua
--!strict

return {
	ClientBus = require(script.ClientBus),
	ClientEvents = require(script.ClientEvents),
	ClientEventRegistry = require(script.ClientEventRegistry),
	signals = require(script.signals),
}
```

Create `src/modules/Client/ClientEventBus/Client.luau`:

```lua
--!strict

return require(script.Core.ClientBus)
```

Create `src/modules/Client/ClientEventBus/init.luau`:

```lua
--!strict

return {
	Client = require(script.Client),
	Utils = require(script.Utils),
	Core = require(script.Core),
}
```

- [ ] **Step 7: Run the focused spec**

Run:

```powershell
npm run lint:luau
```

Expected: PASS for EventBus-created code. Existing unrelated lint failures may appear because the worktree is already dirty; record them separately and do not modify unrelated files.

## Task 7: Verification And Final Report

**Files:**
- Review all EventBus files from Tasks 1-6.

- [ ] **Step 1: Format the touched EventBus and spec files**

Run:

```powershell
npx stylua --config-path=stylua.toml src/modules/Shared/SharedEventBus src/modules/Server/ServerEventBus src/modules/Client/ClientEventBus src/modules/Server/Tests/Specs/EventBus/EventBusCore.spec.luau
```

Expected: command exits successfully and only formats EventBus files plus the new spec.

- [ ] **Step 2: Run Luau analysis**

Run:

```powershell
npm run lint:luau
```

Expected: no EventBus-related errors. Existing unrelated errors from the dirty worktree should be listed in the final report if present.

- [ ] **Step 3: Run style check for touched files**

Run:

```powershell
npx stylua --config-path=stylua.toml --check src/modules/Shared/SharedEventBus src/modules/Server/ServerEventBus src/modules/Client/ClientEventBus src/modules/Server/Tests/Specs/EventBus/EventBusCore.spec.luau
```

Expected: PASS.

- [ ] **Step 4: Inspect git diff**

Run:

```powershell
git diff -- src/modules/Shared/SharedEventBus src/modules/Server/ServerEventBus src/modules/Client/ClientEventBus src/modules/Server/Tests/Specs/EventBus/EventBusCore.spec.luau
```

Expected: diff is limited to EventBus implementation and tests.

- [ ] **Step 5: Final report content**

Report:

```txt
created EventBus files under SharedEventBus, ServerEventBus, and ClientEventBus
created EventBusCore.spec.luau
how to require SharedEventBus: require(gameRoot.Shared.SharedEventBus)
how to require ServerEventBus: require(gameRoot.Server.ServerEventBus)
how to require ClientEventBus: require(gameRoot.Client.ClientEventBus)
server callback and Rx examples
client callback and Rx examples
verification commands and results
assumption: ByteNet remains the only client-server communication layer
assumption: old Shared/Core/EventBus.luau was not migrated
```

## Self-Review

- Spec coverage: the plan creates every requested EventBus file, required APIs, Rx APIs, registries, constants, and exports.
- Marker scan: no blank markers or deferred implementation steps are used.
- Type consistency: `Observe`, `GetRxSignal`, `On`, `Once`, `Fire`, `Wait`, `Off`, `Has`, `GetSignal`, `GetEventNames`, `Clear`, and `Destroy` are consistently named across shared, server, and client buses.
