local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaidTaskUtils = require("MaidTaskUtils")
local Sift: any = require(ReplicatedStorage.Packages.Sift)

local ReactiveState = {}

local BaseValue = {}
BaseValue.__index = BaseValue

local MutableState = {}
MutableState.__index = MutableState
setmetatable(MutableState, BaseValue)

local ComputedState = {}
ComputedState.__index = ComputedState
setmetatable(ComputedState, BaseValue)

export type Subscription = () -> ()

export type BaseValue<T> = any
export type MutableState<T> = any
export type ComputedState<T> = any

local nextValueId = 0
local nextSubscriberId = 0
local activeCollector: any? = nil

local function noop() end

local function safeDisconnect(connection: any?)
	if connection == nil or not MaidTaskUtils.isValidTask(connection) then
		return
	end
	pcall(function()
		MaidTaskUtils.doTask(connection)
	end)
end

function BaseValue._subscribeInternal(self: any, callback: any): Subscription
	if self.destroyed or typeof(callback) ~= "function" then
		return noop
	end
	nextSubscriberId += 1
	local subscriberId = nextSubscriberId
	self.subscribers[subscriberId] = callback
	return function()
		self.subscribers[subscriberId] = nil
	end
end

function BaseValue._emit(self: any, nextValue: any, prevValue: any)
	for _, callback in self.subscribers do
		callback(nextValue, prevValue)
	end
end

function BaseValue.Subscribe(self: any, callback: any): Subscription
	return self:_subscribeInternal(callback)
end

function BaseValue.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	table.clear(self.subscribers)
end

function MutableState.new<T>(initialValue: T): MutableState<T>
	nextValueId += 1
	local self = setmetatable({
		kind = "state",
		id = nextValueId,
		value = initialValue,
		destroyed = false,
		subscribers = {} :: { [number]: (nextValue: T, prevValue: T) -> () },
	}, MutableState)
	return self :: any
end

function MutableState.Get<T>(self: MutableState<T>): T
	if activeCollector ~= nil then
		activeCollector:_collectDependency(self)
	end
	return self.value
end

function MutableState.Set<T>(self: MutableState<T>, nextValue: T): boolean
	if self.destroyed then
		return false
	end
	if self.value == nextValue then
		return false
	end
	local prevValue = self.value
	self.value = nextValue
	self:_emit(nextValue, prevValue)
	return true
end

function MutableState.Update<T>(self: MutableState<T>, updater: (prevValue: T) -> T): boolean
	if self.destroyed then
		return false
	end
	if typeof(updater) ~= "function" then
		return false
	end
	return self:Set(updater(self.value))
end

MutableState.Subscribe = BaseValue.Subscribe
MutableState.Destroy = BaseValue.Destroy

function ComputedState.new<T>(compute: () -> T): ComputedState<T>
	nextValueId += 1
	local self = setmetatable({
		kind = "computed",
		id = nextValueId,
		compute = compute,
		value = nil :: any,
		hasValue = false,
		dirty = true,
		destroyed = false,
		subscribers = {} :: { [number]: (nextValue: T, prevValue: T) -> () },
		dependencies = {} :: { [any]: true },
		dependencySubscriptions = {} :: { [any]: Subscription },
	}, ComputedState)
	self:_recompute()
	return self :: any
end

function ComputedState._collectDependency(self: any, dependency: any)
	if self.dependencies[dependency] ~= nil then
		return
	end
	self.dependencies[dependency] = true
end

function ComputedState._clearDependencies(self: any)
	for dependency, disconnect in self.dependencySubscriptions do
		disconnect()
		self.dependencySubscriptions[dependency] = nil
	end
	table.clear(self.dependencies)
end

function ComputedState._recompute(self: any)
	if self.destroyed then
		return
	end
	local previousCollector = activeCollector
	self:_clearDependencies()
	activeCollector = self
	local ok, result = pcall(self.compute)
	activeCollector = previousCollector
	if not ok then
		return
	end

	for dependency in self.dependencies do
		self.dependencySubscriptions[dependency] = dependency:Subscribe(function()
			self:_markDirty()
		end)
	end

	local prevValue = self.value
	local changed = (not self.hasValue) or prevValue ~= result
	self.value = result
	self.hasValue = true
	self.dirty = false
	if changed then
		self:_emit(self.value, prevValue)
	end
end

function ComputedState._markDirty(self: any)
	if self.destroyed then
		return
	end
	if self.dirty then
		return
	end
	self.dirty = true
	self:_recompute()
end

function ComputedState.Get<T>(self: ComputedState<T>): T
	if activeCollector ~= nil then
		activeCollector:_collectDependency(self)
	end
	if self.dirty then
		local selfAny = self :: any
		selfAny:_recompute()
	end
	return (self :: any).value
end

