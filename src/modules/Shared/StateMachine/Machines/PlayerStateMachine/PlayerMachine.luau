
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

local PlayerBlackboard = require("PlayerBlackboard")
local PlayerTransitions = require("PlayerTransitions")
local StateMachine = require("StateMachineEngine")

local Airborne = require("Airborne")
local Grounded = require("Grounded")
local Override = require("Override")

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
