--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

export type BreakState = {
	visible: boolean,
	adornee: BasePart?,
	image: string,
	frameIndex: number,
	columns: number,
	rows: number,
	frameSize: Vector2,
	canvasSize: Vector2,
	face: Enum.NormalId,
	imagePosition: UDim2,
	imageSize: UDim2,
	transparency: number,
	tileX: number?,
	tileY: number?,
	updatedAt: number,
}

export type ShinySpeckState = {
	id: string,
	adornee: BasePart,
	image: string,
	columns: number,
	rows: number,
	frameSize: Vector2,
	frameRate: number,
	face: Enum.NormalId,
	position: UDim2,
	size: UDim2,
	updatedAt: number,
}

local DEFAULT_STATE: BreakState = {
	visible = false,
	adornee = nil,
	image = "",
	frameIndex = 1,
	columns = 1,
	rows = 1,
	frameSize = Vector2.new(1, 1),
	canvasSize = Vector2.new(1, 1),
	face = Enum.NormalId.Right,
	imagePosition = UDim2.fromScale(0.5, 0.5),
	imageSize = UDim2.fromScale(1, 1),
	transparency = 1,
	tileX = nil,
	tileY = nil,
	updatedAt = os.clock(),
}

local tileSlice = {}

local breakStateAtom: Charm.Atom<BreakState> = Charm.atom(DEFAULT_STATE)
local shinySpecksAtom: Charm.Atom<{ [string]: ShinySpeckState }> = Charm.atom({})

local function sanitizeInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function sanitizeVector2(valueRaw: any, fallback: Vector2): Vector2
	return if typeof(valueRaw) == "Vector2" then valueRaw else fallback
end

local function sanitizeUDim2(valueRaw: any, fallback: UDim2): UDim2
	return if typeof(valueRaw) == "UDim2" then valueRaw else fallback
end

local function sanitizeFace(valueRaw: any, fallback: Enum.NormalId): Enum.NormalId
	if valueRaw == Enum.NormalId.Left or valueRaw == Enum.NormalId.Right then
		return valueRaw
	end
	return fallback
end

