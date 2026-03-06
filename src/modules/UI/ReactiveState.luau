--!strict
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

export type BaseValue<T> = {
	kind: string,
	id: number,
	destroyed: boolean,
	get: (self: BaseValue<T>) -> T,
	subscribe: (self: BaseValue<T>, callback: (nextValue: T, prevValue: T) -> ()) -> Subscription,
	destroy: (self: BaseValue<T>) -> (),
}

export type MutableState<T> = BaseValue<T> & {
	set: (self: MutableState<T>, nextValue: T) -> boolean,
	update: (self: MutableState<T>, updater: (prevValue: T) -> T) -> boolean,
}

export type ComputedState<T> = BaseValue<T>

local nextValueId = 0
local nextSubscriberId = 0
local activeCollector: any? = nil

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function noop()
end

local function safeDisconnect(connection: any?)
	if connection == nil then
		return
	end
	pcall(function()
		connection:Disconnect()
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

function BaseValue.subscribe(self: any, callback: any): Subscription
	return self:_subscribeInternal(callback)
end

function BaseValue.destroy(self: any)
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

function MutableState.get<T>(self: MutableState<T>): T
	if activeCollector ~= nil then
		activeCollector:_collectDependency(self)
	end
	return self.value
end

function MutableState.set<T>(self: MutableState<T>, nextValue: T): boolean
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

function MutableState.update<T>(self: MutableState<T>, updater: (prevValue: T) -> T): boolean
	if self.destroyed then
		return false
	end
	if typeof(updater) ~= "function" then
		return false
	end
	return self:set(updater(self.value))
end

MutableState.subscribe = BaseValue.subscribe
MutableState.destroy = BaseValue.destroy

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
		warn(string.format("[ReactiveState] Computed callback failed: %s", tostring(result)))
		return
	end

	for dependency in self.dependencies do
		self.dependencySubscriptions[dependency] = dependency:subscribe(function()
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

function ComputedState.get<T>(self: ComputedState<T>): T
	if activeCollector ~= nil then
		activeCollector:_collectDependency(self)
	end
	if self.dirty then
		local selfAny = self :: any
		selfAny:_recompute()
	end
	return (self :: any).value
end

function ComputedState.destroy<T>(self: ComputedState<T>)
	if self.destroyed then
		return
	end
	local selfAny = self :: any
	selfAny:_clearDependencies()
	BaseValue.destroy(self :: any)
end

ComputedState.subscribe = BaseValue.subscribe

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
	if typeof(sourceRaw) ~= "table" or typeof(sourceRaw.get) ~= "function" or typeof(sourceRaw.subscribe) ~= "function" then
		return noop
	end

	local instance = instanceRaw :: Instance
	local source = sourceRaw :: any
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

	apply(source:get())
	local disconnectSource = source:subscribe(function(nextValue: any)
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
		local values = table.create(#sourceList)
		for index = 1, #sourceList do
			values[index] = sourceList[index]:get()
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
		if attributeCacheRaw ~= nil and typeof(attributeCacheRaw.get) == "function" then
			initialValue = attributeCacheRaw:get(instanceRaw, attributeRaw, defaultValue)
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

	if attributeCacheRaw ~= nil and typeof(attributeCacheRaw.onChanged) == "function" then
		disconnect = attributeCacheRaw:onChanged(instanceRaw, attributeRaw, function(_, _, nextValue)
			state:set(nextValue)
		end)
	elseif typeof(instanceRaw) == "Instance" and typeof(attributeRaw) == "string" then
		connection = instanceRaw:GetAttributeChangedSignal(attributeRaw):Connect(function()
			local value = instanceRaw:GetAttribute(attributeRaw)
			if value == nil then
				value = defaultValue
			end
			state:set(value)
		end)
	end

	local baseDestroy = state.destroy
	function state.destroy(selfState)
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
