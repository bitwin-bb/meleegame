--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("LootService", function()
	return {
		["requestDropFromSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestDropSelectedSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
