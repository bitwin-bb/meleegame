local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("ChorusSoundEffect", "ChorusSoundEffect", require("Maid"))
