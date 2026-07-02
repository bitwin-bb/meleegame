local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("NpcService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onNpcAdded"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onNpcRemoved"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onNpcStateChanged"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
