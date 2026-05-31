--!strict

local Nevermore = require(script:FindFirstAncestor("StateMachine").Nevermore)
local Table = Nevermore.Get("Table")

local root = script:FindFirstAncestor("StateMachine")
local PlayerBlackboard = require(script.Parent.PlayerBlackboard)
local PlayerTransitions = require(script.Parent.PlayerTransitions)
local StateMachine = require(root.Core.StateMachine)

local Airborne = require(script.Parent.Airborne)
local Grounded = require(script.Parent.Grounded)
local Override = require(script.Parent.Override)

local PlayerMachine = {}

function PlayerMachine.new(configRaw: any?): any
	local config: any = if typeof(configRaw) == "table" then Table.copy(configRaw :: any) else {}
	local machine = StateMachine.new({
		Blackboard = PlayerBlackboard.Create(config),
		Context = config.Context or config.context,
	})

	machine:RegisterState("Idle", Grounded.IdleState.new())
	machine:RegisterState("Run", Grounded.RunState.new())
	machine:RegisterState("Dash", Grounded.DashState.new())
	machine:RegisterState("Jump", Airborne.JumpState.new())
	machine:RegisterState("Fall", Airborne.FallState.new())
	machine:RegisterState("Stunned", Override.StunnedState.new())
	machine:RegisterState("Knockback", Override.KnockbackState.new())
	machine:RegisterState("Dead", Override.DeadState.new())
	PlayerTransitions.Register(machine)

	if config.AutoStart ~= false then
		machine:Start(if typeof(config.InitialState) == "string" then config.InitialState else "Idle")
	end

	return machine
end

PlayerMachine.New = PlayerMachine.new

return PlayerMachine
