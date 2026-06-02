--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

return {
	Client = require(gameRoot.Shared.SharedEventBus.Client),
	Server = require(gameRoot.Shared.SharedEventBus.Server),
	Utils = require(gameRoot.Shared.SharedEventBus.Utils),
	Core = require(gameRoot.Shared.SharedEventBus.Core),
}
