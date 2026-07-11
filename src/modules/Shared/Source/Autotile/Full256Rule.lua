local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local EightWayBlobRule = require("EightWayBlobRule")

local Full256Rule = Table.merge(EightWayBlobRule, {
	Mode = "Full256",
	IncludeDiagonals = true,
})

return Table.readonly(Full256Rule)
