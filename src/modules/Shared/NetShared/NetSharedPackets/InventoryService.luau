local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("InventoryService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestDropFromSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestMoveSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestPlaceSelectedDeployable"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSetSelectedSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSplitSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestTrashSelectedSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestTrashSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestUseSelectedSlot"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
