local require = require(script.Parent.loader).load(script)

local StateMachinePackage = require("StateMachine")

local Nevermore = StateMachinePackage.Nevermore
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local CombatController = {}
CombatController.__index = CombatController

export type CombatController = typeof(setmetatable(
	{} :: {
		maid: any,
		Started: any,
		machine: any?,
	},
	CombatController
))

function CombatController.new(configRaw: any?): CombatController
	local self = setmetatable({
		maid = Maid.new(),
		Started = Signal.new(),
		machine = StateMachinePackage.Machines.Combat.CombatMachine.new(configRaw),
	}, CombatController)

	self.maid:GiveTask(self.Started)
	self.maid:GiveTask(self.machine)
	return self
end

function CombatController.Start(self: CombatController): boolean
	self.Started:Fire()
	return true
end

function CombatController.Update(self: CombatController, dt: number)
	if self.machine ~= nil and typeof(self.machine.Update) == "function" then
		self.machine:Update(dt)
	end
end

function CombatController.Destroy(self: CombatController)
	self.maid:DoCleaning()
	self.machine = nil
end
return CombatController
