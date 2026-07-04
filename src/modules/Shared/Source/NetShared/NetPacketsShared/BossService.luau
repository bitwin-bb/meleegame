local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet: any = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("BossService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onAnnouncement"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onBossAdded"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onBossRemoved"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["onBossUpdated"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestManualSummon"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
