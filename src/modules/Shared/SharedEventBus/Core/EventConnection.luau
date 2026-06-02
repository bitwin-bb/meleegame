--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

return require(gameRoot.Shared.SharedEventBus.Core.signals.Connection)
