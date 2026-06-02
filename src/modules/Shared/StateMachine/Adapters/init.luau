--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

return Table.copy({
	AnimationAdapter = require(gameRoot.Shared.StateMachine.Adapters.AnimationAdapter),
	CharacterAdapter = require(gameRoot.Shared.StateMachine.Adapters.CharacterAdapter),
	MovementAdapter = require(gameRoot.Shared.StateMachine.Adapters.MovementAdapter),
	HumanoidAdapter = require(gameRoot.Shared.StateMachine.Adapters.HumanoidAdapter),
})
