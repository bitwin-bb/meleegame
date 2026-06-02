--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

local Table = require(quentyPackages.table.Shared.Table)

return table.freeze(Table.copy({
	image = "rbxassetid://112548159625239",
	columns = 5,
	rows = 1,
	frameSize = Vector2.new(15, 15),
	frameRate = 18,
}))
