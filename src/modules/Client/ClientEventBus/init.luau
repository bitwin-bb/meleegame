--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

return {
	Client = require(gameRoot.Client.ClientEventBus.Client),
	Utils = require(gameRoot.Client.ClientEventBus.Utils),
	Core = require(gameRoot.Client.ClientEventBus.Core),
}
