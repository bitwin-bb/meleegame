local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioLimiter", "AudioLimiter", require("Maid"))
