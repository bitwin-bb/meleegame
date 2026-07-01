
local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Maid = Nevermore.Get("Maid")
local NativeStateStack = Nevermore.Get("StateStack")
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")

local StateStack = {}
StateStack.__index = StateStack

export type StateStack = typeof(setmetatable(
	{} :: {
		stack: { string },
		cleanups: { () -> () },
		native: any,
		maid: any,
		Changed: any,
	},
	StateStack
))

function StateStack.new(valuesRaw: { string }?): StateStack
	local self = setmetatable({
		stack = if typeof(valuesRaw) == "table" then Table.copy(valuesRaw) else {},
		cleanups = {},
		native = NativeStateStack.new(nil),
		maid = Maid.new(),
		Changed = Signal.new(),
	}, StateStack)

	self.maid:GiveTask(self.native)
	self.maid:GiveTask(self.Changed)

	for _, stateName in self.stack do
		table.insert(self.cleanups, self.native:PushState(stateName))
	end

	return self
end

function StateStack.Push(self: StateStack, stateNameRaw: any): boolean
	if typeof(stateNameRaw) ~= "string" or stateNameRaw == "" then
		return false
	end
	table.insert(self.stack, stateNameRaw)
	table.insert(self.cleanups, self.native:PushState(stateNameRaw))
	self.Changed:Fire(self:Peek(), self:GetSnapshot())
	return true
end

function StateStack.Pop(self: StateStack): string?
	if #self.stack <= 0 then
		return nil
	end
	local cleanup = table.remove(self.cleanups)
	if cleanup ~= nil then
		cleanup()
	end

	local stateName = table.remove(self.stack)
	self.Changed:Fire(self:Peek(), self:GetSnapshot())
	return stateName
end

function StateStack.Peek(self: StateStack): string?
	return self.stack[#self.stack]
end

function StateStack.Clear(self: StateStack)
	for index = #self.cleanups, 1, -1 do
		local cleanup = self.cleanups[index]
		cleanup()
		self.cleanups[index] = nil
	end
	table.clear(self.stack)
	self.Changed:Fire(nil, {})
end

function StateStack.GetSnapshot(self: StateStack): { string }
	return Table.copy(self.stack)
end

function StateStack.Observe(self: StateStack): any
	return self.native:Observe()
end

function StateStack.ObserveBrio(self: StateStack, predicate: ((any) -> boolean)?): any
	return self.native:ObserveBrio(predicate)
end

function StateStack.Destroy(self: StateStack)
	self:Clear()
	self.maid:DoCleaning()
end
return StateStack
