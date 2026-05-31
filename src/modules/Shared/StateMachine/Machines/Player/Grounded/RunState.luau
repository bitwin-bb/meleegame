--!strict

local State = require(script:FindFirstAncestor("StateMachine").Core.State)

local RunState = {}

function RunState.new(): any
	return State.new({
		Name = "Run",
		Enter = function(_self: any, machine: any)
			machine:GetBlackboard():Set("MovementState", "Run")
		end,
		Update = function(_self: any, machine: any, _dt: number)
			local blackboard = machine:GetBlackboard()
			local movement = blackboard:Get("Movement")
			local moveVector = blackboard:Get("MoveVector")
			local speed = blackboard:Get("MoveSpeed")
			if
				typeof(movement) == "table"
				and typeof(movement.SetVelocity) == "function"
				and typeof(moveVector) == "Vector3"
			then
				movement:SetVelocity(moveVector * (if typeof(speed) == "number" then speed else 16))
			end
		end,
	})
end

return RunState
