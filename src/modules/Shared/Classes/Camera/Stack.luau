--!strict

local Stack = {}
Stack.__index = Stack

export type OverrideEntry = {
	id: number,
	order: number,
	priority: number,
	kind: string,
	label: string,
	enabled: boolean,
	createdAt: number,
	expiresAt: number?,
	subject: any?,
	target: any?,
	position: Vector3?,
	velocity: Vector3?,
	lookPosition: Vector3?,
	cameraPosition: Vector3?,
	cameraCFrame: CFrame?,
	fieldOfView: number?,
	viewConfig: { [string]: any }?,
	predict: { [string]: any }?,
	sideSign: number?,
	movementBackAmount: number?,
	mouseInfluenceX: number?,
	mouseInfluenceY: number?,
	disableRoom: boolean?,
	disableMovementBack: boolean?,
	disableMouseInfluence: boolean?,
	runtimeId: string?,
	bossId: string?,
	encounterChannel: string?,
	metadata: { [string]: any }?,
}

export type Stack = typeof(setmetatable(
	{} :: {
		nextId: number,
		nextOrder: number,
		entries: { [number]: OverrideEntry },
	},
	Stack
))

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function cloneDictionary(sourceRaw: any): { [string]: any }?
	if typeof(sourceRaw) ~= "table" then
		return nil
	end
	local clone = {}
	for key, value in sourceRaw do
		clone[key] = value
	end
	return clone
end

local function cloneEntry(entry: OverrideEntry): OverrideEntry
	return {
		id = entry.id,
		order = entry.order,
		priority = entry.priority,
		kind = entry.kind,
		label = entry.label,
		enabled = entry.enabled,
		createdAt = entry.createdAt,
		expiresAt = entry.expiresAt,
		subject = entry.subject,
		target = entry.target,
		position = entry.position,
		velocity = entry.velocity,
		lookPosition = entry.lookPosition,
		cameraPosition = entry.cameraPosition,
		cameraCFrame = entry.cameraCFrame,
		fieldOfView = entry.fieldOfView,
		viewConfig = cloneDictionary(entry.viewConfig),
		predict = cloneDictionary(entry.predict),
		sideSign = entry.sideSign,
		movementBackAmount = entry.movementBackAmount,
		mouseInfluenceX = entry.mouseInfluenceX,
		mouseInfluenceY = entry.mouseInfluenceY,
		disableRoom = entry.disableRoom,
		disableMovementBack = entry.disableMovementBack,
		disableMouseInfluence = entry.disableMouseInfluence,
		runtimeId = entry.runtimeId,
		bossId = entry.bossId,
		encounterChannel = entry.encounterChannel,
		metadata = cloneDictionary(entry.metadata),
	}
end

local function isExpired(entry: OverrideEntry, now: number): boolean
	return entry.expiresAt ~= nil and now >= entry.expiresAt
end

function Stack.New(): Stack
	return setmetatable({
		nextId = 0,
		nextOrder = 0,
		entries = {} :: { [number]: OverrideEntry },
	}, Stack)
end

