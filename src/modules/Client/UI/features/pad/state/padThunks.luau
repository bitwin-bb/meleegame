--!strict
local padSlice = require(script:FindFirstAncestor("game").Client.UI.features.pad.state.padSlice)

local padThunks = {}

function padThunks.Start(): () -> ()
	return function() end
end

function padThunks.Stop() end

function padThunks.GetPadState()
	return padSlice.getPadState()
end

padThunks.start = padThunks.Start
padThunks.stop = padThunks.Stop
padThunks.getPadState = padThunks.GetPadState

return padThunks
