--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

return {
	ClientSignal = require(gameRoot.Client.ClientEventBus.Core.signals.ClientSignal),
}
