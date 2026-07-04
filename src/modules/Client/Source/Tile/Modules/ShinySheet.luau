local require = require(script.Parent.loader).load(script)

local Table: any = require("Table")

return table.freeze(Table.copy({
	image = "rbxassetid://112548159625239",
	columns = 5,
	rows = 1,
	frameSize = Vector2.new(15, 15),
	frameRate = 18,
}))
