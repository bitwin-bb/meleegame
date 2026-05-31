--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("PlayerService", function()
	return {
		["applyFacing"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["applyMovementLock"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onDamaged"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["setFacing"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["setWorldReadyForMovement"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
