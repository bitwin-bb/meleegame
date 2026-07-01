
local require = require(script.Parent.loader).load(script)

local padSlice = require("padSlice")

local padThunks = {}

function padThunks.Start(): () -> ()
	return function() end
end

function padThunks.Stop() end

function padThunks.GetPadState()
	return padSlice.getPadState()
end
return padThunks
