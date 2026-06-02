--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing game root")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")


return require(quentyPackages.signal.Shared.Signal)
