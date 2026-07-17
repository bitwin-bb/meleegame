local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet: any = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("CropService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onActionResult"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onChunkSnapshot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onChunkUnloaded"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onCropDeltas"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestHarvest"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestPlant"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
