--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

return {
	Signal = require(quentyPackages.signal.Shared.Signal),
	Connection = require(gameRoot.Shared.SharedEventBus.Core.signals.Connection),
}
