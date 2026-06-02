--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

return {
	EventBus = require(gameRoot.Shared.SharedEventBus.Core.EventBus),
	EventName = require(gameRoot.Shared.SharedEventBus.Core.EventName),
	EventConnection = require(gameRoot.Shared.SharedEventBus.Core.EventConnection),
	Types = require(gameRoot.Shared.SharedEventBus.Core.Types),
	signals = require(gameRoot.Shared.SharedEventBus.Core.signals),
}
