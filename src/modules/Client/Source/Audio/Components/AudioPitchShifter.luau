local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioPitchShifter", "AudioPitchShifter", require("Maid"))
