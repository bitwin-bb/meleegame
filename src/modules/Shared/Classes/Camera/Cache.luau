--!strict

local Cache = {}
Cache.__index = Cache

export type SubjectSnapshot = {
	key: string,
	kind: string,
	position: Vector3,
	velocity: Vector3,
	updatedAt: number,
}

export type FrameSnapshot = {
	frame: number,
	updatedAt: number,
	deltaTime: number,
	mode: string,
	reason: string,
	subjectKey: string?,
	subjectKind: string?,
	targetPosition: Vector3?,
	predictedPosition: Vector3?,
	cameraCFrame: CFrame?,
	fieldOfView: number?,
	hasOverride: boolean,
}

export type Cache = typeof(setmetatable(
	{} :: {
		frame: number,
		lastUpdatedAt: number,
		lastDeltaTime: number,
		subjects: { [string]: SubjectSnapshot },
		lastFrame: FrameSnapshot,
	},
	Cache
))

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

local function cloneFrameSnapshot(snapshot: FrameSnapshot): FrameSnapshot
	return {
		frame = snapshot.frame,
		updatedAt = snapshot.updatedAt,
		deltaTime = snapshot.deltaTime,
		mode = snapshot.mode,
		reason = snapshot.reason,
		subjectKey = snapshot.subjectKey,
		subjectKind = snapshot.subjectKind,
		targetPosition = snapshot.targetPosition,
		predictedPosition = snapshot.predictedPosition,
		cameraCFrame = snapshot.cameraCFrame,
		fieldOfView = snapshot.fieldOfView,
		hasOverride = snapshot.hasOverride,
	}
end

local function createDefaultFrameSnapshot(): FrameSnapshot
	return {
		frame = 0,
		updatedAt = 0,
		deltaTime = 1 / 60,
		mode = "Disabled",
		reason = "uninitialized",
		subjectKey = nil,
		subjectKind = nil,
		targetPosition = nil,
		predictedPosition = nil,
		cameraCFrame = nil,
		fieldOfView = nil,
		hasOverride = false,
	}
end

function Cache.New(): Cache
	return setmetatable({
		frame = 0,
		lastUpdatedAt = 0,
		lastDeltaTime = 1 / 60,
		subjects = {} :: { [string]: SubjectSnapshot },
		lastFrame = createDefaultFrameSnapshot(),
	}, Cache)
end

function Cache.Reset(self: Cache)
	self.frame = 0
	self.lastUpdatedAt = 0
	self.lastDeltaTime = 1 / 60
	table.clear(self.subjects)
	self.lastFrame = createDefaultFrameSnapshot()
end

function Cache.GetSubject(self: Cache, keyRaw: any): SubjectSnapshot?
	if typeof(keyRaw) ~= "string" or keyRaw == "" then
		return nil
	end
	return self.subjects[keyRaw]
end

function Cache.ResolveDerivedVelocity(
	self: Cache,
	keyRaw: any,
	positionRaw: any,
	nowRaw: any,
	fallbackVelocityRaw: any?
): Vector3
	local fallbackVelocity = if typeof(fallbackVelocityRaw) == "Vector3" then fallbackVelocityRaw else Vector3.zero
	if typeof(keyRaw) ~= "string" or keyRaw == "" or typeof(positionRaw) ~= "Vector3" then
		return fallbackVelocity
	end

	local previous = self.subjects[keyRaw]
	if previous == nil then
		return fallbackVelocity
	end

	local now = sanitizeNumber(nowRaw, os.clock(), 0, nil)
	local dt = now - previous.updatedAt
	if dt <= 1e-4 then
		return fallbackVelocity
	end

	local derivedVelocity = (positionRaw - previous.position) / dt
	if derivedVelocity.Magnitude <= 1e-4 then
		return fallbackVelocity
	end
	return derivedVelocity
end

function Cache.RememberSubject(
	self: Cache,
	keyRaw: any,
	kindRaw: any,
	positionRaw: any,
	velocityRaw: any,
	nowRaw: any
): SubjectSnapshot?
	if typeof(keyRaw) ~= "string" or keyRaw == "" or typeof(positionRaw) ~= "Vector3" then
		return nil
	end

	local snapshot: SubjectSnapshot = {
		key = keyRaw,
		kind = if typeof(kindRaw) == "string" and kindRaw ~= "" then kindRaw else "Unknown",
		position = positionRaw,
		velocity = if typeof(velocityRaw) == "Vector3" then velocityRaw else Vector3.zero,
		updatedAt = sanitizeNumber(nowRaw, os.clock(), 0, nil),
	}
	self.subjects[keyRaw] = snapshot
	return snapshot
end

function Cache.StoreFrame(self: Cache, snapshotRaw: any): FrameSnapshot
	local snapshot = if typeof(snapshotRaw) == "table" then snapshotRaw else {}
	self.frame += 1
	self.lastUpdatedAt = sanitizeNumber((snapshot :: any).updatedAt, os.clock(), 0, nil)
	self.lastDeltaTime = sanitizeNumber((snapshot :: any).deltaTime, self.lastDeltaTime, 0, 1)

	self.lastFrame = {
		frame = self.frame,
		updatedAt = self.lastUpdatedAt,
		deltaTime = self.lastDeltaTime,
		mode = if typeof((snapshot :: any).mode) == "string" then (snapshot :: any).mode else "Unknown",
		reason = if typeof((snapshot :: any).reason) == "string" then (snapshot :: any).reason else "",
		subjectKey = if typeof((snapshot :: any).subjectKey) == "string" then (snapshot :: any).subjectKey else nil,
		subjectKind = if typeof((snapshot :: any).subjectKind) == "string" then (snapshot :: any).subjectKind else nil,
		targetPosition = if typeof((snapshot :: any).targetPosition) == "Vector3" then (snapshot :: any).targetPosition else nil,
		predictedPosition = if typeof((snapshot :: any).predictedPosition) == "Vector3"
			then (snapshot :: any).predictedPosition
			else nil,
		cameraCFrame = if typeof((snapshot :: any).cameraCFrame) == "CFrame" then (snapshot :: any).cameraCFrame else nil,
		fieldOfView = if typeof((snapshot :: any).fieldOfView) == "number" then (snapshot :: any).fieldOfView else nil,
		hasOverride = (snapshot :: any).hasOverride == true,
	}

	return self:getFrame()
end

function Cache.GetFrame(self: Cache): FrameSnapshot
	return cloneFrameSnapshot(self.lastFrame)
end

function Cache.GetDebugState(self: Cache): { [string]: any }
	local frame = self.lastFrame
	return {
		frame = self.frame,
		updatedAt = self.lastUpdatedAt,
		deltaTime = self.lastDeltaTime,
		mode = frame.mode,
		reason = frame.reason,
		subjectKey = frame.subjectKey,
		subjectKind = frame.subjectKind,
		targetPosition = frame.targetPosition,
		predictedPosition = frame.predictedPosition,
		hasOverride = frame.hasOverride,
		fieldOfView = frame.fieldOfView,
	}
end

Cache.new = Cache.New
Cache.reset = Cache.Reset
Cache.getSubject = Cache.GetSubject
Cache.resolveDerivedVelocity = Cache.ResolveDerivedVelocity
Cache.rememberSubject = Cache.RememberSubject
Cache.storeFrame = Cache.StoreFrame
Cache.getFrame = Cache.GetFrame
Cache.getDebugState = Cache.GetDebugState

return Cache
