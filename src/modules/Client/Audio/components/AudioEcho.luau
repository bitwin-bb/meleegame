local require = require(script.Parent.loader).load(script)

local FusionUtils = require("fusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioEcho", "AudioEcho", require("Maid"))
