local require = require(script.Parent.loader).load(script)

local FusionUtils = require("fusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioSpeechToText", "AudioSpeechToText", require("Maid"))
