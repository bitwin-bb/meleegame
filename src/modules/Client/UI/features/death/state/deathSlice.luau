--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type DeathState = {
	visible: boolean,
	message: string,
	diedAt: number?,
	respawnAt: number?,
	respawnDelay: number,
	sequence: number,
	updatedAt: number,
}

export type ShowDeathPayload = {
	message: string?,
	diedAt: number?,
	respawnAt: number?,
	respawnDelay: number?,
}

local DEFAULT_MESSAGE = "You were slain..."
local DEFAULT_RESPAWN_DELAY = 5
local MIN_RESPAWN_DELAY = 0.1
local MAX_RESPAWN_DELAY = 120

local DEFAULT_STATE: DeathState = {
	visible = false,
	message = DEFAULT_MESSAGE,
	diedAt = nil,
	respawnAt = nil,
	respawnDelay = DEFAULT_RESPAWN_DELAY,
	sequence = 0,
	updatedAt = os.clock(),
}

local deathStateAtom: Charm.Atom<DeathState> = Charm.atom(DEFAULT_STATE)

local function sanitizeFiniteNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return valueRaw
end

local function sanitizeOptionalTimestamp(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return valueRaw
end

local function sanitizeMessage(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end
	local message = string.gsub(valueRaw, "^%s*(.-)%s*$", "%1")
	if message == "" then
		return fallback
	end
	return message
end

local function sanitizeRespawnDelay(valueRaw: any, fallback: number): number
	local delay = sanitizeFiniteNumber(valueRaw, fallback)
	return math.clamp(delay, MIN_RESPAWN_DELAY, MAX_RESPAWN_DELAY)
end

local function getDeathState(): DeathState
	return deathStateAtom()
end

local function setDeathState(stateRaw: any): DeathState
	local current = deathStateAtom()
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	local visible = (source :: any).visible == true
	local message = sanitizeMessage((source :: any).message, current.message)
	local sequenceRaw = sanitizeFiniteNumber((source :: any).sequence, current.sequence)
	local sequence = math.max(0, math.floor(sequenceRaw))
	local now = os.clock()
	local diedAt = sanitizeOptionalTimestamp((source :: any).diedAt)
	local respawnDelay = sanitizeRespawnDelay((source :: any).respawnDelay, current.respawnDelay)
	local respawnAt = sanitizeOptionalTimestamp((source :: any).respawnAt)

	if visible then
		if diedAt == nil then
			diedAt = now
		end
		if respawnAt == nil then
			respawnAt = diedAt + respawnDelay
		end
	else
		diedAt = nil
		respawnAt = nil
	end

	local nextState: DeathState = {
		visible = visible,
		message = message,
		diedAt = diedAt,
		respawnAt = respawnAt,
		respawnDelay = respawnDelay,
		sequence = sequence,
		updatedAt = now,
	}
	deathStateAtom(nextState)
	return nextState
end

local function showDeath(payloadRaw: any): DeathState
	local current = deathStateAtom()
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {}
	local now = os.clock()

	local message = sanitizeMessage((payload :: any).message, DEFAULT_MESSAGE)
	local diedAt = sanitizeOptionalTimestamp((payload :: any).diedAt)
	if diedAt == nil then
		diedAt = now
	end

	local respawnDelay = sanitizeRespawnDelay((payload :: any).respawnDelay, current.respawnDelay)
	local respawnAt = sanitizeOptionalTimestamp((payload :: any).respawnAt)
	if respawnAt == nil then
		respawnAt = diedAt + respawnDelay
	end

	local nextState: DeathState = {
		visible = true,
		message = message,
		diedAt = diedAt,
		respawnAt = respawnAt,
		respawnDelay = respawnDelay,
		sequence = current.sequence + 1,
		updatedAt = now,
	}
	deathStateAtom(nextState)
	return nextState
end

local function hideDeath(): DeathState
	local current = deathStateAtom()
	if not current.visible then
		return current
	end

	local nextState: DeathState = {
		visible = false,
		message = current.message,
		diedAt = nil,
		respawnAt = nil,
		respawnDelay = current.respawnDelay,
		sequence = current.sequence,
		updatedAt = os.clock(),
	}
	deathStateAtom(nextState)
	return nextState
end

local function resetDeathState(): DeathState
	local nextState: DeathState = {
		visible = false,
		message = DEFAULT_MESSAGE,
		diedAt = nil,
		respawnAt = nil,
		respawnDelay = DEFAULT_RESPAWN_DELAY,
		sequence = 0,
		updatedAt = os.clock(),
	}
	deathStateAtom(nextState)
	return nextState
end

return {
	deathStateAtom = deathStateAtom,
	getDeathState = getDeathState,
	setDeathState = setDeathState,
	showDeath = showDeath,
	hideDeath = hideDeath,
	resetDeathState = resetDeathState,
}
