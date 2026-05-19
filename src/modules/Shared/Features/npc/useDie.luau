--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcServiceUtils = require(script.Parent.NpcServiceUtils)
local NpcThunks = require(script.Parent.NpcThunks)
local React = require(ReplicatedStorage.Packages.React)

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
				NpcThunks.spawnSlimeDeathGore(snapshot)
			end
		end

		previousAliveRef.current = cloneAliveById(snapshotsById)
	end, { snapshotsById })
end
