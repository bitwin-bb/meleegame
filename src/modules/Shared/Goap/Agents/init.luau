--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.Goap.Nevermore)
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Agent = require(gameRoot.Shared.Goap.Core.Agent),
	NPCAgent = require(gameRoot.Shared.Goap.Agents.NPCAgent),
})