function Stack.Push(self: Stack, entryRaw: any): number
	local source = if typeof(entryRaw) == "table" then entryRaw else {}
	self.nextId += 1
	self.nextOrder += 1

	local now = os.clock()
	local durationSeconds = if typeof((source :: any).durationSeconds) == "number" and (source :: any).durationSeconds >= 0
		then (source :: any).durationSeconds
		else nil
	local explicitExpiresAt = if typeof((source :: any).expiresAt) == "number" then (source :: any).expiresAt else nil

	local entry: OverrideEntry = {
		id = self.nextId,
		order = self.nextOrder,
		priority = math.floor(sanitizeNumber((source :: any).priority, 0, -1000000, 1000000)),
		kind = if trim((source :: any).kind) ~= "" then trim((source :: any).kind) else "Override",
		label = if trim((source :: any).label) ~= "" then trim((source :: any).label) else "",
		enabled = (source :: any).enabled ~= false,
		createdAt = now,
		expiresAt = if explicitExpiresAt ~= nil then explicitExpiresAt else if durationSeconds ~= nil then now + durationSeconds else nil,
		subject = (source :: any).subject,
		target = (source :: any).target,
		position = if typeof((source :: any).position) == "Vector3" then (source :: any).position else nil,
		velocity = if typeof((source :: any).velocity) == "Vector3" then (source :: any).velocity else nil,
		lookPosition = if typeof((source :: any).lookPosition) == "Vector3" then (source :: any).lookPosition else nil,
		cameraPosition = if typeof((source :: any).cameraPosition) == "Vector3" then (source :: any).cameraPosition else nil,
		cameraCFrame = if typeof((source :: any).cameraCFrame) == "CFrame" then (source :: any).cameraCFrame else nil,
		fieldOfView = if typeof((source :: any).fieldOfView) == "number" then (source :: any).fieldOfView else nil,
		viewConfig = cloneDictionary((source :: any).viewConfig),
		predict = cloneDictionary((source :: any).predict),
		sideSign = if typeof((source :: any).sideSign) == "number" then (source :: any).sideSign else nil,
		movementBackAmount = if typeof((source :: any).movementBackAmount) == "number"
			then (source :: any).movementBackAmount
			else nil,
		mouseInfluenceX = if typeof((source :: any).mouseInfluenceX) == "number"
			then (source :: any).mouseInfluenceX
			else nil,
		mouseInfluenceY = if typeof((source :: any).mouseInfluenceY) == "number"
			then (source :: any).mouseInfluenceY
			else nil,
		disableRoom = if typeof((source :: any).disableRoom) == "boolean" then (source :: any).disableRoom else nil,
		disableMovementBack = if typeof((source :: any).disableMovementBack) == "boolean"
			then (source :: any).disableMovementBack
			else nil,
		disableMouseInfluence = if typeof((source :: any).disableMouseInfluence) == "boolean"
			then (source :: any).disableMouseInfluence
			else nil,
		runtimeId = if trim((source :: any).runtimeId) ~= "" then trim((source :: any).runtimeId) else nil,
		bossId = if trim((source :: any).bossId) ~= "" then trim((source :: any).bossId) else nil,
		encounterChannel = if trim((source :: any).encounterChannel) ~= ""
			then trim((source :: any).encounterChannel)
			else if trim((source :: any).channel) ~= "" then trim((source :: any).channel) else nil,
		metadata = cloneDictionary((source :: any).metadata),
	}

	self.entries[entry.id] = entry
	return entry.id
end

function Stack.Update(self: Stack, idRaw: any, patchRaw: any): boolean
	if typeof(idRaw) ~= "number" or typeof(patchRaw) ~= "table" then
		return false
	end

	local id = math.floor(idRaw)
	local entry = self.entries[id]
	if entry == nil then
		return false
	end

	local patch = patchRaw :: any
	for key, value in patch do
		if key ~= "id" and key ~= "order" and key ~= "createdAt" then
			(entry :: any)[key] = value
		end
	end
	return true
end

function Stack.Remove(self: Stack, idRaw: any): boolean
	if typeof(idRaw) ~= "number" then
		return false
	end
	local id = math.floor(idRaw)
	if self.entries[id] == nil then
		return false
	end
	self.entries[id] = nil
	return true
end

function Stack.Clear(self: Stack)
	table.clear(self.entries)
end

function Stack.PruneExpired(self: Stack, nowRaw: any)
	local now = sanitizeNumber(nowRaw, os.clock(), 0, nil)
	for id, entry in self.entries do
		if entry.enabled ~= true or isExpired(entry, now) then
			self.entries[id] = nil
		end
	end
end

function Stack.Resolve(self: Stack, nowRaw: any): OverrideEntry?
	local now = sanitizeNumber(nowRaw, os.clock(), 0, nil)
	self:pruneExpired(now)

	local bestEntry = nil :: OverrideEntry?
	for _, entry in self.entries do
		if entry.enabled ~= true then
			continue
		end
		if bestEntry == nil then
			bestEntry = entry
			continue
		end
		if entry.priority > bestEntry.priority or (entry.priority == bestEntry.priority and entry.order > bestEntry.order) then
			bestEntry = entry
		end
	end

	if bestEntry == nil then
		return nil
	end
	return cloneEntry(bestEntry)
end

function Stack.GetEntries(self: Stack, nowRaw: any): { OverrideEntry }
	local now = sanitizeNumber(nowRaw, os.clock(), 0, nil)
	self:pruneExpired(now)

	local entries = {}
	for _, entry in self.entries do
		entries[#entries + 1] = cloneEntry(entry)
	end
	table.sort(entries, function(left: OverrideEntry, right: OverrideEntry): boolean
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return left.order > right.order
	end)
	return entries
end

Stack.new = Stack.New
Stack.push = Stack.Push
Stack.update = Stack.Update
Stack.remove = Stack.Remove
Stack.clear = Stack.Clear
Stack.pruneExpired = Stack.PruneExpired
Stack.resolve = Stack.Resolve
Stack.getEntries = Stack.GetEntries

return Stack
