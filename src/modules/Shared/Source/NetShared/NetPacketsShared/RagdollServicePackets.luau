local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("RagdollService", function()
	return {
		["applyState"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSelfRagdoll"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSelfRecover"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSync"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
