local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("BuildService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["canPlaceAt"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["getTileAt"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onActionResult"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onBreakProgress"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onTileFetched"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onTileDeltas"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onTreeFelled"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestBreakTile"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestPlaceTile"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
