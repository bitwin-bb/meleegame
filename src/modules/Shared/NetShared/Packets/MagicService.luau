--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("MagicService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onCastVisual"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onImpactVisual"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestCast"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestRefreshEquipped"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSetInputHeld"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
