local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("FlangeSoundEffect", "FlangeSoundEffect", require("Maid"))
