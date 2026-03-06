--!strict

local TagQuery = {}
TagQuery.__index = TagQuery

export type TagProvider = {
	GetTagged: (self: any, tag: string) -> { any },
	HasTag: ((self: any, instance: any, tag: string) -> boolean)?,
	GetTags: ((self: any, instance: any) -> { string })?,
	GetInstanceAddedSignal: ((self: any, tag: string) -> any)?,
	GetInstanceRemovedSignal: ((self: any, tag: string) -> any)?,
}

export type TagListener = (instance: any, isAdded: boolean, tag: string) -> ()

export type TagQuery = typeof(setmetatable({} :: any, TagQuery))

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function connectSignal(signal: any, callback: (...any) -> ()): any?
	if signal == nil then
		return nil
	end
	local ok, connection = pcall(function()
		return signal:Connect(callback)
	end)
	if not ok then
		return nil
	end
	return connection
end

function TagQuery.new(providerRaw: any): TagQuery
	if typeof(providerRaw) ~= "table" or typeof((providerRaw :: any).GetTagged) ~= "function" then
		error("TagQuery.new expects a provider with GetTagged(tag)")
	end
	local self = setmetatable({
		provider = providerRaw :: TagProvider,
		tagLists = {} :: { [string]: { any } },
		tagSets = {} :: { [string]: { [any]: true } },
		tagVersions = {} :: { [string]: number },
		listeners = {} :: { [string]: { [number]: TagListener } },
		nextListenerId = 0,
		tagConnections = {} :: { [string]: { any? } },
	}, TagQuery)
	return self
end

