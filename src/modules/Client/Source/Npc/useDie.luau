local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcServiceUtils = require("NpcServiceUtils")
local NpcThunks = require("NpcThunks")
local React: any = require(ReplicatedStorage.Packages.React)

type NpcSnapshot = NpcServiceUtils.NpcSnapshot

local function cloneAliveById(snapshotsById: { [string]: NpcSnapshot }): { [string]: boolean }
	local output = {}
	for runtimeId, snapshot in snapshotsById do
		output[runtimeId] = snapshot.isAlive
	end
	return output
end

return function(snapshotsById: { [string]: NpcSnapshot })
	local previousAliveRef = React.useRef({} :: { [string]: boolean })

	React.useEffect(function()
		local previousAliveById = previousAliveRef.current
		for runtimeId, snapshot in snapshotsById do
			if snapshot.npcType ~= "Slime" then
				continue
			end

			if previousAliveById[runtimeId] == true and snapshot.isAlive == false then
				NpcThunks.SpawnSlimeDeathGore(snapshot)
			end
		end

		previousAliveRef.current = cloneAliveById(snapshotsById)
	end, { snapshotsById })
end
