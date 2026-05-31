--!strict

local Nevermore = require(script:FindFirstAncestor("Goap").Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Agent = require(script:FindFirstAncestor("Goap").Core.Agent),
	NPCAgent = require(script.NPCAgent),
})
