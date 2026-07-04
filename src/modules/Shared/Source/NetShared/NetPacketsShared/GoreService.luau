local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet: any = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("GoreService", function()
	return {
		["destroyLimb"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["emitBlood"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["registerEntity"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["removeEntity"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["setBloodColor"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["spawnGibs"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
