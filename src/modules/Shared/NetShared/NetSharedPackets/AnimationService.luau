local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("AnimationService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["setFootstepsEnabled"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["setProfile"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