function TagQuery._refreshTag(self: TagQuery, tag: string)
	local list = self.provider:GetTagged(tag)
	if typeof(list) ~= "table" then
		list = {}
	end

	local outList = table.create(#list)
	local outSet = {}
	for index = 1, #list do
		local instance = list[index]
		if outSet[instance] == nil then
			outSet[instance] = true
			outList[#outList + 1] = instance
		end
	end

	self.tagLists[tag] = outList
	self.tagSets[tag] = outSet
	self.tagVersions[tag] = (self.tagVersions[tag] or 0) + 1
end

function TagQuery._ensureTagSignals(self: TagQuery, tag: string)
	if self.tagConnections[tag] ~= nil then
		return
	end

	local addedConnection = nil
	local removedConnection = nil

	local getAdded = self.provider.GetInstanceAddedSignal
	if getAdded ~= nil then
		local ok, signal = pcall(function()
			return getAdded(self.provider, tag)
		end)
		if ok then
			addedConnection = connectSignal(signal, function(instance: any)
				if self.tagLists[tag] == nil then
					self:_refreshTag(tag)
				end
				local list = self.tagLists[tag]
				local set = self.tagSets[tag]
				if list == nil or set == nil then
					return
				end
				if set[instance] == nil then
					set[instance] = true
					list[#list + 1] = instance
					self.tagVersions[tag] = (self.tagVersions[tag] or 0) + 1
					local tagListeners = self.listeners[tag]
					if tagListeners ~= nil then
						for _, listener in tagListeners do
							listener(instance, true, tag)
						end
					end
				end
			end)
		end
	end

	local getRemoved = self.provider.GetInstanceRemovedSignal
	if getRemoved ~= nil then
		local ok, signal = pcall(function()
			return getRemoved(self.provider, tag)
		end)
		if ok then
			removedConnection = connectSignal(signal, function(instance: any)
				local list = self.tagLists[tag]
				local set = self.tagSets[tag]
				if list == nil or set == nil then
					return
				end
				if set[instance] ~= nil then
					set[instance] = nil
					for index = #list, 1, -1 do
						if list[index] == instance then
							table.remove(list, index)
							break
						end
					end
					self.tagVersions[tag] = (self.tagVersions[tag] or 0) + 1
					local tagListeners = self.listeners[tag]
					if tagListeners ~= nil then
						for _, listener in tagListeners do
							listener(instance, false, tag)
						end
					end
				end
			end)
		end
	end

	self.tagConnections[tag] = { addedConnection, removedConnection }
end

function TagQuery.getTagged(self: TagQuery, tagRaw: any): { any }
	if typeof(tagRaw) ~= "string" or tagRaw == "" then
		return {}
	end
	if self.tagLists[tagRaw] == nil then
		self:_refreshTag(tagRaw)
	end
	self:_ensureTagSignals(tagRaw)
	return self.tagLists[tagRaw] or {}
end

function TagQuery.hasTag(self: TagQuery, instance: any, tagRaw: any): boolean
	if typeof(tagRaw) ~= "string" or tagRaw == "" then
		return false
	end
	if self.tagSets[tagRaw] == nil then
		self:_refreshTag(tagRaw)
	end
	self:_ensureTagSignals(tagRaw)
	local set = self.tagSets[tagRaw]
	if set ~= nil and set[instance] ~= nil then
		return true
	end
	local hasTag = self.provider.HasTag
	if hasTag ~= nil then
		local ok, result = pcall(hasTag, self.provider, instance, tagRaw)
		if ok and result then
			return true
		end
	end
	return false
end

function TagQuery.getVersion(self: TagQuery, tagRaw: any): number
	if typeof(tagRaw) ~= "string" then
		return 0
	end
	return self.tagVersions[tagRaw] or 0
end

function TagQuery.subscribe(self: TagQuery, tagRaw: any, listener: TagListener): () -> ()
	if typeof(tagRaw) ~= "string" or tagRaw == "" then
		return function() end
	end
	if typeof(listener) ~= "function" then
		return function() end
	end

	if self.listeners[tagRaw] == nil then
		self.listeners[tagRaw] = {}
	end
	self.nextListenerId += 1
	local listenerId = self.nextListenerId
	self.listeners[tagRaw][listenerId] = listener

	if self.tagLists[tagRaw] == nil then
		self:_refreshTag(tagRaw)
	end
	self:_ensureTagSignals(tagRaw)

	return function()
		local byTag = self.listeners[tagRaw]
		if byTag ~= nil then
			byTag[listenerId] = nil
			if next(byTag) == nil then
				self.listeners[tagRaw] = nil
			end
		end
	end
end

function TagQuery.observeTag(self: TagQuery, tagRaw: any, onAdded: ((instance: any, tag: string) -> ())?, onRemoved: ((instance: any, tag: string) -> ())?): () -> ()
	if typeof(tagRaw) ~= "string" or tagRaw == "" then
		return function() end
	end

	if onAdded ~= nil then
		local tagged = self:getTagged(tagRaw)
		for index = 1, #tagged do
			onAdded(tagged[index], tagRaw)
		end
	end

	return self:subscribe(tagRaw, function(instance, isAdded, tag)
		if isAdded then
			if onAdded ~= nil then
				onAdded(instance, tag)
			end
		else
			if onRemoved ~= nil then
				onRemoved(instance, tag)
			end
		end
	end)
end

function TagQuery.invalidate(self: TagQuery, tagRaw: any?)
	if tagRaw == nil then
		table.clear(self.tagLists)
		table.clear(self.tagSets)
		table.clear(self.tagVersions)
		return
	end
	if typeof(tagRaw) ~= "string" or tagRaw == "" then
		return
	end
	self.tagLists[tagRaw] = nil
	self.tagSets[tagRaw] = nil
	self.tagVersions[tagRaw] = nil
end

function TagQuery.destroy(self: TagQuery)
	for _, connections in self.tagConnections do
		for _, connection in connections do
			if connection ~= nil then
				pcall(function()
					connection:Disconnect()
				end)
			end
		end
	end
	table.clear(self.tagConnections)
	for _, byTag in self.listeners do
		table.clear(byTag)
	end
	table.clear(self.listeners)
	for _, list in self.tagLists do
		clearArray(list)
	end
	table.clear(self.tagLists)
	table.clear(self.tagSets)
	table.clear(self.tagVersions)
end

return TagQuery
