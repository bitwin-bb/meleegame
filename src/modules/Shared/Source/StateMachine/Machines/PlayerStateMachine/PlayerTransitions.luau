
local require = require(script.Parent.loader).load(script)

local Guards = require("Guards")
local Transition = require("Transition")

local PlayerTransitions = {}

local function getBlackboard(machine: any): any
	return machine:GetBlackboard()
end

local function isMoving(machine: any): boolean
	local blackboard = getBlackboard(machine)
	local moveVector = blackboard:Get("MoveVector")
	if typeof(moveVector) == "Vector3" and moveVector.Magnitude > 0.05 then
		return true
	end
	return blackboard:Get("IsMoving") == true
end

local function isGrounded(machine: any): boolean
	return Guards.IsGroundedGuard.Evaluate(machine)
end

function PlayerTransitions.Register(machine: any)
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
		To = "Stunned",
		Priority = 900,
		Guard = function(stateMachine: any): boolean
			return getBlackboard(stateMachine):Get("IsStunned") == true
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "*",
		To = "Knockback",
		Priority = 850,
		Guard = function(stateMachine: any): boolean
			return getBlackboard(stateMachine):Get("IsKnockback") == true
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Idle",
		To = "Run",
		Guard = isMoving,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Run",
		To = "Idle",
		Guard = function(stateMachine: any): boolean
			return not isMoving(stateMachine)
		end,
	}))

	for _, fromState in { "Idle", "Run" } do
		machine:RegisterTransition(Transition.new({
			From = fromState,
			To = "Jump",
			Priority = 20,
			Guard = function(stateMachine: any): boolean
				return getBlackboard(stateMachine):Get("JumpRequested") == true
			end,
		}))

		machine:RegisterTransition(Transition.new({
			From = fromState,
			To = "Dash",
			Priority = 15,
			Guard = function(stateMachine: any): boolean
				local blackboard = getBlackboard(stateMachine)
				return blackboard:Get("DashRequested") == true
					and Guards.CooldownReadyGuard.Evaluate(stateMachine, "DashCooldown", "LastDashTime")
			end,
		}))
	end

	machine:RegisterTransition(Transition.new({
		From = "Jump",
		To = "Fall",
		Guard = function(stateMachine: any): boolean
			local velocity = getBlackboard(stateMachine):Get("Velocity")
			return typeof(velocity) ~= "Vector3" or velocity.Y <= 0
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Fall",
		To = "Run",
		Guard = function(stateMachine: any): boolean
			return isGrounded(stateMachine) and isMoving(stateMachine)
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Fall",
		To = "Idle",
		Guard = function(stateMachine: any): boolean
			return isGrounded(stateMachine) and not isMoving(stateMachine)
		end,
	}))

	machine:RegisterTransition(Transition.new({
		From = "Dash",
		To = "Idle",
		Guard = function(stateMachine: any): boolean
			local duration = getBlackboard(stateMachine):Get("DashDuration")
			return stateMachine:GetStateElapsed("Dash") >= (if typeof(duration) == "number" then duration else 0.18)
		end,
	}))

	for _, overrideState in { "Stunned", "Knockback" } do
		machine:RegisterTransition(Transition.new({
			From = overrideState,
			To = "Idle",
			Guard = function(stateMachine: any): boolean
				return not getBlackboard(stateMachine):Get(
					if overrideState == "Stunned" then "IsStunned" else "IsKnockback"
				)
			end,
		}))
	end
end
return PlayerTransitions
