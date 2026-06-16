local require = require(script.Parent.loader).load(script)

local FusionUtils = require("fusionUtils")

return FusionUtils.CreateInstanceWrapper("AudioChannelSplitter", "AudioChannelSplitter", require("Maid"))
