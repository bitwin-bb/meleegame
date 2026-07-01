
local require = require(script.Parent.loader).load(script)

local Nevermore = require("GoapNevermore")
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local CombatInputHandler = {}
CombatInputHandler.__index = CombatInputHandler

export type CombatInputHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		Queued: any,
		input: any?,
		queuedAttack: string?,
		blocking: boolean,
	},
	CombatInputHandler
))

function CombatInputHandler.new(inputHandler: any?): CombatInputHandler
	local self = setmetatable({
		maid = Maid.new(),
		Queued = Signal.new(),
		input = inputHandler,
		queuedAttack = nil,
		blocking = false,
	}, CombatInputHandler)

	self.maid:GiveTask(self.Queued)
	return self
end

function CombatInputHandler.QueueAttack(self: CombatInputHandler, attackNameRaw: any?)
	local attackName = if typeof(attackNameRaw) == "string" and attackNameRaw ~= "" then attackNameRaw else "Light"
	self.queuedAttack = attackName
	self.Queued:Fire(attackName)
end

function CombatInputHandler.GetQueuedAttack(self: CombatInputHandler): string?
	return self.queuedAttack
end

function CombatInputHandler.ConsumeAttack(self: CombatInputHandler): string?
	local attackName = self.queuedAttack
	self.queuedAttack = nil
	return attackName
end

function CombatInputHandler.SetBlocking(self: CombatInputHandler, blockingRaw: any)
	self.blocking = blockingRaw == true
end

function CombatInputHandler.IsBlocking(self: CombatInputHandler): boolean
	local input = self.input
	if input ~= nil and typeof(input.IsBlocking) == "function" then
		return input:IsBlocking()
	end
	return self.blocking
end

function CombatInputHandler.Destroy(self: CombatInputHandler)
	self.maid:DoCleaning()
	self.input = nil
	self.queuedAttack = nil
end
return CombatInputHandler
