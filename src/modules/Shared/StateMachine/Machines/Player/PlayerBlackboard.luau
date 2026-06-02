--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Nevermore = require(gameRoot.Shared.StateMachine.Nevermore)
local Table = Nevermore.Get("Table")

local Blackboard = require(gameRoot.Shared.StateMachine.Core.Blackboard)

local PlayerBlackboard = {}

function PlayerBlackboard.Create(configRaw: any?): any
	local config: any = if typeof(configRaw) == "table" then Table.copy(configRaw :: any) else {}
	local blackboard = Blackboard.new()

	blackboard:Set("Character", config.Character or config.character)
	blackboard:Set("Humanoid", config.Humanoid or config.humanoid)
	blackboard:Set("Root", config.Root or config.root)
	blackboard:Set("Input", config.Input or config.input)
	blackboard:Set("Movement", config.Movement or config.movement)
	blackboard:Set("Animation", config.Animation or config.animation)
	blackboard:Set("Effects", config.Effects or config.effects)
	blackboard:Set("Camera", config.Camera or config.camera)
	blackboard:Set("Health", if typeof(config.Health) == "number" then config.Health else 100)
	blackboard:Set("MoveSpeed", if typeof(config.MoveSpeed) == "number" then config.MoveSpeed else 16)
	blackboard:Set("DashCooldown", if typeof(config.DashCooldown) == "number" then config.DashCooldown else 0.6)
	blackboard:Set("DashDuration", if typeof(config.DashDuration) == "number" then config.DashDuration else 0.18)
	blackboard:Set("StunDuration", if typeof(config.StunDuration) == "number" then config.StunDuration else 0.5)
	blackboard:Set(
		"KnockbackDuration",
		if typeof(config.KnockbackDuration) == "number" then config.KnockbackDuration else 0.25
	)
	blackboard:Set("IsGrounded", config.IsGrounded == true)
	blackboard:Set("FacingDirection", if typeof(config.FacingDirection) == "number" then config.FacingDirection else 1)
	blackboard:Set("MoveVector", if typeof(config.MoveVector) == "Vector3" then config.MoveVector else Vector3.zero)
	blackboard:Set("JumpRequested", false)
	blackboard:Set("DashRequested", false)
	blackboard:Set("IsStunned", false)
	blackboard:Set("IsKnockback", false)
	blackboard:Set("LastDashTime", -math.huge)

	return blackboard
end

PlayerBlackboard.create = PlayerBlackboard.Create

return PlayerBlackboard
