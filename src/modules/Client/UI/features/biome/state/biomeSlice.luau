--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type BiomeState = {
	visible: boolean,
	biomeKey: string?,
	biomeName: string,
	enteredAt: number?,
	updatedAt: number,
}

export type ShowBiomePayload = {
	biomeKey: string?,
	biomeName: string?,
}

local DEFAULT_STATE: BiomeState = {
	visible = false,
	biomeKey = nil,
	biomeName = "",
	enteredAt = nil,
	updatedAt = os.clock(),
}

local biomeStateAtom: Charm.Atom<BiomeState> = Charm.atom(DEFAULT_STATE)

local function sanitizeBiomeKey(valueRaw: any): string?
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return nil
end

local function sanitizeBiomeName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function getBiomeState(): BiomeState
	return biomeStateAtom()
end

local function setBiomeState(stateRaw: any): BiomeState
	local current = biomeStateAtom()
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	local visible = (source :: any).visible == true
	local biomeKey = sanitizeBiomeKey((source :: any).biomeKey)
	local biomeName = sanitizeBiomeName((source :: any).biomeName, current.biomeName)
	local enteredAtRaw = (source :: any).enteredAt
	local enteredAt = if typeof(enteredAtRaw) == "number" and enteredAtRaw == enteredAtRaw
		then enteredAtRaw
		else current.enteredAt

	local nextState: BiomeState = {
		visible = visible,
		biomeKey = biomeKey,
		biomeName = biomeName,
		enteredAt = enteredAt,
		updatedAt = os.clock(),
	}

	if not visible then
		nextState.enteredAt = nil
	end
	if nextState.biomeName == "" then
		nextState.visible = false
		nextState.enteredAt = nil
	end
	if nextState.biomeKey == nil then
		nextState.visible = false
		nextState.enteredAt = nil
	end

	biomeStateAtom(nextState)
	return nextState
end

local function showBiomeName(payloadRaw: any): BiomeState
	local current = biomeStateAtom()
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {}
	local biomeKey = sanitizeBiomeKey((payload :: any).biomeKey)
	local biomeName = sanitizeBiomeName((payload :: any).biomeName, current.biomeName)

	local nextState: BiomeState = {
		visible = biomeKey ~= nil and biomeName ~= "",
		biomeKey = biomeKey,
		biomeName = biomeName,
		enteredAt = os.clock(),
		updatedAt = os.clock(),
	}

	if not nextState.visible then
		nextState.enteredAt = nil
	end

	biomeStateAtom(nextState)
	return nextState
end

local function hideBiomeName(): BiomeState
	local current = biomeStateAtom()
	if not current.visible then
		return current
	end

	local nextState: BiomeState = {
		visible = false,
		biomeKey = current.biomeKey,
		biomeName = current.biomeName,
		enteredAt = nil,
		updatedAt = os.clock(),
	}
	biomeStateAtom(nextState)
	return nextState
end

local function resetBiomeState(): BiomeState
	local nextState: BiomeState = {
		visible = false,
		biomeKey = nil,
		biomeName = "",
		enteredAt = nil,
		updatedAt = os.clock(),
	}
	biomeStateAtom(nextState)
	return nextState
end

return {
	biomeStateAtom = biomeStateAtom,
	getBiomeState = getBiomeState,
	setBiomeState = setBiomeState,
	showBiomeName = showBiomeName,
	hideBiomeName = hideBiomeName,
	resetBiomeState = resetBiomeState,
}
