local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet: any = require(ReplicatedStorage.Packages.ByteNet)

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
