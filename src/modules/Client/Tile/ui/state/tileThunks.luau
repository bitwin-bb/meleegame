
local require = require(script.Parent.loader).load(script)

local tileSlice = require("tileSlice")

type BreakState = tileSlice.BreakState
type ShinySpeckState = tileSlice.ShinySpeckState

local tileThunks = {}

function tileThunks.PublishBreak(stateRaw: any): BreakState
	return tileSlice.SetBreakState(stateRaw)
end

function tileThunks.ClearBreak(): BreakState
	return tileSlice.ClearBreakState()
end

function tileThunks.GetBreakState(): BreakState
	return tileSlice.GetBreakState()
end

function tileThunks.PublishShinySpeck(speckRaw: any): ShinySpeckState?
	return tileSlice.PublishShinySpeck(speckRaw)
end

function tileThunks.RemoveShinySpeck(idRaw: any): boolean
	return tileSlice.RemoveShinySpeck(idRaw)
end

function tileThunks.ClearShinySpecksForAdornee(adorneeRaw: any): number
	return tileSlice.ClearShinySpecksForAdornee(adorneeRaw)
end
return tileThunks
