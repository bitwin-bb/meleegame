local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioGate", "AudioGate", require("Maid"))
