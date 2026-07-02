local require = require(script.Parent.loader).load(script)
local Nevermore = require("StateMachineNevermore")
local Table = Nevermore.Get("Table")

local Blackboard = require("StateMachineBlackboard")
local Guards = require("Guards")
local StateMachine = require("StateMachineEngine")
local Transition = require("Transition")

local ChaseState = require("ChaseState")
local DeadState = require("SlimeDeadState")
local HurtState = require("HurtState")
local IdleState = require("SlimeIdleState")
local WanderState = require("WanderState")

local SlimeMachine = {}

local function createBlackboard(config: { [string]: any }): any
	local blackboard = Blackboard.new()
	blackboard:Set("Model", config.Model or config.model)
	blackboard:Set("Root", config.Root or config.root)
	blackboard:Set("Health", if typeof(config.Health) == "number" then config.Health else 100)
	blackboard:Set("MaxHealth", if typeof(config.MaxHealth) == "number" then config.MaxHealth else 100)
	blackboard:Set("Target", config.Target or config.target)
	blackboard:Set("AggroRange", if typeof(config.AggroRange) == "number" then config.AggroRange else 60)
	blackboard:Set("AttackRange", if typeof(config.AttackRange) == "number" then config.AttackRange else 8)
	blackboard:Set("MoveSpeed", if typeof(config.MoveSpeed) == "number" then config.MoveSpeed else 12)
	blackboard:Set("IdleDuration", if typeof(config.IdleDuration) == "number" then config.IdleDuration else 1.2)
	blackboard:Set("WanderDuration", if typeof(config.WanderDuration) == "number" then config.WanderDuration else 1.8)
	blackboard:Set("HurtDuration", if typeof(config.HurtDuration) == "number" then config.HurtDuration else 0.35)
	blackboard:Set("LastAttackTime", if typeof(config.LastAttackTime) == "number" then config.LastAttackTime else 0)
	blackboard:Set("TookDamage", false)
	return blackboard
end

function SlimeMachine.new(configRaw: any?): any
	local config: any = if typeof(configRaw) == "table" then Table.copy(configRaw :: any) else {}
	local machine = StateMachine.New({
		Blackboard = createBlackboard(config),
		Context = config.Context or config.context,
	})

	machine:RegisterState("Idle", IdleState.new())
	machine:RegisterState("Wander", WanderState.new())
	machine:RegisterState("Chase", ChaseState.new())
	machine:RegisterState("Hurt", HurtState.new())
	machine:RegisterState("Dead", DeadState.new())

	machine:RegisterTransition(Transition.new({
		From = "*",
		To = "Dead",
		Priority = 1000,
		Guard = function(stateMachine: any): boolean
			return Guards.HealthBelowGuard.Evaluate(stateMachine, 0, "Health")
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "*",
		To = "Hurt",
		Priority = 100,
		Guard = function(stateMachine: any): boolean
			return stateMachine:GetBlackboard():Get("TookDamage") == true
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Idle",
		To = "Chase",
		Priority = 10,
		Guard = Guards.HasTargetGuard.new("Target"),
	}))

	machine:RegisterTransition(Transition.new({
		From = "Idle",
		To = "Wander",
		Guard = function(stateMachine: any): boolean
			local duration = stateMachine:GetBlackboard():Get("IdleDuration")
			return stateMachine:GetStateElapsed("Idle") >= (if typeof(duration) == "number" then duration else 1.2)
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Wander",
		To = "Chase",
		Priority = 10,
		Guard = Guards.HasTargetGuard.new("Target"),
	}))

	machine:RegisterTransition(Transition.new({
		From = "Wander",
		To = "Idle",
		Guard = function(stateMachine: any): boolean
			local duration = stateMachine:GetBlackboard():Get("WanderDuration")
			return stateMachine:GetStateElapsed("Wander") >= (if typeof(duration) == "number" then duration else 1.8)
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Hurt",
		To = "Chase",
		Priority = 5,
		Guard = function(stateMachine: any): boolean
			local duration = stateMachine:GetBlackboard():Get("HurtDuration")
			return stateMachine:GetStateElapsed("Hurt") >= (if typeof(duration) == "number" then duration else 0.35)
				and Guards.HasTargetGuard.Evaluate(stateMachine, "Target")
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Hurt",
		To = "Idle",
		Guard = function(stateMachine: any): boolean
			local duration = stateMachine:GetBlackboard():Get("HurtDuration")
			return stateMachine:GetStateElapsed("Hurt") >= (if typeof(duration) == "number" then duration else 0.35)
		end,
	}))

	if config.AutoStart ~= false then
		machine:Start(if typeof(config.InitialState) == "string" then config.InitialState else "Idle")
	end

	return machine
end

SlimeMachine.New = SlimeMachine.new

return SlimeMachine
