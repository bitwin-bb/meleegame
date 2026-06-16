local require = require(script.Parent.loader).load(script)

local testEnvironment = getfenv() :: any
local describe = testEnvironment.describe :: any
local it = testEnvironment.it :: any
local expect = testEnvironment.expect :: any

local Goap = require("Goap")

return function()
	describe("Goap core", function()
		it("clones, satisfies, and applies world state facts", function()
			local worldState = Goap.Core.WorldState.new({
				HasTarget = true,
				TargetInRange = false,
			})

			local clone = worldState:Clone()
			clone:Apply({
				TargetInRange = true,
				CanAttack = true,
			})

			expect(worldState:Get("TargetInRange")).to.equal(false)
			expect(clone:Satisfies({
				HasTarget = true,
				TargetInRange = true,
				CanAttack = true,
			})).to.equal(true)
			expect(worldState:Matches(clone)).to.equal(false)

			worldState:Destroy()
			clone:Destroy()
		end)

		it("builds the lowest cost ordered action plan", function()
			local planner = Goap.Core.Planner.new()
			local worldState = Goap.Core.WorldState.new({
				HasTarget = true,
				TargetInRange = false,
				CanAttack = true,
			})
			local goal = Goap.Core.Goal.new({
				Name = "KillTarget",
				DesiredState = {
					TargetDead = true,
				},
			})
			local moveAction = Goap.Core.Action.new({
				Name = "MoveToTarget",
				Cost = 2,
				Preconditions = {
					HasTarget = true,
				},
				Effects = {
					TargetInRange = true,
				},
			})
			local attackAction = Goap.Core.Action.new({
				Name = "AttackTarget",
				Cost = 1,
				Preconditions = {
					HasTarget = true,
					TargetInRange = true,
					CanAttack = true,
				},
				Effects = {
					TargetDead = true,
				},
			})
			local expensiveAction = Goap.Core.Action.new({
				Name = "ThrowBomb",
				Cost = 10,
				Preconditions = {
					HasTarget = true,
				},
				Effects = {
					TargetDead = true,
				},
			})

			local plan = planner:BuildPlan(nil, worldState, goal, {
				expensiveAction,
				attackAction,
				moveAction,
			})

			expect(plan ~= nil).to.equal(true)
			expect((plan :: any):GetCost()).to.equal(3)
			expect((plan :: any):GetActions()[1].Name).to.equal("MoveToTarget")
			expect((plan :: any):GetActions()[2].Name).to.equal("AttackTarget")

			planner:Destroy()
			worldState:Destroy()
			goal:Destroy()
			moveAction:Destroy()
			attackAction:Destroy()
			expensiveAction:Destroy();
			(plan :: any):Destroy()
		end)

		it("executes a plan by starting, updating, and advancing actions", function()
			local agent = Goap.Core.Agent.new()
			local executor = Goap.Executors.PlanExecutor.new()
			local started = 0
			local updated = 0
			local finished = false
			local action = Goap.Core.Action.new({
				Name = "CountAction",
				Effects = {
					Counted = true,
				},
				Start = function()
					started += 1
				end,
				Update = function()
					updated += 1
					finished = true
				end,
				IsFinished = function()
					return finished
				end,
			})
			local plan = Goap.Core.Plan.new({
				action,
			})

			expect(executor:Update(agent, plan, 0.1)).to.equal(true)
			expect(plan:IsComplete()).to.equal(true)
			expect(started).to.equal(1)
			expect(updated).to.equal(1)

			agent:Destroy()
			executor:Destroy()
			action:Destroy()
			plan:Destroy()
		end)

		it("updates sensors, selects a goal, plans, and executes through an agent", function()
			local agent = Goap.Core.Agent.new()
			local target = {
				Name = "Target",
			}

			agent:GetBlackboard():Set("Target", target)
			agent:SetWorldState("CanAttack", true)
			agent:SetWorldState("TargetInRange", true)
			agent:AddSensor(Goap.Sensors.TargetSensor.new())
			agent:AddGoal(Goap.Goals.KillTargetGoal.new())
			agent:AddAction(Goap.Actions.AttackTargetAction.new())

			agent:Update(0.1)

			expect(agent:GetCurrentGoal().Name).to.equal("KillTarget")
			expect(agent:GetWorldState("TargetDead")).to.equal(true)

			agent:Destroy()
		end)
	end)
end
