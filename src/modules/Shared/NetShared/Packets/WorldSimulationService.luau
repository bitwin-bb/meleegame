--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("WorldSimulationService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onChunkDelta"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onChunkUnloaded"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onDebugCounters"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["setStreamRadius"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["submitInput"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
