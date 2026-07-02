local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("VFXService", function()
	return {
		["play"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["stopAll"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["stopChannel"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
