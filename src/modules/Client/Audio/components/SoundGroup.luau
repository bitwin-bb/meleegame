local require = require(script.Parent.loader).load(script)

local FusionUtils = require("fusionUtils")

return FusionUtils.CreateInstanceWrapper("SoundGroup", "SoundGroup", require("Maid"))
