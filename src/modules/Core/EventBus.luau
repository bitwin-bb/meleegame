--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local EventBus = {}
EventBus.__index = EventBus

export type EventHandler = (payload: any, eventName: string, channel: string) -> ()

export type ListenerRecord = {
	id: number,
	priority: number,
	order: number,
	eventName: string,
	handler: EventHandler,
	once: boolean,
	channel: string,
	active: boolean,
}

export type ChannelBucket = {
	listenersByEvent: { [string]: { ListenerRecord } },
}

export type EventBus = typeof(setmetatable({} :: any, EventBus))

local function clampPriority(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" then
		return fallback
	end
	local value = math.floor(valueRaw)
	if value < -1000000 then
		return -1000000
	end
	if value > 1000000 then
		return 1000000
	end
	return value
end

local function normalizeChannel(channelRaw: any): string
	if typeof(channelRaw) ~= "string" or channelRaw == "" then
		return "default"
	end
	return channelRaw
end

local function normalizeEventName(eventRaw: any): string
	if typeof(eventRaw) ~= "string" or eventRaw == "" then
		return "*"
	end
	return eventRaw
end

local function splitChannel(channel: string): { string }
	local out = {}
	local startIndex = 1
	while startIndex <= #channel do
		local dotIndex = string.find(channel, ".", startIndex, true)
		if dotIndex == nil then
			out[#out + 1] = string.sub(channel, startIndex)
			break
		end
		out[#out + 1] = string.sub(channel, startIndex, dotIndex - 1)
		startIndex = dotIndex + 1
	end
	if #out == 0 then
		out[1] = channel
	end
	return out
end

local function buildScopedChannels(channel: string): { string }
	if channel == "*" then
		return { "*" }
	end
	local parts = splitChannel(channel)
	local out = Sift.Array.create(#parts + 1)
	out[1] = "*"
	local cursor = ""
	for index = 1, #parts do
		if cursor == "" then
			cursor = parts[index]
		else
			cursor = cursor .. "." .. parts[index]
		end
		out[#out + 1] = cursor
	end
	return out
end

local function compareDispatchRecords(a: any, b: any): boolean
	if a.priority ~= b.priority then
		return a.priority > b.priority
	end
	if a.channelDepth ~= b.channelDepth then
		return a.channelDepth > b.channelDepth
	end
	return a.order < b.order
end

function EventBus.new(): EventBus
	local self = setmetatable({
		channels = {} :: { [string]: ChannelBucket },
		listenerById = {} :: { [number]: ListenerRecord },
		nextListenerId = 0,
		nextOrder = 0,
	}, EventBus)
	return self
end

function EventBus._getOrCreateBucket(self: EventBus, channel: string): ChannelBucket
	local bucket = self.channels[channel]
	if bucket ~= nil then
		return bucket
	end
	bucket = {
		listenersByEvent = {},
	}
	self.channels[channel] = bucket
	return bucket
end

function EventBus._addListener(self: EventBus, channelRaw: any, eventNameRaw: any, handler: EventHandler, priorityRaw: any, once: boolean): () -> ()
	if typeof(handler) ~= "function" then
		return function() end
	end
	local channel = normalizeChannel(channelRaw)
	local eventName = normalizeEventName(eventNameRaw)
	local priority = clampPriority(priorityRaw, 0)

	self.nextListenerId += 1
	self.nextOrder += 1
	local listenerId = self.nextListenerId
	local record = {
		id = listenerId,
		priority = priority,
		order = self.nextOrder,
		eventName = eventName,
		handler = handler,
		once = once,
		channel = channel,
		active = true,
	} :: ListenerRecord

	local bucket = self:_getOrCreateBucket(channel)
	local listeners = bucket.listenersByEvent[eventName]
	if listeners == nil then
		listeners = {}
		bucket.listenersByEvent[eventName] = listeners
	end
	listeners[#listeners + 1] = record
	self.listenerById[listenerId] = record

	return function()
		self:unsubscribe(listenerId)
	end
end

function EventBus.subscribe(self: EventBus, channelRaw: any, eventNameRaw: any, handler: EventHandler, priorityRaw: any): () -> ()
	return self:_addListener(channelRaw, eventNameRaw, handler, priorityRaw, false)
end

function EventBus.once(self: EventBus, channelRaw: any, eventNameRaw: any, handler: EventHandler, priorityRaw: any): () -> ()
	return self:_addListener(channelRaw, eventNameRaw, handler, priorityRaw, true)
end

function EventBus.unsubscribe(self: EventBus, listenerIdRaw: any)
	if typeof(listenerIdRaw) ~= "number" then
		return
	end
	local listenerId = math.floor(listenerIdRaw)
	local record = self.listenerById[listenerId]
	if record == nil then
		return
	end
	record.active = false
	self.listenerById[listenerId] = nil

	local bucket = self.channels[record.channel]
	if bucket == nil then
		return
	end
	local listeners = bucket.listenersByEvent[record.eventName]
	if listeners == nil then
		return
	end
	for index = #listeners, 1, -1 do
		if listeners[index].id == listenerId then
			table.remove(listeners, index)
			break
		end
	end
	if #listeners == 0 then
		bucket.listenersByEvent[record.eventName] = nil
	end
	if next(bucket.listenersByEvent) == nil then
		self.channels[record.channel] = nil
	end
end

function EventBus.publish(self: EventBus, channelRaw: any, eventNameRaw: any, payload: any): number
	local channel = normalizeChannel(channelRaw)
	local eventName = normalizeEventName(eventNameRaw)
	local scopedChannels = buildScopedChannels(channel)

	local dispatch = {}
	for scopedIndex = 1, #scopedChannels do
		local scopedChannel = scopedChannels[scopedIndex]
		local bucket = self.channels[scopedChannel]
		if bucket == nil then
			continue
		end

		local exactListeners = bucket.listenersByEvent[eventName]
		if exactListeners ~= nil then
			for _, record in exactListeners do
				if record.active then
					dispatch[#dispatch + 1] = {
						record = record,
						priority = record.priority,
						order = record.order,
						channelDepth = scopedIndex,
					}
				end
			end
		end

		local wildcardListeners = bucket.listenersByEvent["*"]
		if wildcardListeners ~= nil then
			for _, record in wildcardListeners do
				if record.active then
					dispatch[#dispatch + 1] = {
						record = record,
						priority = record.priority,
						order = record.order,
						channelDepth = scopedIndex,
					}
				end
			end
		end
	end

	if #dispatch == 0 then
		return 0
	end

	table.sort(dispatch, compareDispatchRecords)
	local fired = 0
	for index = 1, #dispatch do
		local record = dispatch[index].record :: ListenerRecord
		if record.active then
			fired += 1
			local ok, err = pcall(record.handler, payload, eventName, channel)
			if not ok then
				warn(string.format("[EventBus] listener error on %s:%s -> %s", channel, eventName, tostring(err)))
			end
			if record.once then
				self:unsubscribe(record.id)
			end
		end
	end

	return fired
end

function EventBus.clearChannel(self: EventBus, channelRaw: any)
	local channel = normalizeChannel(channelRaw)
	local bucket = self.channels[channel]
	if bucket == nil then
		return
	end
	for _, listeners in bucket.listenersByEvent do
		for _, record in listeners do
			record.active = false
			self.listenerById[record.id] = nil
		end
	end
	self.channels[channel] = nil
end

function EventBus.destroy(self: EventBus)
	local channels = {}
	for channel in self.channels do
		channels[#channels + 1] = channel
	end
	for _, channel in channels do
		self:clearChannel(channel)
	end
	table.clear(self.channels)
	table.clear(self.listenerById)
end

return EventBus
