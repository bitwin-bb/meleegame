--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type MiningProgressState = {
	visible: boolean,
	progress: number,
	tileX: number?,
	tileY: number?,
	worldPosition: Vector3?,
	updatedAt: number,
}

local DEFAULT_STATE: MiningProgressState = {
	visible = false,
	progress = 0,
	tileX = nil,
	tileY = nil,
	worldPosition = nil,
	updatedAt = os.clock(),
}

local miningProgressStateAtom: Charm.Atom<MiningProgressState> = Charm.atom(DEFAULT_STATE)

local function sanitizeProgress(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return math.clamp(fallback, 0, 1)
	end
	return math.clamp(valueRaw, 0, 1)
end

local function sanitizeTileCoordinate(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return math.floor(valueRaw)
end

local function sanitizeWorldPosition(valueRaw: any): Vector3?
	if typeof(valueRaw) == "Vector3" then
		return valueRaw
	end
	return nil
end

local function getMiningProgressState(): MiningProgressState
	return miningProgressStateAtom()
end

local function setMiningProgressState(stateRaw: any): MiningProgressState
	local current = miningProgressStateAtom()
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	local isVisible = (source :: any).visible == true
	local nextState: MiningProgressState = {
		visible = isVisible,
		progress = sanitizeProgress((source :: any).progress, current.progress),
		tileX = sanitizeTileCoordinate((source :: any).tileX),
		tileY = sanitizeTileCoordinate((source :: any).tileY),
		worldPosition = sanitizeWorldPosition((source :: any).worldPosition),
		updatedAt = os.clock(),
	}

	if not isVisible then
		nextState.progress = 0
		nextState.tileX = nil
		nextState.tileY = nil
		nextState.worldPosition = nil
	end

	miningProgressStateAtom(nextState)
	return nextState
end

local function showMiningProgress(payloadRaw: any): MiningProgressState
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {}
	local nextState: MiningProgressState = {
		visible = true,
		progress = sanitizeProgress((payload :: any).progress, 0),
		tileX = sanitizeTileCoordinate((payload :: any).tileX),
		tileY = sanitizeTileCoordinate((payload :: any).tileY),
		worldPosition = sanitizeWorldPosition((payload :: any).worldPosition),
		updatedAt = os.clock(),
	}

	if nextState.worldPosition == nil then
		nextState.visible = false
		nextState.progress = 0
		nextState.tileX = nil
		nextState.tileY = nil
	end

	miningProgressStateAtom(nextState)
	return nextState
end

local function hideMiningProgress(): MiningProgressState
	local nextState: MiningProgressState = {
		visible = false,
		progress = 0,
		tileX = nil,
		tileY = nil,
		worldPosition = nil,
		updatedAt = os.clock(),
	}
	miningProgressStateAtom(nextState)
	return nextState
end

local function resetMiningProgressState(): MiningProgressState
	local nextState = {
		visible = false,
		progress = 0,
		tileX = nil,
		tileY = nil,
		worldPosition = nil,
		updatedAt = os.clock(),
	} :: MiningProgressState
	miningProgressStateAtom(nextState)
	return nextState
end

return {
	miningProgressStateAtom = miningProgressStateAtom,
	getMiningProgressState = getMiningProgressState,
	setMiningProgressState = setMiningProgressState,
	showMiningProgress = showMiningProgress,
	hideMiningProgress = hideMiningProgress,
	resetMiningProgressState = resetMiningProgressState,
}
