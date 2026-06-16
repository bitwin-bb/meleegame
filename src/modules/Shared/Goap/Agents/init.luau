
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Table = Nevermore.GetRolePackages("Exports").Table

return Table.copy({
	Agent = require("Agent"),
	NPCAgent = require(script:WaitForChild("NPCAgent")),
})
