local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioEqualizer", "AudioEqualizer", require("Maid"))
