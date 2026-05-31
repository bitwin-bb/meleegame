--!strict

local Nevermore = require(script:FindFirstAncestor("StateMachine").Nevermore)
local Table = Nevermore.Get("Table")

local root = script:FindFirstAncestor("StateMachine")
local Blackboard = require(root.Core.Blackboard)
local StateMachine = require(root.Core.StateMachine)
local Transition = require(root.Core.Transition)

local ActiveState = require(script.Parent.ActiveState)
local IdleState = require(script.Parent.IdleState)
local RecoveryState = require(script.Parent.RecoveryState)
local StartupState = require(script.Parent.StartupState)

local CombatMachine = {}

local function createBlackboard(config: { [string]: any }): any
	local blackboard = Blackboard.new()
	blackboard:Set("AttackRequested", config.AttackRequested == true)
	blackboard:Set("QueuedAttack", config.QueuedAttack)
	blackboard:Set(
		"StartupDuration",
		if typeof(config.StartupDuration) == "number" then config.StartupDuration else 0.12
	)
	blackboard:Set("ActiveDuration", if typeof(config.ActiveDuration) == "number" then config.ActiveDuration else 0.16)
	blackboard:Set(
		"RecoveryDuration",
		if typeof(config.RecoveryDuration) == "number" then config.RecoveryDuration else 0.24
	)
	blackboard:Set("Hitbox", config.Hitbox or config.hitbox)
	blackboard:Set("HitboxConfig", config.HitboxConfig or config.hitboxConfig)
	return blackboard
end

function CombatMachine.new(configRaw: any?): any
	local config: any = if typeof(configRaw) == "table" then Table.copy(configRaw :: any) else {}
	local machine = StateMachine.new({
		Blackboard = createBlackboard(config),
		Context = config.Context or config.context,
	})

	machine:RegisterState("Idle", IdleState.new())
	machine:RegisterState("Startup", StartupState.new())
	machine:RegisterState("Active", ActiveState.new())
	machine:RegisterState("Recovery", RecoveryState.new())

	machine:RegisterTransition(Transition.new({
		From = "Idle",
		To = "Startup",
		Guard = function(stateMachine: any): boolean
			local blackboard = stateMachine:GetBlackboard()
			return blackboard:Get("AttackRequested") == true or blackboard:Get("QueuedAttack") ~= nil
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Startup",
		To = "Active",
		Guard = function(stateMachine: any): boolean
			local duration = stateMachine:GetBlackboard():Get("StartupDuration")
			return stateMachine:GetStateElapsed("Startup") >= (if typeof(duration) == "number" then duration else 0.12)
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Active",
		To = "Recovery",
		Guard = function(stateMachine: any): boolean
			local duration = stateMachine:GetBlackboard():Get("ActiveDuration")
			return stateMachine:GetStateElapsed("Active") >= (if typeof(duration) == "number" then duration else 0.16)
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Recovery",
		To = "Idle",
		Guard = function(stateMachine: any): boolean
			local duration = stateMachine:GetBlackboard():Get("RecoveryDuration")
			return stateMachine:GetStateElapsed("Recovery") >= (if typeof(duration) == "number" then duration else 0.24)
		end,
	}))

	if config.AutoStart ~= false then
		machine:Start(if typeof(config.InitialState) == "string" then config.InitialState else "Idle")
	end

	return machine
end

CombatMachine.New = CombatMachine.new

return CombatMachine
