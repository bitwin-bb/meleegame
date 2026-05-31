--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("LiquidService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onChunkDelta"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onChunkSnapshot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onChunkUnloaded"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onEffectEvent"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
