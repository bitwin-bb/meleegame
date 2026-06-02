--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

return {
	ClientBus = require(gameRoot.Client.ClientEventBus.Core.ClientBus),
	ClientEvents = require(gameRoot.Client.ClientEventBus.Core.ClientEvents),
	ClientEventRegistry = require(gameRoot.Client.ClientEventBus.Core.ClientEventRegistry),
	signals = require(gameRoot.Client.ClientEventBus.Core.signals),
}
