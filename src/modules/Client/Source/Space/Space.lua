local require = require(script.Parent.loader).load(script)

local SpaceClient = require("SpaceClient")
local SpaceShared = require("SpaceShared")
local Table: any = require("Table")

return Table.merge(SpaceShared, {
	Client = SpaceClient,
})
