local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm: any = require(ReplicatedStorage.Packages.Charm)

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

local function CoerceFiniteNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return valueRaw
end

local function CoerceOptionalTimestamp(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return valueRaw
end

local function CoerceMessage(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end
	local message = string.gsub(valueRaw, "^%s*(.-)%s*$", "%1")
	if message == "" then
		return fallback
	end
	return message
end

local function CoerceRespawnDelay(valueRaw: any, fallback: number): number
	local delay = CoerceFiniteNumber(valueRaw, fallback)
	return math.clamp(delay, MIN_RESPAWN_DELAY, MAX_RESPAWN_DELAY)
end

local function getDeathState(): DeathState
	return deathStateAtom()
end

local function setDeathState(stateRaw: any): DeathState
	local current = deathStateAtom()
	local source = if typeof(stateRaw) == "table" then stateRaw else {} :: any
	local visible = (source :: any).visible == true
	local message = CoerceMessage((source :: any).message, current.message)
	local sequenceRaw = CoerceFiniteNumber((source :: any).sequence, current.sequence)
	local sequence = math.max(0, math.floor(sequenceRaw))
	local now = os.clock()
	local diedAt = CoerceOptionalTimestamp((source :: any).diedAt)
	local respawnDelay = CoerceRespawnDelay((source :: any).respawnDelay, current.respawnDelay)
	local respawnAt = CoerceOptionalTimestamp((source :: any).respawnAt)

	if visible then
		local deathTime: number = diedAt or now
		diedAt = deathTime
		if respawnAt == nil then
			respawnAt = deathTime + respawnDelay
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
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {} :: any
	local now = os.clock()

	local message = CoerceMessage((payload :: any).message, DEFAULT_MESSAGE)
	local diedAt = CoerceOptionalTimestamp((payload :: any).diedAt)
	if diedAt == nil then
		diedAt = now
	end
	local deathTime = diedAt :: number

	local respawnDelay = CoerceRespawnDelay((payload :: any).respawnDelay, current.respawnDelay)
	local respawnAt = CoerceOptionalTimestamp((payload :: any).respawnAt)
	if respawnAt == nil then
		respawnAt = deathTime + respawnDelay
	end
	diedAt = deathTime

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
