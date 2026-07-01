local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any


local EventBusClient = require("EventBusClient")
local EventBusServer = require("EventBusServer")
local EventBusShared = require("EventBusShared")

local function waitUntil(predicate: () -> boolean, label: string)
	local timeoutAt = os.clock() + 1
	while not predicate() do
		if os.clock() >= timeoutAt then
			error("timed out waiting for " .. label, 2)
		end

		task.wait()
	end
end

local function withErrorOnUnknownEvent(utils: any, enabled: boolean, callback: () -> ())
	local previousErrorOnUnknownEvent = utils.ERROR_ON_UNKNOWN_EVENT
	utils.ERROR_ON_UNKNOWN_EVENT = enabled

	local ok, result = pcall(callback)
	utils.ERROR_ON_UNKNOWN_EVENT = previousErrorOnUnknownEvent

	if not ok then
		error(tostring(result), 2)
	end
end

return function()
	describe("EventBusShared Signal", function()
		it("connects, fires, disconnects, and reports connection count", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local total = 0
			local connection = signal:Connect(function(value)
				total += value
			end)

			expect(connection.Connected).to.equal(true)
			expect(signal:GetConnectionCount()).to.equal(1)

			signal:Fire(3)
			waitUntil(function()
				return total == 3
			end, "signal listener delivery")

			connection:Disconnect()
			signal:Fire(5)

			expect(total).to.equal(3)
			expect(connection.Connected).to.equal(false)
			expect(signal:GetConnectionCount()).to.equal(0)

			signal:Destroy()
		end)

		it("disconnects once listeners after the first fire", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local count = 0

			signal:Once(function()
				count += 1
			end)

			signal:Fire()
			signal:Fire()

			waitUntil(function()
				return count == 1
			end, "once signal delivery")

			expect(count).to.equal(1)
			expect(signal:GetConnectionCount()).to.equal(0)

			signal:Destroy()
		end)

		it("disconnects all listeners and prevents later fires", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local count = 0
			local firstConnection = signal:Connect(function()
				count += 1
			end)
			local secondConnection = signal:Connect(function()
				count += 1
			end)

			expect(signal:GetConnectionCount()).to.equal(2)

			signal:DisconnectAll()
			signal:Fire()

			expect(count).to.equal(0)
			expect(firstConnection.Connected).to.equal(false)
			expect(secondConnection.Connected).to.equal(false)
			expect(signal:GetConnectionCount()).to.equal(0)

			signal:Destroy()
		end)

		it("skips listeners disconnected before async delivery", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local count = 0
			local connection = signal:Connect(function()
				count += 1
			end)

			signal:Fire()
			connection:Disconnect()
			task.wait()

			expect(count).to.equal(0)
			expect(signal:GetConnectionCount()).to.equal(0)

			signal:Destroy()
		end)

		it("skips listeners after destroy before async delivery", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local count = 0

			signal:Connect(function()
				count += 1
			end)

			signal:Fire()
			signal:Destroy()
			task.wait()

			expect(count).to.equal(0)
			expect(signal:GetConnectionCount()).to.equal(0)
		end)

		it("skips claimed once listeners after disconnect all before async delivery", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local count = 0

			signal:Once(function()
				count += 1
			end)

			signal:Fire()
			signal:DisconnectAll()
			task.wait()

			expect(count).to.equal(0)
			expect(signal:GetConnectionCount()).to.equal(0)

			signal:Destroy()
		end)

		it("keeps firing listeners after one listener errors", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local count = 0

			signal:Connect(function()
				error("expected test error")
			end)

			signal:Connect(function()
				count += 1
			end)

			signal:Fire()

			waitUntil(function()
				return count == 1
			end, "listener after error delivery")

			expect(count).to.equal(1)

			signal:Destroy()
		end)

		it("waits for the next signal fire", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local received = nil
			local waiterReady = false

			task.spawn(function()
				waiterReady = true
				received = signal:Wait()
			end)

			waitUntil(function()
				return waiterReady
			end, "signal waiter readiness")

			signal:Fire("ready")

			waitUntil(function()
				return received ~= nil
			end, "signal wait result")

			expect(received).to.equal("ready")

			signal:Destroy()
		end)

		it("destroys owned listeners and ignores repeated destroy calls", function()
			local signal = EventBusShared.Core.signals.Signal.new()
			local count = 0
			local connection = signal:Connect(function()
				count += 1
			end)

			signal:Destroy()
			signal:Fire()
			signal:Destroy()

			expect(count).to.equal(0)
			expect(connection.Connected).to.equal(false)
			expect(signal:GetConnectionCount()).to.equal(0)

			local ok = pcall(function()
				signal:Connect(function() end)
			end)
			expect(ok).to.equal(false)
		end)
	end)

	describe("EventBusShared EventBus", function()
		it("supports On, Fire, Has, Off, Clear, and GetEventNames", function()
			local bus = EventBusShared.Core.EventBus.new("test")
			local fired = 0

			bus:On("InventoryChanged", function(amount)
				fired += amount
			end)

			expect(bus:Has("InventoryChanged")).to.equal(true)
			bus:Fire("InventoryChanged", 2)
			waitUntil(function()
				return fired == 2
			end, "event bus listener delivery")

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
			local bus = EventBusShared.Core.EventBus.new("test")
			local count = 0
			local received = nil
			local waiterReady = false

			bus:Once("EnemyDied", function()
				count += 1
			end)

			task.spawn(function()
				waiterReady = true
				received = bus:Wait("EnemyDied")
			end)

			waitUntil(function()
				return waiterReady
			end, "event bus waiter readiness")

			bus:Fire("EnemyDied", "slime")

			waitUntil(function()
				return count == 1 and received ~= nil
			end, "event bus once and wait result")

			bus:Fire("EnemyDied", "zombie")

			expect(count).to.equal(1)
			expect(received).to.equal("slime")

			bus:Destroy()
		end)

		it("observes events through Nevermore Rx", function()
			local bus = EventBusShared.Core.EventBus.new("test")
			local values = {}
			local subscription = bus:Observe("UIOpened"):Subscribe(function(screenName)
				values[#values + 1] = screenName
			end)

			bus:Fire("UIOpened", "Inventory")
			waitUntil(function()
				return #values >= 1
			end, "first observed event")

			bus:Fire("UIOpened", "Crafting")
			waitUntil(function()
				return #values >= 2
			end, "second observed event")

			expect(#values).to.equal(2)
			expect(values[1]).to.equal("Inventory")
			expect(values[2]).to.equal("Crafting")

			subscription:Destroy()
			bus:Destroy()
		end)

		it("keeps retained RxSignal handles from recreating events after Off", function()
			local bus = EventBusShared.Core.EventBus.new("test")
			local rxSignal = bus:GetRxSignal("InventoryChanged")

			expect(bus:Has("InventoryChanged")).to.equal(true)
			bus:Off("InventoryChanged")
			expect(bus:Has("InventoryChanged")).to.equal(false)

			local ok = pcall(function()
				rxSignal:Connect(function() end)
			end)

			expect(ok).to.equal(false)
			expect(bus:Has("InventoryChanged")).to.equal(false)

			bus:Destroy()
		end)

		it("resumes retained RxSignal waits when an event is cleared", function()
			local bus = EventBusShared.Core.EventBus.new("test")
			local rxSignal = bus:GetRxSignal("InventoryChanged")
			local resumed = false
			local waiterReady = false
			local received = nil :: any

			task.spawn(function()
				waiterReady = true
				received = rxSignal:Wait()
				resumed = true
			end)

			waitUntil(function()
				return waiterReady
			end, "retained RxSignal clear waiter readiness")

			bus:Clear("InventoryChanged")

			waitUntil(function()
				return resumed
			end, "retained RxSignal wait after clear")

			expect(received).to.equal(nil)
			expect(bus:Has("InventoryChanged")).to.equal(false)

			local ok = pcall(function()
				rxSignal:Connect(function() end)
			end)

			expect(ok).to.equal(false)
			expect(bus:Has("InventoryChanged")).to.equal(false)

			bus:Destroy()
		end)

		it("resumes retained RxSignal waits when the bus is destroyed", function()
			local bus = EventBusShared.Core.EventBus.new("test")
			local rxSignal = bus:GetRxSignal("InventoryChanged")
			local resumed = false
			local waiterReady = false
			local received = nil :: any

			task.spawn(function()
				waiterReady = true
				received = rxSignal:Wait()
				resumed = true
			end)

			waitUntil(function()
				return waiterReady
			end, "retained RxSignal destroy waiter readiness")

			bus:Destroy()

			waitUntil(function()
				return resumed
			end, "retained RxSignal wait after destroy")

			expect(received).to.equal(nil)
			expect(bus:Has("InventoryChanged")).to.equal(false)

			local ok = pcall(function()
				rxSignal:Connect(function() end)
			end)

			expect(ok).to.equal(false)
			expect(bus:Has("InventoryChanged")).to.equal(false)
		end)
	end)

	describe("realm event registries", function()
		it("accepts known server events and rejects unknown server events", function()
			local registry = EventBusServer.Core.EventRegistryServer
			local utils = EventBusServer.Utils

			expect(registry.Has(EventBusServer.Core.EventsServer.EnemyDied)).to.equal(true)
			expect(registry.Has("NotARealServerEvent")).to.equal(false)
			expect(registry.Assert(EventBusServer.Core.EventsServer.EnemyDied)).to.equal(true)

			withErrorOnUnknownEvent(utils, false, function()
				expect(registry.Assert("NotARealServerEvent")).to.equal(false)
			end)

			withErrorOnUnknownEvent(utils, true, function()
				local ok = pcall(function()
					registry.Assert("NotARealServerEvent")
				end)
				expect(ok).to.equal(false)
			end)
		end)

		it("accepts known client events and rejects unknown client events", function()
			local registry = EventBusClient.Core.EventRegistryClient
			local utils = EventBusClient.Utils

			expect(registry.Has(EventBusClient.Core.EventsClient.UIOpened)).to.equal(true)
			expect(registry.Has("NotARealClientEvent")).to.equal(false)
			expect(registry.Assert(EventBusClient.Core.EventsClient.UIOpened)).to.equal(true)

			withErrorOnUnknownEvent(utils, false, function()
				expect(registry.Assert("NotARealClientEvent")).to.equal(false)
			end)

			withErrorOnUnknownEvent(utils, true, function()
				local ok = pcall(function()
					registry.Assert("NotARealClientEvent")
				end)
				expect(ok).to.equal(false)
			end)
		end)
	end)

	describe("realm event buses", function()
		it("delegates server bus wrapper calls", function()
			local bus = EventBusServer.Core.BusServer
			local events = EventBusServer.Core.EventsServer
			local callbackValue = nil :: any
			local observedValue = nil :: any
			local rxSignalValue = nil :: any

			bus:Clear(events.CommandExecuted)
			bus:Clear(events.BossDefeated)
			bus:Clear(events.AbilityUsed)

			local callbackConnection = bus:On(events.CommandExecuted, function(commandName)
				callbackValue = commandName
			end)
			local subscription = bus:Observe(events.BossDefeated):Subscribe(function(bossName)
				observedValue = bossName
			end)
			local rxSignalConnection = bus:GetRxSignal(events.AbilityUsed):Connect(function(abilityName)
				rxSignalValue = abilityName
			end)

			expect(bus:Has(events.CommandExecuted)).to.equal(true)
			expect(bus:Has(events.BossDefeated)).to.equal(true)
			expect(bus:Has(events.AbilityUsed)).to.equal(true)

			bus:Fire(events.CommandExecuted, "grant")
			bus:Fire(events.BossDefeated, "reef_boss")
			bus:Fire(events.AbilityUsed, "dash")

			waitUntil(function()
				return callbackValue == "grant" and observedValue == "reef_boss" and rxSignalValue == "dash"
			end, "server bus wrapper delivery")

			callbackConnection:Disconnect()
			subscription:Destroy()
			rxSignalConnection:Destroy()

			bus:Off(events.CommandExecuted)
			bus:Off(events.BossDefeated)
			bus:Off(events.AbilityUsed)

			expect(bus:Has(events.CommandExecuted)).to.equal(false)
			expect(bus:Has(events.BossDefeated)).to.equal(false)
			expect(bus:Has(events.AbilityUsed)).to.equal(false)

			withErrorOnUnknownEvent(EventBusServer.Utils, false, function()
				expect(bus:On("NotARealServerEvent", function() end)).to.equal(nil)
				expect(bus:Has("NotARealServerEvent")).to.equal(false)
			end)
		end)

		it("delegates client bus wrapper calls", function()
			local bus = EventBusClient.Core.BusClient
			local events = EventBusClient.Core.EventsClient
			local callbackValue = nil :: any
			local observedValue = nil :: any
			local rxSignalValue = nil :: any

			bus:Clear(events.UIOpened)
			bus:Clear(events.UIClosed)
			bus:Clear(events.SoundRequested)

			local callbackConnection = bus:On(events.UIOpened, function(screenName)
				callbackValue = screenName
			end)
			local subscription = bus:Observe(events.UIClosed):Subscribe(function(screenName)
				observedValue = screenName
			end)
			local rxSignalConnection = bus:GetRxSignal(events.SoundRequested):Connect(function(soundName)
				rxSignalValue = soundName
			end)

			expect(bus:Has(events.UIOpened)).to.equal(true)
			expect(bus:Has(events.UIClosed)).to.equal(true)
			expect(bus:Has(events.SoundRequested)).to.equal(true)

			bus:Fire(events.UIOpened, "Inventory")
			bus:Fire(events.UIClosed, "Inventory")
			bus:Fire(events.SoundRequested, "OpenInventory")

			waitUntil(function()
				return callbackValue == "Inventory"
					and observedValue == "Inventory"
					and rxSignalValue == "OpenInventory"
			end, "client bus wrapper delivery")

			callbackConnection:Disconnect()
			subscription:Destroy()
			rxSignalConnection:Destroy()

			bus:Off(events.UIOpened)
			bus:Off(events.UIClosed)
			bus:Off(events.SoundRequested)

			expect(bus:Has(events.UIOpened)).to.equal(false)
			expect(bus:Has(events.UIClosed)).to.equal(false)
			expect(bus:Has(events.SoundRequested)).to.equal(false)

			withErrorOnUnknownEvent(EventBusClient.Utils, false, function()
				expect(bus:On("NotARealClientEvent", function() end)).to.equal(nil)
				expect(bus:Has("NotARealClientEvent")).to.equal(false)
			end)
		end)
	end)
end
