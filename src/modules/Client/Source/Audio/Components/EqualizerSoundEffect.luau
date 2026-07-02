local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("EqualizerSoundEffect", "EqualizerSoundEffect", require("Maid"))
