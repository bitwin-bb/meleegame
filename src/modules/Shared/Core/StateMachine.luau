--!strict

local stateMachineRoot = script:FindFirstAncestor("game").Shared.StateMachine

require(stateMachineRoot.Nevermore).Get("Table")

return require(stateMachineRoot.Core.StateMachine)
