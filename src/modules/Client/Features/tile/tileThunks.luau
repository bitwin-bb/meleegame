--!strict

local tileSlice = require(script.Parent.tileSlice)

type BreakState = tileSlice.BreakState
type ShinySpeckState = tileSlice.ShinySpeckState

local tileThunks = {}

function tileThunks.PublishBreak(stateRaw: any): BreakState
	return tileSlice.setBreakState(stateRaw)
end

function tileThunks.ClearBreak(): BreakState
	return tileSlice.clearBreakState()
end

function tileThunks.GetBreakState(): BreakState
	return tileSlice.getBreakState()
end

function tileThunks.PublishShinySpeck(speckRaw: any): ShinySpeckState?
	return tileSlice.publishShinySpeck(speckRaw)
end

function tileThunks.RemoveShinySpeck(idRaw: any): boolean
	return tileSlice.removeShinySpeck(idRaw)
end

function tileThunks.ClearShinySpecksForAdornee(adorneeRaw: any): number
	return tileSlice.clearShinySpecksForAdornee(adorneeRaw)
end

tileThunks.publishBreak = tileThunks.PublishBreak
tileThunks.clearBreak = tileThunks.ClearBreak
tileThunks.getBreakState = tileThunks.GetBreakState
tileThunks.publishShinySpeck = tileThunks.PublishShinySpeck
tileThunks.removeShinySpeck = tileThunks.RemoveShinySpeck
tileThunks.clearShinySpecksForAdornee = tileThunks.ClearShinySpecksForAdornee

return tileThunks