local function sanitizeTileCoordinate(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return math.floor(valueRaw)
end

local function cloneState(state: BreakState): BreakState
	return {
		visible = state.visible,
		adornee = state.adornee,
		image = state.image,
		frameIndex = state.frameIndex,
		columns = state.columns,
		rows = state.rows,
		frameSize = state.frameSize,
		canvasSize = state.canvasSize,
		face = state.face,
		imagePosition = state.imagePosition,
		imageSize = state.imageSize,
		transparency = state.transparency,
		tileX = state.tileX,
		tileY = state.tileY,
		updatedAt = state.updatedAt,
	}
end

function tileSlice.GetBreakState(): BreakState
	return cloneState(breakStateAtom())
end

function tileSlice.SetBreakState(stateRaw: any): BreakState
	local source = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else {}
	local columns = sanitizeInteger(source.columns, DEFAULT_STATE.columns, 1, 128)
	local rows = sanitizeInteger(source.rows, DEFAULT_STATE.rows, 1, 128)
	local frameSize = sanitizeVector2(source.frameSize, DEFAULT_STATE.frameSize)
	local nextState: BreakState = {
		visible = source.visible == true,
		adornee = if typeof(source.adornee) == "Instance" and source.adornee:IsA("BasePart")
			then source.adornee
			else nil,
		image = if typeof(source.image) == "string" then source.image else "",
		frameIndex = sanitizeInteger(source.frameIndex, DEFAULT_STATE.frameIndex, 1, columns * rows),
		columns = columns,
		rows = rows,
		frameSize = frameSize,
		canvasSize = sanitizeVector2(source.canvasSize, frameSize),
		face = sanitizeFace(source.face, DEFAULT_STATE.face),
		imagePosition = sanitizeUDim2(source.imagePosition, DEFAULT_STATE.imagePosition),
		imageSize = sanitizeUDim2(source.imageSize, DEFAULT_STATE.imageSize),
		transparency = if typeof(source.transparency) == "number"
			then math.clamp(source.transparency, 0, 1)
			else DEFAULT_STATE.transparency,
		tileX = sanitizeTileCoordinate(source.tileX),
		tileY = sanitizeTileCoordinate(source.tileY),
		updatedAt = os.clock(),
	}

	if not nextState.visible then
		nextState = cloneState(DEFAULT_STATE)
		nextState.updatedAt = os.clock()
	end

	breakStateAtom(nextState)
	return cloneState(nextState)
end

function tileSlice.ClearBreakState(): BreakState
	local nextState = cloneState(DEFAULT_STATE)
	nextState.updatedAt = os.clock()
	breakStateAtom(nextState)
	return cloneState(nextState)
end

local function cloneShinySpeck(speck: ShinySpeckState): ShinySpeckState
	return {
		id = speck.id,
		adornee = speck.adornee,
		image = speck.image,
		columns = speck.columns,
		rows = speck.rows,
		frameSize = speck.frameSize,
		frameRate = speck.frameRate,
		face = speck.face,
		position = speck.position,
		size = speck.size,
		updatedAt = speck.updatedAt,
	}
end

local function cloneShinySpecks(source: { [string]: ShinySpeckState }): { [string]: ShinySpeckState }
	local output = {}
	for id, speck in source do
		output[id] = cloneShinySpeck(speck)
	end
	return output
end

function tileSlice.GetShinySpecks(): { [string]: ShinySpeckState }
	return cloneShinySpecks(shinySpecksAtom())
end

function tileSlice.PublishShinySpeck(speckRaw: any): ShinySpeckState?
	if typeof(speckRaw) ~= "table" then
		return nil
	end

	local source = speckRaw :: { [string]: any }
	if typeof(source.id) ~= "string" or source.id == "" then
		return nil
	end
	if typeof(source.adornee) ~= "Instance" or not source.adornee:IsA("BasePart") then
		return nil
	end

	local columns = sanitizeInteger(source.columns, 1, 1, 128)
	local rows = sanitizeInteger(source.rows, 1, 1, 128)
	local nextSpeck: ShinySpeckState = {
		id = source.id,
		adornee = source.adornee,
		image = if typeof(source.image) == "string" then source.image else "",
		columns = columns,
		rows = rows,
		frameSize = sanitizeVector2(source.frameSize, Vector2.new(32, 32)),
		frameRate = sanitizeInteger(source.frameRate, 18, 1, 120),
		face = sanitizeFace(source.face, DEFAULT_STATE.face),
		position = sanitizeUDim2(source.position, UDim2.fromScale(0.5, 0.5)),
		size = sanitizeUDim2(source.size, UDim2.fromOffset(32, 32)),
		updatedAt = os.clock(),
	}

	local nextSpecks = cloneShinySpecks(shinySpecksAtom())
	nextSpecks[nextSpeck.id] = nextSpeck
	shinySpecksAtom(nextSpecks)
	return cloneShinySpeck(nextSpeck)
end

function tileSlice.RemoveShinySpeck(idRaw: any): boolean
	if typeof(idRaw) ~= "string" or idRaw == "" then
		return false
	end

	local current = shinySpecksAtom()
	if current[idRaw] == nil then
		return false
	end

	local nextSpecks = cloneShinySpecks(current)
	nextSpecks[idRaw] = nil
	shinySpecksAtom(nextSpecks)
	return true
end

function tileSlice.ClearShinySpecksForAdornee(adorneeRaw: any): number
	if typeof(adorneeRaw) ~= "Instance" or not adorneeRaw:IsA("BasePart") then
		return 0
	end

	local didRemove = 0
	local nextSpecks = {}
	for id, speck in shinySpecksAtom() do
		if speck.adornee == adorneeRaw then
			didRemove += 1
		else
			nextSpecks[id] = cloneShinySpeck(speck)
		end
	end

	if didRemove > 0 then
		shinySpecksAtom(nextSpecks)
	end
	return didRemove
end

tileSlice.breakStateAtom = breakStateAtom
tileSlice.shinySpecksAtom = shinySpecksAtom
tileSlice.getBreakState = tileSlice.GetBreakState
tileSlice.setBreakState = tileSlice.SetBreakState
tileSlice.clearBreakState = tileSlice.ClearBreakState
tileSlice.getShinySpecks = tileSlice.GetShinySpecks
tileSlice.publishShinySpeck = tileSlice.PublishShinySpeck
tileSlice.removeShinySpeck = tileSlice.RemoveShinySpeck
tileSlice.clearShinySpecksForAdornee = tileSlice.ClearShinySpecksForAdornee

return tileSlice
