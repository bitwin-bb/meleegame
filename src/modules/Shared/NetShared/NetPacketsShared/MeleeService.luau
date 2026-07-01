local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("MeleeService", function()
	return {
		["requestRefreshEquipped"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
		["requestSetInputHeld"] = ByteNet.definePacket({
			value = ByteNet.unknown,
		}),
	}
end)
