local require = require(script.Parent.loader).load(script)

local FusionUtils = require("FusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioChannelSplitter", "AudioChannelSplitter", require("Maid"))
