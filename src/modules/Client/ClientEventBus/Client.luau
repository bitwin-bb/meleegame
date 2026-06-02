--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

return require(gameRoot.Client.ClientEventBus.Core.ClientBus)
