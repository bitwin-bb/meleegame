local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local EightWayBlobRule = require("EightWayBlobRule")

local FourWay16Rule = Table.merge(EightWayBlobRule, {
	Mode = "FourWay16",
	IncludeDiagonals = false,
})

return Table.readonly(FourWay16Rule)