function ComputedState.Destroy<T>(self: ComputedState<T>)
	if self.destroyed then
		return
	end
	local selfAny = self :: any
	selfAny:_clearDependencies()
	BaseValue.Destroy(self :: any)
end

ComputedState.Subscribe = BaseValue.Subscribe

function ReactiveState.CreateState<T>(initialValue: T): MutableState<T>
	return MutableState.new(initialValue)
end

function ReactiveState.Computed<T>(compute: () -> T): ComputedState<T>
	if typeof(compute) ~= "function" then
		error("ReactiveState.Computed expects a callback")
	end
	return ComputedState.new(compute)
end

function ReactiveState.Bind(instanceRaw: any, propertyRaw: any, sourceRaw: any, transformRaw: any?): Subscription
	if typeof(instanceRaw) ~= "Instance" then
		return noop
	end
	if typeof(propertyRaw) ~= "string" or propertyRaw == "" then
		return noop
	end
	if typeof(sourceRaw) ~= "table" then
		return noop
	end

	local instance = instanceRaw :: Instance
	local source = sourceRaw :: any
	local getValue = if typeof(source.Get) == "function" then source.Get else source.get
	local subscribe = if typeof(source.Subscribe) == "function" then source.Subscribe else source.subscribe
	if typeof(getValue) ~= "function" or typeof(subscribe) ~= "function" then
		return noop
	end
	local property = propertyRaw :: string
	local transform = if typeof(transformRaw) == "function" then transformRaw else nil

	local alive = true
	local function apply(value: any)
		if not alive then
			return
		end
		local nextValue = if transform ~= nil then transform(value) else value
		pcall(function()
			(instance :: any)[property] = nextValue
		end)
	end

	apply(getValue(source))
	local disconnectSource = subscribe(source, function(nextValue: any)
		apply(nextValue)
	end)

	local destroyingConnection = nil
	local ancestryConnection = nil
	if typeof((instance :: any).Destroying) == "RBXScriptSignal" then
		destroyingConnection = (instance :: any).Destroying:Connect(function()
			alive = false
			disconnectSource()
			safeDisconnect(ancestryConnection)
		end)
	end
	ancestryConnection = instance.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			alive = false
			disconnectSource()
			safeDisconnect(destroyingConnection)
			safeDisconnect(ancestryConnection)
		end
	end)

	return function()
		if not alive then
			return
		end
		alive = false
		disconnectSource()
		safeDisconnect(destroyingConnection)
		safeDisconnect(ancestryConnection)
	end
end

function ReactiveState.Combine(sourceListRaw: any, compute: (...any) -> any): ComputedState<any>
	if typeof(sourceListRaw) ~= "table" then
		error("ReactiveState.Combine expects a source list")
	end
	if typeof(compute) ~= "function" then
		error("ReactiveState.Combine expects a compute callback")
	end
	local sourceList = sourceListRaw :: { any }
	return ReactiveState.Computed(function()
		local values = Sift.Array.create(#sourceList)
		for index = 1, #sourceList do
			local source = sourceList[index]
			local getValue = if typeof(source.Get) == "function" then source.Get else source.get
			values[index] = getValue(source)
		end
		return compute(table.unpack(values, 1, #values))
	end)
end

function ReactiveState.FromAttributeCache(
	attributeCacheRaw: any,
	instanceRaw: any,
	attributeRaw: any,
	defaultValue: any?
): MutableState<any>
	local initialValue = defaultValue
	if typeof(instanceRaw) == "Instance" then
		if attributeCacheRaw ~= nil and typeof(attributeCacheRaw.Get) == "function" then
			initialValue = attributeCacheRaw:Get(instanceRaw, attributeRaw, defaultValue)
		elseif typeof(attributeRaw) == "string" then
			initialValue = instanceRaw:GetAttribute(attributeRaw)
			if initialValue == nil then
				initialValue = defaultValue
			end
		end
	end
	local state = ReactiveState.CreateState(initialValue)
	local disconnect: Subscription? = nil
	local connection: RBXScriptConnection? = nil

	if attributeCacheRaw ~= nil and typeof(attributeCacheRaw.OnChanged) == "function" then
		disconnect = attributeCacheRaw:OnChanged(instanceRaw, attributeRaw, function(_, _, nextValue)
			state:Set(nextValue)
		end)
	elseif typeof(instanceRaw) == "Instance" and typeof(attributeRaw) == "string" then
		connection = instanceRaw:GetAttributeChangedSignal(attributeRaw):Connect(function()
			local value = instanceRaw:GetAttribute(attributeRaw)
			if value == nil then
				value = defaultValue
			end
			state:Set(value)
		end)
	end

	local baseDestroy = state.Destroy
	function state.Destroy(selfState)
		if disconnect ~= nil then
			disconnect()
			disconnect = nil
		end
		safeDisconnect(connection)
		connection = nil
		baseDestroy(selfState)
	end
	return state
end
return ReactiveState
