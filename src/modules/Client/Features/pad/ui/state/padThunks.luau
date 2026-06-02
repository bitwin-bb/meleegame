--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local padSlice = require(gameRoot.Client.Features.pad.ui.state.padSlice)

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
